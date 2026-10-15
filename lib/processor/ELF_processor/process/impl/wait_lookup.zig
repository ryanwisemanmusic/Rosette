//! Remember a wait-table position, never a pointer or a readiness decision.
//! Runtime-lock ownership and wait/event semantics remain with windows_sync.
const process = @import("../../process.zig");
const metadata = @import("import_metadata.zig");
const Slot = struct { owner: usize = 0, handle: u64 = 0, index: usize = 0 };
threadlocal var slots: [256]Slot = @splat(.{});
pub threadlocal var enabled = true; // differential test control only
pub fn find(self: *const process.ElfState, handle: u64) ?usize {
    if (handle == 0) return null;
    const stats = metadata.forState(self);
    stats.wait_lookups +|= 1;
    const end = self.windows_wait_object_high_water;
    stats.wait_entries_peak = @max(stats.wait_entries_peak, end);
    const owner = @intFromPtr(self);
    const hash = (handle ^ (@as(u64, @intCast(owner)) >> 4)) *% 0x9E3779B97F4A7C15;
    const slot = &slots[@intCast(hash >> 56)];
    if (enabled and slot.owner == owner and slot.handle == handle and slot.index < end and
        self.windows_wait_objects[slot.index].handle == handle)
    {
        stats.wait_hits +|= 1;
        return slot.index;
    }
    for (self.windows_wait_objects[0..end], 0..) |*object, index| {
        if (object.handle != handle) continue;
        stats.wait_scanned +|= index + 1;
        if (enabled) slot.* = .{ .owner = owner, .handle = handle, .index = index };
        return index;
    }
    stats.wait_scanned +|= end;
    return null;
}
