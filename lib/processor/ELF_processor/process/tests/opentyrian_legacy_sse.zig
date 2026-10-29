const std = @import("std");
const process = @import("../../process.zig");
const testing = std.testing;
const ElfState = process.ElfState;
const MEM_BASE = process.__ProcessInternals._MEM_BASE;
const Op = process.Op;
const RegId = process.RegId;
const decodeInsn = process.__ProcessInternals._decodeInsn;

fn testStepBytes(state: *ElfState, bytes: []const u8) void {
    const code = MEM_BASE + 0x1000;
    for (bytes, 0..) |byte, offset| state.write8(code + offset, byte);
    state.regs.rip = code;
    state.terminated = false;
    _ = state.step();
}

fn testGetLanes(state: *const ElfState, register: usize) [4]u64 {
    return .{
        std.mem.readInt(u64, state.xmm[register][0..8], .little),
        std.mem.readInt(u64, state.xmm[register][8..16], .little),
        std.mem.readInt(u64, state.ymm_hi[register][0..8], .little),
        std.mem.readInt(u64, state.ymm_hi[register][8..16], .little),
    };
}

test "legacy PCMPEQB memory form from OpenTyrian executes through the PE64 step path" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // OpenTyrian's JE_loadMap reaches this exact encoding:
    // pcmpeqb -0x10(%rax), %xmm0. It is a legacy SSE2 two-operand form,
    // so XMM0 is both the left input and destination, and YMM0's upper half
    // must remain unchanged.
    const data = MEM_BASE + 0x20000;
    state.regs.rax = data + 16;
    state.xmm[0] = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    state.ymm_hi[0] = [_]u8{0xA5} ** 16;
    var expected: [16]u8 = [_]u8{0xFF} ** 16;
    expected[7] = 0;
    for (0..16) |index| state.write8(data + index, @intCast(index));
    state.write8(data + 7, 0xFE);

    const decoded = decodeInsn(&.{ 0x66, 0x0F, 0x74, 0x40, 0xF0 });
    try testing.expectEqual(Op.vpcmpeqb, decoded.op);
    try testing.expect(decoded.legacy_sse);
    try testing.expectEqual(@as(u8, 5), decoded.len);

    testStepBytes(&state, &.{ 0x66, 0x0F, 0x74, 0x40, 0xF0 });

    try testing.expect(!state.terminated);
    try testing.expectEqual(MEM_BASE + 0x1005, state.regs.rip);
    try testing.expectEqualSlices(u8, &expected, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xA5} ** 16), &state.ymm_hi[0]);
}

test "legacy PMULLW register form from OpenTyrian executes through the PE64 step path" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // The observed death-path fault was 66 0F D5 C3 (pmullw %xmm3, %xmm0).
    // It uses XMM0 as both destination and first source, wraps each product
    // to its low 16 bits, and leaves YMM0's upper half unchanged.
    const decoded = decodeInsn(&.{ 0x66, 0x0F, 0xD5, 0xC3 });
    try testing.expectEqual(Op.vpmullw, decoded.op);
    try testing.expect(decoded.legacy_sse);
    try testing.expectEqual(@as(u8, 4), decoded.len);

    const left = [_]u16{ 0xFFFF, 2, 300, 0x8000, 17, 0x1234, 0x7FFF, 0x55AA };
    const right = [_]u16{ 2, 0x8000, 300, 2, 19, 0x1111, 3, 0xA55A };
    for (left, 0..) |lane, index| std.mem.writeInt(u16, state.xmm[0][index * 2 ..][0..2], lane, .little);
    for (right, 0..) |lane, index| std.mem.writeInt(u16, state.xmm[3][index * 2 ..][0..2], lane, .little);
    state.ymm_hi[0] = [_]u8{0xC7} ** 16;

    testStepBytes(&state, &.{ 0x66, 0x0F, 0xD5, 0xC3 });

    try testing.expect(!state.terminated);
    try testing.expectEqual(MEM_BASE + 0x1004, state.regs.rip);
    for (left, right, 0..) |a, b, index| {
        try testing.expectEqual(a *% b, std.mem.readInt(u16, state.xmm[0][index * 2 ..][0..2], .little));
    }
    try testing.expectEqualSlices(u8, &([_]u8{0xC7} ** 16), &state.ymm_hi[0]);
}

test "legacy PSUBW subtracts packed words and preserves upper YMM state" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const psubw = decodeInsn(&.{ 0x66, 0x0F, 0xF9, 0xC1 }); // psubw %xmm1, %xmm0
    try testing.expectEqual(Op.vpsubw, psubw.op);
    try testing.expect(psubw.legacy_sse);
    state.xmm[0] = [_]u8{0} ** 16;
    state.xmm[1] = [_]u8{0} ** 16;
    std.mem.writeInt(u16, state.xmm[0][0..2], 5, .little);
    std.mem.writeInt(u16, state.xmm[0][2..4], 2, .little);
    std.mem.writeInt(u16, state.xmm[1][0..2], 7, .little);
    std.mem.writeInt(u16, state.xmm[1][2..4], 1, .little);
    state.ymm_hi[0] = [_]u8{0xB6} ** 16;

    state.execute(psubw);

    try testing.expectEqual(@as(u16, 0xFFFE), std.mem.readInt(u16, state.xmm[0][0..2], .little));
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, state.xmm[0][2..4], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xB6} ** 16), &state.ymm_hi[0]);
}

test "legacy PADDW adds packed words and preserves upper YMM state" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const paddw = decodeInsn(&.{ 0x66, 0x0F, 0xFD, 0xC1 }); // paddw %xmm1, %xmm0
    try testing.expectEqual(Op.vpaddw, paddw.op);
    try testing.expect(paddw.legacy_sse);
    state.xmm[0] = [_]u8{0} ** 16;
    state.xmm[1] = [_]u8{0} ** 16;
    std.mem.writeInt(u16, state.xmm[0][0..2], 0xFFFF, .little);
    std.mem.writeInt(u16, state.xmm[0][2..4], 12, .little);
    std.mem.writeInt(u16, state.xmm[1][0..2], 2, .little);
    std.mem.writeInt(u16, state.xmm[1][2..4], 30, .little);
    state.ymm_hi[0] = [_]u8{0xD2} ** 16;

    state.execute(paddw);

    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, state.xmm[0][0..2], .little));
    try testing.expectEqual(@as(u16, 42), std.mem.readInt(u16, state.xmm[0][2..4], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xD2} ** 16), &state.ymm_hi[0]);
}

test "legacy PSADBW sums unsigned byte distances and preserves upper YMM state" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const psadbw = decodeInsn(&.{ 0x66, 0x0F, 0xF6, 0xC1 }); // psadbw %xmm1, %xmm0
    try testing.expectEqual(Op.vpsadbw, psadbw.op);
    try testing.expect(psadbw.legacy_sse);
    state.xmm[0] = [_]u8{10} ** 8 ++ [_]u8{3} ** 8;
    state.xmm[1] = [_]u8{3} ** 8 ++ [_]u8{10} ** 8;
    state.ymm_hi[0] = [_]u8{0xA7} ** 16;

    state.execute(psadbw);

    try testing.expectEqual(@as(u64, 56), testGetLanes(&state, 0)[0]);
    try testing.expectEqual(@as(u64, 56), testGetLanes(&state, 0)[1]);
    try testing.expectEqualSlices(u8, &([_]u8{0xA7} ** 16), &state.ymm_hi[0]);
}

test "legacy PMAXSW selects signed packed-word maxima and preserves upper YMM" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const pmaxsw = decodeInsn(&.{ 0x66, 0x0F, 0xEE, 0xC1 }); // pmaxsw %xmm1, %xmm0
    try testing.expectEqual(Op.vpmaxsw, pmaxsw.op);
    try testing.expect(pmaxsw.legacy_sse);
    state.xmm[0] = [_]u8{0} ** 16;
    state.xmm[1] = [_]u8{0} ** 16;
    std.mem.writeInt(u16, state.xmm[0][0..2], 0x8000, .little);
    std.mem.writeInt(u16, state.xmm[0][2..4], 5, .little);
    std.mem.writeInt(u16, state.xmm[1][0..2], 0x7FFF, .little);
    std.mem.writeInt(u16, state.xmm[1][2..4], 3, .little);
    state.ymm_hi[0] = [_]u8{0xA5} ** 16;

    state.execute(pmaxsw);

    try testing.expectEqual(@as(i16, 0x7FFF), @as(i16, @bitCast(std.mem.readInt(u16, state.xmm[0][0..2], .little))));
    try testing.expectEqual(@as(i16, 5), @as(i16, @bitCast(std.mem.readInt(u16, state.xmm[0][2..4], .little))));
    try testing.expectEqualSlices(u8, &([_]u8{0xA5} ** 16), &state.ymm_hi[0]);
}

test "legacy PINSRW inserts register and memory words while preserving upper YMM state" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const data = MEM_BASE + 0x40000;
    state.regs.r10 = data;
    state.regs.rax = 2;
    state.write16(data + 8, 0xBEEF);
    for (0..8) |lane| std.mem.writeInt(u16, state.xmm[1][lane * 2 ..][0..2], @intCast(0x100 + lane), .little);
    state.ymm_hi[1] = [_]u8{0xA9} ** 16;

    const memory = decodeInsn(&.{ 0x66, 0x41, 0x0F, 0xC4, 0x0C, 0x82, 0x00 });
    try testing.expectEqual(Op.vpinsrw, memory.op);
    try testing.expect(!memory.is_reg_form);
    try testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try testing.expectEqual(memory.xmm_dst, memory.xmm_src);
    testStepBytes(&state, &.{ 0x66, 0x41, 0x0F, 0xC4, 0x0C, 0x82, 0x00 });
    try testing.expectEqual(@as(u16, 0xBEEF), std.mem.readInt(u16, state.xmm[1][0..2], .little));
    try testing.expectEqual(@as(u16, 0x101), std.mem.readInt(u16, state.xmm[1][2..4], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xA9} ** 16), &state.ymm_hi[1]);

    state.regs.r8 = 0x1234_ABCD;
    state.ymm_hi[9] = [_]u8{0xA9} ** 16;
    const register = decodeInsn(&.{ 0x66, 0x45, 0x0F, 0xC4, 0xC8, 0x05 });
    try testing.expectEqual(Op.vpinsrw, register.op);
    try testing.expectEqual(RegId.r8b_r8w_r8d_r8, register.src_reg);
    try testing.expectEqual(@as(u8, 9), register.xmm_dst);
    try testing.expectEqual(@as(u8, 9), register.xmm_src);
    testStepBytes(&state, &.{ 0x66, 0x45, 0x0F, 0xC4, 0xC8, 0x05 });
    try testing.expectEqual(@as(u16, 0xABCD), std.mem.readInt(u16, state.xmm[9][10..12], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xA9} ** 16), &state.ymm_hi[9]);
}

test "legacy MOVDDUP decodes m64 and duplicates its low qword while preserving upper YMM" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const data = MEM_BASE + 0x41000;
    state.regs.rax = data;
    state.write64(data, 0x0123_4567_89AB_CDEF);
    state.write64(data + 8, 0xDEAD_BEEF_CAFE_BABE);
    state.ymm_hi[1] = [_]u8{0x6D} ** 16;

    const memory = decodeInsn(&.{ 0xF2, 0x0F, 0x12, 0x08 }); // movddup (%rax), %xmm1
    try testing.expectEqual(Op.vmovddup, memory.op);
    try testing.expect(memory.legacy_sse);
    try testing.expect(!memory.is_reg_form);
    try testing.expectEqual(@as(u8, 4), memory.len);
    testStepBytes(&state, &.{ 0xF2, 0x0F, 0x12, 0x08 });
    try testing.expectEqual(@as(u64, 0x0123_4567_89AB_CDEF), std.mem.readInt(u64, state.xmm[1][0..8], .little));
    try testing.expectEqual(@as(u64, 0x0123_4567_89AB_CDEF), std.mem.readInt(u64, state.xmm[1][8..16], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0x6D} ** 16), &state.ymm_hi[1]);

    state.xmm[2] = [_]u8{0} ** 16;
    std.mem.writeInt(u64, state.xmm[2][0..8], 0xA1A2_A3A4_A5A6_A7A8, .little);
    std.mem.writeInt(u64, state.xmm[2][8..16], 0x1112_1314_1516_1718, .little);
    const register = decodeInsn(&.{ 0xF2, 0x0F, 0x12, 0xCA }); // movddup %xmm2, %xmm1
    try testing.expectEqual(Op.vmovddup, register.op);
    try testing.expect(register.is_reg_form);
    state.execute(register);
    try testing.expectEqual(@as(u64, 0xA1A2_A3A4_A5A6_A7A8), std.mem.readInt(u64, state.xmm[1][0..8], .little));
    try testing.expectEqual(@as(u64, 0xA1A2_A3A4_A5A6_A7A8), std.mem.readInt(u64, state.xmm[1][8..16], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0x6D} ** 16), &state.ymm_hi[1]);
}

test "legacy UNPCKLPD interleaves XMM low qwords and preserves upper YMM" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.xmm[0] = [_]u8{0} ** 16;
    state.xmm[2] = [_]u8{0} ** 16;
    std.mem.writeInt(u64, state.xmm[0][0..8], 0x0102_0304_0506_0708, .little);
    std.mem.writeInt(u64, state.xmm[0][8..16], 0x1112_1314_1516_1718, .little);
    std.mem.writeInt(u64, state.xmm[2][0..8], 0x2122_2324_2526_2728, .little);
    state.ymm_hi[0] = [_]u8{0xC7} ** 16;

    const decoded = decodeInsn(&.{ 0x66, 0x0F, 0x14, 0xC2 }); // unpcklpd %xmm2, %xmm0
    try testing.expectEqual(Op.vunpcklpd, decoded.op);
    try testing.expect(decoded.legacy_sse);
    try testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try testing.expectEqual(@as(u8, 2), decoded.xmm_src2);
    state.execute(decoded);

    try testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), std.mem.readInt(u64, state.xmm[0][0..8], .little));
    try testing.expectEqual(@as(u64, 0x2122_2324_2526_2728), std.mem.readInt(u64, state.xmm[0][8..16], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xC7} ** 16), &state.ymm_hi[0]);
}
