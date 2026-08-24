//! Route-independent: Xbox 360 timer object lifecycle and the console's time
//! base.
//!
//! The console counts time in 100-nanosecond units, and its timeout parameter
//! is signed with a sign that changes the *meaning* rather than the magnitude.
//! Both are ABI facts; one copy, no route mirror.
//!
//! ## The sign convention is the whole problem
//!
//! A Windows-family timeout is an `i64` of 100 ns units where a **negative**
//! value is a relative interval and a **positive** value is an absolute
//! deadline since 1601. Getting this backwards does not produce an error: it
//! produces a wait that either returns instantly or blocks for four centuries.
//! The four-century version is indistinguishable from a deadlock, and it is
//! usually diagnosed as one — a thread parked forever on a condition variable
//! with nothing obviously wrong.
//!
//! Zero is a third case again: poll and return immediately, never block.
//!
//! ## What this package is not
//!
//! * It is not a clock. It cannot tell the time: the host time APIs are out of
//!   reach from a package by construction, and the runtime owns every real
//!   timestamp.
//! * It is not a timer object. Period, due time, and signalled state are live
//!   state and belong to `lib/scheduler/`.
//! * It does not schedule. Deciding when a thread wakes is a runtime decision.

const std = @import("std");

/// The console's time unit: 100 nanoseconds.
pub const ticks_per_microsecond: u64 = 10;
pub const ticks_per_millisecond: u64 = 10_000;
pub const ticks_per_second: u64 = 10_000_000;

/// The epoch the absolute form counts from: 1601-01-01 UTC. Stated so that a
/// value in the low millions is recognisable as *not* an absolute deadline.
pub const epoch_year: u32 = 1601;

/// Timer objects the kernel will keep.
pub const max_timer_count: u32 = 64;

/// The finest interval the hardware resolves. A request below this is honoured
/// at this granularity rather than refused — a title asking for a 10 ns timer
/// gets 100 ns, not an error.
pub const min_resolution_ticks: u64 = 1;
pub const min_resolution_ns: u64 = 100;

/// The longest period a periodic timer may carry.
pub const max_period_ms: u64 = 60_000;

/// Wait forever. The most negative `i64`; no relative interval can collide
/// with it, which is why this value and not zero means "infinite".
pub const infinite_timeout: i64 = std.math.minInt(i64);

pub const TimerKind = enum(u8) {
    /// Signals once, then stays signalled until reset.
    manual_reset,
    /// Signals once and resets when a single waiter is released.
    synchronization,

    /// Whether a signal releases every waiter or exactly one.
    ///
    /// The distinction behind a lost wakeup: a synchronisation timer releases
    /// one thread, so eleven others stay parked and the twelfth's progress is
    /// mistaken for the whole system running.
    pub fn releasesAllWaiters(self: TimerKind) bool {
        return self == .manual_reset;
    }
};

pub const TimerState = enum(u8) {
    inactive,
    active,
    signalled,
    cancelled,

    pub fn isWaitable(self: TimerState) bool {
        return self == .active or self == .signalled;
    }
};

/// How a timeout parameter should be read.
pub const TimeoutMeaning = union(enum) {
    /// Do not block; report whether the object was already signalled.
    poll,
    /// Block until signalled, with no deadline.
    infinite,
    /// Block for this many ticks from now.
    relative: u64,
    /// Block until this absolute tick count since the epoch.
    absolute: u64,
};

/// Interpret a raw timeout parameter.
///
/// The one function this package exists to provide. Pure: it reads the value
/// handed in and consults no clock.
pub fn interpretTimeout(raw: i64) TimeoutMeaning {
    if (raw == 0) return .poll;
    if (raw == infinite_timeout) return .infinite;
    if (raw < 0) {
        // Negative is relative. Negating `minInt` would overflow, which is why
        // the infinite case is taken above and not folded in here.
        return .{ .relative = @intCast(-raw) };
    }
    return .{ .absolute = @intCast(raw) };
}

/// Convert milliseconds to console ticks, saturating rather than wrapping.
pub fn millisecondsToTicks(milliseconds: u64) u64 {
    return std.math.mul(u64, milliseconds, ticks_per_millisecond) catch std.math.maxInt(u64);
}

/// The relative timeout parameter a wait of this many milliseconds needs.
///
/// Negative, because relative is negative. Written as a helper so that the
/// sign is applied in one place instead of at every call site.
pub fn relativeTimeoutFromMilliseconds(milliseconds: u64) i64 {
    const ticks = millisecondsToTicks(milliseconds);
    const clamped: i64 = @intCast(@min(ticks, @as(u64, std.math.maxInt(i64))));
    return -clamped;
}

/// Whether a period is one a periodic timer may carry.
///
/// Zero is not a period: a periodic timer with a zero period would requeue
/// itself without advancing and starve every other runnable thread.
pub fn isValidPeriod(period_ms: u64) bool {
    return period_ms > 0 and period_ms <= max_period_ms;
}

pub fn contractIsWellFormed() bool {
    if (ticks_per_second != ticks_per_millisecond * 1000) return false;
    if (ticks_per_millisecond != ticks_per_microsecond * 1000) return false;
    if (infinite_timeout >= 0) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the time base is one hundred nanoseconds" {
    try std.testing.expectEqual(@as(u64, 10_000_000), ticks_per_second);
    try std.testing.expectEqual(@as(u64, 10_000), ticks_per_millisecond);
    try std.testing.expectEqual(@as(u64, 10), ticks_per_microsecond);
    // Not nanoseconds and not milliseconds — the two units it is most often
    // mistaken for, each off by a factor of 100 or 10000.
    try std.testing.expect(ticks_per_second != 1_000_000_000);
    try std.testing.expect(ticks_per_second != 1_000);
}

test "negative is relative and positive is absolute" {
    // Backwards, this either spins or blocks for centuries. The centuries
    // version reads as a deadlock and gets debugged as one.
    switch (interpretTimeout(-10_000)) {
        .relative => |ticks| try std.testing.expectEqual(@as(u64, 10_000), ticks),
        else => return error.TestUnexpectedResult,
    }
    switch (interpretTimeout(10_000)) {
        .absolute => |ticks| try std.testing.expectEqual(@as(u64, 10_000), ticks),
        else => return error.TestUnexpectedResult,
    }
}

test "zero polls and does not block" {
    // A third meaning, not a degenerate relative wait. A runtime that treats
    // zero as "block for zero ticks" and then sleeps has turned a poll into a
    // scheduler round trip on a hot path.
    try std.testing.expectEqual(TimeoutMeaning.poll, interpretTimeout(0));
}

test "the infinite sentinel does not overflow when negated" {
    // minInt(i64) has no positive twin. Folding it into the relative branch
    // would trap on the negation, so it is taken first.
    try std.testing.expectEqual(TimeoutMeaning.infinite, interpretTimeout(infinite_timeout));
    try std.testing.expectEqual(@as(i64, -9223372036854775808), infinite_timeout);

    // Everything one step less negative is still an ordinary relative wait.
    switch (interpretTimeout(infinite_timeout + 1)) {
        .relative => |ticks| try std.testing.expectEqual(@as(u64, 9223372036854775807), ticks),
        else => return error.TestUnexpectedResult,
    }
}

test "a one second wait is expressed as a negative tick count" {
    try std.testing.expectEqual(@as(i64, -10_000_000), relativeTimeoutFromMilliseconds(1000));
    switch (interpretTimeout(relativeTimeoutFromMilliseconds(1000))) {
        .relative => |ticks| try std.testing.expectEqual(ticks_per_second, ticks),
        else => return error.TestUnexpectedResult,
    }
}

test "millisecond conversion saturates rather than wrapping" {
    // A wrapped conversion turns a very long wait into a very short one, and
    // the resulting busy loop looks like a scheduler bug.
    try std.testing.expectEqual(@as(u64, 10_000), millisecondsToTicks(1));
    try std.testing.expectEqual(std.math.maxInt(u64), millisecondsToTicks(std.math.maxInt(u64)));
    // Saturation must stay non-negative once it becomes a parameter.
    try std.testing.expect(relativeTimeoutFromMilliseconds(std.math.maxInt(u64)) < 0);
}

test "a manual reset timer releases every waiter" {
    // The lost-wakeup shape: a synchronisation timer releases one thread, so
    // the other waiters stay parked while one of them makes progress.
    try std.testing.expect(TimerKind.manual_reset.releasesAllWaiters());
    try std.testing.expect(!TimerKind.synchronization.releasesAllWaiters());
}

test "a zero period is not a period" {
    try std.testing.expect(!isValidPeriod(0));
    try std.testing.expect(isValidPeriod(1));
    try std.testing.expect(isValidPeriod(max_period_ms));
    try std.testing.expect(!isValidPeriod(max_period_ms + 1));
}

test "waitable states exclude the ones that never signal" {
    try std.testing.expect(TimerState.active.isWaitable());
    try std.testing.expect(TimerState.signalled.isWaitable());
    try std.testing.expect(!TimerState.inactive.isWaitable());
    try std.testing.expect(!TimerState.cancelled.isWaitable());
}
