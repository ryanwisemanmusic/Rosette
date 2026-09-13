//! The performance counter Rosette publishes to a hosted Windows guest.
//!
//! One subsystem, one file. Every timed thing the guest does is denominated
//! in this counter - `QueryPerformanceCounter`, every `WaitForSingleObject`
//! timeout, every frame limiter, every repeating timer - so what it counts
//! and how fast it moves decides how much work the guest gets done between
//! two of its own deadlines. That is a large enough question to read on its
//! own rather than three hundred lines apart inside the interpreter.
//!
//! ## Why it is not derived from instruction count
//!
//! It used to advance one tick per interpreted instruction against a
//! published frequency of one megahertz, which describes a machine executing
//! one instruction per microsecond. Real hardware does about three thousand.
//! A guest millisecond therefore bought a thousand instructions of work where
//! the code asking for it was written expecting three million.
//!
//! The 2026-09-12 run shows the bill: 102,658 of 118,015 waits timed out, and
//! the two threads servicing one repeating millisecond timer held forty-two
//! percent of the interpreter between them. Sampling the host's monotonic
//! clock makes a guest millisecond a real millisecond - about twelve thousand
//! interpreted instructions at this interpreter's rate - and makes guest time
//! agree with the clock the window server and the person watching are on.

const std = @import("std");

/// The frequency Rosetta publishes from `QueryPerformanceFrequency`, and the
/// unit `ticks` counts. Both halves have to come from here: a guest that
/// measures elapsed time and a guest that sleeps must get the same answer.
pub const hz: u64 = 1_000_000;

/// Nanoseconds per tick. Exact, so the conversion never rounds.
pub const nanos_per_tick: u64 = @divExact(@as(u64, 1_000_000_000), hz);

/// Ticks in one guest millisecond, which is the unit every Win32 timeout is
/// expressed in.
pub const ticks_per_millisecond: u64 = hz / 1000;

/// How often the host clock is re-read.
///
/// Not every instruction: the read is cheap but not free at five billion of
/// them. Within a stride the clock is flat, which is also what a real
/// performance counter with finite resolution does.
pub const sample_stride: u64 = 512;

/// Where the counter's value comes from.
pub const Source = enum {
    /// The host's monotonic clock. A guest millisecond is a real
    /// millisecond.
    host_monotonic,
    /// One tick per interpreted instruction. Selected by
    /// `ROSETTE_GUEST_CLOCK=instructions`; kept because the trade-off is
    /// real - this source is immune to host scheduling jitter, the other is
    /// immune to how fast the interpreter happens to be.
    retired_instructions,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .host_monotonic => "host monotonic clock: a guest millisecond is a real millisecond, so guest timers fire at the rate they were written for",
            .retired_instructions => "retired instructions (ROSETTE_GUEST_CLOCK=instructions): a guest millisecond is a thousand instructions, so every guest timer fires far more often per unit of work than on hardware",
        };
    }
};

pub const Clock = struct {
    /// What the guest reads from `QueryPerformanceCounter`.
    ticks: u64 = 0,
    source: Source = .host_monotonic,
    /// Host monotonic nanoseconds at the first sample, so the counter starts
    /// near zero rather than at the machine's uptime.
    base_nanos: u64 = 0,
    /// Interpreted steps since the last host read.
    stride: u64 = 0,
    /// Set when the host clock could not be read at all, so the report says
    /// the counter is a fallback rather than presenting it as real time.
    host_unavailable: bool = false,

    /// Move the counter forward by one interpreted instruction's worth.
    ///
    /// `now_nanos` is the host's monotonic clock, or zero when it could not
    /// be read. Passed in rather than read here so this file has no clock
    /// syscall in it and stays testable without one.
    pub fn advance(self: *Clock, now_nanos: u64) void {
        if (self.source == .retired_instructions) {
            self.ticks +|= 1;
            return;
        }
        self.stride +|= 1;
        if (self.stride < sample_stride) return;
        self.stride = 0;
        self.apply(now_nanos);
    }

    /// Read the host clock now, whatever the stride says.
    ///
    /// For a caller about to decide something *because* of the time. The
    /// stride exists to keep the read off the per-instruction path, not to
    /// make a deadline check answer with a stale value.
    pub fn refresh(self: *Clock, now_nanos: u64) void {
        if (self.source == .retired_instructions) return;
        self.stride = 0;
        self.apply(now_nanos);
    }

    fn apply(self: *Clock, now_nanos: u64) void {
        if (now_nanos == 0) {
            // No host clock. Advance by the stride's worth rather than let
            // the guest see a stopped counter, and record that this happened
            // so the report does not call the result real time.
            self.host_unavailable = true;
            self.ticks +|= sample_stride;
            return;
        }
        if (self.base_nanos == 0) {
            self.base_nanos = now_nanos;
            return;
        }
        if (now_nanos <= self.base_nanos) return;
        // Divide before scaling: multiplying first overflows u64 after about
        // five hours of uptime, and a saturating multiply would freeze the
        // clock there rather than fail visibly.
        const elapsed = now_nanos - self.base_nanos;
        const sampled = @divTrunc(elapsed, nanos_per_tick);
        // Never decreases. A performance counter that goes backwards makes a
        // guest computing `now - then` see an enormous unsigned interval, and
        // every deadline in the run is computed that way.
        if (sampled > self.ticks) self.ticks = sampled;
    }

    /// A deadline this many guest milliseconds from now.
    pub fn deadlineAfterMilliseconds(self: *const Clock, milliseconds: u64) u64 {
        return self.ticks +| (milliseconds *| ticks_per_millisecond);
    }

    /// Guest time as a fraction of real time, in tenths. One point zero means
    /// the two agree.
    ///
    /// The number the old design got wrong in a way nobody could see: it read
    /// twelve, which looks like a scaling choice, when the damaging ratio was
    /// guest time against *work done* and nothing reported that at all.
    pub fn dilationTenths(self: *const Clock, real_nanos: u64) u64 {
        if (real_nanos == 0) return 0;
        const guest_nanos = self.ticks *| nanos_per_tick;
        return @divTrunc(guest_nanos *| 10, real_nanos);
    }

    pub fn sourceLabel(self: *const Clock) []const u8 {
        if (self.source == .host_monotonic and self.host_unavailable) {
            return "host monotonic clock, with gaps filled from instruction count because the host clock could not be read";
        }
        return self.source.label();
    }
};

test "the counter tracks real time and never goes backwards" {
    var clock = Clock{};
    // The first sample only establishes the base.
    clock.refresh(1_000_000_000);
    try std.testing.expectEqual(@as(u64, 0), clock.ticks);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), clock.base_nanos);

    // One second later is one million ticks at 1 MHz.
    clock.refresh(2_000_000_000);
    try std.testing.expectEqual(@as(u64, 1_000_000), clock.ticks);

    // A host clock that jumps backwards - a reading racing another thread's,
    // a suspend - must not take the counter with it.
    clock.refresh(1_500_000_000);
    try std.testing.expectEqual(@as(u64, 1_000_000), clock.ticks);
    clock.refresh(0);
    try std.testing.expect(clock.ticks >= 1_000_000);
    try std.testing.expect(clock.host_unavailable);
}

test "a guest millisecond is a real millisecond" {
    var clock = Clock{};
    clock.refresh(0x1000_0000_0000);
    const start = clock.ticks;
    // Ten milliseconds of host time.
    clock.refresh(0x1000_0000_0000 + 10 * std.time.ns_per_ms);
    try std.testing.expectEqual(start + 10 * ticks_per_millisecond, clock.ticks);

    // And a ten-millisecond deadline set at the start expires exactly there,
    // so a sleeper and a clock reader agree.
    var deadline_clock = Clock{};
    deadline_clock.ticks = start;
    const deadline = deadline_clock.deadlineAfterMilliseconds(10);
    try std.testing.expectEqual(clock.ticks, deadline);
}

test "the stride keeps the read off the hot path without skipping a deadline" {
    var clock = Clock{};
    clock.refresh(1_000_000_000);
    // Advancing fewer than a stride's steps does not read the clock, so the
    // counter is flat - which is what a real counter with finite resolution
    // does too.
    for (0..sample_stride - 1) |_| clock.advance(9_000_000_000);
    try std.testing.expectEqual(@as(u64, 0), clock.ticks);
    // The stride's last step samples.
    clock.advance(9_000_000_000);
    try std.testing.expectEqual(@as(u64, 8_000_000), clock.ticks);

    // And a caller that asks directly is never told a stale value: a deadline
    // check happens when every worker is parked and no instruction is
    // running, which is precisely when the stride would never complete.
    var parked = Clock{};
    parked.refresh(1_000_000_000);
    parked.advance(2_000_000_000); // one step, well inside the stride
    try std.testing.expectEqual(@as(u64, 0), parked.ticks);
    parked.refresh(2_000_000_000);
    try std.testing.expectEqual(@as(u64, 1_000_000), parked.ticks);
}

test "the instruction-derived source is exactly one tick a step and ignores the host" {
    var clock = Clock{ .source = .retired_instructions };
    for (0..1000) |_| clock.advance(123_456_789);
    try std.testing.expectEqual(@as(u64, 1000), clock.ticks);
    // A refresh must not reach for the host clock in this mode, or a test or
    // a replay driving the counter by hand would have it overwritten.
    clock.ticks = 12_345;
    clock.refresh(999_999_999_999);
    try std.testing.expectEqual(@as(u64, 12_345), clock.ticks);
    try std.testing.expect(std.mem.indexOf(u8, clock.sourceLabel(), "retired instructions") != null);
}

test "dilation reports guest time against real time" {
    var clock = Clock{};
    clock.ticks = 1_000_000; // one guest second
    try std.testing.expectEqual(@as(u64, 10), clock.dilationTenths(std.time.ns_per_s));
    // Twelve guest seconds in one real second is the x12.0 the old
    // instruction-derived clock produced.
    clock.ticks = 12_000_000;
    try std.testing.expectEqual(@as(u64, 120), clock.dilationTenths(std.time.ns_per_s));
    try std.testing.expectEqual(@as(u64, 0), clock.dilationTenths(0));
}
