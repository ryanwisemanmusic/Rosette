//! Which producer stopped, when a set of threads is waiting for something that
//! will never arrive.
//!
//! Distinct from `wait_graph.zig` in this same module, which detects classical
//! wait-for cycles through resource ownership. The failure here has no
//! ownership edge and no cycle in that sense: a thread that signalled a
//! condition variable and then waited on it owns nothing and blocks nobody. It
//! is only unsatisfiable because the set of threads that ever notified the
//! object and the set now waiting on it have become the same set — which is a
//! fact about notifier liveness, not about a resource graph, and no cycle
//! detector will find it.
//!
//! "blocked=15" is the least useful true statement a runtime can make. Fifteen
//! threads waiting is what a healthy emulator looks like between frames and
//! what a dead one looks like forever, and the number is identical in both
//! cases. Even naming the object does not settle it: twelve threads parked on
//! one condition variable is a thread pool at idle, or a lost wakeup, depending
//! entirely on whether anything is still going to signal it.
//!
//! So the question this answers is not "who is waiting" but "who was supposed
//! to wake them, and can they still". That needs one fact nobody records: the
//! identity of the threads that have *notified* the object in the past. With
//! it, three situations separate cleanly — notifications are still arriving;
//! notifications have stopped but a notifier is alive and could resume; and
//! every thread that has ever notified this object is now itself waiting on it,
//! which is a closed cycle that cannot open no matter how long anyone waits.
//!
//! The third case is a proof, not a heuristic, and it is worth the bookkeeping
//! precisely because it is the one that looks identical to idling from the
//! outside. A run that ends with it should name the object and the last thread
//! to signal it, because that thread's final path is where the missing
//! notification went.

const std = @import("std");

/// Threads are tracked by slot so membership is a bitmask rather than a scan.
/// Matches the scheduler's own fixed thread table.
pub const max_threads: usize = 64;
pub const ThreadMask = u64;

pub fn maskOf(slot: usize) ThreadMask {
    if (slot >= max_threads) return 0;
    return @as(ThreadMask, 1) << @intCast(slot);
}

/// What the waiters on one object can expect.
pub const Progress = enum(u8) {
    /// Nobody is waiting.
    idle,
    /// A notification arrived recently. Waiting here is normal.
    progressing,
    /// Waiters exist and nothing has ever notified this object. Either the
    /// producer has not started or it signals something else.
    never_notified,
    /// Notifications have stopped, but at least one thread that used to send
    /// them is still able to run. Recoverable, and worth watching.
    starved,
    /// Every thread that has ever notified this object is now itself waiting
    /// on it. No amount of time changes this.
    unsatisfiable,

    pub fn terminal(self: Progress) bool {
        return self == .unsatisfiable;
    }

    pub fn label(self: Progress) []const u8 {
        return switch (self) {
            .idle => "idle (no waiters)",
            .progressing => "progressing (a notification arrived recently)",
            .never_notified => "NEVER NOTIFIED (waiters exist and nothing has ever signalled this object)",
            .starved => "STARVED (notifications stopped; a past notifier is still runnable)",
            .unsatisfiable => "UNSATISFIABLE (every thread that ever notified this object is now waiting on it)",
        };
    }

    pub fn guidance(self: Progress) []const u8 {
        return switch (self) {
            .idle => "nothing to investigate here",
            .progressing => "this wait is being served; look elsewhere for the stall",
            .never_notified => "find the code that should signal this object and confirm it ran. Waiters chose this object, so something intended to signal it",
            .starved => "the last notifier is still able to run and has not signalled since. Follow that thread's path from its last notification forward — the notification it did not send is on it",
            .unsatisfiable => "this is a closed wait cycle and it will never open. The last thread to signal this object then waited on it, so the wake it owed was never sent. That thread's path between its last notification and its own wait is the defect",
        };
    }
};

/// One synchronisation object's history.
pub const Object = struct {
    address: u64 = 0,
    active: bool = false,
    /// Threads currently waiting.
    waiter_mask: ThreadMask = 0,
    /// Threads that have ever notified. The field that makes the difference.
    notifier_mask: ThreadMask = 0,
    notifications: u64 = 0,
    last_notify_step: u64 = 0,
    last_notify_thread: u64 = 0,
    last_notify_pc: u64 = 0,
    first_wait_step: u64 = 0,
    /// Threads that can still run: not waiting on this object, not finished.
    /// Supplied by the caller because only the scheduler knows.
    pub fn waiterCount(self: Object) u32 {
        return @popCount(self.waiter_mask);
    }

    pub fn notifierCount(self: Object) u32 {
        return @popCount(self.notifier_mask);
    }

    /// Whether every past notifier is currently parked on this same object.
    /// A notifier that has terminated is excluded by the caller, because a
    /// finished thread is not going to signal anything either but says
    /// something different about why.
    pub fn notifiersAllWaitingHere(self: Object) bool {
        if (self.notifier_mask == 0) return false;
        return self.notifier_mask & ~self.waiter_mask == 0;
    }
};

/// How long without a notification counts as stopped. Steps rather than time:
/// the runtime's own clock is virtual, and a step count is what correlates
/// with everything else in the log.
pub const default_stall_steps: u64 = 100_000_000;

pub fn classify(object: Object, current_step: u64, stall_steps: u64) Progress {
    if (object.waiter_mask == 0) return .idle;
    if (object.notifications == 0) return .never_notified;
    if (current_step -| object.last_notify_step < stall_steps) return .progressing;
    if (object.notifiersAllWaitingHere()) return .unsatisfiable;
    return .starved;
}

/// The set of objects, kept alongside the scheduler's own tables.
pub const Graph = struct {
    objects: [max_threads]Object = [_]Object{.{}} ** max_threads,
    count: usize = 0,
    overflow: u64 = 0,

    pub fn find(self: *Graph, address: u64) ?*Object {
        for (self.objects[0..self.count]) |*object| {
            if (object.active and object.address == address) return object;
        }
        return null;
    }

    pub fn findOrCreate(self: *Graph, address: u64) ?*Object {
        if (self.find(address)) |existing| return existing;
        if (self.count >= self.objects.len) {
            self.overflow +|= 1;
            return null;
        }
        const object = &self.objects[self.count];
        self.count += 1;
        object.* = .{ .address = address, .active = true };
        return object;
    }

    pub fn noteWait(self: *Graph, address: u64, slot: usize, step: u64) void {
        const object = self.findOrCreate(address) orelse return;
        if (object.waiter_mask == 0) object.first_wait_step = step;
        object.waiter_mask |= maskOf(slot);
    }

    pub fn noteWake(self: *Graph, address: u64, slot: usize) void {
        const object = self.find(address) orelse return;
        object.waiter_mask &= ~maskOf(slot);
    }

    /// Record who sent a notification. The thread identity is the point: a
    /// count of notifications cannot say whether the sender is still able to
    /// send another.
    pub fn noteNotify(self: *Graph, address: u64, slot: usize, thread: u64, pc: u64, step: u64) void {
        const object = self.findOrCreate(address) orelse return;
        object.notifier_mask |= maskOf(slot);
        object.notifications +|= 1;
        object.last_notify_step = step;
        object.last_notify_thread = thread;
        object.last_notify_pc = pc;
    }

    /// The object most worth reporting: the one whose waiters are most stuck.
    /// An unsatisfiable object outranks a starved one however long the starved
    /// one has waited, because only one of them is a proof.
    pub fn worstObject(self: *Graph, current_step: u64, stall_steps: u64) ?*Object {
        var worst: ?*Object = null;
        var worst_rank: u8 = 0;
        var worst_age: u64 = 0;
        for (self.objects[0..self.count]) |*object| {
            if (!object.active) continue;
            const progress = classify(object.*, current_step, stall_steps);
            const rank: u8 = switch (progress) {
                .idle, .progressing => 0,
                .starved => 1,
                .never_notified => 2,
                .unsatisfiable => 3,
            };
            if (rank == 0) continue;
            const age = current_step -| object.first_wait_step;
            if (rank > worst_rank or (rank == worst_rank and age > worst_age)) {
                worst = object;
                worst_rank = rank;
                worst_age = age;
            }
        }
        return worst;
    }
};

test "an object nobody waits on is idle regardless of history" {
    const object = Object{ .address = 0x1000, .active = true, .notifications = 5 };
    try std.testing.expectEqual(Progress.idle, classify(object, 1_000_000_000, default_stall_steps));
}

test "a recent notification means the wait is being served" {
    const object = Object{
        .address = 0x1000,
        .active = true,
        .waiter_mask = maskOf(3),
        .notifier_mask = maskOf(1),
        .notifications = 384,
        .last_notify_step = 900,
    };
    try std.testing.expectEqual(Progress.progressing, classify(object, 1000, default_stall_steps));
}

// Waiters chose this object, so something intended to signal it.
test "waiters with no notification history are a different finding from a stall" {
    const object = Object{ .address = 0x1000, .active = true, .waiter_mask = maskOf(3) };
    const progress = classify(object, 10_000_000_000, default_stall_steps);
    try std.testing.expectEqual(Progress.never_notified, progress);
    try std.testing.expect(std.mem.indexOf(u8, progress.guidance(), "confirm it ran") != null);
}

// The distinction the whole file exists for.
test "a closed wait cycle is proven, not guessed" {
    // Thread 7 notified this object 384 times and is now waiting on it, and it
    // is the only thread that ever notified it.
    const closed = Object{
        .address = 0x19a5668,
        .active = true,
        .waiter_mask = maskOf(7) | maskOf(4) | maskOf(11),
        .notifier_mask = maskOf(7),
        .notifications = 384,
        .last_notify_step = 3_381_773_258,
    };
    const progress = classify(closed, 10_175_000_000, default_stall_steps);
    try std.testing.expectEqual(Progress.unsatisfiable, progress);
    try std.testing.expect(progress.terminal());
    try std.testing.expect(std.mem.indexOf(u8, progress.label(), "UNSATISFIABLE") != null);
    try std.testing.expect(std.mem.indexOf(u8, progress.guidance(), "closed wait cycle") != null);
}

// If any past notifier is still outside the wait set, the cycle is open and a
// wake can still arrive. Calling that unsatisfiable would be a false alarm.
test "one notifier still outside the wait set makes it merely starved" {
    const open = Object{
        .address = 0x19a5668,
        .active = true,
        .waiter_mask = maskOf(7) | maskOf(4),
        // Thread 9 has notified before and is not waiting here.
        .notifier_mask = maskOf(7) | maskOf(9),
        .notifications = 384,
        .last_notify_step = 1,
    };
    const progress = classify(open, 10_000_000_000, default_stall_steps);
    try std.testing.expectEqual(Progress.starved, progress);
    try std.testing.expect(!progress.terminal());
    try std.testing.expect(std.mem.indexOf(u8, progress.guidance(), "still able to run") != null);
}

test "waits and wakes move threads in and out of the wait set" {
    var graph = Graph{};
    graph.noteWait(0x2000, 3, 100);
    graph.noteWait(0x2000, 4, 110);
    try std.testing.expectEqual(@as(u32, 2), graph.find(0x2000).?.waiterCount());
    // The first waiter set the age baseline, not the second.
    try std.testing.expectEqual(@as(u64, 100), graph.find(0x2000).?.first_wait_step);

    graph.noteWake(0x2000, 3);
    try std.testing.expectEqual(@as(u32, 1), graph.find(0x2000).?.waiterCount());
}

test "a notifier is remembered by identity, not just counted" {
    var graph = Graph{};
    graph.noteNotify(0x3000, 5, 0x7fff2050, 0x48b150, 900);
    graph.noteNotify(0x3000, 5, 0x7fff2050, 0x48b160, 950);
    const object = graph.find(0x3000).?;
    try std.testing.expectEqual(@as(u64, 2), object.notifications);
    // One distinct notifier, two notifications.
    try std.testing.expectEqual(@as(u32, 1), object.notifierCount());
    try std.testing.expectEqual(@as(u64, 0x7fff2050), object.last_notify_thread);
    try std.testing.expectEqual(@as(u64, 0x48b160), object.last_notify_pc);
    try std.testing.expectEqual(@as(u64, 950), object.last_notify_step);
}

// A proof outranks a long wait: reporting the oldest stall first would bury it.
test "an unsatisfiable object outranks an older starved one" {
    var graph = Graph{};
    // Old and starved.
    graph.noteNotify(0x4000, 1, 0xaa, 0, 10);
    graph.noteWait(0x4000, 2, 20);
    // Newer, but a closed cycle.
    graph.noteNotify(0x5000, 3, 0xbb, 0, 5_000_000);
    graph.noteWait(0x5000, 3, 5_000_100);

    const worst = graph.worstObject(10_000_000_000, default_stall_steps).?;
    try std.testing.expectEqual(@as(u64, 0x5000), worst.address);
}

test "an object whose waits are being served is never reported as worst" {
    var graph = Graph{};
    graph.noteNotify(0x6000, 1, 0xaa, 0, 9_999_999_000);
    graph.noteWait(0x6000, 2, 9_999_999_500);
    try std.testing.expect(graph.worstObject(10_000_000_000, default_stall_steps) == null);
}

test "the graph refuses to overflow and says it did" {
    var graph = Graph{};
    var index: usize = 0;
    while (index < max_threads + 4) : (index += 1) {
        graph.noteWait(0x8000 + index * 0x10, 1, 1);
    }
    try std.testing.expectEqual(max_threads, graph.count);
    try std.testing.expect(graph.overflow > 0);
}

test "a slot outside the table contributes no mask bit" {
    try std.testing.expectEqual(@as(ThreadMask, 0), maskOf(max_threads));
    try std.testing.expectEqual(@as(ThreadMask, 1), maskOf(0));
}

// An object with no notifier history must not be called a closed cycle: there
// is no notifier to have closed it.
test "no notifier history is never mistaken for a closed cycle" {
    const object = Object{ .address = 0x1000, .active = true, .waiter_mask = maskOf(1) };
    try std.testing.expect(!object.notifiersAllWaitingHere());
}

test "every progress state explains itself and what to do" {
    inline for (@typeInfo(Progress).@"enum".fields) |field| {
        const progress: Progress = @enumFromInt(field.value);
        try std.testing.expect(progress.label().len > 0);
        try std.testing.expect(progress.guidance().len > 0);
    }
}
