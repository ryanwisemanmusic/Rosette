//! Cross-route equivalence test for SHA ABI/source facts.

const std = @import("std");
const x86 = @import("x86_sha");
const arm64 = @import("arm64_sha");
const ppc = @import("ppc_sha");

pub fn main() !void {}

test "SHA constants, layouts, and fingerprints agree across routes" {
    try std.testing.expectEqualSlices(u32, &x86.sha1_init, &arm64.sha1_init);
    try std.testing.expectEqualSlices(u32, &x86.sha1_init, &ppc.sha1_init);
    try std.testing.expectEqualSlices(u32, &x86.sha256_init, &arm64.sha256_init);
    try std.testing.expectEqualSlices(u32, &x86.sha256_init, &ppc.sha256_init);
    try std.testing.expectEqual(x86.block_bytes, arm64.block_bytes);
    try std.testing.expectEqual(x86.block_bytes, ppc.block_bytes);
    try std.testing.expectEqual(x86.sha1_state_size, arm64.sha1_state_size);
    try std.testing.expectEqual(x86.sha1_state_size, ppc.sha1_state_size);
    try std.testing.expectEqual(x86.sha256_state_size, arm64.sha256_state_size);
    try std.testing.expectEqual(x86.sha256_state_size, ppc.sha256_state_size);
    try std.testing.expect(x86.validate() and arm64.validate() and ppc.validate());
    try std.testing.expectEqual(x86.fingerprint(), arm64.fingerprint());
    try std.testing.expectEqual(x86.fingerprint(), ppc.fingerprint());
}

test "SHA host route identity remains explicit" {
    try std.testing.expect(x86.host_is_little_endian);
    try std.testing.expect(arm64.host_is_little_endian);
    try std.testing.expect(!ppc.host_is_little_endian);
    try std.testing.expect(!std.mem.eql(u8, x86.host_architecture, arm64.host_architecture));
    try std.testing.expect(!std.mem.eql(u8, arm64.host_architecture, ppc.host_architecture));
}
