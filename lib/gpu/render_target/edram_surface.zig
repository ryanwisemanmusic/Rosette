//! EDRAM surface placement and tile arithmetic.
//!
//! A surface occupies a contiguous run of tiles starting at a base tile. The
//! arithmetic is small; the consequences of getting it wrong are not, because
//! every mistake produces an image rather than an error.
//!
//! ## Overlap is the failure worth detecting
//!
//! EDRAM is 10 MiB, and a title at 720p with MSAA and multiple render targets
//! can genuinely run out. When two surfaces overlap, each writes over the
//! other's tiles and the result is two half-correct images interleaved in
//! bands — which looks like a tiling bug, or a shader bug, or a resolve bug,
//! and is none of them. Detecting the overlap at bind time turns an
//! unattributable visual artefact into a specific, named condition.

const std = @import("std");
const contract = @import("xenia_render_target_contract");

pub const Error = error{
    /// The surface runs past the end of EDRAM.
    OutOfEdram,
    /// A dimension of zero.
    DegenerateSurface,
};

pub const Surface = struct {
    base_tile: u32 = 0,
    /// Logical extent in pixels, before MSAA expansion.
    width: u32 = 0,
    height: u32 = 0,
    msaa: contract.Msaa = .x1,
    format: contract.SurfaceFormat = .color32,

    /// The extent in sample space, after MSAA expansion.
    ///
    /// The asymmetry lives here: 2x expands height only. A model that scales
    /// both for 2x reserves twice the tiles it needs and pushes later
    /// surfaces out of EDRAM.
    pub fn sampleExtent(self: Surface) struct { width: u32, height: u32 } {
        return .{
            .width = self.width * self.msaa.widthScale(),
            .height = self.height * self.msaa.heightScale(),
        };
    }

    pub fn tileSpan(self: Surface) u64 {
        const extent = self.sampleExtent();
        return contract.tilesForExtent(extent.width, extent.height, self.format.is64Bit());
    }

    /// The half-open tile range this surface occupies.
    pub fn tileRange(self: Surface) Error!struct { start: u32, end: u64 } {
        if (self.width == 0 or self.height == 0) return error.DegenerateSurface;
        const span = self.tileSpan();
        if (!contract.fitsInEdram(self.base_tile, span)) return error.OutOfEdram;
        return .{ .start = self.base_tile, .end = @as(u64, self.base_tile) + span };
    }

    /// Whether two surfaces share any tile.
    ///
    /// Half-open ranges, so a surface ending exactly where another begins does
    /// not overlap. Getting that boundary wrong reports a false conflict on
    /// every tightly packed layout, which is the layout a title short on EDRAM
    /// is most likely to use.
    pub fn overlaps(self: Surface, other: Surface) Error!bool {
        const mine = try self.tileRange();
        const theirs = try other.tileRange();
        return mine.start < theirs.end and theirs.start < mine.end;
    }

    pub fn bytes(self: Surface) u64 {
        return self.tileSpan() * contract.tile_bytes;
    }
};

/// A set of bound render targets.
pub const Binding = struct {
    color: [contract.max_color_targets]?Surface = @splat(null),
    depth: ?Surface = null,

    pub fn boundCount(self: *const Binding) u32 {
        var count: u32 = 0;
        for (self.color) |slot| {
            if (slot != null) count += 1;
        }
        if (self.depth != null) count += 1;
        return count;
    }

    pub fn totalTiles(self: *const Binding) u64 {
        var total: u64 = 0;
        for (self.color) |slot| {
            if (slot) |surface| total += surface.tileSpan();
        }
        if (self.depth) |surface| total += surface.tileSpan();
        return total;
    }

    pub const Conflict = struct {
        first: u32,
        second: u32,
        /// Index `max_color_targets` names the depth target.
        pub fn describesDepth(self: Conflict) bool {
            return self.second == contract.max_color_targets;
        }
    };

    /// The first pair of bound surfaces that share a tile.
    ///
    /// Returning the pair rather than a bool is the point: "something
    /// overlaps" sends someone checking every target, and the answer is
    /// usually two specific ones.
    pub fn findOverlap(self: *const Binding) Error!?Conflict {
        var surfaces: [contract.max_render_targets]?Surface = @splat(null);
        for (self.color, 0..) |slot, index| surfaces[index] = slot;
        surfaces[contract.max_color_targets] = self.depth;

        for (surfaces, 0..) |maybe_first, i| {
            const first = maybe_first orelse continue;
            for (surfaces[i + 1 ..], i + 1..) |maybe_second, j| {
                const second = maybe_second orelse continue;
                if (try first.overlaps(second)) {
                    return .{ .first = @intCast(i), .second = @intCast(j) };
                }
            }
        }
        return null;
    }

    /// Whether the bound set fits in EDRAM at all.
    pub fn fits(self: *const Binding) bool {
        return self.totalTiles() <= contract.tile_count;
    }
};

test "a 1280x720 colour target spans the tiles the geometry predicts" {
    const surface = Surface{ .width = 1280, .height = 720 };
    try std.testing.expectEqual(@as(u64, 16 * 45), surface.tileSpan());
    const range = try surface.tileRange();
    try std.testing.expectEqual(@as(u32, 0), range.start);
    try std.testing.expectEqual(@as(u64, 720), range.end);
    try std.testing.expectEqual(@as(u64, 720 * contract.tile_bytes), surface.bytes());
}

test "2x MSAA expands height only" {
    // Scaling both axes reserves twice the tiles and pushes later surfaces
    // out of EDRAM; scaling neither overlaps them.
    const base = Surface{ .width = 1280, .height = 720 };
    const two_x = Surface{ .width = 1280, .height = 720, .msaa = .x2 };
    try std.testing.expectEqual(@as(u32, 1280), two_x.sampleExtent().width);
    try std.testing.expectEqual(@as(u32, 1440), two_x.sampleExtent().height);
    try std.testing.expectEqual(base.tileSpan() * 2, two_x.tileSpan());

    const four_x = Surface{ .width = 1280, .height = 720, .msaa = .x4 };
    try std.testing.expectEqual(@as(u32, 2560), four_x.sampleExtent().width);
    try std.testing.expectEqual(@as(u32, 1440), four_x.sampleExtent().height);
    try std.testing.expectEqual(base.tileSpan() * 4, four_x.tileSpan());
}

test "a 64-bit format doubles the span" {
    const narrow = Surface{ .width = 640, .height = 480 };
    const wide = Surface{ .width = 640, .height = 480, .format = .color64 };
    try std.testing.expectEqual(narrow.tileSpan() * 2, wide.tileSpan());
}

test "a degenerate surface is refused rather than spanning nothing" {
    // A zero-sized surface would compute a zero span and then overlap
    // everything or nothing depending on the comparison, so it is refused.
    try std.testing.expectError(error.DegenerateSurface, (Surface{ .width = 0, .height = 100 }).tileRange());
    try std.testing.expectError(error.DegenerateSurface, (Surface{ .width = 100, .height = 0 }).tileRange());
}

test "a surface that runs off the end of EDRAM is refused" {
    // 4x MSAA at 1280x720 is 2880 tiles against 2048 available.
    const oversized = Surface{ .width = 1280, .height = 720, .msaa = .x4 };
    try std.testing.expect(oversized.tileSpan() > contract.tile_count);
    try std.testing.expectError(error.OutOfEdram, oversized.tileRange());

    // And a well-sized surface placed too high.
    const displaced = Surface{ .base_tile = 2000, .width = 1280, .height = 720 };
    try std.testing.expectError(error.OutOfEdram, displaced.tileRange());
}

test "adjacent surfaces do not overlap" {
    // Half-open ranges. Getting this boundary wrong reports a false conflict
    // on every tightly packed layout — the layout a title short on EDRAM uses.
    const first = Surface{ .base_tile = 0, .width = 1280, .height = 720 };
    const second = Surface{ .base_tile = 720, .width = 640, .height = 480 };
    try std.testing.expect(!try first.overlaps(second));
    try std.testing.expect(!try second.overlaps(first));
}

test "surfaces sharing one tile overlap" {
    const first = Surface{ .base_tile = 0, .width = 1280, .height = 720 };
    const second = Surface{ .base_tile = 719, .width = 640, .height = 480 };
    try std.testing.expect(try first.overlaps(second));
    try std.testing.expect(try second.overlaps(first));
}

test "an empty binding has nothing bound and fits" {
    const binding = Binding{};
    try std.testing.expectEqual(@as(u32, 0), binding.boundCount());
    try std.testing.expectEqual(@as(u64, 0), binding.totalTiles());
    try std.testing.expect(binding.fits());
    try std.testing.expect(try binding.findOverlap() == null);
}

test "a well laid out binding reports no conflict" {
    var binding = Binding{};
    binding.color[0] = .{ .base_tile = 0, .width = 640, .height = 480 };
    // 640/80 = 8 across, 480/16 = 30 down = 240 tiles.
    binding.color[1] = .{ .base_tile = 240, .width = 640, .height = 480 };
    binding.depth = .{ .base_tile = 480, .width = 640, .height = 480, .format = .depth24s8 };

    try std.testing.expectEqual(@as(u32, 3), binding.boundCount());
    try std.testing.expectEqual(@as(u64, 720), binding.totalTiles());
    try std.testing.expect(binding.fits());
    try std.testing.expect(try binding.findOverlap() == null);
}

test "an overlap names both surfaces rather than merely existing" {
    // "Something overlaps" sends someone checking every target; the answer is
    // usually two specific ones.
    var binding = Binding{};
    binding.color[0] = .{ .base_tile = 0, .width = 640, .height = 480 };
    binding.color[2] = .{ .base_tile = 100, .width = 640, .height = 480 };
    const conflict = (try binding.findOverlap()).?;
    try std.testing.expectEqual(@as(u32, 0), conflict.first);
    try std.testing.expectEqual(@as(u32, 2), conflict.second);
    try std.testing.expect(!conflict.describesDepth());
}

test "a depth target overlapping colour is identified as the depth target" {
    var binding = Binding{};
    binding.color[0] = .{ .base_tile = 0, .width = 640, .height = 480 };
    binding.depth = .{ .base_tile = 100, .width = 640, .height = 480, .format = .depth24s8 };
    const conflict = (try binding.findOverlap()).?;
    try std.testing.expectEqual(@as(u32, 0), conflict.first);
    try std.testing.expect(conflict.describesDepth());
}

test "a binding that exceeds EDRAM is reported as not fitting" {
    var binding = Binding{};
    for (&binding.color) |*slot| {
        slot.* = .{ .base_tile = 0, .width = 1280, .height = 720 };
    }
    // Four 720-tile targets is 2880, against 2048 available.
    try std.testing.expectEqual(@as(u64, 2880), binding.totalTiles());
    try std.testing.expect(!binding.fits());
}
