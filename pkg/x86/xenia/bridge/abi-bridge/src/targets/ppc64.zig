const target = @import("../target.zig");

pub const profile = target.Profile{
    .architecture = .ppc64,
    .host_endian = .big,
    .guest_endian = .big,
    .host_pointer_bits = 64,
    .guest_pointer_bits = 32,
    .host_nop_bytes = &[_]u8{ 0x60, 0x00, 0x00, 0x00 },
    .host_nop_word = 0x60000000,
    .host_nop_width = 4,
};
