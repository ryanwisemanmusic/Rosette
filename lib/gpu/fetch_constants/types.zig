//! Wire-level types shared by Xenos texture and vertex fetch descriptors.

const std = @import("std");

pub const FetchConstantType = enum(u2) {
    invalid_texture = 0,
    invalid_vertex = 1,
    texture = 2,
    vertex = 3,
};

pub const TextureDimension = enum(u2) {
    one_d = 0,
    two_d = 1,
    three_d = 2,
    cube = 3,
};

pub const Endian = enum(u2) {
    none = 0,
    @"8in16" = 1,
    @"8in32" = 2,
    @"16in32" = 3,
};

/// The four possible interpretations of a six-dword texture-slot snapshot.
/// A vertex value is a valid Xenos vertex descriptor, but is the wrong kind
/// of resource if a shader asks the texture cache to bind that slot.
pub const TextureSlotDiagnosis = enum {
    texture,
    invalid_texture,
    invalid_vertex_in_texture_slot,
    vertex_in_texture_slot,
};

pub fn diagnoseTextureSlot(raw: [6]u32) TextureSlotDiagnosis {
    return switch (@as(FetchConstantType, @enumFromInt(@as(u2, @truncate(raw[0]))))) {
        .texture => .texture,
        .invalid_texture => .invalid_texture,
        .invalid_vertex => .invalid_vertex_in_texture_slot,
        .vertex => .vertex_in_texture_slot,
    };
}

test "texture slot diagnosis keeps vertex records distinct from bad texture data" {
    const halo_vertex_descriptor = [_]u32{
        0x0537_85A3,
        0x1000_001A,
        0,
        0,
        0,
        0,
    };
    try std.testing.expectEqual(.vertex_in_texture_slot, diagnoseTextureSlot(halo_vertex_descriptor));

    var texture = halo_vertex_descriptor;
    texture[0] = (texture[0] & ~@as(u32, 3)) | @intFromEnum(FetchConstantType.texture);
    try std.testing.expectEqual(.texture, diagnoseTextureSlot(texture));

    texture[0] = @intFromEnum(FetchConstantType.invalid_texture);
    try std.testing.expectEqual(.invalid_texture, diagnoseTextureSlot(texture));
    texture[0] = @intFromEnum(FetchConstantType.invalid_vertex);
    try std.testing.expectEqual(.invalid_vertex_in_texture_slot, diagnoseTextureSlot(texture));
}
