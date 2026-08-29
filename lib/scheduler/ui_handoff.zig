const std = @import("std");

pub const Phase = enum {
    idle,
    queued,
    callback_running,
    callback_suspended,
    worker_running,
    completed,
};

pub const Health = enum {
    idle,
    progressing,
    queued_stalled,
    callback_stalled,
    worker_stalled,
    completed,
    completion_stalled,
};

pub const CallbackQuantumAction = enum {
    retain,
    rendezvous_worker,
};

/// Describes what a UI callback owes its scheduling thread when it returns.
/// GTK idle sources are asynchronous event-loop work by default: the caller
/// queues them and keeps going. A synchronous framework handoff is a
/// different contract and must be selected explicitly so its caller can be
/// resumed before another callback crosses the boundary.
pub const CompletionMode = enum {
    rendezvous,
    detached,
};

pub const SchedulingOwner = struct {
    thread: u64,
    rip: u64,
};

/// Tracks one UI-thread handoff across cooperative guest-thread switches.
/// Host thread identity is insufficient because Rosette executes multiple
/// guest pthread contexts on one host interpreter thread.
pub const UiHandoffTracker = struct {
    phase: Phase = .idle,
    generation: u64 = 0,
    source_id: u64 = 0,
    callback: u64 = 0,
    callback_handle: u64 = 0,
    scheduling_thread: u64 = 0,
    scheduling_rip: u64 = 0,
    worker_handle: u64 = 0,
    queued_step: u64 = 0,
    callback_started_step: u64 = 0,
    last_progress_step: u64 = 0,
    completed_step: u64 = 0,
    callback_suspensions: u64 = 0,
    callback_resumptions: u64 = 0,
    worker_slices: u64 = 0,
    diagnostic_count: u64 = 0,
    last_diagnostic_step: u64 = 0,
    worker_rip: u64 = 0,
    /// `rendezvous` preserves the scheduling-thread completion dependency.
    /// `detached` records callback completion without making an unrelated
    /// parked guest thread a prerequisite for dispatching later idle work.
    completion_mode: CompletionMode = .rendezvous,
    callback_rip: u64 = 0,
    /// Scheduling thread of the most recently abandoned completion, remembered
    /// until that thread is seen running again. A thread that failed to collect
    /// one completion is not waiting for callbacks at all, so granting it the
    /// next completion's dependency would re-stall the queue on the same dead
    /// end once per callback for the rest of the run. Survives every reset for
    /// exactly that reason.
    abandoned_thread: u64 = 0,
    /// Completed callbacks by terminal ownership disposition. `total` is
    /// incremented exactly once in `completed`; every completed generation is
    /// then resumed, explicitly abandoned, detached, inherited from an
    /// already abandoned owner, ownerless, or still pending.
    completions_total: u64 = 0,
    completions_resumed: u64 = 0,
    completions_abandoned: u64 = 0,
    completions_inherited_abandonment: u64 = 0,
    completions_detached: u64 = 0,
    completions_ownerless: u64 = 0,

    pub fn queued(self: *UiHandoffTracker, source_id: u64, callback: u64, scheduling_thread: u64, scheduling_rip: u64, step: u64) void {
        self.queuedWithMode(source_id, callback, scheduling_thread, scheduling_rip, step, .rendezvous);
    }

    /// Queue a callback with an explicit completion contract. Keeping this
    /// separate from `queued` leaves the scheduler's low-level tests and
    /// synchronous callers strict by default while allowing the GTK adapter
    /// to model its documented fire-and-forget API accurately.
    pub fn queuedWithMode(
        self: *UiHandoffTracker,
        source_id: u64,
        callback: u64,
        scheduling_thread: u64,
        scheduling_rip: u64,
        step: u64,
        completion_mode: CompletionMode,
    ) void {
        const next_generation = self.generation +| 1;
        self.* = .{
            .phase = .queued,
            .generation = next_generation,
            .source_id = source_id,
            .callback = callback,
            .scheduling_thread = scheduling_thread,
            .scheduling_rip = scheduling_rip,
            .queued_step = step,
            .last_progress_step = step,
            .completion_mode = completion_mode,
            .abandoned_thread = self.abandoned_thread,
            .completions_total = self.completions_total,
            .completions_resumed = self.completions_resumed,
            .completions_abandoned = self.completions_abandoned,
            .completions_inherited_abandonment = self.completions_inherited_abandonment,
            .completions_detached = self.completions_detached,
            .completions_ownerless = self.completions_ownerless,
        };
    }

    /// Record a newly queued callback only when no handoff is already in
    /// flight. A second GTK idle source may be queued while the first callback
    /// is still executing; replacing the active generation here would make
    /// the scheduler lose ownership of the running callback and stop donating
    /// quanta to runnable workers.
    pub fn queueIfIdle(self: *UiHandoffTracker, source_id: u64, callback: u64, scheduling_thread: u64, scheduling_rip: u64, step: u64) bool {
        return self.queueIfIdleWithMode(source_id, callback, scheduling_thread, scheduling_rip, step, .rendezvous);
    }

    pub fn queueIfIdleWithMode(
        self: *UiHandoffTracker,
        source_id: u64,
        callback: u64,
        scheduling_thread: u64,
        scheduling_rip: u64,
        step: u64,
        completion_mode: CompletionMode,
    ) bool {
        if (!self.acceptsNewHandoff()) return false;
        self.queuedWithMode(source_id, callback, scheduling_thread, scheduling_rip, step, completion_mode);
        return true;
    }

    /// Start the generation belonging to the callback actually selected for
    /// dispatch. If it was queued behind another active callback, its queue
    /// metadata intentionally wasn't installed until this point.
    pub fn beginDispatch(
        self: *UiHandoffTracker,
        source_id: u64,
        callback: u64,
        scheduling_thread: u64,
        scheduling_rip: u64,
        queued_step: u64,
        callback_handle: u64,
        callback_rip: u64,
        step: u64,
    ) void {
        self.beginDispatchWithMode(
            source_id,
            callback,
            scheduling_thread,
            scheduling_rip,
            queued_step,
            callback_handle,
            callback_rip,
            step,
            .rendezvous,
        );
    }

    pub fn beginDispatchWithMode(
        self: *UiHandoffTracker,
        source_id: u64,
        callback: u64,
        scheduling_thread: u64,
        scheduling_rip: u64,
        queued_step: u64,
        callback_handle: u64,
        callback_rip: u64,
        step: u64,
        completion_mode: CompletionMode,
    ) void {
        if (self.phase != .queued or self.source_id != source_id or self.callback != callback) {
            self.queuedWithMode(source_id, callback, scheduling_thread, scheduling_rip, queued_step, completion_mode);
        }
        self.callbackStarted(callback_handle, callback_rip, step);
    }

    pub fn callbackStarted(self: *UiHandoffTracker, handle: u64, rip: u64, step: u64) void {
        if (self.phase != .queued) {
            if (self.diagnostic_count < 32 or (self.diagnostic_count & (self.diagnostic_count - 1) == 0)) {
                std.debug.print(
                    "scheduler: UI handoff unexpected callbackStarted: phase={s} expected=queued diagnostic={d}\n",
                    .{ @tagName(self.phase), self.diagnostic_count + 1 },
                );
            }
            self.diagnostic_count +|= 1;
            return;
        }
        self.phase = .callback_running;
        self.callback_handle = handle;
        self.callback_rip = rip;
        self.callback_started_step = step;
        self.last_progress_step = step;
    }

    pub fn callbackSuspended(self: *UiHandoffTracker, step: u64) void {
        if (self.phase != .callback_running) {
            if (self.diagnostic_count < 32 or (self.diagnostic_count & (self.diagnostic_count - 1) == 0)) {
                std.debug.print(
                    "scheduler: UI handoff unexpected callbackSuspended: phase={s} expected=callback_running diagnostic={d}\n",
                    .{ @tagName(self.phase), self.diagnostic_count + 1 },
                );
            }
            self.diagnostic_count +|= 1;
            return;
        }
        self.phase = .callback_suspended;
        self.callback_suspensions +|= 1;
        self.last_progress_step = step;
    }

    pub fn workerStarted(self: *UiHandoffTracker, handle: u64, rip: u64, step: u64) void {
        if (self.phase != .callback_suspended and self.phase != .worker_running) {
            if (self.diagnostic_count < 32 or (self.diagnostic_count & (self.diagnostic_count - 1) == 0)) {
                std.debug.print(
                    "scheduler: UI handoff unexpected workerStarted: phase={s} expected=callback_suspended or worker_running diagnostic={d}\n",
                    .{ @tagName(self.phase), self.diagnostic_count + 1 },
                );
            }
            self.diagnostic_count +|= 1;
            return;
        }
        self.phase = .worker_running;
        self.worker_handle = handle;
        self.worker_rip = rip;
        self.worker_slices +|= 1;
        self.last_progress_step = step;
    }

    pub fn callbackResumed(self: *UiHandoffTracker, rip: u64, step: u64) void {
        if (self.phase != .callback_suspended and self.phase != .worker_running) {
            if (self.diagnostic_count < 32 or (self.diagnostic_count & (self.diagnostic_count - 1) == 0)) {
                std.debug.print(
                    "scheduler: UI handoff unexpected callbackResumed: phase={s} expected=callback_suspended or worker_running diagnostic={d}\n",
                    .{ @tagName(self.phase), self.diagnostic_count + 1 },
                );
            }
            self.diagnostic_count +|= 1;
            return;
        }
        self.phase = .callback_running;
        self.callback_rip = rip;
        self.worker_handle = 0;
        self.callback_resumptions +|= 1;
        self.last_progress_step = step;
    }

    pub fn completed(self: *UiHandoffTracker, step: u64) void {
        if (!self.isActive()) return;
        self.phase = .completed;
        self.completions_total +|= 1;
        if (self.completion_mode == .detached) {
            self.completions_detached +|= 1;
        } else if (self.scheduling_thread == 0) {
            self.completions_ownerless +|= 1;
        } else if (self.scheduling_thread == self.abandoned_thread) {
            self.completions_inherited_abandonment +|= 1;
        }
        self.completed_step = step;
        self.last_progress_step = step;
        self.worker_handle = 0;
    }

    pub fn reset(self: *UiHandoffTracker) void {
        const dropped_pending = self.phase == .completed and self.hasCompletionDependency();
        self.* = .{
            .generation = self.generation,
            .abandoned_thread = self.abandoned_thread,
            .completions_total = self.completions_total,
            .completions_resumed = self.completions_resumed,
            .completions_abandoned = self.completions_abandoned,
            .completions_inherited_abandonment = self.completions_inherited_abandonment,
            .completions_detached = self.completions_detached,
            .completions_ownerless = self.completions_ownerless +| @intFromBool(dropped_pending),
        };
    }

    /// Record that `handle` is executing again. A thread that has resumed is
    /// once more a legitimate completion target, whatever happened to an
    /// earlier handoff it scheduled.
    pub fn noteThreadResumed(self: *UiHandoffTracker, handle: u64) void {
        if (handle != 0 and handle == self.abandoned_thread) self.abandoned_thread = 0;
    }

    /// Whether the tracker may adopt a newly queued source as its generation.
    ///
    /// `.completed` is normally not idle: the callback is gone, but ownership
    /// has not returned to the guest thread that scheduled it yet, and
    /// replacing the generation there would lose that dependency and let an
    /// unrelated callback run across the scheduling thread's atomic
    /// continuation. Once the dependency is gone — resolved or abandoned — the
    /// tracker owes nothing and a new handoff is free to take it over.
    fn acceptsNewHandoff(self: *const UiHandoffTracker) bool {
        return switch (self.phase) {
            .idle => true,
            .completed => !self.hasCompletionDependency(),
            .queued, .callback_running, .callback_suspended, .worker_running => false,
        };
    }

    pub fn isActive(self: *const UiHandoffTracker) bool {
        return switch (self.phase) {
            .queued, .callback_running, .callback_suspended, .worker_running => true,
            .idle, .completed => false,
        };
    }

    pub fn ownsCallbackHandle(self: *const UiHandoffTracker, handle: u64) bool {
        return self.callback_handle != 0 and self.callback_handle == handle;
    }

    /// A callback may queue more UI work while it is running. The synthetic
    /// callback handle cannot own that child handoff because it disappears at
    /// callback return. Carry forward the original guest owner instead, so a
    /// child callback can never leave completion affinity pointing at a dead
    /// synthetic context.
    pub fn schedulingOwner(self: *const UiHandoffTracker, current_thread: u64, current_rip: u64) SchedulingOwner {
        if (self.ownsCallbackHandle(current_thread)) {
            return .{ .thread = self.scheduling_thread, .rip = self.scheduling_rip };
        }
        return .{ .thread = current_thread, .rip = current_rip };
    }

    /// Update the last-progress timestamp without changing any other
    /// handoff state.  This lets a long-running callback (e.g. SHA-1
    /// memory initialisation) suppress false stall diagnostics while
    /// it makes genuine forward progress inside its guest code.
    pub fn registerProgress(self: *UiHandoffTracker, step: u64) void {
        if (!self.isActive()) return;
        self.last_progress_step = step;
    }

    /// Decide whether a running callback should donate one full quantum to a
    /// producer. This is based on scheduler eligibility, not callback symbols
    /// or application identity, so the same handoff rule applies to any guest.
    pub fn callbackQuantumAction(
        self: *const UiHandoffTracker,
        deferred_workers: u64,
        runnable_suspended: usize,
    ) CallbackQuantumAction {
        if (self.phase != .callback_running) return .retain;
        if (deferred_workers == 0 and runnable_suspended == 0) return .retain;
        return .rendezvous_worker;
    }

    /// At a scheduling boundary, return to the callback after its worker has
    /// consumed a complete slice instead of burying UI work in the FIFO queue.
    pub fn shouldPreferCallback(self: *const UiHandoffTracker, current_step: u64, worker_quantum: u64) bool {
        return self.phase == .worker_running and
            self.callback_handle != 0 and
            current_step -| self.last_progress_step >= worker_quantum;
    }

    /// Once the UI callback and any cleanup worker have returned, execution
    /// belongs to the guest thread that requested the handoff. Returning to a
    /// generic FIFO entry first can revive an unrelated context that has been
    /// frozen across the entire callback and violate its atomic invariants.
    pub fn completionResumeHandle(self: *const UiHandoffTracker) u64 {
        if (self.phase != .completed) return 0;
        if (self.completion_mode == .detached) return 0;
        if (self.scheduling_thread == self.abandoned_thread) return 0;
        return self.scheduling_thread;
    }

    pub fn hasCompletionDependency(self: *const UiHandoffTracker) bool {
        return self.completionResumeHandle() != 0;
    }

    pub fn completionResumed(self: *UiHandoffTracker, handle: u64, step: u64) bool {
        if (handle == 0 or handle != self.completionResumeHandle()) return false;
        self.* = .{
            .generation = self.generation,
            .last_progress_step = step,
            .abandoned_thread = self.abandoned_thread,
            .completions_total = self.completions_total,
            .completions_resumed = self.completions_resumed +| 1,
            .completions_abandoned = self.completions_abandoned,
            .completions_inherited_abandonment = self.completions_inherited_abandonment,
            .completions_detached = self.completions_detached,
            .completions_ownerless = self.completions_ownerless,
        };
        return true;
    }

    /// Abandon a completion dependency whose scheduling thread has stopped
    /// being able to satisfy it, and report the handle that was abandoned
    /// (0 when nothing was released).
    ///
    /// The dependency exists so that a synchronous handoff returns to its
    /// requester before another callback runs. That is only a liveness-safe
    /// rule while the requester is still waiting for *this* callback. A thread
    /// that used the deferred (fire-and-forget) form has no such wait: it can
    /// park on an unrelated long-lived object immediately after queueing, and
    /// then it never becomes resumable again. Holding every later callback
    /// behind it cannot help it — the queued callbacks are the only producers
    /// left — so the queue would stay pinned for the rest of the run.
    ///
    /// The bound is the same no-progress threshold the stall diagnostics use,
    /// which is many scheduler quanta: a requester that is genuinely waiting on
    /// the callback resumes long before this, so the ordering guarantee is
    /// unchanged for every handoff that can still be honoured. The abandoned
    /// thread is then remembered, so the wait is paid once rather than once per
    /// queued callback — see `abandoned_thread`.
    pub fn releaseStalledCompletion(self: *UiHandoffTracker, current_step: u64, stall_steps: u64) u64 {
        if (self.health(current_step, stall_steps) != .completion_stalled) return 0;
        const abandoned = self.scheduling_thread;
        self.* = .{
            .generation = self.generation,
            .last_progress_step = current_step,
            .abandoned_thread = abandoned,
            .completions_total = self.completions_total,
            .completions_resumed = self.completions_resumed,
            .completions_abandoned = self.completions_abandoned +| 1,
            .completions_inherited_abandonment = self.completions_inherited_abandonment,
            .completions_detached = self.completions_detached,
            .completions_ownerless = self.completions_ownerless,
        };
        return abandoned;
    }

    pub fn pendingCompletions(self: *const UiHandoffTracker) u64 {
        const terminal = self.completions_resumed +|
            self.completions_abandoned +|
            self.completions_inherited_abandonment +|
            self.completions_detached +|
            self.completions_ownerless;
        return self.completions_total -| terminal;
    }

    pub fn terminalInvariantHolds(self: *const UiHandoffTracker) bool {
        return self.completions_total == self.completions_resumed +|
            self.completions_abandoned +|
            self.completions_inherited_abandonment +|
            self.completions_detached +|
            self.completions_ownerless +|
            self.pendingCompletions();
    }

    pub fn health(self: *const UiHandoffTracker, current_step: u64, stall_steps: u64) Health {
        return switch (self.phase) {
            .idle => .idle,
            .completed => if (self.hasCompletionDependency() and current_step -| self.last_progress_step >= stall_steps) .completion_stalled else .completed,
            .queued => if (current_step -| self.last_progress_step >= stall_steps) .queued_stalled else .progressing,
            .callback_running, .callback_suspended => if (current_step -| self.last_progress_step >= stall_steps) .callback_stalled else .progressing,
            .worker_running => if (current_step -| self.last_progress_step >= stall_steps) .worker_stalled else .progressing,
        };
    }

    pub fn diagnose(self: *UiHandoffTracker, current_step: u64, stall_steps: u64, active_thread: u64, active_rip: u64, suspended_count: u64) void {
        const status = self.health(current_step, stall_steps);
        if (status == .idle or status == .progressing or status == .completed) return;
        if (current_step -| self.last_diagnostic_step < stall_steps) return;
        self.last_diagnostic_step = current_step;
        self.diagnostic_count +|= 1;
        std.debug.print(
            "scheduler: UI HANDOFF STALL: diagnostic={d} generation={d} health={s} phase={s} handoff={s} source={d} callback=0x{x} callback_handle=0x{x} callback_rip=0x{x} worker=0x{x} worker_rip=0x{x} active=0x{x} active_rip=0x{x} age={d} no_progress={d} queued_by=0x{x} queued_rip=0x{x} suspend/resume/worker_slices={d}/{d}/{d} suspended={d}\n",
            .{
                self.diagnostic_count,
                self.generation,
                @tagName(status),
                @tagName(self.phase),
                @tagName(self.completion_mode),
                self.source_id,
                self.callback,
                self.callback_handle,
                self.callback_rip,
                self.worker_handle,
                self.worker_rip,
                active_thread,
                active_rip,
                current_step -| self.queued_step,
                current_step -| self.last_progress_step,
                self.scheduling_thread,
                self.scheduling_rip,
                self.callback_suspensions,
                self.callback_resumptions,
                self.worker_slices,
                suspended_count,
            },
        );
    }
};

test "UI handoff tracks callback worker and completion" {
    var tracker = UiHandoffTracker{};
    tracker.queued(7, 0x1234, 0x2000, 0x5678, 100);
    tracker.callbackStarted(0xFFFF_F900_0000_0007, 0x5678, 110);
    tracker.callbackSuspended(120);
    tracker.workerStarted(0x7FFF_2030, 0x1234, 120);

    try std.testing.expect(tracker.shouldPreferCallback(10_120, 10_000));
    try std.testing.expectEqual(Health.worker_stalled, tracker.health(200_120, 100_000));

    tracker.callbackResumed(0x1234, 10_120);
    try std.testing.expectEqual(Phase.callback_running, tracker.phase);
    tracker.completed(10_200);
    try std.testing.expectEqual(Health.completed, tracker.health(20_000, 100_000));
}

test "UI handoff preserves generation across reset" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 2, 3, 4, 5);
    tracker.reset();
    try std.testing.expectEqual(@as(u64, 1), tracker.generation);
    try std.testing.expectEqual(Phase.idle, tracker.phase);
}

test "completed UI handoff returns to its scheduling thread exactly once" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x5678, 20);
    tracker.completed(30);

    try std.testing.expectEqual(@as(u64, 0x7FFF_2020), tracker.completionResumeHandle());
    try std.testing.expect(tracker.hasCompletionDependency());
    try std.testing.expect(!tracker.queueIfIdle(2, 0x4321, 0x7FFF_2030, 0x8765, 35));
    try std.testing.expectEqual(Health.completion_stalled, tracker.health(140, 100));
    try std.testing.expect(!tracker.completionResumed(0x7FFF_2000, 40));
    try std.testing.expect(tracker.completionResumed(0x7FFF_2020, 50));
    try std.testing.expectEqual(@as(u64, 0), tracker.completionResumeHandle());
    try std.testing.expect(!tracker.hasCompletionDependency());
    try std.testing.expectEqual(@as(u64, 1), tracker.generation);
}

test "detached UI handoff completes without a scheduling dependency" {
    var tracker = UiHandoffTracker{};
    tracker.queuedWithMode(1, 0x1234, 0x7FFF_2020, 0x5678, 10, .detached);
    tracker.beginDispatchWithMode(
        1,
        0x1234,
        0x7FFF_2020,
        0x5678,
        10,
        0xFFFF_F900_0000_0001,
        0x1234,
        20,
        .detached,
    );
    tracker.completed(30);

    try std.testing.expectEqual(CompletionMode.detached, tracker.completion_mode);
    try std.testing.expectEqual(@as(u64, 0), tracker.completionResumeHandle());
    try std.testing.expect(!tracker.hasCompletionDependency());
    try std.testing.expectEqual(Health.completed, tracker.health(1_000_000, 100));
    try std.testing.expectEqual(@as(u64, 0), tracker.releaseStalledCompletion(1_000_000, 100));
    try std.testing.expectEqual(@as(u64, 1), tracker.completions_total);
    try std.testing.expectEqual(@as(u64, 1), tracker.completions_detached);
    try std.testing.expectEqual(@as(u64, 0), tracker.pendingCompletions());
    try std.testing.expect(tracker.terminalInvariantHolds());

    // A detached callback cannot pin the next event-loop source behind the
    // parked thread that happened to enqueue it.
    try std.testing.expect(tracker.queueIfIdleWithMode(2, 0x4321, 0x7FFF_2030, 0x8765, 40, .detached));
}

test "a completion dependency its scheduling thread cannot satisfy is released" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x5678, 20);
    tracker.completed(30);

    // Still inside the bound: the dependency is preserved, so a queued
    // callback cannot run across the scheduling thread's continuation.
    try std.testing.expectEqual(@as(u64, 0), tracker.releaseStalledCompletion(120, 100));
    try std.testing.expect(tracker.hasCompletionDependency());
    try std.testing.expect(!tracker.queueIfIdle(2, 0x4321, 0x7FFF_2030, 0x8765, 120));

    // Past it: the scheduling thread never came back, so the idle queue is
    // handed back to the scheduler instead of staying pinned forever.
    try std.testing.expectEqual(@as(u64, 0x7FFF_2020), tracker.releaseStalledCompletion(130, 100));
    try std.testing.expect(!tracker.hasCompletionDependency());
    try std.testing.expectEqual(Phase.idle, tracker.phase);
    try std.testing.expectEqual(@as(u64, 1), tracker.generation);
    try std.testing.expect(tracker.queueIfIdle(2, 0x4321, 0x7FFF_2030, 0x8765, 140));

    // Releasing is one-shot: nothing is left to abandon afterwards.
    try std.testing.expectEqual(@as(u64, 0), tracker.releaseStalledCompletion(1000, 100));
    try std.testing.expectEqual(@as(u64, 1), tracker.completions_abandoned);
}

test "an abandoned scheduling thread does not re-stall the queue once per callback" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x5678, 20);
    tracker.completed(30);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2020), tracker.releaseStalledCompletion(130, 100));

    // The next callback was queued by the same parked thread. Its completion
    // must not pin the queue again — that thread already showed it is not
    // waiting on callbacks, so the stall would repeat for every one of them.
    tracker.queued(2, 0x4321, 0x7FFF_2020, 0x8765, 140);
    tracker.callbackStarted(0xFFFF_F900_0000_0002, 0x8765, 150);
    tracker.completed(160);
    try std.testing.expect(!tracker.hasCompletionDependency());
    try std.testing.expectEqual(Health.completed, tracker.health(10_000, 100));
    try std.testing.expect(tracker.queueIfIdle(3, 0x9999, 0x7FFF_2030, 0x1111, 170));

    // An unrelated thread is unaffected by the abandonment.
    tracker.callbackStarted(0xFFFF_F900_0000_0003, 0x1111, 180);
    tracker.completed(190);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2030), tracker.completionResumeHandle());
    try std.testing.expect(tracker.completionResumed(0x7FFF_2030, 200));

    // Once the abandoned thread runs again it is a valid target once more.
    tracker.noteThreadResumed(0x7FFF_2020);
    tracker.queued(4, 0x4321, 0x7FFF_2020, 0x8765, 210);
    tracker.callbackStarted(0xFFFF_F900_0000_0004, 0x8765, 220);
    tracker.completed(230);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2020), tracker.completionResumeHandle());
}

test "completion ownership accounts resumed abandoned and inherited terminals" {
    var tracker = UiHandoffTracker{};

    tracker.queued(1, 0x1000, 0x7FFF_2020, 0x2000, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x1000, 20);
    tracker.completed(30);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2020), tracker.releaseStalledCompletion(130, 100));

    for (2..4) |source| {
        tracker.queued(source, 0x1000 + source, 0x7FFF_2020, 0x2000, 140 + source);
        tracker.callbackStarted(0xFFFF_F900_0000_0000 + source, 0x1000, 150 + source);
        tracker.completed(160 + source);
    }

    tracker.queued(4, 0x1004, 0x7FFF_2030, 0x2000, 200);
    tracker.callbackStarted(0xFFFF_F900_0000_0004, 0x1004, 210);
    tracker.completed(220);
    try std.testing.expect(tracker.completionResumed(0x7FFF_2030, 230));

    try std.testing.expectEqual(@as(u64, 4), tracker.completions_total);
    try std.testing.expectEqual(@as(u64, 1), tracker.completions_resumed);
    try std.testing.expectEqual(@as(u64, 1), tracker.completions_abandoned);
    try std.testing.expectEqual(@as(u64, 2), tracker.completions_inherited_abandonment);
    try std.testing.expectEqual(@as(u64, 0), tracker.pendingCompletions());
    try std.testing.expect(tracker.terminalInvariantHolds());
}

test "a resumed handoff is never eligible for stalled release" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x5678, 20);
    tracker.completed(30);
    try std.testing.expect(tracker.completionResumed(0x7FFF_2020, 40));
    try std.testing.expectEqual(@as(u64, 0), tracker.releaseStalledCompletion(1_000_000, 100));

    // A callback that is merely slow keeps its handoff: only the completed
    // phase carries a dependency to abandon.
    tracker.queued(2, 0x4321, 0x7FFF_2030, 0x8765, 50);
    tracker.callbackStarted(0xFFFF_F900_0000_0002, 0x8765, 60);
    try std.testing.expectEqual(@as(u64, 0), tracker.releaseStalledCompletion(1_000_000, 100));
    try std.testing.expectEqual(Phase.callback_running, tracker.phase);
}

test "UI callbacks pass child handoffs back to the original guest owner" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x1234, 20);

    const nested = tracker.schedulingOwner(0xFFFF_F900_0000_0001, 0x9999);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2020), nested.thread);
    try std.testing.expectEqual(@as(u64, 0x5678), nested.rip);

    const ordinary = tracker.schedulingOwner(0x7FFF_2040, 0xABCD);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2040), ordinary.thread);
    try std.testing.expectEqual(@as(u64, 0xABCD), ordinary.rip);
}

test "registerProgress updates last_progress_step without state change" {
    var tracker = UiHandoffTracker{};
    try std.testing.expectEqual(Health.idle, tracker.health(100, 10));
    tracker.registerProgress(50);
    // idle is not active, so registerProgress is a no-op
    try std.testing.expectEqual(@as(u64, 0), tracker.last_progress_step);

    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x1234, 20);
    try std.testing.expectEqual(@as(u64, 20), tracker.last_progress_step);
    try std.testing.expectEqual(Health.progressing, tracker.health(25, 10));

    // Without registerProgress, the next health check would stall
    try std.testing.expectEqual(Health.callback_stalled, tracker.health(40, 10));

    // After registerProgress, the stall disappears
    tracker.registerProgress(35);
    try std.testing.expectEqual(Health.progressing, tracker.health(40, 10));

    // Phase is unchanged
    try std.testing.expectEqual(Phase.callback_running, tracker.phase);
}

test "running UI callback yields a quantum only when a producer is eligible" {
    var tracker = UiHandoffTracker{};
    tracker.queued(1, 0x1234, 0x7FFF_2020, 0x5678, 10);
    tracker.callbackStarted(0xFFFF_F900_0000_0001, 0x1234, 20);
    try std.testing.expectEqual(CallbackQuantumAction.retain, tracker.callbackQuantumAction(0, 0));
    try std.testing.expectEqual(CallbackQuantumAction.rendezvous_worker, tracker.callbackQuantumAction(1, 0));
    try std.testing.expectEqual(CallbackQuantumAction.rendezvous_worker, tracker.callbackQuantumAction(0, 1));
    tracker.callbackSuspended(30);
    try std.testing.expectEqual(CallbackQuantumAction.retain, tracker.callbackQuantumAction(1, 1));
}

test "queued callback does not replace active handoff generation" {
    var tracker = UiHandoffTracker{};
    try std.testing.expect(tracker.queueIfIdle(4, 0x4000, 0x7FFF_2000, 0x1111, 10));
    tracker.beginDispatch(4, 0x4000, 0x7FFF_2000, 0x1111, 10, 0xFFFF_F900_0000_0004, 0x4000, 20);

    try std.testing.expect(!tracker.queueIfIdle(5, 0x5000, 0x7FFF_2010, 0x2222, 30));
    try std.testing.expectEqual(@as(u64, 4), tracker.source_id);
    try std.testing.expectEqual(Phase.callback_running, tracker.phase);
    try std.testing.expectEqual(CallbackQuantumAction.rendezvous_worker, tracker.callbackQuantumAction(0, 1));

    tracker.completed(40);
    try std.testing.expect(!tracker.queueIfIdle(5, 0x5000, 0x7FFF_2010, 0x2222, 30));
    try std.testing.expect(tracker.completionResumed(0x7FFF_2000, 45));
    tracker.beginDispatch(5, 0x5000, 0x7FFF_2010, 0x2222, 30, 0xFFFF_F900_0000_0005, 0x5000, 50);
    try std.testing.expectEqual(@as(u64, 2), tracker.generation);
    try std.testing.expectEqual(@as(u64, 5), tracker.source_id);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2010), tracker.scheduling_thread);
    try std.testing.expectEqual(Phase.callback_running, tracker.phase);
}
