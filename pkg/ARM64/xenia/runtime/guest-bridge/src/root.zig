//! ARM64 host-side facts for the PPC guest bridge.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";

pub const GuestAddress = u32;
pub const GuestWord = u32;

pub fn decodeGuestWord(bytes: *const [4]u8) GuestWord {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

pub fn guestInstructionAligned(address: GuestAddress) bool {
    return address & 3 == 0;
}

pub fn hostBranchDisplacement(from: u64, target: u64) ?i64 {
    if ((from & 3) != 0 or (target & 3) != 0) return null;
    if (target >= from) {
        const distance = target - from;
        if (distance > 0x07ff_fffc) return null;
        return @intCast(distance);
    }

    const distance = from - target;
    if (distance > 0x0800_0000) return null;
    return -@as(i64, @intCast(distance));
}

pub fn fitsHostBranch(from: u64, target: u64) bool {
    return hostBranchDisplacement(from, target) != null;
}

pub const host_nop_bytes = [_]u8{ 0x1f, 0x20, 0x03, 0xd5 };
pub const ppc_guest_nop_bytes = [_]u8{ 0x60, 0x00, 0x00, 0x00 };

test "package identity is the ARM64 native bridge route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
}

test "PPC guest words stay big-endian on the ARM64 host route" {
    try std.testing.expectEqual(@as(u32, 0x6000_0000), decodeGuestWord(&ppc_guest_nop_bytes));
    try std.testing.expect(guestInstructionAligned(0x8258_2cc8));
    try std.testing.expect(!guestInstructionAligned(0x8258_2cca));
}

test "the ARM64 NOP is four bytes and is not the PPC guest NOP" {
    try std.testing.expectEqual(@as(usize, 4), host_nop_bytes.len);
    try std.testing.expect(!std.mem.eql(u8, host_nop_bytes[0..], ppc_guest_nop_bytes[0..]));
}

test "ARM64 branch 26 uses scaled signed range and alignment" {
    try std.testing.expectEqual(@as(i64, 0), hostBranchDisplacement(0x1000, 0x1000).?);
    try std.testing.expectEqual(@as(i64, 0x07ff_fffc), hostBranchDisplacement(0x1000, 0x07ff_fffc + 0x1000).?);
    try std.testing.expectEqual(@as(i64, -0x0800_0000), hostBranchDisplacement(0x0800_1000, 0x1000).?);
    try std.testing.expect(!fitsHostBranch(0x1001, 0x1000));
    try std.testing.expect(!fitsHostBranch(0, 0x0800_0000));
}
