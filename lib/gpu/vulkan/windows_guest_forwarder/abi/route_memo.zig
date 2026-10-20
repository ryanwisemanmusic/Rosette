//! Everything the Microsoft-ABI Vulkan adapter derives from an entry point's
//! name, derived once per name instead of on every call.
//!
//! Each `Bridge.dispatch` used to compare the name it was handed against
//! dozens of strings: ownership and the ABI facts (`route_metadata.zig`,
//! which `vkCmd*` bypassed), whether it is the surface call, a command, a
//! frame-evidence boundary, which logical contract it completes, and then the
//! loader's own symbol lookup, which hashes and compares it again and checks
//! the device's optional capabilities. Xenia makes about 17,000 of these
//! calls in a heavy frame, almost all to the same dozen command names.
//!
//! A slot keeps a copy of its name, so a hit compares the bytes and a reused
//! name pointer cannot inherit another name's route. The loader token is kept
//! with the adapter instance (`Bridge.route_instance`), library and native
//! device it was looked up for and is looked up again when any changes. Slots are per host thread, as in
//! `route_metadata.zig`: no lock and no sharing.
const std = @import("std");
const route_metadata = @import("route_metadata.zig");

/// Which logical-contract note a completed call makes
/// (`windows_guest_forwarder.noteContract`).
pub const Contract = enum(u8) {
    observed,
    command,
    create_instance,
    create_surface,
    create_device,
    get_queue,
    create_swapchain,
    swapchain_images,
    acquire,
    submit,
    present,

    /// Entry points that return a VkResult; void commands leave RAX
    /// unspecified.
    pub fn resultBearing(contract: Contract) bool {
        return switch (contract) {
            .observed, .command, .get_queue => false,
            else => true,
        };
    }
};

pub const Route = struct {
    facts: route_metadata.Facts,
    /// `vkCmd*`: a command recorded into a command buffer.
    command: bool = false,
    /// `vkCreateWin32SurfaceKHR`, forwarded as `vkCreateMetalSurfaceEXT`.
    surface: bool = false,
    /// A submit or present: the forwarder's frame evidence is copied after it.
    frame_evidence: bool = false,
    contract: Contract = .observed,
    /// The loader token for this name, for the adapter `token_owner`, its
    /// library `token_library` and the native device `token_device`; 0 until
    /// looked up.
    token: u64 = 0,
    token_owner: u64 = 0,
    token_library: u64 = 0,
    token_device: usize = 0,
};

const name_bytes = 80;
const Slot = struct { key: usize = 0, name: [name_bytes]u8 = undefined, length: usize = 0, route: Route = undefined };
threadlocal var slots: [128]Slot = @splat(.{});
threadlocal var spare: Route = undefined;

/// Offline control: false derives every call's route from its name again.
pub var enabled = true;

/// The route for `name`. The pointer is this host thread's slot (or a
/// scratch copy for a name too long to keep): valid until this thread's next
/// lookup, which is all a dispatch needs.
pub fn lookup(comptime derive: fn ([]const u8) Route, name: []const u8, counts: *route_metadata.Counts) *Route {
    counts.lookups +|= 1;
    if (enabled and name.len != 0 and name.len <= name_bytes) {
        const key = @intFromPtr(name.ptr);
        const hash = (@as(u64, @intCast(key)) ^ @as(u64, @intCast(name.len))) *% 0x9E3779B97F4A7C15;
        const slot = &slots[@intCast(hash >> 57)];
        if (slot.key == key and slot.length == name.len and std.mem.eql(u8, slot.name[0..slot.length], name)) {
            counts.hits +|= 1;
            return &slot.route;
        }
        slot.route = derive(name);
        slot.key = key;
        slot.length = name.len;
        @memcpy(slot.name[0..name.len], name);
        counts.misses +|= 1;
        return &slot.route;
    }
    counts.misses +|= 1;
    spare = derive(name);
    return &spare;
}

/// A process-unique number for each adapter, so one adapter's tokens never
/// answer for another's (two adapters may share an address in turn).
pub fn newOwner() u64 {
    return next_owner.fetchAdd(1, .monotonic);
}
var next_owner = std.atomic.Value(u64).init(1);

/// The memoized loader token, when it was looked up by this adapter for this
/// library and device. A token is kept only once a device exists: before
/// that the loader's answer for an optional entry point can still change.
pub fn token(route: *const Route, owner: u64, library: u64, device: usize) ?u64 {
    if (!enabled or route.token == 0 or owner == 0 or device == 0) return null;
    if (route.token_owner != owner or route.token_library != library or route.token_device != device) return null;
    return route.token;
}

pub fn keepToken(route: *Route, value: u64, owner: u64, library: u64, device: usize) void {
    if (!enabled or value == 0 or owner == 0 or device == 0) return;
    route.token = value;
    route.token_owner = owner;
    route.token_library = library;
    route.token_device = device;
}

fn testDerive(name: []const u8) Route {
    return .{
        .facts = .{ .owned = true, .signature = null, .float_count = name.len },
        .command = std.mem.startsWith(u8, name, "vkCmd"),
    };
}

test "a route is derived once per name, and a reused name pointer derives its own" {
    var counts: route_metadata.Counts = .{};
    var mutable: [24]u8 = undefined;
    const a = "vkCmdDrawIndexed";
    const b = "vkQueueSubmit2KHR";
    @memcpy(mutable[0..a.len], a);
    const first = lookup(testDerive, mutable[0..a.len], &counts);
    try std.testing.expect(first.command);
    const owner = newOwner();
    keepToken(first, 0x51, owner, 1, 0xD0);
    const again = lookup(testDerive, mutable[0..a.len], &counts);
    try std.testing.expectEqual(@as(u64, 1), counts.hits);
    try std.testing.expectEqual(@as(?u64, 0x51), token(again, owner, 1, 0xD0));
    // Another adapter, library or device looks the token up again.
    try std.testing.expectEqual(@as(?u64, null), token(again, newOwner(), 1, 0xD0));
    try std.testing.expectEqual(@as(?u64, null), token(again, owner, 2, 0xD0));
    try std.testing.expectEqual(@as(?u64, null), token(again, owner, 1, 0xE0));
    // The same storage now holds another name: its own route, no token.
    @memcpy(mutable[0..b.len], b);
    const other = lookup(testDerive, mutable[0..b.len], &counts);
    try std.testing.expect(!other.command);
    try std.testing.expectEqual(@as(usize, b.len), other.facts.float_count);
    try std.testing.expectEqual(@as(?u64, null), token(other, owner, 1, 0xD0));
    // No device yet: nothing is kept.
    keepToken(other, 0x77, owner, 1, 0);
    try std.testing.expectEqual(@as(?u64, null), token(other, owner, 1, 0));
}

test "a name too long for a slot is derived on every call" {
    var counts: route_metadata.Counts = .{};
    const long = "vk" ++ "X" ** 90;
    const route = lookup(testDerive, long, &counts);
    try std.testing.expectEqual(@as(usize, long.len), route.facts.float_count);
    _ = lookup(testDerive, long, &counts);
    try std.testing.expectEqual(@as(u64, 0), counts.hits);
    try std.testing.expectEqual(@as(u64, 2), counts.misses);
}
