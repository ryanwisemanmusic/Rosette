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
    /// Callback registered in Rosette's translated-x86 model. Only this field
    /// authorizes `drain_gpu_interrupts` into `scheduleSignalCallback`.
    interrupt_callback_registered: bool = false,
    /// Xenia's real callback lives in its PowerPC CPU engine. It proves that
    /// Xenia's callback channel exists, but cannot receive model-x86 events.
    powerpc_callback_registered: bool = false,
    powerpc_callback_returned: bool = false,

    presenter_ready: bool = false,
    presenter_device_lost: bool = false,
    guest_wait_deadlocked: bool = false,
    guest_waiting: bool = false,
    guest_runnable: bool = true,
};

/// A controller decision is a safety boundary, not just a log message. These
/// violations describe decisions that would either mutate a host-owned system
/// without the evidence that authorizes it or report a state contradictory to
/// the sample from which the decision was made.
pub const DecisionViolation = enum(u8) {
    host_authorization_mismatch,
    host_action_domain_mismatch,
    drain_without_callback,
    drain_without_pending_work,
    refresh_without_guest_output,
    refresh_without_presenter,
    refresh_after_authentic_swap,
    yield_without_powerpc_callback,
    yield_without_pending_work,
    guest_boundary_already_entered,
    authentic_swap_before_guest_boundary,
    device_lost_not_observed,
    render_target_gap_not_observed,
    action_blocker_mismatch,
    presenter_wait_while_ready,
    presented_without_completion,
    presented_with_mutating_action,

    pub fn label(self: DecisionViolation) []const u8 {
        return switch (self) {
            .host_authorization_mismatch => "host-authorization-mismatch",
            .host_action_domain_mismatch => "host-action-domain-mismatch",
            .drain_without_callback => "drain-without-callback",
            .drain_without_pending_work => "drain-without-pending-work",
            .refresh_without_guest_output => "refresh-without-guest-output",
            .refresh_without_presenter => "refresh-without-presenter",
            .refresh_after_authentic_swap => "refresh-after-authentic-swap",
            .yield_without_powerpc_callback => "yield-without-powerpc-callback",
            .yield_without_pending_work => "yield-without-pending-work",
            .guest_boundary_already_entered => "guest-boundary-already-entered",
            .authentic_swap_before_guest_boundary => "authentic-swap-before-guest-boundary",
            .device_lost_not_observed => "device-lost-not-observed",
            .render_target_gap_not_observed => "render-target-gap-not-observed",
            .action_blocker_mismatch => "action-blocker-mismatch",
            .presenter_wait_while_ready => "presenter-wait-while-ready",
            .presented_without_completion => "presented-without-completion",
            .presented_with_mutating_action => "presented-with-mutating-action",
        };
    }
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

    /// Validate the decision against the immutable sample that produced it.
    /// This is intentionally independent of `decide`: the second path catches
    /// regressions where a future policy change adds an action but forgets to
    /// update one of its evidence or ownership preconditions.
    pub fn contractViolation(self: Decision, sample: Sample) ?DecisionViolation {
        if (self.host_action_authorized != self.action.hostMayExecute())
            return .host_authorization_mismatch;

        const target_missing = sample.pm4_stream_consumed and !sample.render_target_state_observed;
        const memory_missing = sample.render_target_state_observed and !sample.render_target_memory_observed;
        const completion_pending = sample.draw_completion_signaled > sample.draw_completion_dispatched;
        const gpu_work_pending = completion_pending or sample.pending_gpu_interrupts != 0;

        if (self.blocker == .guest_vdswap_not_entered and sample.guest_vdswap_entered)
            return .guest_boundary_already_entered;
        if (self.blocker == .authentic_swap_not_consumed and !sample.guest_vdswap_entered)
            return .authentic_swap_before_guest_boundary;
        if (self.blocker == .device_lost and !sample.presenter_device_lost)
            return .device_lost_not_observed;
        if (self.blocker == .render_target_missing and !(target_missing or memory_missing))
            return .render_target_gap_not_observed;

        switch (self.action) {
            .drain_gpu_interrupts => {
                if (self.domain != .pm4) return .host_action_domain_mismatch;
                if (!sample.interrupt_callback_registered) return .drain_without_callback;
                if (!gpu_work_pending) return .drain_without_pending_work;
            },
            .refresh_discovered_output => {
                if (self.domain != .presenter) return .host_action_domain_mismatch;
                if (!sample.guest_output_available) return .refresh_without_guest_output;
                if (!sample.presenter_ready) return .refresh_without_presenter;
                if (sample.authentic_swap_consumed) return .refresh_after_authentic_swap;
            },
            .yield_guest_for_gpu => {
                if (!sample.powerpc_callback_registered) return .yield_without_powerpc_callback;
                if (!gpu_work_pending) return .yield_without_pending_work;
            },
            .await_guest_vdswap => {
                if (self.blocker != .guest_vdswap_not_entered and
                    self.blocker != .authentic_swap_not_consumed)
                    return .action_blocker_mismatch;
            },
            .await_render_target => {
                if (self.blocker != .render_target_missing) return .action_blocker_mismatch;
            },
            .await_presenter => {
                if (self.blocker != .presenter_not_ready) return .action_blocker_mismatch;
                if (sample.presenter_ready) return .presenter_wait_while_ready;
            },
            .report_stall => {
                if (self.blocker == .none) return .action_blocker_mismatch;
            },
            .observe_only, .continue_guest => {},
        }

        if (self.phase == .presented) {
            if (!sample.native_present_completed) return .presented_without_completion;
            if (self.action != .observe_only) return .presented_with_mutating_action;
        }
        return null;
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
    /// Number of samples for which the guest-owned VdSwap boundary remained
    /// open. This is an observation count, not a failed wake or refusal.
    guest_boundary_observations: u64 = 0,
    /// A non-zero value means the policy emitted a decision whose ownership or
    /// evidence preconditions contradict the sample that produced it.
    last_sample: Sample = .{},
    contract_violations: u64 = 0,
    last_contract_violation: ?DecisionViolation = null,
    last_contract_violation_decision: Decision = .{},
    last_contract_violation_sample: Sample = .{},

    /// Observe one process snapshot and return the controller directive. The
    /// only state this mutates is this ledger; any host action is still applied
    /// explicitly by the process owner after it inspects the directive.
    pub fn observe(self: *Controller, sample: Sample) Decision {
        if (sample.step < self.last_step) self.beginNewRun();
        self.last_step = sample.step;
        self.last_sample = sample;
        self.observeProgress(&self.last_guest_progress_step, sample.guest_progress_step, sample.step);
        self.observeProgress(&self.last_ring_progress_step, sample.ring_progress_step, sample.step);
        self.observeProgress(&self.last_pm4_progress_step, sample.pm4_progress_step, sample.step);
        self.observeProgress(&self.last_presenter_progress_step, sample.presenter_progress_step, sample.step);
        self.observations +|= 1;

        const decision = self.decide(sample);
        if (decision.fingerprint() != self.last_decision.fingerprint()) self.transitions +|= 1;
        if (decision.host_action_authorized) self.host_actions_authorized +|= 1;
        if (decision.action == .await_guest_vdswap or decision.blocker == .guest_vdswap_not_entered)
            self.guest_boundary_observations +|= 1;
        if (decision.contractViolation(sample)) |violation| {
            self.contract_violations +|= 1;
            self.last_contract_violation = violation;
            self.last_contract_violation_decision = decision;
            self.last_contract_violation_sample = sample;
        }
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
        // A consumed draw with no target is causally upstream of callback and
        // wait symptoms. Lead with the first missing rendering fact even when
        // a heuristic wait detector also calls the cycling guest deadlocked.
        if (target_missing or memory_missing) {
            decision.phase = .waiting_render_target;
            decision.action = .await_render_target;
            decision.blocker = .render_target_missing;
            decision.domain = .pm4;
            if (sample.guest_wait_deadlocked) decision.secondary_blocker = .guest_wait_deadlock;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if ((completion_pending or sample.pending_gpu_interrupts != 0) and sample.interrupt_callback_registered) {
            decision.phase = .gpu_pending;
            decision.action = .drain_gpu_interrupts;
            if (completion_pending) decision.blocker = .completion_not_dispatched;
            decision.domain = .pm4;
            decision.host_action_authorized = true;
            if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if ((completion_pending or sample.pending_gpu_interrupts != 0) and sample.powerpc_callback_registered) {
            decision.phase = .gpu_pending;
            decision.action = .yield_guest_for_gpu;
            decision.blocker = .callback_domain_bridge_missing;
            decision.domain = .pm4;
            decision.host_action_authorized = false;
            if (sample.powerpc_callback_returned) {
                // The real PowerPC route is alive. The pending count belongs to
                // the parallel model route and must not be interpreted as a
                // failure of Xenia's callback consumer.
                decision.secondary_blocker = .completion_not_dispatched;
            } else if (producer_stalled) decision.secondary_blocker = .guest_producer_quiet;
            return decision;
        }
        if (sample.guest_wait_deadlocked) {
            decision.phase = .stalled;
            decision.action = .report_stall;
            decision.blocker = .guest_wait_deadlock;
            decision.domain = .guest;
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
        .render_target_memory_observed = true,
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

test "PowerPC callback cannot drain translated x86 model completions" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = 100,
        .draw_completion_signaled = 24,
        .powerpc_callback_registered = true,
        .powerpc_callback_returned = true,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Action.yield_guest_for_gpu, decision.action);
    try std.testing.expectEqual(Blocker.callback_domain_bridge_missing, decision.blocker);
    try std.testing.expect(!decision.host_action_authorized);
}

test "render target gap outranks a coincident wait diagnosis" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = 100,
        .pm4_stream_consumed = true,
        .guest_wait_deadlocked = true,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Blocker.render_target_missing, decision.blocker);
    try std.testing.expectEqual(Blocker.guest_wait_deadlock, decision.secondary_blocker);
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

test "an open guest boundary is observation, not a controller contract failure" {
    var controller = Controller{};
    const decision = controller.observe(.{
        .step = 100,
        .presenter_ready = true,
    });
    try std.testing.expectEqual(Action.await_guest_vdswap, decision.action);
    try std.testing.expectEqual(@as(u64, 1), controller.guest_boundary_observations);
    try std.testing.expectEqual(@as(u64, 0), controller.contract_violations);
    try std.testing.expect(controller.last_contract_violation == null);
}

test "controller validation catches unauthorized host work" {
    const decision = Decision{
        .action = .await_guest_vdswap,
        .host_action_authorized = true,
    };
    try std.testing.expectEqual(
        DecisionViolation.host_authorization_mismatch,
        decision.contractViolation(.{}).?,
    );
}

test "controller validation catches a host drain without callback evidence" {
    const decision = Decision{
        .phase = .gpu_pending,
        .action = .drain_gpu_interrupts,
        .domain = .pm4,
        .host_action_authorized = true,
    };
    try std.testing.expectEqual(
        DecisionViolation.drain_without_callback,
        decision.contractViolation(.{ .pending_gpu_interrupts = 1 }).?,
    );
}

test "every controller action is non-fabricating by policy" {
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        const action: Action = @enumFromInt(field.value);
        try std.testing.expect(!action.fabricatesGuestBehaviour());
    }
}
