//! Guard and edge proofs for the newly native completion templates.
const core = @import("core.zig");
const f = @import("tests.zig");
const std = @import("std");
const t = std.testing;
test "native completion packed madd checks aliased registers memory and modulo overflow" {
    var random = std.Random.DefaultPrng.init(0x5A77);
    for ([_]bool{ true, false }) |register| for ([_]u8{ 0, 1, 2, 15 }) |dst| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 4, .{ .op = .vpmaddwd, .is_reg_form = register, .xmm_dst = dst, .xmm_src = 1, .xmm_src2 = 2, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
        const s = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(s);
        for (0..64) |sample| {
            s.* = .{};
            s.regs = .{ .rbx = 0x100, .rflags = 0xA57 };
            random.random().bytes(&s.xmm[1]);
            random.random().bytes(&s.xmm[2]);
            s.ymm_hi[dst] = @splat(0xA5);
            s.zmm_hi[dst] = @splat(0xC7);
            if (sample == 0) for (0..8) |word| {
                std.mem.writeInt(u16, s.xmm[1][word * 2 ..][0..2], 0x8000, .little);
                std.mem.writeInt(u16, s.xmm[2][word * 2 ..][0..2], 0x8000, .little);
            };
            @memcpy(s.memory[0x100..][0..16], &s.xmm[2]);
            var expected: [16]u8 = undefined;
            for (0..4) |lane| {
                const n = lane * 4;
                const a: i64 = std.mem.readInt(i16, s.xmm[1][n..][0..2], .little);
                const b: i64 = std.mem.readInt(i16, s.xmm[2][n..][0..2], .little);
                const c: i64 = std.mem.readInt(i16, s.xmm[1][n + 2 ..][0..2], .little);
                const d: i64 = std.mem.readInt(i16, s.xmm[2][n + 2 ..][0..2], .little);
                std.mem.writeInt(i32, expected[n..][0..4], @truncate(a * b + c * d), .little);
            }
            if (sample % 2 == 0) s.admitMemory(true, true);
            _ = try h.run(s);
            try t.expectEqual(expected, s.xmm[dst]);
            try t.expectEqual(@as([16]u8, @splat(0)), s.ymm_hi[dst]);
            try t.expectEqual(@as([32]u8, @splat(0)), s.zmm_hi[dst]);
            try t.expectEqual(@as(u64, 0xA57), s.regs.rflags);
            try t.expectEqual(@as(u32, 0), s.interprets);
        }
    };
}
test "native completion CWDE exhausts AX and preserves flags without helpers" {
    var h = try f.TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 1, .{ .op = .cwde, .size = .bits32 });
    const s = try t.allocator.create(f.TestState);
    defer t.allocator.destroy(s);
    s.* = .{};
    _ = try h.run(s);
    for (0..65536) |ax| {
        s.regs = .{ .rax = 0xABCDEF9876540000 | ax, .rflags = 0xA57 };
        try t.expectEqual(@as(u32, 1), h.block.entry()(s, &h.block.helpers, &s.scratch));
        const expected: u32 = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @intCast(ax))))));
        try t.expectEqual(@as(u64, expected), s.regs.rax);
        try t.expectEqual(@as(u64, 0xA57), s.regs.rflags);
    }
    try t.expectEqual(@as(u32, 0), s.interprets);
}
fn div() core.DecodedInsn {
    return .{ .op = .div_mem32, .size = .bits32, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}
test "native completion memory divide guards retain the interpreter for zero and high half" {
    var h = try f.TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 2, div());
    for ([_]u32{ 0, 1, 7, 0xFFFFFFFF }) |divisor| for ([_]u32{ 0, 1, 0xFFFFFFFF }) |high| {
        const s = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(s);
        s.* = .{};
        s.regs = .{ .rbx = 0x100, .rax = 0xFFFFFFFF, .rdx = high, .rflags = 0xA57 };
        std.mem.writeInt(u32, s.memory[0x100..][0..4], divisor, .little);
        s.admitMemory(true, true);
        _ = try h.run(s);
        if (divisor == 0 or high != 0) {
            try t.expectEqual(@as(u32, 1), s.interprets);
            try t.expectEqual(@as(u64, 0xFFFFFFFF), s.regs.rax);
            try t.expectEqual(@as(u64, high), s.regs.rdx);
        } else {
            try t.expectEqual(@as(u32, 0), s.interprets);
            try t.expectEqual(@as(u64, 0xFFFFFFFF / divisor), s.regs.rax);
            try t.expectEqual(@as(u64, 0xFFFFFFFF % divisor), s.regs.rdx);
        }
        try t.expectEqual(@as(u64, 0xA57), s.regs.rflags);
    };
}
test "native completion MOVAPS cold page and crossing retain the guarded vector helper" {
    for ([_]core.Op{ .movaps_xmm_mem, .movaps_mem_xmm }) |op| for ([_]u64{ 0x100, 4090 }) |address| {
        var h = try f.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 3, .{ .op = op, .legacy_sse = true, .xmm_dst = 5, .xmm_src = 5, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
        const s = try t.allocator.create(f.TestState);
        defer t.allocator.destroy(s);
        s.* = .{};
        s.regs.rbx = address;
        s.xmm[5] = @splat(0x7B);
        s.ymm_hi[5] = @splat(0xA5);
        s.zmm_hi[5] = @splat(0xC7);
        if (address != 0x100) s.admitMemory(true, true);
        _ = try h.run(s);
        try t.expectEqual(@as(u32, 0), s.interprets);
        try t.expectEqual(@as(u32, 1), if (op == .movaps_xmm_mem) s.reads else s.writes);
        try t.expectEqual(@as([16]u8, @splat(0xA5)), s.ymm_hi[5]);
        try t.expectEqual(@as([32]u8, @splat(0xC7)), s.zmm_hi[5]);
    };
}
