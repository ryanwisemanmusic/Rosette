const std = @import("std");

const max_named_handles = 128;
const max_objects = 128;
const max_locale_facets = 32;
const max_atexit_entries = 1024;
const handle_base: u64 = 0xFFFF_FE00_0000_0000;
const synthetic_thunk_base: u64 = 0xFFFF_FD00_0000_0000;

pub const LocaleFacetKind = enum(u8) {
    generic,
    ctype,
    collate,
};

pub const SyntheticThunk = enum(u8) {
    ctype_toupper_char = 1,
    ctype_toupper_range,
    ctype_tolower_char,
    ctype_tolower_range,
    ctype_widen_char,
    ctype_widen_range,
    ctype_narrow_char,
    ctype_narrow_range,
    locale_has_facet,
    locale_use_facet,
    locale_destroy,
    xmodule_get_name,
};

const NamedHandle = struct {
    handle: u64 = 0,
    name: []const u8 = "",
};

const ObjectHandle = struct {
    handle: u64 = 0,
    receiver: u64 = 0,
    selector: u64 = 0,
};

const FacetHandle = struct {
    id: u64 = 0,
    handle: u64 = 0,
    vtable: u64 = 0,
    table: u64 = 0,
    kind: LocaleFacetKind = .generic,
};

pub const AtexitEntry = struct {
    function: u64 = 0,
    argument: u64 = 0,
    dso: u64 = 0,
    takes_argument: bool = true,
};

pub const MessageResult = struct {
    value: u64,
    selector_name: []const u8,
    modeled: bool,
};

/// Minimal opaque runtime state for APIs whose values are identities rather
/// than dereferenceable guest pointers.
pub const Runtime = struct {
    classes: [max_named_handles]NamedHandle = [_]NamedHandle{.{}} ** max_named_handles,
    class_count: usize = 0,
    selectors: [max_named_handles]NamedHandle = [_]NamedHandle{.{}} ** max_named_handles,
    selector_count: usize = 0,
    objects: [max_objects]ObjectHandle = [_]ObjectHandle{.{}} ** max_objects,
    object_count: usize = 0,
    locale_impl: u64 = 0,
    locale_impl_facet: u64 = 0,
    locale_facets: [max_locale_facets]FacetHandle = [_]FacetHandle{.{}} ** max_locale_facets,
    locale_facet_count: usize = 0,
    atexit_entries: [max_atexit_entries]AtexitEntry = [_]AtexitEntry{.{}} ** max_atexit_entries,
    atexit_count: usize = 0,
    next_handle: u64 = handle_base,

    pub fn classNamed(self: *Runtime, name: []const u8) u64 {
        return self.intern(&self.classes, &self.class_count, name);
    }

    pub fn className(self: *const Runtime, handle: u64) []const u8 {
        for (self.classes[0..self.class_count]) |entry| {
            if (entry.handle == handle) return entry.name;
        }
        return "<unknown-class>";
    }

    pub fn selectorNamed(self: *Runtime, name: []const u8) u64 {
        return self.intern(&self.selectors, &self.selector_count, name);
    }

    pub fn selectorName(self: *const Runtime, handle: u64) []const u8 {
        for (self.selectors[0..self.selector_count]) |entry| {
            if (entry.handle == handle) return entry.name;
        }
        return "<unknown-selector>";
    }

    pub fn sendMessage(self: *Runtime, receiver: u64, selector: u64) MessageResult {
        const name = self.selectorName(selector);
        if (receiver == 0) return .{ .value = 0, .selector_name = name, .modeled = true };

        if (std.mem.eql(u8, name, "sharedApplication") or
            std.mem.eql(u8, name, "contentView") or
            std.mem.eql(u8, name, "layer") or
            std.mem.eql(u8, name, "alloc") or
            std.mem.eql(u8, name, "new"))
        {
            return .{ .value = self.objectFor(receiver, selector), .selector_name = name, .modeled = true };
        }
        if (std.mem.eql(u8, name, "init") or std.mem.eql(u8, name, "retain") or
            std.mem.eql(u8, name, "autorelease"))
        {
            return .{ .value = receiver, .selector_name = name, .modeled = true };
        }
        if (std.mem.eql(u8, name, "respondsToSelector:") or
            std.mem.eql(u8, name, "isKindOfClass:") or
            std.mem.eql(u8, name, "isEqual:"))
        {
            return .{ .value = 1, .selector_name = name, .modeled = true };
        }
        if (std.mem.startsWith(u8, name, "set") or
            std.mem.eql(u8, name, "activateIgnoringOtherApps:") or
            std.mem.eql(u8, name, "release"))
        {
            return .{ .value = 0, .selector_name = name, .modeled = true };
        }
        return .{ .value = 0, .selector_name = name, .modeled = false };
    }

    pub fn currentThreadHandle(_: *const Runtime) u64 {
        return handle_base + 1;
    }

    pub fn initLocale(self: *Runtime, state: anytype, object: u64, source: ?u64) bool {
        var impl = if (source) |source_object| state.read64(source_object) else 0;
        if (impl == 0) {
            if (self.locale_impl == 0) {
                self.locale_impl = state.guestAlloc(64, 16) orelse return false;
                // Set up a minimal vtable for the locale implementation so
                // native libc++ code (pubimbue, ~locale, etc.) can call
                // virtual functions without crashing on a null vtable pointer.
                const vtable = state.guestAlloc(32, 16) orelse return false;
                const vtable_bytes = state.guestMemory(vtable, 32) orelse return false;
                @memset(vtable_bytes, 0);
                state.write64(vtable + 0x00, thunkAddress(.locale_destroy));
                state.write64(vtable + 0x08, thunkAddress(.locale_has_facet));
                state.write64(vtable + 0x10, thunkAddress(.locale_use_facet));
                const impl_bytes = state.guestMemory(self.locale_impl, 64) orelse return false;
                @memset(impl_bytes, 0);
                state.write64(self.locale_impl, vtable);
                // Pre-create a ctype facet for this locale implementation
                self.locale_impl_facet = self.localeFacet(state, 0, .ctype) orelse return false;
            }
            impl = self.locale_impl;
        }
        state.write64(object, impl);
        return true;
    }

    pub fn destroyLocale(_: *Runtime, state: anytype, object: u64) bool {
        const bytes = state.guestMemory(object, 8) orelse return false;
        @memset(bytes, 0);
        return true;
    }

    pub fn localeFacet(self: *Runtime, state: anytype, id: u64, kind: LocaleFacetKind) ?u64 {
        for (self.locale_facets[0..self.locale_facet_count]) |entry| {
            if (entry.id == id and entry.kind == kind) return entry.handle;
        }
        if (self.locale_facet_count >= self.locale_facets.len) return null;
        const handle = state.guestAlloc(128, 16) orelse return null;
        const vtable = state.guestAlloc(128, 16) orelse return null;
        const object_bytes = state.guestMemory(handle, 128) orelse return null;
        const vtable_bytes = state.guestMemory(vtable, 128) orelse return null;
        @memset(object_bytes, 0);
        @memset(vtable_bytes, 0);
        state.write64(handle, vtable);

        var table: u64 = 0;
        if (kind == .ctype) {
            table = state.guestAlloc(256 * @sizeOf(u32), 16) orelse return null;
            const table_bytes = state.guestMemory(table, 256 * @sizeOf(u32)) orelse return null;
            for (0..256) |index| {
                std.mem.writeInt(u32, table_bytes[index * 4 ..][0..4], appleCtypeMask(@intCast(index)), .little);
            }
            state.write64(handle + 16, table);
            state.write64(vtable + 0x18, thunkAddress(.ctype_toupper_char));
            state.write64(vtable + 0x20, thunkAddress(.ctype_toupper_range));
            state.write64(vtable + 0x28, thunkAddress(.ctype_tolower_char));
            state.write64(vtable + 0x30, thunkAddress(.ctype_tolower_range));
            state.write64(vtable + 0x38, thunkAddress(.ctype_widen_char));
            state.write64(vtable + 0x40, thunkAddress(.ctype_widen_range));
            state.write64(vtable + 0x48, thunkAddress(.ctype_narrow_char));
            state.write64(vtable + 0x50, thunkAddress(.ctype_narrow_range));
        }

        self.locale_facets[self.locale_facet_count] = .{
            .id = id,
            .handle = handle,
            .vtable = vtable,
            .table = table,
            .kind = kind,
        };
        self.locale_facet_count += 1;
        return handle;
    }

    pub fn registerAtexit(self: *Runtime, function: u64, argument: u64, dso: u64) bool {
        if (function == 0 or self.atexit_count >= self.atexit_entries.len) return false;
        self.atexit_entries[self.atexit_count] = .{
            .function = function,
            .argument = argument,
            .dso = dso,
        };
        self.atexit_count += 1;
        return true;
    }

    pub fn registerPlainAtexit(self: *Runtime, function: u64) bool {
        if (function == 0 or self.atexit_count >= self.atexit_entries.len) return false;
        self.atexit_entries[self.atexit_count] = .{
            .function = function,
            .takes_argument = false,
        };
        self.atexit_count += 1;
        return true;
    }

    pub fn takeLastAtexit(self: *Runtime) ?AtexitEntry {
        if (self.atexit_count == 0) return null;
        self.atexit_count -= 1;
        const entry = self.atexit_entries[self.atexit_count];
        self.atexit_entries[self.atexit_count] = .{};
        return entry;
    }

    fn intern(
        self: *Runtime,
        entries: *[max_named_handles]NamedHandle,
        count: *usize,
        name: []const u8,
    ) u64 {
        for (entries[0..count.*]) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.handle;
        }
        if (count.* >= entries.len) return 0;
        const handle = self.allocateHandle();
        entries[count.*] = .{ .handle = handle, .name = name };
        count.* += 1;
        return handle;
    }

    fn objectFor(self: *Runtime, receiver: u64, selector: u64) u64 {
        for (self.objects[0..self.object_count]) |entry| {
            if (entry.receiver == receiver and entry.selector == selector) return entry.handle;
        }
        if (self.object_count >= self.objects.len) return 0;
        const handle = self.allocateHandle();
        self.objects[self.object_count] = .{
            .handle = handle,
            .receiver = receiver,
            .selector = selector,
        };
        self.object_count += 1;
        return handle;
    }

    fn allocateHandle(self: *Runtime) u64 {
        const handle = self.next_handle;
        self.next_handle +%= 0x10;
        return handle;
    }
};    pub fn syntheticThunk(address: u64) ?SyntheticThunk {
        if (address <= synthetic_thunk_base or address > synthetic_thunk_base + std.math.maxInt(u8)) return null;
        const offset = address - synthetic_thunk_base;
        const tag: u8 = @intCast(offset);
        return switch (tag) {
            1 => .ctype_toupper_char,
            2 => .ctype_toupper_range,
            3 => .ctype_tolower_char,
            4 => .ctype_tolower_range,
            5 => .ctype_widen_char,
            6 => .ctype_widen_range,
            7 => .ctype_narrow_char,
            8 => .ctype_narrow_range,
            9 => .locale_has_facet,
            10 => .locale_use_facet,
            11 => .locale_destroy,
            12 => .xmodule_get_name,
            else => null,
        };
    }

pub fn thunkAddress(thunk: SyntheticThunk) u64 {
    return synthetic_thunk_base + @intFromEnum(thunk);
}

fn appleCtypeMask(character: u8) u32 {
    const alpha: u32 = 0x0000_0100;
    const control: u32 = 0x0000_0200;
    const digit: u32 = 0x0000_0400;
    const lower: u32 = 0x0000_1000;
    const punctuation: u32 = 0x0000_2000;
    const space: u32 = 0x0000_4000;
    const upper: u32 = 0x0000_8000;
    const hexadecimal: u32 = 0x0001_0000;
    const blank: u32 = 0x0002_0000;
    const printable: u32 = 0x0004_0000;

    var mask: u32 = 0;
    if (character < 0x20 or character == 0x7F) mask |= control;
    if (std.ascii.isWhitespace(character)) mask |= space;
    if (character == ' ' or character == '\t') mask |= blank;
    if (character >= 0x20 and character <= 0x7E) mask |= printable;
    if (std.ascii.isUpper(character)) mask |= alpha | upper;
    if (std.ascii.isLower(character)) mask |= alpha | lower;
    if (std.ascii.isDigit(character)) mask |= digit;
    if (std.ascii.isHex(character)) mask |= hexadecimal;
    if (character >= 0x21 and character <= 0x7E and !std.ascii.isAlphanumeric(character)) mask |= punctuation;
    return mask;
}

/// Initializes the libc++ ABI v1 `basic_string<char>` representation used by
/// Apple libc++ ABI tag v160006.
pub fn initLibcppString(state: anytype, object: u64, source: u64, length: u64) bool {
    // A null pointer is valid for an empty string. Avoid asking the guest
    // address translator to map it, since real Mach-O mappings intentionally
    // leave address zero unmapped.
    if (length == 0) {
        const object_bytes = state.guestMemory(object, 24) orelse return false;
        @memset(object_bytes, 0);
        return true;
    }

    var source_address = source;
    if (rangesOverlap(object, 24, source, length)) {
        const snapshot_size = @max(length, 1);
        const snapshot = state.guestAlloc(snapshot_size, 1) orelse return false;
        const original = state.guestMemoryConst(source, length) orelse return false;
        const copy = state.guestMemory(snapshot, length) orelse return false;
        std.mem.copyForwards(u8, copy, original);
        source_address = snapshot;
    }

    const source_bytes = state.guestMemoryConst(source_address, length) orelse return false;
    const object_bytes = state.guestMemory(object, 24) orelse return false;
    @memset(object_bytes, 0);

    if (length < 23) {
        object_bytes[0] = @intCast(length << 1);
        const len: usize = @intCast(length);
        @memcpy(object_bytes[1 .. 1 + len], source_bytes);
        object_bytes[1 + len] = 0;
        return true;
    }

    const capacity = std.math.add(u64, length, 16) catch return false;
    const allocation_size = capacity & ~@as(u64, 15);
    const data = state.guestAlloc(allocation_size, 16) orelse return false;
    const data_bytes = state.guestMemory(data, allocation_size) orelse return false;
    const len: usize = @intCast(length);
    @memcpy(data_bytes[0..len], source_bytes);
    data_bytes[len] = 0;
    state.write64(object, allocation_size | 1);
    state.write64(object + 8, length);
    state.write64(object + 16, data);
    return true;
}

pub fn destroyLibcppString(state: anytype, object: u64) bool {
    const object_bytes = state.guestMemory(object, 24) orelse return false;
    @memset(object_bytes, 0);
    return true;
}

pub fn initLibcppStringLiteral(state: anytype, object: u64, value: []const u8) bool {
    if (value.len >= 23) return false;
    const object_bytes = state.guestMemory(object, 24) orelse return false;
    @memset(object_bytes, 0);
    object_bytes[0] = @intCast(value.len << 1);
    @memcpy(object_bytes[1 .. 1 + value.len], value);
    return true;
}

pub fn initLibcppStringFromSlice(state: anytype, object: u64, value: []const u8) bool {
    const object_bytes = state.guestMemory(object, 24) orelse return false;
    @memset(object_bytes, 0);
    if (value.len < 23) {
        object_bytes[0] = @intCast(value.len << 1);
        @memcpy(object_bytes[1 .. 1 + value.len], value);
        object_bytes[1 + value.len] = 0;
        return true;
    }
    const capacity = (std.math.add(u64, value.len, 16) catch return false) & ~@as(u64, 15);
    const allocation = state.guestAlloc(capacity, 16) orelse return false;
    const storage = state.guestMemory(allocation, capacity) orelse return false;
    @memcpy(storage[0..value.len], value);
    storage[value.len] = 0;
    state.write64(object, capacity | 1);
    state.write64(object + 8, value.len);
    state.write64(object + 16, allocation);
    return true;
}

pub fn initLibcppStringFill(state: anytype, object: u64, length: u64, value: u8) bool {
    if (length > std.math.maxInt(usize)) return false;
    const object_bytes = state.guestMemory(object, 24) orelse return false;
    @memset(object_bytes, 0);

    if (length < 23) {
        object_bytes[0] = @intCast(length << 1);
        const len: usize = @intCast(length);
        @memset(object_bytes[1 .. 1 + len], value);
        object_bytes[1 + len] = 0;
        return true;
    }

    const capacity = std.math.add(u64, length, 16) catch return false;
    const allocation_size = capacity & ~@as(u64, 15);
    const data = state.guestAlloc(allocation_size, 16) orelse return false;
    const data_bytes = state.guestMemory(data, allocation_size) orelse return false;
    const len: usize = @intCast(length);
    @memset(data_bytes[0..len], value);
    data_bytes[len] = 0;
    state.write64(object, allocation_size | 1);
    state.write64(object + 8, length);
    state.write64(object + 16, data);
    return true;
}

pub fn resizeLibcppString(state: anytype, object: u64, new_size: u64, fill_char: u8) bool {
    if (new_size > std.math.maxInt(usize)) return false;
    const object_bytes = state.guestMemory(object, 24) orelse return false;

    const is_long = object_bytes[0] & 1 != 0;
    const ns: usize = @intCast(new_size);

    if (is_long) {
        const capacity = state.read64(object) & ~@as(u64, 1);
        const old_len = state.read64(object + 8);
        const data_ptr = state.read64(object + 16);
        if (old_len > new_size) {
            state.write64(object + 8, new_size);
            if (new_size != 0) {
                const data_bytes = state.guestMemory(data_ptr, new_size + 1) orelse return false;
                data_bytes[ns] = 0;
            }
            return true;
        }
        if (new_size <= capacity) {
            const data_bytes = state.guestMemory(data_ptr, new_size + 1) orelse return false;
            const ol: usize = @intCast(old_len);
            if (ns > ol) {
                @memset(data_bytes[ol..ns], fill_char);
            }
            data_bytes[ns] = 0;
            state.write64(object + 8, new_size);
            return true;
        }
        // need to grow
        const old_bytes = state.guestMemoryConst(data_ptr, old_len) orelse return false;
        const new_capacity = (std.math.add(u64, new_size, 16) catch return false) & ~@as(u64, 15);
        const new_data = state.guestAlloc(new_capacity, 16) orelse return false;
        const new_bytes = state.guestMemory(new_data, new_capacity) orelse return false;
        const ol_us: usize = @intCast(old_len);
        @memcpy(new_bytes[0..ol_us], old_bytes);
        @memset(new_bytes[ol_us..ns], fill_char);
        new_bytes[ns] = 0;
        state.write64(object, new_capacity | 1);
        state.write64(object + 8, new_size);
        state.write64(object + 16, new_data);
        return true;
    }

    // short string
    const old_len = object_bytes[0] >> 1;
    if (new_size < 23) {
        if (old_len <= new_size) {
            const ol_us: usize = @intCast(old_len);
            @memset(object_bytes[1 + ol_us .. 1 + ns], fill_char);
        }
        object_bytes[0] = @intCast(new_size << 1);
        object_bytes[1 + ns] = 0;
        return true;
    }

    // short -> long transition
    const capacity = (std.math.add(u64, new_size, 16) catch return false) & ~@as(u64, 15);
    const data = state.guestAlloc(capacity, 16) orelse return false;
    const data_bytes = state.guestMemory(data, capacity) orelse return false;
    const ol_us: usize = @intCast(old_len);
    @memcpy(data_bytes[0..ol_us], object_bytes[1..(1 + ol_us)]);
    @memset(data_bytes[ol_us..ns], fill_char);
    data_bytes[ns] = 0;
    state.write64(object, capacity | 1);
    state.write64(object + 8, new_size);
    state.write64(object + 16, data);
    return true;
}

pub const LibcppStringView = struct {
    address: u64,
    length: u64,
};

pub fn libcppStringView(state: anytype, object: u64) ?LibcppStringView {
    const object_bytes = state.guestMemoryConst(object, 24) orelse return null;
    if (object_bytes[0] & 1 == 0) {
        const length = object_bytes[0] >> 1;
        return .{ .address = object + 1, .length = length };
    }
    return .{
        .address = state.read64(object + 16),
        .length = state.read64(object + 8),
    };
}

pub fn copyLibcppString(state: anytype, destination: u64, source: u64) bool {
    const view = libcppStringView(state, source) orelse return false;
    return initLibcppString(state, destination, view.address, view.length);
}

/// Implements the value-producing libc++ `basic_string::substr(pos, count)`
/// operation without entering another libc++ constructor. Returns null when
/// `pos` is out of range so the caller may retain libc++'s exception behavior.
pub fn substringLibcppString(state: anytype, destination: u64, source: u64, position: u64, count: u64) ?u64 {
    const view = libcppStringView(state, source) orelse return null;
    if (position > view.length) return null;
    const available = view.length - position;
    const result_length = @min(count, available);
    if (!initLibcppString(state, destination, view.address + position, result_length)) return null;
    return result_length;
}

pub fn compareLibcppStringWithBytes(state: anytype, object: u64, rhs_address: u64, rhs_length: u64) ?i32 {
    const lhs_view = libcppStringView(state, object) orelse return null;
    const lhs = state.guestMemoryConst(lhs_view.address, lhs_view.length) orelse return null;
    const rhs = state.guestMemoryConst(rhs_address, rhs_length) orelse return null;
    return switch (std.mem.order(u8, lhs, rhs)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn appendLibcppString(state: anytype, object: u64, source: u64, source_length: u64) bool {
    const current = libcppStringView(state, object) orelse return false;
    const total = std.math.add(u64, current.length, source_length) catch return false;
    const temporary = state.guestAlloc(@max(total, 1), 1) orelse return false;
    const temporary_bytes = state.guestMemory(temporary, total) orelse return false;
    const current_bytes = state.guestMemoryConst(current.address, current.length) orelse return false;
    const source_bytes = state.guestMemoryConst(source, source_length) orelse return false;
    const current_len: usize = @intCast(current.length);
    @memcpy(temporary_bytes[0..current_len], current_bytes);
    @memcpy(temporary_bytes[current_len..], source_bytes);
    return initLibcppString(state, object, temporary, total);
}

pub fn pushBackLibcppString(state: anytype, object: u64, character: u8) bool {
    const current = libcppStringView(state, object) orelse return false;
    const new_length = std.math.add(u64, current.length, 1) catch return false;
    const object_bytes = state.guestMemory(object, 24) orelse return false;

    if (object_bytes[0] & 1 == 0 and new_length < 23) {
        const old_length: usize = @intCast(current.length);
        object_bytes[1 + old_length] = character;
        object_bytes[1 + old_length + 1] = 0;
        object_bytes[0] = @intCast(new_length << 1);
        return true;
    }

    if (object_bytes[0] & 1 != 0) {
        const allocation_size = state.read64(object) & ~@as(u64, 1);
        if (new_length < allocation_size) {
            const data = state.guestMemory(current.address, allocation_size) orelse return false;
            data[@intCast(current.length)] = character;
            data[@intCast(new_length)] = 0;
            state.write64(object + 8, new_length);
            return true;
        }
    }

    const temporary = state.guestAlloc(new_length, 1) orelse return false;
    const destination = state.guestMemory(temporary, new_length) orelse return false;
    const source = state.guestMemoryConst(current.address, current.length) orelse return false;
    const old_length: usize = @intCast(current.length);
    @memcpy(destination[0..old_length], source);
    destination[old_length] = character;
    return initLibcppString(state, object, temporary, new_length);
}

pub fn growLibcppString(
    state: anytype,
    object: u64,
    old_capacity: u64,
    capacity_delta: u64,
    old_size: u64,
    prefix_size: u64,
    deleted_size: u64,
    inserted_size: u64,
) bool {
    if (prefix_size > old_size or deleted_size > old_size - prefix_size) return false;
    const current = libcppStringView(state, object) orelse return false;
    if (current.length < old_size) return false;
    const source = state.guestMemoryConst(current.address, old_size) orelse return false;

    const requested = std.math.add(u64, old_capacity, capacity_delta) catch return false;
    const doubled = std.math.mul(u64, old_capacity, 2) catch requested;
    const recommended = @max(requested, doubled);
    const allocation_size = (std.math.add(u64, recommended, 16) catch return false) & ~@as(u64, 15);
    const allocation = state.guestAlloc(@max(allocation_size, 16), 16) orelse return false;
    const destination = state.guestMemory(allocation, @max(allocation_size, 16)) orelse return false;

    const prefix: usize = @intCast(prefix_size);
    if (prefix != 0) @memcpy(destination[0..prefix], source[0..prefix]);
    const suffix_size = old_size - prefix_size - deleted_size;
    if (suffix_size != 0) {
        const suffix_source: usize = @intCast(prefix_size + deleted_size);
        const suffix_destination: usize = @intCast(prefix_size + inserted_size);
        const suffix_length: usize = @intCast(suffix_size);
        @memcpy(
            destination[suffix_destination .. suffix_destination + suffix_length],
            source[suffix_source .. suffix_source + suffix_length],
        );
    }

    state.write64(object, allocation_size | 1);
    state.write64(object + 8, old_size);
    state.write64(object + 16, allocation);
    return true;
}

pub fn insertLibcppString(state: anytype, object: u64, position: u64, source: u64, source_length: u64) bool {
    const current = libcppStringView(state, object) orelse return false;
    if (position > current.length) return false;

    const total = std.math.add(u64, current.length, source_length) catch return false;
    const temporary = state.guestAlloc(@max(total, 1), 1) orelse return false;
    const temporary_bytes = state.guestMemory(temporary, total) orelse return false;
    const current_bytes = state.guestMemoryConst(current.address, current.length) orelse return false;
    const source_bytes = state.guestMemoryConst(source, source_length) orelse return false;

    const pos: usize = @intCast(position);
    const current_len: usize = @intCast(current.length);
    const source_len: usize = @intCast(source_length);

    @memcpy(temporary_bytes[0..pos], current_bytes[0..pos]);
    @memcpy(temporary_bytes[pos .. pos + source_len], source_bytes);
    @memcpy(temporary_bytes[pos + source_len .. pos + source_len + current_len - pos], current_bytes[pos..current_len]);

    return initLibcppString(state, object, temporary, total);
}

pub fn concatCStringAndLibcppString(
    state: anytype,
    destination: u64,
    c_string: u64,
    c_string_length: u64,
    rhs: u64,
) bool {
    if (!initLibcppString(state, destination, c_string, c_string_length)) return false;
    const rhs_view = libcppStringView(state, rhs) orelse return false;
    return appendLibcppString(state, destination, rhs_view.address, rhs_view.length);
}

pub fn libcppRegexClassMask(name: []const u8, ignore_case: bool) u32 {
    const alpha: u32 = 0x0000_0100;
    const control: u32 = 0x0000_0200;
    const digit: u32 = 0x0000_0400;
    const lower: u32 = 0x0000_1000;
    const punctuation: u32 = 0x0000_2000;
    const space: u32 = 0x0000_4000;
    const upper: u32 = 0x0000_8000;
    const hexadecimal: u32 = 0x0001_0000;
    const blank: u32 = 0x0002_0000;
    const printable: u32 = 0x0004_0000;
    const regex_word: u32 = 0x0000_0080;
    const alphanumeric = alpha | digit;

    if (std.mem.eql(u8, name, "alnum")) return alphanumeric;
    if (std.mem.eql(u8, name, "alpha")) return alpha;
    if (std.mem.eql(u8, name, "blank")) return blank;
    if (std.mem.eql(u8, name, "cntrl")) return control;
    if (std.mem.eql(u8, name, "digit") or std.mem.eql(u8, name, "d")) return digit;
    if (std.mem.eql(u8, name, "graph")) return alphanumeric | punctuation;
    if (std.mem.eql(u8, name, "lower")) return if (ignore_case) alpha else lower;
    if (std.mem.eql(u8, name, "print")) return printable;
    if (std.mem.eql(u8, name, "punct")) return punctuation;
    if (std.mem.eql(u8, name, "space") or std.mem.eql(u8, name, "s")) return space;
    if (std.mem.eql(u8, name, "upper")) return if (ignore_case) alpha else upper;
    if (std.mem.eql(u8, name, "xdigit")) return hexadecimal;
    if (std.mem.eql(u8, name, "word") or std.mem.eql(u8, name, "w")) return alphanumeric | regex_word;
    return 0;
}

pub fn cxaGuardAcquire(state: anytype, guard: u64) ?u64 {
    const bytes = state.guestMemory(guard, 8) orelse return null;
    if (bytes[0] != 0 or bytes[1] != 0) return 0;
    bytes[1] = 1;
    return 1;
}

pub fn cxaGuardRelease(state: anytype, guard: u64) bool {
    const bytes = state.guestMemory(guard, 8) orelse return false;
    bytes[0] = 1;
    bytes[1] = 0;
    return true;
}

pub fn cxaGuardAbort(state: anytype, guard: u64) bool {
    const bytes = state.guestMemory(guard, 8) orelse return false;
    bytes[1] = 0;
    return true;
}

fn rangesOverlap(lhs: u64, lhs_len: u64, rhs: u64, rhs_len: u64) bool {
    if (lhs_len == 0 or rhs_len == 0) return false;
    const lhs_end = std.math.add(u64, lhs, lhs_len) catch std.math.maxInt(u64);
    const rhs_end = std.math.add(u64, rhs, rhs_len) catch std.math.maxInt(u64);
    return lhs < rhs_end and rhs < lhs_end;
}

const TestState = struct {
    mem: [2048]u8 = [_]u8{0} ** 2048,
    heap_next: u64 = 256,

    pub fn guestMemory(self: *TestState, address: u64, count: u64) ?[]u8 {
        if (address + count > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + count)];
    }

    pub fn guestMemoryConst(self: *const TestState, address: u64, count: u64) ?[]const u8 {
        if (address + count > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + count)];
    }

    pub fn guestAlloc(self: *TestState, count: u64, alignment: u64) ?u64 {
        const start = (self.heap_next + alignment - 1) & ~(alignment - 1);
        if (start + count > self.mem.len) return null;
        self.heap_next = start + count;
        return start;
    }

    pub fn write64(self: *TestState, address: u64, value: u64) void {
        std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
    }

    pub fn read64(self: *const TestState, address: u64) u64 {
        return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
    }
};

test "Objective-C identities and object-producing messages are stable" {
    var runtime = Runtime{};
    const app_class = runtime.classNamed("NSApplication");
    try std.testing.expectEqual(app_class, runtime.classNamed("NSApplication"));
    const selector = runtime.selectorNamed("sharedApplication");
    const first = runtime.sendMessage(app_class, selector);
    const second = runtime.sendMessage(app_class, selector);
    try std.testing.expect(first.modeled);
    try std.testing.expect(first.value != 0);
    try std.testing.expectEqual(first.value, second.value);
}

test "libc++ short and long string layouts" {
    var state = TestState{};
    @memcpy(state.mem[32..37], "hello");
    try std.testing.expect(initLibcppString(&state, 0, 32, 5));
    try std.testing.expectEqual(@as(u8, 10), state.mem[0]);
    try std.testing.expectEqualStrings("hello", state.mem[1..6]);

    @memset(state.mem[48..80], 'x');
    try std.testing.expect(initLibcppString(&state, 80, 48, 32));
    const capacity_word = std.mem.readInt(u64, state.mem[80..88], .little);
    try std.testing.expect(capacity_word & 1 != 0);
    try std.testing.expectEqual(@as(u64, 32), std.mem.readInt(u64, state.mem[88..96], .little));
    const data = std.mem.readInt(u64, state.mem[96..104], .little);
    try std.testing.expectEqualSlices(u8, state.mem[48..80], state.mem[@intCast(data)..@intCast(data + 32)]);
}

test "libc++ empty string initialization does not dereference its source" {
    var state = TestState{};
    try std.testing.expect(initLibcppString(&state, 160, std.math.maxInt(u64), 0));
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 24), state.mem[160..184]);
}

test "libc++ string assignment tolerates an overlapping source" {
    var state = TestState{};
    @memcpy(state.mem[1..6], "hello");
    try std.testing.expect(initLibcppString(&state, 0, 1, 5));
    try std.testing.expectEqualStrings("hello", state.mem[1..6]);
    try std.testing.expect(destroyLibcppString(&state, 0));
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 24), state.mem[0..24]);
}

test "libc++ string compare with C string bytes is lexicographic" {
    var state = TestState{};
    @memcpy(state.mem[32..37], "hello");
    @memcpy(state.mem[48..53], "hello");
    @memcpy(state.mem[56..61], "hellp");
    @memcpy(state.mem[64..68], "hell");
    try std.testing.expect(initLibcppString(&state, 0, 32, 5));
    try std.testing.expectEqual(@as(?i32, 0), compareLibcppStringWithBytes(&state, 0, 48, 5));
    try std.testing.expectEqual(@as(?i32, -1), compareLibcppStringWithBytes(&state, 0, 56, 5));
    try std.testing.expectEqual(@as(?i32, 1), compareLibcppStringWithBytes(&state, 0, 64, 4));

    @memset(state.mem[96..128], 'x');
    try std.testing.expect(initLibcppString(&state, 128, 96, 32));
    try std.testing.expectEqual(@as(?i32, 0), compareLibcppStringWithBytes(&state, 128, 96, 32));
}

test "Itanium C++ guard acquire release and abort lifecycle" {
    var state = TestState{};
    try std.testing.expectEqual(@as(?u64, 1), cxaGuardAcquire(&state, 32));
    try std.testing.expectEqual(@as(u8, 1), state.mem[33]);
    try std.testing.expectEqual(@as(?u64, 0), cxaGuardAcquire(&state, 32));
    try std.testing.expect(cxaGuardAbort(&state, 32));
    try std.testing.expectEqual(@as(?u64, 1), cxaGuardAcquire(&state, 32));
    try std.testing.expect(cxaGuardRelease(&state, 32));
    try std.testing.expectEqual(@as(u8, 1), state.mem[32]);
    try std.testing.expectEqual(@as(?u64, 0), cxaGuardAcquire(&state, 32));
}

test "libc++ locale identities facets and destructor registration are stable" {
    var state = TestState{};
    var runtime = Runtime{};
    try std.testing.expect(runtime.initLocale(&state, 0, null));
    try std.testing.expect(runtime.initLocale(&state, 8, 0));
    try std.testing.expectEqual(state.read64(0), state.read64(8));
    try std.testing.expectEqual(@as(u64, 0), state.read64(16));
    try std.testing.expect(runtime.initLocale(&state, 24, 16));
    try std.testing.expectEqual(state.read64(0), state.read64(24));
    const facet = runtime.localeFacet(&state, 0x1234, .ctype) orelse return error.OutOfMemory;
    try std.testing.expectEqual(facet, runtime.localeFacet(&state, 0x1234, .ctype).?);
    const vtable = state.read64(facet);
    try std.testing.expectEqual(SyntheticThunk.ctype_tolower_range, syntheticThunk(state.read64(vtable + 0x30)).?);
    const table = state.read64(facet + 16);
    const h_offset: usize = @intCast(table + @as(u64, 'h') * 4);
    const h_mask = std.mem.readInt(u32, state.mem[h_offset..][0..4], .little);
    try std.testing.expect(h_mask & 0x100 != 0);
    try std.testing.expect(h_mask & 0x500 == 0x100);
    try std.testing.expect(runtime.registerAtexit(0x10, 0x20, 0x30));
    try std.testing.expectEqual(@as(usize, 1), runtime.atexit_count);
    try std.testing.expect(runtime.destroyLocale(&state, 8));
    try std.testing.expectEqual(@as(u64, 0), state.read64(8));
}

test "plain and C++ atexit callbacks drain in reverse registration order" {
    var runtime = Runtime{};
    try std.testing.expect(runtime.registerPlainAtexit(0x10));
    try std.testing.expect(runtime.registerAtexit(0x20, 0x21, 0x22));

    const cxx = runtime.takeLastAtexit().?;
    try std.testing.expectEqual(@as(u64, 0x20), cxx.function);
    try std.testing.expectEqual(@as(u64, 0x21), cxx.argument);
    try std.testing.expect(cxx.takes_argument);
    const plain = runtime.takeLastAtexit().?;
    try std.testing.expectEqual(@as(u64, 0x10), plain.function);
    try std.testing.expect(!plain.takes_argument);
    try std.testing.expect(runtime.takeLastAtexit() == null);
}

test "libc++ regex class names use Apple ctype masks" {
    try std.testing.expectEqual(@as(u32, 0x500), libcppRegexClassMask("alnum", false));
    try std.testing.expectEqual(@as(u32, 0x4000), libcppRegexClassMask("space", false));
    try std.testing.expectEqual(@as(u32, 0x580), libcppRegexClassMask("w", false));
    try std.testing.expectEqual(@as(u32, 0x100), libcppRegexClassMask("lower", true));
    try std.testing.expectEqual(@as(u32, 0), libcppRegexClassMask("not-a-class", false));
}

test "libc++ string copy append and concatenation preserve contents" {
    var state = TestState{};
    @memcpy(state.mem[32..37], "hello");
    @memcpy(state.mem[48..54], " world");
    try std.testing.expect(initLibcppString(&state, 0, 32, 5));
    try std.testing.expect(appendLibcppString(&state, 0, 48, 6));
    const appended = libcppStringView(&state, 0).?;
    try std.testing.expectEqualStrings("hello world", state.guestMemoryConst(appended.address, appended.length).?);

    try std.testing.expect(copyLibcppString(&state, 80, 0));
    const copied = libcppStringView(&state, 80).?;
    try std.testing.expectEqualStrings("hello world", state.guestMemoryConst(copied.address, copied.length).?);

    @memcpy(state.mem[112..119], "prefix ");
    try std.testing.expect(concatCStringAndLibcppString(&state, 136, 112, 7, 80));
    const concatenated = libcppStringView(&state, 136).?;
    try std.testing.expectEqualStrings("prefix hello world", state.guestMemoryConst(concatenated.address, concatenated.length).?);
}

test "libc++ string substring preserves bounds and empty suffix" {
    var state = TestState{};
    @memcpy(state.mem[32..48], "User_0123456789:");
    try std.testing.expect(initLibcppString(&state, 0, 32, 16));

    try std.testing.expectEqual(@as(?u64, 10), substringLibcppString(&state, 64, 0, 5, 10));
    var view = libcppStringView(&state, 64).?;
    try std.testing.expectEqualStrings("0123456789", state.guestMemoryConst(view.address, view.length).?);

    try std.testing.expectEqual(@as(?u64, 0), substringLibcppString(&state, 96, 0, 16, std.math.maxInt(u64)));
    view = libcppStringView(&state, 96).?;
    try std.testing.expectEqual(@as(u64, 0), view.length);
    try std.testing.expect(state.mem[96] & 1 == 0);
    try std.testing.expectEqual(@as(?u64, null), substringLibcppString(&state, 128, 0, 17, 1));
}

test "libc++ string push_back preserves short and long representations" {
    var state = TestState{};
    @memcpy(state.mem[32..37], "hello");
    try std.testing.expect(initLibcppString(&state, 0, 32, 5));
    try std.testing.expect(pushBackLibcppString(&state, 0, '!'));
    var view = libcppStringView(&state, 0).?;
    try std.testing.expectEqualStrings("hello!", state.guestMemoryConst(view.address, view.length).?);
    try std.testing.expect(state.mem[0] & 1 == 0);

    @memset(state.mem[64..86], 'x');
    try std.testing.expect(initLibcppString(&state, 96, 64, 22));
    try std.testing.expect(pushBackLibcppString(&state, 96, 'y'));
    view = libcppStringView(&state, 96).?;
    try std.testing.expectEqual(@as(u64, 23), view.length);
    try std.testing.expect(state.mem[96] & 1 != 0);
    try std.testing.expectEqual(@as(u8, 'y'), state.guestMemoryConst(view.address + 22, 1).?[0]);

    const allocation = view.address;
    try std.testing.expect(pushBackLibcppString(&state, 96, 'z'));
    view = libcppStringView(&state, 96).?;
    try std.testing.expectEqual(allocation, view.address);
    try std.testing.expectEqual(@as(u64, 24), view.length);
    try std.testing.expectEqualStrings("yz", state.guestMemoryConst(view.address + 22, 2).?);
    try std.testing.expectEqual(@as(u8, 0), state.guestMemoryConst(view.address + view.length, 1).?[0]);
}

test "libc++ fill initialization preserves short and long layouts" {
    var state = TestState{};
    try std.testing.expect(initLibcppStringFill(&state, 0, 5, '3'));
    var view = libcppStringView(&state, 0).?;
    try std.testing.expectEqualStrings("33333", state.guestMemoryConst(view.address, view.length).?);
    try std.testing.expect(state.mem[0] & 1 == 0);
    try std.testing.expectEqual(@as(u8, 0), state.mem[6]);

    try std.testing.expect(initLibcppStringFill(&state, 64, 32, 'x'));
    view = libcppStringView(&state, 64).?;
    try std.testing.expectEqual(@as(u64, 32), view.length);
    try std.testing.expect(state.mem[64] & 1 != 0);
    try std.testing.expectEqualSlices(u8, &([_]u8{'x'} ** 32), state.guestMemoryConst(view.address, view.length).?);
    try std.testing.expectEqual(@as(u8, 0), state.guestMemoryConst(view.address + view.length, 1).?[0]);
}

test "libc++ string growth preserves prefix and shifted suffix" {
    var state = TestState{};
    @memcpy(state.mem[32..38], "abcdef");
    try std.testing.expect(initLibcppString(&state, 0, 32, 6));
    try std.testing.expect(growLibcppString(&state, 0, 22, 10, 6, 2, 2, 3));

    const grown = libcppStringView(&state, 0).?;
    try std.testing.expectEqual(@as(u64, 6), grown.length);
    try std.testing.expectEqualStrings("ab", state.guestMemoryConst(grown.address, 2).?);
    try std.testing.expectEqualStrings("ef", state.guestMemoryConst(grown.address + 5, 2).?);
    try std.testing.expect(state.read64(0) & 1 != 0);
}
