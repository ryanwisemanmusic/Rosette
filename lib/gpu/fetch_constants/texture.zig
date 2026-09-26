//! Six-dword Xenos texture-fetch descriptor decoding.

const types = @import("types.zig");

fn signedBits(value: u32, bits: u5) i32 {
    const mask = (@as(u32, 1) << bits) - 1;
    const raw: i32 = @intCast(value & mask);
    const sign = @as(i32, 1) << (bits - 1);
    return if ((raw & sign) != 0) raw - (@as(i32, 1) << bits) else raw;
}

pub const TextureFetch = struct {
    type: types.FetchConstantType = .invalid_texture,
    sign: [4]u2 = .{ 0, 0, 0, 0 },
    clamp: [3]u3 = .{ 0, 0, 0 },
    pitch_pixels: u32 = 0,
    tiled: bool = false,
    format: u6 = 0,
    endian: types.Endian = .none,
    request_size: u2 = 0,
    stacked: bool = false,
    nearest_clamp_policy: bool = false,
    base_address_bytes: u64 = 0,
    width: u32 = 1,
    height: u32 = 1,
    depth: u32 = 1,
    num_format: bool = false,
    swizzle: u12 = 0,
    exp_adjust: i8 = 0,
    mag_filter: u2 = 0,
    min_filter: u2 = 0,
    mip_filter: u2 = 0,
    aniso_filter: u3 = 0,
    arbitrary_filter: u3 = 0,
    border_size: bool = false,
    volume_mag_filter: bool = false,
    volume_min_filter: bool = false,
    mip_min_level: u4 = 0,
    mip_max_level: u4 = 0,
    mag_aniso_walk: bool = false,
    min_aniso_walk: bool = false,
    lod_bias: i16 = 0,
    grad_exp_adjust_h: i8 = 0,
    grad_exp_adjust_v: i8 = 0,
    border_color: u2 = 0,
    force_bc_w_to_max: bool = false,
    tri_clamp: u2 = 0,
    aniso_bias: i8 = 0,
    dimension: types.TextureDimension = .two_d,
    packed_mips: bool = false,
    mip_address_bytes: u64 = 0,

    pub fn decode(raw: [6]u32) TextureFetch {
        const dimension: types.TextureDimension = @enumFromInt(@as(u2, @truncate(raw[5] >> 9)));
        var result = TextureFetch{
            .type = @enumFromInt(@as(u2, @truncate(raw[0]))),
            .sign = .{
                @truncate(raw[0] >> 2),
                @truncate(raw[0] >> 4),
                @truncate(raw[0] >> 6),
                @truncate(raw[0] >> 8),
            },
            .clamp = .{
                @truncate(raw[0] >> 10),
                @truncate(raw[0] >> 13),
                @truncate(raw[0] >> 16),
            },
            .pitch_pixels = ((raw[0] >> 22) & 0x1FF) << 5,
            .tiled = (raw[0] & 0x8000_0000) != 0,
            .format = @truncate(raw[1]),
            .endian = @enumFromInt(@as(u2, @truncate(raw[1] >> 6))),
            .request_size = @truncate(raw[1] >> 8),
            .stacked = (raw[1] & (1 << 10)) != 0,
            .nearest_clamp_policy = (raw[1] & (1 << 11)) != 0,
            .base_address_bytes = @as(u64, raw[1] >> 12) << 12,
            .num_format = (raw[3] & 1) != 0,
            .swizzle = @truncate(raw[3] >> 1),
            .exp_adjust = @intCast(signedBits(raw[3] >> 13, 6)),
            .mag_filter = @truncate(raw[3] >> 19),
            .min_filter = @truncate(raw[3] >> 21),
            .mip_filter = @truncate(raw[3] >> 23),
            .aniso_filter = @truncate(raw[3] >> 25),
            .arbitrary_filter = @truncate(raw[3] >> 28),
            .border_size = (raw[3] & 0x8000_0000) != 0,
            .volume_mag_filter = (raw[4] & 1) != 0,
            .volume_min_filter = (raw[4] & 2) != 0,
            .mip_min_level = @truncate(raw[4] >> 2),
            .mip_max_level = @truncate(raw[4] >> 6),
            .mag_aniso_walk = (raw[4] & (1 << 10)) != 0,
            .min_aniso_walk = (raw[4] & (1 << 11)) != 0,
            .lod_bias = @intCast(signedBits(raw[4] >> 12, 10)),
            .grad_exp_adjust_h = @intCast(signedBits(raw[4] >> 22, 5)),
            .grad_exp_adjust_v = @intCast(signedBits(raw[4] >> 27, 5)),
            .border_color = @truncate(raw[5]),
            .force_bc_w_to_max = (raw[5] & (1 << 2)) != 0,
            .tri_clamp = @truncate(raw[5] >> 3),
            .aniso_bias = @intCast(signedBits(raw[5] >> 5, 4)),
            .dimension = dimension,
            .packed_mips = (raw[5] & (1 << 11)) != 0,
            .mip_address_bytes = @as(u64, raw[5] >> 12) << 12,
        };

        switch (dimension) {
            .one_d => result.width = (raw[2] & 0x00FF_FFFF) + 1,
            .two_d => {
                result.width = (raw[2] & 0x1FFF) + 1;
                result.height = ((raw[2] >> 13) & 0x1FFF) + 1;
                result.depth = if (result.stacked) ((raw[2] >> 26) & 0x3F) + 1 else 1;
            },
            .three_d => {
                result.width = (raw[2] & 0x7FF) + 1;
                result.height = ((raw[2] >> 11) & 0x7FF) + 1;
                result.depth = ((raw[2] >> 22) & 0x3FF) + 1;
            },
            .cube => {
                result.width = (raw[2] & 0x1FFF) + 1;
                result.height = ((raw[2] >> 13) & 0x1FFF) + 1;
                result.depth = if (result.stacked) ((raw[2] >> 26) & 0x3F) + 1 else 6;
            },
        }
        return result;
    }
};

test "texture fetch decoder expands Xenos dimensions and addresses" {
    const raw = [_]u32{
        2 | (1 << 2) | (2 << 13) | (37 << 22) | 0x8000_0000,
        3 | (2 << 6) | (1 << 10) | (0x12345 << 12),
        127 | (63 << 11) | (3 << 22),
        1 | (0xA55 << 1) | (0x3F << 13) | (1 << 19) | (2 << 21) | (3 << 23),
        1 | 2 | (2 << 2) | (9 << 6) | (1 << 10) | (1 << 11) | (0x3FF << 12),
        2 | (1 << 2) | (3 << 3) | (0xF << 5) | (2 << 9) | (0x54321 << 12),
    };
    const fetch = TextureFetch.decode(raw);
    const std = @import("std");
    try std.testing.expectEqual(types.FetchConstantType.texture, fetch.type);
    try std.testing.expectEqual(@as(u32, 37 << 5), fetch.pitch_pixels);
    try std.testing.expect(fetch.tiled);
    try std.testing.expectEqual(@as(u32, 128), fetch.width);
    try std.testing.expectEqual(@as(u32, 64), fetch.height);
    try std.testing.expectEqual(@as(u32, 4), fetch.depth);
    try std.testing.expectEqual(@as(u64, 0x12345 << 12), fetch.base_address_bytes);
    try std.testing.expectEqual(types.TextureDimension.three_d, fetch.dimension);
    try std.testing.expectEqual(@as(i16, -1), fetch.lod_bias);
    try std.testing.expect(fetch.volume_mag_filter and fetch.volume_min_filter);
    try std.testing.expect(fetch.mag_aniso_walk and fetch.min_aniso_walk);
    try std.testing.expectEqual(@as(u2, 2), fetch.border_color);
    try std.testing.expect(fetch.force_bc_w_to_max);
    try std.testing.expectEqual(@as(u2, 3), fetch.tri_clamp);
    try std.testing.expectEqual(@as(i8, -1), fetch.aniso_bias);
}
