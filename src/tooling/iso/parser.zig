const std = @import("std");
const types = @import("types.zig");

const IsoError = types.IsoError;
const sector_size = types.sector_size;
const primary_volume_sector = types.primary_volume_sector;
const IterateAction = types.IterateAction;

/// Parsed context for reading an ISO 9660 image from an in-memory byte slice.
pub const IsoReader = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    volume: types.VolumeInfo,

    /// Open an ISO image from an in-memory buffer, parsing the primary volume
    /// descriptor immediately. Returns `null` if the image cannot be parsed.
    pub fn open(allocator: std.mem.Allocator, bytes: []const u8) IsoError!IsoReader {
        const volume = try parsePrimaryVolumeDescriptor(bytes);
        return IsoReader{
            .allocator = allocator,
            .bytes = bytes,
            .volume = volume,
        };
    }

    /// Return the logical block size (typically 2048 for standard images).
    pub fn blockSize(self: *const IsoReader) u16 {
        return self.volume.logical_block_size;
    }

    /// Total number of logical sectors in the image.
    pub fn totalSectors(self: *const IsoReader) u32 {
        return self.volume.total_sectors;
    }

    /// Read one logical sector into a caller-provided buffer.
    /// The buffer must be at least `self.blockSize()` bytes long.
    pub fn readSector(self: *const IsoReader, sector: u32, buffer: []u8) IsoError!usize {
        const bs: u32 = self.volume.logical_block_size;
        const offset: usize = @as(usize, sector) * @as(usize, bs);
        if (offset >= self.bytes.len) return error.SectorOutOfBounds;
        const available = self.bytes.len - offset;
        const count = @min(available, buffer.len);
        @memcpy(buffer[0..count], self.bytes[offset .. offset + count]);
        return count;
    }

    /// Iterate over the entries in a directory given its extent location and
    /// data length. Calls `callback` for each entry; return `.stop` from the
    /// callback to halt iteration early.
    pub fn iterateDirectory(
        self: *const IsoReader,
        extent_location: u32,
        data_length: u32,
        comptime callback_fn: *const fn (entry: types.DirectoryEntry, context: ?*anyopaque) IsoError!IterateAction,
        context: ?*anyopaque,
    ) IsoError!void {
        const bs: u32 = self.volume.logical_block_size;
        var remaining: u32 = data_length;
        var sector_offset: u32 = 0;

        var sector_buf: [sector_size]u8 = undefined;

        while (remaining > 0) {
            const current_sector = extent_location + sector_offset;
            const read_bytes = try self.readSector(current_sector, &sector_buf);
            const end = @min(remaining, @as(u32, @intCast(read_bytes)));
            const data = sector_buf[0..end];
            var pos: usize = 0;

            while (pos < data.len) {
                const record_length = data[pos];
                if (record_length == 0) {
                    // Padded sector; skip to next sector.
                    pos = data.len;
                    break;
                }

                var rec = parseDirectoryRecord(data, pos) catch break;
                defer rec.file_identifier = if (rec.file_identifier_length > 0)
                    rec.file_identifier
                else
                    "";

                const dir_entry: types.DirectoryEntry = .{
                    .name = rec.file_identifier,
                    .extent_location = rec.extent_location,
                    .data_length = rec.data_length,
                    .is_directory = rec.file_flags.directory,
                    .recording_date_time = rec.recording_date_time,
                    .file_flags = rec.file_flags,
                };

                const action = try callback_fn(dir_entry, context);
                if (action == .stop) return;

                pos += record_length;
            }

            const next_end: u32 = (sector_offset + 1) * bs;
            if (next_end > data_length) break;
            remaining = data_length - next_end;
            sector_offset += 1;
        }
    }

    /// Read the raw bytes of a file at the given extent location.
    /// The caller owns the returned memory.
    pub fn readFile(self: *const IsoReader, extent_location: u32, data_length: u32) IsoError![]u8 {
        const bs: u32 = self.volume.logical_block_size;
        if (data_length == 0) return &.{};

        const output = try self.allocator.alloc(u8, data_length);
        errdefer self.allocator.free(output);

        const sector_count = (data_length + bs - 1) / bs;
        var offset: usize = 0;

        for (0..sector_count) |i| {
            const sector = extent_location + @as(u32, @intCast(i));
            const remaining = data_length - @as(u32, @intCast(offset));
            const chunk_size = @min(remaining, bs);
            const buf = output[offset .. offset + @as(usize, chunk_size)];
            _ = try self.readSector(sector, buf);
            offset += @as(usize, chunk_size);
        }

        return output;
    }

    /// Find a single file entry by path (e.g., "DIR/FILE.EXT").
    /// Returns the DirectoryEntry if found, or `error.EntryNotFound`.
    pub fn findPath(self: *const IsoReader, path: []const u8) IsoError!types.DirectoryEntry {
        var parts = std.mem.splitScalar(u8, path, '/');

        // Start from root.
        var current_extent = self.volume.root_extent;
        var current_length = self.volume.root_length;

        while (parts.next()) |part| {
            if (part.len == 0) continue;
            const is_last = parts.peek() == null;

            var result: ?types.DirectoryEntry = null;

            try self.iterateDirectory(current_extent, current_length, struct {
                fn cb(entry: types.DirectoryEntry, ctx: ?*anyopaque) IsoError!IterateAction {
                    const data = @as(*struct { needle: []const u8, out: *?types.DirectoryEntry, is_last: bool }, @ptrCast(@alignCast(ctx.?)));
                    const normalized = if (entry.name.len == 1 and entry.name[0] == 0) "." else entry.name;
                    const normalized2 = if (entry.name.len == 1 and entry.name[0] == 1) ".." else normalized;

                    // Compare case-insensitively for robustness.
                    if (std.ascii.eqlIgnoreCase(normalized2, data.needle)) {
                        data.out.* = entry;
                        return .stop;
                    }

                    // Strip version number (;1) for matching.
                    if (std.mem.indexOfScalar(u8, entry.name, ';')) |semi| {
                        const base = entry.name[0..semi];
                        if (std.ascii.eqlIgnoreCase(base, data.needle)) {
                            data.out.* = entry;
                            return .stop;
                        }
                    }

                    return .cont;
                }
            }.cb, @as(?*anyopaque, @ptrCast(@constCast(&.{ .needle = part, .out = &result, .is_last = is_last }))));

            const entry = result orelse return error.EntryNotFound;

            if (!is_last) {
                if (!entry.is_directory) return error.EntryNotFound;
                current_extent = entry.extent_location;
                current_length = entry.data_length;
            } else {
                return entry;
            }
        }

        return error.EntryNotFound;
    }

    /// List the root directory entries.
    /// List the root directory entries. Allocates with `self.allocator`.
    /// The caller owns the returned slice.
    pub fn listRoot(self: *const IsoReader) IsoError![]types.DirectoryEntry {
        var list = std.ArrayListUnmanaged(types.DirectoryEntry){
            .items = self.allocator.alloc(types.DirectoryEntry, 0) catch return error.UnexpectedEof,
            .capacity = 0,
        };
        errdefer self.allocator.free(list.items);

        var sector_buf: [sector_size]u8 = undefined;
        _ = try self.readSector(self.volume.root_extent, &sector_buf);
        const end = @min(self.volume.root_length, @as(u32, @intCast(sector_buf.len)));
        const data = sector_buf[0..end];
        var pos: usize = 0;
        while (pos < data.len) {
            const record_length = data[pos];
            if (record_length == 0) break;
            const rec = try parseDirectoryRecord(data, pos);
            const entry = types.DirectoryEntry{
                .name = rec.file_identifier,
                .extent_location = rec.extent_location,
                .data_length = rec.data_length,
                .is_directory = rec.file_flags.directory,
                .recording_date_time = rec.recording_date_time,
                .file_flags = rec.file_flags,
            };
            list.append(self.allocator, entry) catch return error.UnexpectedEof;
            pos += record_length;
        }

        return list.toOwnedSlice(self.allocator) catch return error.UnexpectedEof;
    }
};

/// Parse the Primary Volume Descriptor (sector 16) from a raw ISO image.
pub fn parsePrimaryVolumeDescriptor(bytes: []const u8) IsoError!types.VolumeInfo {
    const sector_offset = primary_volume_sector * sector_size;
    if (sector_offset + sector_size > bytes.len) return error.UnexpectedEof;

    const sector = bytes[sector_offset .. sector_offset + sector_size];

    // Validate volume descriptor header.
    const type_byte = sector[0];
    if (type_byte != @intFromEnum(types.VolumeDescriptorType.primary)) {
        return error.BadVolumeDescriptorType;
    }
    const identifier = sector[1..6];
    if (!std.mem.eql(u8, identifier, types.iso_identifier)) {
        return error.InvalidIdentifier;
    }

    // System identifier (offset 8, 32 bytes)
    var sys_id: [32]u8 = .{0} ** 32;
    @memcpy(&sys_id, sector[8..40]);

    // Volume identifier (offset 40, 32 bytes)
    var vol_id: [32]u8 = .{0} ** 32;
    @memcpy(&vol_id, sector[40..72]);

    // Total sectors (offset 80, both-byte-order 4-byte)
    const total_sectors_le = readU32Le(sector, 80);
    const total_sectors_be = readU32Big(sector, 84);
    _ = total_sectors_be;

    // Logical block size (offset 128, both-byte-order 2-byte)
    const block_size_le = readU16Le(sector, 128);
    const block_size_be = readU16Big(sector, 130);
    _ = block_size_be;

    // Path table sizes / locations (offset 132)
    const l_path_table = readU32Le(sector, 140);
    const m_path_table = readU32Le(sector, 148);

    // Root directory record (offset 156, variable length — typically 34 bytes)
    const root_dir = try parseDirectoryRecord(sector, 156);

    // Volume set / publisher / preparer / application (offsets 190..446)
    var vol_set_id: [128]u8 = .{0} ** 128;
    @memcpy(&vol_set_id, sector[190..318]);
    var publisher_id: [128]u8 = .{0} ** 128;
    @memcpy(&publisher_id, sector[318..446]);
    var preparer_id: [128]u8 = .{0} ** 128;
    @memcpy(&preparer_id, sector[446..574]);
    var app_id: [128]u8 = .{0} ** 128;
    @memcpy(&app_id, sector[574..702]);

    // Date/time fields (offsets 813..830)
    const creation_date = parseVolumeDateTime(sector, 813);

    return types.VolumeInfo{
        .volume_identifier = vol_id,
        .total_sectors = total_sectors_le,
        .logical_block_size = @truncate(block_size_le),
        .root_extent = root_dir.extent_location,
        .root_length = root_dir.data_length,
        .l_path_table_location = l_path_table,
        .m_path_table_location = m_path_table,
        .creation_date = creation_date,
        .application_identifier = app_id,
        .publisher_identifier = publisher_id,
        .data_preparer_identifier = preparer_id,
        .volume_set_identifier = vol_set_id,
    };
}

/// Parse a directory record at a given position within a sector buffer.
pub fn parseDirectoryRecord(data: []const u8, pos: usize) IsoError!types.DirectoryRecord {
    if (pos + 33 > data.len) return error.BadDirectoryRecord;

    const record_length = data[pos];
    if (record_length < 33) return error.BadDirectoryRecord;

    const file_id_length = data[pos + 32];
    const total = @as(usize, record_length);
    if (pos + total > data.len) return error.BadDirectoryRecord;

    const extent_location = readU32Le(data, pos + 2);
    const data_length = readU32Le(data, pos + 10);
    const volume_seq = readU16Le(data, pos + 28);

    var flags: types.FileFlags = .{};
    @as(*u8, @ptrCast(&flags)).* = data[pos + 25];

    var dt: types.RecordingDateTime = .{};
    dt.years_since_1900 = data[pos + 18];
    dt.month = data[pos + 19];
    dt.day = data[pos + 20];
    dt.hour = data[pos + 21];
    dt.minute = data[pos + 22];
    dt.second = data[pos + 23];
    dt.gmt_offset = @as(i8, @bitCast(data[pos + 24]));

    const name_start = pos + 33;
    const name = data[name_start .. name_start + file_id_length];

    return types.DirectoryRecord{
        .length = record_length,
        .extended_attribute_length = data[pos + 1],
        .extent_location = extent_location,
        .data_length = data_length,
        .recording_date_time = dt,
        .file_flags = flags,
        .file_unit_size = data[pos + 26],
        .interleave_gap_size = data[pos + 27],
        .volume_sequence_number = volume_seq,
        .file_identifier_length = file_id_length,
        .file_identifier = name,
        .raw_offset = pos,
        .raw_length = record_length,
    };
}

/// Parse a 17-byte volume date/time field at the given offset.
pub fn parseVolumeDateTime(data: []const u8, pos: usize) types.VolumeDateTime {
    var dt: types.VolumeDateTime = undefined;
    if (pos + 17 > data.len) {
        @memset(@as(*[17]u8, @ptrCast(&dt)), 0);
        dt.gmt_offset = 0;
        return dt;
    }
    @memcpy(&dt.year, data[pos..][0..4]);
    @memcpy(&dt.month, data[pos + 4..][0..2]);
    @memcpy(&dt.day, data[pos + 6..][0..2]);
    @memcpy(&dt.hour, data[pos + 8..][0..2]);
    @memcpy(&dt.minute, data[pos + 10..][0..2]);
    @memcpy(&dt.second, data[pos + 12..][0..2]);
    @memcpy(&dt.hundredths, data[pos + 14..][0..2]);
    dt.gmt_offset = @as(i8, @bitCast(data[pos + 16]));
    return dt;
}

/// Find all volume descriptors in the ISO image (from sector 16 forward).
/// The caller owns the returned slice.
pub fn findAllVolumeDescriptors(allocator: std.mem.Allocator, bytes: []const u8) IsoError![]types.VolumeDescriptorType {
    var list = std.ArrayListUnmanaged(types.VolumeDescriptorType){
        .items = allocator.alloc(types.VolumeDescriptorType, 0) catch return error.UnexpectedEof,
        .capacity = 0,
    };
    errdefer list.deinit(allocator);

    var sector: usize = types.primary_volume_sector;
    while (true) {
        const offset = sector * sector_size;
        if (offset + 7 > bytes.len) break;
        const type_byte = bytes[offset];
        const descriptor_type: types.VolumeDescriptorType = @enumFromInt(type_byte);
        list.append(allocator, descriptor_type) catch return error.UnexpectedEof;
        if (descriptor_type == .set_terminator) break;
        sector += 1;
    }

    return list.toOwnedSlice(allocator) catch return error.UnexpectedEof;
}

fn readU16Le(data: []const u8, pos: usize) u16 {
    return @as(u16, data[pos]) | (@as(u16, data[pos + 1]) << 8);
}

fn readU16Big(data: []const u8, pos: usize) u16 {
    return @as(u16, data[pos + 1]) | (@as(u16, data[pos]) << 8);
}

fn readU32Le(data: []const u8, pos: usize) u32 {
    return @as(u32, data[pos]) |
        (@as(u32, data[pos + 1]) << 8) |
        (@as(u32, data[pos + 2]) << 16) |
        (@as(u32, data[pos + 3]) << 24);
}

fn readU32Big(data: []const u8, pos: usize) u32 {
    return @as(u32, data[pos + 3]) |
        (@as(u32, data[pos + 2]) << 8) |
        (@as(u32, data[pos + 1]) << 16) |
        (@as(u32, data[pos]) << 24);
}

fn writeU16Le(buf: []u8, pos: usize, val: u16) void {
    buf[pos] = @truncate(val);
    buf[pos + 1] = @truncate(val >> 8);
}

fn writeU32Le(buf: []u8, pos: usize, val: u32) void {
    buf[pos] = @truncate(val);
    buf[pos + 1] = @truncate(val >> 8);
    buf[pos + 2] = @truncate(val >> 16);
    buf[pos + 3] = @truncate(val >> 24);
}

const testing = std.testing;

fn isoBytes() []const u8 {
    // Build a minimal synthetic ISO 9660 image for testing.
    // Sector 16 = Primary Volume Descriptor.
    // Sector 17+ = Root directory data.
    const total_sectors: usize = 20;
    const img = std.heap.page_allocator.alloc(u8, total_sectors * sector_size) catch unreachable;
    @memset(img, 0);

    const pvd_off = 16 * sector_size;
    img[pvd_off] = 1; // primary
    @memcpy(img[pvd_off + 1 ..][0..5], "CD001");
    img[pvd_off + 6] = 1; // version

    // Volume identifier: "TEST_VOLUME"
    for ("TEST_VOLUME", 0..) |ch, i| {
        img[pvd_off + 40 + i] = @as(u8, ch);
    }
    // Total sectors = 20
    writeU32Le(img, pvd_off + 80, 20);
    img[pvd_off + 84] = 0;
    img[pvd_off + 85] = 0;
    img[pvd_off + 86] = 0;
    img[pvd_off + 87] = 0;
    // Block size = 2048
    writeU16Le(img, pvd_off + 128, 2048);
    img[pvd_off + 130] = 0x08;
    img[pvd_off + 131] = 0;

    // Root directory record at offset 156. Point to sector 17.
    img[pvd_off + 156] = 34; // length
    img[pvd_off + 157] = 0; // ext attr length
    writeU32Le(img, pvd_off + 158, 17); // extent location
    writeU32Le(img, pvd_off + 166, sector_size); // data length = 1 sector
    // date/time = 2024-01-01 12:00:00
    img[pvd_off + 174] = 124; // 1900 + 124 = 2024
    img[pvd_off + 175] = 1;
    img[pvd_off + 176] = 1;
    img[pvd_off + 177] = 12;
    img[pvd_off + 178] = 0;
    img[pvd_off + 179] = 0;
    img[pvd_off + 180] = 0; // gmt offset
    img[pvd_off + 181] = 2; // flags: directory
    img[pvd_off + 182] = 0; // file unit size
    img[pvd_off + 183] = 0; // interleave gap
    writeU16Le(img, pvd_off + 184, 1); // volume seq
    img[pvd_off + 186] = 1; // file id length = 1
    img[pvd_off + 187] = 0; // file id = 0 (meaning root '.')
    // pad to even
    img[pvd_off + 188] = 0;
    img[pvd_off + 189] = 0;

    // Write the volume descriptor set terminator at sector 19.
    const term_sector: usize = 19;
    const term_off = term_sector * sector_size;
    img[term_off] = 255; // set_terminator
    @memcpy(img[term_off + 1 ..][0..5], "CD001");
    img[term_off + 6] = 1;

    // Root directory data in sector 17. It contains . and .. entries.
    // The root record data area starts at sector 17.
    const root_off = 17 * sector_size;
    // Clear it.
    @memset(img[root_off .. root_off + sector_size], 0);

    // Entry for "." (current dir)
    // length 34, ext attr 0, extent=17, data=512, date/time, flags=dir, id=1 char
    img[root_off] = 34;
    img[root_off + 1] = 0;
    writeU32Le(img, root_off + 2, 17);
    writeU32Le(img, root_off + 10, sector_size);
    img[root_off + 18] = 124; // years from 1900
    img[root_off + 19] = 1;
    img[root_off + 20] = 1;
    img[root_off + 21] = 12;
    img[root_off + 22] = 0;
    img[root_off + 23] = 0;
    img[root_off + 24] = 0;
    img[root_off + 25] = 2; // directory flag
    img[root_off + 26] = 0;
    img[root_off + 27] = 0;
    writeU16Le(img, root_off + 28, 1);
    img[root_off + 32] = 1; // file id length = 1
    img[root_off + 33] = 0; // '.' encoded as single 0 byte
    // Entry for ".." (parent dir — same as root here)
    // Start at offset 34 (no padding needed since 34 is even)
    img[root_off + 34] = 34;
    img[root_off + 35] = 0;
    writeU32Le(img, root_off + 36, 17);
    writeU32Le(img, root_off + 44, sector_size);
    img[root_off + 52] = 124;
    img[root_off + 53] = 1;
    img[root_off + 54] = 1;
    img[root_off + 55] = 12;
    img[root_off + 56] = 0;
    img[root_off + 57] = 0;
    img[root_off + 58] = 0;
    img[root_off + 59] = 2;
    img[root_off + 60] = 0;
    img[root_off + 61] = 0;
    writeU16Le(img, root_off + 62, 1);
    img[root_off + 66] = 1; // file id length = 1
    img[root_off + 67] = 1; // '..' encoded as single 1 byte

    return img;
}


test "parse primary volume descriptor from synthetic image" {
    const img = isoBytes();
    defer std.heap.page_allocator.free(img);

    const info = try parsePrimaryVolumeDescriptor(img);
    const vol_id = std.mem.sliceTo(@as(*const [32]u8, &info.volume_identifier), 0);
    try testing.expectEqualStrings("TEST_VOLUME", vol_id);
    try testing.expectEqual(@as(u16, 2048), info.logical_block_size);
    try testing.expectEqual(@as(u32, 20), info.total_sectors);
    try testing.expectEqual(@as(u32, 17), info.root_extent);
}

test "IsoReader list root directory entries" {
    const img = isoBytes();
    defer std.heap.page_allocator.free(img);

    var reader = try IsoReader.open(testing.allocator, img);
    const entries = try reader.listRoot();
    defer testing.allocator.free(entries);

    // Should have at least "." and ".."
    try testing.expect(entries.len >= 2);
    // First entry: file id 0 = "."
    try testing.expect(entries[0].is_directory);
    // Second entry: file id 1 = ".."
    try testing.expect(entries[1].is_directory);
}

test "IsoReader find path returns root" {
    const img = isoBytes();
    defer std.heap.page_allocator.free(img);

    var reader = try IsoReader.open(testing.allocator, img);
    const entry = try reader.findPath(".");
    try testing.expect(entry.is_directory);
}

test "findAllVolumeDescriptors discovers set terminator" {
    const img = isoBytes();
    defer std.heap.page_allocator.free(img);

    const descriptors = try findAllVolumeDescriptors(testing.allocator, img);
    defer testing.allocator.free(descriptors);

    // Primary (1) + set_terminator (255) = 2 descriptors.
    try testing.expect(descriptors.len >= 2);
    try testing.expectEqual(types.VolumeDescriptorType.primary, descriptors[0]);
    try testing.expectEqual(types.VolumeDescriptorType.set_terminator, descriptors[descriptors.len - 1]);
}
