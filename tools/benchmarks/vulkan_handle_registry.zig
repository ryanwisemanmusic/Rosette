//! Compile twice with the registry module before/after the change. CPU only;
//! prepopulate immutable identities, then validate every timed lookup result.
const std = @import("std");
const Entry = @import("registry").Entry;
fn now() u64 {
    var value: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &value) != 0) unreachable;
    return @as(u64, @intCast(value.sec)) * 1_000_000_000 + @as(u64, @intCast(value.nsec));
}
pub fn main() !void {
    const slots = try std.heap.page_allocator.alloc(Entry, 16384);
    defer std.heap.page_allocator.free(slots);
    for (slots, 0..) |*slot, i| slot.* = .{ .synthetic = 0x1000 + (i + 1) * 16, .real = 0x8000 + (i + 1) * 32 };
    const started = now();
    var checksum: u64 = 0;
    for (0..4096) |i| {
        const index = (i * 7919) % slots.len;
        const value = Entry.findReal(slots, 0x1000 + (index + 1) * 16) orelse return error.MissingIdentity;
        if (value != 0x8000 + (index + 1) * 32) return error.WrongIdentity;
        checksum +%= value;
    }
    std.debug.print("registry cold ns={d} lookups=4096 checksum={d}\n", .{ now() - started, checksum });
    const warm = now();
    for (0..2000000) |_| {
        const value = Entry.findReal(slots, 0x1010) orelse return error.MissingIdentity;
        if (value != 0x8020) return error.WrongIdentity;
        checksum +%= value;
    }
    std.debug.print("registry warm ns={d} lookups=2000000 checksum={d}\n", .{ now() - warm, checksum });
    const missed = now();
    for (0..4096) |i| {
        if (Entry.findReal(slots, 0x10000000 + i) != null) return error.InventedIdentity;
    }
    std.debug.print("registry absent ns={d} lookups=4096 checksum={d}\n", .{ now() - missed, checksum });
}
