//! Route-independent: the virtual filesystem's device kinds and the XISO disc
//! image layout.
//!
//! A title's content arrives through one of a small number of device kinds — a
//! disc image, an XContent container, a host directory, or the null device.
//! Rosette's `disc_mounted` stage records which route was selected, and the
//! current run reports XISO.
//!
//! ## The partition offset is searched, not known
//!
//! An XISO does not begin at its game partition. Depending on how the image was
//! produced the partition starts at one of five offsets, and the only way to
//! tell is to look for the string `MICROSOFT*XBOX*MEDIA` at sector 32 of each
//! candidate in turn.
//!
//! That matters because the failure mode is quiet: pick the wrong base and the
//! directory table decodes to garbage, which presents as a disc with no files
//! rather than as a disc that failed to mount. `likely_partition_offsets`
//! records the five candidates in the order they are tried, so a reader can
//! tell "offset 0x02080000 matched" from "no offset matched".
//!
//! ## Everything is in 2 KiB sectors
//!
//! Sector arithmetic, not byte arithmetic. An entry's data offset is
//! `game_offset + sector * 2048`, and computing it in bytes gives an offset
//! 2048 times too small — which lands inside the image and reads plausible
//! garbage rather than failing.
//!
//! ## What this package is not
//!
//! * It is not a filesystem. It opens nothing, mounts nothing and reads
//!   nothing.
//! * It holds no mount table. Which device backs `game:` at runtime is
//!   configuration, and `pkg/common/xenia/mount-contract` owns the namespace.
//! * It does not parse a directory. The entry walk is `lib/io/`'s.

const std = @import("std");

/// Disc sectors are 2 KiB. The same 2048 an unbuffered read must align to.
pub const sector_bytes: u64 = 2048;

/// The partition's magic lives at sector 32 of the game partition.
pub const magic_sector: u64 = 32;
pub const partition_magic = "MICROSOFT*XBOX*MEDIA";

/// The offsets a game partition is looked for at, in the order tried.
///
/// 0 is a raw partition dump; the others correspond to image formats that
/// prepend a header or a video partition.
pub const likely_partition_offsets = [_]u64{
    0x0000_0000,
    0x0000_FB20,
    0x0002_0600,
    0x0208_0000,
    0x0FD9_0000,
};

/// Byte offset of a sector within an image, given a partition base.
///
/// Sector arithmetic. Computing in bytes gives an offset 2048 times too small,
/// which lands inside the image and reads plausible garbage.
pub fn sectorOffset(game_offset: u64, sector: u64) u64 {
    return game_offset + sector * sector_bytes;
}

/// Where the magic should be for a candidate partition base.
pub fn magicOffsetFor(game_offset: u64) u64 {
    return sectorOffset(game_offset, magic_sector);
}

/// Whether an image is large enough for a partition at this base to exist.
///
/// Checked before reading the magic: a candidate base past the end of the file
/// would otherwise read out of bounds during probing, and probing deliberately
/// tries bases that are usually wrong.
pub fn partitionFitsIn(image_bytes: u64, game_offset: u64) bool {
    const needed = magicOffsetFor(game_offset) + partition_magic.len;
    return image_bytes >= needed;
}

pub const DeviceKind = enum(u8) {
    /// A raw XISO disc image.
    disc_image,
    /// A compressed disc archive.
    disc_archive,
    /// An STFS/XContent container: DLC, title updates, save data.
    xcontent_container,
    /// A directory on the host filesystem.
    host_path,
    /// Reads succeed and return nothing.
    null_device,

    /// Whether the device's contents can change while the title runs.
    ///
    /// A disc cannot; a host path can. A cache keyed on the assumption that
    /// content is immutable will serve stale data from a host path, and the
    /// title sees a file it already replaced.
    pub fn isImmutable(self: DeviceKind) bool {
        return switch (self) {
            .disc_image, .disc_archive, .xcontent_container => true,
            .host_path, .null_device => false,
        };
    }

    /// Whether a write to this device could ever be observed again.
    pub fn isWritable(self: DeviceKind) bool {
        return self == .host_path;
    }

    /// Whether the device is backed by sector-addressed media.
    pub fn usesSectors(self: DeviceKind) bool {
        return self == .disc_image or self == .disc_archive;
    }
};

/// Attribute bits on a directory entry, as the on-disc table stores them.
pub const EntryAttribute = struct {
    pub const read_only: u8 = 0x01;
    pub const hidden: u8 = 0x02;
    pub const system: u8 = 0x04;
    pub const directory: u8 = 0x10;
    pub const archive: u8 = 0x20;
    pub const normal: u8 = 0x80;
};

pub fn isDirectoryEntry(attributes: u8) bool {
    return attributes & EntryAttribute.directory != 0;
}

pub fn contractIsWellFormed() bool {
    if (sector_bytes != 2048) return false;
    if (partition_magic.len != 20) return false;
    if (likely_partition_offsets[0] != 0) return false;
    if (magicOffsetFor(0) != 32 * 2048) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "sectors are 2 KiB and offsets are computed in them" {
    // Computing in bytes gives an offset 2048 times too small, which lands
    // inside the image and reads plausible garbage rather than failing.
    try std.testing.expectEqual(@as(u64, 2048), sector_bytes);
    try std.testing.expectEqual(@as(u64, 0), sectorOffset(0, 0));
    try std.testing.expectEqual(@as(u64, 2048), sectorOffset(0, 1));
    try std.testing.expectEqual(@as(u64, 65536), sectorOffset(0, 32));
    // The naive byte reading, for contrast.
    try std.testing.expect(sectorOffset(0, 32) != 32);
}

test "the magic sits at sector 32 of the partition, not of the file" {
    // A partition based at 0x02080000 puts its magic at 0x02090000, not at
    // 0x10000. Searching the file's sector 32 finds nothing and the disc
    // reports as unmountable when it is simply offset.
    try std.testing.expectEqual(@as(u64, 0x1_0000), magicOffsetFor(0));
    try std.testing.expectEqual(@as(u64, 0x0209_0000), magicOffsetFor(0x0208_0000));
    try std.testing.expectEqual(@as(u64, 0x0FDA_0000), magicOffsetFor(0x0FD9_0000));
}

test "five partition offsets are tried, raw first" {
    // Order matters for reporting: "offset 0x02080000 matched" is a different
    // fact from "no offset matched", and both are more useful than "mount
    // failed".
    try std.testing.expectEqual(@as(usize, 5), likely_partition_offsets.len);
    try std.testing.expectEqual(@as(u64, 0), likely_partition_offsets[0]);
    try std.testing.expectEqual(@as(u64, 0x0FD9_0000), likely_partition_offsets[4]);
    // Strictly ascending, so a search that stops at the first match is
    // deterministic rather than order dependent.
    var previous: u64 = 0;
    for (likely_partition_offsets[1..]) |offset| {
        try std.testing.expect(offset > previous);
        previous = offset;
    }
}

test "the magic is twenty bytes and not NUL terminated" {
    // A comparison that includes a terminator reads one byte past the magic,
    // which on a correctly formed image is the first byte of real data.
    try std.testing.expectEqual(@as(usize, 20), partition_magic.len);
    try std.testing.expectEqualStrings("MICROSOFT*XBOX*MEDIA", partition_magic);
}

test "a candidate base past the end of the image is refused" {
    // Probing deliberately tries bases that are usually wrong, so the bounds
    // check has to come before the read.
    const small_image: u64 = 0x1_0000;
    try std.testing.expect(!partitionFitsIn(small_image, 0));
    try std.testing.expect(partitionFitsIn(0x1_0000 + 20, 0));
    try std.testing.expect(!partitionFitsIn(small_image, 0x0FD9_0000));
    // A large enough image accommodates the last candidate.
    try std.testing.expect(partitionFitsIn(0x1000_0000, 0x0FD9_0000));
}

test "disc devices are immutable and host paths are not" {
    // A cache assuming immutability serves stale data from a host path, and
    // the title sees a file it already replaced.
    try std.testing.expect(DeviceKind.disc_image.isImmutable());
    try std.testing.expect(DeviceKind.disc_archive.isImmutable());
    try std.testing.expect(DeviceKind.xcontent_container.isImmutable());
    try std.testing.expect(!DeviceKind.host_path.isImmutable());
    try std.testing.expect(!DeviceKind.null_device.isImmutable());
}

test "only a host path accepts writes" {
    try std.testing.expect(DeviceKind.host_path.isWritable());
    try std.testing.expect(!DeviceKind.disc_image.isWritable());
    try std.testing.expect(!DeviceKind.xcontent_container.isWritable());
    // The null device is not writable: a write there is discarded, which is
    // different from being accepted.
    try std.testing.expect(!DeviceKind.null_device.isWritable());
}

test "only disc devices use sector addressing" {
    try std.testing.expect(DeviceKind.disc_image.usesSectors());
    try std.testing.expect(DeviceKind.disc_archive.usesSectors());
    try std.testing.expect(!DeviceKind.host_path.usesSectors());
    try std.testing.expect(!DeviceKind.xcontent_container.usesSectors());
}

test "directory entries are recognised by attribute bit" {
    try std.testing.expect(isDirectoryEntry(EntryAttribute.directory));
    try std.testing.expect(isDirectoryEntry(EntryAttribute.directory | EntryAttribute.read_only));
    try std.testing.expect(!isDirectoryEntry(EntryAttribute.normal));
    try std.testing.expect(!isDirectoryEntry(0));
    // The bits do not overlap.
    try std.testing.expectEqual(@as(u8, 0), EntryAttribute.directory & EntryAttribute.normal);
}

test "sector offsets do not overflow on a large image" {
    // A 64-bit computation throughout: a 32-bit sector times 2048 overflows
    // a u32 at 2 MiB of sectors, which is well inside a dual-layer disc.
    const big_sector: u64 = 4_000_000;
    try std.testing.expectEqual(@as(u64, 8_192_000_000), sectorOffset(0, big_sector));
    try std.testing.expect(sectorOffset(0, big_sector) > std.math.maxInt(u32));
}
