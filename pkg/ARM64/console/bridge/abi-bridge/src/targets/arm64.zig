const target = @import("../target.zig");

pub const profile = target.Profile{
    .architecture = .arm64,
    .host_endian = .little,
    .guest_endian = .big,
    .host_pointer_bits = 64,
    .guest_pointer_bits = 32,
    .host_nop_bytes = &[_]u8{ 0x1f, 0x20, 0x03, 0xd5 },
    .host_nop_word = 0xd503201f,
    .host_nop_width = 4,
};
