//! Immutable Xenon guest-endian facts for the x86-64 host route.
//!
//! The guest is 32-bit big-endian PowerPC. Host byte order and host codegen
//! differ by route, but these guest vectors must not drift.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";
pub const host_is_little_endian = true;
pub const guest_is_big_endian = true;
pub const guest_pointer_bits: u8 = 32;
pub const host_pointer_bits: u8 = 64;

pub const ppc_nop_bytes = [_]u8{ 0x60, 0x00, 0x00, 0x00 };
pub const ppc_nop_word: u32 = 0x6000_0000;
pub const guest_instruction_width: u8 = 4;

pub fn decodeGuestWord(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .big);
}

pub fn encodeGuestWord(word: u32) [4]u8 {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, word, .big);
    return bytes;
}

pub fn guestInstructionAligned(address: u32) bool {
    return address & (guest_instruction_width - 1) == 0;
}

pub fn routeFingerprint() u64 {
    var result = std.hash.Wyhash.hash(0, "XENIA-GUEST-ENDIAN-V1");
    result = std.hash.Wyhash.hash(result, &ppc_nop_bytes);
    result = std.hash.Wyhash.hash(result, std.mem.asBytes(&ppc_nop_word));
    return result;
}

test "guest word vectors are big-endian" {
    try std.testing.expectEqual(ppc_nop_word, decodeGuestWord(&ppc_nop_bytes));
    try std.testing.expectEqualSlices(u8, &ppc_nop_bytes, &encodeGuestWord(ppc_nop_word));
    try std.testing.expectEqual(@as(u8, 4), guest_instruction_width);
}

test "x86 route keeps host and guest facts distinct" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
    try std.testing.expect(host_is_little_endian);
    try std.testing.expect(guest_is_big_endian);
    try std.testing.expectEqual(@as(u8, 32), guest_pointer_bits);
    try std.testing.expectEqual(@as(u8, 64), host_pointer_bits);
    try std.testing.expect(guestInstructionAligned(0x8258_2cc8));
    try std.testing.expect(!guestInstructionAligned(0x8258_2cca));
}

test "route fingerprint is deterministic" {
    try std.testing.expect(routeFingerprint() != 0);
    try std.testing.expectEqual(routeFingerprint(), routeFingerprint());
}
