//! A cheap host clock for measuring how long something took.
//!
//! `monotonicNanoseconds` reads CLOCK_MONOTONIC, which Darwin derives from
//! the wall clock and the boot time on every call (`gettimeofday` and
//! `mach_boottime_usec` under `clock_gettime`). That is right for deadlines,
//! which must keep counting across system sleep, and several times the cost
//! of reading the timer itself. Ledgers that only subtract two readings taken
//! a few microseconds apart - the runtime-lock hold ledger on every import,
//! the Vulkan bridge's host-time spans on every graphics call - use this
//! clock: `mach_absolute_time` scaled by the cached timebase on Darwin, the
//! monotonic clock elsewhere. Never mix its readings with another clock's.

const std = @import("std");
const builtin = @import("builtin");

/// Internal control for offline comparison; production keeps it on.
pub var enabled: bool = true;

var timebase_numer: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var timebase_denom: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

pub fn nanoseconds() u64 {
    if (builtin.os.tag != .macos or !enabled) return fallback();
    var numer = timebase_numer.load(.monotonic);
    var denom = timebase_denom.load(.monotonic);
    if (numer == 0) {
        var info: std.c.mach_timebase_info_data = undefined;
        if (std.c.mach_timebase_info(&info) != 0 or info.numer == 0 or info.denom == 0) return fallback();
        timebase_denom.store(info.denom, .monotonic);
        timebase_numer.store(info.numer, .monotonic);
        numer = info.numer;
        denom = info.denom;
    }
    const ticks = std.c.mach_absolute_time();
    if (numer == denom) return ticks;
    return @intCast(@as(u128, ticks) * numer / denom);
}

fn fallback() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    if (timestamp.sec < 0 or timestamp.nsec < 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(timestamp.nsec));
}

test "the duration clock advances and measures a real interval" {
    const saved = enabled;
    defer enabled = saved;
    for ([_]bool{ true, false }) |on| {
        enabled = on;
        const started = nanoseconds();
        var request = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
        _ = std.c.nanosleep(&request, null);
        const elapsed = nanoseconds() - started;
        try std.testing.expect(elapsed >= std.time.ns_per_ms and elapsed < 2 * std.time.ns_per_s);
    }
}
