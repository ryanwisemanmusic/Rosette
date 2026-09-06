//! Exact, deterministic guest synchronization semantics for diagnostics.
//!
//! This is a model used by the Rosette contract tests and by bounded evidence
//! consumers.  It deliberately does not wake an arbitrary object because a
//! wait is old: manual-reset events persist until reset, auto-reset events
//! release one waiter, and semaphores release only the count they own.  The
//! model makes lost, duplicate, and wrong-object wakeups visible without
//! touching a live guest object.

const std = @import("std");

pub const Kind = enum(u8) {
    manual_event,
    auto_event,
    semaphore,
};

pub const WaitResult = enum(u8) {
    ready,
    blocked,
    already_waiting,
};

pub const SignalResult = struct {
    woke: u8 = 0,
    stored: u32 = 0,
    previous: u32 = 0,
};

pub const max_waiters: usize = 16;

pub const Object = struct {
    kind: Kind = .manual_event,
    signaled: bool = false,
    count: u32 = 0,
    maximum: u32 = 1,
    pending: [max_waiters]u64 = [_]u64{0} ** max_waiters,
    pending_count: usize = 0,
    released: [max_waiters]u64 = [_]u64{0} ** max_waiters,
    released_count: usize = 0,
    signal_count: u64 = 0,
    reset_count: u64 = 0,
    lost_signal_count: u64 = 0,

    pub fn manualEvent() Object {
        return .{ .kind = .manual_event };
    }

    pub fn autoEvent() Object {
        return .{ .kind = .auto_event };
    }

    pub fn semaphore(initial: u32, maximum: u32) Object {
        return .{
            .kind = .semaphore,
            .count = @min(initial, maximum),
            .maximum = @max(maximum, 1),
        };
    }

    pub fn wait(self: *Object, waiter: u64) WaitResult {
        if (waiter == 0) return .blocked;
        if (self.takeReleased(waiter)) return .ready;
        switch (self.kind) {
            .manual_event => {
                if (self.signaled) return .ready;
            },
            .auto_event => {
                if (self.signaled) {
                    self.signaled = false;
                    return .ready;
                }
            },
            .semaphore => {
                if (self.count != 0) {
                    self.count -= 1;
                    return .ready;
                }
            },
        }
        for (self.pending[0..self.pending_count]) |existing| {
            if (existing == waiter) return .already_waiting;
        }
        if (self.pending_count < self.pending.len) {
            self.pending[self.pending_count] = waiter;
            self.pending_count += 1;
        } else {
            // A full waiter queue is a real refusal, not an invented wake.
            self.lost_signal_count +|= 1;
        }
        return .blocked;
    }

    pub fn signal(self: *Object, amount: u32) SignalResult {
        const previous = self.available();
        self.signal_count +|= 1;
        var result = SignalResult{ .previous = previous };
        switch (self.kind) {
            .manual_event => {
                self.signaled = true;
                result.woke = self.releaseAllPending();
                result.stored = @intFromBool(self.signaled);
            },
            .auto_event => {
                if (self.pending_count != 0) {
                    self.releaseOnePending();
                    result.woke = 1;
                } else {
                    self.signaled = true;
                    result.stored = 1;
                }
            },
            .semaphore => {
                const release = @min(amount, self.maximum -| self.count);
                self.count += release;
                while (self.count != 0 and self.pending_count != 0) {
                    self.count -= 1;
                    self.releaseOnePending();
                    result.woke +|= 1;
                }
                result.stored = self.count;
            },
        }
        return result;
    }

    pub fn reset(self: *Object) bool {
        if (self.kind == .semaphore) return false;
        self.signaled = false;
        self.reset_count +|= 1;
        return true;
    }

    pub fn available(self: *const Object) u32 {
        return switch (self.kind) {
            .manual_event, .auto_event => @intFromBool(self.signaled),
            .semaphore => self.count,
        };
    }

    pub fn pendingWaiters(self: *const Object) usize {
        return self.pending_count;
    }

    pub fn wasReleased(self: *Object, waiter: u64) bool {
        return self.takeReleased(waiter);
    }

    fn takeReleased(self: *Object, waiter: u64) bool {
        for (self.released[0..self.released_count], 0..) |existing, index| {
            if (existing != waiter) continue;
            if (index + 1 < self.released_count) {
                std.mem.copyForwards(u64, self.released[index .. self.released_count - 1], self.released[index + 1 .. self.released_count]);
            }
            self.released_count -= 1;
            return true;
        }
        return false;
    }

    fn releaseOnePending(self: *Object) void {
        if (self.pending_count == 0) return;
        const waiter = self.pending[0];
        if (self.pending_count > 1) {
            std.mem.copyForwards(u64, self.pending[0 .. self.pending_count - 1], self.pending[1..self.pending_count]);
        }
        self.pending_count -= 1;
        if (self.released_count < self.released.len) {
            self.released[self.released_count] = waiter;
            self.released_count += 1;
        } else {
            self.lost_signal_count +|= 1;
        }
    }

    fn releaseAllPending(self: *Object) u8 {
        var released: u8 = 0;
        while (self.pending_count != 0) {
            self.releaseOnePending();
            released +|= 1;
        }
        return released;
    }
};

test "manual reset event releases all waiters and remains signaled" {
    var event = Object.manualEvent();
    try std.testing.expectEqual(WaitResult.blocked, event.wait(11));
    try std.testing.expectEqual(WaitResult.blocked, event.wait(12));
    const signal = event.signal(1);
    try std.testing.expectEqual(@as(u8, 2), signal.woke);
    try std.testing.expect(event.wasReleased(11));
    try std.testing.expect(event.wasReleased(12));
    try std.testing.expectEqual(WaitResult.ready, event.wait(13));
    try std.testing.expect(event.reset());
    try std.testing.expectEqual(WaitResult.blocked, event.wait(13));
}

test "auto reset event releases one waiter per signal" {
    var event = Object.autoEvent();
    _ = event.wait(1);
    _ = event.wait(2);
    try std.testing.expectEqual(@as(u8, 1), event.signal(1).woke);
    try std.testing.expect(event.wasReleased(1));
    try std.testing.expect(!event.wasReleased(2));
    try std.testing.expectEqual(WaitResult.ready, event.wait(3));
    try std.testing.expectEqual(WaitResult.blocked, event.wait(4));
}

test "semaphore consumes exactly its available count" {
    var semaphore = Object.semaphore(1, 3);
    try std.testing.expectEqual(WaitResult.ready, semaphore.wait(1));
    try std.testing.expectEqual(WaitResult.blocked, semaphore.wait(2));
    try std.testing.expectEqual(@as(u8, 1), semaphore.signal(1).woke);
    try std.testing.expect(semaphore.wasReleased(2));
    try std.testing.expectEqual(@as(u32, 0), semaphore.available());
    try std.testing.expect(!semaphore.reset());
}

test "a duplicate wait does not create a second waiter" {
    var event = Object.manualEvent();
    try std.testing.expectEqual(WaitResult.blocked, event.wait(9));
    try std.testing.expectEqual(WaitResult.already_waiting, event.wait(9));
    try std.testing.expectEqual(@as(usize, 1), event.pendingWaiters());
}
