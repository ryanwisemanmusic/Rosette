const std = @import("std");
const testing = std.testing;
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");

const ResourceString = struct {
    address: u32,
    length: u16,
};

fn resourceTraceEnabled() bool {
    const value = std.c.getenv("ROSETTE_PE32_GL_TRACE") orelse return false;
    return value[0] != 0 and value[0] != '0';
}

fn memoryOffset(ex: *const Executor, address: u32, length: usize) ?usize {
    if (address < ex.mem.base) return null;
    const offset: usize = @intCast(address - ex.mem.base);
    if (offset > ex.mem.data.len or length > ex.mem.data.len - offset) return null;
    return offset;
}

fn read8(ex: *const Executor, address: u32) ?u8 {
    const offset = memoryOffset(ex, address, 1) orelse return null;
    return ex.mem.data[offset];
}

fn read16(ex: *const Executor, address: u32) ?u16 {
    const offset = memoryOffset(ex, address, 2) orelse return null;
    return std.mem.readInt(u16, ex.mem.data[offset..][0..2], .little);
}

fn read32(ex: *const Executor, address: u32) ?u32 {
    const offset = memoryOffset(ex, address, 4) orelse return null;
    return std.mem.readInt(u32, ex.mem.data[offset..][0..4], .little);
}

fn addAddress(base: u32, offset: u32) ?u32 {
    return std.math.add(u32, base, offset) catch null;
}

fn imageRange(ex: *const Executor, module: u32) ?u32 {
    if (read16(ex, module) != 0x5A4D) return null; // MZ
    const pe_offset = read32(ex, addAddress(module, 0x3C) orelse return null) orelse return null;
    const pe = addAddress(module, pe_offset) orelse return null;
    if (read32(ex, pe) != 0x00004550) return null; // PE\0\0
    const optional_size = read16(ex, addAddress(pe, 20) orelse return null) orelse return null;
    const optional = addAddress(pe, 24) orelse return null;
    if (optional_size < 120 or read16(ex, optional) != 0x010B) return null; // PE32
    const image_size = read32(ex, addAddress(optional, 56) orelse return null) orelse return null;
    if (image_size == 0 or memoryOffset(ex, module, @intCast(image_size)) == null) return null;
    return image_size;
}

const ImageResources = struct {
    module: u32,
    image_size: u32,
    root: u32,
    size: u32,
};

fn imageResources(ex: *const Executor, module_arg: u32) ?ImageResources {
    const module = if (module_arg == 0)
        (if (ex.pe32_main_module_base != 0) ex.pe32_main_module_base else ex.mem.base)
    else
        module_arg;
    const image_size = imageRange(ex, module) orelse return null;
    const pe_offset = read32(ex, addAddress(module, 0x3C) orelse return null) orelse return null;
    const pe = addAddress(module, pe_offset) orelse return null;
    const optional = addAddress(pe, 24) orelse return null;
    const directory = addAddress(optional, 112) orelse return null;
    const rva = read32(ex, directory) orelse return null;
    const size = read32(ex, addAddress(directory, 4) orelse return null) orelse return null;
    if (rva == 0 or size < 16 or rva > image_size or size > image_size - rva) return null;
    const root = addAddress(module, rva) orelse return null;
    if (memoryOffset(ex, root, @intCast(size)) == null) return null;
    return .{ .module = module, .image_size = image_size, .root = root, .size = size };
}

const ResourceKey = union(enum) {
    ordinal: u16,
    guest_name: u32,
};

fn foldedUtf16(value: u16) u16 {
    return if (value >= 'A' and value <= 'Z') value + ('a' - 'A') else value;
}

fn resourceNameMatches(ex: *const Executor, resources: ImageResources, relative_name: u32, guest_name: u32) bool {
    if (relative_name > resources.size or resources.size - relative_name < 2) return false;
    const stored_length = read16(ex, resources.root + relative_name) orelse return false;
    var guest_index: u32 = 0;
    while (guest_index <= 255) : (guest_index += 1) {
        const guest_address = addAddress(guest_name, guest_index * 2) orelse return false;
        const guest_unit = read16(ex, guest_address) orelse return false;
        if (guest_unit == 0) return guest_index == stored_length;
        if (guest_index >= stored_length) return false;
        const stored_relative = relative_name + 2 + guest_index * 2;
        if (stored_relative > resources.size or resources.size - stored_relative < 2) return false;
        const stored_unit = read16(ex, resources.root + stored_relative) orelse return false;
        if (foldedUtf16(stored_unit) != foldedUtf16(guest_unit)) return false;
    }
    return false;
}

fn resourceKeyMatches(ex: *const Executor, resources: ImageResources, entry_name: u32, key: ResourceKey) bool {
    return switch (key) {
        .ordinal => |ordinal| entry_name & 0x8000_0000 == 0 and entry_name & 0xFFFF == ordinal,
        .guest_name => |address| entry_name & 0x8000_0000 != 0 and
            resourceNameMatches(ex, resources, entry_name & 0x7FFF_FFFF, address),
    };
}

fn findDirectoryEntry(
    ex: *const Executor,
    resources: ImageResources,
    directory_offset: u32,
    wanted: ResourceKey,
    language: bool,
) ?u32 {
    if (directory_offset > resources.size or resources.size - directory_offset < 16) return null;
    const directory = resources.root + directory_offset;
    const named_count = read16(ex, directory + 12) orelse return null;
    const id_count = read16(ex, directory + 14) orelse return null;
    const count = @as(u32, named_count) + id_count;
    const entries_offset = std.math.add(u32, directory_offset, 16) catch return null;
    const entries_size = std.math.mul(u32, count, 8) catch return null;
    if (entries_offset > resources.size or entries_size > resources.size - entries_offset) return null;

    var first_language: ?u32 = null;
    var neutral_language: ?u32 = null;
    for (0..count) |index| {
        const relative_entry = entries_offset + @as(u32, @intCast(index)) * 8;
        const entry = resources.root + relative_entry;
        const name = read32(ex, entry) orelse return null;
        const target = read32(ex, entry + 4) orelse return null;
        if (language) {
            if (first_language == null) first_language = target;
            if ((name & 0x8000_0000) == 0) {
                const id = name & 0xFFFF;
                if (id == 0x0409) return target;
                if (id == 0) neutral_language = target;
            }
        } else if (resourceKeyMatches(ex, resources, name, wanted)) {
            return target;
        }
    }
    if (language) return neutral_language orelse first_language;
    return null;
}

fn findResourceDataEntry(ex: *const Executor, resources: ImageResources, name_arg: u32, type_arg: u32) ?u32 {
    const type_key: ResourceKey = if (type_arg & 0xFFFF_0000 == 0)
        .{ .ordinal = @truncate(type_arg) }
    else
        .{ .guest_name = type_arg };
    const name_key: ResourceKey = if (name_arg & 0xFFFF_0000 == 0)
        .{ .ordinal = @truncate(name_arg) }
    else
        .{ .guest_name = name_arg };

    const type_target = findDirectoryEntry(ex, resources, 0, type_key, false) orelse return null;
    if ((type_target & 0x8000_0000) == 0) return null;
    const name_target = findDirectoryEntry(ex, resources, type_target & 0x7FFF_FFFF, name_key, false) orelse return null;
    if ((name_target & 0x8000_0000) == 0) return null;
    const language_target = findDirectoryEntry(ex, resources, name_target & 0x7FFF_FFFF, .{ .ordinal = 0 }, true) orelse return null;
    if ((language_target & 0x8000_0000) != 0) return null;
    const data_offset = language_target & 0x7FFF_FFFF;
    if (data_offset > resources.size or resources.size - data_offset < 16) return null;
    return resources.root + data_offset;
}

fn findResourceWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 3);
    const module = frame.arg(0);
    const name = frame.arg(1);
    const resource_type = frame.arg(2);
    const resources = imageResources(ex, module) orelse {
        ex.win32_last_error = 1813; // ERROR_RESOURCE_TYPE_NOT_FOUND
        if (resourceTraceEnabled()) std.debug.print("PE32_RESOURCE: FindResourceW module=0x{X:0>8} name=0x{X:0>8} type=0x{X:0>8} result=missing-image error={d}\n", .{ module, name, resource_type, ex.win32_last_error });
        frame.finish(0);
        return;
    };
    const data_entry = findResourceDataEntry(ex, resources, name, resource_type) orelse {
        ex.win32_last_error = 1814; // ERROR_RESOURCE_NAME_NOT_FOUND
        if (resourceTraceEnabled()) std.debug.print("PE32_RESOURCE: FindResourceW module=0x{X:0>8} name=0x{X:0>8} type=0x{X:0>8} result=missing error={d}\n", .{ module, name, resource_type, ex.win32_last_error });
        frame.finish(0);
        return;
    };
    ex.win32_last_error = 0;
    if (resourceTraceEnabled()) std.debug.print("PE32_RESOURCE: FindResourceW module=0x{X:0>8} name=0x{X:0>8} type=0x{X:0>8} entry=0x{X:0>8}\n", .{ module, name, resource_type, data_entry });
    frame.finish(data_entry);
}

fn resourceData(ex: *Executor, module_arg: u32, resource_handle: u32) ?struct { address: u32, size: u32 } {
    const resources = imageResources(ex, module_arg) orelse return null;
    if (resource_handle < resources.root or resource_handle - resources.root > resources.size or
        resources.size - (resource_handle - resources.root) < 16)
    {
        return null;
    }
    const data_rva = read32(ex, resource_handle) orelse return null;
    const data_size = read32(ex, resource_handle + 4) orelse return null;
    if (data_rva > resources.image_size or data_size > resources.image_size - data_rva) return null;
    const address = addAddress(resources.module, data_rva) orelse return null;
    if (memoryOffset(ex, address, @intCast(data_size)) == null) return null;
    return .{ .address = address, .size = data_size };
}

fn loadResourceThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const module = frame.arg(0);
    const resource_handle = frame.arg(1);
    const loaded = resourceData(ex, module, resource_handle) orelse {
        ex.win32_last_error = 1813;
        if (resourceTraceEnabled()) std.debug.print("PE32_RESOURCE: LoadResource module=0x{X:0>8} entry=0x{X:0>8} result=missing error={d}\n", .{ module, resource_handle, ex.win32_last_error });
        frame.finish(0);
        return;
    };
    ex.win32_last_error = 0;
    if (resourceTraceEnabled()) std.debug.print("PE32_RESOURCE: LoadResource module=0x{X:0>8} entry=0x{X:0>8} data=0x{X:0>8} size={d}\n", .{ module, resource_handle, loaded.address, loaded.size });
    frame.finish(loaded.address);
}

fn lockResourceThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    const address = frame.arg(0);
    const valid = address != 0 and memoryOffset(ex, address, 1) != null;
    ex.win32_last_error = if (valid) 0 else 6; // ERROR_INVALID_HANDLE
    if (resourceTraceEnabled()) std.debug.print("PE32_RESOURCE: LockResource data=0x{X:0>8} valid={} error={d}\n", .{ address, valid, ex.win32_last_error });
    frame.finish(if (valid) address else 0);
}

fn sizeOfResourceThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 2);
    const resource = resourceData(ex, frame.arg(0), frame.arg(1)) orelse {
        ex.win32_last_error = 1813;
        frame.finish(0);
        return;
    };
    ex.win32_last_error = 0;
    frame.finish(resource.size);
}

fn freeResourceThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 1);
    // PE resources are already mapped with their module; FreeResource is a
    // compatibility no-op and must not unmap or mutate guest image storage.
    const handle = frame.arg(0);
    const valid = handle != 0 and memoryOffset(ex, handle, 1) != null;
    ex.win32_last_error = if (valid) 0 else 6; // ERROR_INVALID_HANDLE
    frame.finish(@intFromBool(valid));
}

fn resourceString(ex: *const Executor, module: u32, string_id: u32) ?ResourceString {
    const image_size = imageRange(ex, module) orelse return null;
    const pe_offset = read32(ex, addAddress(module, 0x3C) orelse return null) orelse return null;
    const pe = addAddress(module, pe_offset) orelse return null;
    const optional = addAddress(pe, 24) orelse return null;
    const resource_directory = addAddress(optional, 112) orelse return null; // DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE]
    const resource_rva = read32(ex, resource_directory) orelse return null;
    const resource_size = read32(ex, addAddress(resource_directory, 4) orelse return null) orelse return null;
    if (resource_rva == 0 or resource_size < 16 or resource_rva > image_size or resource_size > image_size - resource_rva) return null;
    const resource_base = addAddress(module, resource_rva) orelse return null;
    if (memoryOffset(ex, resource_base, @intCast(resource_size)) == null) return null;

    const block_id = (string_id >> 4) + 1;
    const string_index: u16 = @truncate(string_id & 0xF);
    var directory_offset: u32 = 0;

    // IMAGE_RESOURCE_DIRECTORY entries are type -> string-table block -> language.
    for (0..3) |level| {
        const directory_address = addAddress(resource_base, directory_offset) orelse return null;
        const named_count = read16(ex, addAddress(directory_address, 12) orelse return null) orelse return null;
        const id_count = read16(ex, addAddress(directory_address, 14) orelse return null) orelse return null;
        const entry_count = @as(u32, named_count) + id_count;
        const entries_offset = std.math.add(u32, directory_offset, 16) catch return null;
        const entries_bytes = std.math.mul(u32, entry_count, 8) catch return null;
        if (entries_offset > resource_size or entries_bytes > resource_size - entries_offset) return null;

        const wanted_id: u32 = switch (level) {
            0 => 6, // RT_STRING
            1 => block_id,
            else => 0, // Language is selected below, preferring US English.
        };
        var selected_target: ?u32 = null;
        var fallback_target: ?u32 = null;
        var neutral_target: ?u32 = null;
        for (0..entry_count) |entry_index| {
            const relative_entry = entries_offset + @as(u32, @intCast(entry_index)) * 8;
            const entry_address = addAddress(resource_base, relative_entry) orelse return null;
            const name = read32(ex, entry_address) orelse return null;
            const target = read32(ex, addAddress(entry_address, 4) orelse return null) orelse return null;
            if ((name & 0x80000000) != 0) continue;
            const id = name & 0xFFFF;
            if (level < 2) {
                if (id == wanted_id) selected_target = target;
            } else {
                if (fallback_target == null) {
                    fallback_target = target;
                }
                if (id == 0x0409) selected_target = target;
                if (id == 0) neutral_target = target;
            }
        }
        const target = selected_target orelse (if (level == 2) neutral_target orelse fallback_target else null) orelse return null;
        if (level < 2) {
            if ((target & 0x80000000) == 0) return null;
            directory_offset = target & 0x7FFFFFFF;
            if (directory_offset > resource_size or resource_size - directory_offset < 16) return null;
            continue;
        }

        if ((target & 0x80000000) != 0) return null;
        const data_entry_offset = target & 0x7FFFFFFF;
        if (data_entry_offset > resource_size or resource_size - data_entry_offset < 16) return null;
        const data_entry = addAddress(resource_base, data_entry_offset) orelse return null;
        const data_rva = read32(ex, data_entry) orelse return null;
        const data_size = read32(ex, addAddress(data_entry, 4) orelse return null) orelse return null;
        if (data_rva > image_size or data_size > image_size - data_rva) return null;
        const data_address = addAddress(module, data_rva) orelse return null;
        if (memoryOffset(ex, data_address, @intCast(data_size)) == null) return null;
        const data_end = data_address + data_size;
        var cursor = data_address;
        var index: u16 = 0;
        while (index < 16) : (index += 1) {
            if (cursor > data_end or data_end - cursor < 2) return null;
            const length = read16(ex, cursor) orelse return null;
            cursor += 2;
            const string_bytes = @as(u32, length) * 2;
            if (string_bytes > data_end - cursor) return null;
            if (index == string_index) return .{ .address = cursor, .length = length };
            cursor += string_bytes;
        }
        return null;
    }
    return null;
}

fn loadStringWThunk(ex: *Executor) void {
    const frame = abi.CallFrame.raw(ex, 4);
    const module_arg = frame.arg(0);
    const main_module = if (ex.pe32_main_module_base != 0) ex.pe32_main_module_base else ex.mem.base;
    const module = if (module_arg == 0) main_module else module_arg;
    if (module != main_module) {
        ex.win32_last_error = 1814; // ERROR_RESOURCE_NAME_NOT_FOUND
        frame.finish(0);
        return;
    }

    const string_id = frame.arg(1);
    const buffer = frame.arg(2);
    const capacity = frame.arg(3);
    const found = resourceString(ex, module, string_id) orelse {
        ex.win32_last_error = 1814;
        frame.finish(0);
        return;
    };

    if (capacity == 0) {
        const pointer_offset = memoryOffset(ex, buffer, 4) orelse {
            ex.win32_last_error = 998; // ERROR_NOACCESS
            frame.finish(0);
            return;
        };
        std.mem.writeInt(u32, ex.mem.data[pointer_offset..][0..4], found.address, .little);
        ex.win32_last_error = 0;
        frame.finish(@as(u32, found.length));
        return;
    }

    if (buffer == 0 or @as(usize, capacity) > ex.mem.data.len / 2) {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    }
    const output_bytes = @as(usize, capacity) * 2;
    const output_offset = memoryOffset(ex, buffer, output_bytes) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    const copied: u16 = @intCast(@min(@as(u32, found.length), capacity - 1));
    const source_offset = memoryOffset(ex, found.address, @as(usize, copied) * 2) orelse {
        ex.win32_last_error = 998;
        frame.finish(0);
        return;
    };
    const copied_bytes = @as(usize, copied) * 2;
    @memcpy(ex.mem.data[output_offset .. output_offset + copied_bytes], ex.mem.data[source_offset .. source_offset + copied_bytes]);
    std.mem.writeInt(u16, ex.mem.data[output_offset + copied_bytes ..][0..2], 0, .little);
    ex.win32_last_error = 0;
    frame.finish(copied);
}

pub fn register(ex: *Executor) void {
    ex.import_table.put("LoadStringW", loadStringWThunk) catch {};
    ex.import_table.put("FindResourceW", findResourceWThunk) catch {};
    ex.import_table.put("LoadResource", loadResourceThunk) catch {};
    ex.import_table.put("LockResource", lockResourceThunk) catch {};
    ex.import_table.put("SizeofResource", sizeOfResourceThunk) catch {};
    ex.import_table.put("FreeResource", freeResourceThunk) catch {};
}

fn writeU16(ex: *Executor, address: u32, value: u16) void {
    const offset = memoryOffset(ex, address, 2).?;
    std.mem.writeInt(u16, ex.mem.data[offset..][0..2], value, .little);
}

fn writeU32(ex: *Executor, address: u32, value: u32) void {
    const offset = memoryOffset(ex, address, 4).?;
    std.mem.writeInt(u32, ex.mem.data[offset..][0..4], value, .little);
}

fn writeDirectory(ex: *Executor, resource_base: u32, relative: u32, ids: []const struct { u16, u32 }) void {
    writeU16(ex, resource_base + relative + 14, @intCast(ids.len));
    for (ids, 0..) |entry, index| {
        const address = resource_base + relative + 16 + @as(u32, @intCast(index)) * 8;
        writeU32(ex, address, entry[0]);
        writeU32(ex, address + 4, entry[1]);
    }
}

test "LoadStringW resolves PE32 string-table resources and bounds the output" {
    var ex = Executor.init(std.testing.allocator, 0x20000);
    defer ex.deinit();
    ex.mem.base = 0x00400000;
    ex.pe32_main_module_base = 0x00401000;
    ex.regs.esp = 0x0041F000;
    register(&ex);

    const module = ex.pe32_main_module_base;
    writeU16(&ex, module, 0x5A4D);
    writeU32(&ex, module + 0x3C, 0x80);
    writeU32(&ex, module + 0x80, 0x00004550);
    writeU16(&ex, module + 0x80 + 20, 224);
    const optional = module + 0x80 + 24;
    writeU16(&ex, optional, 0x010B);
    writeU32(&ex, optional + 56, 0x2000);
    writeU32(&ex, optional + 92, 16);
    writeU32(&ex, optional + 112, 0x1000);
    writeU32(&ex, optional + 116, 0x1000);

    const resource_base = module + 0x1000;
    writeDirectory(&ex, resource_base, 0, &.{.{ 6, 0x80000020 }});
    writeDirectory(&ex, resource_base, 0x20, &.{.{ 3, 0x80000040 }}); // block for string ID 42
    writeDirectory(&ex, resource_base, 0x40, &.{.{ 0x0409, 0x60 }});
    writeU32(&ex, resource_base + 0x60, 0x1080);
    writeU32(&ex, resource_base + 0x64, 64);
    const table = module + 0x1080;
    var cursor = table;
    for (0..10) |_| {
        writeU16(&ex, cursor, 0);
        cursor += 2;
    }
    writeU16(&ex, cursor, 4);
    cursor += 2;
    for ([_]u16{ 'M', 'a', 'z', 'e' }) |unit| {
        writeU16(&ex, cursor, unit);
        cursor += 2;
    }

    const output: u32 = 0x00402000;
    ex.push(4); // Capacity includes the terminator.
    ex.push(output);
    ex.push(42);
    ex.push(module);
    ex.dispatch_import("LoadStringW");

    try testing.expectEqual(@as(u32, 3), ex.regs.eax);
    try testing.expectEqual(@as(u16, 'M'), ex.mem.read16(output));
    try testing.expectEqual(@as(u16, 'a'), ex.mem.read16(output + 2));
    try testing.expectEqual(@as(u16, 'z'), ex.mem.read16(output + 4));
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(output + 6));
    try testing.expectEqual(@as(u32, 0), ex.win32_last_error);
}
