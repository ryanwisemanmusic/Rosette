const std = @import("std");
const fmt = @import("../pe_format.zig");
const parser = @import("../pe_parser.zig");

pub const ImportKind = enum {
    name,
    ordinal,
};

pub const ImportDescriptor = struct {
    dll_name: []const u8,
    function_name: []const u8,
    iat_rva: u32,
    ordinal: ?u16 = null,
    kind: ImportKind = .name,
};

pub const ImportDirectory = struct {
    descriptors: []ImportDescriptor,
    pointer_size: u8,

    pub fn deinit(self: *ImportDirectory, allocator: std.mem.Allocator) void {
        // The no-import fallback used by the bounded PE runner is a static
        // empty slice, not an allocation owned by this directory.
        if (self.descriptors.len == 0) {
            self.* = .{ .descriptors = &.{}, .pointer_size = 0 };
            return;
        }
        for (self.descriptors) |descriptor| {
            allocator.free(descriptor.dll_name);
            allocator.free(descriptor.function_name);
        }
        allocator.free(self.descriptors);
        self.* = .{ .descriptors = &.{}, .pointer_size = 0 };
    }
};

pub const ParseError = error{
    ImportDirectoryNotFound,
    TruncatedImportTable,
    InvalidImportTable,
    UnterminatedImportString,
    RvaResolutionFailed,
    OutOfMemory,
};

fn readU16(bytes: []const u8, offset: usize) ParseError!u16 {
    if (offset > bytes.len or bytes.len - offset < 2) return error.TruncatedImportTable;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32(bytes: []const u8, offset: usize) ParseError!u32 {
    if (offset > bytes.len or bytes.len - offset < 4) return error.TruncatedImportTable;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn readU64(bytes: []const u8, offset: usize) ParseError!u64 {
    if (offset > bytes.len or bytes.len - offset < 8) return error.TruncatedImportTable;
    return @as(u64, try readU32(bytes, offset)) |
        (@as(u64, try readU32(bytes, offset + 4)) << 32);
}

fn rvaToOffset(image: *const parser.Image, rva: u32) ParseError!u32 {
    for (image.sections) |section| {
        const section_end = std.math.add(u32, section.virtual_address, section.raw_size) catch continue;
        if (rva < section.virtual_address or rva >= section_end) continue;
        if (section.raw_offset == 0 or section.raw_size == 0) continue;
        return std.math.add(u32, section.raw_offset, rva - section.virtual_address) catch error.RvaResolutionFailed;
    }
    return error.RvaResolutionFailed;
}

fn parseStringAtRva(bytes: []const u8, image: *const parser.Image, rva: u32) ParseError![]const u8 {
    const offset: usize = @intCast(try rvaToOffset(image, rva));
    var end = offset;
    while (end < bytes.len and bytes[end] != 0) : (end += 1) {}
    if (end == bytes.len) return error.UnterminatedImportString;
    return bytes[offset..end];
}

fn duplicate(allocator: std.mem.Allocator, value: []const u8) ParseError![]const u8 {
    return allocator.dupe(u8, value) catch error.OutOfMemory;
}

fn readThunk(bytes: []const u8, offset: usize, pointer_size: u8) ParseError!u64 {
    return if (pointer_size == 8) readU64(bytes, offset) else @as(u64, try readU32(bytes, offset));
}

fn thunkIsOrdinal(thunk: u64, pointer_size: u8) bool {
    return if (pointer_size == 8)
        (thunk & fmt.import.ordinal_flag64) != 0
    else
        (thunk & fmt.import.ordinal_flag32) != 0;
}

fn thunkNameRva(thunk: u64, pointer_size: u8) ?u32 {
    const value = if (pointer_size == 8)
        thunk & ~fmt.import.ordinal_flag64
    else
        thunk & ~@as(u64, fmt.import.ordinal_flag32);
    if (value > std.math.maxInt(u32)) return null;
    return @intCast(value);
}

fn thunkOrdinal(thunk: u64) u16 {
    return @truncate(thunk);
}

pub fn parseImportDirectory(allocator: std.mem.Allocator, bytes: []const u8, image: *const parser.Image) ParseError!ImportDirectory {
    const directory = image.dataDirectory(fmt.data_dir.entry_import) orelse return error.ImportDirectoryNotFound;
    const directory_end = directory.end() orelse return error.InvalidImportTable;
    if (directory.size < fmt.import.descriptor_size or !image.rvaInImage(directory.virtual_address, directory.size)) {
        return error.InvalidImportTable;
    }

    const pointer_size: u8 = if (image.isPe32Plus()) 8 else 4;
    const descriptor_count: usize = @intCast(directory.size / fmt.import.descriptor_size);
    var descriptors: std.ArrayList(ImportDescriptor) = .empty;
    errdefer descriptors.deinit(allocator);

    var found_terminator = false;
    for (0..descriptor_count) |descriptor_index| {
        const descriptor_delta = std.math.mul(u32, @intCast(descriptor_index), fmt.import.descriptor_size) catch return error.InvalidImportTable;
        const descriptor_rva = std.math.add(u32, directory.virtual_address, descriptor_delta) catch return error.InvalidImportTable;
        if (descriptor_rva >= directory_end) return error.TruncatedImportTable;
        const desc_off_u32 = try rvaToOffset(image, descriptor_rva);
        const desc_off: usize = @intCast(desc_off_u32);

        const oft = try readU32(bytes, desc_off);
        const timestamp = try readU32(bytes, desc_off + 4);
        const forwarder_chain = try readU32(bytes, desc_off + 8);
        const name_rva = try readU32(bytes, desc_off + 12);
        const first_thunk = try readU32(bytes, desc_off + 16);
        if (oft == 0 and timestamp == 0 and forwarder_chain == 0 and name_rva == 0 and first_thunk == 0) {
            found_terminator = true;
            break;
        }
        if (name_rva == 0 or first_thunk == 0) return error.InvalidImportTable;

        const dll_name = try parseStringAtRva(bytes, image, name_rva);
        const lookup_rva = if (oft != 0) oft else first_thunk;
        var thunk_index: u32 = 0;
        while (true) : (thunk_index += 1) {
            const thunk_delta = std.math.mul(u32, thunk_index, @as(u32, pointer_size)) catch return error.InvalidImportTable;
            const thunk_rva = std.math.add(u32, lookup_rva, thunk_delta) catch return error.InvalidImportTable;
            const thunk_off_u32 = try rvaToOffset(image, thunk_rva);
            const thunk_off: usize = @intCast(thunk_off_u32);
            const thunk = try readThunk(bytes, thunk_off, pointer_size);
            if (thunk == 0) break;

            const iat_delta = std.math.mul(u32, thunk_index, @as(u32, pointer_size)) catch return error.InvalidImportTable;
            const iat_rva = std.math.add(u32, first_thunk, iat_delta) catch return error.InvalidImportTable;
            const dll_copy = try duplicate(allocator, dll_name);
            if (thunkIsOrdinal(thunk, pointer_size)) {
                const ordinal = thunkOrdinal(thunk);
                const function_copy = std.fmt.allocPrint(allocator, "#{d}", .{ordinal}) catch return error.OutOfMemory;
                try descriptors.append(allocator, .{
                    .dll_name = dll_copy,
                    .function_name = function_copy,
                    .iat_rva = iat_rva,
                    .ordinal = ordinal,
                    .kind = .ordinal,
                });
                continue;
            }

            const hint_name_rva = thunkNameRva(thunk, pointer_size) orelse return error.InvalidImportTable;
            const hint_name_off: usize = @intCast(try rvaToOffset(image, hint_name_rva));
            _ = try readU16(bytes, hint_name_off);
            const function_start = hint_name_off + 2;
            if (function_start > bytes.len) return error.TruncatedImportTable;
            var function_end = function_start;
            while (function_end < bytes.len and bytes[function_end] != 0) : (function_end += 1) {}
            if (function_end == bytes.len) return error.UnterminatedImportString;
            if (function_end == function_start) return error.InvalidImportTable;
            const function_copy = try duplicate(allocator, bytes[function_start..function_end]);
            try descriptors.append(allocator, .{
                .dll_name = dll_copy,
                .function_name = function_copy,
                .iat_rva = iat_rva,
            });
        }
    }

    if (!found_terminator) return error.TruncatedImportTable;
    return .{
        .descriptors = descriptors.toOwnedSlice(allocator) catch return error.OutOfMemory,
        .pointer_size = pointer_size,
    };
}
