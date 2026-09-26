//! Microsoft x64 call arguments translated to the SysV ABI used by the
//! shared Vulkan forwarder.

const std = @import("std");

pub const RegisterArguments = struct {
    rcx: u64,
    rdx: u64,
    r8: u64,
    r9: u64,
};

pub const SysVRegisterArguments = struct {
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    r8: u64,
    r9: u64,
};

pub fn mapArguments(
    microsoft: RegisterArguments,
    stack_arg4: u64,
    stack_arg5: u64,
) SysVRegisterArguments {
    return .{
        .rdi = microsoft.rcx,
        .rsi = microsoft.rdx,
        .rdx = microsoft.r8,
        .rcx = microsoft.r9,
        .r8 = stack_arg4,
        .r9 = stack_arg5,
    };
}

/// Return the byte offset of a Microsoft x64 stack argument from the entry
/// RSP. A direct synthetic return has already been popped, while an imported
/// thunk still has its return address on the guest stack.
pub fn stackArgumentOffset(index: usize, has_direct_return: bool) u64 {
    std.debug.assert(index >= 4);
    const stack_bias: u64 = if (has_direct_return) 32 else 40;
    return stack_bias + @as(u64, @intCast(index - 4)) * 8;
}

/// Vulkan commands with scalar float parameters pass the bits in XMM1..N in
/// the Windows ABI and XMM0..N-1 in the SysV ABI. Copy whole lanes so NaNs,
/// signed zero, and other non-canonical payloads survive unchanged.
pub fn mapScalarFloatArguments(xmm: anytype, count: usize) void {
    if (count >= xmm.len) return;
    for (0..count) |index| xmm[index] = xmm[index + 1];
}

test "Microsoft register and stack arguments map to SysV slots" {
    const mapped = mapArguments(.{
        .rcx = 0x11,
        .rdx = 0x22,
        .r8 = 0x33,
        .r9 = 0x44,
    }, 0x55, 0x66);
    try std.testing.expectEqual(@as(u64, 0x11), mapped.rdi);
    try std.testing.expectEqual(@as(u64, 0x22), mapped.rsi);
    try std.testing.expectEqual(@as(u64, 0x33), mapped.rdx);
    try std.testing.expectEqual(@as(u64, 0x44), mapped.rcx);
    try std.testing.expectEqual(@as(u64, 0x55), mapped.r8);
    try std.testing.expectEqual(@as(u64, 0x66), mapped.r9);

    try std.testing.expectEqual(@as(u64, 32), stackArgumentOffset(4, true));
    try std.testing.expectEqual(@as(u64, 40), stackArgumentOffset(5, true));
    try std.testing.expectEqual(@as(u64, 48), stackArgumentOffset(6, true));
    try std.testing.expectEqual(@as(u64, 40), stackArgumentOffset(4, false));
    try std.testing.expectEqual(@as(u64, 48), stackArgumentOffset(5, false));
    try std.testing.expectEqual(@as(u64, 56), stackArgumentOffset(6, false));
}

test "scalar float arguments preserve their exact bit patterns" {
    var xmm: [16][16]u8 = @splat(@splat(0));
    const bits = [_]u32{ 0x3f800000, 0x80000000, 0xc0200000 };
    for (bits, 1..) |value, index| std.mem.writeInt(u32, xmm[index][0..4], value, .little);

    mapScalarFloatArguments(&xmm, 3);

    for (bits, 0..) |value, index| try std.testing.expectEqual(value, std.mem.readInt(u32, xmm[index][0..4], .little));
}
