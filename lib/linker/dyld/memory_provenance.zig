const std = @import("std");

pub const RegionKind = enum {
    macho_text,
    macho_data,
    macho_const,
    guest_heap,
    guest_mmap,
    guest_unmapped,
    guest_stack,
    synthetic_vtable,
    synthetic_typeinfo,
    synthetic_object,
    synthetic_handle,
    import_got,
    lazy_bind_stub,
    synthetic_thunk,
    pthread_stack,
    file_buffer,
    objc_handle,
};

pub const Permissions = packed struct {
    read: bool = true,
    write: bool = true,
    execute: bool = false,
};

pub const Region = struct {
    start: u64,
    end: u64,
    permissions: Permissions,
    kind: RegionKind,
    owner: []const u8,
    allocation_site: u64 = 0,
    generation: u64,

    pub fn contains(self: Region, address: u64, size: u64) bool {
        const end = std.math.add(u64, address, size) catch return false;
        return address >= self.start and end <= self.end;
    }

    pub fn isSynthetic(self: Region) bool {
        return switch (self.kind) {
            .synthetic_vtable, .synthetic_typeinfo, .synthetic_object, .synthetic_handle, .lazy_bind_stub, .synthetic_thunk, .objc_handle => true,
            else => false,
        };
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    regions: std.ArrayList(Region) = .empty,
    generation: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.regions.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn register(self: *Registry, start: u64, size: u64, permissions: Permissions, kind: RegionKind, owner: []const u8, allocation_site: u64) bool {
        if (size == 0) return false;
        const end = std.math.add(u64, start, size) catch return false;
        self.generation +|= 1;
        self.regions.append(self.allocator, .{
            .start = start,
            .end = end,
            .permissions = permissions,
            .kind = kind,
            .owner = owner,
            .allocation_site = allocation_site,
            .generation = self.generation,
        }) catch return false;
        return true;
    }

    /// Newer, more-specific registrations override older encompassing ones.
    pub fn find(self: *const Registry, address: u64, size: u64) ?Region {
        var index = self.regions.items.len;
        while (index > 0) {
            index -= 1;
            const region = self.regions.items[index];
            if (region.contains(address, size)) return region;
        }
        return null;
    }

    /// Returns whether an address is an intentionally executable synthetic
    /// thunk. Synthetic thunks don't have guest memory backing, so normal
    /// page-permission checks can't recognize them. Keep this decision in the
    /// provenance registry so the newest-registration-wins rule also applies
    /// to control transfers.
    pub fn permitsSyntheticExecution(self: *const Registry, address: u64, size: u64) bool {
        const region = self.find(address, size) orelse return false;
        return region.start == address and
            region.kind == .synthetic_thunk and
            region.permissions.execute;
    }

    pub fn removeExact(self: *Registry, start: u64) void {
        var index = self.regions.items.len;
        while (index > 0) {
            index -= 1;
            if (self.regions.items[index].start == start) {
                _ = self.regions.swapRemove(index);
                return;
            }
        }
    }
};

test "typed regions prefer the newest specific provenance" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expect(registry.register(0x1000, 0x1000, .{}, .guest_heap, "allocator", 0x40));
    try std.testing.expect(registry.register(0x1400, 0x80, .{ .write = false }, .synthetic_vtable, "std::ostream", 0x88));
    const vtable = registry.find(0x1410, 8).?;
    try std.testing.expectEqual(RegionKind.synthetic_vtable, vtable.kind);
    try std.testing.expectEqualStrings("std::ostream", vtable.owner);
    try std.testing.expect(!vtable.permissions.write);
    try std.testing.expectEqual(RegionKind.guest_heap, registry.find(0x1200, 8).?.kind);
}

test "only executable synthetic thunks permit unbacked execution" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.register(
        0xFFFF_FC00_0000_000C,
        6,
        .{ .read = false, .write = false, .execute = true },
        .synthetic_thunk,
        "_calloc",
        0,
    ));
    try std.testing.expect(registry.permitsSyntheticExecution(0xFFFF_FC00_0000_000C, 1));
    try std.testing.expect(!registry.permitsSyntheticExecution(0xFFFF_FC00_0000_0011, 1));
    try std.testing.expect(!registry.permitsSyntheticExecution(0xFFFF_FC00_0000_0012, 1));

    try std.testing.expect(registry.register(
        0xFFFF_FC00_0000_000C,
        1,
        .{ .read = false, .write = false, .execute = false },
        .synthetic_handle,
        "revoked callback",
        0,
    ));
    try std.testing.expect(!registry.permitsSyntheticExecution(0xFFFF_FC00_0000_000C, 1));
    try std.testing.expect(!registry.permitsSyntheticExecution(0xFFFF_FC00_0000_000D, 1));
}
