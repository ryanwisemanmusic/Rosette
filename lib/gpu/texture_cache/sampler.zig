//! Sampler state.
//!
//! Filtering, addressing and mip selection, as the fetch constant describes
//! them. The values are small; what matters is that the defaults are the
//! console's rather than the host API's, because a sampler that silently
//! defaults to the host's idea of "reasonable" changes how every texture in
//! the title looks without anything reporting a difference.

const std = @import("std");

pub const Filter = enum(u2) {
    point = 0,
    linear = 1,
    /// The fetch constant can say "whatever the base level says", which is not
    /// the same as either concrete filter and must not be collapsed into one.
    base_map = 2,
};

pub const AddressMode = enum(u3) {
    repeat = 0,
    mirrored_repeat = 1,
    clamp_to_edge = 2,
    mirror_clamp_to_edge = 3,
    clamp_to_border = 4,
    mirror_clamp_to_border = 5,

    /// Whether the mode reads outside the texture's own texels.
    ///
    /// A border-sampling mode needs a border colour; substituting edge clamp
    /// changes the seams of every decal and skybox in the title.
    pub fn usesBorderColor(self: AddressMode) bool {
        return self == .clamp_to_border or self == .mirror_clamp_to_border;
    }
};

pub const Sampler = struct {
    min_filter: Filter = .point,
    mag_filter: Filter = .point,
    mip_filter: Filter = .base_map,
    address_u: AddressMode = .repeat,
    address_v: AddressMode = .repeat,
    address_w: AddressMode = .repeat,
    /// Anisotropy exponent: the console encodes 1x/2x/4x/8x/16x as 0..4.
    aniso_exponent: u3 = 0,
    /// Mip clamp, in 1/16 steps as the fetch constant stores them.
    min_mip_level_16: u16 = 0,
    max_mip_level_16: u16 = 0,

    pub fn maxAnisotropy(self: Sampler) u32 {
        return @as(u32, 1) << self.aniso_exponent;
    }

    pub fn isAnisotropic(self: Sampler) bool {
        return self.aniso_exponent > 0;
    }

    /// Whether any address mode needs a border colour.
    pub fn needsBorderColor(self: Sampler) bool {
        return self.address_u.usesBorderColor() or
            self.address_v.usesBorderColor() or
            self.address_w.usesBorderColor();
    }

    /// The mip level range in whole levels.
    pub fn mipRange(self: Sampler) struct { min: u32, max: u32 } {
        return .{
            .min = @as(u32, self.min_mip_level_16) / 16,
            .max = @as(u32, self.max_mip_level_16) / 16,
        };
    }

    /// Whether the sampler's own fields are consistent.
    ///
    /// A max below min is not clamped here: silently swapping them hides a
    /// fetch-constant decode bug, and the swap produces a plausible image.
    pub fn isWellFormed(self: Sampler) bool {
        return self.max_mip_level_16 >= self.min_mip_level_16;
    }
};

test "the default sampler is point filtered and repeating" {
    // The console's defaults, not the host API's. A sampler defaulting to
    // linear changes how every texture looks with nothing reporting it.
    const sampler = Sampler{};
    try std.testing.expectEqual(Filter.point, sampler.min_filter);
    try std.testing.expectEqual(Filter.point, sampler.mag_filter);
    try std.testing.expectEqual(AddressMode.repeat, sampler.address_u);
    try std.testing.expect(!sampler.isAnisotropic());
    try std.testing.expectEqual(@as(u32, 1), sampler.maxAnisotropy());
}

test "base_map is a third filter state, not a synonym" {
    // Collapsing it into point or linear picks a filter the fetch constant
    // deliberately left to the base level.
    try std.testing.expect(Filter.base_map != Filter.point);
    try std.testing.expect(Filter.base_map != Filter.linear);
    try std.testing.expectEqual(Filter.base_map, (Sampler{}).mip_filter);
}

test "anisotropy is an exponent, not a multiplier" {
    // Reading the field as a direct multiplier gives 4x where the title asked
    // for 16x, and the difference is visible on every ground texture.
    try std.testing.expectEqual(@as(u32, 1), (Sampler{ .aniso_exponent = 0 }).maxAnisotropy());
    try std.testing.expectEqual(@as(u32, 2), (Sampler{ .aniso_exponent = 1 }).maxAnisotropy());
    try std.testing.expectEqual(@as(u32, 4), (Sampler{ .aniso_exponent = 2 }).maxAnisotropy());
    try std.testing.expectEqual(@as(u32, 16), (Sampler{ .aniso_exponent = 4 }).maxAnisotropy());
}

test "border modes are distinguishable from edge clamp" {
    // Substituting edge clamp changes the seams of every decal and skybox.
    try std.testing.expect(AddressMode.clamp_to_border.usesBorderColor());
    try std.testing.expect(AddressMode.mirror_clamp_to_border.usesBorderColor());
    try std.testing.expect(!AddressMode.clamp_to_edge.usesBorderColor());
    try std.testing.expect(!AddressMode.repeat.usesBorderColor());
    try std.testing.expect(!AddressMode.mirrored_repeat.usesBorderColor());
}

test "a border colour is needed if any axis asks for one" {
    var sampler = Sampler{};
    try std.testing.expect(!sampler.needsBorderColor());
    sampler.address_v = .clamp_to_border;
    try std.testing.expect(sampler.needsBorderColor());

    sampler = Sampler{ .address_w = .mirror_clamp_to_border };
    try std.testing.expect(sampler.needsBorderColor());
}

test "mip levels are stored in sixteenths" {
    // Reading the raw field as whole levels selects level 16 where the title
    // asked for level 1, which is a 1x1 mip on most textures.
    const sampler = Sampler{ .min_mip_level_16 = 16, .max_mip_level_16 = 64 };
    try std.testing.expectEqual(@as(u32, 1), sampler.mipRange().min);
    try std.testing.expectEqual(@as(u32, 4), sampler.mipRange().max);
}

test "an inverted mip range is reported rather than swapped" {
    // Swapping hides a fetch-constant decode bug behind a plausible image.
    const inverted = Sampler{ .min_mip_level_16 = 64, .max_mip_level_16 = 16 };
    try std.testing.expect(!inverted.isWellFormed());
    const upright = Sampler{ .min_mip_level_16 = 16, .max_mip_level_16 = 64 };
    try std.testing.expect(upright.isWellFormed());
    // Equal is legal: a single pinned level.
    const pinned = Sampler{ .min_mip_level_16 = 32, .max_mip_level_16 = 32 };
    try std.testing.expect(pinned.isWellFormed());
}

test "the three address axes are independent" {
    const sampler = Sampler{
        .address_u = .repeat,
        .address_v = .clamp_to_edge,
        .address_w = .mirrored_repeat,
    };
    try std.testing.expectEqual(AddressMode.repeat, sampler.address_u);
    try std.testing.expectEqual(AddressMode.clamp_to_edge, sampler.address_v);
    try std.testing.expectEqual(AddressMode.mirrored_repeat, sampler.address_w);
}
