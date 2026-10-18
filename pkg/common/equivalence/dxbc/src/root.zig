//! Cross-route equivalence test for the DXBC checksum source mirrors.

const std = @import("std");
const x86 = @import("x86_dxbc");
const arm64 = @import("arm64_dxbc");
const ppc = @import("ppc_dxbc");

pub fn main() !void {}

test "DXBC constants, layout, and vectors cannot drift" {
    try std.testing.expectEqualSlices(u32, &x86.md5_iv, &arm64.md5_iv);
    try std.testing.expectEqualSlices(u32, &x86.md5_iv, &ppc.md5_iv);
    try std.testing.expectEqualSlices(u8, &x86.md5_shifts, &arm64.md5_shifts);
    try std.testing.expectEqualSlices(u8, &x86.md5_shifts, &ppc.md5_shifts);
    try std.testing.expectEqual(x86.hash_offset, arm64.hash_offset);
    try std.testing.expectEqual(x86.hash_offset, ppc.hash_offset);
    try std.testing.expectEqual(x86.md5_context_size, arm64.md5_context_size);
    try std.testing.expectEqual(x86.md5_context_size, ppc.md5_context_size);
    try std.testing.expectEqualSlices(u8, &x86.padding, &arm64.padding);
    try std.testing.expectEqualSlices(u8, &x86.padding, &ppc.padding);
    try std.testing.expectEqualStrings(x86.known_dxbc_payload, arm64.known_dxbc_payload);
    try std.testing.expectEqualStrings(x86.known_dxbc_payload, ppc.known_dxbc_payload);
    try std.testing.expectEqualSlices(u8, &x86.known_dxbc_checksum, &arm64.known_dxbc_checksum);
    try std.testing.expectEqualSlices(u8, &x86.known_dxbc_checksum, &ppc.known_dxbc_checksum);
    try std.testing.expect(x86.validate() and arm64.validate() and ppc.validate());
    try std.testing.expectEqual(x86.fingerprint(), arm64.fingerprint());
    try std.testing.expectEqual(x86.fingerprint(), ppc.fingerprint());
}

test "DXBC host route facts remain explicit" {
    try std.testing.expect(x86.host_is_little_endian);
    try std.testing.expect(arm64.host_is_little_endian);
    try std.testing.expect(!ppc.host_is_little_endian);
    try std.testing.expect(!std.mem.eql(u8, x86.host_architecture, arm64.host_architecture));
    try std.testing.expect(!std.mem.eql(u8, arm64.host_architecture, ppc.host_architecture));
}
