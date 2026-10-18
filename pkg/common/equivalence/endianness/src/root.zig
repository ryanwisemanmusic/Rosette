//! Cross-route equivalence test for the endianness source mirrors.

const std = @import("std");
const x86 = @import("x86_endianness");
const arm64 = @import("arm64_endianness");
const ppc = @import("ppc_endianness");

pub fn main() !void {}

test "fixed-width and Xenon guest vectors cannot drift" {
    try std.testing.expectEqual(x86.sizeof_uint16, arm64.sizeof_uint16);
    try std.testing.expectEqual(x86.sizeof_uint16, ppc.sizeof_uint16);
    try std.testing.expectEqual(x86.sizeof_uint32, arm64.sizeof_uint32);
    try std.testing.expectEqual(x86.sizeof_uint32, ppc.sizeof_uint32);
    try std.testing.expectEqual(x86.sizeof_uint64, arm64.sizeof_uint64);
    try std.testing.expectEqual(x86.sizeof_uint64, ppc.sizeof_uint64);
    try std.testing.expectEqual(x86.byte_swap_16_expected, arm64.byte_swap_16_expected);
    try std.testing.expectEqual(x86.byte_swap_16_expected, ppc.byte_swap_16_expected);
    try std.testing.expectEqual(x86.byte_swap_32_expected, arm64.byte_swap_32_expected);
    try std.testing.expectEqual(x86.byte_swap_32_expected, ppc.byte_swap_32_expected);
    try std.testing.expectEqual(x86.byte_swap_64_expected, arm64.byte_swap_64_expected);
    try std.testing.expectEqual(x86.byte_swap_64_expected, ppc.byte_swap_64_expected);
    try std.testing.expectEqualSlices(u8, &x86.guest_word_bytes, &arm64.guest_word_bytes);
    try std.testing.expectEqualSlices(u8, &x86.guest_word_bytes, &ppc.guest_word_bytes);
    try std.testing.expectEqual(x86.guest_word_input, arm64.guest_word_input);
    try std.testing.expectEqual(x86.guest_word_input, ppc.guest_word_input);
    try std.testing.expect(x86.validate() and arm64.validate() and ppc.validate());
    try std.testing.expectEqual(x86.fingerprint(), arm64.fingerprint());
    try std.testing.expectEqual(x86.fingerprint(), ppc.fingerprint());
}

test "host endianness remains an explicit route fact" {
    try std.testing.expect(x86.host_is_little_endian);
    try std.testing.expect(arm64.host_is_little_endian);
    try std.testing.expect(!ppc.host_is_little_endian);
    try std.testing.expect(!std.mem.eql(u8, x86.host_architecture, arm64.host_architecture));
    try std.testing.expect(!std.mem.eql(u8, arm64.host_architecture, ppc.host_architecture));
}
