const std = @import("std");

pub const TimerEntry = struct {
    deadline_ns: u64,
    sequence: u64,
    thread: u64,
    wait_object: u64,
    wait_generation: u64,
};

/// One virtual clock domain for guest-visible clocks and scheduler deadlines.
/// Deadlines are ordered by `(deadline, sequence)`, so equal-deadline wakeups
/// have stable FIFO behavior without depending on guest addresses or symbols.
pub const Service = struct {
    monotonic_ns: u64 = 1_000_000_000,
    wall_epoch_ns: u64 = 1_719_000_000 * 1_000_000_000,
    next_sequence: u64 = 1,
    quiescence_advances: u64 = 0,
    quiescence_advanced_ns: u64 = 0,
    deadlines: std.ArrayList(TimerEntry) = .empty,

    pub fn deinit(self: *Service, allocator: std.mem.Allocator) void {
        self.deadlines.deinit(allocator);
        self.* = .{};
    }

    pub fn now(self: *const Service) u64 {
        return self.monotonic_ns;
    }

    pub fn wallNow(self: *const Service) u64 {
        return self.wall_epoch_ns +| self.monotonic_ns;
    }

    pub fn advanceBy(self: *Service, delta_ns: u64) u64 {
        self.monotonic_ns +|= delta_ns;
        return self.monotonic_ns;
    }

    pub fn advanceTo(self: *Service, deadline_ns: u64) u64 {
        self.monotonic_ns = @max(self.monotonic_ns, deadline_ns);
        return self.monotonic_ns;
    }

    /// Advance time only when the cooperative scheduler has proven that no
    /// guest context can currently run. This gives polling/event loops a real
    /// notion of elapsed time without making clock reads themselves mutate
    /// time or jumping to an unbounded sentinel deadline.
    pub fn advanceForQuiescence(self: *Service) u64 {
        const scheduler_tick_ns: u64 = 1_000_000;
        self.quiescence_advances +|= 1;
        self.quiescence_advanced_ns +|= scheduler_tick_ns;
        return self.advanceBy(scheduler_tick_ns);
    }

    pub fn schedule(
        self: *Service,
        allocator: std.mem.Allocator,
        deadline_ns: u64,
        thread: u64,
        wait_object: u64,
        wait_generation: u64,
    ) !u64 {
        const sequence = self.next_sequence;
        self.next_sequence +|= 1;
        try self.deadlines.append(allocator, .{
            .deadline_ns = deadline_ns,
            .sequence = sequence,
            .thread = thread,
            .wait_object = wait_object,
            .wait_generation = wait_generation,
        });
        siftUp(self.deadlines.items, self.deadlines.items.len - 1);
        return sequence;
    }

    pub fn nextDeadline(self: *const Service) ?u64 {
        if (self.deadlines.items.len == 0) return null;
        return self.deadlines.items[0].deadline_ns;
    }

    pub fn cancel(self: *Service, sequence: u64) bool {
        if (sequence == 0) return false;
        for (self.deadlines.items, 0..) |entry, index| {
            if (entry.sequence != sequence) continue;
            const last = self.deadlines.pop() orelse return true;
            if (index < self.deadlines.items.len) {
                self.deadlines.items[index] = last;
                if (index != 0 and lessThan(self.deadlines.items[index], self.deadlines.items[(index - 1) / 2])) {
                    siftUp(self.deadlines.items, index);
                } else {
                    siftDown(self.deadlines.items, index);
                }
            }
            return true;
        }
        return false;
    }

    pub fn popDue(self: *Service) ?TimerEntry {
        if (self.deadlines.items.len == 0 or self.deadlines.items[0].deadline_ns > self.monotonic_ns) return null;
        const result = self.deadlines.items[0];
        const last = self.deadlines.pop() orelse return result;
        if (self.deadlines.items.len != 0) {
            self.deadlines.items[0] = last;
            siftDown(self.deadlines.items, 0);
        }
        return result;
    }
};

fn lessThan(lhs: TimerEntry, rhs: TimerEntry) bool {
    return lhs.deadline_ns < rhs.deadline_ns or
        (lhs.deadline_ns == rhs.deadline_ns and lhs.sequence < rhs.sequence);
}

fn siftUp(items: []TimerEntry, start: usize) void {
    var index = start;
    while (index != 0) {
        const parent = (index - 1) / 2;
        if (!lessThan(items[index], items[parent])) break;
        std.mem.swap(TimerEntry, &items[index], &items[parent]);
        index = parent;
    }
}

fn siftDown(items: []TimerEntry, start: usize) void {
    var index = start;
    while (true) {
        const left = index * 2 + 1;
        if (left >= items.len) return;
        const right = left + 1;
        var smallest = left;
        if (right < items.len and lessThan(items[right], items[left])) smallest = right;
        if (!lessThan(items[smallest], items[index])) return;
        std.mem.swap(TimerEntry, &items[index], &items[smallest]);
        index = smallest;
    }
}

test "deadline heap orders time then insertion sequence" {
    var service = Service{ .monotonic_ns = 0 };
    defer service.deinit(std.testing.allocator);
    _ = try service.schedule(std.testing.allocator, 20, 2, 0, 0);
    _ = try service.schedule(std.testing.allocator, 10, 1, 0, 0);
    _ = try service.schedule(std.testing.allocator, 10, 3, 0, 0);
    try std.testing.expectEqual(@as(?u64, 10), service.nextDeadline());
    _ = service.advanceTo(10);
    try std.testing.expectEqual(@as(u64, 1), service.popDue().?.thread);
    try std.testing.expectEqual(@as(u64, 3), service.popDue().?.thread);
    try std.testing.expectEqual(@as(?TimerEntry, null), service.popDue());
    _ = service.advanceTo(20);
    try std.testing.expectEqual(@as(u64, 2), service.popDue().?.thread);
}

test "monotonic clock never moves backward" {
    var service = Service{};
    try std.testing.expectEqual(@as(u64, 1_000_000_000), service.advanceTo(5));
    try std.testing.expectEqual(@as(u64, 1_000_000_007), service.advanceBy(7));
}

test "quiescence advances time by bounded scheduler ticks" {
    var service = Service{ .monotonic_ns = 10 };
    try std.testing.expectEqual(@as(u64, 1_000_010), service.advanceForQuiescence());
    try std.testing.expectEqual(@as(u64, 2_000_010), service.advanceForQuiescence());
    try std.testing.expectEqual(@as(u64, 2), service.quiescence_advances);
    try std.testing.expectEqual(@as(u64, 2_000_000), service.quiescence_advanced_ns);
}

test "cancel removes a signaled wait deadline without disturbing heap order" {
    var service = Service{ .monotonic_ns = 0 };
    defer service.deinit(std.testing.allocator);
    const later = try service.schedule(std.testing.allocator, 30, 3, 0, 0);
    const first = try service.schedule(std.testing.allocator, 10, 1, 0, 0);
    _ = try service.schedule(std.testing.allocator, 20, 2, 0, 0);
    try std.testing.expect(service.cancel(first));
    try std.testing.expect(!service.cancel(first));
    try std.testing.expect(service.cancel(later));
    try std.testing.expectEqual(@as(?u64, 20), service.nextDeadline());
}
