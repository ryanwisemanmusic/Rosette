//! x86-64 host-side facts for the PPC guest bridge.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";

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

pub fn hostBranchDisplacement(from_end: u64, target: u64) ?i64 {
    if (target >= from_end) {
        const distance = target - from_end;
        if (distance > 0x7fff_ffff) return null;
        return @intCast(distance);
    }

    const distance = from_end - target;
    if (distance > 0x8000_0000) return null;
    return -@as(i64, @intCast(distance));
}

pub fn fitsHostBranch(from_end: u64, target: u64) bool {
    return hostBranchDisplacement(from_end, target) != null;
}

pub const host_nop_bytes = [_]u8{0x90};
pub const ppc_guest_nop_bytes = [_]u8{ 0x60, 0x00, 0x00, 0x00 };

test "package identity is the x86 Xbyak route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
}

test "PPC guest words stay big-endian on the x86-64 host route" {
    try std.testing.expectEqual(@as(u32, 0x6000_0000), decodeGuestWord(&ppc_guest_nop_bytes));
    try std.testing.expect(guestInstructionAligned(0x8258_2cc8));
    try std.testing.expect(!guestInstructionAligned(0x8258_2cca));
}

test "the x86-64 NOP is one byte and is not the PPC guest NOP" {
    try std.testing.expectEqual(@as(usize, 1), host_nop_bytes.len);
    try std.testing.expect(!std.mem.eql(u8, host_nop_bytes[0..], ppc_guest_nop_bytes[0..]));
}

test "the x86-64 host branch uses signed rel32 range" {
    try std.testing.expectEqual(@as(i64, 0), hostBranchDisplacement(0x1004, 0x1004).?);
    try std.testing.expectEqual(@as(i64, 0x7fff_ffff), hostBranchDisplacement(0x1000, 0x8000_0fff).?);
    try std.testing.expectEqual(@as(i64, -0x8000_0000), hostBranchDisplacement(0x8000_1000, 0x0000_1000).?);
    try std.testing.expect(!fitsHostBranch(0, 0x8000_0000));
}
