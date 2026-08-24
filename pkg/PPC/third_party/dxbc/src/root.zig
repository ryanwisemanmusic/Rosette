//! Source mirror of `third_party/dxbc/dxbc_checksum.zig` for PPC64.
//! This records immutable shader-container facts; checksum execution remains runtime-owned.

const std = @import("std");

pub const host_architecture = "powerpc64";
pub const host_is_little_endian = false;
pub const guest_shader_container_endian = .little;
pub const md5_iv = [_]u32{ 0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476 };
pub const md5_shifts = [_]u8{ 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 };
pub const hash_offset: u32 = 0x14;
pub const chunk_size: u8 = 64;
pub const pad_threshold: u8 = 56;
pub const terminator_lsb: u8 = 1;
pub const md5_context_size: u16 = 104;
pub const md5_context_offsets = .{ .i = 0, .buf = 8, .input = 24, .digest = 88 };
pub const padding = [_]u8{0x80} ++ [_]u8{0} ** 63;
pub const known_dxbc_payload = "DXBC";
pub const known_dxbc_checksum = [_]u8{ 0xf6, 0xfc, 0x9c, 0x6a, 0x38, 0xfe, 0x16, 0x11, 0xc4, 0x12, 0x86, 0xa4, 0x9f, 0x05, 0x9f, 0x81 };

pub fn validate() bool {
    return md5_iv[0] == 0x6745_2301 and
        md5_iv[3] == 0x1032_5476 and
        md5_shifts.len == 16 and
        md5_shifts[0] == 7 and md5_shifts[15] == 21 and
        hash_offset == 0x14 and chunk_size == 64 and
        pad_threshold == 56 and terminator_lsb == 1 and
        md5_context_size == 104 and
        md5_context_offsets.i == 0 and
        md5_context_offsets.buf == 8 and
        md5_context_offsets.input == 24 and
        md5_context_offsets.digest == 88 and
        padding[0] == 0x80 and padding[63] == 0 and
        known_dxbc_payload.len == 4 and known_dxbc_checksum.len == 16;
}

pub fn fingerprint() u64 {
    var value = std.hash.Wyhash.hash(0, "ROSETTE-DXBC-ABI-V1");
    value = std.hash.Wyhash.hash(value, std.mem.sliceAsBytes(&md5_iv));
    value = std.hash.Wyhash.hash(value, &md5_shifts);
    value = std.hash.Wyhash.hash(value, &known_dxbc_checksum);
    return value;
}

test "PPC DXBC ABI facts validate" {
    try std.testing.expect(!host_is_little_endian);
    try std.testing.expect(validate());
    try std.testing.expectEqualStrings("powerpc64", host_architecture);
}

test "PPC DXBC source mirror fingerprint is stable" {
    try std.testing.expect(fingerprint() != 0);
    try std.testing.expectEqual(fingerprint(), fingerprint());
}
