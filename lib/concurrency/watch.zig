//! Who is waiting on what, readable from any thread.
//!
//! A host thread that registers here gets one record it alone writes:
//! whether it is parked, on which word, under which label, since when, and
//! a progress counter its owner bumps. A watchdog - or an exit report after
//! a supervisor's SIGTERM - reads every record without taking a lock and
//! without stopping anyone, which is the only way to diagnose a process
//! whose threads are all asleep.
//!
//! The 2026-09-25 run hung for ninety seconds on a two-thread cycle: the
//! GPU worker held the runtime gate while it waited for the main thread to
//! run an AppKit block, and the main thread was parked on that gate. The
//! log's last line was the bridge saying it was marshaling a request; nothing
//! said who held what. With this registry the same state reads as a cycle.

const std = @import("std");
const futex = @import("futex.zig");

pub const capacity = 96;
pub const name_bytes = 32;

pub const State = enum(u8) {
    vacant,
    running,
    parked,
};

pub const Record = struct {
    /// One cache line per thread: the owner writes it constantly and no
    /// other thread's record shares it.
    state: std.atomic.Value(u8) align(128) = std.atomic.Value(u8).init(@intFromEnum(State.vacant)),
    thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Address of the futex word the thread is parked on, and a static label
    /// saying what that word is ("gate resume", "runtime mutex", ...).
    parked_on: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    parked_label: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    parked_since_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Bumped by the owner as it makes progress (guest steps, pumps...).
    progress: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    parks: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    parked_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    name_storage: [name_bytes]u8 = @splat(0),
    name_len: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    /// What the thread is doing when it is not parked - the import or
    /// runtime call it is inside - and since when, set by the embedder
    /// (`beginActivity`). The text is not copied: it must outlive the run,
    /// as import names and string literals do. A sequence count brackets
    /// every change (odd while it is being written), so a reader on another
    /// thread copies a name and length that belong together.
    activity_seq: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    activity_ptr: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    activity_len: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    activity_since_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// How many activities this thread has begun: a reader that sees the
    /// same count twice knows the thread never left the one it is in.
    activities: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub fn name(self: *const Record) []const u8 {
        return self.name_storage[0..@min(self.name_len.load(.acquire), name_bytes)];
    }

    /// The thread's current activity copied into `buffer` (truncated to it),
    /// and when it began; an empty name when it is in none, or when the
    /// owner was changing it at that instant.
    pub fn activity(self: *const Record, buffer: []u8) Activity {
        const before = self.activity_seq.load(.acquire);
        if ((before & 1) != 0) return .{};
        const pointer = self.activity_ptr.load(.acquire);
        const length = self.activity_len.load(.acquire);
        const since = self.activity_since_ns.load(.acquire);
        if (pointer == 0) return .{};
        // Copy before the second sequence read, with acquire loads, so that
        // read cannot move ahead of the copy: a change during the copy is
        // then seen, and the copy discarded.
        const copied = @min(length, buffer.len);
        const source: [*]const u8 = @ptrFromInt(pointer);
        for (buffer[0..copied], 0..) |*byte, index| byte.* = @atomicLoad(u8, &source[index], .acquire);
        if (self.activity_seq.load(.acquire) != before) return .{};
        return .{ .name = buffer[0..copied], .since_ns = since };
    }

    pub fn label(self: *const Record) []const u8 {
        const pointer = self.parked_label.load(.acquire);
        if (pointer == 0) return "";
        return std.mem.sliceTo(@as([*:0]const u8, @ptrFromInt(pointer)), 0);
    }

    pub fn currentState(self: *const Record) State {
        return @enumFromInt(self.state.load(.acquire));
    }

    /// Nanoseconds this thread has been parked at `now`, or zero.
    pub fn parkedFor(self: *const Record, now: u64) u64 {
        if (self.currentState() != .parked) return 0;
        return now -| self.parked_since_ns.load(.acquire);
    }
};

pub const Activity = struct {
    name: []const u8 = "",
    since_ns: u64 = 0,
};

var records: [capacity]Record = [_]Record{.{}} ** capacity;
var records_used: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
threadlocal var current_record: ?*Record = null;

/// Register the calling thread under `thread_name`. Idempotent: a second
/// call renames. Returns null when every record is taken; the thread then
/// simply goes unwatched.
pub fn registerCurrentThread(thread_name: []const u8) ?*Record {
    if (current_record) |record| {
        setName(record, thread_name);
        return record;
    }
    for (&records, 0..) |*record, index| {
        if (record.state.cmpxchgStrong(@intFromEnum(State.vacant), @intFromEnum(State.running), .acq_rel, .monotonic) != null) continue;
        record.thread_id.store(@intCast(std.Thread.getCurrentId()), .release);
        record.parked_on.store(0, .release);
        record.parked_label.store(0, .release);
        record.progress.store(0, .release);
        record.activities.store(0, .release);
        setActivity(record, 0, 0, 0);
        setName(record, thread_name);
        current_record = record;
        _ = records_used.fetchMax(@intCast(index + 1), .acq_rel);
        return record;
    }
    return null;
}

/// Release the calling thread's record, if it has one.
pub fn unregisterCurrentThread() void {
    const record = current_record orelse return;
    current_record = null;
    record.name_len.store(0, .release);
    record.thread_id.store(0, .release);
    record.state.store(@intFromEnum(State.vacant), .release);
}

pub fn currentRecord() ?*Record {
    return current_record;
}

/// Count progress for the calling thread (cheap: one relaxed store to its
/// own line).
pub fn noteProgress(amount: u64) void {
    const record = current_record orelse return;
    record.progress.store(record.progress.load(.monotonic) +% amount, .monotonic);
}

/// Say what the calling thread is now doing - an import, a runtime call -
/// until `endActivity`. `text` must outlive the run. Nested calls replace
/// the outer activity; a thread reports the innermost thing it is in.
pub fn beginActivity(text: []const u8) void {
    const record = current_record orelse return;
    setActivity(record, @intFromPtr(text.ptr), @intCast(@min(text.len, std.math.maxInt(u32))), futex.monotonicNanoseconds());
    record.activities.store(record.activities.load(.monotonic) +% 1, .monotonic);
}

/// The calling thread has left its activity.
pub fn endActivity() void {
    const record = current_record orelse return;
    if (record.activity_ptr.load(.monotonic) == 0) return;
    setActivity(record, 0, 0, 0);
}

fn setActivity(record: *Record, pointer: usize, length: u32, since: u64) void {
    // Odd while the fields change. The field stores are releases, so none of
    // them can become visible before the odd count that announces them; the
    // closing even count is a release too.
    const sequence = record.activity_seq.load(.monotonic);
    record.activity_seq.store(sequence +% 1, .monotonic);
    record.activity_ptr.store(pointer, .release);
    record.activity_len.store(length, .release);
    record.activity_since_ns.store(since, .release);
    record.activity_seq.store(sequence +% 2, .release);
}

fn setName(record: *Record, thread_name: []const u8) void {
    const length = @min(thread_name.len, name_bytes);
    @memcpy(record.name_storage[0..length], thread_name[0..length]);
    record.name_len.store(@intCast(length), .release);
}

/// Called by `park.zig` around every sleep.
pub fn beginPark(word: *const futex.Word, label: [*:0]const u8, now: u64) void {
    const record = current_record orelse return;
    record.parked_on.store(@intFromPtr(word), .monotonic);
    record.parked_label.store(@intFromPtr(label), .monotonic);
    record.parked_since_ns.store(now, .monotonic);
    record.state.store(@intFromEnum(State.parked), .release);
}

/// Mark the calling thread as blocked in something that is not a park of
/// this package - a `dispatch_sync` to the main thread, a driver call - so a
/// stall report still says where it is. Pair with `endBlocking`.
pub fn beginBlocking(label: [*:0]const u8) void {
    const record = current_record orelse return;
    record.parked_on.store(0, .monotonic);
    record.parked_label.store(@intFromPtr(label), .monotonic);
    record.parked_since_ns.store(futex.monotonicNanoseconds(), .monotonic);
    record.state.store(@intFromEnum(State.parked), .release);
}

pub fn endBlocking() void {
    endPark(futex.monotonicNanoseconds());
}

pub fn endPark(now: u64) void {
    const record = current_record orelse return;
    const since = record.parked_since_ns.load(.monotonic);
    record.state.store(@intFromEnum(State.running), .release);
    record.parks.store(record.parks.load(.monotonic) +% 1, .monotonic);
    record.parked_ns.store(record.parked_ns.load(.monotonic) +% (now -| since), .monotonic);
}

/// Every registered record, for reports. The slice is stable; records in it
/// may be vacant.
pub fn allRecords() []Record {
    return records[0..records_used.load(.acquire)];
}

/// A thread whose longest current park exceeds `threshold_ns`, for a
/// watchdog: the longest-parked record, or null when nobody has been asleep
/// that long.
pub fn longestParked(now: u64, threshold_ns: u64) ?*Record {
    var worst: ?*Record = null;
    var worst_ns: u64 = threshold_ns;
    for (allRecords()) |*record| {
        const parked = record.parkedFor(now);
        if (parked >= worst_ns) {
            worst = record;
            worst_ns = parked;
        }
    }
    return worst;
}

test "a registered thread is named, parks and unparks in its record" {
    const record = registerCurrentThread("watch test").?;
    defer unregisterCurrentThread();
    try std.testing.expectEqualStrings("watch test", record.name());
    var word = futex.Word.init(0);
    beginPark(&word, "test word", 100);
    try std.testing.expectEqual(State.parked, record.currentState());
    try std.testing.expectEqualStrings("test word", record.label());
    try std.testing.expectEqual(@as(u64, 50), record.parkedFor(150));
    try std.testing.expect(longestParked(150, 10) == record);
    endPark(160);
    try std.testing.expectEqual(State.running, record.currentState());
    try std.testing.expectEqual(@as(u64, 60), record.parked_ns.load(.acquire));
    try std.testing.expect(longestParked(1000, 10) == null);
}

test "a thread's activity is readable from another thread and ends empty" {
    const Shared = struct {
        record: std.atomic.Value(?*Record) = std.atomic.Value(?*Record).init(null),
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn run(self: *@This()) void {
            self.record.store(registerCurrentThread("activity test"), .release);
            defer unregisterCurrentThread();
            const names = [_][]const u8{ "USER32.dll!GetMessageW", "vulkan-1.dll!vkGetDeviceQueue" };
            var index: usize = 0;
            while (!self.stop.load(.acquire)) : (index +%= 1) {
                beginActivity(names[index % names.len]);
                std.atomic.spinLoopHint();
                endActivity();
            }
            beginActivity("KERNEL32.dll!Sleep");
            while (self.record.load(.acquire) != null) std.atomic.spinLoopHint();
        }
    };
    var shared: Shared = .{};
    const thread = try std.Thread.spawn(.{}, Shared.run, .{&shared});
    while (shared.record.load(.acquire) == null) std.atomic.spinLoopHint();
    const record = shared.record.load(.acquire).?;
    var buffer: [64]u8 = undefined;
    // Every name read while it changes is one of the whole names, never a
    // mix of one's pointer and the other's length.
    for (0..20_000) |_| {
        const seen = record.activity(&buffer);
        if (seen.name.len == 0) continue;
        try std.testing.expect(std.mem.eql(u8, seen.name, "USER32.dll!GetMessageW") or
            std.mem.eql(u8, seen.name, "vulkan-1.dll!vkGetDeviceQueue"));
    }
    shared.stop.store(true, .release);
    while (!std.mem.eql(u8, record.activity(&buffer).name, "KERNEL32.dll!Sleep")) std.atomic.spinLoopHint();
    try std.testing.expect(record.activity(&buffer).since_ns != 0);
    try std.testing.expect(record.activities.load(.acquire) != 0);
    shared.record.store(null, .release);
    thread.join();
}

test "records are reused after a thread leaves" {
    const first = registerCurrentThread("first").?;
    unregisterCurrentThread();
    try std.testing.expectEqual(State.vacant, first.currentState());
    const second = registerCurrentThread("second").?;
    defer unregisterCurrentThread();
    try std.testing.expect(second == first);
    try std.testing.expectEqualStrings("second", second.name());
}
