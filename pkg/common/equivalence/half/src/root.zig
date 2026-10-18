//! Cross-route equivalence test for the half-precision source mirrors.

const std = @import("std");
const x86 = @import("x86_half");
const arm64 = @import("arm64_half");
const ppc = @import("ppc_half");

pub fn main() !void {}

test "half format constants and vectors cannot drift" {
    try std.testing.expectEqual(x86.version.major, arm64.version.major);
    try std.testing.expectEqual(x86.version.major, ppc.version.major);
    try std.testing.expectEqual(x86.version.minor, arm64.version.minor);
    try std.testing.expectEqual(x86.version.minor, ppc.version.minor);
    try std.testing.expectEqual(x86.version.patch, arm64.version.patch);
    try std.testing.expectEqual(x86.version.patch, ppc.version.patch);
    try std.testing.expectEqual(x86.round_style, arm64.round_style);
    try std.testing.expectEqual(x86.round_style, ppc.round_style);
    try std.testing.expectEqual(x86.total_width, arm64.total_width);
    try std.testing.expectEqual(x86.total_width, ppc.total_width);
    try std.testing.expectEqual(x86.exponent_mask, arm64.exponent_mask);
    try std.testing.expectEqual(x86.exponent_mask, ppc.exponent_mask);
    try std.testing.expectEqual(x86.mantissa_mask, arm64.mantissa_mask);
    try std.testing.expectEqual(x86.mantissa_mask, ppc.mantissa_mask);
    try std.testing.expectEqual(x86.infinity_bits, arm64.infinity_bits);
    try std.testing.expectEqual(x86.infinity_bits, ppc.infinity_bits);
    try std.testing.expectEqual(x86.quiet_nan_bits, arm64.quiet_nan_bits);
    try std.testing.expectEqual(x86.quiet_nan_bits, ppc.quiet_nan_bits);
    try std.testing.expectEqual(x86.neg_zero_bits, arm64.neg_zero_bits);
    try std.testing.expectEqual(x86.neg_zero_bits, ppc.neg_zero_bits);
    try std.testing.expect(x86.validate() and arm64.validate() and ppc.validate());
    try std.testing.expectEqual(x86.fingerprint(), arm64.fingerprint());
    try std.testing.expectEqual(x86.fingerprint(), ppc.fingerprint());
}

test "half host route facts remain explicit" {
    try std.testing.expect(x86.host_is_little_endian);
    try std.testing.expect(arm64.host_is_little_endian);
    try std.testing.expect(!ppc.host_is_little_endian);
    try std.testing.expect(!std.mem.eql(u8, x86.host_architecture, arm64.host_architecture));
    try std.testing.expect(!std.mem.eql(u8, arm64.host_architecture, ppc.host_architecture));
}
