//! Per-call work the Windows Vulkan adapter can skip without changing what
//! the forwarder or the guest observes.
//!
//! Xenia's GPU thread makes about seventeen thousand Vulkan calls per frame in
//! a heavy Halo 3 scene, each through `Bridge.dispatch`. The original adapter
//! copied all sixteen stack-argument slots of its scratch stack on every
//! call, although most command calls take no stack arguments at all; a cached
//! stack now remembers how many of its leading slots can be nonzero and
//! writes only those and the call's own arguments, so every slot past the
//! arguments still reads zero exactly as before.

/// Internal control for offline comparison; production keeps it on.
pub var scratch_enabled: bool = true;

/// Host-time spans only subtract two readings, so they use the cheap timer
/// rather than CLOCK_MONOTONIC (see `duration_clock` in lib/concurrency).
pub var fast_clock: bool = true;

const std = @import("std");
const builtin = @import("builtin");
var timebase_numer = std.atomic.Value(u32).init(0);
var timebase_denom = std.atomic.Value(u32).init(1);

pub fn durationNs() u64 {
    if (builtin.os.tag == .macos and fast_clock) {
        var numer = timebase_numer.load(.monotonic);
        var denom = timebase_denom.load(.monotonic);
        if (numer == 0) {
            var info: std.c.mach_timebase_info_data = undefined;
            if (std.c.mach_timebase_info(&info) == 0 and info.numer != 0 and info.denom != 0) {
                timebase_denom.store(info.denom, .monotonic);
                timebase_numer.store(info.numer, .monotonic);
                numer = info.numer;
                denom = info.denom;
            }
        }
        if (numer != 0) {
            const ticks = std.c.mach_absolute_time();
            return if (numer == denom) ticks else @intCast(@as(u128, ticks) * numer / denom);
        }
    }
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0 or timestamp.sec < 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) *| std.time.ns_per_s +| @as(u64, @intCast(timestamp.nsec));
}

test "bridge host-time clock measures a real interval on both routes" {
    const saved = fast_clock;
    defer fast_clock = saved;
    for ([_]bool{ true, false }) |on| {
        fast_clock = on;
        const started = durationNs();
        var request = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
        _ = std.c.nanosleep(&request, null);
        const elapsed = durationNs() - started;
        try std.testing.expect(elapsed >= std.time.ns_per_ms and elapsed < 2 * std.time.ns_per_s);
    }
}
