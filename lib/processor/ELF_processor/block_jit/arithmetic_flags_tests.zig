const core = @import("core.zig");
const f = @import("tests.zig");
const std = @import("std");
const t = std.testing;
const decoder = core._test_api._x64_decoder;

fn equal(a: *f.TestState, b: *f.TestState) !void {
    try t.expectEqualDeep(a.regs, b.regs);
    try t.expectEqualDeep(a.xmm, b.xmm);
    try t.expectEqualDeep(a.memory, b.memory);
    try t.expectEqual(a.interprets, b.interprets);
}
fn state() !*f.TestState {
    const s = try t.allocator.create(f.TestState);
    s.* = .{};
    return s;
}
const forms = [_]core.Op{ .add_reg32_reg32, .add_reg64_reg64, .sub_reg32_reg32, .sub_reg64_reg64, .cmp_reg32_reg32, .cmp_reg64_reg64 };
fn insn(op: core.Op, dst: core.RegId, src: core.RegId) core.DecodedInsn {
    return .{ .op = op, .size = if (op == .add_reg32_reg32 or op == .sub_reg32_reg32 or op == .cmp_reg32_reg32) .bits32 else .bits64, .dst_reg = dst, .src_reg = src };
}
test "arithmetic throughput agrees with decoder oracle for edge random aliases and untouched flags" {
    const values = [_]u64{ 0, 1, 15, 16, 127, 128, 255, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF };
    var rng = std.Random.DefaultPrng.init(0xADDF1A6);
    const a = try state();
    defer t.allocator.destroy(a);
    const b = try state();
    defer t.allocator.destroy(b);
    for (forms) |op| for ([_]bool{ false, true }) |alias| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        const d = insn(op, .al_ax_eax_rax, if (alias) .al_ax_eax_rax else .bl_bx_ebx_rbx);
        try h.add(0x1000, 3, d);
        _ = try h.run(a);
        const before = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x1003, .{ .arithmetic_flags = false, .exact_exit_flags = true });
        const after = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x1003, .{ .arithmetic_flags = true, .exact_exit_flags = true });
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = before.code;
        blocks[1].code = after.code;
        for (0..512) |n| {
            a.* = .{};
            a.regs.rax = if (n < values.len * values.len) values[n / values.len] else rng.random().int(u64);
            a.regs.rbx = if (n < values.len * values.len) values[n % values.len] else rng.random().int(u64);
            a.regs.rflags = rng.random().int(u32) | 2;
            const mask: u64 = if (d.size == .bits32) 0xFFFFFFFF else std.math.maxInt(u64);
            const lhs = a.regs.rax & mask;
            const rhs = (if (alias) a.regs.rax else a.regs.rbx) & mask;
            const add = op == .add_reg32_reg32 or op == .add_reg64_reg64;
            const result = (if (add) lhs +% rhs else lhs -% rhs) & mask;
            var flags = a.regs.rflags;
            if (add) decoder.applyAdd(&flags, lhs, rhs, result, d.size) else decoder.applySub(&flags, lhs, rhs, result, d.size);
            b.* = a.*;
            for (&blocks, [_]*f.TestState{ a, b }) |*block, s| {
                s.scratch.block = block;
                try t.expectEqual(@as(u64, 1), block.entry()(s, &block.helpers, &s.scratch));
            }
            try equal(a, b);
            try t.expectEqual(flags, b.regs.rflags);
        }
    };
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "arithmetic throughput alternating full block CPU comparison" {
    const bench = std.c.getenv("ROSETTE_ARITHMETIC_BENCH") != null;
    for (0..4) |profile| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        const a = try state();
        defer t.allocator.destroy(a);
        const b = try state();
        defer t.allocator.destroy(b);
        var rip: u64 = 0x1000;
        // Preserve each writer's flags with an observer helper in profile 0;
        // profiles 1/2 use carry readers so flags remain useful within a block.
        for (0..if (profile == 3) @as(usize, 1) else 32) |n| {
            try h.add(rip, 3, insn(forms[(n % 2) * 2 + (if (profile == 2) @as(usize, 0) else 1)], @enumFromInt(n % 8), @enumFromInt(8 + n % 8)));
            rip += 3;
            if (profile == 0) {
                try h.add(rip, 1, .{ .op = .nop });
                h.insns.items[h.insns.items.len - 1].force_fallback = true;
                rip += 1;
            } else if (profile != 3) {
                try h.add(rip, 3, .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .ch_bp_ebp_rbp, .cond = if (n % 2 == 0) .o else .be });
                rip += 3;
            }
        }
        _ = try h.run(a);
        const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .arithmetic_flags = false });
        const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, rip, .{ .arithmetic_flags = true });
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = old.code;
        blocks[1].code = new.code;
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                s.* = .{};
                const regs: *[16]u64 = @ptrCast(&s.regs);
                for (regs, 0..) |*r, i| r.* = 0x7FFFFFF0 + i * 0xFFFF0000;
                const block = &blocks[@intFromBool(enabled)];
                s.scratch.block = block;
                const count: usize = if (bench) 100000 else 16;
                var retired: u64 = 0;
                const start = cpu();
                for (0..count) |_| retired += block.entry()(s, &block.helpers, &s.scratch);
                const ns = cpu() - start;
                try t.expectEqual(@as(u64, count * (if (profile == 3) @as(usize, 1) else 64)), retired);
                if (bench) std.debug.print("arithmetic profile={d} pair={d} enabled={} operations={d} retired={d} cpu_ns={d} code_bytes={d}\n", .{ profile, pair, enabled, count, retired, ns, block.code.len * @sizeOf(u32) });
            }
            try equal(a, b);
        }
    }
}

test {
    _ = @import("natural_scalar_lanes_tests.zig");
    _ = @import("chain_layout_tests.zig");
    _ = @import("scalar_register_path_tests.zig");
}
