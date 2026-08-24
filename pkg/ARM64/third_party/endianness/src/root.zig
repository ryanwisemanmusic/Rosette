//! Source mirror of `third_party/endianness` for the ARM64 route.
//! Host facts differ by route; fixed-width and Xenon guest vectors do not.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_is_little_endian = true;
pub const guest_is_big_endian = true;
pub const sizeof_uint16: u8 = 2;
pub const sizeof_uint32: u8 = 4;
pub const sizeof_uint64: u8 = 8;

pub const byte_swap_16_input: u16 = 0x1234;
pub const byte_swap_16_expected: u16 = 0x3412;
pub const byte_swap_32_input: u32 = 0x1234_5678;
pub const byte_swap_32_expected: u32 = 0x7856_3412;
pub const byte_swap_64_input: u64 = 0x1234_5678_9abc_def0;
pub const byte_swap_64_expected: u64 = 0xf0de_bc9a_7856_3412;
pub const guest_word_input: u32 = 0x6000_0000;
pub const guest_word_bytes = [_]u8{ 0x60, 0x00, 0x00, 0x00 };

pub fn encodeGuestWord(word: u32) [4]u8 {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, word, .big);
    return bytes;
}

pub fn decodeGuestWord(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .big);
}

pub fn validate() bool {
    return @sizeOf(u16) == sizeof_uint16 and
        @sizeOf(u32) == sizeof_uint32 and
        @sizeOf(u64) == sizeof_uint64 and
        @byteSwap(byte_swap_16_input) == byte_swap_16_expected and
        @byteSwap(byte_swap_32_input) == byte_swap_32_expected and
        @byteSwap(byte_swap_64_input) == byte_swap_64_expected and
        decodeGuestWord(&guest_word_bytes) == guest_word_input and
        std.mem.eql(u8, &encodeGuestWord(guest_word_input), &guest_word_bytes);
}

pub fn fingerprint() u64 {
    var value = std.hash.Wyhash.hash(0, "ROSETTE-ENDIANNES-V1");
    value = std.hash.Wyhash.hash(value, &guest_word_bytes);
    return value;
}

test "ARM64 fixed-width and guest vectors validate" {
    try std.testing.expect(host_is_little_endian);
    try std.testing.expect(guest_is_big_endian);
    try std.testing.expect(validate());
    try std.testing.expectEqualStrings("arm64", host_architecture);
}

test "ARM64 route preserves the source mirror vectors" {
    try std.testing.expectEqual(@as(u16, 0x3412), @byteSwap(byte_swap_16_input));
    try std.testing.expectEqual(@as(u32, 0x7856_3412), @byteSwap(byte_swap_32_input));
    try std.testing.expectEqual(@as(u64, 0xf0de_bc9a_7856_3412), @byteSwap(byte_swap_64_input));
    try std.testing.expectEqual(@as(u32, 0x6000_0000), decodeGuestWord(&guest_word_bytes));
}

test "ARM64 source mirror fingerprint is stable" {
    try std.testing.expect(fingerprint() != 0);
    try std.testing.expectEqual(fingerprint(), fingerprint());
}
