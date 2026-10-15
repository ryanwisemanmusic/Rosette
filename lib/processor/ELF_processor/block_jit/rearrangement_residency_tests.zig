//! Differential native publication, aliasing and CPU-only throughput.
const core = @import("core.zig");
const f = @import("tests.zig");
const std = @import("std");
const t = std.testing;
const ops = [_]core.Op{ .vpshufb, .vpshufd, .vshufps, .vshufpd, .vpackssdw, .vpacksswb, .vpackuswb, .vpackusdw, .vpmaddwd, .vpmuludq, .vpblendw, .vinsertps };
fn instruction(op: core.Op, dst: u8, lhs: u8, rhs: u8, immediate: u64) core.DecodedInsn {
    return .{ .op = op, .is_reg_form = true, .uses_imm = true, .xmm_dst = dst, .xmm_src = lhs, .xmm_src2 = rhs, .imm = immediate };
}
fn state() !*f.TestState {
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
}
test "rearrangement residency matches eager state for aliases high registers all immediates" {
    var rng = std.Random.DefaultPrng.init(0xA22A);
    for (ops) |op| for ([_]u8{ 0, 1, 2, 15 }) |dst| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        const a = try state();
        defer t.allocator.destroy(a);
        const b = try state();
        defer t.allocator.destroy(b);
        for (0..16) |sample| {
            h.insns.clearRetainingCapacity();
            for (0..16) |n| try h.add(0x1000 + n * 5, 5, instruction(op, dst, if (n % 2 == 0) dst else 1, if (n % 3 == 0) dst else 2, sample * 16 + n));
            a.* = .{};
            rng.random().bytes(std.mem.asBytes(&a.xmm));
            rng.random().bytes(std.mem.asBytes(&a.ymm_hi));
            rng.random().bytes(std.mem.asBytes(&a.zmm_hi));
            a.regs = .{ .rflags = 0xA57, .mxcsr = 0x1F80 };
            b.* = a.*;
            try t.expectEqual(try h.runWith(a, .{ .rearrangement_residency = false }), try h.runWith(b, .{ .rearrangement_residency = true }));
            try equal(a, b);
            try t.expectEqual(@as(u32, 0), b.interprets);
        }
    };
}
test "rearrangement residency publishes at memory observer and forced helper boundaries" {
    for ([_]bool{ false, true }) |helper| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 5, instruction(.vpshufd, 0, 1, 1, 0x1B));
        if (helper) {
            try h.add(0x1005, 1, .{ .op = .nop });
            h.insns.items[1].force_fallback = true;
        } else try h.add(0x1005, 4, .{ .op = .vmovdqu_mem_xmm, .xmm_src = 0, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
        try h.add(0x1009, 5, instruction(.vpblendw, 15, 0, 1, 0xAA));
        const a = try state();
        defer t.allocator.destroy(a);
        const b = try state();
        defer t.allocator.destroy(b);
        a.regs.rbx = 0x100;
        for (&a.xmm[1], 0..) |*byte, i| byte.* = @intCast(i + 1);
        a.poison_upper_on_interpret = true;
        b.* = a.*;
        _ = try h.runWith(a, .{ .rearrangement_residency = false });
        _ = try h.runWith(b, .{ .rearrangement_residency = true });
        try equal(a, b);
        if (!helper) try t.expectEqualSlices(u8, &a.xmm[0], b.memory[0x100..][0..16]);
    }
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "rearrangement residency alternating CPU comparisons" {
    const bench = std.c.getenv("ROSETTE_THROUGHPUT_BENCH") != null;
    for ([_]bool{ false, true }) |mixed| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        for (0..96) |n| try h.add(0x1000 + n * 5, 5, instruction(if (mixed) ops[n % ops.len] else .vpshufb, @intCast(n % 8), @intCast(n % 8), 8, 0x1B));
        const a = try state();
        defer t.allocator.destroy(a);
        const b = try state();
        defer t.allocator.destroy(b);
        _ = try h.run(a);
        const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x11E0, .{ .rearrangement_residency = false });
        const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x11E0, .{ .rearrangement_residency = true });
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = old.code;
        blocks[1].code = new.code;
        for (0..if (bench) @as(usize, 7) else 1) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                s.* = .{};
                for (&s.xmm, 0..) |*reg, i| for (reg, 0..) |*byte, j| {
                    byte.* = @truncate(i * 17 + j * 7);
                };
                const block = &blocks[@intFromBool(enabled)];
                s.scratch.block = block;
                var retired: u64 = 0;
                const n: usize = if (bench) 100000 else 16;
                const start = cpu();
                for (0..n) |_| retired += block.entry()(s, &block.helpers, &s.scratch);
                const elapsed = cpu() - start;
                try t.expectEqual(@as(u64, n * 96), retired);
                if (bench) std.debug.print("throughput kind=rearrangement mixed={} pair={d} enabled={} operations={d} retired={d} cpu_ns={d} code_bytes={d}\n", .{ mixed, pair, enabled, n, retired, elapsed, if (enabled) new.code.len else old.code.len });
            }
            try equal(a, b);
        }
    }
}
