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

    pub fn queued(self: *UiHandoffTracker, source_id: u64, callback: u64, scheduling_thread: u64, scheduling_rip: u64, step: u64) void {
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
        };
    }

    pub fn callbackStarted(self: *UiHandoffTracker, handle: u64, step: u64) void {
        if (self.phase != .queued) return;
        self.phase = .callback_running;
        self.callback_handle = handle;
        self.callback_started_step = step;
        self.last_progress_step = step;
    }

    pub fn callbackSuspended(self: *UiHandoffTracker, step: u64) void {
        if (self.phase != .callback_running) return;
        self.phase = .callback_suspended;
        self.callback_suspensions +|= 1;
        self.last_progress_step = step;
    }

    pub fn workerStarted(self: *UiHandoffTracker, handle: u64, step: u64) void {
        if (self.phase != .callback_suspended and self.phase != .worker_running) return;
        self.phase = .worker_running;
        self.worker_handle = handle;
        self.worker_slices +|= 1;
        self.last_progress_step = step;
    }

    pub fn callbackResumed(self: *UiHandoffTracker, step: u64) void {
        if (self.phase != .callback_suspended and self.phase != .worker_running) return;
        self.phase = .callback_running;
        self.worker_handle = 0;
        self.callback_resumptions +|= 1;
        self.last_progress_step = step;
    }

    pub fn completed(self: *UiHandoffTracker, step: u64) void {
        if (!self.isActive()) return;
        self.phase = .completed;
        self.completed_step = step;
        self.last_progress_step = step;
        self.worker_handle = 0;
    }

    pub fn reset(self: *UiHandoffTracker) void {
        const generation = self.generation;
        self.* = .{ .generation = generation };
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

    /// At a scheduling boundary, return to the callback after its worker has
    /// consumed a complete slice instead of burying UI work in the FIFO queue.
    pub fn shouldPreferCallback(self: *const UiHandoffTracker, current_step: u64, worker_quantum: u64) bool {
        return self.phase == .worker_running and
            self.callback_handle != 0 and
            current_step -| self.last_progress_step >= worker_quantum;
    }

    pub fn health(self: *const UiHandoffTracker, current_step: u64, stall_steps: u64) Health {
        return switch (self.phase) {
            .idle => .idle,
            .completed => .completed,
            .queued => if (current_step -| self.last_progress_step >= stall_steps) .queued_stalled else .progressing,
            .callback_running, .callback_suspended => if (current_step -| self.last_progress_step >= stall_steps) .callback_stalled else .progressing,
            .worker_running => if (current_step -| self.last_progress_step >= stall_steps) .worker_stalled else .progressing,
        };
    }

    pub fn diagnose(self: *UiHandoffTracker, current_step: u64, stall_steps: u64) void {
        const status = self.health(current_step, stall_steps);
        if (status == .idle or status == .progressing or status == .completed) return;
        if (current_step -| self.last_diagnostic_step < stall_steps) return;
        self.last_diagnostic_step = current_step;
        self.diagnostic_count +|= 1;
        std.debug.print(
            "scheduler: UI HANDOFF STALL: diagnostic={d} generation={d} health={s} phase={s} source={d} callback=0x{x} callback_handle=0x{x} worker=0x{x} age={d} no_progress={d} queued_by=0x{x} queued_rip=0x{x} suspend/resume/worker_slices={d}/{d}/{d}\n",
            .{
                self.diagnostic_count,
                self.generation,
                @tagName(status),
                @tagName(self.phase),
                self.source_id,
                self.callback,
                self.callback_handle,
                self.worker_handle,
                current_step -| self.queued_step,
                current_step -| self.last_progress_step,
                self.scheduling_thread,
                self.scheduling_rip,
                self.callback_suspensions,
                self.callback_resumptions,
                self.worker_slices,
            },
        );
    }
};

test "UI handoff tracks callback worker and completion" {
    var tracker = UiHandoffTracker{};
    tracker.queued(7, 0x1234, 0x2000, 0x5678, 100);
    tracker.callbackStarted(0xFFFF_F900_0000_0007, 110);
    tracker.callbackSuspended(120);
    tracker.workerStarted(0x7FFF_2030, 120);

    try std.testing.expect(tracker.shouldPreferCallback(10_120, 10_000));
    try std.testing.expectEqual(Health.worker_stalled, tracker.health(200_120, 100_000));

    tracker.callbackResumed(10_120);
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
