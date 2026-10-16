//! Spin-then-park handoff for the hybrid Vulkan command FIFO.
//!
//! Xenia's GPU thread issues one Vulkan call every one to three microseconds
//! while it replays a deferred command buffer. The worker that runs the
//! queued native calls finishes each one long before the next arrives, so a
//! worker that sleeps the moment its queue is empty is woken by a
//! condition-variable signal on nearly every call: the 2026-10-16 Custom
//! Games run recorded 10.83 million wakes for 17.09 million queued commands,
//! and 854,000 ordering barriers that had to sleep until the worker caught
//! up. Each of those is a system call, a context switch and a cross-core
//! wake on the guest GPU thread's critical path.
//!
//! The worker now keeps polling for a bounded time after it runs dry, and only
//! then parks; a producer signals only a parked worker; and an ordering
//! barrier polls the worker's completion watermark before it blocks. FIFO
//! order, sequence numbers, payload ownership, the full-queue fallback and
//! shutdown are unchanged. `enabled = false` restores the original handoff
//! exactly: signal on every empty-to-nonempty submission, sleep at once when
//! idle, block at once on a barrier.

const std = @import("std");
const builtin = @import("builtin");

/// Internal control for offline comparison; production keeps it on.
pub var enabled: bool = true;
/// How long the worker keeps polling for new commands after it runs dry.
pub var worker_spin_ns: u64 = 50 * std.time.ns_per_us;
/// How long an ordering barrier polls the completion watermark before it
/// sleeps on the worker's condition variable.
pub var drain_spin_ns: u64 = 50 * std.time.ns_per_us;
/// Attempts at an uncontended mutex before the ordinary blocking lock. The
/// queue's critical sections copy at most one command payload, so a holder
/// leaves the lock within a few hundred nanoseconds; Darwin's default mutex
/// would otherwise park the waiter in the kernel immediately.
pub const lock_spins: u32 = 1024;

pub fn nowNs() u64 {
    if (builtin.os.tag != .macos and builtin.os.tag != .linux) return 0;
    var value: std.c.timespec = undefined;
    const clock: std.c.clockid_t = if (builtin.os.tag == .macos) .UPTIME_RAW else .MONOTONIC;
    if (std.c.clock_gettime(clock, &value) != 0 or value.sec < 0) return 0;
    return @as(u64, @intCast(value.sec)) *| std.time.ns_per_s +| @as(u64, @intCast(value.nsec));
}

/// Poll `ready(context)` until it is true or `budget_ns` has elapsed.
/// The clock is read once per 32 polls; a zero budget polls once.
pub inline fn spinUntil(budget_ns: u64, context: anytype, comptime ready: fn (@TypeOf(context)) bool) bool {
    if (ready(context)) return true;
    if (budget_ns == 0) return false;
    const started = nowNs();
    var polls: u32 = 0;
    while (true) {
        std.atomic.spinLoopHint();
        if (ready(context)) return true;
        polls +%= 1;
        if (polls & 31 == 0) {
            const now = nowNs();
            if (now < started or now - started >= budget_ns) return ready(context);
        }
    }
}

/// Lock `mutex`, trying the uncontended path `lock_spins` times first.
pub fn lockSpinning(mutex: *std.c.pthread_mutex_t) void {
    if (enabled) {
        var attempt: u32 = 0;
        while (attempt < lock_spins) : (attempt += 1) {
            if (std.c.pthread_mutex_trylock(mutex) == .SUCCESS) return;
            std.atomic.spinLoopHint();
        }
    }
    if (std.c.pthread_mutex_lock(mutex) != .SUCCESS) unreachable;
}

test "spinUntil returns at once when ready and gives up after its budget" {
    const Flag = struct {
        fn yes(_: void) bool {
            return true;
        }
        fn no(_: void) bool {
            return false;
        }
    };
    try std.testing.expect(spinUntil(0, {}, Flag.yes));
    try std.testing.expect(!spinUntil(0, {}, Flag.no));
    const started = nowNs();
    try std.testing.expect(!spinUntil(200 * std.time.ns_per_us, {}, Flag.no));
    try std.testing.expect(nowNs() - started >= 200 * std.time.ns_per_us);
}
