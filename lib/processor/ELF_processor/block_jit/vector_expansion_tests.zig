const std = @import("std");
const core = @import("core.zig");
const harness = @import("tests.zig");
const permute = @import("vector_permute.zig");
const testing = std.testing;

test "compact permutation selects whole dwords for all control bits and aliases" {
    var random = std.Random.DefaultPrng.init(0xB17C0DE);
    for ([_]bool{ false, true }) |wide| for ([_]u8{ 0, 1, 2, 15 }) |dst| {
        var h = try harness.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 5, .{ .op = .vpermilps, .vector_256 = wide, .xmm_dst = dst, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = true });
        for (0..64) |_| {
            var state = harness.TestState{};
            random.random().bytes(std.mem.asBytes(&state.xmm));
            random.random().bytes(std.mem.asBytes(&state.ymm_hi));
            random.random().bytes(std.mem.asBytes(&state.zmm_hi));
            const low = state.xmm;
            const high = state.ymm_hi;
            const zmm = state.zmm_hi;
            state.regs.rflags = 0x246;
            _ = try h.run(&state);
            for (0..2) |half| {
                const source = if (half == 0) low[1] else high[1];
                const controls = if (half == 0) low[2] else high[2];
                const result = if (half == 0) state.xmm[dst] else state.ymm_hi[dst];
                for (0..4) |lane| {
                    const select = std.mem.readInt(u32, controls[lane * 4 ..][0..4], .little) & 3;
                    if (half == 0 or wide) {
                        try testing.expectEqualSlices(u8, source[select * 4 ..][0..4], result[lane * 4 ..][0..4]);
                    } else try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, result[lane * 4 ..][0..4]);
                }
            }
            for (0..32) |reg| if (reg != dst) {
                try testing.expectEqualSlices(u8, &low[reg], &state.xmm[reg]);
                try testing.expectEqualSlices(u8, &high[reg], &state.ymm_hi[reg]);
            };
            try testing.expectEqualDeep(zmm, state.zmm_hi);
            try testing.expectEqual(@as(u64, 0x246), state.regs.rflags);
            try testing.expectEqual(@as(u32, 0), h.block.fallback_count);
        }
    };
}

test "YMM unpack templates interleave each lane with either source aliased" {
    var random = std.Random.DefaultPrng.init(0x256A11A5);
    const forms = [_]struct { op: core.Op, bytes: usize, high: bool }{
        .{ .op = .vunpcklps, .bytes = 4, .high = false },   .{ .op = .vunpckhps, .bytes = 4, .high = true },
        .{ .op = .vunpcklpd, .bytes = 8, .high = false },   .{ .op = .vunpckhpd, .bytes = 8, .high = true },
        .{ .op = .vpunpcklbw, .bytes = 1, .high = false },  .{ .op = .vpunpckhbw, .bytes = 1, .high = true },
        .{ .op = .vpunpcklwd, .bytes = 2, .high = false },  .{ .op = .vpunpckhwd, .bytes = 2, .high = true },
        .{ .op = .vpunpckldq, .bytes = 4, .high = false },  .{ .op = .vpunpckhdq, .bytes = 4, .high = true },
        .{ .op = .vpunpcklqdq, .bytes = 8, .high = false }, .{ .op = .vpunpckhqdq, .bytes = 8, .high = true },
    };
    for (forms) |form| for ([_]u8{ 0, 1, 2, 15 }) |dst| {
        var h = try harness.TestHarness.init();
        defer h.deinit();
        try h.add(0x1000, 4, .{ .op = form.op, .vector_256 = true, .xmm_dst = dst, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = true });
        for (0..8) |_| {
            var state = harness.TestState{};
            random.random().bytes(std.mem.asBytes(&state.xmm));
            random.random().bytes(std.mem.asBytes(&state.ymm_hi));
            const low = state.xmm;
            const high = state.ymm_hi;
            @memset(std.mem.asBytes(&state.zmm_hi), 0xCD);
            state.regs.rflags = 0x246;
            _ = try h.run(&state);
            for (0..2) |half| {
                const lhs = if (half == 0) low[1] else high[1];
                const rhs = if (half == 0) low[2] else high[2];
                const result = if (half == 0) state.xmm[dst] else state.ymm_hi[dst];
                const start: usize = if (form.high) 8 else 0;
                for (0..8 / form.bytes) |lane| {
                    try testing.expectEqualSlices(u8, lhs[start + lane * form.bytes ..][0..form.bytes], result[lane * 2 * form.bytes ..][0..form.bytes]);
                    try testing.expectEqualSlices(u8, rhs[start + lane * form.bytes ..][0..form.bytes], result[(lane * 2 + 1) * form.bytes ..][0..form.bytes]);
                }
            }
            for (0..32) |reg| if (reg != dst) {
                try testing.expectEqualSlices(u8, &low[reg], &state.xmm[reg]);
                try testing.expectEqualSlices(u8, &high[reg], &state.ymm_hi[reg]);
            };
            for (state.zmm_hi) |reg| for (reg) |byte| try testing.expectEqual(@as(u8, 0xCD), byte);
            try testing.expectEqual(@as(u64, 0x246), state.regs.rflags);
            try testing.expectEqual(@as(u32, 0), h.block.fallback_count);
        }
        var memory_form: core.DecodedInsn = .{ .op = form.op, .vector_256 = true, .is_reg_form = false };
        try testing.expect(!core.isVectorNative(memory_form));
        memory_form.is_reg_form = true;
        memory_form.is_evex = true;
        try testing.expect(!core.isVectorNative(memory_form));
    };
}

test "compact permutation template emits twelve ARM words" {
    var assembler = core.Assembler.init(testing.allocator);
    defer assembler.deinit();
    try permute.variable(&assembler, 0, 1, 2, 4, 5, 10);
    try testing.expectEqual(@as(usize, 12), assembler.words.items.len);
}
