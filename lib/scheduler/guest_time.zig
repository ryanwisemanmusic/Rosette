const std = @import("std");

pub const TimerEntry = struct {
    deadline_ns: u64,
    sequence: u64,
    thread: u64,
    wait_object: u64,
    wait_generation: u64,
};

/// Clock mode: virtual (deterministic step-based, default) or wall-clock (real host time).
/// Virtual mode advances 1 ns per executed guest instruction (1 GHz nominal).
/// Wall-clock mode uses the host monotonic clock, suitable for non-emulator apps.
pub const TimeMode = enum {
    virtual,
    wall_clock,
};

/// One virtual clock domain for guest-visible clocks and scheduler deadlines.
/// Deadlines are ordered by `(deadline, sequence)`, so equal-deadline wakeups
/// have stable FIFO behavior without depending on guest addresses or symbols.
pub const Service = struct {
    /// Clock mode: virtual (step-based) or wall_clock (host monotonic time).
    time_mode: TimeMode = .virtual,
    monotonic_ns: u64 = 1_000_000_000,
    wall_epoch_ns: u64 = 1_719_000_000 * 1_000_000_000,
    /// Host monotonic timestamp captured when wall-clock mode was enabled.
    host_base_ns: u64 = 0,
    /// Guest-visible time offset at wall-clock baseline capture.
    guest_base_ns: u64 = 1_000_000_000,
    next_sequence: u64 = 1,
    quiescence_advances: u64 = 0,
    quiescence_advanced_ns: u64 = 0,
    execution_step_watermark: ?u64 = null,
    execution_advances: u64 = 0,
    execution_advanced_ns: u64 = 0,
    deadlines: std.ArrayList(TimerEntry) = .empty,

    pub fn deinit(self: *Service, allocator: std.mem.Allocator) void {
        self.deadlines.deinit(allocator);
        self.* = .{};
    }

    pub fn now(self: *const Service) u64 {
        return self.monotonic_ns;
    }

    pub fn wallNow(self: *const Service) u64 {
        if (self.time_mode == .wall_clock) return self.monotonic_ns;
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
    /// guest context can currently run. In wall-clock mode, reads the real
    /// host time directly. In virtual mode, advances by a bounded scheduler
    /// tick (1 ms). This gives polling/event loops a real
    /// notion of elapsed time without making clock reads themselves mutate
    /// time or jumping to an unbounded sentinel deadline.
    pub fn advanceForQuiescence(self: *Service) u64 {
        if (self.time_mode == .wall_clock) {
            self.monotonic_ns = self.wallClockNow();
            return self.monotonic_ns;
        }
        const scheduler_tick_ns: u64 = 1_000_000;
        self.quiescence_advances +|= 1;
        self.quiescence_advanced_ns +|= scheduler_tick_ns;
        return self.advanceBy(scheduler_tick_ns);
    }

    /// Capture the current host monotonic time as the wall-clock baseline.
    /// After calling this, `now()` and `wallNow()` return host-relative time.
    pub fn captureWallClockBaseline(self: *Service) void {
        self.host_base_ns = monotonicHostNs();
        self.guest_base_ns = self.monotonic_ns;
    }

    /// Compute the current wall-clock guest time based on elapsed host time
    /// since the baseline capture.
    fn wallClockNow(self: *const Service) u64 {
        if (self.host_base_ns == 0) return self.monotonic_ns;
        const host_now = monotonicHostNs();
        const elapsed = host_now -| self.host_base_ns;
        return self.guest_base_ns +| elapsed;
    }

    /// Keep finite guest waits moving while other guest contexts remain
    /// runnable. In wall-clock mode the clock advances to real host time.
    /// One translated instruction represents one nanosecond of
    /// deterministic virtual execution time (a nominal 1 GHz guest clock).
    ///
    /// Previously the clock advanced only during global quiescence. A busy
    /// producer could therefore prevent every timer and sleep deadline from
    /// expiring forever, even while the cooperative scheduler kept rotating
    /// contexts. The watermark makes repeated scheduler scans idempotent.
    pub fn advanceForExecution(self: *Service, current_step: u64) u64 {
        if (self.time_mode == .wall_clock) {
            self.monotonic_ns = self.wallClockNow();
            return self.monotonic_ns;
        }
        const previous_step = self.execution_step_watermark orelse {
            self.execution_step_watermark = current_step;
            return self.monotonic_ns;
        };
        if (current_step <= previous_step) return self.monotonic_ns;

        const delta_ns = current_step - previous_step;
        self.execution_step_watermark = current_step;
        self.execution_advances +|= 1;
        self.execution_advanced_ns +|= delta_ns;
        return self.advanceBy(delta_ns);
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

/// Read the host monotonic clock directly. Returns 0 on failure.
fn monotonicHostNs() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

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

test "execution advances finite deadlines while runnable work continues" {
    var service = Service{ .monotonic_ns = 10 };
    try std.testing.expectEqual(@as(u64, 10), service.advanceForExecution(1_000));
    try std.testing.expectEqual(@as(u64, 1_000_010), service.advanceForExecution(1_001_000));
    try std.testing.expectEqual(@as(u64, 1_000_010), service.advanceForExecution(1_001_000));
    try std.testing.expectEqual(@as(u64, 1_000_010), service.advanceForExecution(900_000));
    try std.testing.expectEqual(@as(u64, 1), service.execution_advances);
    try std.testing.expectEqual(@as(u64, 1_000_000), service.execution_advanced_ns);
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
