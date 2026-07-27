const std = @import("std");

pub const MAX_TRACKED_SLOTS: usize = 131_072;

pub const Entry = struct {
    address: u64,
    previous_value: u64,
    value: u64,
    instruction_address: u64,
    step: u64,
    thread: u64,
};

pub const Tracker = struct {
    entries: std.AutoHashMapUnmanaged(u64, Entry) = .empty,
    dropped_slots: u64 = 0,

    pub fn deinit(self: *Tracker, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn record(
        self: *Tracker,
        allocator: std.mem.Allocator,
        address: u64,
        previous_value: u64,
        value: u64,
        instruction_address: u64,
        step: u64,
        thread: u64,
    ) void {
        if (address < 0x1000 or (address & 7) != 0) return;
        // Retain pointer-bearing transitions rather than every integer store.
        // A clear of a pointer is still retained because its previous value is
        // pointer-sized, while bulk initialization with zero stays cheap.
        if (previous_value < 0x1000 and value < 0x1000) return;

        const entry = Entry{
            .address = address,
            .previous_value = previous_value,
            .value = value,
            .instruction_address = instruction_address,
            .step = step,
            .thread = thread,
        };
        if (self.entries.getPtr(address)) |existing| {
            existing.* = entry;
            return;
        }
        if (self.entries.count() >= MAX_TRACKED_SLOTS) {
            self.dropped_slots +|= 1;
            return;
        }
        self.entries.put(allocator, address, entry) catch {
            self.dropped_slots +|= 1;
        };
    }

    pub fn lookup(self: *const Tracker, address: u64) ?Entry {
        return self.entries.get(address);
    }

    pub fn forget(self: *Tracker, address: u64) void {
        _ = self.entries.remove(address);
    }

    /// Returns the most recent non-null value associated with a tracked slot.
    /// If the last observed write cleared the slot, the value immediately
    /// preceding that clear is returned. Callers must independently validate
    /// that the value is meaningful for their domain before using it.
    pub fn lastNonNullValue(self: *const Tracker, address: u64) ?u64 {
        const entry = self.lookup(address) orelse return null;
        if (entry.value >= 0x1000) return entry.value;
        if (entry.previous_value >= 0x1000) return entry.previous_value;
        return null;
    }
};

test "memory write provenance retains the last writer for a slot" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0x4000, 0x1234, 0, 0x2000, 77, 9);
    const entry = tracker.lookup(0x4000).?;
    try std.testing.expectEqual(@as(u64, 0x1234), entry.previous_value);
    try std.testing.expectEqual(@as(u64, 0), entry.value);
    try std.testing.expectEqual(@as(u64, 0x2000), entry.instruction_address);
    try std.testing.expectEqual(@as(u64, 77), entry.step);
    try std.testing.expectEqual(@as(u64, 9), entry.thread);
}

test "memory write provenance updates existing slots" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0x8000, 0, 0x2000, 3, 4, 5);
    tracker.record(std.testing.allocator, 0x8000, 0x2000, 0x6000, 7, 8, 9);
    try std.testing.expectEqual(@as(usize, 1), tracker.entries.count());
    try std.testing.expectEqual(@as(u64, 0x6000), tracker.lookup(0x8000).?.value);
}

test "memory write provenance retains a non-null recovery candidate" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);

    tracker.record(std.testing.allocator, 0x9000, 0x1234, 0, 7, 8, 9);
    try std.testing.expectEqual(@as(u64, 0x1234), tracker.lastNonNullValue(0x9000).?);

    tracker.record(std.testing.allocator, 0x9000, 0, 0x5678, 10, 11, 12);
    try std.testing.expectEqual(@as(u64, 0x5678), tracker.lastNonNullValue(0x9000).?);
}
