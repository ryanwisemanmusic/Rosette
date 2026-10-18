//! Cross-route equivalence test for the console guest-endian source mirrors.
//!
//! The three route packages are intentionally separate source trees. This test
//! is the guard against semantic drift: every guest-facing value must agree,
//! while host architecture/codegen facts remain route-specific.

const std = @import("std");
const x86 = @import("x86_guest_endian");
const arm64 = @import("arm64_guest_endian");
const ppc = @import("ppc_guest_endian");

pub fn main() !void {}

test "all route mirrors agree on guest semantics" {
    try std.testing.expectEqualSlices(u8, &x86.ppc_nop_bytes, &arm64.ppc_nop_bytes);
    try std.testing.expectEqualSlices(u8, &x86.ppc_nop_bytes, &ppc.ppc_nop_bytes);
    try std.testing.expectEqual(x86.ppc_nop_word, arm64.ppc_nop_word);
    try std.testing.expectEqual(x86.ppc_nop_word, ppc.ppc_nop_word);
    try std.testing.expectEqual(x86.guest_instruction_width, arm64.guest_instruction_width);
    try std.testing.expectEqual(x86.guest_instruction_width, ppc.guest_instruction_width);
    try std.testing.expectEqual(x86.guest_pointer_bits, arm64.guest_pointer_bits);
    try std.testing.expectEqual(x86.guest_pointer_bits, ppc.guest_pointer_bits);
    try std.testing.expect(x86.guest_is_big_endian and arm64.guest_is_big_endian and ppc.guest_is_big_endian);
    try std.testing.expectEqual(x86.routeFingerprint(), arm64.routeFingerprint());
    try std.testing.expectEqual(x86.routeFingerprint(), ppc.routeFingerprint());

    try std.testing.expectEqual(@as(u32, 0x6000_0000), x86.decodeGuestWord(&x86.ppc_nop_bytes));
    try std.testing.expectEqual(@as(u32, 0x6000_0000), arm64.decodeGuestWord(&arm64.ppc_nop_bytes));
    try std.testing.expectEqual(@as(u32, 0x6000_0000), ppc.decodeGuestWord(&ppc.ppc_nop_bytes));
}

test "generic byte-order helpers agree across route mirrors" {
    const big_x86 = x86.encodeInteger(u32, 0x1234_5678, .big);
    const big_arm64 = arm64.encodeInteger(u32, 0x1234_5678, .big);
    const big_ppc = ppc.encodeInteger(u32, 0x1234_5678, .big);
    try std.testing.expectEqualSlices(u8, &big_x86, &big_arm64);
    try std.testing.expectEqualSlices(u8, &big_x86, &big_ppc);

    const little_x86 = x86.encodeInteger(u32, 0x1234_5678, .little);
    const little_arm64 = arm64.encodeInteger(u32, 0x1234_5678, .little);
    const little_ppc = ppc.encodeInteger(u32, 0x1234_5678, .little);
    try std.testing.expectEqualSlices(u8, &little_x86, &little_arm64);
    try std.testing.expectEqualSlices(u8, &little_x86, &little_ppc);

    try std.testing.expectEqual(@as(u32, 0x1234_5678), x86.decodeInteger(u32, &little_x86, .little));
    try std.testing.expectEqual(@as(u32, 0x1234_5678), arm64.decodeInteger(u32, &little_arm64, .little));
    try std.testing.expectEqual(@as(u32, 0x1234_5678), ppc.decodeInteger(u32, &little_ppc, .little));
    try std.testing.expect(x86.addressAligned(0x1020, 32));
    try std.testing.expect(arm64.addressAligned(0x1020, 32));
    try std.testing.expect(ppc.addressAligned(0x1020, 32));
}

test "host route facts remain distinct" {
    try std.testing.expect(!std.mem.eql(u8, x86.host_architecture, arm64.host_architecture));
    try std.testing.expect(!std.mem.eql(u8, arm64.host_architecture, ppc.host_architecture));
    try std.testing.expect(x86.host_is_little_endian);
    try std.testing.expect(arm64.host_is_little_endian);
    try std.testing.expect(!ppc.host_is_little_endian);
    try std.testing.expect(!std.mem.eql(u8, x86.host_codegen, arm64.host_codegen));
}
