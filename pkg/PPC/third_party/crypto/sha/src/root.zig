//! Source mirror of `third_party/crypto/sha.zig` for direct PPC.
//! This package carries ABI facts; hashing execution remains runtime-owned.

const std = @import("std");

pub const host_architecture = "ppc64";
pub const host_is_little_endian = false;
pub const sha1_init = [_]u32{ 0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476, 0xc3d2_e1f0 };
pub const sha256_init = [_]u32{ 0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19 };
pub const block_bytes: u8 = 64;
pub const sha1_digest_bytes: u8 = 20;
pub const sha256_digest_bytes: u8 = 32;
pub const sha1_state_size: u16 = 104;
pub const sha256_state_size: u16 = 112;
pub const guest_digest_endian = .big;

pub const Sha1State = extern struct {
    digest: [5]u32,
    block: [64]u8,
    block_index: usize,
    byte_count: usize,
};

pub const Sha256State = extern struct {
    num_bytes: u64,
    buffer_size: usize,
    buffer: [64]u8,
    hash: [8]u32,
};

pub fn validate() bool {
    return @sizeOf(Sha1State) == sha1_state_size and
        @sizeOf(Sha256State) == sha256_state_size and
        @offsetOf(Sha1State, "block") == 20 and
        @offsetOf(Sha1State, "block_index") == 88 and
        @offsetOf(Sha256State, "buffer") == 16 and
        @offsetOf(Sha256State, "hash") == 80 and
        sha1_init[0] == 0x6745_2301 and sha256_init[7] == 0x5be0_cd19;
}

pub fn fingerprint() u64 {
    var value = std.hash.Wyhash.hash(0, "ROSETTE-SHA-ABI-V1");
    value = std.hash.Wyhash.hash(value, std.mem.sliceAsBytes(&sha1_init));
    value = std.hash.Wyhash.hash(value, std.mem.sliceAsBytes(&sha256_init));
    return value;
}

test "PPC SHA constants and layouts validate" {
    try std.testing.expect(!host_is_little_endian);
    try std.testing.expect(validate());
    try std.testing.expectEqualStrings("ppc64", host_architecture);
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Sha1State) - 40);
}

test "PPC SHA source mirror fingerprint is stable" {
    try std.testing.expect(fingerprint() != 0);
    try std.testing.expectEqual(fingerprint(), fingerprint());
}
