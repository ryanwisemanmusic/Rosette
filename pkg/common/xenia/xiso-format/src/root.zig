//! Route-independent: the Xbox 360 disc image (GDFX/XISO) container layout,
//! and what an unreadable region of one actually costs.
//!
//! The defect this exists for
//! --------------------------
//! A title image is several gigabytes, and the only thing that reads all of it
//! is the launch-input content hash. So a damaged image announces itself as a
//! digest that stops at some percentage, hours of wall time after the operator
//! could have been told anything useful — and when it does stop, an offset is
//! all it says. An offset is not a diagnosis: 4744806400 is fatal if it lands
//! on the volume descriptor and merely unfortunate if it lands in the middle of
//! one file's data, and nothing in a byte count distinguishes those.
//!
//! This package carries the layout that separates them, and the plan for
//! establishing it cheaply. Identifying an image and reaching its directory
//! table costs a few hundred kilobytes of reads at known offsets. Whether the
//! image is *whole* still costs reading it, but whether it is **usable** does
//! not, and conflating the two is what makes a damaged input take minutes to
//! report and then report the wrong thing.
//!
//! ## The partition does not have to start at zero
//!
//! An image can be a raw partition dump, a full disc layout, or one of several
//! trimmed forms, and they differ only in where the game partition begins.
//! The volume descriptor is always at sector 32 *of the partition*, so finding
//! the partition is a search over known offsets rather than a constant. An
//! image read with the wrong base does not fail loudly; it fails as a directory
//! table full of implausible sector numbers.
//!
//! ## What this package is not
//!
//! * It is not a mounter, a reader, or a filesystem. It performs no host
//!   access of any kind and holds no descriptor.
//! * It does not decide policy. It says what a damaged range covers; whether a
//!   run may proceed on a partly readable image is an admission decision.
//! * It knows the root directory table only. Every subdirectory has its own
//!   table somewhere in partition space, and finding those requires walking the
//!   tree — which is a read, and therefore not this package's job. The
//!   extent-aware classifier exists so a caller that has walked can hand back
//!   what it learned.

const std = @import("std");

/// Every offset in a disc image is a multiple of this.
pub const sector_bytes: u64 = 2048;

/// Present at sector 32 of the game partition, and the only positive
/// identification that a file is a disc image at all.
pub const magic = "MICROSOFT*XBOX*MEDIA";

/// The volume descriptor's sector, counted from the start of the partition.
pub const volume_descriptor_sector: u64 = 32;

/// Where a game partition is known to begin. An image is identified by trying
/// each of these and looking for the magic; there is no field that says which
/// layout is in use, so the search *is* the identification.
pub const likely_game_offsets = [_]u64{
    0x0000_0000,
    0x0000_FB20,
    0x0002_0600,
    0x0208_0000,
    0x0FD9_0000,
};

/// Byte offsets of the fields read out of the volume descriptor.
pub const root_sector_field_offset: usize = 20;
pub const root_size_field_offset: usize = 24;

/// The smallest directory table that could hold one entry, and the largest one
/// worth believing. A table outside this range means the image was read with
/// the wrong partition base far more often than it means a huge directory.
pub const min_root_size: u32 = 13;
pub const max_root_size: u32 = 32 * 1024 * 1024;

/// Directory entry field offsets. Child ordinals are counted in four-byte
/// units from the start of the table, not in entries.
pub const entry_node_left_offset: usize = 0;
pub const entry_node_right_offset: usize = 2;
pub const entry_sector_offset: usize = 4;
pub const entry_length_offset: usize = 8;
pub const entry_attributes_offset: usize = 12;
pub const entry_name_length_offset: usize = 13;
pub const entry_name_offset: usize = 14;
pub const entry_ordinal_scale: u64 = 4;
pub const attribute_directory: u8 = 0x10;

/// Where the volume descriptor sits for a given partition base.
pub fn volumeDescriptorOffset(game_offset: u64) u64 {
    return game_offset + volume_descriptor_sector * sector_bytes;
}

/// Where a partition-relative sector lands in the file.
pub fn sectorOffset(game_offset: u64, sector: u32) u64 {
    return game_offset + @as(u64, sector) * sector_bytes;
}

pub fn rootDirectorySizeIsPlausible(root_size: u32) bool {
    return root_size >= min_root_size and root_size <= max_root_size;
}

/// What a volume descriptor says about the image around it.
pub const VolumeDescriptor = struct {
    game_offset: u64,
    root_sector: u32,
    root_size: u32,

    pub fn rootOffset(self: VolumeDescriptor) u64 {
        return sectorOffset(self.game_offset, self.root_sector);
    }

    pub fn rootEnd(self: VolumeDescriptor) u64 {
        return self.rootOffset() + self.root_size;
    }

    pub fn descriptorOffset(self: VolumeDescriptor) u64 {
        return volumeDescriptorOffset(self.game_offset);
    }
};

/// Decode a volume descriptor from the sector read at `volumeDescriptorOffset`.
///
/// Returns null when the buffer does not carry the magic or describes a
/// directory table no image would have. Both mean the same thing in practice:
/// this partition base is not the right one, so keep searching.
pub fn readVolumeDescriptor(game_offset: u64, sector: []const u8) ?VolumeDescriptor {
    if (sector.len < root_size_field_offset + 4) return null;
    if (!std.mem.eql(u8, sector[0..magic.len], magic)) return null;
    const root_sector = std.mem.readInt(u32, sector[root_sector_field_offset..][0..4], .little);
    const root_size = std.mem.readInt(u32, sector[root_size_field_offset..][0..4], .little);
    if (!rootDirectorySizeIsPlausible(root_size)) return null;
    return .{ .game_offset = game_offset, .root_sector = root_sector, .root_size = root_size };
}

/// Which structural part of an image an offset falls in.
pub const ImageRegion = enum {
    /// Before the game partition begins: padding or another partition.
    before_partition,
    /// The volume descriptor sector. Nothing mounts without it.
    volume_descriptor,
    /// The root directory table.
    directory_table,
    /// File contents, and any subdirectory table this classifier cannot see.
    file_data,
    /// Past the image's declared length.
    past_end,

    pub fn text(self: ImageRegion) []const u8 {
        return switch (self) {
            .before_partition => "before-partition",
            .volume_descriptor => "volume-descriptor",
            .directory_table => "directory-table",
            .file_data => "file-data",
            .past_end => "past-end",
        };
    }
};

pub fn regionOf(volume: VolumeDescriptor, image_bytes: u64, offset: u64) ImageRegion {
    if (offset >= image_bytes) return .past_end;
    const descriptor = volume.descriptorOffset();
    if (offset >= descriptor and offset < descriptor + sector_bytes) return .volume_descriptor;
    if (offset >= volume.rootOffset() and offset < volume.rootEnd()) return .directory_table;
    if (offset < volume.game_offset) return .before_partition;
    return .file_data;
}

/// What an unreadable range costs the run.
///
/// Ordered by severity, because a range wide enough to cover two regions is
/// owned by the worse of them.
pub const DamageImpact = enum {
    /// The range lies past the image's declared end, so it damages nothing the
    /// image claims.
    outside_image,
    /// Some file's contents are wrong. The image still identifies and mounts,
    /// and a title that never reads the affected file never notices.
    content_damaged,
    /// Part of the root directory table is gone. Entries resolved through the
    /// damaged part of the tree cannot be found at all.
    directory_damaged,
    /// The volume descriptor is unreadable. The image cannot be identified,
    /// so nothing about it can be mounted.
    unmountable,

    pub fn text(self: DamageImpact) []const u8 {
        return switch (self) {
            .outside_image => "outside-image",
            .content_damaged => "content-damaged",
            .directory_damaged => "directory-damaged",
            .unmountable => "unmountable",
        };
    }

    /// Whether this impact stops the image being used at all, as opposed to
    /// making some of what it holds wrong.
    pub fn blocksMount(self: DamageImpact) bool {
        return switch (self) {
            .unmountable, .directory_damaged => true,
            .content_damaged, .outside_image => false,
        };
    }

    pub fn atLeastAsSevereAs(self: DamageImpact, other: DamageImpact) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }
};

fn rangesOverlap(a_start: u64, a_end: u64, b_start: u64, b_end: u64) bool {
    return a_start < b_end and b_start < a_end;
}

/// Classify an unreadable range `[damage_start, damage_end)`.
pub fn impactOfDamage(
    volume: VolumeDescriptor,
    image_bytes: u64,
    damage_start: u64,
    damage_end: u64,
) DamageImpact {
    if (damage_end <= damage_start) return .outside_image;
    if (damage_start >= image_bytes) return .outside_image;
    const descriptor = volume.descriptorOffset();
    if (rangesOverlap(damage_start, damage_end, descriptor, descriptor + sector_bytes)) {
        return .unmountable;
    }
    if (rangesOverlap(damage_start, damage_end, volume.rootOffset(), volume.rootEnd())) {
        return .directory_damaged;
    }
    return .content_damaged;
}

/// One directory table found by walking the tree.
pub const DirectoryExtent = struct {
    offset: u64,
    length: u64,
};

/// The same classification, for a caller that has walked the tree and can say
/// where the subdirectory tables are.
///
/// Without those extents a damaged subdirectory table is indistinguishable from
/// damaged file contents, and the two differ: one loses a file's contents, the
/// other loses every name below it.
pub fn impactOfDamageWithDirectoryExtents(
    volume: VolumeDescriptor,
    image_bytes: u64,
    damage_start: u64,
    damage_end: u64,
    extents: []const DirectoryExtent,
) DamageImpact {
    const base = impactOfDamage(volume, image_bytes, damage_start, damage_end);
    if (base.atLeastAsSevereAs(.directory_damaged)) return base;
    if (base == .outside_image) return base;
    for (extents) |extent| {
        if (rangesOverlap(damage_start, damage_end, extent.offset, extent.offset + extent.length)) {
            return .directory_damaged;
        }
    }
    return base;
}

/// What a probe step is establishing.
pub const ProbeKind = enum {
    /// Look for the magic at one candidate partition base.
    identify,
    /// Read the volume descriptor whose base was identified.
    volume_descriptor,
    /// Read the root directory table.
    directory_table,
    /// Read one sector somewhere in content, to catch gross damage without
    /// reading the whole image.
    content_sample,

    pub fn text(self: ProbeKind) []const u8 {
        return switch (self) {
            .identify => "identify",
            .volume_descriptor => "volume-descriptor",
            .directory_table => "directory-table",
            .content_sample => "content-sample",
        };
    }
};

/// One read a caller should perform. The package plans; it never reads.
pub const ProbeStep = struct {
    kind: ProbeKind,
    offset: u64,
    length: u64,
    /// Whether a refusal here means the image cannot be used at all, as opposed
    /// to one more piece of evidence.
    required: bool,
};

/// Enough room for the identification sweep.
pub const identification_step_count: usize = likely_game_offsets.len;

/// How many content sectors to sample by default.
///
/// Sampling is a net, not a proof. Sixty-four sectors across a six-gigabyte
/// image read in well under a second and catch an image that is broadly gone;
/// they will usually miss a single damaged region, and a plan that claimed
/// otherwise would be worse than no plan at all. Whether an image is *whole*
/// is what the content hash is for.
pub const default_content_samples: usize = 64;

/// Fill `steps` with the identification sweep. Returns how many were written.
pub fn identificationPlan(image_bytes: u64, steps: []ProbeStep) usize {
    var written: usize = 0;
    for (likely_game_offsets) |game_offset| {
        if (written >= steps.len) break;
        const offset = volumeDescriptorOffset(game_offset);
        if (offset + magic.len > image_bytes) continue;
        steps[written] = .{
            .kind = .identify,
            .offset = offset,
            .length = magic.len,
            .required = false,
        };
        written += 1;
    }
    return written;
}

/// Fill `steps` with the reads that must succeed for the image to mount.
pub fn structurePlan(volume: VolumeDescriptor, steps: []ProbeStep) usize {
    var written: usize = 0;
    if (written < steps.len) {
        steps[written] = .{
            .kind = .volume_descriptor,
            .offset = volume.descriptorOffset(),
            .length = sector_bytes,
            .required = true,
        };
        written += 1;
    }
    if (written < steps.len) {
        steps[written] = .{
            .kind = .directory_table,
            .offset = volume.rootOffset(),
            .length = volume.root_size,
            .required = true,
        };
        written += 1;
    }
    return written;
}

/// Fill `steps` with evenly spaced content sectors.
///
/// The samples deliberately start after the directory table and stop before the
/// end of the image, so a sample never re-reads something the structure plan
/// already established and never runs off the end.
pub fn contentSamplePlan(
    volume: VolumeDescriptor,
    image_bytes: u64,
    sample_count: usize,
    steps: []ProbeStep,
) usize {
    if (sample_count == 0 or steps.len == 0) return 0;
    const first = volume.rootEnd();
    if (image_bytes < first + sector_bytes) return 0;
    const span = image_bytes - first - sector_bytes;
    const wanted = @min(sample_count, steps.len);
    var written: usize = 0;
    while (written < wanted) : (written += 1) {
        // Spread across the span inclusive of both ends when more than one
        // sample is asked for.
        const numerator = @as(u64, written) * span;
        const denominator: u64 = if (wanted > 1) @as(u64, wanted - 1) else 1;
        const raw = first + numerator / denominator;
        steps[written] = .{
            .kind = .content_sample,
            .offset = raw - (raw % sector_bytes),
            .length = sector_bytes,
            .required = false,
        };
    }
    return written;
}

/// The package's own consistency, checked at build time by its tests.
pub fn contractIsWellFormed() bool {
    return magic.len == 20 and
        sector_bytes == 2048 and
        volume_descriptor_sector == 32 and
        root_sector_field_offset + 4 <= sector_bytes and
        root_size_field_offset + 4 <= sector_bytes and
        min_root_size < max_root_size and
        likely_game_offsets.len > 0 and
        likely_game_offsets[0] == 0;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the volume descriptor is sector 32 of the partition, not of the file" {
    try std.testing.expectEqual(@as(u64, 0x10000), volumeDescriptorOffset(0));
    // A trimmed image whose partition starts late puts the descriptor exactly
    // that much later. Reading 0x10000 unconditionally is how an image gets
    // misidentified as "not a disc image".
    try std.testing.expectEqual(@as(u64, 0x0FD9_0000 + 0x10000), volumeDescriptorOffset(0x0FD9_0000));
}

test "a volume descriptor is only believed with the magic and a plausible table" {
    var sector = [_]u8{0} ** 64;
    @memcpy(sector[0..magic.len], magic);
    std.mem.writeInt(u32, sector[root_sector_field_offset..][0..4], 1_504_103, .little);
    std.mem.writeInt(u32, sector[root_size_field_offset..][0..4], 2048, .little);

    const volume = readVolumeDescriptor(0, &sector) orelse return error.ShouldDecode;
    try std.testing.expectEqual(@as(u32, 1_504_103), volume.root_sector);
    try std.testing.expectEqual(@as(u64, 3_080_402_944), volume.rootOffset());

    // Without the magic this base is simply the wrong one.
    var wrong = sector;
    wrong[0] = 'X';
    try std.testing.expect(readVolumeDescriptor(0, &wrong) == null);

    // A table size no image would have means the same thing: keep searching.
    var absurd = sector;
    std.mem.writeInt(u32, absurd[root_size_field_offset..][0..4], max_root_size + 1, .little);
    try std.testing.expect(readVolumeDescriptor(0, &absurd) == null);

    var empty = sector;
    std.mem.writeInt(u32, empty[root_size_field_offset..][0..4], min_root_size - 1, .little);
    try std.testing.expect(readVolumeDescriptor(0, &empty) == null);
}

test "a truncated buffer decodes to nothing rather than to garbage" {
    var sector = [_]u8{0} ** 24;
    @memcpy(sector[0..magic.len], magic);
    try std.testing.expect(readVolumeDescriptor(0, &sector) == null);
}

test "the same offset is fatal or harmless depending on what it covers" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;

    // The measured hole in a real image: past the directory table, inside
    // content. The image still identifies and still mounts.
    try std.testing.expectEqual(
        DamageImpact.content_damaged,
        impactOfDamage(volume, image_bytes, 4_744_806_400, 4_745_347_072),
    );
    try std.testing.expect(!impactOfDamage(volume, image_bytes, 4_744_806_400, 4_745_347_072).blocksMount());

    // The same size of hole over the volume descriptor ends the run.
    try std.testing.expectEqual(
        DamageImpact.unmountable,
        impactOfDamage(volume, image_bytes, 0x10000, 0x10000 + 540_672),
    );
    try std.testing.expect(impactOfDamage(volume, image_bytes, 0x10000, 0x10000 + 540_672).blocksMount());

    // And over the directory table it loses names rather than bytes.
    try std.testing.expectEqual(
        DamageImpact.directory_damaged,
        impactOfDamage(volume, image_bytes, volume.rootOffset(), volume.rootEnd()),
    );
}

test "a range past the declared end damages nothing the image claims" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;
    try std.testing.expectEqual(
        DamageImpact.outside_image,
        impactOfDamage(volume, image_bytes, image_bytes, image_bytes + 4096),
    );
    // An empty range is not damage.
    try std.testing.expectEqual(
        DamageImpact.outside_image,
        impactOfDamage(volume, image_bytes, 1024, 1024),
    );
}

test "a range spanning two regions is owned by the worse of them" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;
    // Content and the directory table together is a directory loss, not a
    // content loss.
    const impact = impactOfDamage(volume, image_bytes, volume.rootOffset() - 4096, volume.rootEnd() + 4096);
    try std.testing.expectEqual(DamageImpact.directory_damaged, impact);
    try std.testing.expect(DamageImpact.unmountable.atLeastAsSevereAs(.directory_damaged));
    try std.testing.expect(!DamageImpact.content_damaged.atLeastAsSevereAs(.directory_damaged));
}

test "a walked subdirectory table is not content, once the caller can say so" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;
    const extents = [_]DirectoryExtent{.{ .offset = 4_744_800_000, .length = 2048 }};

    // Without the extents this range is indistinguishable from file contents.
    try std.testing.expectEqual(
        DamageImpact.content_damaged,
        impactOfDamage(volume, image_bytes, 4_744_800_000, 4_744_802_048),
    );
    // With them it is a lost directory.
    try std.testing.expectEqual(
        DamageImpact.directory_damaged,
        impactOfDamageWithDirectoryExtents(volume, image_bytes, 4_744_800_000, 4_744_802_048, &extents),
    );
    // A range that misses every extent is still content.
    try std.testing.expectEqual(
        DamageImpact.content_damaged,
        impactOfDamageWithDirectoryExtents(volume, image_bytes, 5_000_000_000, 5_000_002_048, &extents),
    );
}

test "regions are named for every part of an image" {
    const volume = VolumeDescriptor{ .game_offset = 0x0FD9_0000, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;
    try std.testing.expectEqual(ImageRegion.before_partition, regionOf(volume, image_bytes, 0));
    try std.testing.expectEqual(ImageRegion.volume_descriptor, regionOf(volume, image_bytes, volume.descriptorOffset()));
    try std.testing.expectEqual(ImageRegion.directory_table, regionOf(volume, image_bytes, volume.rootOffset()));
    try std.testing.expectEqual(ImageRegion.file_data, regionOf(volume, image_bytes, 5_000_000_000));
    try std.testing.expectEqual(ImageRegion.past_end, regionOf(volume, image_bytes, image_bytes));
}

test "identification reads twenty bytes per candidate, not a partition" {
    var steps: [identification_step_count]ProbeStep = undefined;
    const written = identificationPlan(6_110_191_616, &steps);
    try std.testing.expectEqual(likely_game_offsets.len, written);

    var total: u64 = 0;
    for (steps[0..written]) |step| {
        try std.testing.expectEqual(ProbeKind.identify, step.kind);
        try std.testing.expect(!step.required);
        total += step.length;
    }
    try std.testing.expectEqual(@as(u64, magic.len * likely_game_offsets.len), total);
    try std.testing.expectEqual(@as(u64, 0x10000), steps[0].offset);
}

test "a candidate that cannot fit in the image is not probed" {
    var steps: [identification_step_count]ProbeStep = undefined;
    // Small enough that only the zero base can hold a descriptor.
    const written = identificationPlan(0x10000 + magic.len, &steps);
    try std.testing.expectEqual(@as(usize, 1), written);
    try std.testing.expectEqual(@as(u64, 0x10000), steps[0].offset);
}

test "the structure plan is what must read for the image to mount" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    var steps: [4]ProbeStep = undefined;
    const written = structurePlan(volume, &steps);
    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(ProbeKind.volume_descriptor, steps[0].kind);
    try std.testing.expectEqual(ProbeKind.directory_table, steps[1].kind);
    for (steps[0..written]) |step| try std.testing.expect(step.required);
    try std.testing.expectEqual(volume.rootOffset(), steps[1].offset);
    try std.testing.expectEqual(@as(u64, 2048), steps[1].length);
}

test "content samples stay sector aligned and inside the image" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;
    var steps: [default_content_samples]ProbeStep = undefined;
    const written = contentSamplePlan(volume, image_bytes, default_content_samples, &steps);
    try std.testing.expectEqual(default_content_samples, written);

    var previous: u64 = 0;
    for (steps[0..written]) |step| {
        try std.testing.expectEqual(ProbeKind.content_sample, step.kind);
        try std.testing.expect(!step.required);
        try std.testing.expectEqual(@as(u64, 0), step.offset % sector_bytes);
        try std.testing.expect(step.offset >= volume.rootEnd() - sector_bytes);
        try std.testing.expect(step.offset + step.length <= image_bytes);
        try std.testing.expect(step.offset >= previous);
        previous = step.offset;
    }
}

test "sampling a whole image costs a rounding error of its size" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    const image_bytes: u64 = 6_110_191_616;
    var steps: [default_content_samples]ProbeStep = undefined;
    const written = contentSamplePlan(volume, image_bytes, default_content_samples, &steps);

    var total: u64 = 0;
    for (steps[0..written]) |step| total += step.length;
    // The whole net is well under a megabyte against a six-gigabyte image.
    try std.testing.expect(total < 1024 * 1024);
    try std.testing.expect(total * 1000 < image_bytes);
}

test "an image too small to sample plans nothing rather than reading past its end" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    var steps: [default_content_samples]ProbeStep = undefined;
    try std.testing.expectEqual(@as(usize, 0), contentSamplePlan(volume, volume.rootEnd(), 8, &steps));
    try std.testing.expectEqual(@as(usize, 0), contentSamplePlan(volume, 6_110_191_616, 0, &steps));
}

test "a single sample is planned without dividing by zero" {
    const volume = VolumeDescriptor{ .game_offset = 0, .root_sector = 1_504_103, .root_size = 2048 };
    var steps: [1]ProbeStep = undefined;
    const written = contentSamplePlan(volume, 6_110_191_616, 1, &steps);
    try std.testing.expectEqual(@as(usize, 1), written);
    try std.testing.expectEqual(@as(u64, 0), steps[0].offset % sector_bytes);
}

test "a directory ordinal is scaled by four, not by entry size" {
    // The child pointers in a table are four-byte units. Treating them as
    // entry indices walks into the middle of a name.
    try std.testing.expectEqual(@as(u64, 4), entry_ordinal_scale);
    try std.testing.expectEqual(@as(usize, 14), entry_name_offset);
    try std.testing.expect(entry_name_length_offset < entry_name_offset);
}

test "every region and impact states its own vocabulary" {
    try std.testing.expectEqualStrings("volume-descriptor", ImageRegion.volume_descriptor.text());
    try std.testing.expectEqualStrings("file-data", ImageRegion.file_data.text());
    try std.testing.expectEqualStrings("unmountable", DamageImpact.unmountable.text());
    try std.testing.expectEqualStrings("content-damaged", DamageImpact.content_damaged.text());
    try std.testing.expectEqualStrings("identify", ProbeKind.identify.text());
}
