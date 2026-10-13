//! VEX EXTRACTPS is a bit copy, using the same native template as PEXTRD.
//! Raw bytes exercise decoding, high registers, flags and memory permissions.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const testing = std.testing;
const base = I._MEM_BASE;

test "native vector extraction preserves all lane bits upper state and exact memory widths" {
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const state = try testing.allocator.create(process.ElfState);
    defer testing.allocator.destroy(state);
    state.* = process.ElfState.init(testing.allocator);
    defer state.deinit();
    state.image_low = base;
    state.image_high = base + state.mem.len;
    const code = base + 0x1000;
    const output = base + 0x30000;
    var program: [256]u8 = undefined;
    var count: usize = 0;
    for ([_]u8{ 0, 1, 2, 3, 4, 0xFD, 0xFE, 0xFF }, 0..) |imm, n| {
        // vextractps r15d,xmm11,imm; mov [rbx+n*8],r15d;
        // vextractps [rbx+n*8+4],xmm11,imm.
        const register = [_]u8{ 0xC4, 0x43, 0x79, 0x17, 0xDF, imm };
        const store = [_]u8{ 0x44, 0x89, 0x7B, @intCast(n * 8) };
        const memory = [_]u8{ 0xC4, 0x63, 0x79, 0x17, 0x5B, @intCast(n * 8 + 4), imm };
        inline for (.{ &register, &store, &memory }) |bytes| {
            @memcpy(program[count..][0..bytes.len], bytes);
            count += bytes.len;
        }
    }
    program[count] = 0xEB;
    program[count + 1] = 0xFE;
    @memcpy(state.guestMemory(code, count + 2).?, program[0 .. count + 2]);
    state.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = count + 2 }});
    const source = [_]u32{ 0x80000000, 0x7FC01234, 0xFF800000, 0x01234567 };
    for (source, 0..) |bits, n| std.mem.writeInt(u32, state.xmm[11][n * 4 ..][0..4], bits, .little);
    for (&state.ymm_hi) |*reg| @memset(reg, 0xCD);
    for (&state.zmm_hi) |*reg| @memset(reg, 0xEF);
    const xmm_before = state.xmm;
    state.block_jit_enabled = true;
    // Warm and execute the production translator, not a hand-emitted snippet.
    for (0..32) |_| {
        @memset(state.guestMemory(output - 1, 67).?, 0xA5);
        state.regs = .{ .rip = code, .rbx = output, .rsp = base + 0x40000, .r15 = 0xFFFFFFFFFFFFFFFF, .rflags = 0x246 };
        var steps: usize = 0;
        while (state.regs.rip != code + count and steps < 200 and !state.terminated) : (steps += 1) _ = state.step();
        try testing.expectEqual(code + count, state.regs.rip);
        try testing.expectEqual(@as(u64, 0x246), state.regs.rflags);
        try testing.expectEqual(@as(u64, source[3]), state.regs.r15);
        for ([_]u8{ 0, 1, 2, 3, 4, 0xFD, 0xFE, 0xFF }, 0..) |imm, n| {
            try testing.expectEqual(source[imm & 3], state.read32(output + n * 8));
            try testing.expectEqual(source[imm & 3], state.read32(output + n * 8 + 4));
        }
        try testing.expectEqual(@as(u8, 0xA5), state.read8(output - 1));
        try testing.expectEqual(@as(u8, 0xA5), state.read8(output + 64));
        try testing.expectEqualDeep(xmm_before, state.xmm);
        for (state.ymm_hi) |reg| for (reg) |byte| try testing.expectEqual(@as(u8, 0xCD), byte);
        for (state.zmm_hi) |reg| for (reg) |byte| try testing.expectEqual(@as(u8, 0xEF), byte);
    }
    try testing.expect(state.block_jit != null);
    try testing.expect(state.block_jit.?.executions > 0);
    try testing.expectEqual(@as(u64, 0), state.block_jit.?.fallback_ops[@intFromEnum(process.Op.vextractps)]);
}
