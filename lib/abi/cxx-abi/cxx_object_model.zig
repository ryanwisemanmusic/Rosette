const std = @import("std");
const vtables = @import("itanium_vtable_builder.zig");

pub const Kind = enum {
    ios_base,
    basic_ios,
    basic_streambuf,
    basic_istream,
    basic_ostream,
    basic_iostream,
    basic_filebuf,
    basic_ifstream,
    basic_ofstream,
    basic_fstream,
    locale,
    runtime_error,
};

pub const StreamLayout = struct {
    size: u64,
    rdbuf_offset: u64,
    state_offset: u64,
    exceptions_offset: u64,
    tie_offset: u64,
    locale_offset: u64,
    fill_offset: u64,
};

pub const stream_layout = StreamLayout{
    .size = 64,
    .rdbuf_offset = 16,
    .state_offset = 24,
    .exceptions_offset = 28,
    .tie_offset = 32,
    .locale_offset = 40,
    .fill_offset = 48,
};

pub const FILEBUF_OFFSET_IN_IFSTREAM: u64 = 16;
pub const BASIC_IOS_OFFSET_IN_IFSTREAM: u64 = 424;
// libc++ stores basic_istream::__gc_ immediately after the vptr.  It must be
// initialized before a parser inspects gcount() for the first time.
pub const BASIC_ISTREAM_GCOUNT_OFFSET: u64 = 8;
pub const IFSTREAM_SIZE: u64 = BASIC_IOS_OFFSET_IN_IFSTREAM + stream_layout.size;
pub const BADBIT: u32 = 1;
pub const EOFBIT: u32 = 2;
pub const FAILBIT: u32 = 4;

const TypeRecord = struct {
    typeinfo: u64 = 0,
    vtable: u64 = 0,
};

pub const Model = struct {
    builder: vtables.Builder = .{},
    types: [std.enums.values(Kind).len]TypeRecord = [_]TypeRecord{.{}} ** std.enums.values(Kind).len,
    objects_initialized: u64 = 0,

    pub fn reset(self: *Model) void {
        self.* = .{};
    }

    pub fn ensureType(self: *Model, state: anytype, kind: Kind, virtual_base_offset: ?i64) ?TypeRecord {
        const record = &self.types[@intFromEnum(kind)];
        if (record.vtable != 0) return record.*;
        const name = @tagName(kind);
        const name_address = state.guestAlloc(name.len + 1, 1) orelse return null;
        const name_bytes = state.guestMemory(name_address, name.len + 1) orelse return null;
        @memcpy(name_bytes[0..name.len], name);
        name_bytes[name.len] = 0;
        const typeinfo = state.guestAlloc(16, @alignOf(u64)) orelse return null;
        state.write64(typeinfo, 0);
        state.write64(typeinfo + 8, name_address);
        if (@hasDecl(@TypeOf(state.*), "registerSyntheticRegion")) {
            state.registerSyntheticRegion(
                typeinfo,
                16,
                .synthetic_typeinfo,
                name,
                .{ .kind = .guest_backed, .may_dereference = true, .owner = name },
            );
        }
        const virtual_bases: []const i64 = if (virtual_base_offset) |offset| &.{offset} else &.{};
        const table = self.builder.create(state, .{
            .type_name = name,
            .typeinfo = typeinfo,
            .virtual_base_offsets = virtual_bases,
            .virtual_slots = &.{0},
        }) orelse return null;
        record.* = .{ .typeinfo = typeinfo, .vtable = table.address_point };
        return record.*;
    }

    pub fn initializeBasicIos(self: *Model, state: anytype, object: u64, streambuf: u64) bool {
        if (state.guestMemory(object, stream_layout.size) == null) return false;
        const record = self.ensureType(state, .basic_ios, null) orelse return false;
        state.write64(object, record.vtable);
        state.write64(object + stream_layout.rdbuf_offset, streambuf);
        state.write32(object + stream_layout.state_offset, 0);
        state.write32(object + stream_layout.exceptions_offset, 0);
        state.write64(object + stream_layout.tie_offset, 0);
        state.write64(object + stream_layout.locale_offset, 0);
        state.write8(object + stream_layout.fill_offset, ' ');
        self.markObject(state, object, stream_layout.size, .basic_ios);
        self.objects_initialized +|= 1;
        return true;
    }

    pub fn initializeStream(self: *Model, state: anytype, kind: Kind, object: u64, streambuf: u64) bool {
        if (kind != .basic_istream and kind != .basic_ostream and kind != .basic_iostream) return false;
        if (state.guestMemory(object, stream_layout.size) == null) return false;
        // basic_istream/basic_ostream virtually inherit basic_ios. Even when
        // Rosette's compact model uses a zero adjustment, vtable[-3] must
        // exist because libc++ constructor code reads that ABI slot.
        const record = self.ensureType(state, kind, 0) orelse return false;
        state.write64(object, record.vtable);
        state.write64(object + stream_layout.rdbuf_offset, streambuf);
        state.write32(object + stream_layout.state_offset, 0);
        state.write32(object + stream_layout.exceptions_offset, 0);
        state.write64(object + stream_layout.tie_offset, 0);
        state.write64(object + stream_layout.locale_offset, 0);
        state.write8(object + stream_layout.fill_offset, ' ');
        self.markObject(state, object, stream_layout.size, kind);
        self.objects_initialized +|= 1;
        return true;
    }

    pub fn initializeStreamBase(self: *Model, state: anytype, kind: Kind, object: u64) bool {
        if (kind != .basic_istream and kind != .basic_ostream and kind != .basic_iostream) return false;
        const size = if (kind == .basic_istream) BASIC_ISTREAM_GCOUNT_OFFSET + @sizeOf(u64) else @sizeOf(u64);
        if (state.guestMemory(object, size) == null) return false;
        const record = self.ensureType(state, kind, 0) orelse return false;
        state.write64(object, record.vtable);
        if (kind == .basic_istream) state.write64(object + BASIC_ISTREAM_GCOUNT_OFFSET, 0);
        self.markObject(state, object, size, kind);
        self.objects_initialized +|= 1;
        return true;
    }

    pub fn initializeStreambufBase(self: *Model, state: anytype, object: u64) bool {
        if (state.guestMemory(object, @sizeOf(u64)) == null) return false;
        const record = self.ensureType(state, .basic_streambuf, null) orelse return false;
        state.write64(object, record.vtable);
        self.markObject(state, object, @sizeOf(u64), .basic_streambuf);
        self.objects_initialized +|= 1;
        return true;
    }

    pub fn initializeIfstream(self: *Model, state: anytype, object: u64) bool {
        if (state.guestMemory(object, IFSTREAM_SIZE) == null) return false;
        const ifstream = self.ensureType(state, .basic_ifstream, @intCast(BASIC_IOS_OFFSET_IN_IFSTREAM)) orelse return false;
        const filebuf = self.ensureType(state, .basic_filebuf, null) orelse return false;
        state.write64(object, ifstream.vtable);
        state.write64(object + BASIC_ISTREAM_GCOUNT_OFFSET, 0);
        state.write64(object + FILEBUF_OFFSET_IN_IFSTREAM, filebuf.vtable);
        if (!self.initializeBasicIos(state, object + BASIC_IOS_OFFSET_IN_IFSTREAM, object + FILEBUF_OFFSET_IN_IFSTREAM)) return false;
        self.markObject(state, object, IFSTREAM_SIZE, .basic_ifstream);
        self.objects_initialized +|= 1;
        return true;
    }

    pub fn rdbuf(_: *const Model, state: anytype, object: u64) u64 {
        return state.read64(object + stream_layout.rdbuf_offset);
    }

    pub fn rdstate(_: *const Model, state: anytype, object: u64) u32 {
        return state.read32(object + stream_layout.state_offset);
    }

    pub fn clear(_: *Model, state: anytype, object: u64, value: u32) bool {
        if (state.guestMemory(object, stream_layout.size) == null) return false;
        state.write32(object + stream_layout.state_offset, value);
        return true;
    }

    pub fn setstate(self: *Model, state: anytype, object: u64, value: u32) bool {
        return self.clear(state, object, self.rdstate(state, object) | value);
    }

    pub fn good(self: *const Model, state: anytype, object: u64) bool {
        return self.rdstate(state, object) == 0;
    }

    pub fn fail(self: *const Model, state: anytype, object: u64) bool {
        return self.rdstate(state, object) & (BADBIT | FAILBIT) != 0;
    }

    pub fn eof(self: *const Model, state: anytype, object: u64) bool {
        return self.rdstate(state, object) & EOFBIT != 0;
    }

    fn markObject(_: *Model, state: anytype, object: u64, size: u64, kind: Kind) void {
        if (@hasDecl(@TypeOf(state.*), "registerSyntheticRegion")) {
            state.registerSyntheticRegion(
                object,
                size,
                .synthetic_object,
                @tagName(kind),
                .{ .kind = .caller_storage, .may_dereference = true, .owner = @tagName(kind) },
            );
        }
    }
};

const TestState = struct {
    mem: [4096]u8 = [_]u8{0} ** 4096,
    next: u64 = 1024,
    marked_objects: u64 = 0,
    pub fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
        const address = std.mem.alignForward(u64, self.next, alignment);
        if (address + size > self.mem.len) return null;
        self.next = address + size;
        return address;
    }
    pub fn guestMemory(self: *@This(), address: u64, size: u64) ?[]u8 {
        if (address + size > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + size)];
    }
    pub fn guestMemoryConst(self: *const @This(), address: u64, size: u64) ?[]const u8 {
        if (address + size > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + size)];
    }
    pub fn read32(self: *const @This(), address: u64) u32 {
        return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
    }
    pub fn read64(self: *const @This(), address: u64) u64 {
        return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
    }
    pub fn write8(self: *@This(), address: u64, value: u8) void {
        self.mem[@intCast(address)] = value;
    }
    pub fn write32(self: *@This(), address: u64, value: u32) void {
        std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
    }
    pub fn write64(self: *@This(), address: u64, value: u64) void {
        std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
    }
    pub fn registerSyntheticRegion(self: *@This(), _: u64, _: u64, kind: @import("dyld").memory_provenance.RegionKind, _: []const u8, _: @import("dyld").pointer_firewall.Policy) void {
        if (kind == .synthetic_object) self.marked_objects +|= 1;
    }
};

test "C++ object model initializes dereferenceable stream state" {
    var state = TestState{};
    var model = Model{};
    try std.testing.expect(model.initializeStream(&state, .basic_ostream, 64, 0x300));
    try std.testing.expect(state.read64(64) != 0);
    try std.testing.expectEqual(@as(u64, 0x300), model.rdbuf(&state, 64));
    try std.testing.expect(model.setstate(&state, 64, 0x4));
    try std.testing.expectEqual(@as(u32, 0x4), model.rdstate(&state, 64));
    try std.testing.expect(model.fail(&state, 64));
    try std.testing.expect(!model.good(&state, 64));
    try std.testing.expect(!model.eof(&state, 64));
    try std.testing.expect(state.marked_objects != 0);
}

test "C++ object model gives ifstream coherent base subobjects" {
    var state = TestState{};
    var model = Model{};
    try std.testing.expect(model.initializeIfstream(&state, 64));
    try std.testing.expect(state.read64(64) != 0);
    try std.testing.expect(state.read64(64 + FILEBUF_OFFSET_IN_IFSTREAM) != 0);
    try std.testing.expect(state.read64(64 + BASIC_IOS_OFFSET_IN_IFSTREAM) != 0);
    try std.testing.expectEqual(@as(u64, 64 + FILEBUF_OFFSET_IN_IFSTREAM), model.rdbuf(&state, 64 + BASIC_IOS_OFFSET_IN_IFSTREAM));
}
