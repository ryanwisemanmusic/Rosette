const std = @import("std");
const memory_provenance = @import("memory_provenance.zig");
const pointer_firewall = @import("pointer_firewall.zig");

pub const Category = enum {
    typeinfo,
    type_name,
    vtable,
    construction_vtable,
    vtt,
    guard,
    reference_temporary,
    unknown,
};

pub const Result = struct {
    address: u64,
    category: Category,
};

pub fn classify(symbol: []const u8) Category {
    if (std.mem.startsWith(u8, symbol, "__ZTI")) return .typeinfo;
    if (std.mem.startsWith(u8, symbol, "__ZTS")) return .type_name;
    if (std.mem.startsWith(u8, symbol, "__ZTV")) return .vtable;
    if (std.mem.startsWith(u8, symbol, "__ZTC")) return .construction_vtable;
    if (std.mem.startsWith(u8, symbol, "__ZTT")) return .vtt;
    if (std.mem.startsWith(u8, symbol, "__ZGV")) return .guard;
    if (std.mem.startsWith(u8, symbol, "__ZGR")) return .reference_temporary;
    return .unknown;
}

/// Builds conservative Itanium ABI data in guest-owned storage. The records
/// are deliberately non-callable: unknown virtual slots remain null, making
/// unsupported behavior an attributable null dispatch instead of interpreting
/// a dyld slot or native ARM64 address as guest x86 code.
pub fn materialize(state: anytype, symbol: []const u8) ?Result {
    const category = classify(symbol);
    return switch (category) {
        .typeinfo => materializeTypeinfo(state, symbol),
        .type_name => materializeTypeName(state, symbol),
        .vtable, .construction_vtable => materializeZeroRecord(state, symbol, category, 32, .synthetic_vtable),
        .vtt => materializeZeroRecord(state, symbol, category, 16, .synthetic_vtable),
        .guard => materializeZeroRecord(state, symbol, category, 8, .synthetic_object),
        .reference_temporary => materializeZeroRecord(state, symbol, category, 16, .synthetic_object),
        .unknown => null,
    };
}

fn materializeTypeinfo(state: anytype, symbol: []const u8) ?Result {
    const encoded_name = symbol[@min(symbol.len, 5)..];
    const name_address = allocateBytes(state, encoded_name.len + 1, 1) orelse return null;
    const name = state.guestMemory(name_address, encoded_name.len + 1) orelse return null;
    @memcpy(name[0..encoded_name.len], encoded_name);
    name[encoded_name.len] = 0;

    const address = allocateBytes(state, 16, @alignOf(u64)) orelse return null;
    const record = state.guestMemory(address, 16) orelse return null;
    @memset(record, 0);
    state.write64(address + 8, name_address);
    registerRegion(state, address, 16, .synthetic_typeinfo, symbol);
    return .{ .address = address, .category = .typeinfo };
}

fn materializeTypeName(state: anytype, symbol: []const u8) ?Result {
    const encoded_name = symbol[@min(symbol.len, 5)..];
    const address = allocateBytes(state, encoded_name.len + 1, 1) orelse return null;
    const bytes = state.guestMemory(address, encoded_name.len + 1) orelse return null;
    @memcpy(bytes[0..encoded_name.len], encoded_name);
    bytes[encoded_name.len] = 0;
    registerRegion(state, address, encoded_name.len + 1, .synthetic_object, symbol);
    return .{ .address = address, .category = .type_name };
}

fn materializeZeroRecord(state: anytype, symbol: []const u8, category: Category, size: u64, kind: anytype) ?Result {
    const address = allocateBytes(state, size, @alignOf(u64)) orelse return null;
    const bytes = state.guestMemory(address, size) orelse return null;
    @memset(bytes, 0);
    registerRegion(state, address, size, kind, symbol);
    return .{ .address = address, .category = category };
}

fn allocateBytes(state: anytype, size: u64, alignment: u64) ?u64 {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "guestAlloc")) return state.guestAlloc(size, alignment);
    return null;
}

fn registerRegion(state: anytype, address: u64, size: u64, kind: anytype, owner: []const u8) void {
    const State = @TypeOf(state.*);
    if (comptime @hasDecl(State, "registerSyntheticRegion")) {
        state.registerSyntheticRegion(
            address,
            size,
            kind,
            owner,
            .{ .kind = .guest_backed, .may_dereference = true, .owner = owner },
        );
    }
}

test "Itanium ABI symbols are classified without application-specific names" {
    try std.testing.expectEqual(Category.typeinfo, classify("__ZTINSt3__112system_errorE"));
    try std.testing.expectEqual(Category.type_name, classify("__ZTSNSt3__112system_errorE"));
    try std.testing.expectEqual(Category.vtable, classify("__ZTVNSt3__112system_errorE"));
    try std.testing.expectEqual(Category.construction_vtable, classify("__ZTC1A0_1B"));
    try std.testing.expectEqual(Category.vtt, classify("__ZTT1A"));
    try std.testing.expectEqual(Category.guard, classify("__ZGVZ1fvE1x"));
    try std.testing.expectEqual(Category.reference_temporary, classify("__ZGRZ1fvE1x_"));
}

const TestState = struct {
    memory: [512]u8 = [_]u8{0xAA} ** 512,
    next: u64 = 64,
    registrations: u64 = 0,
    last_kind: ?memory_provenance.RegionKind = null,

    fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
        const address = std.mem.alignForward(u64, self.next, alignment);
        if (address + size > self.memory.len) return null;
        self.next = address + size;
        return address;
    }

    fn guestMemory(self: *@This(), address: u64, size: u64) ?[]u8 {
        if (address + size > self.memory.len) return null;
        return self.memory[@intCast(address)..@intCast(address + size)];
    }

    fn write64(self: *@This(), address: u64, value: u64) void {
        std.mem.writeInt(u64, self.memory[@intCast(address)..][0..8], value, .little);
    }

    fn read64(self: *const @This(), address: u64) u64 {
        return std.mem.readInt(u64, self.memory[@intCast(address)..][0..8], .little);
    }

    fn registerSyntheticRegion(
        self: *@This(),
        _: u64,
        _: u64,
        kind: memory_provenance.RegionKind,
        _: []const u8,
        policy: pointer_firewall.Policy,
    ) void {
        std.debug.assert(policy.may_dereference);
        self.registrations +|= 1;
        self.last_kind = kind;
    }
};

test "typeinfo materialization creates a guest-backed record and name" {
    var state = TestState{};
    const result = materialize(&state, "__ZTIN3foo5ErrorE").?;
    try std.testing.expectEqual(Category.typeinfo, result.category);
    try std.testing.expectEqual(@as(u64, 0), state.read64(result.address));
    const name_address = state.read64(result.address + 8);
    try std.testing.expectEqualStrings("N3foo5ErrorE", std.mem.sliceTo(state.memory[@intCast(name_address)..], 0));
    try std.testing.expectEqual(memory_provenance.RegionKind.synthetic_typeinfo, state.last_kind.?);
}

test "vtable materialization is zeroed and relocation-safe" {
    var state = TestState{};
    const result = materialize(&state, "__ZTVN3foo5ErrorE").?;
    try std.testing.expectEqual(Category.vtable, result.category);
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[@intCast(result.address)..@intCast(result.address + 32)]);
    try std.testing.expectEqual(memory_provenance.RegionKind.synthetic_vtable, state.last_kind.?);
}
