const target = @import("../target.zig");

pub const profile = target.Profile{
    .architecture = .x86_64,
    .host_endian = .little,
    .guest_endian = .big,
    .host_pointer_bits = 64,
    .guest_pointer_bits = 32,
    .host_nop_bytes = &[_]u8{0x90},
    .host_nop_word = 0x00000090,
    .host_nop_width = 1,
};
