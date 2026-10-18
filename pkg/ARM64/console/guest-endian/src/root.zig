//! Generic integer byte-order helpers plus PPC guest facts for the ARM64 route.
//!
//! Compatibility constants describe Xenia's current 32-bit big-endian PPC
//! guest. Conversion and alignment helpers accept caller-selected formats.

const std = @import("std");

pub const ByteOrder = enum { big, little };

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";
pub const host_is_little_endian = true;
pub const guest_is_big_endian = true;
pub const guest_pointer_bits: u8 = 32;
pub const host_pointer_bits: u8 = 64;

pub const ppc_nop_bytes = [_]u8{ 0x60, 0x00, 0x00, 0x00 };
pub const ppc_nop_word: u32 = 0x6000_0000;
pub const guest_instruction_width: u8 = 4;

pub fn decodeInteger(comptime Int: type, bytes: *const [@sizeOf(Int)]u8, order: ByteOrder) Int {
    return switch (order) {
        .big => std.mem.readInt(Int, bytes, .big),
        .little => std.mem.readInt(Int, bytes, .little),
    };
}

pub fn encodeInteger(comptime Int: type, value: Int, order: ByteOrder) [@sizeOf(Int)]u8 {
    var bytes: [@sizeOf(Int)]u8 = undefined;
    switch (order) {
        .big => std.mem.writeInt(Int, &bytes, value, .big),
        .little => std.mem.writeInt(Int, &bytes, value, .little),
    }
    return bytes;
}

pub fn addressAligned(address: u64, alignment: u8) bool {
    if (alignment == 0 or (alignment & (alignment - 1)) != 0) return false;
    return address & (@as(u64, alignment) - 1) == 0;
}

pub fn decodeGuestWord(bytes: *const [4]u8) u32 {
    return decodeInteger(u32, bytes, .big);
}

pub fn encodeGuestWord(word: u32) [4]u8 {
    return encodeInteger(u32, word, .big);
}

pub fn guestInstructionAligned(address: u32) bool {
    return addressAligned(address, guest_instruction_width);
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

test "integer helpers support caller-selected widths and byte orders" {
    const big = encodeInteger(u32, 0x1234_5678, .big);
    const little = encodeInteger(u32, 0x1234_5678, .little);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, &big);
    try std.testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, &little);
    try std.testing.expectEqual(@as(u32, 0x1234_5678), decodeInteger(u32, &big, .big));
    try std.testing.expectEqual(@as(u32, 0x1234_5678), decodeInteger(u32, &little, .little));

    const short = encodeInteger(u16, 0xabcd, .little);
    try std.testing.expectEqualSlices(u8, &.{ 0xcd, 0xab }, &short);
    try std.testing.expectEqual(@as(u16, 0xabcd), decodeInteger(u16, &short, .little));
}

test "alignment helper accepts power-of-two byte alignments only" {
    try std.testing.expect(addressAligned(0x1010, 16));
    try std.testing.expect(!addressAligned(0x1011, 16));
    try std.testing.expect(!addressAligned(0x1010, 0));
    try std.testing.expect(!addressAligned(0x1010, 3));
}

test "ARM64 route keeps host and guest facts distinct" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
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
