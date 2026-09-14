//! A confined Windows registry for a PE guest.
//!
//! macOS has no registry, and the host's preferences must never be visible
//! to a guest. Rosette used to answer every open with ERROR_FILE_NOT_FOUND and
//! every write with ERROR_ACCESS_DENIED. That is a truthful refusal, and it is
//! also a hard failure for any program that keeps its own settings there:
//! Xenia's `Emulator::SetPersistentEmulatorFlags` creates
//! `HKCU\Software\Xenia` and was refused twice every run, so the flags it
//! reads back on the next query could never exist.
//!
//! This is the registry the guest owns: keys and values it creates, visible
//! to later calls in the same run, and nothing else. It is rooted in the run,
//! not the host, so a key the guest never wrote is still absent - SDL's audio
//! device-name probe of `HKLM\System\...\MediaCategories` still reads
//! ERROR_FILE_NOT_FOUND, exactly as on a Windows machine without that entry.
//!
//! ## Semantics kept
//!
//! * Key and value names compare case-insensitively (ASCII), with `\`
//!   separators normalised.
//! * A key exists if it was created or if a key beneath it was: Windows
//!   creates every intermediate key of a `RegCreateKeyEx` path.
//! * Values keep their type and exact bytes. A `RegSetValueExW` string is
//!   stored as the UTF-16 the guest supplied; no A/W conversion is invented.
//! * Capacity is bounded and a refusal is ERROR_NOT_ENOUGH_MEMORY, counted.
//!
//! ## Not modelled
//!
//! Persistence across runs, security descriptors, notifications, enumeration
//! and the class name. Each absence is a refusal the caller can see.

const std = @import("std");

pub const error_success: u32 = 0;
pub const error_file_not_found: u32 = 2;
pub const error_invalid_handle: u32 = 6;
pub const error_not_enough_memory: u32 = 8;
pub const error_invalid_parameter: u32 = 87;
pub const error_more_data: u32 = 234;
pub const error_unsupported_type: u32 = 1630;

pub const max_keys: usize = 256;
pub const max_values: usize = 1024;
pub const max_handles: usize = 256;
pub const max_path_bytes: usize = 260;
pub const max_name_bytes: usize = 256;
pub const max_value_bytes: usize = 64 * 1024;
pub const max_total_value_bytes: usize = 4 * 1024 * 1024;
/// Registry handles live in their own range so they can never be confused
/// with a wait object, a file or a module handle from the shared allocator.
pub const handle_base: u64 = 0xFFFF_F700_0000_0000;

/// The predefined root a handle names, if it names one. Win64 sign-extends
/// `HKEY_CURRENT_USER` to 0xFFFFFFFF80000001, and both spellings are roots.
pub fn rootOf(handle: u64) ?u32 {
    const high = handle >> 32;
    if (high != 0 and high != 0xFFFF_FFFF) return null;
    const low: u32 = @truncate(handle);
    return switch (low) {
        0x8000_0000, 0x8000_0001, 0x8000_0002, 0x8000_0003, 0x8000_0005 => low,
        else => null,
    };
}

const Key = struct {
    used: bool = false,
    root: u32 = 0,
    path_len: u16 = 0,
    path: [max_path_bytes]u8 = undefined,

    fn pathSlice(self: *const Key) []const u8 {
        return self.path[0..self.path_len];
    }
};

const Value = struct {
    used: bool = false,
    key: u16 = 0,
    name_len: u16 = 0,
    name: [max_name_bytes]u8 = undefined,
    value_type: u32 = 0,
    data: []u8 = &.{},

    fn nameSlice(self: *const Value) []const u8 {
        return self.name[0..self.name_len];
    }
};

const HandleSlot = struct {
    used: bool = false,
    key: u16 = 0,
};

const Tables = struct {
    keys: [max_keys]Key = [_]Key{.{}} ** max_keys,
    values: [max_values]Value = [_]Value{.{}} ** max_values,
    handles: [max_handles]HandleSlot = [_]HandleSlot{.{}} ** max_handles,
};

pub const OpenResult = struct {
    status: u32,
    handle: u64 = 0,
    created: bool = false,
};

pub const QueryResult = struct {
    status: u32,
    value_type: u32 = 0,
    data: []const u8 = &.{},
};

/// How much of a value fits a caller's buffer, by the rules
/// `RegQueryValueEx` and `RegGetValue` share.
pub const Fit = struct {
    status: u32,
    /// The size to write back through the caller's size pointer.
    reported_size: u32,
    /// Whether the value's bytes should be copied into the caller's buffer.
    copy: bool,
};

pub fn fitValue(value_size: usize, has_buffer: bool, has_size: bool, capacity: u32) Fit {
    const size: u32 = @intCast(@min(value_size, std.math.maxInt(u32)));
    if (!has_size) {
        // No size pointer: a data pointer cannot be bounded.
        return .{ .status = if (has_buffer) error_invalid_parameter else error_success, .reported_size = 0, .copy = false };
    }
    if (!has_buffer) return .{ .status = error_success, .reported_size = size, .copy = false };
    if (capacity < size) return .{ .status = error_more_data, .reported_size = size, .copy = false };
    return .{ .status = error_success, .reported_size = size, .copy = true };
}

/// Whether a value's type passes a `RegGetValue` RRF_RT_* restriction.
pub fn typeAllowed(value_type: u32, flags: u32) bool {
    const restriction = flags & 0xFFFF;
    if (restriction == 0 or restriction == 0xFFFF) return true;
    if (value_type > 15) return false;
    return (restriction >> @as(u5, @intCast(value_type))) & 1 != 0;
}

pub const Registry = struct {
    tables: ?*Tables = null,
    value_bytes: usize = 0,

    keys_created: u64 = 0,
    values_written: u64 = 0,
    values_deleted: u64 = 0,
    queries: u64 = 0,
    queries_found: u64 = 0,
    opens: u64 = 0,
    opens_missing: u64 = 0,
    capacity_refusals: u64 = 0,
    invalid_handles: u64 = 0,

    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        const tables = self.tables orelse return;
        for (&tables.values) |*value| {
            if (value.used and value.data.len != 0) allocator.free(value.data);
        }
        allocator.destroy(tables);
        self.* = .{};
    }

    pub fn keyCount(self: *const Registry) usize {
        const tables = self.tables orelse return 0;
        var total: usize = 0;
        for (&tables.keys) |*key| total += @intFromBool(key.used);
        return total;
    }

    pub fn valueCount(self: *const Registry) usize {
        const tables = self.tables orelse return 0;
        var total: usize = 0;
        for (&tables.values) |*value| total += @intFromBool(value.used);
        return total;
    }

    pub fn isKnownHandle(self: *const Registry, handle: u64) bool {
        if (rootOf(handle) != null) return true;
        return self.handleKey(handle) != null;
    }

    /// Open or create `subkey` beneath `parent`, which is a root or a handle
    /// this registry issued.
    pub fn openKey(self: *Registry, allocator: std.mem.Allocator, parent: u64, subkey: []const u8, create: bool) OpenResult {
        self.opens +|= 1;
        var path_buffer: [max_path_bytes]u8 = undefined;
        const resolved = self.resolve(parent, subkey, &path_buffer) orelse {
            self.invalid_handles +|= 1;
            return .{ .status = error_invalid_handle };
        };
        if (resolved.path.len > max_path_bytes) return .{ .status = error_invalid_parameter };
        const tables = self.ensureTables(allocator) orelse {
            self.capacity_refusals +|= 1;
            return .{ .status = error_not_enough_memory };
        };
        var created = false;
        const key_index = self.findKey(resolved.root, resolved.path) orelse blk: {
            // A predefined root always exists; opening it with an empty or
            // null subkey returns a handle to the root itself.
            if (!create and resolved.path.len != 0 and !self.hasDescendant(resolved.root, resolved.path)) {
                self.opens_missing +|= 1;
                return .{ .status = error_file_not_found };
            }
            const index = self.addKey(resolved.root, resolved.path) orelse {
                self.capacity_refusals +|= 1;
                return .{ .status = error_not_enough_memory };
            };
            created = create;
            if (create) self.keys_created +|= 1;
            break :blk index;
        };
        for (&tables.handles, 0..) |*slot, index| {
            if (slot.used) continue;
            slot.* = .{ .used = true, .key = @intCast(key_index) };
            return .{ .status = error_success, .handle = handle_base + index + 1, .created = created };
        }
        self.capacity_refusals +|= 1;
        return .{ .status = error_not_enough_memory };
    }

    pub fn closeKey(self: *Registry, handle: u64) u32 {
        if (rootOf(handle) != null) return error_success;
        const tables = self.tables orelse return self.invalid(handle);
        const index = handleIndex(handle) orelse return self.invalid(handle);
        if (!tables.handles[index].used) return self.invalid(handle);
        tables.handles[index] = .{};
        return error_success;
    }

    pub fn setValue(
        self: *Registry,
        allocator: std.mem.Allocator,
        handle: u64,
        name: []const u8,
        value_type: u32,
        data: []const u8,
    ) u32 {
        if (name.len > max_name_bytes) return error_invalid_parameter;
        if (data.len > max_value_bytes) {
            self.capacity_refusals +|= 1;
            return error_not_enough_memory;
        }
        const key_index = self.keyForHandle(allocator, handle) orelse return self.invalid(handle);
        const tables = self.tables.?;
        const existing = self.findValue(key_index, name);
        const previous_len = if (existing) |index| tables.values[index].data.len else 0;
        if (self.value_bytes - previous_len + data.len > max_total_value_bytes) {
            self.capacity_refusals +|= 1;
            return error_not_enough_memory;
        }
        const copy = allocator.alloc(u8, data.len) catch {
            self.capacity_refusals +|= 1;
            return error_not_enough_memory;
        };
        @memcpy(copy, data);
        const slot_index = existing orelse blk: {
            for (&tables.values, 0..) |*value, index| {
                if (!value.used) break :blk index;
            }
            allocator.free(copy);
            self.capacity_refusals +|= 1;
            return error_not_enough_memory;
        };
        const slot = &tables.values[slot_index];
        if (slot.used and slot.data.len != 0) allocator.free(slot.data);
        slot.* = .{ .used = true, .key = @intCast(key_index), .value_type = value_type, .data = copy };
        slot.name_len = @intCast(normalise(name, &slot.name));
        self.value_bytes = self.value_bytes - previous_len + data.len;
        self.values_written +|= 1;
        return error_success;
    }

    /// `RegQueryValueEx`: a value of the key `handle` names.
    pub fn queryValue(self: *Registry, handle: u64, name: []const u8) QueryResult {
        self.queries +|= 1;
        const key_index = self.existingKeyForHandle(handle) orelse {
            if (!self.isKnownHandle(handle)) return .{ .status = self.invalid(handle) };
            return .{ .status = error_file_not_found };
        };
        return self.valueResult(key_index, name);
    }

    /// `RegGetValue`: a value of `subkey` beneath `handle`, without a handle.
    pub fn getValue(self: *Registry, handle: u64, subkey: []const u8, name: []const u8) QueryResult {
        self.queries +|= 1;
        var path_buffer: [max_path_bytes]u8 = undefined;
        const resolved = self.resolve(handle, subkey, &path_buffer) orelse return .{ .status = self.invalid(handle) };
        const key_index = self.findKey(resolved.root, resolved.path) orelse return .{ .status = error_file_not_found };
        return self.valueResult(key_index, name);
    }

    pub fn deleteValue(self: *Registry, allocator: std.mem.Allocator, handle: u64, name: []const u8) u32 {
        const key_index = self.existingKeyForHandle(handle) orelse {
            if (!self.isKnownHandle(handle)) return self.invalid(handle);
            return error_file_not_found;
        };
        const index = self.findValue(key_index, name) orelse return error_file_not_found;
        const value = &self.tables.?.values[index];
        self.value_bytes -= value.data.len;
        if (value.data.len != 0) allocator.free(value.data);
        value.* = .{};
        self.values_deleted +|= 1;
        return error_success;
    }

    fn valueResult(self: *Registry, key_index: usize, name: []const u8) QueryResult {
        const index = self.findValue(key_index, name) orelse return .{ .status = error_file_not_found };
        const value = &self.tables.?.values[index];
        self.queries_found +|= 1;
        return .{ .status = error_success, .value_type = value.value_type, .data = value.data };
    }

    fn invalid(self: *Registry, handle: u64) u32 {
        _ = handle;
        self.invalid_handles +|= 1;
        return error_invalid_handle;
    }

    fn ensureTables(self: *Registry, allocator: std.mem.Allocator) ?*Tables {
        if (self.tables) |tables| return tables;
        const tables = allocator.create(Tables) catch return null;
        tables.* = .{};
        self.tables = tables;
        return tables;
    }

    const Resolved = struct { root: u32, path: []const u8 };

    fn resolve(self: *const Registry, parent: u64, subkey: []const u8, buffer: *[max_path_bytes]u8) ?Resolved {
        var used: usize = 0;
        var root: u32 = 0;
        if (rootOf(parent)) |value| {
            root = value;
        } else {
            const index = self.handleKey(parent) orelse return null;
            const key = &self.tables.?.keys[index];
            root = key.root;
            @memcpy(buffer[0..key.path_len], key.pathSlice());
            used = key.path_len;
        }
        var normalised: [max_path_bytes]u8 = undefined;
        const length = normalise(subkey, &normalised);
        if (length != 0) {
            if (used != 0) {
                if (used == max_path_bytes) return .{ .root = root, .path = buffer[0..used] };
                buffer[used] = '\\';
                used += 1;
            }
            const take = @min(length, max_path_bytes - used);
            @memcpy(buffer[used..][0..take], normalised[0..take]);
            used += take;
        }
        return .{ .root = root, .path = buffer[0..used] };
    }

    fn handleKey(self: *const Registry, handle: u64) ?usize {
        const tables = self.tables orelse return null;
        const index = handleIndex(handle) orelse return null;
        if (!tables.handles[index].used) return null;
        return tables.handles[index].key;
    }

    /// The key a value operation targets, creating the root's own key on
    /// first write to a bare root.
    fn keyForHandle(self: *Registry, allocator: std.mem.Allocator, handle: u64) ?usize {
        if (rootOf(handle)) |root| {
            _ = self.ensureTables(allocator) orelse return null;
            return self.findKey(root, "") orelse self.addKey(root, "");
        }
        return self.handleKey(handle);
    }

    fn existingKeyForHandle(self: *const Registry, handle: u64) ?usize {
        if (rootOf(handle)) |root| return self.findKey(root, "");
        return self.handleKey(handle);
    }

    fn findKey(self: *const Registry, root: u32, path: []const u8) ?usize {
        const tables = self.tables orelse return null;
        for (&tables.keys, 0..) |*key, index| {
            if (key.used and key.root == root and std.mem.eql(u8, key.pathSlice(), path)) return index;
        }
        return null;
    }

    fn hasDescendant(self: *const Registry, root: u32, path: []const u8) bool {
        const tables = self.tables orelse return false;
        for (&tables.keys) |*key| {
            if (!key.used or key.root != root) continue;
            const candidate = key.pathSlice();
            if (path.len == 0) return true;
            if (candidate.len > path.len and std.mem.startsWith(u8, candidate, path) and candidate[path.len] == '\\') return true;
        }
        return false;
    }

    fn addKey(self: *Registry, root: u32, path: []const u8) ?usize {
        const tables = self.tables orelse return null;
        for (&tables.keys, 0..) |*key, index| {
            if (key.used) continue;
            key.* = .{ .used = true, .root = root, .path_len = @intCast(path.len) };
            @memcpy(key.path[0..path.len], path);
            return index;
        }
        return null;
    }

    fn findValue(self: *const Registry, key_index: usize, name: []const u8) ?usize {
        const tables = self.tables orelse return null;
        var normalised: [max_name_bytes]u8 = undefined;
        const length = normalise(name, &normalised);
        for (&tables.values, 0..) |*value, index| {
            if (value.used and value.key == key_index and std.mem.eql(u8, value.nameSlice(), normalised[0..length])) return index;
        }
        return null;
    }
};

fn handleIndex(handle: u64) ?usize {
    if (handle <= handle_base or handle > handle_base + max_handles) return null;
    return @intCast(handle - handle_base - 1);
}

/// Lower-case ASCII, separators collapsed and trimmed. Returns the length
/// written; input longer than the output is truncated.
fn normalise(input: []const u8, output: []u8) usize {
    var used: usize = 0;
    var previous_separator = true;
    for (input) |byte| {
        if (used == output.len) break;
        if (byte == '\\') {
            if (previous_separator) continue;
            previous_separator = true;
            output[used] = '\\';
            used += 1;
            continue;
        }
        previous_separator = false;
        output[used] = std.ascii.toLower(byte);
        used += 1;
    }
    while (used != 0 and output[used - 1] == '\\') used -= 1;
    return used;
}

test "a key the guest created holds the value it wrote, case-insensitively" {
    const allocator = std.testing.allocator;
    var registry = Registry{};
    defer registry.deinit(allocator);

    const hkcu: u64 = 0xFFFF_FFFF_8000_0001;
    // Xenia's first act: open, find nothing, create and write.
    try std.testing.expectEqual(error_file_not_found, registry.openKey(allocator, hkcu, "Software\\Xenia", false).status);
    const created = registry.openKey(allocator, hkcu, "Software\\Xenia", true);
    try std.testing.expectEqual(error_success, created.status);
    try std.testing.expect(created.created);
    const flags = [_]u8{ 1, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectEqual(error_success, registry.setValue(allocator, created.handle, "EmuFlags", 11, &flags));
    try std.testing.expectEqual(error_success, registry.closeKey(created.handle));

    // The next run of the same probe finds it.
    const opened = registry.openKey(allocator, 0x8000_0001, "software\\XENIA\\", false);
    try std.testing.expectEqual(error_success, opened.status);
    const value = registry.queryValue(opened.handle, "emuflags");
    try std.testing.expectEqual(error_success, value.status);
    try std.testing.expectEqual(@as(u32, 11), value.value_type);
    try std.testing.expectEqualSlices(u8, &flags, value.data);
}

test "an absent key stays absent, and a parent of a created key exists" {
    const allocator = std.testing.allocator;
    var registry = Registry{};
    defer registry.deinit(allocator);
    const hklm: u64 = 0xFFFF_FFFF_8000_0002;
    try std.testing.expectEqual(error_file_not_found, registry.openKey(allocator, hklm, "System\\CurrentControlSet\\Control\\MediaCategories", false).status);
    const deep = registry.openKey(allocator, 0x8000_0001, "Software\\Vendor\\Product", true);
    try std.testing.expectEqual(error_success, deep.status);
    try std.testing.expectEqual(error_success, registry.openKey(allocator, 0x8000_0001, "Software\\Vendor", false).status);
    try std.testing.expectEqual(error_file_not_found, registry.openKey(allocator, 0x8000_0001, "Software\\Other", false).status);
    try std.testing.expectEqual(error_file_not_found, registry.getValue(hklm, "System", "anything").status);
    // A root opened with no subkey is the root.
    try std.testing.expectEqual(error_success, registry.openKey(allocator, hklm, "", false).status);
}

test "a relative open composes with the parent handle's path" {
    const allocator = std.testing.allocator;
    var registry = Registry{};
    defer registry.deinit(allocator);
    const software = registry.openKey(allocator, 0x8000_0001, "Software", true);
    const child = registry.openKey(allocator, software.handle, "Child", true);
    try std.testing.expectEqual(error_success, registry.setValue(allocator, child.handle, "", 4, &[_]u8{ 7, 0, 0, 0 }));
    const got = registry.getValue(0x8000_0001, "software\\child", "");
    try std.testing.expectEqual(error_success, got.status);
    try std.testing.expectEqual(@as(u8, 7), got.data[0]);
}

test "handles are checked and bounded" {
    const allocator = std.testing.allocator;
    var registry = Registry{};
    defer registry.deinit(allocator);
    try std.testing.expectEqual(error_invalid_handle, registry.closeKey(handle_base + 5));
    try std.testing.expectEqual(error_success, registry.closeKey(0x8000_0002));
    try std.testing.expectEqual(error_invalid_handle, registry.openKey(allocator, 0x1234, "x", true).status);
    try std.testing.expectEqual(error_invalid_handle, registry.queryValue(0x1234, "x").status);
    try std.testing.expect(!registry.isKnownHandle(0x1234));
    try std.testing.expect(registry.isKnownHandle(0xFFFF_FFFF_8000_0000));
    const opened = registry.openKey(allocator, 0x8000_0001, "a", true);
    try std.testing.expect(registry.isKnownHandle(opened.handle));
    try std.testing.expectEqual(error_success, registry.closeKey(opened.handle));
    try std.testing.expectEqual(error_invalid_handle, registry.closeKey(opened.handle));
}

test "values overwrite, delete, and respect the size budget" {
    const allocator = std.testing.allocator;
    var registry = Registry{};
    defer registry.deinit(allocator);
    const key = registry.openKey(allocator, 0x8000_0001, "k", true);
    try std.testing.expectEqual(error_success, registry.setValue(allocator, key.handle, "v", 3, "abc"));
    try std.testing.expectEqual(error_success, registry.setValue(allocator, key.handle, "V", 3, "de"));
    try std.testing.expectEqualSlices(u8, "de", registry.queryValue(key.handle, "v").data);
    try std.testing.expectEqual(@as(usize, 2), registry.value_bytes);
    try std.testing.expectEqual(error_success, registry.deleteValue(allocator, key.handle, "v"));
    try std.testing.expectEqual(error_file_not_found, registry.queryValue(key.handle, "v").status);
    try std.testing.expectEqual(@as(usize, 0), registry.value_bytes);
    const huge = [_]u8{0} ** (max_value_bytes + 1);
    try std.testing.expectEqual(error_not_enough_memory, registry.setValue(allocator, key.handle, "big", 3, &huge));
}

test "buffer fitting follows RegQueryValueEx" {
    try std.testing.expectEqual(Fit{ .status = error_success, .reported_size = 8, .copy = false }, fitValue(8, false, true, 0));
    try std.testing.expectEqual(Fit{ .status = error_more_data, .reported_size = 8, .copy = false }, fitValue(8, true, true, 4));
    try std.testing.expectEqual(Fit{ .status = error_success, .reported_size = 8, .copy = true }, fitValue(8, true, true, 16));
    try std.testing.expectEqual(error_invalid_parameter, fitValue(8, true, false, 0).status);
    try std.testing.expect(typeAllowed(4, 0x10)); // RRF_RT_REG_DWORD
    try std.testing.expect(!typeAllowed(1, 0x10));
    try std.testing.expect(typeAllowed(1, 0xFFFF)); // RRF_RT_ANY
}
