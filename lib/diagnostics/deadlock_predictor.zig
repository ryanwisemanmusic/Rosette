//! Threads that will never wake, and who was supposed to wake them.
//!
//! A livelock burns CPU making no progress; a deadlock burns nothing. They look
//! nothing alike from inside and identical from outside — the run stops
//! advancing — so the detector that finds one is structurally blind to the
//! other. The livelock predictor watches for repetition. Nothing here repeats:
//! a parked thread emits no log lines, consumes no steps, and is invisible to
//! every heuristic built on activity.
//!
//! So this asks the opposite question. Not "what keeps happening" but **"who is
//! waiting, and can anyone still signal them?"**
//!
//! ## Why a cycle is not the only deadlock
//!
//! The textbook deadlock is a cycle: A holds X and wants Y, B holds Y and wants
//! X. Real emulator deadlocks are usually simpler and are missed by cycle
//! detection entirely:
//!
//!   * Nobody has *ever* signalled the object. A waiter parked on an event no
//!     code path reaches is deadlocked with no cycle at all.
//!   * The only thread that ever signalled it has terminated. The object is
//!     live, the waiters are live, and the producer is gone.
//!   * Every thread that could signal it is itself parked. No cycle is needed —
//!     the wait-for graph just has no live root.
//!
//! Each of those is a different bug with a different owner, and reporting them
//! all as "deadlock" throws away the part that says what to do. The finding
//! names which one it is.
//!
//! ## Evidence, not inference
//!
//! A thread is only recorded as waiting when something observed it waiting, and
//! an object only gains a notifier when a thread is observed signalling it.
//! "No notifier" therefore means "none observed", which is why the report
//! always states how long the observation window was: on a short window that is
//! not evidence of anything, and the verdict says so rather than accusing a
//! thread that simply had not run yet.

const std = @import("std");

/// What kind of synchronisation object a thread is parked on. Kept because the
/// remedies differ: a semaphore with a zero count is a counting problem, an
/// event nobody sets is a control-flow problem, and a join on a dead thread is
/// a lifetime problem.
pub const ObjectKind = enum(u8) {
    unknown,
    event,
    semaphore,
    mutex,
    condvar,
    critical_section,
    thread_join,

    pub fn label(self: ObjectKind) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .event => "event",
            .semaphore => "semaphore",
            .mutex => "mutex",
            .condvar => "condvar",
            .critical_section => "critical_section",
            .thread_join => "thread_join",
        };
    }
};

/// Why a set of waiters cannot make progress. Ordered by severity so the worst
/// across a table is a max, and each names a different owner.
pub const Finding = enum(u8) {
    /// Nobody is waiting on anything. The least informative state, so it ranks
    /// below a live handshake: `worst` walks every object, and an idle one must
    /// never outrank one that is demonstrably working.
    no_waiters = 0,
    /// Waiters exist and someone has signalled recently. Normal.
    healthy = 1,
    /// Waiters exist and the observation window is too short to conclude that
    /// nobody will signal. Explicitly not a finding.
    window_too_short = 2,
    /// Every thread that has ever signalled this object is itself parked. The
    /// wait-for graph has no live root, which is a deadlock without a cycle.
    all_notifiers_parked = 3,
    /// The only threads that ever signalled this object have terminated. The
    /// object is live, the waiters are live, and the producer is gone.
    notifiers_terminated = 4,
    /// Nothing has ever signalled this object and something is waiting on it.
    /// A waiter parked on an object no code path reaches.
    never_notified = 5,
    /// A true cycle: each thread in the chain waits on an object only the next
    /// thread can signal.
    wait_cycle = 6,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .no_waiters => "no_waiters",
            .healthy => "healthy",
            .window_too_short => "window_too_short",
            .all_notifiers_parked => "ALL_NOTIFIERS_PARKED",
            .notifiers_terminated => "NOTIFIERS_TERMINATED",
            .never_notified => "NEVER_NOTIFIED",
            .wait_cycle => "WAIT_CYCLE",
        };
    }

    pub fn deadlocked(self: Finding) bool {
        return @intFromEnum(self) >= @intFromEnum(Finding.all_notifiers_parked);
    }

    /// Whether the finding is strong enough to stop a run without another
    /// causal witness. `deadlocked()` intentionally includes NEVER_NOTIFIED
    /// because it is a useful predictor result; a worker that has never been
    /// signalled is not, by that fact alone, distinguishable from an idle
    /// worker waiting for future work. The run-integrity gate uses this stricter
    /// predicate and treats a mature explicit cycle as proven separately.
    pub fn provenDeadlock(self: Finding) bool {
        return self == .all_notifiers_parked or
            self == .notifiers_terminated or
            self == .wait_cycle;
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .no_waiters => "nothing is parked on this object",
            .healthy => "waiters exist and something has signalled recently, so this handshake is making progress",
            .window_too_short => "waiters exist and the observation window is too short to conclude that nobody will signal them. This is not a finding; it is a statement that the run has not been watched long enough",
            .all_notifiers_parked => "every thread that has ever signalled this object is itself parked on something. The wait-for graph has no live root, so no amount of waiting resolves it — this is a deadlock even though no cycle exists. Find the one thread that should still be running and ask what parked it",
            .notifiers_terminated => "the only threads that ever signalled this object have terminated. The object is live and its waiters are live and the producer is gone, so the waiters are parked forever. Look at why the producer exited before its consumers did",
            .never_notified => "something is parked on an object nothing has ever signalled. No thread has been observed raising it even once, so the waiter is not waiting for a late signal — it is waiting for a code path that has not been reached. Find who was supposed to signal it and confirm that code ran at all",
            .wait_cycle => "each thread in this chain waits on an object only the next thread in the chain can signal. This is a true circular deadlock and it will not resolve on its own; breaking any one edge releases all of them",
        };
    }
};

/// A thread's participation in the graph.
pub const ThreadState = enum(u8) {
    running,
    /// Parked on an object.
    waiting,
    terminated,

    pub fn parked(self: ThreadState) bool {
        return self == .waiting;
    }
};

pub const max_threads = 48;
pub const max_objects = 48;

/// Steps a waiter must have been parked before its silence means anything.
/// Below this a thread that simply has not been scheduled yet reads as
/// deadlocked, which is the easiest possible false positive to produce.
pub const minimum_park_steps: u64 = 50_000_000;

pub const Thread = struct {
    handle: u64 = 0,
    state: ThreadState = .running,
    waiting_on: u64 = 0,
    blocked_since_step: u64 = 0,
    /// The instruction boundary that entered the wait. A parked thread has
    /// no later instruction samples, so this is the most useful answer to
    /// "where did it stop?" without a host debugger.
    blocked_rip: u64 = 0,
    start_routine: u64 = 0,
    waiting_mutex: u64 = 0,
    wait_generation: u64 = 0,
    notified_generation: u64 = 0,
    blocked_reason: []const u8 = "",
};

pub const Object = struct {
    address: u64 = 0,
    kind: ObjectKind = .unknown,
    waiters: u32 = 0,
    notifications: u64 = 0,
    /// Threads observed signalling this object. Bounded to a small set: the
    /// question is whether *any* live thread can, not an exact roster.
    notifiers: [4]u64 = [_]u64{0} ** 4,
    notifier_count: u32 = 0,
    last_notify_step: u64 = 0,
    last_notify_thread: u64 = 0,
    last_notify_pc: u64 = 0,
    /// The longest any current waiter has been parked here.
    longest_park_steps: u64 = 0,
    /// How many times a bounded spurious wake was granted to this object's
    /// waiters. A count above zero means the repair was attempted and the
    /// waiter re-parked: the predicate is genuinely unsatisfied, which is a
    /// different (and stronger) statement than "nobody has ever signalled it".
    repair_attempts: u32 = 0,

    fn addNotifier(self: *Object, thread: u64) void {
        if (thread == 0) return;
        for (self.notifiers[0..self.notifier_count]) |existing| {
            if (existing == thread) return;
        }
        if (self.notifier_count == self.notifiers.len) return;
        self.notifiers[self.notifier_count] = thread;
        self.notifier_count += 1;
    }
};

/// Optional context attached to a scheduler observation. The original
/// four-argument observer remains below for small callers and tests; the
/// richer form is what the Mach-O runtime uses when it can preserve the wait
/// boundary.
pub const ThreadObservation = struct {
    handle: u64,
    state: ThreadState,
    waiting_on: u64,
    blocked_since_step: u64,
    blocked_rip: u64 = 0,
    start_routine: u64 = 0,
    waiting_mutex: u64 = 0,
    wait_generation: u64 = 0,
    notified_generation: u64 = 0,
    blocked_reason: []const u8 = "",
};

pub const Ledger = struct {
    threads: [max_threads]Thread = [_]Thread{.{}} ** max_threads,
    thread_count: usize = 0,
    objects: [max_objects]Object = [_]Object{.{}} ** max_objects,
    object_count: usize = 0,
    untracked_threads: u64 = 0,
    untracked_objects: u64 = 0,

    fn threadSlot(self: *Ledger, handle: u64) ?*Thread {
        for (self.threads[0..self.thread_count]) |*thread| {
            if (thread.handle == handle) return thread;
        }
        if (self.thread_count == max_threads) {
            self.untracked_threads +|= 1;
            return null;
        }
        const thread = &self.threads[self.thread_count];
        thread.* = .{ .handle = handle };
        self.thread_count += 1;
        return thread;
    }

    fn objectSlot(self: *Ledger, address: u64) ?*Object {
        for (self.objects[0..self.object_count]) |*object| {
            if (object.address == address) return object;
        }
        if (self.object_count == max_objects) {
            self.untracked_objects +|= 1;
            return null;
        }
        const object = &self.objects[self.object_count];
        object.* = .{ .address = address };
        self.object_count += 1;
        return object;
    }

    pub fn observeThread(
        self: *Ledger,
        handle: u64,
        state: ThreadState,
        waiting_on: u64,
        blocked_since_step: u64,
    ) void {
        self.observeThreadContext(.{
            .handle = handle,
            .state = state,
            .waiting_on = waiting_on,
            .blocked_since_step = blocked_since_step,
        });
    }

    pub fn observeThreadContext(self: *Ledger, observation: ThreadObservation) void {
        const handle = observation.handle;
        if (handle == 0) return;
        const thread = self.threadSlot(handle) orelse return;
        thread.state = observation.state;
        thread.waiting_on = if (observation.state == .waiting) observation.waiting_on else 0;
        thread.blocked_since_step = observation.blocked_since_step;
        thread.blocked_rip = observation.blocked_rip;
        thread.start_routine = observation.start_routine;
        thread.waiting_mutex = if (observation.state == .waiting) observation.waiting_mutex else 0;
        thread.wait_generation = if (observation.state == .waiting) observation.wait_generation else 0;
        thread.notified_generation = if (observation.state == .waiting) observation.notified_generation else 0;
        thread.blocked_reason = if (observation.state == .waiting) observation.blocked_reason else "";
    }

    pub fn observeNotify(self: *Ledger, address: u64, kind: ObjectKind, notifier: u64, step: u64) void {
        if (address == 0) return;
        const object = self.objectSlot(address) orelse return;
        if (object.kind == .unknown) object.kind = kind;
        object.notifications +|= 1;
        object.last_notify_step = step;
        object.last_notify_thread = notifier;
        object.last_notify_pc = 0;
        object.addNotifier(notifier);
    }

    /// Record the notifier's call-site PC when the caller has it. Kept
    /// separate from `observeNotify` so the compatibility observer above can
    /// remain address-only without inventing a program counter.
    pub fn observeNotifyAt(
        self: *Ledger,
        address: u64,
        kind: ObjectKind,
        notifier: u64,
        program_counter: u64,
        step: u64,
    ) void {
        self.observeNotify(address, kind, notifier, step);
        if (address == 0) return;
        if (self.objectSlot(address)) |object| object.last_notify_pc = program_counter;
    }

    /// Declare an object exists and what kind it is, without a notification.
    pub fn observeObject(self: *Ledger, address: u64, kind: ObjectKind) void {
        if (address == 0) return;
        const object = self.objectSlot(address) orelse return;
        if (object.kind == .unknown) object.kind = kind;
    }

    /// Record that a bounded spurious wake was granted to this object's
    /// waiters. Kept separate from notifications: a notification is the
    /// guest signalling the object, a repair is Rosette manufacturing one
    /// wake to let the guest re-check its predicate.
    pub fn observeRepair(self: *Ledger, address: u64, attempts: u32) void {
        if (address == 0 or attempts == 0) return;
        const object = self.objectSlot(address) orelse return;
        object.repair_attempts = attempts;
    }

    /// Recompute waiter counts from the thread table. Called before a verdict
    /// so the two halves can never drift apart.
    pub fn refresh(self: *Ledger, now_step: u64) void {
        for (self.objects[0..self.object_count]) |*object| {
            object.waiters = 0;
            object.longest_park_steps = 0;
        }
        for (self.threads[0..self.thread_count]) |thread| {
            if (!thread.state.parked() or thread.waiting_on == 0) continue;
            const object = self.objectSlot(thread.waiting_on) orelse continue;
            object.waiters += 1;
            const parked = if (now_step > thread.blocked_since_step)
                now_step - thread.blocked_since_step
            else
                0;
            if (parked > object.longest_park_steps) object.longest_park_steps = parked;
        }
    }

    fn threadState(self: *const Ledger, handle: u64) ?ThreadState {
        for (self.threads[0..self.thread_count]) |thread| {
            if (thread.handle == handle) return thread.state;
        }
        return null;
    }

    /// Classify one object.
    pub fn classify(self: *const Ledger, object: Object) Finding {
        if (object.waiters == 0) return .no_waiters;
        if (object.longest_park_steps < minimum_park_steps) return .window_too_short;
        if (object.notifier_count == 0 and object.notifications == 0) return .never_notified;

        var live_notifier = false;
        var any_terminated = false;
        for (object.notifiers[0..object.notifier_count]) |handle| {
            const state = self.threadState(handle) orelse {
                // A notifier whose thread we never modelled might still be
                // live; refusing to conclude is the honest answer.
                live_notifier = true;
                continue;
            };
            switch (state) {
                .running => live_notifier = true,
                .terminated => any_terminated = true,
                .waiting => {},
            }
        }
        if (live_notifier) return .healthy;
        if (any_terminated) return .notifiers_terminated;
        if (object.notifier_count != 0) return .all_notifiers_parked;
        return .never_notified;
    }

    /// A cycle through the wait-for graph starting at `handle`, if one exists.
    ///
    /// The edge from a thread is: it waits on an object, and the object's
    /// notifiers are the threads that could release it. A cycle means every
    /// releaser is itself waiting on something the chain eventually closes.
    ///
    /// Three guards keep this honest, all conservative (they make the detector
    /// *less* willing to call something a cycle, matching the roster being a
    /// lower bound):
    ///
    ///   * A running (or unmodelled) notifier means the wait can still be
    ///     released, so the chain is open and cannot be a deadlock cycle. A
    ///     worker pool at idle has plenty of parked members who have signalled
    ///     the pool condvar; the pool is only a deadlock if *nobody* who has
    ///     ever signalled it can still run.
    ///   * A thread that signalled the object it now waits on is not "the next
    ///     thread in the chain": picking it would report a cycle whose
    ///     entries repeat (`[A, B, B]`), which contradicts the finding's own
    ///     description.
    ///   * Walking the same dependency object twice with different threads is
    ///     an open handshake (every pool member waits on the same condvar),
    ///     not a narrowed dependency. A true cycle walks distinct objects
    ///     until it closes on a thread.
    pub fn findCycle(self: *const Ledger, handle: u64, out: []u64) ?[]u64 {
        var length: usize = 0;
        var current = handle;
        var seen_objects: [8]u64 = [_]u64{0} ** 8;
        var seen_object_count: usize = 0;
        while (length < out.len) {
            out[length] = current;
            length += 1;

            var waiting_on: u64 = 0;
            var state: ThreadState = .running;
            for (self.threads[0..self.thread_count]) |thread| {
                if (thread.handle != current) continue;
                waiting_on = thread.waiting_on;
                state = thread.state;
            }
            if (!state.parked() or waiting_on == 0) return null;

            var next: u64 = 0;
            var live_releaser = false;
            for (self.objects[0..self.object_count]) |object| {
                if (object.address != waiting_on) continue;
                for (object.notifiers[0..object.notifier_count]) |notifier| {
                    const notifier_state = self.threadState(notifier) orelse {
                        // A notifier we never modelled might still be live;
                        // refusing to close the cycle is the honest answer.
                        live_releaser = true;
                        break;
                    };
                    switch (notifier_state) {
                        .running => live_releaser = true,
                        .waiting => {
                            if (next == 0 and notifier != current) next = notifier;
                        },
                        .terminated => {},
                    }
                    if (live_releaser) break;
                }
                break;
            }
            // Any thread that could still release this wait opens the chain,
            // whatever the rest of the roster looks like.
            if (live_releaser) return null;
            if (next == 0) return null;
            // A thread that waits on an object the chain already walked is the
            // same release set repeated — a mutual wait or a worker pool at
            // idle, not a narrowing dependency. This check comes before the
            // close so a cycle must walk distinct objects to count as one;
            // classification already names the repeated-object case as
            // all-notifiers-parked.
            for (seen_objects[0..seen_object_count]) |seen| {
                if (seen == waiting_on) return null;
            }
            seen_objects[seen_object_count] = waiting_on;
            seen_object_count += 1;
            // Closing back onto any thread already in the chain is a cycle.
            for (out[0..length]) |seen| {
                if (seen == next) {
                    if (length < out.len) {
                        out[length] = next;
                        length += 1;
                    }
                    return out[0..length];
                }
            }
            current = next;
        }
        return null;
    }

    /// The worst finding across every object, and the object it belongs to.
    pub fn worst(self: *const Ledger) struct { finding: Finding, object: ?Object } {
        var result = Finding.no_waiters;
        // Starts at the least severe value, which is why `no_waiters` has to be
        // the enum's zero: an idle object outranking a working one would make
        // every healthy run report as idle.
        var chosen: ?Object = null;
        for (self.objects[0..self.object_count]) |object| {
            const finding = self.classify(object);
            if (@intFromEnum(finding) > @intFromEnum(result)) {
                result = finding;
                chosen = object;
            }
        }
        return .{ .finding = result, .object = chosen };
    }

    pub fn parkedThreadCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.threads[0..self.thread_count]) |thread| {
            if (thread.state.parked()) count += 1;
        }
        return count;
    }

    /// Copy the current waiters for one object into caller-owned storage. A
    /// report should name the actual waiter, not merely repeat the object's
    /// address; returning copies keeps this diagnostic bounded and avoids
    /// exposing mutable ledger storage to formatters.
    pub fn waitersFor(self: *const Ledger, address: u64, out: []Thread) []const Thread {
        var count: usize = 0;
        for (self.threads[0..self.thread_count]) |thread| {
            if (thread.state != .waiting or thread.waiting_on != address) continue;
            if (count == out.len) break;
            out[count] = thread;
            count += 1;
        }
        return out[0..count];
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.thread_count == 0)
            return "no thread state has been observed, so nothing can be said about deadlock either way";
        return self.worst().finding.meaning();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const long_park: u64 = minimum_park_steps * 2;

test "a thread parked briefly is not accused of deadlock" {
    var ledger = Ledger{};
    ledger.observeObject(0x1000, .event);
    ledger.observeThread(1, .waiting, 0x1000, 100);
    ledger.refresh(1000);
    try std.testing.expectEqual(Finding.window_too_short, ledger.worst().finding);
    try std.testing.expect(!ledger.worst().finding.deadlocked());
    try std.testing.expect(std.mem.indexOf(u8, Finding.window_too_short.meaning(), "not a finding") != null);
}

// The case the observed run hit: a waiter parked four billion steps on an
// object nothing has ever raised.
test "a waiter on an object nobody ever signalled is a deadlock with no cycle" {
    var ledger = Ledger{};
    ledger.observeObject(0x15cd8140, .condvar);
    ledger.observeThread(0x7fff2090, .waiting, 0x15cd8140, 0);
    ledger.refresh(long_park);

    const worst = ledger.worst();
    try std.testing.expectEqual(Finding.never_notified, worst.finding);
    try std.testing.expect(worst.finding.deadlocked());
    try std.testing.expectEqual(@as(u64, 0x15cd8140), worst.object.?.address);
    try std.testing.expect(std.mem.indexOf(u8, worst.finding.meaning(), "has not been reached") != null);
}

test "a blocker report retains the wait boundary and waiter identity" {
    var ledger = Ledger{};
    ledger.observeObject(0x14ce9fd0, .condvar);
    ledger.observeThreadContext(.{
        .handle = 0x7fff2090,
        .state = .waiting,
        .waiting_on = 0x14ce9fd0,
        .blocked_since_step = 65_112_171,
        .blocked_rip = 0x1d3a60,
        .start_routine = 0x1d3a60,
        .waiting_mutex = 0x14ce9f90,
        .wait_generation = 0,
        .notified_generation = 0,
        .blocked_reason = "pthread_cond_wait",
    });
    ledger.refresh(65_112_171 + long_park);

    var waiters: [max_threads]Thread = undefined;
    const matching = ledger.waitersFor(0x14ce9fd0, &waiters);
    try std.testing.expectEqual(@as(usize, 1), matching.len);
    try std.testing.expectEqual(@as(u64, 0x7fff2090), matching[0].handle);
    try std.testing.expectEqual(@as(u64, 0x1d3a60), matching[0].blocked_rip);
    try std.testing.expectEqual(@as(u64, 0x14ce9f90), matching[0].waiting_mutex);
    try std.testing.expectEqualStrings("pthread_cond_wait", matching[0].blocked_reason);
    try std.testing.expectEqual(Finding.never_notified, ledger.worst().finding);
}

test "a producer that exited leaves its consumers parked forever" {
    var ledger = Ledger{};
    ledger.observeNotify(0x2000, .semaphore, 0xAA, 10);
    ledger.observeThread(0xAA, .terminated, 0, 0);
    ledger.observeThread(0xBB, .waiting, 0x2000, 0);
    ledger.refresh(long_park);

    try std.testing.expectEqual(Finding.notifiers_terminated, ledger.worst().finding);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "producer exited") != null);
}

// No cycle exists and the graph still cannot progress: every thread that could
// signal is itself parked.
test "a graph with no live root is a deadlock even without a cycle" {
    var ledger = Ledger{};
    ledger.observeNotify(0x3000, .event, 0xAA, 10);
    // The notifier is parked on something else entirely.
    ledger.observeThread(0xAA, .waiting, 0x4000, 0);
    ledger.observeObject(0x4000, .event);
    ledger.observeThread(0xBB, .waiting, 0x3000, 0);
    ledger.refresh(long_park);

    // Classified per object: this graph deliberately holds two different
    // problems, and `worst` would report the more severe one.
    var parked_root: ?Object = null;
    for (ledger.objects[0..ledger.object_count]) |object| {
        if (object.address == 0x3000) parked_root = object;
    }
    try std.testing.expectEqual(Finding.all_notifiers_parked, ledger.classify(parked_root.?));
    try std.testing.expect(std.mem.indexOf(u8, Finding.all_notifiers_parked.meaning(), "no live root") != null);
}

test "a live notifier means the handshake is working however long the wait" {
    var ledger = Ledger{};
    ledger.observeNotify(0x5000, .event, 0xAA, 10);
    ledger.observeThread(0xAA, .running, 0, 0);
    ledger.observeThread(0xBB, .waiting, 0x5000, 0);
    ledger.refresh(long_park);
    try std.testing.expectEqual(Finding.healthy, ledger.worst().finding);
    try std.testing.expect(!ledger.worst().finding.deadlocked());
}

test "a true cycle is found and reported as its own finding" {
    var ledger = Ledger{};
    // A waits on X, which only B signals; B waits on Y, which only A signals.
    ledger.observeNotify(0x1000, .event, 0xBB, 1);
    ledger.observeNotify(0x2000, .event, 0xAA, 1);
    ledger.observeThread(0xAA, .waiting, 0x1000, 0);
    ledger.observeThread(0xBB, .waiting, 0x2000, 0);
    ledger.refresh(long_park);

    try std.testing.expectEqual(Finding.all_notifiers_parked, ledger.worst().finding);
    var chain: [8]u64 = undefined;
    const cycle = ledger.findCycle(0xAA, &chain).?;
    try std.testing.expect(cycle.len >= 3);
    try std.testing.expectEqual(@as(u64, 0xAA), cycle[0]);
    try std.testing.expectEqual(@as(u64, 0xBB), cycle[1]);
    try std.testing.expectEqual(@as(u64, 0xAA), cycle[cycle.len - 1]);
}

// The observed run's shape: a worker pool at idle. Every member has signalled
// the pool condvar at some point and is now parked on it, and a member is still
// running. Walking "first parked notifier" would invent a cycle out of the pool
// handshake; a live notifier means the wait can still be released.
test "a worker pool at idle with a live member is not a cycle" {
    var ledger = Ledger{};
    // Pool condvar: members have signalled it; one member is still running.
    ledger.observeNotify(0x19ad668, .condvar, 0x7fff2110, 1);
    ledger.observeNotify(0x19ad668, .condvar, 0x7fff2040, 2);
    ledger.observeNotify(0x19ad668, .condvar, 0x7fff2080, 3);
    ledger.observeThread(0x7fff2020, .waiting, 0x19ad668, 0);
    ledger.observeThread(0x7fff2110, .waiting, 0x19ad668, 0);
    ledger.observeThread(0x7fff2040, .waiting, 0x19ad668, 0);
    ledger.observeThread(0x7fff2080, .running, 0, 0);
    ledger.refresh(long_park);

    var chain: [8]u64 = undefined;
    try std.testing.expect(ledger.findCycle(0x7fff2020, &chain) == null);
    // The pool handshake is healthy, not a deadlock.
    try std.testing.expectEqual(Finding.healthy, ledger.classify(ledger.objects[0]));
}

// A thread that signalled the object it now waits on must not be reported as
// "the next thread in the chain": that would produce a cycle whose entries
// repeat ([A, B, B]), contradicting the finding's own description.
test "a thread waiting on an object it itself signalled is not a self-cycle" {
    var ledger = Ledger{};
    ledger.observeNotify(0x1000, .event, 0xBB, 1);
    ledger.observeThread(0xAA, .waiting, 0x1000, 0);
    // B signalled 0x1000 and is now parked on it — a self-edge.
    ledger.observeThread(0xBB, .waiting, 0x1000, 0);
    ledger.refresh(long_park);

    var chain: [8]u64 = undefined;
    try std.testing.expect(ledger.findCycle(0xAA, &chain) == null);
    // Classification still sees it: B is the only notifier and it is parked.
    try std.testing.expectEqual(Finding.all_notifiers_parked, ledger.classify(ledger.objects[0]));
}

// Two threads parked on the same object with no live releaser is a mutual
// wait, but the release set never narrowed: the detector walks one object and
// closes on the same threads, which is all-notifiers-parked, not a cycle.
test "a mutual wait on one object with no live releaser is not a cycle" {
    var ledger = Ledger{};
    ledger.observeNotify(0x2000, .condvar, 0xAA, 1);
    ledger.observeNotify(0x2000, .condvar, 0xBB, 1);
    ledger.observeThread(0xAA, .waiting, 0x2000, 0);
    ledger.observeThread(0xBB, .waiting, 0x2000, 0);
    ledger.refresh(long_park);

    var chain: [8]u64 = undefined;
    try std.testing.expect(ledger.findCycle(0xAA, &chain) == null);
    try std.testing.expectEqual(Finding.all_notifiers_parked, ledger.classify(ledger.objects[0]));
}

test "an acyclic wait chain is not reported as a cycle" {
    var ledger = Ledger{};
    ledger.observeNotify(0x1000, .event, 0xBB, 1);
    ledger.observeThread(0xAA, .waiting, 0x1000, 0);
    // B is parked on an object with no notifier at all, so the chain ends.
    ledger.observeObject(0x2000, .event);
    ledger.observeThread(0xBB, .waiting, 0x2000, 0);
    ledger.refresh(long_park);

    var chain: [8]u64 = undefined;
    try std.testing.expect(ledger.findCycle(0xAA, &chain) == null);
    // And the deeper problem is still found by classification.
    try std.testing.expectEqual(Finding.never_notified, ledger.worst().finding);
}

test "a running thread is never the start of a cycle" {
    var ledger = Ledger{};
    ledger.observeThread(0xAA, .running, 0, 0);
    var chain: [8]u64 = undefined;
    try std.testing.expect(ledger.findCycle(0xAA, &chain) == null);
}

// A notifier whose thread was never modelled might still be alive; concluding
// deadlock from an incomplete roster is the easiest false positive here.
test "an unmodelled notifier prevents a deadlock conclusion" {
    var ledger = Ledger{};
    ledger.observeNotify(0x6000, .semaphore, 0xCC, 10);
    ledger.observeThread(0xBB, .waiting, 0x6000, 0);
    ledger.refresh(long_park);
    try std.testing.expectEqual(Finding.healthy, ledger.worst().finding);
}

test "waiter counts are recomputed rather than accumulated" {
    var ledger = Ledger{};
    ledger.observeObject(0x7000, .event);
    ledger.observeThread(0xAA, .waiting, 0x7000, 0);
    ledger.refresh(long_park);
    try std.testing.expectEqual(@as(u32, 1), ledger.objects[0].waiters);

    // The thread wakes; the object must not still show a waiter.
    ledger.observeThread(0xAA, .running, 0, 0);
    ledger.refresh(long_park * 2);
    try std.testing.expectEqual(@as(u32, 0), ledger.objects[0].waiters);
    try std.testing.expectEqual(Finding.no_waiters, ledger.worst().finding);
    try std.testing.expectEqual(@as(u32, 0), ledger.parkedThreadCount());
}

test "repair attempts are recorded per object and survive refresh" {
    var ledger = Ledger{};
    ledger.observeObject(0x15cd8140, .condvar);
    ledger.observeThread(0xAA, .waiting, 0x15cd8140, 0);
    ledger.observeRepair(0x15cd8140, 1);
    ledger.refresh(long_park);

    const object = ledger.objects[0];
    try std.testing.expectEqual(@as(u32, 1), object.repair_attempts);
    // The finding stays never_notified — the repair does not manufacture a
    // notification — but the attempts are carried for the report.
    try std.testing.expectEqual(Finding.never_notified, ledger.classify(object));
}

test "objects and threads past capacity are counted rather than dropped" {
    var ledger = Ledger{};
    var index: u64 = 1;
    while (index <= max_objects) : (index += 1) ledger.observeObject(index * 0x1000, .event);
    ledger.observeObject(0xDEAD_0000, .event);
    try std.testing.expectEqual(@as(u64, 1), ledger.untracked_objects);

    index = 1;
    while (index <= max_threads) : (index += 1) ledger.observeThread(index, .running, 0, 0);
    ledger.observeThread(0xFFFF, .running, 0, 0);
    try std.testing.expectEqual(@as(u64, 1), ledger.untracked_threads);
}

test "every finding names a different owner and only some are deadlocks" {
    inline for (.{
        Finding.healthy,              Finding.no_waiters,
        Finding.window_too_short,     Finding.all_notifiers_parked,
        Finding.notifiers_terminated, Finding.never_notified,
        Finding.wait_cycle,
    }) |finding| {
        try std.testing.expect(finding.label().len > 0);
        try std.testing.expect(finding.meaning().len > 30);
    }
    try std.testing.expect(!Finding.healthy.deadlocked());
    try std.testing.expect(!Finding.window_too_short.deadlocked());
    try std.testing.expect(Finding.never_notified.deadlocked());
    try std.testing.expect(Finding.wait_cycle.deadlocked());
    try std.testing.expect(!Finding.never_notified.provenDeadlock());
    try std.testing.expect(Finding.all_notifiers_parked.provenDeadlock());
    try std.testing.expect(Finding.notifiers_terminated.provenDeadlock());
    try std.testing.expect(Finding.wait_cycle.provenDeadlock());

    inline for (.{
        ObjectKind.event,   ObjectKind.semaphore,        ObjectKind.mutex,
        ObjectKind.condvar, ObjectKind.critical_section, ObjectKind.thread_join,
    }) |kind| try std.testing.expect(kind.label().len > 0);
}

test "an empty ledger concludes nothing rather than reporting health" {
    const ledger = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "no thread state has been observed") != null);
}
