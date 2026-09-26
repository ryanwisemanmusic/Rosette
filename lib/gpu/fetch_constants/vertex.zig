//! Two-dword vertex-fetch descriptor decoding.

const types = @import("types.zig");

pub const VertexFetch = struct {
    type: types.FetchConstantType = .invalid_texture,
    address_dwords: u32 = 0,
    endian: types.Endian = .none,
    size_words: u32 = 0,

    pub fn decode(raw: [2]u32) VertexFetch {
        return .{
            .type = @enumFromInt(@as(u2, @truncate(raw[0] & 0x3))),
            .address_dwords = raw[0] >> 2,
            .endian = @enumFromInt(@as(u2, @truncate(raw[1] & 0x3))),
            .size_words = (raw[1] >> 2) & 0x00FF_FFFF,
        };
    }

    pub fn addressBytes(self: VertexFetch) u64 {
        return @as(u64, self.address_dwords) * 4;
    }

    pub fn sizeBytes(self: VertexFetch) u64 {
        return @as(u64, self.size_words) * 4;
    }
};

test "vertex fetch decodes the address and length in their own units" {
    const fetch = VertexFetch.decode(.{ 0x0523_2583, 0x1000_001A });
    const std = @import("std");
    try std.testing.expectEqual(types.FetchConstantType.vertex, fetch.type);
    try std.testing.expectEqual(@as(u64, 0x0523_2580), fetch.addressBytes());
    try std.testing.expectEqual(types.Endian.@"8in32", fetch.endian);
    try std.testing.expectEqual(@as(u32, 6), fetch.size_words);
    try std.testing.expectEqual(@as(u64, 24), fetch.sizeBytes());
}
