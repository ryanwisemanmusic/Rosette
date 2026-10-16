const std = @import("std");
const core = @import("core.zig");
const f = @import("tests.zig");
const t = std.testing;
const ops = [_]core.Op{ .shl_reg_imm, .shr_reg_imm, .sar_reg_imm, .rol_reg_imm, .ror_reg_imm, .not_reg64, .neg_reg64 };
fn allocate() !*f.TestState {
    const s = try t.allocator.create(f.TestState);
    s.* = .{};
    return s;
}
fn equal(a: *f.TestState, b: *f.TestState) !void {
    try t.expectEqualDeep(a.regs, b.regs);
    try t.expectEqualDeep(a.xmm, b.xmm);
    try t.expectEqualDeep(a.ymm_hi, b.ymm_hi);
    try t.expectEqualDeep(a.zmm_hi, b.zmm_hi);
    try t.expectEqualDeep(a.memory, b.memory);
    try t.expectEqual(a.interprets, b.interprets);
    try t.expectEqual(a.flags_at_interpret, b.flags_at_interpret);
}
fn form(op: core.Op, size: core.Size, count: u8, id: core.RegId) core.DecodedInsn {
    const actual: core.Op = if (op == .not_reg64) switch (size) {
        .bits8 => .not_reg8,
        .bits16 => .not_reg16,
        .bits32 => .not_reg32,
        else => .not_reg64,
    } else if (op == .neg_reg64) switch (size) {
        .bits8 => .neg_reg8,
        .bits16 => .neg_reg16,
        .bits32 => .neg_reg32,
        else => .neg_reg64,
    } else op;
    return .{ .op = actual, .size = size, .dst_reg = id, .imm = count };
}
fn oracle(value: u64, op: core.Op, size: core.Size, count: u8) u64 {
    const bits: u7 = if (size == .bits64) 64 else 32;
    const mask: u64 = if (bits == 64) std.math.maxInt(u64) else 0xFFFFFFFF;
    const n: u6 = @intCast(count & (bits - 1));
    const v = value & mask;
    if ((op == .rol_reg_imm or op == .ror_reg_imm) and n == 0) return value;
    return switch (op) {
        .shl_reg_imm => (v << n) & mask,
        .shr_reg_imm => v >> n,
        .sar_reg_imm => if (bits == 64) @bitCast(@as(i64, @bitCast(v)) >> n) else @as(u32, @bitCast(@as(i32, @bitCast(@as(u32, @truncate(v)))) >> @as(u5, @intCast(n)))),
        .rol_reg_imm => ((v << n) | (v >> @as(u6, @intCast(bits - n)))) & mask,
        .ror_reg_imm => ((v >> n) | (v << @as(u6, @intCast(bits - n)))) & mask,
        .not_reg64 => ~v & mask,
        .neg_reg64 => (0 -% v) & mask,
        else => unreachable,
    };
}
test "direct scalar paths preserve width counts flags observers and oracle results" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    var random = std.Random.DefaultPrng.init(0x5CA1A2);
    for (ops) |op| for ([_]core.Size{ .bits8, .bits16, .bits32, .bits64 }) |size| for ([_]u8{ 0, 1, 7, 31, 32, 63, 64, 255 }) |count| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        var rip: u64 = 0x1000;
        for (0..16) |_| {
            try h.add(rip, 4, form(op, size, count, .al_ax_eax_rax));
            rip += 4;
        }
        // This ordinary flag writer proves the preceding outputs dead.
        try h.add(rip, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .imm = 7 });
        rip += 4;
        _ = try h.run(a);
        const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .direct_scalar_paths = false });
        const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .direct_scalar_paths = true });
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = old.code;
        blocks[1].code = new.code;
        for (0..32) |_| {
            a.* = .{};
            const regs: *[16]u64 = @ptrCast(&a.regs);
            for (regs) |*r| r.* = random.random().int(u64);
            a.regs.rflags = random.random().int(u32) | 2;
            var expected = a.regs.rax;
            if (size == .bits32 or size == .bits64) for (0..16) |_| {
                expected = oracle(expected, op, size, count);
            };
            b.* = a.*;
            for (&blocks, [_]*f.TestState{ a, b }) |*block, s| {
                s.scratch.block = block;
                try t.expectEqual(@as(u32, 17), block.entry()(s, &block.helpers, &s.scratch));
            }
            try equal(a, b);
            if (size == .bits32 or size == .bits64) try t.expectEqual(expected, b.regs.rax);
        }
    };
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "direct scalar paths alternating complete block CPU comparisons" {
    const bench = std.c.getenv("ROSETTE_CHAIN_BENCH") != null;
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for (0..6) |profile| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        var rip: u64 = 0x1000;
        for (0..if (profile == 5) @as(usize, 1) else 64) |i| {
            const op = if (profile == 1) ops[3 + i % 2] else if (profile == 2) ops[5 + i % 2] else ops[i % 3];
            try h.add(rip, 4, form(op, if (profile == 4) .bits16 else if (profile == 1) .bits32 else .bits64, @intCast(1 + i % 6), @enumFromInt(i % (if (profile == 2) @as(usize, 9) else 4))));
            rip += 4;
            if (profile == 3) {
                try h.add(rip, 1, .{ .op = .nop });
                h.insns.items[h.insns.items.len - 1].force_fallback = true;
                rip += 1;
            }
        }
        try h.add(rip, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .imm = 7 });
        rip += 4;
        _ = try h.run(a);
        const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .direct_scalar_paths = false });
        const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .direct_scalar_paths = true });
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = old.code;
        blocks[1].code = new.code;
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                s.* = .{};
                const regs: *[16]u64 = @ptrCast(&s.regs);
                for (regs, 0..) |*r, i| r.* = 0xF123456789ABCDEF +% i;
                s.regs.rflags = 0xA57;
                const block = &blocks[@intFromBool(enabled)];
                const n: usize = if (bench) (if (profile == 5) @as(usize, 1000000) else 300000) else 16;
                s.scratch.block = block;
                var retired: u64 = 0;
                const start = cpu();
                for (0..n) |_| retired += block.entry()(s, &block.helpers, &s.scratch);
                const ns = cpu() - start;
                try t.expectEqual(@as(u64, n * h.insns.items.len), retired);
                if (bench) std.debug.print("scalar profile={d} pair={d} enabled={} entries={d} retired={d} cpu_ns={d} code_bytes={d}\n", .{ profile, pair, enabled, n, retired, ns, block.code.len * @sizeOf(u32) });
            }
            try equal(a, b);
        }
    }
}

test "direct scalar paths caller-saved caches and full-state observers retain liveness" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    var h = try f.TestHarness.init();
    defer h.deinit();
    var rip: u64 = 0x1000;
    for (0..36) |i| {
        try h.add(rip, 4, form(.not_reg64, .bits32, 1, @enumFromInt(i % 9)));
        rip += 4;
        try h.add(rip, 4, form(.shl_reg_imm, .bits64, 7, @enumFromInt(i % 9)));
        rip += 4;
        // Kills shift flags while retaining a complete interpreter boundary.
        try h.add(rip, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .r15b_r15w_r15d_r15, .imm = 3 });
        rip += 4;
        try h.add(rip, 1, .{ .op = .nop });
        h.insns.items[h.insns.items.len - 1].force_fallback = true;
        rip += 1;
    }
    _ = try h.run(a);
    const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .direct_scalar_paths = false });
    const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .direct_scalar_paths = true });
    try t.expect(new.direct_scalar_ops >= 60);
    var blocks = [_]core.Block{ h.block, h.block };
    blocks[0].code = old.code;
    blocks[1].code = new.code;
    var rng = std.Random.DefaultPrng.init(0xCACE5);
    for (0..128) |_| {
        a.* = .{};
        const regs: *[16]u64 = @ptrCast(&a.regs);
        for (regs) |*r| r.* = rng.random().int(u64);
        a.regs.rflags = rng.random().int(u32) | 2;
        a.poison_upper_on_interpret = true;
        b.* = a.*;
        for (&blocks, [_]*f.TestState{ a, b }) |*block, s| {
            s.scratch.block = block;
            try t.expectEqual(@as(u32, 144), block.entry()(s, &block.helpers, &s.scratch));
        }
        try equal(a, b);
    }
}
