const std = @import("std");
const memory_provenance = @import("memory_provenance.zig");
const pointer_firewall = @import("pointer_firewall.zig");

pub const Spec = struct {
    type_name: []const u8,
    offset_to_top: i64 = 0,
    typeinfo: u64,
    virtual_base_offsets: []const i64 = &.{},
    virtual_slots: []const u64 = &.{},
};

pub const BuiltVtable = struct {
    allocation: u64,
    size: u64,
    address_point: u64,
    typeinfo: u64,
    offset_to_top: i64,
};

pub const Builder = struct {
    created: u64 = 0,
    validation_failures: u64 = 0,

    pub fn create(self: *Builder, state: anytype, spec: Spec) ?BuiltVtable {
        const prefix_entries = spec.virtual_base_offsets.len + 2;
        const total_entries = prefix_entries + @max(spec.virtual_slots.len, 1);
        const size: u64 = @intCast(total_entries * @sizeOf(u64));
        const allocation = state.guestAlloc(size, @alignOf(u64)) orelse return null;
        const storage = state.guestMemory(allocation, size) orelse return null;
        @memset(storage, 0);
        const address_point = allocation + @as(u64, @intCast(prefix_entries * @sizeOf(u64)));

        for (spec.virtual_base_offsets, 0..) |offset, index| {
            const slot = allocation + @as(u64, @intCast(index * @sizeOf(u64)));
            state.write64(slot, @bitCast(offset));
        }
        state.write64(address_point - 16, @bitCast(spec.offset_to_top));
        state.write64(address_point - 8, spec.typeinfo);
        for (spec.virtual_slots, 0..) |target, index| {
            state.write64(address_point + @as(u64, @intCast(index * @sizeOf(u64))), target);
        }

        if (@hasDecl(@TypeOf(state.*), "registerSyntheticRegion")) {
            state.registerSyntheticRegion(
                allocation,
                size,
                .synthetic_vtable,
                spec.type_name,
                .{ .kind = .guest_backed, .may_dereference = true, .owner = spec.type_name },
            );
        }
        self.created +|= 1;
        const built = BuiltVtable{
            .allocation = allocation,
            .size = size,
            .address_point = address_point,
            .typeinfo = spec.typeinfo,
            .offset_to_top = spec.offset_to_top,
        };
        if (!self.validate(state, built)) return null;
        return built;
    }

    pub fn validate(self: *Builder, state: anytype, vtable: BuiltVtable) bool {
        const offset: i64 = @bitCast(state.read64(vtable.address_point - 16));
        const typeinfo = state.read64(vtable.address_point - 8);
        const valid = offset == vtable.offset_to_top and typeinfo == vtable.typeinfo and
            state.guestMemoryConst(vtable.allocation, vtable.size) != null;
        if (!valid) self.validation_failures +|= 1;
        return valid;
    }
};

const TestState = struct {
    mem: [512]u8 = [_]u8{0} ** 512,
    next: u64 = 64,
    marked_kind: ?memory_provenance.RegionKind = null,
    marked_policy: ?pointer_firewall.Policy = null,

    fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
        const address = std.mem.alignForward(u64, self.next, alignment);
        if (address + size > self.mem.len) return null;
        self.next = address + size;
        return address;
    }
    fn guestMemory(self: *@This(), address: u64, size: u64) ?[]u8 {
        if (address + size > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + size)];
    }
    fn guestMemoryConst(self: *const @This(), address: u64, size: u64) ?[]const u8 {
        if (address + size > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + size)];
    }
    fn read64(self: *const @This(), address: u64) u64 {
        return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
    }
    fn write64(self: *@This(), address: u64, value: u64) void {
        std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
    }
    fn registerSyntheticRegion(self: *@This(), _: u64, _: u64, kind: memory_provenance.RegionKind, _: []const u8, policy: pointer_firewall.Policy) void {
        self.marked_kind = kind;
        self.marked_policy = policy;
    }
};

test "Itanium vtable builder writes canonical negative headers and slots" {
    var state = TestState{};
    var builder = Builder{};
    const built = builder.create(&state, .{
        .type_name = "Derived",
        .offset_to_top = -16,
        .typeinfo = 0x40,
        .virtual_base_offsets = &.{24},
        .virtual_slots = &.{ 0xAA, 0xBB },
    }).?;
    try std.testing.expectEqual(@as(u64, 24), state.read64(built.address_point - 24));
    try std.testing.expectEqual(@as(i64, -16), @as(i64, @bitCast(state.read64(built.address_point - 16))));
    try std.testing.expectEqual(@as(u64, 0x40), state.read64(built.address_point - 8));
    try std.testing.expectEqual(@as(u64, 0xAA), state.read64(built.address_point));
    try std.testing.expectEqual(memory_provenance.RegionKind.synthetic_vtable, state.marked_kind.?);
    try std.testing.expect(state.marked_policy.?.may_dereference);
}
