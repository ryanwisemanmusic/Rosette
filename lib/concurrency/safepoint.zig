//! A stop-the-world gate whose common path touches only the calling
//! thread's own cache line.
//!
//! Guest executors take a step lease around each guest step. Rare runtime
//! operations - remapping or protecting guest memory, switching execution
//! modes - take a mutation, which waits until every other executor is
//! between steps and keeps them there until it ends.
//!
//! The gate this replaces kept one shared word: every step did a
//! compare-and-swap on it to enter and a fetch-and-subtract to leave, plus
//! three linear scans of a thread-local table. With four host threads that
//! word bounced between cores on every guest instruction. Here each executor
//! owns a record on its own cache line, and a step writes only that record
//! and reads one read-mostly flag:
//!
//!   executor:  inside := 1 (seq_cst); if stopping (seq_cst) back out and wait
//!   stopper:   stopping := 1 (seq_cst); wait until every inside == 0
//!
//! Sequentially consistent on both sides, the store-then-load pairs cannot
//! both miss each other (Dekker), so a stopper never proceeds while an
//! executor that saw no stop is inside.
//!
//! A thread that must block in the middle of a step - waiting for the
//! runtime mutex, a guest wait object, a message - enters a *safe region*:
//! it counts as outside for its duration, so a stop never waits for a
//! sleeper. The rule that comes with it: no guest memory is touched inside a
//! safe region, and no host pointer into guest memory obtained before it is
//! used after it.
//!
//! Lock order: a thread that needs both the Windows runtime mutex and a
//! mutation takes the runtime mutex first. A stopper therefore never waits
//! on an executor that is waiting for a lock the stopper holds.

const std = @import("std");
const futex = @import("futex.zig");
const park = @import("park.zig");
const mutex_module = @import("mutex.zig");
const Mutex = mutex_module.Mutex;
const currentThreadId = mutex_module.currentThreadId;

pub const max_executors = 256;

pub const Executor = struct {
    /// 1 while the owning thread is inside a step and not in a safe region.
    /// Written only by the owner; read by stoppers.
    inside: futex.Word align(128) = futex.Word.init(0),
    taken: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Owner-private nesting counts.
    depth: u32 = 0,
    safe_depth: u32 = 0,
    mutation_depth: u32 = 0,
    /// Bumped by the owner on each outermost step, so a report can tell a
    /// running executor from a stuck one.
    steps: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
};

pub const Stats = struct {
    stops: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    quiesce_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    longest_quiesce_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    hold_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    longest_hold_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Executors that met a stop at a step boundary and waited for it.
    resume_waits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    safe_regions: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
};

pub const Snapshot = struct {
    stops: u64,
    quiesce_ns: u64,
    longest_quiesce_ns: u64,
    hold_ns: u64,
    longest_hold_ns: u64,
    resume_waits: u64,
    safe_regions: u64,
    executors: u32,
    inside_now: u32,
    stopping: bool,
    holder: u64,
    held_for_ns: u64,
    waiting_for: u64,
};

var next_gate_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

const TlsEntry = struct {
    gate: usize = 0,
    gate_id: u64 = 0,
    executor: ?*Executor = null,
    last_use: u64 = 0,
};
const tls_capacity = 32;
threadlocal var tls_entries: [tls_capacity]TlsEntry = [_]TlsEntry{.{}} ** tls_capacity;
threadlocal var tls_recent: TlsEntry = .{};
threadlocal var tls_clock: u64 = 0;

pub const Gate = struct {
    /// Nonzero while a mutation is being taken or held.
    stopping: futex.Word align(128) = futex.Word.init(0),
    resume_epoch: futex.Word align(128) = futex.Word.init(0),
    resume_waiters: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    high_water: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stopper: Mutex = Mutex.init("gate stopper"),
    /// Diagnostics: the mutation holder, since when, and which executor's
    /// thread a stopper is currently waiting for.
    holder: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    held_since_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    waiting_for: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stats: Stats = .{},
    executors: [max_executors]Executor = [_]Executor{.{}} ** max_executors,

    pub const StepGuard = struct {
        gate: *Gate,
        executor: *Executor,
        active: bool = true,

        pub fn unlock(self: *StepGuard) void {
            if (!self.active) return;
            self.active = false;
            self.gate.leaveStep(self.executor);
        }
    };

    pub const MutationGuard = struct {
        gate: *Gate,
        executor: *Executor,
        reentrant: bool,
        active: bool = true,
        started_ns: u64 = 0,

        pub fn unlock(self: *MutationGuard) void {
            if (!self.active) return;
            self.active = false;
            const me = self.executor;
            std.debug.assert(me.mutation_depth != 0);
            me.mutation_depth -= 1;
            if (self.reentrant) return;
            self.gate.resumeAll(self.started_ns);
        }
    };

    pub const SafeRegion = struct {
        gate: *Gate,
        executor: *Executor,
        active: bool = true,

        pub fn leave(self: *SafeRegion) void {
            if (!self.active) return;
            self.active = false;
            const me = self.executor;
            std.debug.assert(me.safe_depth != 0);
            me.safe_depth -= 1;
            if (me.safe_depth == 0 and me.depth != 0) self.gate.becomeInside(me);
        }
    };

    // -- executors ----------------------------------------------------------

    fn gateId(self: *Gate) u64 {
        const current = self.id.load(.acquire);
        if (current != 0) return current;
        const fresh = next_gate_id.fetchAdd(1, .monotonic);
        return self.id.cmpxchgStrong(0, fresh, .acq_rel, .acquire) orelse fresh;
    }

    fn owns(self: *const Gate, executor: *const Executor) bool {
        const address = @intFromPtr(executor);
        const first = @intFromPtr(&self.executors[0]);
        return address >= first and address < first + @sizeOf(@TypeOf(self.executors));
    }

    fn lookupExecutor(self: *Gate) ?*Executor {
        const key = @intFromPtr(self);
        const id = self.gateId();
        if (tls_recent.gate == key and tls_recent.gate_id == id) {
            if (tls_recent.executor) |executor| return executor;
        }
        for (&tls_entries) |*entry| {
            if (entry.gate != key or entry.gate_id != id) continue;
            const executor = entry.executor orelse continue;
            tls_clock +%= 1;
            entry.last_use = tls_clock;
            tls_recent = entry.*;
            return executor;
        }
        return null;
    }

    /// The calling thread's executor record, registering it on first use.
    pub fn registerCurrentThread(self: *Gate) *Executor {
        if (self.lookupExecutor()) |executor| return executor;
        const thread_id = currentThreadId();
        for (&self.executors, 0..) |*executor, index| {
            if (executor.taken.cmpxchgStrong(0, 1, .acq_rel, .monotonic) != null) continue;
            executor.depth = 0;
            executor.safe_depth = 0;
            executor.mutation_depth = 0;
            executor.inside.store(0, .seq_cst);
            executor.thread_id.store(thread_id, .release);
            _ = self.high_water.fetchMax(@intCast(index + 1), .acq_rel);
            self.remember(executor);
            return executor;
        }
        @panic("guest execution gate: more host threads registered than the gate has executor records");
    }

    /// Give the calling thread's record back. A worker host thread calls
    /// this as it exits so a long run does not exhaust the records.
    pub fn unregisterCurrentThread(self: *Gate) void {
        const executor = self.lookupExecutor() orelse return;
        std.debug.assert(executor.depth == 0 and executor.mutation_depth == 0);
        executor.inside.store(0, .seq_cst);
        executor.thread_id.store(0, .release);
        executor.taken.store(0, .release);
        const key = @intFromPtr(self);
        for (&tls_entries) |*entry| {
            if (entry.gate == key) entry.* = .{};
        }
        if (tls_recent.gate == key) tls_recent = .{};
    }

    fn remember(self: *Gate, executor: *Executor) void {
        const key = @intFromPtr(self);
        const id = self.gateId();
        // Never read another gate's memory here: it may have been freed.
        // Evict the least recently used association instead.
        var chosen: *TlsEntry = &tls_entries[0];
        for (&tls_entries) |*entry| {
            if (entry.executor == null) {
                chosen = entry;
                break;
            }
            if (entry.last_use < chosen.last_use) chosen = entry;
        }
        tls_clock +%= 1;
        chosen.* = .{ .gate = key, .gate_id = id, .executor = executor, .last_use = tls_clock };
        tls_recent = chosen.*;
    }

    // -- steps --------------------------------------------------------------

    pub fn enterStep(self: *Gate) StepGuard {
        const me = self.lookupExecutor() orelse self.registerCurrentThread();
        me.depth += 1;
        if (me.depth == 1) {
            me.steps.store(me.steps.load(.monotonic) +% 1, .monotonic);
            if (me.safe_depth == 0) self.becomeInside(me);
        }
        return .{ .gate = self, .executor = me };
    }

    fn leaveStep(self: *Gate, me: *Executor) void {
        std.debug.assert(me.depth != 0);
        me.depth -= 1;
        if (me.depth == 0 and me.safe_depth == 0) self.becomeOutside(me);
    }

    fn becomeInside(self: *Gate, me: *Executor) void {
        while (true) {
            me.inside.store(1, .seq_cst);
            if (self.stopping.load(.seq_cst) == 0 or me.mutation_depth != 0) return;
            // Another thread is stopping the world: stay out until it ends.
            me.inside.store(0, .seq_cst);
            futex.wake(&me.inside, .all);
            self.waitForResume();
        }
    }

    fn becomeOutside(self: *Gate, me: *Executor) void {
        me.inside.store(0, .seq_cst);
        if (self.stopping.load(.seq_cst) != 0) futex.wake(&me.inside, .all);
    }

    fn waitForResume(self: *Gate) void {
        _ = self.stats.resume_waits.fetchAdd(1, .monotonic);
        _ = self.resume_waiters.fetchAdd(1, .seq_cst);
        defer _ = self.resume_waiters.fetchSub(1, .monotonic);
        while (self.stopping.load(.seq_cst) != 0) {
            const epoch = self.resume_epoch.load(.seq_cst);
            if (self.stopping.load(.seq_cst) == 0) break;
            park.park(&self.resume_epoch, epoch, null, "gate: waiting for a stop-the-world to end");
        }
    }

    // -- safe regions -------------------------------------------------------

    /// Count as outside guest execution until `leave`: for a thread about to
    /// block in the middle of a step. See the file comment for the rule.
    pub fn enterSafeRegion(self: *Gate) SafeRegion {
        const me = self.lookupExecutor() orelse self.registerCurrentThread();
        me.safe_depth += 1;
        if (me.safe_depth == 1 and me.depth != 0) {
            _ = self.stats.safe_regions.fetchAdd(1, .monotonic);
            self.becomeOutside(me);
        }
        return .{ .gate = self, .executor = me };
    }

    // -- mutations ----------------------------------------------------------

    pub fn enterMutation(self: *Gate) MutationGuard {
        const me = self.lookupExecutor() orelse self.registerCurrentThread();
        if (me.mutation_depth != 0) {
            me.mutation_depth += 1;
            return .{ .gate = self, .executor = me, .reentrant = true };
        }
        const started = futex.monotonicNanoseconds();
        // Another stopper may be waiting for this thread's own step to end
        // while this thread waits for it: be outside meanwhile.
        const was_inside = me.inside.load(.monotonic) != 0;
        if (was_inside) self.becomeOutside(me);
        self.stopper.lock();
        self.stopping.store(1, .seq_cst);
        me.mutation_depth = 1;
        self.waitForExecutorsOutside(me);
        if (was_inside) me.inside.store(1, .seq_cst);
        const quiesced = futex.monotonicNanoseconds();
        const quiesce = quiesced -| started;
        _ = self.stats.stops.fetchAdd(1, .monotonic);
        _ = self.stats.quiesce_ns.fetchAdd(quiesce, .monotonic);
        _ = self.stats.longest_quiesce_ns.fetchMax(quiesce, .monotonic);
        self.holder.store(currentThreadId(), .release);
        self.held_since_ns.store(quiesced, .release);
        return .{ .gate = self, .executor = me, .reentrant = false, .started_ns = quiesced };
    }

    fn waitForExecutorsOutside(self: *Gate, me: *Executor) void {
        // An executor registered after this read sees `stopping` when it
        // first steps in, so it needs no wait.
        const count = self.high_water.load(.acquire);
        for (self.executors[0..count]) |*executor| {
            if (executor == me) continue;
            var backoff: park.Backoff = .{};
            while (executor.inside.load(.seq_cst) != 0) {
                if (backoff.spin()) continue;
                self.waiting_for.store(executor.thread_id.load(.monotonic), .monotonic);
                park.park(&executor.inside, 1, null, "gate: stopping the world, waiting for an executor to finish its step");
            }
        }
        self.waiting_for.store(0, .monotonic);
    }

    fn resumeAll(self: *Gate, started_ns: u64) void {
        const held = futex.monotonicNanoseconds() -| started_ns;
        _ = self.stats.hold_ns.fetchAdd(held, .monotonic);
        _ = self.stats.longest_hold_ns.fetchMax(held, .monotonic);
        self.holder.store(0, .release);
        self.stopping.store(0, .seq_cst);
        _ = self.resume_epoch.fetchAdd(1, .seq_cst);
        if (self.resume_waiters.load(.seq_cst) != 0) futex.wake(&self.resume_epoch, .all);
        self.stopper.unlock();
    }

    // -- queries ------------------------------------------------------------

    /// Executors inside a step right now (diagnostic).
    pub fn activeSteps(self: *const Gate) usize {
        var count: usize = 0;
        for (self.executors[0..self.high_water.load(.acquire)]) |*executor| {
            if (executor.inside.load(.acquire) != 0) count += 1;
        }
        return count;
    }

    pub fn mutationPending(self: *const Gate) bool {
        return self.stopping.load(.acquire) != 0;
    }

    /// The calling thread's step nesting, zero when it has none (does not
    /// register the thread).
    pub fn currentStepDepth(self: *Gate) usize {
        const executor = self.lookupExecutor() orelse return 0;
        return executor.depth;
    }

    pub fn holdsMutation(self: *Gate) bool {
        const executor = self.lookupExecutor() orelse return false;
        return executor.mutation_depth != 0;
    }

    pub fn snapshot(self: *const Gate) Snapshot {
        var executors: u32 = 0;
        var inside_now: u32 = 0;
        for (self.executors[0..self.high_water.load(.acquire)]) |*executor| {
            if (executor.taken.load(.acquire) == 0) continue;
            executors += 1;
            if (executor.inside.load(.acquire) != 0) inside_now += 1;
        }
        const since = self.held_since_ns.load(.acquire);
        const holder = self.holder.load(.acquire);
        return .{
            .stops = self.stats.stops.load(.monotonic),
            .quiesce_ns = self.stats.quiesce_ns.load(.monotonic),
            .longest_quiesce_ns = self.stats.longest_quiesce_ns.load(.monotonic),
            .hold_ns = self.stats.hold_ns.load(.monotonic),
            .longest_hold_ns = self.stats.longest_hold_ns.load(.monotonic),
            .resume_waits = self.stats.resume_waits.load(.monotonic),
            .safe_regions = self.stats.safe_regions.load(.monotonic),
            .executors = executors,
            .inside_now = inside_now,
            .stopping = self.stopping.load(.acquire) != 0,
            .holder = holder,
            .held_for_ns = if (holder != 0 and since != 0) futex.monotonicNanoseconds() -| since else 0,
            .waiting_for = self.waiting_for.load(.acquire),
        };
    }
};

test "uncontended steps overlap and leave the gate idle" {
    const Shared = struct {
        gate: *Gate,
        ready: *std.atomic.Value(u32),
        release: *std.atomic.Value(bool),

        fn run(context: @This()) void {
            var step = context.gate.enterStep();
            defer step.unlock();
            _ = context.ready.fetchAdd(1, .release);
            while (!context.release.load(.acquire)) std.atomic.spinLoopHint();
        }
    };
    var gate: Gate = .{};
    var ready = std.atomic.Value(u32).init(0);
    var release = std.atomic.Value(bool).init(false);
    const first = try std.Thread.spawn(.{}, Shared.run, .{Shared{ .gate = &gate, .ready = &ready, .release = &release }});
    const second = try std.Thread.spawn(.{}, Shared.run, .{Shared{ .gate = &gate, .ready = &ready, .release = &release }});
    while (ready.load(.acquire) != 2) std.atomic.spinLoopHint();
    try std.testing.expectEqual(@as(usize, 2), gate.activeSteps());
    release.store(true, .release);
    first.join();
    second.join();
    try std.testing.expectEqual(@as(usize, 0), gate.activeSteps());
    try std.testing.expect(!gate.mutationPending());
}

test "a mutation waits for a live step and holds new steps out" {
    const Shared = struct {
        gate: *Gate,
        reader_ready: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        release_reader: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutation_entered: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        release_mutation: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        newcomer_attempting: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        newcomer_entered: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn reader(context: *@This()) void {
            var step = context.gate.enterStep();
            defer step.unlock();
            context.reader_ready.store(true, .release);
            while (!context.release_reader.load(.acquire)) std.atomic.spinLoopHint();
        }

        fn mutator(context: *@This()) void {
            var mutation = context.gate.enterMutation();
            defer mutation.unlock();
            context.mutation_entered.store(true, .release);
            while (!context.release_mutation.load(.acquire)) std.atomic.spinLoopHint();
        }

        fn newcomer(context: *@This()) void {
            context.newcomer_attempting.store(true, .release);
            var step = context.gate.enterStep();
            defer step.unlock();
            context.newcomer_entered.store(true, .release);
        }
    };
    var gate: Gate = .{};
    var shared = Shared{ .gate = &gate };
    const reader = try std.Thread.spawn(.{}, Shared.reader, .{&shared});
    while (!shared.reader_ready.load(.acquire)) std.atomic.spinLoopHint();
    const mutator = try std.Thread.spawn(.{}, Shared.mutator, .{&shared});
    while (!gate.mutationPending()) std.atomic.spinLoopHint();
    const newcomer = try std.Thread.spawn(.{}, Shared.newcomer, .{&shared});
    while (!shared.newcomer_attempting.load(.acquire)) std.atomic.spinLoopHint();
    var pause = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&pause, null);
    try std.testing.expect(!shared.mutation_entered.load(.acquire));
    try std.testing.expect(!shared.newcomer_entered.load(.acquire));

    shared.release_reader.store(true, .release);
    while (!shared.mutation_entered.load(.acquire)) std.atomic.spinLoopHint();
    _ = std.c.nanosleep(&pause, null);
    try std.testing.expect(!shared.newcomer_entered.load(.acquire));
    shared.release_mutation.store(true, .release);

    reader.join();
    mutator.join();
    newcomer.join();
    try std.testing.expect(shared.newcomer_entered.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), gate.activeSteps());
    try std.testing.expect(!gate.mutationPending());
    try std.testing.expectEqual(@as(u64, 1), gate.snapshot().stops);
}

test "two stepping threads that both mutate do not deadlock" {
    const Worker = struct {
        gate: *Gate,
        ready: *std.atomic.Value(u32),
        completed: *std.atomic.Value(u32),

        fn mutate(self: *@This()) void {
            var step_guard = self.gate.enterStep();
            defer step_guard.unlock();
            _ = self.ready.fetchAdd(1, .seq_cst);
            while (self.ready.load(.seq_cst) != 2) std.atomic.spinLoopHint();
            var mutation_guard = self.gate.enterMutation();
            defer mutation_guard.unlock();
            _ = self.completed.fetchAdd(1, .seq_cst);
        }
    };
    var gate: Gate = .{};
    var ready = std.atomic.Value(u32).init(0);
    var completed = std.atomic.Value(u32).init(0);
    var first = Worker{ .gate = &gate, .ready = &ready, .completed = &completed };
    var second = Worker{ .gate = &gate, .ready = &ready, .completed = &completed };
    const first_thread = try std.Thread.spawn(.{}, Worker.mutate, .{&first});
    const second_thread = try std.Thread.spawn(.{}, Worker.mutate, .{&second});
    first_thread.join();
    second_thread.join();
    try std.testing.expectEqual(@as(u32, 2), completed.load(.seq_cst));
    try std.testing.expect(!gate.mutationPending());
    try std.testing.expectEqual(@as(usize, 0), gate.activeSteps());
}

test "a mutation is reentrant and permits the holder's own nested steps" {
    var gate: Gate = .{};
    var outer = gate.enterMutation();
    var nested = gate.enterMutation();
    var step = gate.enterStep();
    try std.testing.expect(gate.holdsMutation());
    step.unlock();
    nested.unlock();
    outer.unlock();
    try std.testing.expect(!gate.mutationPending());
    try std.testing.expect(!gate.holdsMutation());
    try std.testing.expectEqual(@as(usize, 0), gate.activeSteps());
}

test "a thread in a safe region does not hold up a stop" {
    const Shared = struct {
        gate: *Gate,
        in_region: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        release: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        stepped_again: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn sleeper(context: *@This()) void {
            var step = context.gate.enterStep();
            defer step.unlock();
            var region = context.gate.enterSafeRegion();
            context.in_region.store(true, .release);
            while (!context.release.load(.acquire)) std.atomic.spinLoopHint();
            // Leaving the region with a stop in progress waits for it.
            region.leave();
            context.stepped_again.store(true, .release);
        }
    };
    var gate: Gate = .{};
    var shared = Shared{ .gate = &gate };
    const thread = try std.Thread.spawn(.{}, Shared.sleeper, .{&shared});
    while (!shared.in_region.load(.acquire)) std.atomic.spinLoopHint();
    // The sleeper is mid-step but in a safe region: the stop completes.
    var mutation = gate.enterMutation();
    shared.release.store(true, .release);
    var pause = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&pause, null);
    try std.testing.expect(!shared.stepped_again.load(.acquire));
    mutation.unlock();
    thread.join();
    try std.testing.expect(shared.stepped_again.load(.acquire));
}

test "gates in one thread keep separate executors and nest" {
    var outer_gate: Gate = .{};
    var nested_gate: Gate = .{};
    var outer_step = outer_gate.enterStep();
    var nested_step = nested_gate.enterStep();
    var outer_mutation = outer_gate.enterMutation();
    var nested_mutation = nested_gate.enterMutation();
    var outer_again = outer_gate.enterMutation();
    try std.testing.expectEqual(@as(usize, 1), outer_gate.currentStepDepth());
    outer_again.unlock();
    nested_mutation.unlock();
    outer_mutation.unlock();
    nested_step.unlock();
    outer_step.unlock();
    try std.testing.expect(!outer_gate.mutationPending());
    try std.testing.expect(!nested_gate.mutationPending());
    try std.testing.expectEqual(@as(usize, 0), outer_gate.activeSteps());
    try std.testing.expectEqual(@as(usize, 0), nested_gate.activeSteps());
}

test "an executor record is returned when its thread leaves" {
    var gate: Gate = .{};
    const Worker = struct {
        fn run(target: *Gate) void {
            var step = target.enterStep();
            step.unlock();
            target.unregisterCurrentThread();
        }
    };
    for (0..max_executors + 8) |_| {
        const thread = try std.Thread.spawn(.{}, Worker.run, .{&gate});
        thread.join();
    }
    // Every thread gave its record back, so the table never filled.
    try std.testing.expectEqual(@as(u32, 0), gate.snapshot().executors);
}

test "many threads stepping while one mutates repeatedly all finish" {
    const Shared = struct {
        gate: Gate = .{},
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        /// Written only under a mutation, read by steps: a step that ran
        /// during a mutation would see an odd value.
        guarded: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        torn: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

        fn stepper(shared: *@This()) void {
            while (!shared.stop.load(.acquire)) {
                var step = shared.gate.enterStep();
                if (shared.guarded.load(.acquire) % 2 != 0) _ = shared.torn.fetchAdd(1, .monotonic);
                step.unlock();
            }
            shared.gate.unregisterCurrentThread();
        }

        fn mutator(shared: *@This()) void {
            for (0..300) |_| {
                var mutation = shared.gate.enterMutation();
                _ = shared.guarded.fetchAdd(1, .acq_rel);
                std.atomic.spinLoopHint();
                _ = shared.guarded.fetchAdd(1, .acq_rel);
                mutation.unlock();
            }
            shared.stop.store(true, .release);
        }
    };
    const shared = try std.testing.allocator.create(Shared);
    defer std.testing.allocator.destroy(shared);
    shared.* = .{};
    var steppers: [4]std.Thread = undefined;
    for (&steppers) |*thread| thread.* = try std.Thread.spawn(.{}, Shared.stepper, .{shared});
    const mutator = try std.Thread.spawn(.{}, Shared.mutator, .{shared});
    mutator.join();
    for (steppers) |thread| thread.join();
    try std.testing.expectEqual(@as(u32, 0), shared.torn.load(.acquire));
    try std.testing.expectEqual(@as(u64, 300), shared.gate.snapshot().stops);
}
