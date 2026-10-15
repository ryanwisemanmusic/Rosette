//! Differential publication and actual CPU work for scalar XMM residency.
const core = @import("core.zig");
const f = @import("tests.zig");
const std = @import("std");
const t = std.testing;
const ops = [_]core.Op{ .vaddss, .vsubss, .vmulss, .vdivss, .vminss, .vmaxss, .vaddsd, .vsubsd, .vmulsd, .vdivsd, .vminsd, .vmaxsd };
fn insn(op: core.Op, dst: u8, lhs: u8, rhs: u8) core.DecodedInsn {
    return .{ .op = op, .is_reg_form = true, .xmm_dst = dst, .xmm_src = lhs, .xmm_src2 = rhs };
}
test "scalar residency matches eager publication for aliases NaNs modes and upper state" {
    var random = std.Random.DefaultPrng.init(0x5CA1);
    for (ops) |op| for ([_]u8{ 0, 1, 2, 15 }) |dst| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        for (0..12) |n| try h.add(0x1000 + n * 4, 4, insn(op, dst, if (n % 2 == 0) dst else 1, 2));
        for (0..8) |mode| for (0..8) |sample| {
            const a = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(a);
            const b = try t.allocator.create(f.TestState);
            defer t.allocator.destroy(b);
            a.* = .{};
            random.random().bytes(std.mem.asBytes(&a.xmm));
            random.random().bytes(std.mem.asBytes(&a.ymm_hi));
            random.random().bytes(std.mem.asBytes(&a.zmm_hi));
            a.regs = .{ .rflags = 0xA57, .mxcsr = @intCast(0x1F80 | ((mode & 3) << 13) | ((mode >> 2) << 15)) };
            if (sample == 0) {
                std.mem.writeInt(u64, a.xmm[2][0..8], 0x8000000000000000, .little);
                std.mem.writeInt(u64, a.xmm[1][0..8], 0x7FF80000ABCDEF00, .little);
            }
            b.* = a.*;
            const before = try h.runWith(a, .{ .scalar_residency = false });
            const after = try h.runWith(b, .{ .scalar_residency = true });
            try t.expectEqual(before, after);
            try t.expectEqual(a.regs, b.regs);
            try t.expectEqual(a.xmm, b.xmm);
            try t.expectEqual(a.ymm_hi, b.ymm_hi);
            try t.expectEqual(a.zmm_hi, b.zmm_hi);
            try t.expectEqual(@as(u32, 0), b.interprets);
        };
    };
}
test "scalar residency publishes before observers and memory keeps scalar width" {
    for ([_]bool{ false, true }) |enabled| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 4, insn(.vaddss, 0, 0, 1));
        try h.add(0x1004, 4, .{ .op = .vmovss_mem_xmm, .xmm_src = 0, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
        try h.add(0x1008, 4, .{ .op = .vaddss, .xmm_dst = 2, .xmm_src = 0, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
        const s = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(s);
        s.* = .{};
        s.regs.rbx = 0x100;
        std.mem.writeInt(u32, s.xmm[0][0..4], @bitCast(@as(f32, 2)), .little);
        std.mem.writeInt(u32, s.xmm[1][0..4], @bitCast(@as(f32, 3)), .little);
        _ = try h.runWith(s, .{ .scalar_residency = enabled });
        try t.expectEqual(@as(u32, @bitCast(@as(f32, 5))), std.mem.readInt(u32, s.memory[0x100..][0..4], .little));
        try t.expectEqual(@as(u32, @bitCast(@as(f32, 10))), std.mem.readInt(u32, s.xmm[2][0..4], .little));
        try t.expectEqual(@as(u32, 2), s.reads + s.writes);
    }
}
fn cpu() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
test "scalar residency alternating CPU comparison (ROSETTE_CRITICAL_CPU_BENCH=1)" {
    if (std.c.getenv("ROSETTE_CRITICAL_CPU_BENCH") == null) return error.SkipZigTest;
    for ([_]bool{ false, true }) |independent| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        for (0..96) |n| try h.add(0x1000 + n * 4, 4, insn(if (independent) .vaddsd else .vaddss, if (independent) @intCast(n % 8) else 0, if (independent) @intCast(n % 8) else 0, 8));
        const a = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(a);
        const b = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(b);
        a.* = .{};
        b.* = .{};
        _ = try h.run(a);
        const old = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x1180, .{ .scalar_residency = false });
        const new = try core.compileWith(t.allocator, &h.memory, f.TestState.layout, h.insns.items, 0x1180, .{ .scalar_residency = true });
        try t.expectEqual(@as(u32, 0), old.scalar_resident_ops);
        try t.expectEqual(@as(u32, 96), new.scalar_resident_ops);
        var blocks = [_]core.Block{ h.block, h.block };
        blocks[0].code = old.code;
        blocks[1].code = new.code;
        for (0..7) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |enabled| {
                const s = if (enabled) b else a;
                s.* = .{};
                if (independent) std.mem.writeInt(u64, s.xmm[8][0..8], @bitCast(@as(f64, 1)), .little) else std.mem.writeInt(u32, s.xmm[8][0..4], @bitCast(@as(f32, 1)), .little);
                const block = &blocks[@intFromBool(enabled)];
                s.scratch.block = block;
                var retired: u64 = 0;
                const start = cpu();
                for (0..100000) |_| retired += block.entry()(s, &block.helpers, &s.scratch);
                const duration = cpu() - start;
                try t.expectEqual(@as(u64, 9600000), retired);
                std.debug.print("critical_cpu kind=scalar pair={d} independent={} enabled={} operations={d} retired={d} cpu_ns={d} code_bytes={d} forwarded_loads={d} elided_stores={d}\n", .{ pair, independent, enabled, retired, retired, duration, if (enabled) new.code.len else old.code.len, if (enabled) new.xmm_loads_forwarded else old.xmm_loads_forwarded, if (enabled) new.xmm_stores_elided else old.xmm_stores_elided });
            }
            try t.expectEqual(a.regs, b.regs);
            try t.expectEqual(a.xmm, b.xmm);
            try t.expectEqual(a.ymm_hi, b.ymm_hi);
            try t.expectEqual(a.zmm_hi, b.zmm_hi);
        }
    }
}
