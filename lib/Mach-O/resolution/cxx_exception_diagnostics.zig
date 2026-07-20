const std = @import("std");

const ALLOCATION_HISTORY_LEN: usize = 32;

pub const AllocationRecord = struct {
    storage_address: u64 = 0,
    object_address: u64 = 0,
    object_size: u64 = 0,
    caller_address: u64 = 0,
};

pub const ThrowRecord = struct {
    object_address: u64 = 0,
    type_info_address: u64 = 0,
    destructor_address: u64 = 0,
    caller_address: u64 = 0,
    allocation: ?AllocationRecord = null,
};

pub const Summary = struct {
    allocations: u64,
    throws: u64,
    matched_throws: u64,
    catches_begun: u64,
    catches_ended: u64,
    caught_throws: u64,
    frees: u64,
    rethrows: u64,
    active_catches: usize,
};

pub const Tracker = struct {
    allocations: [ALLOCATION_HISTORY_LEN]AllocationRecord =
        [_]AllocationRecord{AllocationRecord{}} ** ALLOCATION_HISTORY_LEN,
    allocation_index: usize = 0,
    allocation_history_full: bool = false,
    allocation_count: u64 = 0,
    throw_count: u64 = 0,
    matched_throw_count: u64 = 0,
    active_catches: [16]u64 = [_]u64{0} ** 16,
    active_catch_count: usize = 0,
    begin_catch_count: u64 = 0,
    end_catch_count: u64 = 0,
    caught_throw_count: u64 = 0,
    free_count: u64 = 0,
    rethrow_count: u64 = 0,
    last_throw: ?ThrowRecord = null,
    last_throw_caught: bool = false,

    pub fn recordAllocation(self: *Tracker, storage_address: u64, object_address: u64, object_size: u64, caller_address: u64) void {
        self.allocations[self.allocation_index] = .{
            .storage_address = storage_address,
            .object_address = object_address,
            .object_size = object_size,
            .caller_address = caller_address,
        };
        self.allocation_index = (self.allocation_index + 1) % self.allocations.len;
        if (self.allocation_index == 0) self.allocation_history_full = true;
        self.allocation_count +|= 1;
    }

    pub fn recordThrow(
        self: *Tracker,
        object_address: u64,
        type_info_address: u64,
        destructor_address: u64,
        caller_address: u64,
    ) ThrowRecord {
        const allocation = self.findAllocation(object_address);
        const record = ThrowRecord{
            .object_address = object_address,
            .type_info_address = type_info_address,
            .destructor_address = destructor_address,
            .caller_address = caller_address,
            .allocation = allocation,
        };
        self.throw_count +|= 1;
        if (allocation != null) self.matched_throw_count +|= 1;
        self.last_throw = record;
        self.last_throw_caught = false;
        return record;
    }

    pub fn beginCatch(self: *Tracker, exception_address: u64) u64 {
        const object_address = self.exceptionPointer(exception_address);
        if (self.active_catch_count < self.active_catches.len) {
            self.active_catches[self.active_catch_count] = object_address;
            self.active_catch_count += 1;
        }
        self.begin_catch_count +|= 1;
        return object_address;
    }

    pub fn endCatch(self: *Tracker) ?u64 {
        if (self.active_catch_count == 0) return null;
        self.active_catch_count -= 1;
        const object_address = self.active_catches[self.active_catch_count];
        self.active_catches[self.active_catch_count] = 0;
        self.end_catch_count +|= 1;
        if (self.last_throw) |thrown| {
            if (thrown.object_address == object_address and !self.last_throw_caught) {
                self.last_throw_caught = true;
                self.caught_throw_count +|= 1;
            }
        }
        return object_address;
    }

    pub fn exceptionPointer(self: *const Tracker, exception_address: u64) u64 {
        if (self.findAllocation(exception_address)) |allocation| return allocation.object_address;
        const used = if (self.allocation_history_full) self.allocations.len else self.allocation_index;
        for (self.allocations[0..used]) |allocation| {
            if (allocation.object_address == 0) continue;
            if (exception_address >= allocation.storage_address and exception_address <= allocation.object_address) {
                return allocation.object_address;
            }
        }
        return exception_address;
    }

    pub fn freeException(self: *Tracker, exception_address: u64) ?AllocationRecord {
        const object_address = self.exceptionPointer(exception_address);
        const used = if (self.allocation_history_full) self.allocations.len else self.allocation_index;
        for (0..used) |index| {
            if (self.allocations[index].object_address != object_address) continue;
            const allocation = self.allocations[index];
            self.allocations[index] = .{};
            self.free_count +|= 1;
            return allocation;
        }
        return null;
    }

    pub fn recordRethrow(self: *Tracker) ?u64 {
        self.rethrow_count +|= 1;
        self.last_throw_caught = false;
        if (self.active_catch_count == 0) return null;
        return self.active_catches[self.active_catch_count - 1];
    }

    /// Returns only an exception that is still eligible to drive unwinding.
    /// `last_throw` intentionally remains available as diagnostic history
    /// after a catch, but must never resurrect a completed phase-two walk.
    pub fn activeThrow(self: *const Tracker) ?ThrowRecord {
        if (self.last_throw_caught) return null;
        return self.last_throw;
    }

    pub fn summary(self: *const Tracker) Summary {
        return .{
            .allocations = self.allocation_count,
            .throws = self.throw_count,
            .matched_throws = self.matched_throw_count,
            .catches_begun = self.begin_catch_count,
            .catches_ended = self.end_catch_count,
            .caught_throws = self.caught_throw_count,
            .frees = self.free_count,
            .rethrows = self.rethrow_count,
            .active_catches = self.active_catch_count,
        };
    }

    pub fn logSummary(self: *const Tracker) void {
        const totals = self.summary();
        if (totals.allocations == 0 and totals.throws == 0) return;
        std.debug.print(
            "macho-processor: C++ exception runtime: allocations={d} throws={d} matched={d} begin_catch={d} end_catch={d} caught_throws={d} frees={d} rethrows={d} active={d}\n",
            .{ totals.allocations, totals.throws, totals.matched_throws, totals.catches_begun, totals.catches_ended, totals.caught_throws, totals.frees, totals.rethrows, totals.active_catches },
        );
    }

    fn findAllocation(self: *const Tracker, object_address: u64) ?AllocationRecord {
        const used = if (self.allocation_history_full) self.allocations.len else self.allocation_index;
        for (0..used) |offset| {
            const index = (self.allocation_index + self.allocations.len - 1 - offset) % self.allocations.len;
            const allocation = self.allocations[index];
            if (allocation.object_address == object_address) return allocation;
        }
        return null;
    }
};

test "throw is linked to its exception allocation" {
    var tracker = Tracker{};
    tracker.recordAllocation(0x3fc0, 0x4000, 48, 0x1000);
    const thrown = tracker.recordThrow(0x4000, 0x5000, 0x6000, 0x2000);

    try std.testing.expect(thrown.allocation != null);
    try std.testing.expectEqual(@as(u64, 48), thrown.allocation.?.object_size);
    try std.testing.expectEqual(@as(u64, 0x1000), thrown.allocation.?.caller_address);
    try std.testing.expectEqual(@as(u64, 1), tracker.summary().matched_throws);
}

test "allocation history retains the newest matching object" {
    var tracker = Tracker{};
    tracker.recordAllocation(0x3fc0, 0x4000, 16, 0x1000);
    for (0..ALLOCATION_HISTORY_LEN) |index| {
        tracker.recordAllocation(0x7fc0 + index, 0x8000 + index, index + 1, 0x2000 + index);
    }
    tracker.recordAllocation(0x3fc0, 0x4000, 64, 0x3000);

    const thrown = tracker.recordThrow(0x4000, 0x5000, 0, 0x6000);
    try std.testing.expect(thrown.allocation != null);
    try std.testing.expectEqual(@as(u64, 64), thrown.allocation.?.object_size);
    try std.testing.expectEqual(@as(u64, 0x3000), thrown.allocation.?.caller_address);
}

test "catch lifecycle normalizes ABI header pointers and frees storage" {
    var tracker = Tracker{};
    tracker.recordAllocation(0x3fc0, 0x4000, 32, 0x1000);
    _ = tracker.recordThrow(0x4000, 0x5000, 0x6000, 0x2000);
    try std.testing.expectEqual(@as(u64, 0x4000), tracker.beginCatch(0x3fe0));
    try std.testing.expectEqual(@as(u64, 0x4000), tracker.recordRethrow().?);
    try std.testing.expectEqual(@as(u64, 0x4000), tracker.endCatch().?);
    try std.testing.expect(tracker.last_throw_caught);
    const allocation = tracker.freeException(0x3ff0).?;
    try std.testing.expectEqual(@as(u64, 0x3fc0), allocation.storage_address);
    try std.testing.expectEqual(@as(usize, 0), tracker.summary().active_catches);
}

test "unmatched throw remains explicit" {
    var tracker = Tracker{};
    const thrown = tracker.recordThrow(0x4000, 0x5000, 0, 0x6000);

    try std.testing.expect(thrown.allocation == null);
    try std.testing.expectEqual(@as(u64, 0), tracker.summary().matched_throws);
}

test "completed catch remains history but is not an active unwind source" {
    var tracker = Tracker{};
    tracker.recordAllocation(0x3fc0, 0x4000, 16, 0x1000);
    _ = tracker.recordThrow(0x4000, 0x5000, 0, 0x2000);
    try std.testing.expect(tracker.activeThrow() != null);
    _ = tracker.beginCatch(0x3fc0);
    _ = tracker.endCatch();
    try std.testing.expect(tracker.last_throw != null);
    try std.testing.expect(tracker.activeThrow() == null);
}
