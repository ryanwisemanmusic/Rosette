const std = @import("std");
const core = @import("core.zig");
const f = @import("tests.zig");
const t = std.testing;
const shifts = [_]core.Op{ .shl_reg_cl, .shr_reg_cl, .sar_reg_cl, .rol_reg_cl, .ror_reg_cl };
const Program = struct {
    h: f.TestHarness,
    blocks: [2]core.Block,
    counts: [3]u32,
    fn create(d: core.DecodedInsn, repeats: usize, observe: bool, pointers: bool) !*@This() {
        return createSequence(&.{d}, repeats, observe, pointers);
    }
    fn createSequence(sequence: []const core.DecodedInsn, repeats: usize, observe: bool, pointers: bool) !*@This() {
        const p = try t.allocator.create(@This());
        errdefer t.allocator.destroy(p);
        p.h = try f.TestHarness.init();
        errdefer p.h.deinit();
        var rip: u64 = 0x1000;
        for (0..repeats) |_| for (sequence) |d| {
            try p.h.add(rip, 4, d);
            rip += 4;
            if (observe) {
                try p.h.add(rip, 1, .{ .op = .nop });
                p.h.insns.items[p.h.insns.items.len - 1].force_fallback = true;
                rip += 1;
            }
        };
        try p.h.add(rip, 4, .{ .op = .add_reg64_imm32, .size = .bits64, .dst_reg = .r15b_r15w_r15d_r15, .imm = 7 });
        rip += 4;
        const warm = try allocate();
        defer t.allocator.destroy(warm);
        _ = try p.h.run(warm);
        var layout = f.TestState.layout;
        if (pointers) layout.register_files = .pointers_in_scratch;
        for (0..2) |mode| {
            const c = try core.compileWith(t.allocator, &p.h.memory, layout, p.h.insns.items, rip, .{ .direct_register_operands = mode == 1 });
            p.blocks[mode] = p.h.block;
            p.blocks[mode].code = c.code;
            if (mode == 1) p.counts = c.direct_operand_ops;
        }
        return p;
    }
    fn destroy(p: *@This()) void {
        p.h.deinit();
        t.allocator.destroy(p);
    }
    fn run(p: *@This(), enabled: bool, s: *f.TestState) u32 {
        s.scratch.regs_file = @intFromPtr(&s.regs);
        s.scratch.xmm_file = @intFromPtr(&s.xmm);
        s.scratch.ymm_hi_file = @intFromPtr(&s.ymm_hi);
        s.scratch.zmm_hi_file = @intFromPtr(&s.zmm_hi);
        s.scratch.tlb_file = @intFromPtr(&s.tlb);
        const b = &p.blocks[@intFromBool(enabled)];
        s.scratch.block = b;
        return b.entry()(s, &b.helpers, &s.scratch);
    }
};
fn allocate() !*f.TestState {
    const s = try t.allocator.create(f.TestState);
    s.* = .{};
    return s;
}
fn same(a: *f.TestState, b: *f.TestState) !void {
    try t.expectEqualDeep(a.regs, b.regs);
    try t.expectEqualDeep(a.xmm, b.xmm);
    try t.expectEqualDeep(a.ymm_hi, b.ymm_hi);
    try t.expectEqualDeep(a.zmm_hi, b.zmm_hi);
    try t.expectEqualDeep(a.memory, b.memory);
    try t.expectEqual(a.reads, b.reads);
    try t.expectEqual(a.writes, b.writes);
    try t.expectEqual(a.interprets, b.interprets);
    try t.expectEqual(a.flags_at_interpret, b.flags_at_interpret);
    try t.expectEqual(a.scratch.abort, b.scratch.abort);
}
fn seed(s: *f.TestState, value: u64, count: u64) void {
    s.* = .{};
    const regs: *[16]u64 = @ptrCast(&s.regs);
    for (regs, 0..) |*r, i| r.* = value +% i;
    s.regs.rax = value;
    s.regs.rcx = count;
    s.regs.rflags = 0xA57;
    s.poison_upper_on_interpret = true;
}
fn shifted(value: u64, op: core.Op, wide: bool, count: u64) u64 {
    const bits: u7 = if (wide) 64 else 32;
    const n: u6 = @intCast(count & (bits - 1));
    const v = if (wide) value else value & 0xFFFFFFFF;
    if (n == 0 and (op == .rol_reg_cl or op == .ror_reg_cl)) return value;
    const result = switch (op) {
        .shl_reg_cl => v << n,
        .shr_reg_cl => v >> n,
        .sar_reg_cl => if (wide) @as(u64, @bitCast(@as(i64, @bitCast(v)) >> n)) else @as(u64, @as(u32, @bitCast(@as(i32, @bitCast(@as(u32, @truncate(v)))) >> @as(u5, @intCast(n))))),
        .rol_reg_cl => (v << n) | (v >> @as(u6, @intCast(bits - n))),
        .ror_reg_cl => (v >> n) | (v << @as(u6, @intCast(bits - n))),
        else => unreachable,
    };
    return if (wide) result else result & 0xFFFFFFFF;
}
test "register operands variable count aliases zero counts live flags and private layouts" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    var rng = std.Random.DefaultPrng.init(0xC011A5);
    for (shifts) |op| for ([_]bool{ false, true }) |wide| for ([_]bool{ false, true }) |alias| for ([_]bool{ false, true }) |observe| {
        const p = try Program.create(.{ .op = op, .size = if (wide) .bits64 else .bits32, .dst_reg = if (alias) .cl_cx_ecx_rcx else .al_ax_eax_rax }, 16, observe, alias);
        defer p.destroy();
        if (!observe) try t.expect(p.counts[0] != 0);
        for (0..256) |i| {
            const count: u64 = if (i < 128) i else rng.random().int(u64);
            seed(a, rng.random().int(u64), count);
            b.* = a.*;
            var value = if (alias) a.regs.rcx else a.regs.rax;
            for (0..16) |_| value = shifted(value, op, wide, if (alias) value else count);
            try t.expectEqual(p.run(false, a), p.run(true, b));
            try same(a, b);
            try t.expectEqual(value, if (alias) b.regs.rcx else b.regs.rax);
        }
    };
}
test "register operands conversion and product aliases agree with independent values" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    const forms = [_]core.Op{ .movzx_reg32_mem8, .movzx_reg32_mem16, .movsx_reg32_mem8, .movsx_reg32_mem16, .movsxd_reg64_reg32, .cdqe, .cdq, .cqo, .imul_reg32_reg32, .imul_reg64_reg64 };
    var rng = std.Random.DefaultPrng.init(0xC0A1E27);
    for (forms) |op| for ([_]bool{ false, true }) |wide| for ([_]bool{ false, true }) |alias| for ([_]bool{ false, true }) |high| {
        const size: core.Size = if (wide) .bits64 else .bits32;
        const p = try Program.create(.{ .op = op, .size = size, .dst_reg = .al_ax_eax_rax, .src_reg = if (alias) .al_ax_eax_rax else .bl_bx_ebx_rbx, .is_reg_form = true, .src_high8 = high }, 16, false, wide);
        defer p.destroy();
        try t.expect(p.counts[1] + p.counts[2] != 0);
        for (0..64) |_| {
            const v = rng.random().int(u64);
            const rhs = rng.random().int(u64);
            seed(a, v, 0xAB);
            a.regs.rbx = rhs;
            b.* = a.*;
            var expected = v;
            for (0..16) |_| {
                const src = if (op == .cdq or op == .cqo or op == .cdqe) expected else if (alias) expected else rhs;
                const byte: u8 = @truncate(src >> @as(u6, if (high) 8 else 0));
                expected = switch (op) {
                    .movzx_reg32_mem8 => byte,
                    .movzx_reg32_mem16 => src & 0xFFFF,
                    .movsx_reg32_mem8 => @bitCast(@as(i64, @as(i8, @bitCast(byte)))),
                    .movsx_reg32_mem16 => @bitCast(@as(i64, @as(i16, @bitCast(@as(u16, @truncate(src)))))),
                    .movsxd_reg64_reg32, .cdqe => @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(src)))))),
                    .cdq, .cqo => expected,
                    else => expected *% src,
                };
                if ((!wide and (op == .movsx_reg32_mem8 or op == .movsx_reg32_mem16)) or op == .imul_reg32_reg32) expected &= 0xFFFFFFFF;
            }
            try t.expectEqual(p.run(false, a), p.run(true, b));
            try same(a, b);
            if (op == .cdq) try t.expectEqual(if (v & 0x80000000 != 0) @as(u64, 0xFFFFFFFF) else 0, b.regs.rdx) else if (op == .cqo) try t.expectEqual(if (v >> 63 != 0) @as(u64, std.math.maxInt(u64)) else 0, b.regs.rdx) else try t.expectEqual(expected, b.regs.rax);
        }
    };
}
test "register operands endian loads retain admission abort alias and byte order" {
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for ([_]core.Size{ .bits32, .bits64 }) |size| for ([_]bool{ false, true }) |alias| for (0..5) |route| {
        const p = try Program.create(.{ .op = .movbe_reg_mem, .size = size, .dst_reg = .al_ax_eax_rax, .sib_has_base = true, .sib_base_reg = if (alias) .al_ax_eax_rax else .dh_si_esi_rsi }, if (alias) 1 else 16, false, true);
        defer p.destroy();

        for ([_]u64{ 128, 129, 130, 132, 4090, 4092, 4095 }) |address| {
            seed(a, address, 17);
            a.regs.rsi = address;
            for (&a.memory, 0..) |*byte, i| byte.* = @truncate(i *% 37 +% 13);
            b.* = a.*;
            a.tlb = core.Tlb.empty;
            b.tlb = core.Tlb.empty;
            if (route == 0 or route == 4) {
                a.admitMemory(true, false);
                b.admitMemory(true, false);
            }
            if (route == 2) {
                a.abort_on_access = true;
                b.abort_on_access = true;
            }
            if (route == 3) {
                a.scratch.chain_break = 1;
                b.scratch.chain_break = 1;
            }
            try t.expectEqual(p.run(false, a), p.run(true, b));
            try same(a, b);
            const bytes: usize = if (size == .bits64) 8 else 4;
            if (address + bytes <= a.memory.len) {
                const start: usize = @intCast(address);
                const value: u64 = if (size == .bits64) std.mem.readInt(u64, a.memory[start..][0..8], .big) else std.mem.readInt(u32, a.memory[start..][0..4], .big);
                try t.expectEqual(value, b.regs.rax);
            }
        }
    };
}

test "register operands endian destination base invalidates hoisted address after every load" {
    const p = try Program.create(.{ .op = .movbe_reg_mem, .size = .bits64, .dst_reg = .al_ax_eax_rax, .sib_has_base = true, .sib_base_reg = .al_ax_eax_rax }, 9, false, true);
    defer p.destroy();

    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for (0..16) |i| {
        seed(a, 128, i);
        std.mem.writeInt(u64, a.memory[128..136], 256, .big);
        std.mem.writeInt(u64, a.memory[256..264], 128, .big);
        b.* = a.*;
        if (i % 2 == 0) {
            a.admitMemory(true, false);
            b.admitMemory(true, false);
        }
        try t.expectEqual(@as(u32, 10), p.run(false, a));
        try t.expectEqual(@as(u32, 10), p.run(true, b));
        try same(a, b);
        try t.expectEqual(@as(u64, 256), b.regs.rax);
    }
}

fn mixed(i: usize) core.DecodedInsn {
    return switch (i % 8) {
        0 => .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .al_ax_eax_rax },
        1 => .{ .op = .ror_reg_cl, .size = .bits32, .dst_reg = .dl_dx_edx_rdx },
        2 => .{ .op = .movsx_reg32_mem8, .size = .bits64, .dst_reg = .r8b_r8w_r8d_r8, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true, .src_high8 = true },
        3 => .{ .op = .movsxd_reg64_reg32, .size = .bits64, .dst_reg = .r9b_r9w_r9d_r9, .src_reg = .al_ax_eax_rax, .is_reg_form = true },
        4 => .{ .op = .imul_reg64_reg64, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .src_reg = .dl_dx_edx_rdx },
        5 => .{ .op = .movbe_reg_mem, .size = .bits64, .dst_reg = .r10b_r10w_r10d_r10, .sib_has_base = true, .sib_base_reg = .dh_si_esi_rsi },
        6 => .{ .op = .mov_reg64_reg64, .size = .bits64, .dst_reg = .r11b_r11w_r11d_r11, .src_reg = .r10b_r10w_r10d_r10 },
        else => .{ .op = .shr_reg_cl, .size = .bits64, .dst_reg = .r11b_r11w_r11d_r11 },
    };
}
fn prepare(s: *f.TestState, n: u64, admitted: bool) void {
    seed(s, 0xFABCD98765432100 +% n, 5 + n % 59);
    s.regs.rsi = 128;
    for (&s.memory, 0..) |*byte, i| byte.* = @truncate(i *% 37 +% 13);
    if (admitted) s.admitMemory(true, false);
}
const Worker = struct {
    p: *Program,
    a: *f.TestState,
    b: *f.TestState,
    n: usize,
    fn run(w: *@This()) void {
        for (0..256) |i| {
            prepare(w.a, w.n * 256 + i, true);
            prepare(w.b, w.n * 256 + i, true);
            std.debug.assert(w.p.run(false, w.a) == w.p.run(true, w.b));
            same(w.a, w.b) catch @panic("private register cache state diverged");
        }
    }
};
test "register operands mixed register pressure helpers and four private host contexts" {
    var sequence: [8]core.DecodedInsn = undefined;
    for (&sequence, 0..) |*d, i| d.* = mixed(i);
    for ([_]bool{ false, true }) |observe| {
        const p = try Program.createSequence(&sequence, 8, observe, true);
        defer p.destroy();
        if (!observe) for (p.counts) |n| try t.expect(n != 0);
        var workers: [4]Worker = undefined;
        for (&workers, 0..) |*w, n| w.* = .{ .p = p, .a = try allocate(), .b = try allocate(), .n = n };
        defer for (workers) |w| {
            t.allocator.destroy(w.a);
            t.allocator.destroy(w.b);
        };
        var threads: [4]std.Thread = undefined;
        for (&threads, &workers) |*thread, *w| thread.* = try std.Thread.spawn(.{}, Worker.run, .{w});
        for (threads) |thread| thread.join();
    }
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "register operands alternating complete block CPU comparisons" {
    const bench = std.c.getenv("ROSETTE_OPERAND_BENCH") != null;
    const a = try allocate();
    defer t.allocator.destroy(a);
    const b = try allocate();
    defer t.allocator.destroy(b);
    for (0..11) |profile| {
        var sequence: [8]core.DecodedInsn = undefined;
        if (profile == 6) {
            for (&sequence, 0..) |*d, i| d.* = mixed(i);
        } else {
            sequence[0] = switch (profile) {
                0, 7, 8 => .{ .op = .shl_reg_cl, .size = if (profile == 8) .bits16 else .bits64, .dst_reg = .al_ax_eax_rax },
                1 => .{ .op = .ror_reg_cl, .size = .bits32, .dst_reg = .al_ax_eax_rax },
                2, 9 => .{ .op = .movsx_reg32_mem8, .size = .bits64, .dst_reg = .al_ax_eax_rax, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true, .src_high8 = true },
                3 => .{ .op = .movsxd_reg64_reg32, .size = .bits64, .dst_reg = .al_ax_eax_rax, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true },
                4 => .{ .op = .imul_reg64_reg64, .size = .bits64, .dst_reg = .al_ax_eax_rax, .src_reg = .bl_bx_ebx_rbx },
                else => .{ .op = .movbe_reg_mem, .size = .bits64, .dst_reg = .al_ax_eax_rax, .sib_has_base = true, .sib_base_reg = .dh_si_esi_rsi },
            };
        }
        const p = try Program.createSequence(sequence[0..if (profile == 6) 8 else 1], if (profile == 6) 8 else if (profile == 9) 1 else 64, profile == 7, true);
        defer p.destroy();
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                prepare(s, 0, profile != 10);
                // Resolve all private scratch pointers before the timed span.
                _ = p.run(enabled, s);
                const count: usize = if (bench) (if (profile == 9) @as(usize, 1000000) else 300000) else 16;
                const block = &p.blocks[@intFromBool(enabled)];
                var retired: u64 = 0;
                const start = cpu();
                for (0..count) |_| retired += block.entry()(s, &block.helpers, &s.scratch);
                const ns = cpu() - start;
                try t.expectEqual(@as(u64, count * p.h.insns.items.len), retired);
                if (bench) std.debug.print("operands profile={d} pair={d} enabled={} entries={d} retired={d} cpu_ns={d} code_bytes={d}\n", .{ profile, pair, enabled, count, retired, ns, block.code.len * 4 });
            }
            try same(a, b);
        }
    }
}
