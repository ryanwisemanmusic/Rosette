//! EDRAM as ranges with owners and contents, so "the target changed" is a
//! measurement rather than an assumption.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run observed zero EDRAM writes and zero resolves, and the
//! Vulkan command processor's trace path still carries a TODO to write EDRAM
//! at all. That combination means the absence proves nothing: an unimplemented
//! writer and a title that wrote nothing produce the same zero.
//!
//! So allocation, ownership and content are tracked separately. A tile that
//! nobody has claimed, a tile claimed by two draws at once, and a tile written
//! with the value it already held are three different states, and only the
//! last of them is "the draw ran and changed nothing".
//!
//! What it never does
//! ------------------
//! It does not synthesise contents. A range that was never written reports a
//! checksum of zero *and* an unsampled flag, which are different from a range
//! that was written with zeros.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const Address = bridge.contract.Address;

/// The console's EDRAM is 10 MiB of tiles. The model tracks ranges rather than
/// bytes: a per-byte model would be both enormous and less useful, because
/// every question here is about a surface.
pub const total_bytes: u32 = 10 * 1024 * 1024;
pub const tile_bytes: u32 = 5120;
pub const tile_count: u32 = total_bytes / tile_bytes;

pub const Kind = enum(u8) {
    color = 0,
    depth = 1,
    /// Claimed and not yet identified.
    unknown = 255,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .color => "color",
            .depth => "depth",
            .unknown => "unknown",
        };
    }
};

/// One claimed region of EDRAM.
pub const Range = struct {
    base_tile: u32 = 0,
    tiles: u32 = 0,
    kind: Kind = .unknown,
    format: u32 = 0,
    pitch: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    msaa: u8 = 0,
    /// Which draw or resolve claimed it, so two claimants can be named.
    owner_id: u64 = 0,
    claimed_step: u64 = 0,
    writes: u64 = 0,
    /// Content checksum, and whether anything has ever sampled it. A zero
    /// checksum that was never sampled is not an empty surface.
    checksum: u64 = 0,
    sampled: bool = false,
    source: SourceClass = .unknown,

    pub fn endTile(self: Range) u32 {
        return self.base_tile +| self.tiles;
    }

    pub fn overlaps(self: Range, other: Range) bool {
        if (self.tiles == 0 or other.tiles == 0) return false;
        return self.base_tile < other.endTile() and other.base_tile < self.endTile();
    }

    pub fn withinDevice(self: Range) bool {
        return self.tiles != 0 and self.endTile() <= tile_count;
    }
};

pub const max_ranges: usize = 16;

pub const Verdict = enum(u8) {
    /// Nothing has claimed a range.
    unallocated,
    /// Ranges are claimed and nothing has written one.
    allocated_unwritten,
    /// A range was written and its contents did not change.
    written_unchanged,
    /// A range's contents changed.
    modified,
    /// Two live claims overlap.
    overlapping_claims,
    /// A claim extends past the device.
    out_of_device,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unallocated => "unallocated",
            .allocated_unwritten => "allocated-unwritten",
            .written_unchanged => "written-unchanged",
            .modified => "modified",
            .overlapping_claims => "OVERLAPPING-CLAIMS",
            .out_of_device => "OUT-OF-DEVICE",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unallocated => "no draw or resolve has claimed an EDRAM range. There is nothing for a write to land in, and a zero write count here is a consequence rather than a finding",
            .allocated_unwritten => "ranges are claimed and nothing has written one. Either no draw rasterized, or the writer is not implemented — and those produce the same zero, so read the draw classification before concluding either",
            .written_unchanged => "a range was written and its contents are what they already were. A draw that writes the same pixels is real; a writer that writes nothing looks identical unless the checksum is sampled on both sides",
            .modified => "a claimed range's contents changed. Something rendered",
            .overlapping_claims => "two live claims cover the same tiles. Whichever wrote last owns them, and any conclusion about either surface's contents is unsafe",
            .out_of_device => "a claim extends past the end of EDRAM. The register decode or the tile arithmetic is wrong, and nothing downstream of it is trustworthy",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .overlapping_claims or self == .out_of_device;
    }
};

pub const Summary = struct {
    ranges: usize = 0,
    dropped: u64 = 0,
    tiles_claimed: u32 = 0,
    writes: u64 = 0,
    sampled_ranges: usize = 0,
    changed_ranges: usize = 0,
    overlaps: u64 = 0,
    out_of_device: u64 = 0,
    color_ranges: usize = 0,
    depth_ranges: usize = 0,

    /// Share of the device claimed. A surface far larger than the device is a
    /// decode error rather than an ambitious title.
    pub fn occupancyPercent(self: Summary) u32 {
        return (self.tiles_claimed *| 100) / tile_count;
    }
};

pub const Model = struct {
    ranges: [max_ranges]Range = [_]Range{.{}} ** max_ranges,
    count: usize = 0,
    dropped: u64 = 0,
    overlaps: u64 = 0,
    out_of_device: u64 = 0,
    writes: u64 = 0,

    /// Claim a range. A claim that overlaps a live one, or runs off the
    /// device, is recorded and refused: silently accepting either would give
    /// every later content question an answer nobody can trust.
    pub fn claim(self: *Model, range: Range) ?*Range {
        if (!range.withinDevice()) {
            self.out_of_device +|= 1;
            return null;
        }
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.ranges[index].overlaps(range)) {
                self.overlaps +|= 1;
                return null;
            }
        }
        if (self.count >= max_ranges) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.ranges[self.count];
        self.count += 1;
        slot.* = range;
        return slot;
    }

    /// Release a range so its tiles can be claimed again. Without this a
    /// title that reuses EDRAM between passes accumulates false overlaps.
    pub fn release(self: *Model, base_tile: u32) bool {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.ranges[index].base_tile != base_tile) continue;
            self.ranges[index] = self.ranges[self.count - 1];
            self.ranges[self.count - 1] = .{};
            self.count -= 1;
            return true;
        }
        return false;
    }

    pub fn rangeAt(self: *Model, base_tile: u32) ?*Range {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (self.ranges[index].base_tile == base_tile) return &self.ranges[index];
        }
        return null;
    }

    /// Record a write and the checksum it produced. Sampling both sides is
    /// what separates "wrote the same pixels" from "did not write".
    pub fn noteWrite(self: *Model, base_tile: u32, checksum: u64, source: SourceClass) bool {
        const range = self.rangeAt(base_tile) orelse return false;
        self.writes +|= 1;
        range.writes +|= 1;
        range.source = source;
        if (!range.sampled) {
            range.sampled = true;
            range.checksum = checksum;
            return true;
        }
        const changed = range.checksum != checksum;
        range.checksum = checksum;
        return changed;
    }

    pub fn retained(self: *const Model) []const Range {
        return self.ranges[0..self.count];
    }

    pub fn summary(self: *const Model) Summary {
        var out = Summary{
            .ranges = self.count,
            .dropped = self.dropped,
            .writes = self.writes,
            .overlaps = self.overlaps,
            .out_of_device = self.out_of_device,
        };
        for (self.retained()) |range| {
            out.tiles_claimed +|= range.tiles;
            if (range.sampled) out.sampled_ranges += 1;
            if (range.writes > 1) out.changed_ranges += 1;
            switch (range.kind) {
                .color => out.color_ranges += 1,
                .depth => out.depth_ranges += 1,
                .unknown => {},
            }
        }
        return out;
    }

    pub fn verdict(self: *const Model) Verdict {
        if (self.out_of_device != 0) return .out_of_device;
        if (self.overlaps != 0) return .overlapping_claims;
        if (self.count == 0) return .unallocated;
        if (self.writes == 0) return .allocated_unwritten;
        var any_changed = false;
        for (self.retained()) |range| {
            if (range.writes > 1) any_changed = true;
        }
        return if (any_changed) .modified else .written_unchanged;
    }

    pub fn fingerprint(self: *const Model) u64 {
        const totals = self.summary();
        var hash: u64 = totals.ranges;
        hash = hash *% 31 +% totals.writes;
        hash = hash *% 31 +% totals.tiles_claimed;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn colorRange(base: u32, tiles: u32) Range {
    return .{ .base_tile = base, .tiles = tiles, .kind = .color, .width = 1280, .height = 720 };
}

// The 2026-08-31 EDRAM state: nothing claimed, nothing written, and a writer
// with an open TODO. The zero must not read as "the title rendered nothing".
test "an unallocated device makes its zero write count a consequence" {
    const model = Model{};
    const verdict = model.verdict();
    try std.testing.expectEqual(Verdict.unallocated, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "consequence") != null);
}

test "allocated and unwritten cannot distinguish a quiet title from a missing writer" {
    var model = Model{};
    _ = model.claim(colorRange(0, 128)).?;
    const verdict = model.verdict();
    try std.testing.expectEqual(Verdict.allocated_unwritten, verdict);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "same zero") != null);
}

test "a write with the same checksum is not a change" {
    var model = Model{};
    _ = model.claim(colorRange(0, 128)).?;
    // The first write establishes the baseline rather than proving a change.
    try std.testing.expect(model.noteWrite(0, 0xAAAA, .guest_authentic));
    try std.testing.expectEqual(Verdict.written_unchanged, model.verdict());
    try std.testing.expect(!model.noteWrite(0, 0xAAAA, .guest_authentic));
    try std.testing.expect(model.noteWrite(0, 0xBBBB, .guest_authentic));
    try std.testing.expectEqual(Verdict.modified, model.verdict());
    try std.testing.expectEqual(@as(usize, 1), model.summary().changed_ranges);
}

test "overlapping claims are refused and recorded" {
    var model = Model{};
    _ = model.claim(colorRange(0, 128)).?;
    try std.testing.expect(model.claim(colorRange(64, 128)) == null);
    try std.testing.expectEqual(@as(u64, 1), model.overlaps);
    const verdict = model.verdict();
    try std.testing.expectEqual(Verdict.overlapping_claims, verdict);
    try std.testing.expect(verdict.isDefect());

    // Releasing the first lets the second land, which is what a title reusing
    // EDRAM between passes actually does.
    try std.testing.expect(model.release(0));
    try std.testing.expect(model.claim(colorRange(64, 128)) != null);
}

test "a claim past the end of the device is refused" {
    var model = Model{};
    try std.testing.expect(model.claim(.{ .base_tile = tile_count - 1, .tiles = 8 }) == null);
    try std.testing.expectEqual(@as(u64, 1), model.out_of_device);
    try std.testing.expectEqual(Verdict.out_of_device, model.verdict());
    try std.testing.expect(!(Range{ .base_tile = 0, .tiles = 0 }).withinDevice());
    try std.testing.expect((Range{ .base_tile = 0, .tiles = tile_count }).withinDevice());
}

test "a write to a range nobody claimed is refused rather than inventing one" {
    var model = Model{};
    try std.testing.expect(!model.noteWrite(0, 0x1234, .guest_authentic));
    try std.testing.expectEqual(@as(u64, 0), model.writes);
    try std.testing.expectEqual(Verdict.unallocated, model.verdict());
}

test "an unsampled range's zero checksum is not an empty surface" {
    var model = Model{};
    const range = model.claim(colorRange(0, 16)).?;
    try std.testing.expect(!range.sampled);
    try std.testing.expectEqual(@as(u64, 0), range.checksum);
    try std.testing.expectEqual(@as(usize, 0), model.summary().sampled_ranges);
    _ = model.noteWrite(0, 0, .guest_authentic);
    try std.testing.expect(model.rangeAt(0).?.sampled);
    try std.testing.expectEqual(@as(usize, 1), model.summary().sampled_ranges);
}

test "the range table is bounded and occupancy is reported" {
    var model = Model{};
    // Spaced so every claim fits inside the device: an out-of-device refusal
    // and a capacity drop are different counters and this test is about the
    // second one.
    var index: u32 = 0;
    while (index < max_ranges + 3) : (index += 1) {
        _ = model.claim(colorRange(index * 100, 50));
    }
    try std.testing.expectEqual(max_ranges, model.retained().len);
    try std.testing.expectEqual(@as(u64, 3), model.dropped);
    try std.testing.expectEqual(@as(u64, 0), model.out_of_device);
    try std.testing.expect(model.summary().occupancyPercent() > 0);
    try std.testing.expectEqual(@as(u32, 2048), tile_count);
}
