//! Cache only a registry position. Every hit rechecks live range and identity;
//! no names or guest/native pointers survive a registry's lifetime.
const process = @import("../../process.zig");
const metadata = @import("import_metadata.zig");
const capacity = 1024;
const Slot = struct { owner: usize = 0, address: u64 = 0, index: usize = 0 };
threadlocal var slots: [capacity]Slot = @splat(.{});
pub const retained_bytes = @sizeOf(@TypeOf(slots));
/// Differential fixture control; ordinary host workers start enabled.
pub threadlocal var enabled = true;
pub fn lookup(self: *const process.ElfState, address: u64, start: usize) ?process.WindowsImportStub {
    const stats = metadata.forState(self);
    stats.stub_lookups +|= 1;
    stats.dynamic_entries_peak = @max(stats.dynamic_entries_peak, self.windows_stub_count - start);
    const identity = @intFromPtr(self);
    const hash = (address ^ (@as(u64, @intCast(identity)) >> 4)) *% 0x9E3779B97F4A7C15;
    const slot = &slots[@intCast(hash >> 54)];
    if (enabled and slot.owner == identity and slot.address == address and
        slot.index >= start and slot.index < self.windows_stub_count)
    {
        const registered = self.windows_stub_storage[slot.index];
        if (registered.address == address) {
            stats.stub_hits +|= 1;
            var result = registered;
            result.is_dynamic = true;
            return result;
        }
    }
    for (self.windows_stub_storage[start..self.windows_stub_count], start..) |registered, index| {
        if (registered.address != address) continue;
        stats.stub_scanned +|= index - start + 1;
        if (enabled) slot.* = .{ .owner = identity, .address = address, .index = index };
        var result = registered;
        result.is_dynamic = true;
        return result;
    }
    stats.stub_scanned +|= self.windows_stub_count - start;
    return null;
}
