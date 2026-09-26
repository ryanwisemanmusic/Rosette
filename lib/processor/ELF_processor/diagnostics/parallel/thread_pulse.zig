//! A periodic line per host thread: what it is doing, what it is waiting
//! on, and how far it got since the last look.
//!
//! Every Xenia run so far has ended on the operator's SIGTERM or on a fault,
//! and a parallel run's threads move independently: a run can look alive in
//! every counter while the one thread the frame needs has sat in the same
//! wait for a minute. The stall watchdog reports only when *nothing* moves.
//! The pulse runs on the watchdog's thread, reads only the lock-free watch
//! records, and writes the whole table every few seconds - so the log of a
//! run that hangs, crawls or crashes still says, at a known time, which
//! thread was where.

const std = @import("std");
const concurrency = @import("concurrency");
const watch = concurrency.watch;

/// Print every pulse for the first `dense_ns` of the run, then one per
/// `sparse_ns`: the start of a run is where bring-up happens and where
/// everything so far has gone wrong.
pub const Policy = struct {
    dense_ns: u64 = 60 * std.time.ns_per_s,
    sparse_ns: u64 = 30 * std.time.ns_per_s,
    last_printed_ns: u64 = 0,

    pub fn shouldPrint(self: *Policy, elapsed_ns: u64) bool {
        if (elapsed_ns <= self.dense_ns or elapsed_ns -| self.last_printed_ns >= self.sparse_ns) {
            self.last_printed_ns = elapsed_ns;
            return true;
        }
        return false;
    }
};

/// What each record said at the previous printed pulse, for deltas. Used
/// only on the watchdog thread.
pub const Memory = struct {
    thread_id: [watch.capacity]u64 = @splat(0),
    progress: [watch.capacity]u64 = @splat(0),
    parks: [watch.capacity]u64 = @splat(0),
    parked_ns: [watch.capacity]u64 = @splat(0),
    activities: [watch.capacity]u64 = @splat(0),
};

pub const Row = struct {
    name: []const u8,
    state: watch.State,
    thread_id: u64,
    /// For a running thread: its activity, and how long it has been in it.
    activity: []const u8,
    activity_ms: u64,
    /// For a parked thread: what it waits on, and for how long.
    waiting_on: []const u8,
    parked_for_ms: u64,
    progress_delta: u64,
    parks_delta: u64,
    parked_ms_delta: u64,
    /// Activities begun since the previous pulse: zero for a running thread
    /// means it has been inside one call the whole interval.
    activities_delta: u64,
};

/// Describe `record` (at `index` in `watch.allRecords()`) and advance its
/// deltas. `activity_buffer` receives the activity name.
pub fn row(memory: *Memory, index: usize, record: *const watch.Record, now_ns: u64, activity_buffer: []u8) Row {
    const thread_id = record.thread_id.load(.monotonic);
    if (index < watch.capacity and memory.thread_id[index] != thread_id) {
        // A new thread in a reused record starts its deltas at zero.
        memory.thread_id[index] = thread_id;
        memory.progress[index] = 0;
        memory.parks[index] = 0;
        memory.parked_ns[index] = 0;
        memory.activities[index] = 0;
    }
    const progress = record.progress.load(.monotonic);
    const parks = record.parks.load(.monotonic);
    const parked_ns = record.parked_ns.load(.monotonic);
    const activities = record.activities.load(.monotonic);
    const state = record.currentState();
    const current = record.activity(activity_buffer);
    var result: Row = .{
        .name = record.name(),
        .state = state,
        .thread_id = thread_id,
        .activity = current.name,
        .activity_ms = if (current.since_ns != 0) (now_ns -| current.since_ns) / std.time.ns_per_ms else 0,
        .waiting_on = if (state == .parked) record.label() else "",
        .parked_for_ms = record.parkedFor(now_ns) / std.time.ns_per_ms,
        .progress_delta = 0,
        .parks_delta = 0,
        .parked_ms_delta = 0,
        .activities_delta = 0,
    };
    if (index < watch.capacity) {
        result.progress_delta = progress -% memory.progress[index];
        result.parks_delta = parks -% memory.parks[index];
        result.parked_ms_delta = (parked_ns -% memory.parked_ns[index]) / std.time.ns_per_ms;
        result.activities_delta = activities -% memory.activities[index];
        memory.progress[index] = progress;
        memory.parks[index] = parks;
        memory.parked_ns[index] = parked_ns;
        memory.activities[index] = activities;
    }
    return result;
}

/// The record of the thread with id `thread_id`, if it registered one.
pub fn recordForThread(thread_id: u64) ?*const watch.Record {
    if (thread_id == 0) return null;
    for (watch.allRecords()) |*record| {
        if (record.currentState() != .vacant and record.thread_id.load(.monotonic) == thread_id) return record;
    }
    return null;
}

test "the policy is dense at the start and sparse after" {
    var policy: Policy = .{ .dense_ns = 10, .sparse_ns = 100 };
    try std.testing.expect(policy.shouldPrint(5));
    try std.testing.expect(policy.shouldPrint(10));
    try std.testing.expect(!policy.shouldPrint(50));
    try std.testing.expect(policy.shouldPrint(111));
    try std.testing.expect(!policy.shouldPrint(150));
    try std.testing.expect(policy.shouldPrint(211));
}

test "a row reports deltas since the last pulse and the thread's activity" {
    const record = watch.registerCurrentThread("pulse test").?;
    defer watch.unregisterCurrentThread();
    var index: usize = 0;
    for (watch.allRecords(), 0..) |*candidate, position| {
        if (candidate == record) index = position;
    }
    var memory: Memory = .{};
    var buffer: [64]u8 = undefined;
    watch.noteProgress(100);
    watch.beginActivity("vkGetDeviceQueue");
    const first = row(&memory, index, record, concurrency.monotonicNanoseconds(), &buffer);
    try std.testing.expectEqualStrings("pulse test", first.name);
    try std.testing.expectEqualStrings("vkGetDeviceQueue", first.activity);
    try std.testing.expectEqual(@as(u64, 100), first.progress_delta);
    try std.testing.expectEqual(@as(u64, 1), first.activities_delta);
    watch.noteProgress(25);
    const second = row(&memory, index, record, concurrency.monotonicNanoseconds(), &buffer);
    try std.testing.expectEqual(@as(u64, 25), second.progress_delta);
    // Still inside the same call: no activity begun since the last look.
    try std.testing.expectEqual(@as(u64, 0), second.activities_delta);
    watch.endActivity();
    try std.testing.expect(recordForThread(record.thread_id.load(.monotonic)) == record);
    try std.testing.expect(recordForThread(0) == null);
}
