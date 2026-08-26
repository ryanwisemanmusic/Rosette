//! Runtime application controller for translated graphics.
//!
//! This is a small state machine at the seam between the guest scheduler,
//! Xenos command processing and the native presenter.  It does not own any of
//! those systems and it cannot mutate guest state.  Its job is to make a
//! repeatable choice about the *next safe observation or host-owned action*.
//!
//! The distinction matters for the current Halo 3 failure.  The host Vulkan
//! presenter can be ready while the title has stopped after a ring publication.
//! A controller that sees only "presenter ready" will keep presenting clears;
//! this controller keeps the guest-owned VdSwap boundary open and reports the
//! producer/raster gap instead.

const std = @import("std");
const policy = @import("xenia_application_controller_contract");

pub const Phase = policy.Phase;
pub const Action = policy.Action;
pub const Blocker = policy.Blocker;
pub const Domain = policy.Domain;
pub const guest_quiet_threshold_steps = policy.guest_quiet_threshold_steps;
pub const ring_quiet_threshold_steps = policy.ring_quiet_threshold_steps;
pub const pm4_quiet_threshold_steps = policy.pm4_quiet_threshold_steps;
pub const presenter_quiet_threshold_steps = policy.presenter_quiet_threshold_steps;

/// One immutable-at-call-boundary snapshot assembled by the process owner.
/// Progress stamps are optional because some observers only have counters and
/// must not invent an executed-step location for them.
pub const Sample = struct {
    step: u64 = 0,
    guest_progress_step: ?u64 = null,
    ring_progress_step: ?u64 = null,
    pm4_progress_step: ?u64 = null,
    presenter_progress_step: ?u64 = null,

    guest_vdswap_entered: bool = false,
    guest_swap_encoded: bool = false,
    authentic_swap_consumed: bool = false,
    guest_output_available: bool = false,
    native_present_completed: bool = false,

    ring_published: bool = false,
    pm4_stream_observed: bool = false,
    pm4_stream_consumed: bool = false,
    render_target_state_observed: bool = false,
    render_target_memory_observed: bool = false,
    draw_completion_signaled: u64 = 0,
    draw_completion_dispatched: u64 = 0,
    pending_gpu_interrupts: u32 = 0,
    interrupt_callback_registered: bool = false,

    presenter_ready: bool = false,
    presenter_device_lost: bool = false,
    guest_wait_deadlocked: bool = false,
    guest_waiting: bool = false,
    guest_runnable: bool = true,
};

pub const Decision = struct {
    phase: Phase = .boot,
    action: Action = .observe_only,
    blocker: Blocker = .none,
    secondary_blocker: Blocker = .none,
    domain: Domain = .none,
    step: u64 = 0,
    guest_quiet_steps: u64 = 0,
    ring_quiet_steps: u64 = 0,
    pm4_quiet_steps: u64 = 0,
    presenter_quiet_steps: u64 = 0,
    host_action_authorized: bool = false,

    pub fn fingerprint(self: Decision) u64 {
        return @as(u64, @intFromEnum(self.phase)) |
            (@as(u64, @intFromEnum(self.action)) << 8) |
            (@as(u64, @intFromEnum(self.blocker)) << 16) |
            (@as(u64, @intFromEnum(self.secondary_blocker)) << 24) |
            (@as(u64, @intFromEnum(self.domain)) << 32) |
            (@as(u64, @intFromBool(self.host_action_authorized)) << 40);
    }
};

pub const Controller = struct {
    run_epoch: u64 = 0,
    last_step: u64 = 0,
    last_guest_progress_step: ?u64 = null,
    last_ring_progress_step: ?u64 = null,
    last_pm4_progress_step: ?u64 = null,
    last_presenter_progress_step: ?u64 = null,
    phase: Phase = .boot,
    last_decision: Decision = .{},
    observations: u64 = 0,
    transitions: u64 = 0,
    host_actions_authorized: u64 = 0,
    guest_boundary_refusals: u64 = 0,

    /// Observe one process snapshot and return the controller directive. The
    /// only state this mutates is this ledger; any host action is still applied
    /// explicitly by the process owner after it inspects the directive.
    pub fn observe(self: *Controller, sample: Sample) Decision {
        if (sample.step < self.last_step) self.beginNewRun();
        self.last_step = sample.step;
        self.observeProgress(&self.last_guest_progress_step, sample.guest_progress_step, sample.step);
        self.observeProgress(&self.last_ring_progress_step, sample.ring_progress_step, sample.step);
        self.observeProgress(&self.last_pm4_progress_step, sample.pm4_progress_step, sample.step);
        self.observeProgress(&self.last_presenter_progress_step, sample.presenter_progress_step, sample.step);
        self.observations +|= 1;

        const decision = self.decide(sample);
        if (decision.fingerprint() != self.last_decision.fingerprint()) self.transitions +|= 1;
        if (decision.host_action_authorized) self.host_actions_authorized +|= 1;
        if (decision.action == .await_guest_vdswap or decision.blocker == .guest_vdswap_not_entered)
            self.guest_boundary_refusals +|= 1;
        self.phase = decision.phase;
        self.last_decision = decision;
        return decision;
    }

    pub fn guestQuietSteps(self: *const Controller, now: u64) u64 {
        return quietSteps(self.last_guest_progress_step, now);
    }

    pub fn ringQuietSteps(self: *const Controller, now: u64) u64 {
        return quietSteps(self.last_ring_progress_step, now);
    }

    pub fn pm4QuietSteps(self: *const Controller, now: u64) u64 {
        return quietSteps(self.last_pm4_progress_step, now);
    }

    pub fn presenterQuietSteps(self: *const Controller, now: u64) u64 {
        return quietSteps(self.last_presenter_progress_step, now);
    }

    fn observeProgress(self: *Controller, last: *?u64, candidate: ?u64, now: u64) void {
        _ = self;
        const stamp = candidate orelse return;
        if (stamp == 0 or stamp > now) return;
        if (last.* == null or stamp > last.*.?) last.* = stamp;
    }

    fn beginNewRun(self: *Controller) void {
        self.run_epoch +|= 1;
        self.last_step = 0;
        self.last_guest_progress_step = null;
        self.last_ring_progress_step = null;
        self.last_pm4_progress_step = null;
        self.last_presenter_progress_step = null;
        self.phase = .boot;
        self.last_decision = .{};
    }

    fn decide(self: *const Controller, sample: Sample) Decision {
        const guest_quiet = self.guestQuietSteps(sample.step);
        const ring_quiet = self.ringQuietSteps(sample.step);
        const pm4_quiet = self.pm4QuietSteps(sample.step);
        const presenter_quiet = self.presenterQuietSteps(sample.step);
        const completion_pending = sample.draw_completion_signaled > sample.draw_completion_dispatched;
        const producer_stalled = sample.ring_published and
            ring_quiet >= policy.ring_quiet_threshold_steps and
            !sample.authentic_swap_consumed;
        const target_missing = sample.pm4_stream_consumed and !sample.render_target_state_observed;
        const memory_missing = sample.render_target_state_observed and !sample.render_target_memory_observed;

        var decision = Decision{
            .step = sample.step,
            .guest_quiet_steps = guest_quiet,
            .ring_quiet_steps = ring_quiet,
            .pm4_quiet_steps = pm4_quiet,
            .presenter_quiet_steps = presenter_quiet,
        };

        if (sample.native_present_completed) {
            decision.phase = .presented;
            decision.action = .observe_only;
            decision.domain = .presenter;
            return decision;
        }
        if (sample.presenter_device_lost) {
            decision.phase = .stalled;
            decision.action = .report_stall;
            decision.blocker = .device_lost;
            decision.domain = .presenter;
            return decision;
        }
        if (sample.guest_wait_deadlocked) {
            decision.phase = .stalled;
            decision.action = .report_stall;
            decision.blocker = .guest_wait_deadlock;
            decision.domain = .guest;
            return decision;
        }
        if (completion_pending and sample.interrupt_callback_registered) {
            decision.phase = .gpu_pending;
            decision.action = .drain_gpu_interrupts;
            decision.blocker = .completion_not_dispatched;
            decision.domain = .pm4;
            decision.host_action_authorized = true;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if (sample.pending_gpu_interrupts != 0 and sample.interrupt_callback_registered) {
            decision.phase = .gpu_pending;
            decision.action = .drain_gpu_interrupts;
            decision.domain = .pm4;
            decision.host_action_authorized = true;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if (target_missing) {
            decision.phase = .waiting_render_target;
            decision.action = .await_render_target;
            decision.blocker = .render_target_missing;
            decision.domain = .pm4;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if (memory_missing) {
            decision.phase = .waiting_render_target;
            decision.action = .await_render_target;
            decision.blocker = .render_target_missing;
            decision.domain = .pm4;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if (sample.guest_output_available and sample.presenter_ready and !sample.authentic_swap_consumed) {
            decision.phase = .waiting_presenter;
            decision.action = .refresh_discovered_output;
            decision.domain = .presenter;
            decision.host_action_authorized = true;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if (producer_stalled) {
            decision.phase = .stalled;
            decision.action = .report_stall;
            decision.blocker = if (sample.guest_vdswap_entered)
                .guest_producer_quiet
            else
                .guest_vdswap_not_entered;
            decision.domain = .guest;
            return decision;
        }
        if (!sample.presenter_ready) {
            decision.phase = .waiting_presenter;
            decision.action = .await_presenter;
            decision.blocker = .presenter_not_ready;
            decision.domain = .presenter;
            return decision;
        }
        if (!sample.guest_vdswap_entered) {
            decision.phase = if (sample.guest_waiting) .waiting_guest else .guest_running;
            decision.action = .await_guest_vdswap;
            decision.blocker = .guest_vdswap_not_entered;
            decision.domain = .guest;
            return decision;
        }
        if (!sample.authentic_swap_consumed) {
            decision.phase = .gpu_pending;
            decision.action = .await_guest_vdswap;
            decision.blocker = .authentic_swap_not_consumed;
            decision.domain = .pm4;
            return decision;
        }
        decision.phase = if (sample.guest_runnable) .guest_running else .waiting_guest;
        decision.action = .continue_guest;
        decision.domain = .guest;
        return decision;
    }
};

fn quietSteps(last: ?u64, now: u64) u64 {
    return if (last) |stamp| now -| stamp else 0;
}

test "the controller prioritizes a queued completion for a real callback" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = 100,
        .pm4_progress_step = 90,
        .pm4_stream_consumed = true,
        .render_target_state_observed = true,
        .draw_completion_signaled = 4,
        .draw_completion_dispatched = 1,
        .interrupt_callback_registered = true,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Action.drain_gpu_interrupts, decision.action);
    try std.testing.expect(decision.host_action_authorized);
    try std.testing.expectEqual(Blocker.completion_not_dispatched, decision.blocker);
}

test "a stalled published ring keeps the guest VdSwap boundary open" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = policy.ring_quiet_threshold_steps + 10,
        .guest_progress_step = 1,
        .ring_progress_step = 1,
        .ring_published = true,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Phase.stalled, decision.phase);
    try std.testing.expectEqual(Action.report_stall, decision.action);
    try std.testing.expectEqual(Blocker.guest_vdswap_not_entered, decision.blocker);
    try std.testing.expectEqual(Domain.guest, decision.domain);
}

test "a consumed draw with no target is not allowed to look like a presentation" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = 100,
        .pm4_progress_step = 99,
        .pm4_stream_consumed = true,
        .render_target_state_observed = false,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Action.await_render_target, decision.action);
    try std.testing.expectEqual(Blocker.render_target_missing, decision.blocker);
    try std.testing.expect(!decision.host_action_authorized);
}

test "discovered guest pixels may be refreshed without fabricating VdSwap" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = 100,
        .guest_output_available = true,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Action.refresh_discovered_output, decision.action);
    try std.testing.expect(decision.host_action_authorized);
    try std.testing.expectEqual(Blocker.none, decision.blocker);
}

test "a native completion ends the controller without a second action" {
    var controller = Controller{};
    const decision = controller.observe(.{ .step = 100, .native_present_completed = true });
    try std.testing.expectEqual(Phase.presented, decision.phase);
    try std.testing.expectEqual(Action.observe_only, decision.action);
    try std.testing.expectEqual(Blocker.none, decision.blocker);
}

test "a decreasing step starts a new run epoch" {
    var controller = Controller{};
    _ = controller.observe(.{ .step = 100, .guest_progress_step = 90 });
    _ = controller.observe(.{ .step = 10 });
    try std.testing.expectEqual(@as(u64, 1), controller.run_epoch);
    try std.testing.expectEqual(@as(u64, 10), controller.last_step);
}

test "every controller action is non-fabricating by policy" {
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        const action: Action = @enumFromInt(field.value);
        try std.testing.expect(!action.fabricatesGuestBehaviour());
    }
}
