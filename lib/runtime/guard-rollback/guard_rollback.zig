const std = @import("std");

/// Manages `__cxa_guard` variable tracking and rollback for initializer
/// deferral recovery.
///
/// When a C++ static initializer is deferred (step limit exceeded or
/// runtime dependency missing), any `__cxa_guard` variables that were
/// *acquired* during the aborted run must be reset to the uninitialized
/// state so the initializer can be safely re-executed.
///
/// Each guard is a pair of bytes at a known address:
///   byte[0] = completed-flag (0 = not-done, 1 = done)
///   byte[1] = in-progress-flag (0 = available, 1 = acquired)
///
/// Resetting both to zero is safe: the next `__cxa_guard_acquire` call
/// will see the guard as uninitialized and re-enter the initializer.
pub const GuardRollback = struct {
    /// Set of `__cxa_guard` variable addresses tracked during the
    /// current initializer run.
    tracker: std.AutoHashMap(u64, void),

    /// Total number of guards cleared over the lifetime of this tracker.
    total_cleared: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) GuardRollback {
        return .{
            .tracker = std.AutoHashMap(u64, void).init(allocator),
        };
    }

    pub fn deinit(self: *GuardRollback) void {
        self.tracker.deinit();
    }

    // ------------------------------------------------------------------
    // Tracking
    // ------------------------------------------------------------------

    /// Record that a `__cxa_guard` at `guard_addr` was acquired.
    /// Safe to call multiple times for the same address (duplicates are
    /// suppressed by the hash-map semantics).
    pub fn track(self: *GuardRollback, guard_addr: u64) void {
        self.tracker.put(guard_addr, {}) catch {};
    }

    // ------------------------------------------------------------------
    // Rollback
    // ------------------------------------------------------------------

    /// Callback signature for writing a single byte to guest memory.
    /// `ctx` is an opaque context pointer (typically `*MachOState`).
    /// Returns `true` on success, `false` if the address is unmapped.
    pub const WriteByteFn = *const fn (ctx: *anyopaque, addr: u64, byte_offset: u64, value: u8) bool;

    /// Clear every tracked guard by writing zeros to both guard bytes.
    ///
    /// `ctx` is forwarded to `write_byte` unchanged.
    /// After clearing, the internal tracker is reset (ready for a new
    /// initializer run).  Returns the number of guards that were cleared.
    pub fn clearAndReset(self: *GuardRollback, ctx: *anyopaque, write_byte: WriteByteFn) u64 {
        var cleared: u64 = 0;
        var iter = self.tracker.keyIterator();
        while (iter.next()) |guard_addr| {
            // byte[0] = completed-flag (0 = not done)
            // byte[1] = in-progress-flag (0 = available)
            if (write_byte(ctx, guard_addr.*, 0, 0) and
                write_byte(ctx, guard_addr.*, 1, 0))
            {
                cleared +|= 1;
            }
        }
        self.tracker.clearRetainingCapacity();
        self.total_cleared +|= cleared;
        return cleared;
    }

    /// Reset the tracker without clearing any guards.
    /// Use at the start of a *new* initializer run when the previous run
    /// already performed `clearAndReset`.
    pub fn reset(self: *GuardRollback) void {
        self.tracker.clearRetainingCapacity();
    }

    // ------------------------------------------------------------------
    // Diagnostics
    // ------------------------------------------------------------------

    /// Number of guard addresses currently tracked.
    pub fn count(self: *const GuardRollback) usize {
        return self.tracker.count();
    }

    /// Total number of guard clear operations performed over the lifetime.
    pub fn totalCleared(self: *const GuardRollback) u64 {
        return self.total_cleared;
    }
};

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "GuardRollback: basic lifecycle" {
    var gb = GuardRollback.init(std.testing.allocator);
    defer gb.deinit();

    try std.testing.expectEqual(@as(usize, 0), gb.count());

    gb.track(0x1000);
    gb.track(0x2000);
    try std.testing.expectEqual(@as(usize, 2), gb.count());

    // Duplicate track is a no-op
    gb.track(0x1000);
    try std.testing.expectEqual(@as(usize, 2), gb.count());

    var dummy: u8 = 0;
    const cleared = gb.clearAndReset(@as(*anyopaque, @ptrCast(&dummy)), struct {
        fn writer(_: *anyopaque, _: u64, _: u64, _: u8) bool {
            return true;
        }
    }.writer);
    try std.testing.expectEqual(@as(u64, 2), cleared);
    try std.testing.expectEqual(@as(usize, 0), gb.count());
}

test "GuardRollback: reset without clearing" {
    var gb = GuardRollback.init(std.testing.allocator);
    defer gb.deinit();

    gb.track(0x1000);
    try std.testing.expectEqual(@as(usize, 1), gb.count());

    gb.reset();
    try std.testing.expectEqual(@as(usize, 0), gb.count());
}

test "GuardRollback: totalCleared accumulates" {
    var gb = GuardRollback.init(std.testing.allocator);
    defer gb.deinit();

    gb.track(0x1000);
    var dummy: u8 = 0;
    const dummy_ctx: *anyopaque = @ptrCast(&dummy);
    _ = gb.clearAndReset(dummy_ctx, struct {
        fn writer(_: *anyopaque, _: u64, _: u64, _: u8) bool {
            return true;
        }
    }.writer);
    try std.testing.expectEqual(@as(u64, 1), gb.totalCleared());

    gb.track(0x2000);
    gb.track(0x3000);
    _ = gb.clearAndReset(dummy_ctx, struct {
        fn writer(_: *anyopaque, _: u64, _: u64, _: u8) bool {
            return true;
        }
    }.writer);
    try std.testing.expectEqual(@as(u64, 3), gb.totalCleared());
}

test "GuardRollback: writeByteFn receives correct parameters" {
    var gb = GuardRollback.init(std.testing.allocator);
    defer gb.deinit();

    var calls = std.ArrayList(struct { addr: u64, off: u64, val: u8 }).empty;
    defer calls.deinit(std.testing.allocator);

    gb.track(0x1234);
    _ = gb.clearAndReset(&calls, struct {
        fn writer(ctx: *anyopaque, addr: u64, off: u64, val: u8) bool {
            const self_calls: *std.ArrayList(struct { addr: u64, off: u64, val: u8 }) = @ptrCast(@alignCast(ctx));
            self_calls.append(std.testing.allocator, .{ .addr = addr, .off = off, .val = val }) catch {};
            return true;
        }
    }.writer);

    try std.testing.expectEqual(@as(usize, 2), calls.items.len);
    // byte[0] cleared
    try std.testing.expectEqual(@as(u64, 0x1234), calls.items[0].addr);
    try std.testing.expectEqual(@as(u64, 0), calls.items[0].off);
    try std.testing.expectEqual(@as(u8, 0), calls.items[0].val);
    // byte[1] cleared
    try std.testing.expectEqual(@as(u64, 0x1234), calls.items[1].addr);
    try std.testing.expectEqual(@as(u64, 1), calls.items[1].off);
    try std.testing.expectEqual(@as(u8, 0), calls.items[1].val);
}
