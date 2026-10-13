//! Production executor loops for before/after source snapshots. Both binaries
//! keep the block JIT enabled; the baseline uses the previous native templates
//! and the ordinary interpreter only where a wide unpack lacked a template.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const testing = std.testing;
const base = I._MEM_BASE;

test "vector expansion benchmark checks production permute unpack copy and scalar loops" {
    if (std.c.getenv("ROSETTE_VECTOR_EXPANSION_BENCH") == null) return error.SkipZigTest;
    if (!I._block_jit.CodeMemory.available()) return error.SkipZigTest;
    const variant = if (std.c.getenv("ROSETTE_VECTOR_VARIANT")) |value| std.mem.span(value) else "unspecified";
    for (0..5) |kind| {
        const state = try testing.allocator.create(process.ElfState);
        defer testing.allocator.destroy(state);
        state.* = process.ElfState.init(testing.allocator);
        defer state.deinit();
        state.windows_runtime_enabled = true;
        state.image_low = base;
        state.image_high = base + state.mem.len;
        const iterations: u64 = if (kind == 4) 2_000_000 else 200_000;
        const code = base + 0x1000;
        const source = base + 0x20000;
        const destination = base + 0x30000;
        var program: [256]u8 = undefined;
        var length: usize = 0;
        for (0..8) |_| {
            const bytes: []const u8 = switch (kind) {
                0 => &.{ 0xC4, 0xE2, 0x61, 0x0C, 0xD1 }, // vpermilps xmm2,xmm3,xmm1
                1 => &.{ 0xC4, 0xE2, 0x65, 0x0C, 0xD1 }, // vpermilps ymm2,ymm3,ymm1
                2 => &.{ 0xC5, 0xF5, 0x14, 0xC2 }, // vunpcklpd ymm0,ymm1,ymm2
                3 => &.{ 0xC5, 0xFE, 0x6F, 0x1E, 0xC4, 0xE2, 0x65, 0x0C, 0xD1, 0xC5, 0xFE, 0x7F, 0x17 }, // load; permute; store
                else => &.{ 0x48, 0xFF, 0xC0 }, // inc rax
            };
            @memcpy(program[length..][0..bytes.len], bytes);
            length += bytes.len;
        }
        @memcpy(program[length..][0..3], &[_]u8{ 0x49, 0xFF, 0xCF }); // dec r15
        length += 3;
        program[length] = 0x0F;
        program[length + 1] = 0x85;
        std.mem.writeInt(i32, program[length + 2 ..][0..4], -@as(i32, @intCast(length + 6)), .little);
        length += 6;
        program[length] = 0xEB;
        program[length + 1] = 0xFE;
        @memcpy(state.guestMemory(code, length + 2).?, program[0 .. length + 2]);
        state.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = length + 2 }});
        state.windows_iat_low = base + 0x3F000;
        state.windows_iat_high = state.windows_iat_low + 8;
        state.regs = .{ .rip = code, .rsp = base + 0x40000, .rsi = source, .rdi = destination, .r15 = iterations, .rflags = 2 };
        for (0..4) |lane| {
            std.mem.writeInt(u32, state.xmm[3][lane * 4 ..][0..4], @as(u32, @intCast(lane)) * 0x11111111 + 0xA0B0C0D0, .little);
            std.mem.writeInt(u32, state.ymm_hi[3][lane * 4 ..][0..4], @as(u32, @intCast(lane)) * 0x11111111 + 0x10203040, .little);
            std.mem.writeInt(u32, state.xmm[1][lane * 4 ..][0..4], 0xFFF00000 | @as(u32, @intCast(3 - lane)), .little);
            std.mem.writeInt(u32, state.ymm_hi[1][lane * 4 ..][0..4], 0x12345600 | @as(u32, @intCast(lane)), .little);
            std.mem.writeInt(u32, state.xmm[2][lane * 4 ..][0..4], @as(u32, @intCast(lane)) + 9, .little);
            std.mem.writeInt(u32, state.ymm_hi[2][lane * 4 ..][0..4], @as(u32, @intCast(lane)) + 19, .little);
        }
        @memcpy(state.guestMemory(source, 16).?, &state.xmm[3]);
        @memcpy(state.guestMemory(source + 16, 16).?, &state.ymm_hi[3]);
        var expected: [32]u8 = undefined;
        if (kind == 2) {
            @memcpy(expected[0..8], state.xmm[1][0..8]);
            @memcpy(expected[8..16], state.xmm[2][0..8]);
            @memcpy(expected[16..24], state.ymm_hi[1][0..8]);
            @memcpy(expected[24..32], state.ymm_hi[2][0..8]);
        } else {
            for (0..4) |lane| {
                @memcpy(expected[lane * 4 ..][0..4], state.xmm[3][(3 - lane) * 4 ..][0..4]);
                @memcpy(expected[16 + lane * 4 ..][0..4], state.ymm_hi[3][lane * 4 ..][0..4]);
            }
        }
        state.block_jit_enabled = true;
        if (kind == 3) state.setParallelGuestExecution(true);
        defer if (kind == 3) state.setParallelGuestExecution(false);
        const started = I._monotonicNanoseconds();
        var steps: u64 = 0;
        while (state.regs.rip != code + length and !state.terminated and steps < iterations * 30) : (steps += 1) _ = state.step();
        const elapsed = I._monotonicNanoseconds() - started;
        try testing.expectEqual(code + length, state.regs.rip);
        try testing.expectEqual(@as(u64, 0), state.regs.r15);
        const jit = state.block_jit orelse return error.TestUnexpectedResult;
        try testing.expect(jit.executions > 0);
        if (kind == 4) {
            try testing.expectEqual(iterations * 8, state.regs.rax);
        } else if (kind == 3) {
            try testing.expectEqualSlices(u8, &expected, state.guestMemory(destination, 32).?);
        } else {
            const dst: usize = if (kind == 2) 0 else 2;
            try testing.expectEqualSlices(u8, expected[0..16], &state.xmm[dst]);
            if (kind != 0) try testing.expectEqualSlices(u8, expected[16..32], &state.ymm_hi[dst]);
        }
        const names = [_][]const u8{ "permute128", "permute256", "unpack256", "quad-copy", "scalar-control" };
        std.debug.print("VECTOR_EXPANSION variant={s} case={s} iterations={d} elapsed_ns={d} steps={d} native_executions={d} fallbacks={d} unpack_fallbacks={d} code_bytes={d}\n", .{
            variant,                                              names[kind],     iterations, elapsed, steps, jit.executions, jit.fallback_calls,
            jit.fallback_ops[@intFromEnum(process.Op.vunpcklpd)], jit.memory.used,
        });
    }
}
