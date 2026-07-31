const std = @import("std");

/// Volume descriptor type codes (at byte 0 of each descriptor block).
pub const VolumeDescriptorType = enum(u8) {
    boot_record = 0,
    primary = 1,
    supplementary = 2,
    volume_partition = 3,
    set_terminator = 255,
    _,
};

/// Standard ISO 9660 identifier appearing in every volume descriptor.
pub const iso_identifier = "CD001";

/// Logical sector size for standard Mode 1 CD-ROM / DVD-ROM images.
pub const sector_size: usize = 2048;

/// Primary volume descriptor is always at logical sector 16.
pub const primary_volume_sector: usize = 16;

/// File flags byte within a directory record.
pub const FileFlags = packed struct(u8) {
    hidden: bool = false,
    directory: bool = false,
    associated_file: bool = false,
    record_format: bool = false,
    permissions: bool = false,
    reserved_5: bool = false,
    reserved_6: bool = false,
    not_final: bool = false,
};

/// 7-byte recording date/time used in directory records.
pub const RecordingDateTime = struct {
    years_since_1900: u8 = 0,
    month: u8 = 0,
    day: u8 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    gmt_offset: i8 = 0,

pub fn formatDate(self: RecordingDateTime) [10]u8 {
    var buf: [10]u8 = undefined;
    const year: u16 = @as(u16, 1900) + self.years_since_1900;
    _ = std.fmt.bufPrint(&buf, "{d:04}-{d:02}-{d:02}", .{ year, self.month, self.day }) catch unreachable;
    return buf;
}
};

/// 17-byte volume date/time string (VD_recording_date_time fields).
pub const VolumeDateTime = struct {
    year: [4]u8,
    month: [2]u8,
    day: [2]u8,
    hour: [2]u8,
    minute: [2]u8,
    second: [2]u8,
    hundredths: [2]u8,
    gmt_offset: i8,

    pub fn format(self: VolumeDateTime) [19]u8 {
        var buf: [19]u8 = undefined;
        const yr = std.fmt.bufPrint(buf[0..4], "{c}{c}{c}{c}", .{ self.year[0], self.year[1], self.year[2], self.year[3] }) catch unreachable;
        _ = yr;
        buf[4] = '-';
        @memcpy(buf[5..7], &self.month);
        buf[7] = '-';
        @memcpy(buf[8..10], &self.day);
        buf[10] = ' ';
        @memcpy(buf[11..13], &self.hour);
        buf[13] = ':';
        @memcpy(buf[14..16], &self.minute);
        buf[16] = ':';
        @memcpy(buf[17..19], &self.second);
        return buf;
    }
};

/// Both-byte-order integer encoding used by ISO 9660.
pub const BothByteOrder = packed struct {
    le: u16,
    be: u16,
};

/// Both-byte-order (8-byte) for sector addresses and sizes.
pub const BothByteLong = packed struct {
    le: u32,
    be: u32,
};

/// A volume descriptor header (every descriptor starts with this).
pub const VolumeDescriptorHeader = struct {
    type: VolumeDescriptorType,
    identifier: [5]u8,
    version: u8,
};

/// Primary Volume Descriptor — the root of the ISO 9660 filesystem tree.
pub const PrimaryVolumeDescriptor = struct {
    header: VolumeDescriptorHeader,
    system_identifier: [32]u8,
    volume_identifier: [32]u8,
    total_sectors: BothByteLong,
    volume_set_size: BothByteOrder,
    volume_sequence_number: BothByteOrder,
    logical_block_size: BothByteOrder,
    path_table_size: BothByteLong,
    l_path_table_location: u32,
    optional_l_path_table_location: u32,
    m_path_table_location: u32,
    optional_m_path_table_location: u32,
    root_directory: DirectoryRecord,
    volume_set_identifier: [128]u8,
    publisher_identifier: [128]u8,
    data_preparer_identifier: [128]u8,
    application_identifier: [128]u8,
    copyright_file_identifier: [38]u8,
    abstract_file_identifier: [36]u8,
    bibliographic_file_identifier: [37]u8,
    creation_date: VolumeDateTime,
    modification_date: VolumeDateTime,
    expiration_date: VolumeDateTime,
    effective_date: VolumeDateTime,
    file_structure_version: u8,
    application_data: [512]u8,
};

/// A single directory record, pointing to a file or subdirectory.
pub const DirectoryRecord = struct {
    length: u8 = 0,
    extended_attribute_length: u8 = 0,
    extent_location: u32 = 0,
    data_length: u32 = 0,
    recording_date_time: RecordingDateTime = .{},
    file_flags: FileFlags = .{},
    file_unit_size: u8 = 0,
    interleave_gap_size: u8 = 0,
    volume_sequence_number: u16 = 0,
    file_identifier_length: u8 = 0,
    /// Points into the raw sector data; lifetime tied to the sector buffer.
    file_identifier: []const u8 = "",
    /// Raw byte range identifying the record's boundaries.
    raw_offset: usize = 0,
    raw_length: u8 = 0,
};

/// High-level entry listing for directory iteration.
pub const DirectoryEntry = struct {
    name: []const u8,
    extent_location: u32,
    data_length: u32,
    is_directory: bool,
    recording_date_time: RecordingDateTime,
    file_flags: FileFlags,
};

/// Describes the ISO image derived from the primary volume descriptor.
pub const VolumeInfo = struct {
    volume_identifier: [32]u8,
    total_sectors: u32,
    logical_block_size: u16,
    root_extent: u32,
    root_length: u32,
    l_path_table_location: u32,
    m_path_table_location: u32,
    creation_date: VolumeDateTime,
    application_identifier: [128]u8,
    publisher_identifier: [128]u8,
    data_preparer_identifier: [128]u8,
    volume_set_identifier: [128]u8,
};

/// Character sets used by ISO 9660 identifiers.
pub const CharacterSet = enum {
    a_characters,
    d_characters,
};

/// Reserved / implementation-controlled directory record system-use area.
pub const SystemUseEntry = struct {
    signature: [2]u8,
    length: u16,
    data: []const u8,
};

/// Action to continue or stop iteration during directory traversal.
pub const IterateAction = enum {
    cont,
    stop,
};

/// Error set for ISO 9660 parsing.
pub const IsoError = error{
    InvalidIdentifier,
    BadVolumeDescriptorType,
    SectorOutOfBounds,
    TruncatedSector,
    BadDirectoryRecord,
    EntryNotFound,
    PathTableOverflow,
    UnsupportedInterleave,
    UnexpectedEof,
};

test "types have expected sizes" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(VolumeDescriptorType));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(FileFlags));
    try std.testing.expectEqual(@as(usize, 7), @sizeOf(RecordingDateTime));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(BothByteOrder));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(BothByteLong));
    try std.testing.expectEqual(@as(usize, 17), @sizeOf(VolumeDateTime));
}

test "iso identifier constant is correct" {
    try std.testing.expectEqualStrings("CD001", iso_identifier);
    try std.testing.expectEqual(@as(usize, 2048), sector_size);
    try std.testing.expectEqual(@as(usize, 16), primary_volume_sector);
}

test "file flags default to all false" {
    const flags = FileFlags{};
    try std.testing.expectEqual(@as(u8, 0b00000000), @as(u8, @bitCast(flags)));
    try std.testing.expect(!flags.directory);
    try std.testing.expect(!flags.hidden);
}

test "file flags directory bit is bit 1" {
    var flags = FileFlags{};
    flags.directory = true;
    try std.testing.expectEqual(@as(u8, 2), @as(u8, @bitCast(flags)));
}

test "recording date time format date" {
    var dt = RecordingDateTime{};
    dt.years_since_1900 = 110;
    dt.month = 3;
    dt.day = 15;
    const formatted = dt.formatDate();
    try std.testing.expectEqualStrings("2010-03-15", formatted[0..10]);
}
