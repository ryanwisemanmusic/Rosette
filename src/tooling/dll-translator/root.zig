const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

const win = struct {
    const mz_signature: u16 = 0x5A4D;
    const pe_signature: u32 = 0x0000_4550;
    const pe32_magic: u16 = 0x10B;
    const pe64_magic: u16 = 0x20B;
    const image_numberof_directory_entries = 16;
    const resource_directory_index = 2;
    const rt_cursor: u32 = 1;
    const rt_bitmap: u32 = 2;
    const rt_icon: u32 = 3;
    const rt_menu: u32 = 4;
    const rt_dialog: u32 = 5;
    const rt_string: u32 = 6;
    const rt_fontdir: u32 = 7;
    const rt_font: u32 = 8;
    const rt_accelerator: u32 = 9;
    const rt_rcdata: u32 = 10;
    const rt_messagetable: u32 = 11;
    const rt_group_icon: u32 = 14;
    const rt_version: u32 = 16;
    const rt_anicursor: u32 = 21;
    const rt_aniicon: u32 = 22;
    const rt_html: u32 = 23;
    const rt_manifest: u32 = 24;
};

const ParseError = error{
    BadDosHeader,
    BadPeHeader,
    UnsupportedPeMagic,
    MissingResourceDirectory,
    RvaNotMapped,
    TruncatedFile,
    IconIndexOutOfRange,
    NoGroupIcons,
};

const Section = struct {
    virtual_address: u32,
    virtual_size: u32,
    raw_size: u32,
    raw_offset: u32,
};

pub const ResourceDumpEntry = struct {
    type_id: u32,
    resource_id: u32,
    lang_id: u32,
    codepage: u32,
    size: u32,
    file_name: []u8,
};

const ResourceData = struct {
    lang_id: u32,
    codepage: u32,
    size: u32,
    bytes: []const u8,
};

const PeInfo = struct {
    resource_rva: u32,
    resource_size: u32,
    sections: []Section,
};

fn readU16(bytes: []const u8, offset: usize) ParseError!u16 {
    if (offset + 2 > bytes.len) return error.TruncatedFile;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32(bytes: []const u8, offset: usize) ParseError!u32 {
    if (offset + 4 > bytes.len) return error.TruncatedFile;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn alignUp(value: u32, alignment: u32) u32 {
    if (alignment == 0) return value;
    return (value + alignment - 1) & ~(alignment - 1);
}

fn parsePe(allocator: std.mem.Allocator, bytes: []const u8) !PeInfo {
    if (try readU16(bytes, 0) != win.mz_signature) return error.BadDosHeader;
    const pe_offset = try readU32(bytes, 0x3C);
    if (try readU32(bytes, pe_offset) != win.pe_signature) return error.BadPeHeader;

    const file_header_offset = pe_offset + 4;
    const number_of_sections = try readU16(bytes, file_header_offset + 2);
    const size_of_optional_header = try readU16(bytes, file_header_offset + 16);
    const optional_header_offset = file_header_offset + 20;
    const optional_magic = try readU16(bytes, optional_header_offset);
    const data_dir_offset: usize = switch (optional_magic) {
        win.pe32_magic => optional_header_offset + 96,
        win.pe64_magic => optional_header_offset + 112,
        else => return error.UnsupportedPeMagic,
    };

    if (size_of_optional_header < data_dir_offset - optional_header_offset + (win.image_numberof_directory_entries * 8))
        return error.MissingResourceDirectory;

    const resource_dir_offset = data_dir_offset + (win.resource_directory_index * 8);
    const resource_rva = try readU32(bytes, resource_dir_offset);
    const resource_size = try readU32(bytes, resource_dir_offset + 4);
    if (resource_rva == 0 or resource_size == 0) return error.MissingResourceDirectory;

    const section_table_offset = optional_header_offset + size_of_optional_header;
    const sections = try allocator.alloc(Section, number_of_sections);
    errdefer allocator.free(sections);

    for (sections, 0..) |*section, i| {
        const entry_offset = section_table_offset + (i * 40);
        section.* = .{
            .virtual_size = try readU32(bytes, entry_offset + 8),
            .virtual_address = try readU32(bytes, entry_offset + 12),
            .raw_size = try readU32(bytes, entry_offset + 16),
            .raw_offset = try readU32(bytes, entry_offset + 20),
        };
    }

    return .{
        .resource_rva = resource_rva,
        .resource_size = resource_size,
        .sections = sections,
    };
}

fn deinitPe(allocator: std.mem.Allocator, pe: PeInfo) void {
    allocator.free(pe.sections);
}

fn rvaToOffset(pe: PeInfo, rva: u32) ParseError!usize {
    for (pe.sections) |section| {
        const mapped_size = @max(section.virtual_size, section.raw_size);
        const section_end = section.virtual_address + alignUp(mapped_size, 0x1000);
        if (rva >= section.virtual_address and rva < section_end) {
            const delta = rva - section.virtual_address;
            return @as(usize, section.raw_offset + delta);
        }
    }
    return error.RvaNotMapped;
}

fn resourceRootOffset(pe: PeInfo) ParseError!usize {
    return try rvaToOffset(pe, pe.resource_rva);
}

fn resourceEntryCount(bytes: []const u8, dir_offset: usize) ParseError!usize {
    const named = try readU16(bytes, dir_offset + 12);
    const ids = try readU16(bytes, dir_offset + 14);
    return named + ids;
}

fn resourceEntryId(bytes: []const u8, entry_offset: usize) ParseError!?u32 {
    const name = try readU32(bytes, entry_offset);
    if ((name & 0x8000_0000) != 0) return null;
    return name;
}

fn resourceEntryChildOffset(bytes: []const u8, root_offset: usize, entry_offset: usize) ParseError!struct { is_dir: bool, offset: usize } {
    const child = try readU32(bytes, entry_offset + 4);
    return .{
        .is_dir = (child & 0x8000_0000) != 0,
        .offset = root_offset + @as(usize, @intCast(child & 0x7FFF_FFFF)),
    };
}

fn resourceDataForEntry(bytes: []const u8, pe: PeInfo, root_offset: usize, entry_offset: usize) ParseError!ResourceData {
    const name_child = try resourceEntryChildOffset(bytes, root_offset, entry_offset);
    if (!name_child.is_dir) return error.TruncatedFile;

    const lang_count = try resourceEntryCount(bytes, name_child.offset);
    if (lang_count == 0) return error.TruncatedFile;

    const lang_entry_offset = name_child.offset + 16;
    return try resourceDataFromLanguageEntry(bytes, pe, root_offset, lang_entry_offset);
}

fn resourceDataFromLanguageEntry(bytes: []const u8, pe: PeInfo, root_offset: usize, lang_entry_offset: usize) ParseError!ResourceData {
    const lang_id = (try resourceEntryId(bytes, lang_entry_offset)) orelse 0;
    const lang_child = try resourceEntryChildOffset(bytes, root_offset, lang_entry_offset);
    if (lang_child.is_dir) return error.TruncatedFile;

    const data_rva = try readU32(bytes, lang_child.offset);
    const size = try readU32(bytes, lang_child.offset + 4);
    const codepage = try readU32(bytes, lang_child.offset + 8);
    const file_offset = try rvaToOffset(pe, data_rva);
    if (file_offset + size > bytes.len) return error.TruncatedFile;

    return .{
        .lang_id = lang_id,
        .codepage = codepage,
        .size = size,
        .bytes = bytes[file_offset .. file_offset + size],
    };
}

fn findResourceSubdirById(bytes: []const u8, root_offset: usize, dir_offset: usize, want_id: u32) ParseError!?usize {
    const count = try resourceEntryCount(bytes, dir_offset);
    const entries_offset = dir_offset + 16;
    for (0..count) |i| {
        const entry_offset = entries_offset + (i * 8);
        const name = try readU32(bytes, entry_offset);
        const child = try readU32(bytes, entry_offset + 4);
        if ((name & 0x8000_0000) != 0) continue;
        if (name != want_id) continue;
        if ((child & 0x8000_0000) == 0) return null;
        return root_offset + (child & 0x7FFF_FFFF);
    }
    return null;
}

fn findResourceEntryById(bytes: []const u8, dir_offset: usize, want_id: u32) ParseError!?usize {
    const count = try resourceEntryCount(bytes, dir_offset);
    const entries_offset = dir_offset + 16;
    for (0..count) |i| {
        const entry_offset = entries_offset + (i * 8);
        const name = try readU32(bytes, entry_offset);
        if ((name & 0x8000_0000) != 0) continue;
        if (name == want_id) return entry_offset;
    }
    return null;
}

fn isPathLabelByte(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '-' or ch == '_' or ch == '.';
}

fn sanitizePathLabel(label: []u8) void {
    for (label) |*ch| {
        if (!isPathLabelByte(ch.*)) ch.* = '_';
    }
}

fn resourceEntryLabelAlloc(allocator: std.mem.Allocator, bytes: []const u8, root_offset: usize, entry_offset: usize, fallback: []const u8) ![]u8 {
    const raw_name = try readU32(bytes, entry_offset);
    if ((raw_name & 0x8000_0000) == 0) {
        return try std.fmt.allocPrint(allocator, "{d}", .{raw_name});
    }

    const string_offset = root_offset + @as(usize, @intCast(raw_name & 0x7FFF_FFFF));
    const len = try readU16(bytes, string_offset);
    if (len == 0) return try allocator.dupe(u8, fallback);

    const utf16 = try allocator.alloc(u16, len);
    defer allocator.free(utf16);
    for (utf16, 0..) |*unit, i| {
        unit.* = try readU16(bytes, string_offset + 2 + (i * 2));
    }

    const label = try std.unicode.utf16LeToUtf8Alloc(allocator, utf16);
    sanitizePathLabel(label);
    return label;
}

fn nthResourceSubdir(bytes: []const u8, root_offset: usize, dir_offset: usize, index: usize) ParseError!?usize {
    const count = try resourceEntryCount(bytes, dir_offset);
    if (index >= count) return null;
    const entry_offset = dir_offset + 16 + (index * 8);
    const child = try readU32(bytes, entry_offset + 4);
    if ((child & 0x8000_0000) == 0) return null;
    return root_offset + (child & 0x7FFF_FFFF);
}

fn groupIconCount(bytes: []const u8, pe: PeInfo) !usize {
    const root_offset = try resourceRootOffset(pe);
    const type_dir = try findResourceSubdirById(bytes, root_offset, root_offset, win.rt_group_icon);
    if (type_dir == null) return 0;
    return try resourceEntryCount(bytes, type_dir.?);
}

fn validateIconIndex(bytes: []const u8, pe: PeInfo, index: usize) !void {
    const count = try groupIconCount(bytes, pe);
    if (count == 0) return error.NoGroupIcons;
    if (index >= count) return error.IconIndexOutOfRange;

    const root_offset = try resourceRootOffset(pe);
    const type_dir = (try findResourceSubdirById(bytes, root_offset, root_offset, win.rt_group_icon)).?;
    const name_dir = try nthResourceSubdir(bytes, root_offset, type_dir, index);
    if (name_dir == null) return error.IconIndexOutOfRange;
}

fn pathCandidates(allocator: std.mem.Allocator, path: []const u8) ![][]u8 {
    const prefixed_1 = try std.fmt.allocPrint(allocator, "include/assets/dll/{s}", .{path});
    defer allocator.free(prefixed_1);
    const prefixed_2 = try std.fmt.allocPrint(allocator, "../include/assets/dll/{s}", .{path});
    defer allocator.free(prefixed_2);
    const prefixed_3 = try std.fmt.allocPrint(allocator, "../../include/assets/dll/{s}", .{path});
    defer allocator.free(prefixed_3);

    const out = try allocator.alloc([]u8, 4);
    errdefer {
        for (out) |item| {
            if (item.len != 0) allocator.free(item);
        }
        allocator.free(out);
    }

    out[0] = try allocator.dupe(u8, path);
    out[1] = try allocator.dupe(u8, prefixed_1);
    out[2] = try allocator.dupe(u8, prefixed_2);
    out[3] = try allocator.dupe(u8, prefixed_3);
    return out;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const fp = c.fopen(path_z.ptr, "rb");
    if (fp == null) return error.FileNotFound;
    defer _ = c.fclose(fp);

    if (c.fseek(fp, 0, c.SEEK_END) != 0) return error.FileNotFound;
    const end_pos = c.ftell(fp);
    if (end_pos < 0) return error.FileNotFound;
    if (@as(usize, @intCast(end_pos)) > max_bytes) return error.FileTooBig;
    if (c.fseek(fp, 0, c.SEEK_SET) != 0) return error.FileNotFound;

    const bytes = try allocator.alloc(u8, @intCast(end_pos));
    errdefer allocator.free(bytes);
    const read_len = c.fread(bytes.ptr, 1, bytes.len, fp);
    if (read_len != bytes.len) return error.FileNotFound;
    return bytes;
}

fn makePathRecursive(allocator: std.mem.Allocator, raw_path: []const u8) !void {
    if (raw_path.len == 0) return;

    var current: std.ArrayListUnmanaged(u8) = .empty;
    defer current.deinit(allocator);

    if (raw_path[0] == '/') {
        try current.append(allocator, '/');
    }

    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 0 and current.items[current.items.len - 1] != '/') {
            try current.append(allocator, '/');
        }
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        defer allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0) {
            if (c.access(path_z.ptr, 0) != 0) return error.FileNotFound;
        }
    }
}

fn writeFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const fp = c.fopen(path_z.ptr, "wb");
    if (fp == null) return error.FileNotFound;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.FileNotFound;
    }
}

fn loadDllBytes(allocator: std.mem.Allocator, raw_path: []const u8) !struct { []u8, []u8 } {
    const candidates = try pathCandidates(allocator, raw_path);
    defer {
        for (candidates) |item| allocator.free(item);
        allocator.free(candidates);
    }

    for (candidates) |candidate| {
        const bytes = readFileAlloc(allocator, candidate, 16 * 1024 * 1024) catch continue;
        const chosen = try allocator.dupe(u8, candidate);
        return .{ bytes, chosen };
    }
    return error.FileNotFound;
}

fn fakeIconHandle(index: usize) usize {
    return 0xD110_0000 + index + 1;
}

fn writeStatusLine(comptime fmt: []const u8, args: anytype) void {
    runtime_abi.common.writeLine(fmt, args);
}

fn resourceTypeName(type_id: ?u32) []const u8 {
    const id = type_id orelse return "named";
    return switch (id) {
        win.rt_cursor => "cursor",
        win.rt_bitmap => "bitmap",
        win.rt_icon => "icon",
        win.rt_menu => "menu",
        win.rt_dialog => "dialog",
        win.rt_string => "string",
        win.rt_fontdir => "fontdir",
        win.rt_font => "font",
        win.rt_accelerator => "accelerator",
        win.rt_rcdata => "rcdata",
        win.rt_messagetable => "messagetable",
        win.rt_group_icon => "group_icon",
        win.rt_version => "version",
        win.rt_anicursor => "anicursor",
        win.rt_aniicon => "aniicon",
        win.rt_html => "html",
        win.rt_manifest => "manifest",
        else => "unknown",
    };
}

fn startsWith(data: []const u8, prefix: []const u8) bool {
    return data.len >= prefix.len and std.mem.eql(u8, data[0..prefix.len], prefix);
}

fn detectedPayloadExtension(type_id: ?u32, data: []const u8) ?[]const u8 {
    if (startsWith(data, "\x89PNG\r\n\x1a\n")) return "png";
    if (startsWith(data, "\xff\xd8\xff")) return "jpg";
    if (startsWith(data, "GIF87a") or startsWith(data, "GIF89a")) return "gif";
    if (startsWith(data, "BM")) return "bmp";
    if (startsWith(data, "\x00\x00\x01\x00")) return "ico";
    if (startsWith(data, "\x00\x00\x02\x00")) return "cur";
    if (startsWith(data, "PK\x03\x04")) return "zip";
    if (data.len >= 12 and startsWith(data, "RIFF") and std.mem.eql(u8, data[8..12], "WAVE")) return "wav";
    if (data.len >= 12 and startsWith(data, "RIFF") and std.mem.eql(u8, data[8..12], "AVI ")) return "avi";

    const id = type_id orelse return null;
    return switch (id) {
        win.rt_bitmap => "dib",
        win.rt_icon => "dib",
        win.rt_group_icon => "grpicon",
        win.rt_manifest => "xml",
        win.rt_html => "html",
        else => null,
    };
}

fn appendU16Le(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: u16) !void {
    try out.append(allocator, @intCast(value & 0x00FF));
    try out.append(allocator, @intCast(value >> 8));
}

fn appendU32Le(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: u32) !void {
    try out.append(allocator, @intCast(value & 0x0000_00FF));
    try out.append(allocator, @intCast((value >> 8) & 0x0000_00FF));
    try out.append(allocator, @intCast((value >> 16) & 0x0000_00FF));
    try out.append(allocator, @intCast(value >> 24));
}

fn findResourceDataById(bytes: []const u8, pe: PeInfo, root_offset: usize, type_id: u32, resource_id: u32) !?ResourceData {
    const type_dir = try findResourceSubdirById(bytes, root_offset, root_offset, type_id);
    if (type_dir == null) return null;
    const entry_offset = try findResourceEntryById(bytes, type_dir.?, resource_id);
    if (entry_offset == null) return null;
    return try resourceDataForEntry(bytes, pe, root_offset, entry_offset.?);
}

fn writeIconGroupFile(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pe: PeInfo,
    root_offset: usize,
    out_dir: []const u8,
    group_label: []const u8,
    lang_id: u32,
    group_bytes: []const u8,
) !void {
    if (group_bytes.len < 6) return;
    const reserved = try readU16(group_bytes, 0);
    const icon_type = try readU16(group_bytes, 2);
    const declared_count = try readU16(group_bytes, 4);
    if (reserved != 0 or icon_type != 1 or declared_count == 0) return;
    const declared_count_usize: usize = @intCast(declared_count);
    if (group_bytes.len < 6 + (declared_count_usize * 14)) return;

    const IconImage = struct {
        width: u8,
        height: u8,
        color_count: u8,
        reserved: u8,
        planes: u16,
        bit_count: u16,
        bytes: []const u8,
    };

    const images = try allocator.alloc(IconImage, declared_count_usize);
    defer allocator.free(images);
    var image_count: usize = 0;

    for (0..declared_count_usize) |i| {
        const entry_offset = 6 + (i * 14);
        const icon_id = try readU16(group_bytes, entry_offset + 12);
        const icon_data = (try findResourceDataById(bytes, pe, root_offset, win.rt_icon, icon_id)) orelse continue;
        images[image_count] = .{
            .width = group_bytes[entry_offset],
            .height = group_bytes[entry_offset + 1],
            .color_count = group_bytes[entry_offset + 2],
            .reserved = group_bytes[entry_offset + 3],
            .planes = try readU16(group_bytes, entry_offset + 4),
            .bit_count = try readU16(group_bytes, entry_offset + 6),
            .bytes = icon_data.bytes,
        };
        image_count += 1;
    }
    if (image_count == 0) return;

    var ico: std.ArrayListUnmanaged(u8) = .empty;
    defer ico.deinit(allocator);

    try appendU16Le(&ico, allocator, 0);
    try appendU16Le(&ico, allocator, 1);
    try appendU16Le(&ico, allocator, @intCast(image_count));

    var image_offset: u32 = @intCast(6 + (image_count * 16));
    for (images[0..image_count]) |image| {
        try ico.append(allocator, image.width);
        try ico.append(allocator, image.height);
        try ico.append(allocator, image.color_count);
        try ico.append(allocator, image.reserved);
        try appendU16Le(&ico, allocator, image.planes);
        try appendU16Le(&ico, allocator, image.bit_count);
        try appendU32Le(&ico, allocator, @intCast(image.bytes.len));
        try appendU32Le(&ico, allocator, image_offset);
        image_offset += @intCast(image.bytes.len);
    }

    for (images[0..image_count]) |image| {
        try ico.appendSlice(allocator, image.bytes);
    }

    const icon_dir = try std.fmt.allocPrint(allocator, "{s}/icon-groups", .{out_dir});
    defer allocator.free(icon_dir);
    try makePathRecursive(allocator, icon_dir);

    const icon_path = try std.fmt.allocPrint(allocator, "{s}/group-{s}_lang-{d}.ico", .{ icon_dir, group_label, lang_id });
    defer allocator.free(icon_path);
    try writeFilePath(allocator, icon_path, ico.items);
}

fn writeResourceFiles(
    allocator: std.mem.Allocator,
    out_dir: []const u8,
    type_label: []const u8,
    type_id: ?u32,
    name_label: []const u8,
    data: ResourceData,
) ![]u8 {
    const flat_name = try std.fmt.allocPrint(allocator, "type-{s}_id-{s}_lang-{d}.bin", .{
        type_label,
        name_label,
        data.lang_id,
    });
    errdefer allocator.free(flat_name);

    const flat_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ out_dir, flat_name });
    defer allocator.free(flat_path);
    try writeFilePath(allocator, flat_path, data.bytes);

    const resource_dir = try std.fmt.allocPrint(allocator, "{s}/type-{s}/id-{s}_lang-{d}", .{
        out_dir,
        type_label,
        name_label,
        data.lang_id,
    });
    defer allocator.free(resource_dir);
    try makePathRecursive(allocator, resource_dir);

    const payload_path = try std.fmt.allocPrint(allocator, "{s}/payload.bin", .{resource_dir});
    defer allocator.free(payload_path);
    try writeFilePath(allocator, payload_path, data.bytes);

    const detected_ext = detectedPayloadExtension(type_id, data.bytes);
    if (detected_ext) |ext| {
        const typed_payload_path = try std.fmt.allocPrint(allocator, "{s}/payload.{s}", .{ resource_dir, ext });
        defer allocator.free(typed_payload_path);
        try writeFilePath(allocator, typed_payload_path, data.bytes);
    }

    const manifest = try std.fmt.allocPrint(allocator,
        \\type={s}
        \\type_name={s}
        \\id={s}
        \\lang={d}
        \\codepage={d}
        \\size={d}
        \\payload=payload.bin
        \\detected_ext={s}
        \\
    , .{
        type_label,
        resourceTypeName(type_id),
        name_label,
        data.lang_id,
        data.codepage,
        data.size,
        detected_ext orelse "bin",
    });
    defer allocator.free(manifest);

    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/manifest.txt", .{resource_dir});
    defer allocator.free(manifest_path);
    try writeFilePath(allocator, manifest_path, manifest);

    return flat_name;
}

pub fn dumpDllResources(allocator: std.mem.Allocator, raw_path: []const u8, out_dir: []const u8) !void {
    const loaded = try loadDllBytes(allocator, raw_path);
    const bytes = loaded[0];
    const chosen_path = loaded[1];
    defer allocator.free(bytes);
    defer allocator.free(chosen_path);

    const pe = try parsePe(allocator, bytes);
    defer deinitPe(allocator, pe);

    try makePathRecursive(allocator, out_dir);

    var manifest: std.ArrayListUnmanaged(u8) = .empty;
    defer manifest.deinit(allocator);

    {
        const line = try std.fmt.allocPrint(allocator, "dll={s}\n", .{chosen_path});
        defer allocator.free(line);
        try manifest.appendSlice(allocator, line);
    }

    const root_offset = try resourceRootOffset(pe);
    const type_count = try resourceEntryCount(bytes, root_offset);
    for (0..type_count) |type_index| {
        const type_entry_offset = root_offset + 16 + (type_index * 8);
        const type_id = try resourceEntryId(bytes, type_entry_offset);
        const type_fallback = try std.fmt.allocPrint(allocator, "type-{d}", .{type_index});
        defer allocator.free(type_fallback);
        const type_label = try resourceEntryLabelAlloc(allocator, bytes, root_offset, type_entry_offset, type_fallback);
        defer allocator.free(type_label);

        const type_child = try resourceEntryChildOffset(bytes, root_offset, type_entry_offset);
        if (!type_child.is_dir) continue;

        const count = try resourceEntryCount(bytes, type_child.offset);
        {
            const line = try std.fmt.allocPrint(allocator, "type={s} type_name={s} count={d}\n", .{
                type_label,
                resourceTypeName(type_id),
                count,
            });
            defer allocator.free(line);
            try manifest.appendSlice(allocator, line);
        }

        for (0..count) |name_index| {
            const name_entry_offset = type_child.offset + 16 + (name_index * 8);
            const name_fallback = try std.fmt.allocPrint(allocator, "id-{d}", .{name_index});
            defer allocator.free(name_fallback);
            const name_label = try resourceEntryLabelAlloc(allocator, bytes, root_offset, name_entry_offset, name_fallback);
            defer allocator.free(name_label);

            const name_child = try resourceEntryChildOffset(bytes, root_offset, name_entry_offset);
            if (!name_child.is_dir) continue;

            const lang_count = try resourceEntryCount(bytes, name_child.offset);
            for (0..lang_count) |lang_index| {
                const lang_entry_offset = name_child.offset + 16 + (lang_index * 8);
                const data = try resourceDataFromLanguageEntry(bytes, pe, root_offset, lang_entry_offset);
                const file_name = try writeResourceFiles(allocator, out_dir, type_label, type_id, name_label, data);
                defer allocator.free(file_name);

                if (type_id != null and type_id.? == win.rt_group_icon) {
                    try writeIconGroupFile(allocator, bytes, pe, root_offset, out_dir, name_label, data.lang_id, data.bytes);
                }

                const line = try std.fmt.allocPrint(allocator, "  id={s} lang={d} codepage={d} size={d} file={s}\n", .{
                    name_label,
                    data.lang_id,
                    data.codepage,
                    data.size,
                    file_name,
                });
                defer allocator.free(line);
                try manifest.appendSlice(allocator, line);
            }
        }
    }

    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/manifest.txt", .{out_dir});
    defer allocator.free(manifest_path);
    try writeFilePath(allocator, manifest_path, manifest.items);

    writeStatusLine("[runtime-abi][dll] unpacked path={s} out={s}\n", .{ chosen_path, out_dir });
}

pub fn dllIconCountA(path_z: [*:0]const u8) c_int {
    const path = std.mem.span(path_z);
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();
    runtime_abi.common.noteValidation();

    const allocator = std.heap.page_allocator;
    const loaded = loadDllBytes(allocator, path) catch |err| {
        writeStatusLine("[runtime-abi][dll] open failed path={s} err={s}\n", .{ path, @errorName(err) });
        return 0;
    };
    const bytes = loaded[0];
    const chosen_path = loaded[1];
    defer allocator.free(bytes);
    defer allocator.free(chosen_path);

    const pe = parsePe(allocator, bytes) catch |err| {
        runtime_abi.common.violation("dll-translator", "parse_pe", "path={s} err={s}", .{ chosen_path, @errorName(err) });
        return 0;
    };
    defer deinitPe(allocator, pe);

    const count = groupIconCount(bytes, pe) catch |err| {
        runtime_abi.common.violation("dll-translator", "group_icon_count", "path={s} err={s}", .{ chosen_path, @errorName(err) });
        return 0;
    };
    writeStatusLine("[runtime-abi][dll] path={s} group_icons={d}\n", .{ chosen_path, count });
    return @intCast(count);
}

pub fn dllExtractIconA(path_z: [*:0]const u8, index: c_int) usize {
    const path = std.mem.span(path_z);
    runtime_abi.common.acquire();
    defer runtime_abi.common.release();
    runtime_abi.common.noteValidation();

    if (index < 0) {
        const count = dllIconCountA(path_z);
        return @intCast(@max(count, 0));
    }

    const allocator = std.heap.page_allocator;
    const loaded = loadDllBytes(allocator, path) catch |err| {
        writeStatusLine("[runtime-abi][dll] extract open failed path={s} err={s}\n", .{ path, @errorName(err) });
        return 0;
    };
    const bytes = loaded[0];
    const chosen_path = loaded[1];
    defer allocator.free(bytes);
    defer allocator.free(chosen_path);

    const pe = parsePe(allocator, bytes) catch |err| {
        runtime_abi.common.violation("dll-translator", "parse_pe", "path={s} err={s}", .{ chosen_path, @errorName(err) });
        return 0;
    };
    defer deinitPe(allocator, pe);

    validateIconIndex(bytes, pe, @intCast(index)) catch |err| {
        writeStatusLine("[runtime-abi][dll] icon missing path={s} index={d} err={s}\n", .{ chosen_path, index, @errorName(err) });
        return 0;
    };

    const handle = fakeIconHandle(@intCast(index));
    writeStatusLine("[runtime-abi][dll] extracted icon path={s} index={d} handle=0x{x}\n", .{ chosen_path, index, handle });
    return handle;
}

fn utf16ZToUtf8Alloc(allocator: std.mem.Allocator, wide: [*:0]const u16) ![]u8 {
    const wide_slice = std.mem.sliceTo(wide, 0);
    return try std.unicode.utf16LeToUtf8Alloc(allocator, wide_slice);
}

pub fn dllIconCountW(path_z: [*:0]const u16) c_int {
    const allocator = std.heap.page_allocator;
    const utf8 = utf16ZToUtf8Alloc(allocator, path_z) catch return 0;
    defer allocator.free(utf8);
    return dllIconCountA(@ptrCast(utf8.ptr));
}

pub fn dllExtractIconW(path_z: [*:0]const u16, index: c_int) usize {
    const allocator = std.heap.page_allocator;
    const utf8 = utf16ZToUtf8Alloc(allocator, path_z) catch return 0;
    defer allocator.free(utf8);
    return dllExtractIconA(@ptrCast(utf8.ptr), index);
}

test "moricons.dll reports icon groups when present" {
    const allocator = std.testing.allocator;
    const loaded = loadDllBytes(allocator, "moricons.dll") catch return;
    const bytes = loaded[0];
    const chosen_path = loaded[1];
    defer allocator.free(bytes);
    defer allocator.free(chosen_path);
    const pe = try parsePe(allocator, bytes);
    defer deinitPe(allocator, pe);
    try std.testing.expect((try groupIconCount(bytes, pe)) > 0);
}
