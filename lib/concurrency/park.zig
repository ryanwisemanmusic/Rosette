//! The blocking step every primitive in this package shares, and the hook
//! that lets one thread keep serving others while it waits.
//!
//! A thread can install a `Service`: work other threads may be blocked on
//! it for. The host main thread installs one that drains the macOS main
//! dispatch queue, because AppKit and CAMetalLayer calls made by guest
//! workers are `dispatch_sync`ed to it. While a service is installed, a park
//! sleeps in slices and runs the service before and after each one, and any
//! thread can cut the current slice short with `requestService`.
//!
//! That rule is what breaks the 2026-09-25 deadlock. The GPU worker, inside
//! an import, held the runtime gate and `dispatch_sync`ed a window-status
//! query to the main thread; the main thread, inside its own next
//! instruction, was parked on that gate and never drained the queue. With a
//! service installed the main thread runs the query from inside its park,
//! the worker's import finishes and releases the gate, and the main thread
//! goes on. No wait anywhere in the process can hold the main thread away
//! from its queue for longer than one slice.

const std = @import("std");
const futex = @import("futex.zig");
const watch = @import("watch.zig");

pub const Word = futex.Word;

/// Longest single sleep of a thread with a service installed.
pub const default_slice_ns: u64 = std.time.ns_per_ms;

pub const Service = struct {
    context: ?*anyopaque = null,
    /// Run whatever other threads are waiting on this one for. Must not
    /// block indefinitely; may itself park (it is not re-entered).
    run: *const fn (?*anyopaque) void,
    slice_ns: u64 = default_slice_ns,
};

threadlocal var installed_service: ?Service = null;
threadlocal var running_service: bool = false;

/// The word the service thread is parked on right now, so `requestService`
/// can wake it. One service thread per process: the host main thread.
var service_parked_on: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

pub const Stats = struct {
    parks: u64 = 0,
    parked_ns: u64 = 0,
    longest_park_ns: u64 = 0,
    service_runs: u64 = 0,
    service_requests: u64 = 0,
};

var stat_parks: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
var stat_parked_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
var stat_longest_park_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
var stat_service_runs: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
var stat_service_requests: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

pub fn stats() Stats {
    return .{
        .parks = stat_parks.load(.monotonic),
        .parked_ns = stat_parked_ns.load(.monotonic),
        .longest_park_ns = stat_longest_park_ns.load(.monotonic),
        .service_runs = stat_service_runs.load(.monotonic),
        .service_requests = stat_service_requests.load(.monotonic),
    };
}

/// Install (or with null, remove) the calling thread's service. Returns
/// the previous one so a scope can restore it.
pub fn installService(service: ?Service) ?Service {
    const previous = installed_service;
    installed_service = service;
    return previous;
}

pub fn currentService() ?Service {
    return installed_service;
}

/// Run the calling thread's service now, if it has one and is not already
/// inside it. For loops that do their own waiting (the GetMessage block).
pub fn runService() void {
    const service = installed_service orelse return;
    if (running_service) return;
    running_service = true;
    defer running_service = false;
    service.run(service.context);
    _ = stat_service_runs.fetchAdd(1, .monotonic);
}

/// Ask the service thread to run its service promptly. Safe from any
/// thread; costs one atomic increment when nobody is parked.
pub fn requestService() void {
    _ = stat_service_requests.fetchAdd(1, .monotonic);
    const address = service_parked_on.load(.acquire);
    if (address != 0) futex.wake(@ptrFromInt(address), .all);
}

/// Sleep while `word` holds `expected`, at most until the monotonic
/// `deadline_ns` when one is given, and for at most one slice when the
/// calling thread has a service. Returns early for any reason; callers loop
/// on their own condition. `label` names the word for the watch registry.
pub fn park(word: *const Word, expected: u32, deadline_ns: ?u64, label: [*:0]const u8) void {
    var timeout: ?u64 = null;
    const started = futex.monotonicNanoseconds();
    if (deadline_ns) |deadline| {
        if (started >= deadline) return;
        timeout = deadline - started;
    }
    const has_service = installed_service != null and !running_service;
    if (has_service) {
        runService();
        if (word.load(.acquire) != expected) return;
        const slice = installed_service.?.slice_ns;
        timeout = if (timeout) |remaining| @min(remaining, slice) else slice;
        service_parked_on.store(@intFromPtr(word), .release);
    }
    watch.beginPark(word, label, started);
    futex.wait(word, expected, timeout);
    const finished = futex.monotonicNanoseconds();
    watch.endPark(finished);
    if (has_service) {
        service_parked_on.store(0, .release);
        runService();
    }
    const parked = finished -| started;
    _ = stat_parks.fetchAdd(1, .monotonic);
    _ = stat_parked_ns.fetchAdd(parked, .monotonic);
    _ = stat_longest_park_ns.fetchMax(parked, .monotonic);
}

/// A bounded spin before parking: most Rosette critical sections are a few
/// hundred nanoseconds, far shorter than a kernel sleep and wake.
pub const Backoff = struct {
    spins: u32 = 0,

    pub const spin_limit: u32 = 64;

    /// True while spinning is still worthwhile; false means park.
    pub fn spin(self: *Backoff) bool {
        if (self.spins >= spin_limit) return false;
        self.spins += 1;
        std.atomic.spinLoopHint();
        return true;
    }
};

test "a park with a deadline in the past returns at once" {
    var word = Word.init(0);
    park(&word, 0, futex.monotonicNanoseconds() -| 1, "past deadline");
}

test "a service runs while its thread is parked, and a request cuts the slice short" {
    const Counter = struct {
        runs: u32 = 0,
        fn run(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.runs += 1;
        }
    };
    var counter: Counter = .{};
    const previous = installService(.{ .context = &counter, .run = Counter.run, .slice_ns = 200 * std.time.ns_per_ms });
    defer _ = installService(previous);

    const Requester = struct {
        fn run(done: *std.atomic.Value(bool)) void {
            // Keep asking until the park has returned: a request that lands
            // before the park publishes its word only costs one slice.
            while (!done.load(.acquire)) {
                requestService();
                var request = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
                _ = std.c.nanosleep(&request, null);
            }
        }
    };
    var word = Word.init(0);
    var done = std.atomic.Value(bool).init(false);
    const started = futex.monotonicNanoseconds();
    const requester = try std.Thread.spawn(.{}, Requester.run, .{&done});
    park(&word, 0, null, "service test");
    done.store(true, .release);
    requester.join();
    // Once before sleeping and once after: the request woke the slice long
    // before its 200 ms ran out.
    try std.testing.expect(counter.runs >= 2);
    try std.testing.expect(futex.monotonicNanoseconds() - started < 150 * std.time.ns_per_ms);
}

test "a service is not re-entered from inside itself" {
    const Reentrant = struct {
        depth: u32 = 0,
        deepest: u32 = 0,
        fn run(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.depth += 1;
            defer self.depth -= 1;
            self.deepest = @max(self.deepest, self.depth);
            var word = Word.init(1);
            // A park inside the service must not run the service again.
            park(&word, 1, futex.monotonicNanoseconds() + 1000, "inside service");
        }
    };
    var state: Reentrant = .{};
    const previous = installService(.{ .context = &state, .run = Reentrant.run });
    defer _ = installService(previous);
    runService();
    try std.testing.expectEqual(@as(u32, 1), state.deepest);
}
