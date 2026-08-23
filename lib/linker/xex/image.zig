//! Xbox 360 XEX2 image reading.
//!
//! A XEX2 file is a header, a directory of optional headers, a security block,
//! and a "basefile" that is the actual PE image. Everything in it is big-endian
//! and everything is offset-addressed, which makes it a format where a wrong
//! read produces a plausible number rather than a parse error: an offset read
//! little-endian is still an offset, it just points somewhere else.
//!
//! So every accessor here is bounds-checked against the file it came from and
//! returns an error rather than a value it could not verify. `null` means the
//! header is absent, which is normal; an error means the file says something
//! that is not true about itself, which is not.
//!
//! ## What this reads and what it does not
//!
//! It reads the header directory, the security block, the import libraries, and
//! the section layout, and it can map an image whose basefile is plaintext -
//! uncompressed or "basic" compressed, which is a run-length encoding of zero
//! fill and nothing more.
//!
//! It does not decrypt and it does not implement the LZX-based "normal"
//! compression. Those are reported by `basefileFormat` so a caller knows
//! exactly what it is holding; decryption in particular needs key material that
//! belongs to whoever owns the image, not to a loader.

const std = @import("std");

pub const Error = error{
    /// The file does not start with 'XEX2'.
    NotXex2,
    /// A structure claims to extend past the end of the file.
    Truncated,
    /// A field holds a value the format does not allow.
    Malformed,
    /// The basefile needs a transformation this reader does not perform.
    UnsupportedFormat,
    OutOfMemory,
};

pub const magic: u32 = 0x58455832; // 'XEX2'

/// Optional-header keys. The low byte encodes how the value is carried: 0x00
/// and 0x01 mean the value is inline, anything else means it is an offset to a
/// structure. Reading an inline value as an offset is the classic XEX parsing
/// bug and is why `OptionalHeader.isInline` exists rather than each caller
/// deciding.
pub const HeaderKey = struct {
    pub const resource_info: u32 = 0x000002FF;
    pub const file_format_info: u32 = 0x000003FF;
    pub const delta_patch_descriptor: u32 = 0x000005FF;
    pub const base_reference: u32 = 0x00000405;
    pub const bounding_path: u32 = 0x000080FF;
    pub const device_id: u32 = 0x00008105;
    pub const original_base_address: u32 = 0x00010001;
    pub const entry_point: u32 = 0x00010100;
    pub const image_base_address: u32 = 0x00010201;
    pub const import_libraries: u32 = 0x000103FF;
    pub const checksum_timestamp: u32 = 0x00018002;
    pub const original_pe_name: u32 = 0x000183FF;
    pub const static_libraries: u32 = 0x000200FF;
    pub const tls_info: u32 = 0x00020104;
    pub const default_stack_size: u32 = 0x00020200;
    pub const default_filesystem_cache_size: u32 = 0x00020301;
    pub const default_heap_size: u32 = 0x00020401;
    pub const page_heap_size_and_flags: u32 = 0x00028002;
    pub const system_flags: u32 = 0x00030000;
    pub const execution_info: u32 = 0x00040006;
    pub const title_workspace_size: u32 = 0x00040201;
    pub const game_ratings: u32 = 0x00040310;
    pub const lan_key: u32 = 0x00040404;
    pub const multidisc_media_ids: u32 = 0x000406FF;
    pub const alternate_title_ids: u32 = 0x000407FF;
    pub const additional_title_memory: u32 = 0x00040801;
    pub const exports_by_name: u32 = 0x00E10402;
};

pub const ModuleFlags = struct {
    pub const title: u32 = 0x00000001;
    pub const exports_to_title: u32 = 0x00000002;
    pub const system_debugger: u32 = 0x00000004;
    pub const dll_module: u32 = 0x00000008;
    pub const module_patch: u32 = 0x00000010;
    pub const patch_full: u32 = 0x00000020;
    pub const patch_delta: u32 = 0x00000040;
    pub const user_mode: u32 = 0x00000080;
};

pub const Encryption = enum(u16) {
    none = 0,
    normal = 1,
    _,
};

pub const Compression = enum(u16) {
    none = 0,
    /// A list of (data, zero) block lengths: copy `data` bytes, then emit
    /// `zero` zeros. Not a compressor - a description of where the image's
    /// zero-fill went.
    basic = 1,
    /// LZX. Not implemented here.
    normal = 2,
    delta = 3,
    _,
};

pub const SectionType = enum(u4) {
    code = 1,
    data = 2,
    readonly_data = 3,
    _,
};

/// One entry in the optional-header directory.
pub const OptionalHeader = struct {
    key: u32,
    /// Either the value itself or an offset into the file, per `isInline`.
    data: u32,

    /// True when the low byte of the key says the value is carried inline.
    pub fn isInline(self: OptionalHeader) bool {
        const low: u8 = @truncate(self.key);
        return low == 0x00 or low == 0x01;
    }

    /// The number of 32-bit words carried inline, when the value is inline.
    pub fn inlineWordCount(self: OptionalHeader) u8 {
        return @truncate(self.key);
    }
};

/// One page descriptor from the security block: how many pages of one section
/// type follow.
pub const PageDescriptor = struct {
    section_type: SectionType,
    page_count: u32,
};

/// One import library: which module, which version, and how many thunks.
pub const ImportLibrary = struct {
    name: []const u8,
    id: u32,
    version: u32,
    min_version: u32,
    /// Guest addresses of the import records for this library.
    records: []const u32,
};

pub const ExecutionInfo = struct {
    media_id: u32,
    version: u32,
    base_version: u32,
    title_id: u32,
    platform: u8,
    executable_table: u8,
    disc_number: u8,
    disc_count: u8,
    savegame_id: u32,
};

pub const BasefileFormat = struct {
    encryption: Encryption,
    compression: Compression,

    /// True when the basefile can be mapped without a key or a decompressor.
    pub fn isPlain(self: BasefileFormat) bool {
        return self.encryption == .none and
            (self.compression == .none or self.compression == .basic);
    }
};

/// A XEX2 file, borrowed rather than owned.
pub const Image = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) Error!Image {
        if (bytes.len < 0x18) return Error.Truncated;
        const image = Image{ .bytes = bytes };
        if (try image.readU32(0) != magic) return Error.NotXex2;
        // The header size and the basefile offset are the same field: the
        // basefile begins where the headers end.
        const header_size = try image.readU32(0x08);
        if (header_size > bytes.len) return Error.Truncated;
        const count = try image.readU32(0x14);
        // Each directory entry is eight bytes and they start at 0x18.
        const directory_end = 0x18 + @as(u64, count) * 8;
        if (directory_end > bytes.len) return Error.Truncated;
        return image;
    }

    fn readU32(self: Image, offset: u64) Error!u32 {
        if (offset + 4 > self.bytes.len) return Error.Truncated;
        return std.mem.readInt(u32, self.bytes[@intCast(offset)..][0..4], .big);
    }

    fn readU16(self: Image, offset: u64) Error!u16 {
        if (offset + 2 > self.bytes.len) return Error.Truncated;
        return std.mem.readInt(u16, self.bytes[@intCast(offset)..][0..2], .big);
    }

    fn readU8(self: Image, offset: u64) Error!u8 {
        if (offset >= self.bytes.len) return Error.Truncated;
        return self.bytes[@intCast(offset)];
    }

    pub fn moduleFlags(self: Image) Error!u32 {
        return self.readU32(0x04);
    }

    /// Where the headers end and the basefile begins.
    pub fn basefileOffset(self: Image) Error!u32 {
        return self.readU32(0x08);
    }

    pub fn securityOffset(self: Image) Error!u32 {
        return self.readU32(0x10);
    }

    pub fn headerCount(self: Image) Error!u32 {
        return self.readU32(0x14);
    }

    /// The optional header at directory index `index`.
    pub fn optionalHeader(self: Image, index: u32) Error!OptionalHeader {
        const count = try self.headerCount();
        if (index >= count) return Error.Malformed;
        const at = 0x18 + @as(u64, index) * 8;
        return .{
            .key = try self.readU32(at),
            .data = try self.readU32(at + 4),
        };
    }

    /// Find an optional header by key, or null when the image does not carry it.
    pub fn findHeader(self: Image, key: u32) Error!?OptionalHeader {
        const count = try self.headerCount();
        var index: u32 = 0;
        while (index < count) : (index += 1) {
            const header = try self.optionalHeader(index);
            if (header.key == key) return header;
        }
        return null;
    }

    /// The value of an inline optional header, or null when it is absent.
    ///
    /// Returns an error when the header exists but carries an offset: reading
    /// an offset as a value is how a loader ends up with an entry point of
    /// 0x1234 instead of 0x82000000.
    pub fn inlineValue(self: Image, key: u32) Error!?u32 {
        const header = (try self.findHeader(key)) orelse return null;
        if (!header.isInline()) return Error.Malformed;
        return header.data;
    }

    pub fn entryPoint(self: Image) Error!?u32 {
        return self.inlineValue(HeaderKey.entry_point);
    }

    pub fn imageBaseAddress(self: Image) Error!?u32 {
        return self.inlineValue(HeaderKey.image_base_address);
    }

    pub fn originalBaseAddress(self: Image) Error!?u32 {
        return self.inlineValue(HeaderKey.original_base_address);
    }

    pub fn defaultStackSize(self: Image) Error!?u32 {
        return self.inlineValue(HeaderKey.default_stack_size);
    }

    pub fn defaultHeapSize(self: Image) Error!?u32 {
        return self.inlineValue(HeaderKey.default_heap_size);
    }

    pub fn systemFlags(self: Image) Error!?u32 {
        return self.inlineValue(HeaderKey.system_flags);
    }

    // -- security block ---------------------------------------------------

    pub fn imageSize(self: Image) Error!u32 {
        return self.readU32(@as(u64, try self.securityOffset()) + 0x04);
    }

    pub fn imageFlags(self: Image) Error!u32 {
        return self.readU32(@as(u64, try self.securityOffset()) + 0x10C);
    }

    pub fn loadAddress(self: Image) Error!u32 {
        return self.readU32(@as(u64, try self.securityOffset()) + 0x110);
    }

    pub fn importTableCount(self: Image) Error!u32 {
        return self.readU32(@as(u64, try self.securityOffset()) + 0x128);
    }

    pub fn exportTableAddress(self: Image) Error!u32 {
        return self.readU32(@as(u64, try self.securityOffset()) + 0x160);
    }

    pub fn pageDescriptorCount(self: Image) Error!u32 {
        return self.readU32(@as(u64, try self.securityOffset()) + 0x180);
    }

    /// The page descriptor at `index`. Each is a packed word plus a 20-byte
    /// digest, so they are 24 bytes apart.
    pub fn pageDescriptor(self: Image, index: u32) Error!PageDescriptor {
        const count = try self.pageDescriptorCount();
        if (index >= count) return Error.Malformed;
        const at = @as(u64, try self.securityOffset()) + 0x184 + @as(u64, index) * 24;
        const packed_value = try self.readU32(at);
        return .{
            // The section type is the *low* four bits and the page count is the
            // rest: the field is stored as a bitfield, not as two words.
            .section_type = @enumFromInt(@as(u4, @truncate(packed_value))),
            .page_count = packed_value >> 4,
        };
    }

    // -- basefile format ---------------------------------------------------

    pub fn basefileFormat(self: Image) Error!BasefileFormat {
        const header = (try self.findHeader(HeaderKey.file_format_info)) orelse {
            // No format header at all means a plaintext, uncompressed image.
            return .{ .encryption = .none, .compression = .none };
        };
        if (header.isInline()) return Error.Malformed;
        const at: u64 = header.data;
        return .{
            .encryption = @enumFromInt(try self.readU16(at + 4)),
            .compression = @enumFromInt(try self.readU16(at + 6)),
        };
    }

    /// The (data, zero) block list of a basic-compressed basefile.
    pub fn basicCompressionBlockCount(self: Image) Error!u32 {
        const header = (try self.findHeader(HeaderKey.file_format_info)) orelse
            return 0;
        if (header.isInline()) return Error.Malformed;
        const info_size = try self.readU32(header.data);
        if (info_size < 8) return Error.Malformed;
        return (info_size - 8) / 8;
    }

    pub fn basicCompressionBlock(self: Image, index: u32) Error!struct {
        data_size: u32,
        zero_size: u32,
    } {
        const header = (try self.findHeader(HeaderKey.file_format_info)) orelse
            return Error.Malformed;
        const at = @as(u64, header.data) + 8 + @as(u64, index) * 8;
        return .{
            .data_size = try self.readU32(at),
            .zero_size = try self.readU32(at + 4),
        };
    }

    // -- imports -----------------------------------------------------------

    /// How many import libraries the image names.
    pub fn importLibraryCount(self: Image) Error!u32 {
        const header = (try self.findHeader(HeaderKey.import_libraries)) orelse
            return 0;
        if (header.isInline()) return Error.Malformed;
        return self.readU32(@as(u64, header.data) + 8);
    }

    /// Read import library `index` into caller-owned storage.
    ///
    /// The library records follow a string table whose length has to be read
    /// first; walking them requires stepping through every preceding library,
    /// because each carries its own size. That is why this takes an index and
    /// not a pointer.
    pub fn importLibrary(
        self: Image,
        allocator: std.mem.Allocator,
        index: u32,
    ) Error!ImportLibrary {
        const header = (try self.findHeader(HeaderKey.import_libraries)) orelse
            return Error.Malformed;
        if (header.isInline()) return Error.Malformed;
        const base: u64 = header.data;
        const string_table_size = try self.readU32(base + 4);
        const count = try self.readU32(base + 8);
        if (index >= count) return Error.Malformed;

        // Library records start after the string table.
        var at: u64 = base + 12 + string_table_size;
        var walked: u32 = 0;
        while (walked < index) : (walked += 1) {
            const size = try self.readU32(at);
            if (size == 0) return Error.Malformed;
            at += size;
        }

        const name_index = try self.readU16(at + 0x24);
        const record_count = try self.readU16(at + 0x26);
        const records = try allocator.alloc(u32, record_count);
        errdefer allocator.free(records);
        for (records, 0..) |*record, i| {
            record.* = try self.readU32(at + 0x28 + @as(u64, i) * 4);
        }

        return .{
            .name = try self.stringTableEntry(base + 12, string_table_size, name_index),
            .id = try self.readU32(at + 0x18),
            .version = try self.readU32(at + 0x1C),
            .min_version = try self.readU32(at + 0x20),
            .records = records,
        };
    }

    /// The `index`th NUL-terminated name in the import string table.
    fn stringTableEntry(
        self: Image,
        table_at: u64,
        table_size: u32,
        index: u16,
    ) Error![]const u8 {
        if (table_at + table_size > self.bytes.len) return Error.Truncated;
        const table = self.bytes[@intCast(table_at)..][0..table_size];
        var start: usize = 0;
        var seen: u16 = 0;
        while (start < table.len) {
            const end = std.mem.indexOfScalarPos(u8, table, start, 0) orelse table.len;
            if (seen == index) return table[start..end];
            seen += 1;
            start = end + 1;
            // The table is padded with NULs; a run of them ends it.
            while (start < table.len and table[start] == 0) start += 1;
        }
        return Error.Malformed;
    }

    // -- execution info ------------------------------------------------------

    pub fn executionInfo(self: Image) Error!?ExecutionInfo {
        const header = (try self.findHeader(HeaderKey.execution_info)) orelse
            return null;
        if (header.isInline()) return Error.Malformed;
        const at: u64 = header.data;
        return .{
            .media_id = try self.readU32(at),
            .version = try self.readU32(at + 4),
            .base_version = try self.readU32(at + 8),
            .title_id = try self.readU32(at + 12),
            .platform = try self.readU8(at + 16),
            .executable_table = try self.readU8(at + 17),
            .disc_number = try self.readU8(at + 18),
            .disc_count = try self.readU8(at + 19),
            .savegame_id = try self.readU32(at + 20),
        };
    }

    // -- mapping ---------------------------------------------------------------

    /// Expand the basefile into `out`, which the caller sizes to `imageSize()`.
    ///
    /// Only a plaintext basefile can be mapped: an encrypted or LZX-compressed
    /// one is refused by name rather than copied through and left to produce
    /// instructions that decode to nonsense.
    pub fn mapBasefile(self: Image, out: []u8) Error!usize {
        const format = try self.basefileFormat();
        if (!format.isPlain()) return Error.UnsupportedFormat;

        const start = try self.basefileOffset();
        if (start > self.bytes.len) return Error.Truncated;
        const source = self.bytes[start..];

        if (format.compression == .none) {
            const length = @min(source.len, out.len);
            @memcpy(out[0..length], source[0..length]);
            if (out.len > length) @memset(out[length..], 0);
            return length;
        }

        // Basic compression: alternate a run of bytes with a run of zeros.
        var read: usize = 0;
        var written: usize = 0;
        const blocks = try self.basicCompressionBlockCount();
        var index: u32 = 0;
        while (index < blocks) : (index += 1) {
            const block = try self.basicCompressionBlock(index);
            if (read + block.data_size > source.len) return Error.Truncated;
            if (written + block.data_size + block.zero_size > out.len) {
                return Error.Truncated;
            }
            @memcpy(out[written..][0..block.data_size], source[read..][0..block.data_size]);
            read += block.data_size;
            written += block.data_size;
            @memset(out[written..][0..block.zero_size], 0);
            written += block.zero_size;
        }
        if (out.len > written) @memset(out[written..], 0);
        return written;
    }
};

// ---------------------------------------------------------------------------
// Tests
//
// Every test builds its own XEX2 in memory. A synthetic image is the only way
// to test a loader's error paths - a real one is well-formed by construction,
// so it exercises exactly the branches that were never going to be wrong.
// ---------------------------------------------------------------------------

const testing = std.testing;

const Builder = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Builder {
        return .{ .buffer = .empty, .allocator = allocator };
    }

    fn deinit(self: *Builder) void {
        self.buffer.deinit(self.allocator);
    }

    fn putU32(self: *Builder, at: usize, value: u32) !void {
        while (self.buffer.items.len < at + 4) try self.buffer.append(self.allocator, 0);
        std.mem.writeInt(u32, self.buffer.items[at..][0..4], value, .big);
    }

    fn putU16(self: *Builder, at: usize, value: u16) !void {
        while (self.buffer.items.len < at + 2) try self.buffer.append(self.allocator, 0);
        std.mem.writeInt(u16, self.buffer.items[at..][0..2], value, .big);
    }

    fn putBytes(self: *Builder, at: usize, data: []const u8) !void {
        while (self.buffer.items.len < at + data.len) try self.buffer.append(self.allocator, 0);
        @memcpy(self.buffer.items[at..][0..data.len], data);
    }
};

/// Build a minimal well-formed XEX2 with the given optional headers.
fn buildImage(
    allocator: std.mem.Allocator,
    headers: []const OptionalHeader,
    basefile_offset: u32,
    security_offset: u32,
) !std.ArrayList(u8) {
    var b = Builder.init(allocator);
    errdefer b.deinit();
    try b.putU32(0x00, magic);
    try b.putU32(0x04, ModuleFlags.title | ModuleFlags.user_mode);
    try b.putU32(0x08, basefile_offset);
    try b.putU32(0x0C, 0);
    try b.putU32(0x10, security_offset);
    try b.putU32(0x14, @intCast(headers.len));
    for (headers, 0..) |header, i| {
        try b.putU32(0x18 + i * 8, header.key);
        try b.putU32(0x18 + i * 8 + 4, header.data);
    }
    // A security block big enough to read every field this reader exposes.
    try b.putU32(security_offset + 0x00, 0x184);
    try b.putU32(security_offset + 0x04, 0x1000); // image size
    try b.putU32(security_offset + 0x10C, 0); // image flags
    try b.putU32(security_offset + 0x110, 0x82000000); // load address
    try b.putU32(security_offset + 0x128, 1); // import table count
    try b.putU32(security_offset + 0x160, 0x82001000); // export table
    try b.putU32(security_offset + 0x180, 0); // page descriptor count
    // The file has to be at least as long as it says its headers are, or
    // `parse` rightly refuses it as truncated.
    while (b.buffer.items.len < basefile_offset) {
        try b.buffer.append(allocator, 0);
    }
    return b.buffer;
}

test "a file that is not a XEX2 is refused by magic" {
    const bytes = [_]u8{0} ** 64;
    try testing.expectError(Error.NotXex2, Image.parse(&bytes));
}

test "a truncated file is refused rather than read past its end" {
    var short = [_]u8{ 'X', 'E', 'X', '2' } ++ [_]u8{0} ** 8;
    try testing.expectError(Error.Truncated, Image.parse(&short));
}

test "a header directory that runs past the file is refused" {
    var bytes = try buildImage(testing.allocator, &.{}, 0x100, 0x40);
    defer bytes.deinit(testing.allocator);
    // Claim far more headers than the file can hold.
    std.mem.writeInt(u32, bytes.items[0x14..][0..4], 10_000, .big);
    try testing.expectError(Error.Truncated, Image.parse(bytes.items));
}

test "the header directory is walkable and searchable" {
    var bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.entry_point, .data = 0x82012345 },
        .{ .key = HeaderKey.image_base_address, .data = 0x82000000 },
        .{ .key = HeaderKey.default_stack_size, .data = 0x40000 },
    }, 0x400, 0x100);
    defer bytes.deinit(testing.allocator);

    const image = try Image.parse(bytes.items);
    try testing.expectEqual(@as(u32, 3), try image.headerCount());
    try testing.expectEqual(@as(?u32, 0x82012345), try image.entryPoint());
    try testing.expectEqual(@as(?u32, 0x82000000), try image.imageBaseAddress());
    try testing.expectEqual(@as(?u32, 0x40000), try image.defaultStackSize());
    // A header the image does not carry is absent, not an error.
    try testing.expectEqual(@as(?u32, null), try image.defaultHeapSize());
}

test "an inline value and an offset value are told apart by the key" {
    // The low byte of the key says how the value is carried.
    const inline_header = OptionalHeader{ .key = HeaderKey.entry_point, .data = 5 };
    try testing.expect(inline_header.isInline());
    const offset_header = OptionalHeader{ .key = HeaderKey.import_libraries, .data = 5 };
    try testing.expect(!offset_header.isInline());
}

test "reading an offset header as an inline value is refused" {
    var bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.import_libraries, .data = 0x200 },
    }, 0x400, 0x100);
    defer bytes.deinit(testing.allocator);
    const image = try Image.parse(bytes.items);
    // Returning 0x200 here would give a loader an entry point inside the
    // headers instead of an error.
    try testing.expectError(
        Error.Malformed,
        image.inlineValue(HeaderKey.import_libraries),
    );
}

test "the security block reports the load address and image size" {
    var bytes = try buildImage(testing.allocator, &.{}, 0x400, 0x100);
    defer bytes.deinit(testing.allocator);
    const image = try Image.parse(bytes.items);
    try testing.expectEqual(@as(u32, 0x1000), try image.imageSize());
    try testing.expectEqual(@as(u32, 0x82000000), try image.loadAddress());
    try testing.expectEqual(@as(u32, 1), try image.importTableCount());
    try testing.expectEqual(@as(u32, 0x82001000), try image.exportTableAddress());
}

test "a page descriptor splits its packed word into type and count" {
    const bytes = try buildImage(testing.allocator, &.{}, 0x400, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();
    try b.putU32(0x100 + 0x180, 2);
    // Section type 1 (code), 7 pages.
    try b.putU32(0x100 + 0x184, (7 << 4) | 1);
    // Section type 2 (data), 3 pages.
    try b.putU32(0x100 + 0x184 + 24, (3 << 4) | 2);

    const image = try Image.parse(b.buffer.items);
    try testing.expectEqual(@as(u32, 2), try image.pageDescriptorCount());
    const first = try image.pageDescriptor(0);
    try testing.expectEqual(SectionType.code, first.section_type);
    try testing.expectEqual(@as(u32, 7), first.page_count);
    const second = try image.pageDescriptor(1);
    try testing.expectEqual(SectionType.data, second.section_type);
    try testing.expectEqual(@as(u32, 3), second.page_count);
    // An index past the end is refused rather than read.
    try testing.expectError(Error.Malformed, image.pageDescriptor(2));
}

test "an image with no format header is plaintext and uncompressed" {
    var bytes = try buildImage(testing.allocator, &.{}, 0x400, 0x100);
    defer bytes.deinit(testing.allocator);
    const image = try Image.parse(bytes.items);
    const format = try image.basefileFormat();
    try testing.expectEqual(Encryption.none, format.encryption);
    try testing.expectEqual(Compression.none, format.compression);
    try testing.expect(format.isPlain());
}

test "an encrypted or LZX image is named, not mapped" {
    const bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.file_format_info, .data = 0x300 },
    }, 0x400, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();
    try b.putU32(0x300, 8);
    try b.putU16(0x300 + 4, @intFromEnum(Encryption.normal));
    try b.putU16(0x300 + 6, @intFromEnum(Compression.normal));

    const image = try Image.parse(b.buffer.items);
    const format = try image.basefileFormat();
    try testing.expectEqual(Encryption.normal, format.encryption);
    try testing.expectEqual(Compression.normal, format.compression);
    try testing.expect(!format.isPlain());

    var out: [0x1000]u8 = undefined;
    // Copying an encrypted basefile through would produce instructions that
    // decode to nonsense somewhere deep in the run.
    try testing.expectError(Error.UnsupportedFormat, image.mapBasefile(&out));
}

test "an uncompressed basefile maps byte for byte" {
    // The basefile starts after the security block, and the file ends where the
    // basefile ends: "everything after the headers" is what a basefile *is*.
    const bytes = try buildImage(testing.allocator, &.{}, 0x400, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();
    try b.putBytes(0x400, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02 });
    b.buffer.shrinkRetainingCapacity(0x406);

    const image = try Image.parse(b.buffer.items);
    var out: [16]u8 = [_]u8{0xFF} ** 16;
    const written = try image.mapBasefile(&out);
    try testing.expectEqual(@as(usize, 6), written);
    try testing.expectEqualSlices(u8, &.{ 0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02 }, out[0..6]);
    // The tail is zeroed, not left holding whatever was in the buffer.
    try testing.expectEqual(@as(u8, 0), out[6]);
}

test "a basic-compressed basefile expands its zero runs" {
    const bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.file_format_info, .data = 0x300 },
    }, 0x400, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();
    // Two blocks: 2 bytes then 3 zeros, then 3 bytes then 1 zero.
    try b.putU32(0x300, 8 + 16); // info_size
    try b.putU16(0x300 + 4, @intFromEnum(Encryption.none));
    try b.putU16(0x300 + 6, @intFromEnum(Compression.basic));
    try b.putU32(0x300 + 8, 2);
    try b.putU32(0x300 + 12, 3);
    try b.putU32(0x300 + 16, 3);
    try b.putU32(0x300 + 20, 1);
    try b.putBytes(0x400, &[_]u8{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE });
    b.buffer.shrinkRetainingCapacity(0x405);

    const image = try Image.parse(b.buffer.items);
    try testing.expectEqual(@as(u32, 2), try image.basicCompressionBlockCount());

    var out: [16]u8 = [_]u8{0xFF} ** 16;
    const written = try image.mapBasefile(&out);
    try testing.expectEqual(@as(usize, 9), written);
    try testing.expectEqualSlices(
        u8,
        &.{ 0xAA, 0xBB, 0x00, 0x00, 0x00, 0xCC, 0xDD, 0xEE, 0x00 },
        out[0..9],
    );
}

test "a basic block that overruns the output is refused" {
    const bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.file_format_info, .data = 0x300 },
    }, 0x400, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();
    try b.putU32(0x300, 8 + 8);
    try b.putU16(0x300 + 6, @intFromEnum(Compression.basic));
    try b.putU32(0x300 + 8, 2);
    try b.putU32(0x300 + 12, 1_000_000); // a zero run larger than any buffer
    try b.putBytes(0x400, &[_]u8{ 0xAA, 0xBB });

    const image = try Image.parse(b.buffer.items);
    var out: [16]u8 = undefined;
    try testing.expectError(Error.Truncated, image.mapBasefile(&out));
}

test "import libraries are read with their names and thunk records" {
    const bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.import_libraries, .data = 0x300 },
    }, 0x800, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();

    const names = "xboxkrnl.exe\x00xam.xex\x00";
    const string_table_size: u32 = @intCast(names.len);
    try b.putU32(0x300, 0); // total size, unused by this reader
    try b.putU32(0x304, string_table_size);
    try b.putU32(0x308, 2); // library count
    try b.putBytes(0x30C, names);

    const first = 0x30C + string_table_size;
    try b.putU32(first + 0x00, 0x28 + 8); // record size
    try b.putU32(first + 0x18, 0x11223344); // id
    try b.putU32(first + 0x1C, 0x0A0B0C0D); // version
    try b.putU32(first + 0x20, 0x01020304); // min version
    try b.putU16(first + 0x24, 0); // name index -> xboxkrnl.exe
    try b.putU16(first + 0x26, 2); // two records
    try b.putU32(first + 0x28, 0x82010000);
    try b.putU32(first + 0x2C, 0x82010004);

    const second = first + 0x28 + 8;
    try b.putU32(second + 0x00, 0x28 + 4);
    try b.putU32(second + 0x18, 0x55667788);
    try b.putU16(second + 0x24, 1); // name index -> xam.xex
    try b.putU16(second + 0x26, 1);
    try b.putU32(second + 0x28, 0x82020000);

    const image = try Image.parse(b.buffer.items);
    try testing.expectEqual(@as(u32, 2), try image.importLibraryCount());

    const kernel = try image.importLibrary(testing.allocator, 0);
    defer testing.allocator.free(kernel.records);
    try testing.expectEqualStrings("xboxkrnl.exe", kernel.name);
    try testing.expectEqual(@as(u32, 0x11223344), kernel.id);
    try testing.expectEqual(@as(u32, 0x0A0B0C0D), kernel.version);
    try testing.expectEqual(@as(usize, 2), kernel.records.len);
    try testing.expectEqual(@as(u32, 0x82010000), kernel.records[0]);

    // The second library is reached by walking the first's declared size; a
    // reader that assumed a fixed record size would land in the middle of it.
    const xam = try image.importLibrary(testing.allocator, 1);
    defer testing.allocator.free(xam.records);
    try testing.expectEqualStrings("xam.xex", xam.name);
    try testing.expectEqual(@as(u32, 0x55667788), xam.id);
    try testing.expectEqual(@as(usize, 1), xam.records.len);

    try testing.expectError(
        Error.Malformed,
        image.importLibrary(testing.allocator, 2),
    );
}

test "execution info carries the title and media identity" {
    const bytes = try buildImage(testing.allocator, &.{
        .{ .key = HeaderKey.execution_info, .data = 0x280 },
    }, 0x400, 0x100);
    var b = Builder{ .buffer = bytes, .allocator = testing.allocator };
    defer b.deinit();
    try b.putU32(0x280 + 0x00, 0xAABBCCDD); // media id
    try b.putU32(0x280 + 0x0C, 0x4D5307E6); // title id
    try b.putBytes(0x280 + 0x12, &[_]u8{ 1, 2 }); // disc 1 of 2

    const image = try Image.parse(b.buffer.items);
    const info = (try image.executionInfo()).?;
    try testing.expectEqual(@as(u32, 0xAABBCCDD), info.media_id);
    try testing.expectEqual(@as(u32, 0x4D5307E6), info.title_id);
    try testing.expectEqual(@as(u8, 1), info.disc_number);
    try testing.expectEqual(@as(u8, 2), info.disc_count);
}

test "module flags describe what kind of image it is" {
    var bytes = try buildImage(testing.allocator, &.{}, 0x400, 0x100);
    defer bytes.deinit(testing.allocator);
    const image = try Image.parse(bytes.items);
    const flags = try image.moduleFlags();
    try testing.expect(flags & ModuleFlags.title != 0);
    try testing.expect(flags & ModuleFlags.user_mode != 0);
    try testing.expect(flags & ModuleFlags.dll_module == 0);
}
