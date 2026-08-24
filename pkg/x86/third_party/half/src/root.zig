//! Source mirror of `third_party/half/half.zig` for x86-64.
//! It carries immutable IEEE-754 facts; conversion execution remains runtime-owned.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_is_little_endian = true;
pub const version = .{ .major = 1, .minor = 12, .patch = 0 };
pub const round_style: i32 = -1;
pub const ties_to_even: u8 = 0;
pub const fp_fast_fmah: u8 = 1;
pub const total_width: u8 = 16;
pub const exponent_width: u8 = 5;
pub const mantissa_width: u8 = 10;
pub const exponent_bias: u8 = 15;
pub const infinity_bits: u16 = 0x7c00;
pub const quiet_nan_bits: u16 = 0x7fff;
pub const signaling_nan_bits: u16 = 0x7dff;
pub const max_finite_bits: u16 = 0x7bff;
pub const min_normal_bits: u16 = 0x0400;
pub const denorm_min_bits: u16 = 0x0001;
pub const epsilon_bits: u16 = 0x1400;
pub const pos_zero_bits: u16 = 0x0000;
pub const neg_zero_bits: u16 = 0x8000;
pub const sign_bit: u16 = 0x8000;
pub const exponent_mask: u16 = 0x7c00;
pub const mantissa_mask: u16 = 0x03ff;
pub const mantissa_table_len: u16 = 2048;
pub const exponent_table_len: u8 = 64;
pub const offset_table_len: u8 = 64;
pub const base_table_len: u16 = 512;
pub const shift_table_len: u16 = 512;
pub const fp_zero: u8 = 1;
pub const fp_nan: u8 = 2;
pub const fp_infinite: u8 = 3;
pub const fp_normal: u8 = 4;
pub const fp_subnormal: u8 = 0;

pub fn validate() bool {
    return version.major == 1 and version.minor == 12 and version.patch == 0 and
        round_style == -1 and ties_to_even == 0 and fp_fast_fmah == 1 and
        total_width == 16 and exponent_width == 5 and mantissa_width == 10 and exponent_bias == 15 and
        infinity_bits == 0x7c00 and quiet_nan_bits == 0x7fff and signaling_nan_bits == 0x7dff and
        max_finite_bits == 0x7bff and min_normal_bits == 0x0400 and denorm_min_bits == 1 and
        epsilon_bits == 0x1400 and pos_zero_bits == 0 and neg_zero_bits == 0x8000 and
        sign_bit == 0x8000 and exponent_mask == 0x7c00 and mantissa_mask == 0x03ff and
        mantissa_table_len == 2048 and exponent_table_len == 64 and offset_table_len == 64 and
        base_table_len == 512 and shift_table_len == 512 and
        fp_zero == 1 and fp_nan == 2 and fp_infinite == 3 and fp_normal == 4 and fp_subnormal == 0;
}

pub fn fingerprint() u64 {
    var value = std.hash.Wyhash.hash(0, "ROSETTE-HALF-ABI-V1");
    value = std.hash.Wyhash.hash(value, std.mem.asBytes(&infinity_bits));
    value = std.hash.Wyhash.hash(value, std.mem.asBytes(&quiet_nan_bits));
    value = std.hash.Wyhash.hash(value, std.mem.asBytes(&neg_zero_bits));
    return value;
}

test "x86 half ABI facts validate" {
    try std.testing.expect(host_is_little_endian);
    try std.testing.expect(validate());
    try std.testing.expectEqualStrings("x86_64", host_architecture);
}

test "x86 half source mirror fingerprint is stable" {
    try std.testing.expect(fingerprint() != 0);
    try std.testing.expectEqual(fingerprint(), fingerprint());
}
