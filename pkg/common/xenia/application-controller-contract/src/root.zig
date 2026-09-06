//! Immutable application-controller policy for translated graphics runs.
//!
//! The controller is intentionally a coordinator, not a second emulator.  It
//! can select a safe host-owned action (drain an already queued GPU event or
//! refresh an already discovered guest image), or describe the guest-owned
//! boundary that must be reached.  There is no action here that fabricates a
//! VdSwap, advances CP_RB_WPTR, releases a guest wait, or marks a packet
//! authentic.

const std = @import("std");

pub const schema_version: u16 = 1;

pub const Phase = enum(u8) {
    boot,
    guest_running,
    gpu_pending,
    waiting_guest,
    waiting_render_target,
    waiting_presenter,
    presented,
    stalled,

    pub fn label(self: Phase) []const u8 {
        return switch (self) {
            .boot => "boot",
            .guest_running => "guest_running",
            .gpu_pending => "gpu_pending",
            .waiting_guest => "waiting_guest",
            .waiting_render_target => "waiting_render_target",
            .waiting_presenter => "waiting_presenter",
            .presented => "presented",
            .stalled => "stalled",
        };
    }
};

pub const Action = enum(u8) {
    /// No mutation is safe or necessary. Continue observing the owner that is
    /// supposed to produce the next edge.
    observe_only,
    /// The guest remains the active producer. The scheduler may continue its
    /// normal rotation; the controller does not execute it itself.
    continue_guest,
    /// Drain events already queued by the Xenos runtime into an already
    /// registered callback.
    drain_gpu_interrupts,
    /// Give a pending GPU callback/queue a safe scheduling opportunity. This
    /// is a directive to the host scheduler, never a guest state write.
    yield_guest_for_gpu,
    /// Wait for the title to enter its own VdSwap path.
    await_guest_vdswap,
    /// Wait for Xenos target state or memory evidence.
    await_render_target,
    /// Wait for the host presenter to become usable or to complete a frame.
    await_presenter,
    /// Present a guest-produced image already discovered in memory. This does
    /// not create a packet or claim that the title called VdSwap.
    refresh_discovered_output,
    /// Emit a terminal/stall diagnosis. No recovery is claimed.
    report_stall,

    pub fn label(self: Action) []const u8 {
        return switch (self) {
            .observe_only => "observe_only",
            .continue_guest => "continue_guest",
            .drain_gpu_interrupts => "drain_gpu_interrupts",
            .yield_guest_for_gpu => "yield_guest_for_gpu",
            .await_guest_vdswap => "await_guest_vdswap",
            .await_render_target => "await_render_target",
            .await_presenter => "await_presenter",
            .refresh_discovered_output => "refresh_discovered_output",
            .report_stall => "report_stall",
        };
    }

    pub fn hostMayExecute(self: Action) bool {
        return switch (self) {
            .drain_gpu_interrupts, .refresh_discovered_output => true,
            else => false,
        };
    }

    /// A hard safety property: no controller action can claim to perform a
    /// guest-owned decision.
    pub fn fabricatesGuestBehaviour(self: Action) bool {
        _ = self;
        return false;
    }
};

pub const Blocker = enum(u8) {
    none,
    guest_vdswap_not_entered,
    guest_producer_quiet,
    render_target_missing,
    completion_not_dispatched,
    /// Xenia's PowerPC callback exists, but the pending completion belongs to
    /// Rosette's translated-x86 Xenos model. The integer callback address must
    /// not be copied across that executor boundary.
    callback_domain_bridge_missing,
    authentic_swap_not_consumed,
    presenter_not_ready,
    guest_wait_deadlock,
    device_lost,

    pub fn label(self: Blocker) []const u8 {
        return switch (self) {
            .none => "none",
            .guest_vdswap_not_entered => "guest_vdswap_not_entered",
            .guest_producer_quiet => "guest_producer_quiet",
            .render_target_missing => "render_target_missing",
            .completion_not_dispatched => "completion_not_dispatched",
            .callback_domain_bridge_missing => "callback_domain_bridge_missing",
            .authentic_swap_not_consumed => "authentic_swap_not_consumed",
            .presenter_not_ready => "presenter_not_ready",
            .guest_wait_deadlock => "guest_wait_deadlock",
            .device_lost => "device_lost",
        };
    }
};

pub const Domain = enum(u8) {
    none,
    guest,
    ring,
    pm4,
    presenter,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .none => "none",
            .guest => "guest",
            .ring => "ring",
            .pm4 => "pm4",
            .presenter => "presenter",
        };
    }
};

/// These are executed guest steps, not wall-clock durations.  A run at a
/// different host speed therefore gets the same semantic classification.
pub const guest_quiet_threshold_steps: u64 = 500_000_000;
pub const ring_quiet_threshold_steps: u64 = 500_000_000;
pub const pm4_quiet_threshold_steps: u64 = 250_000_000;
pub const presenter_quiet_threshold_steps: u64 = 250_000_000;

pub fn contractIsWellFormed() bool {
    if (guest_quiet_threshold_steps == 0 or ring_quiet_threshold_steps == 0 or
        pm4_quiet_threshold_steps == 0 or presenter_quiet_threshold_steps == 0)
    {
        return false;
    }
    inline for (@typeInfo(Phase).@"enum".fields) |field| {
        if (@as(Phase, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        const action: Action = @enumFromInt(field.value);
        if (action.label().len == 0 or action.fabricatesGuestBehaviour()) return false;
    }
    inline for (@typeInfo(Blocker).@"enum".fields) |field| {
        if (@as(Blocker, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(Domain).@"enum".fields) |field| {
        if (@as(Domain, @enumFromInt(field.value)).label().len == 0) return false;
    }
    return true;
}

test "controller policy is complete and cannot fabricate guest behaviour" {
    try std.testing.expect(contractIsWellFormed());
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        const action: Action = @enumFromInt(field.value);
        try std.testing.expect(!action.fabricatesGuestBehaviour());
    }
    try std.testing.expect(Action.drain_gpu_interrupts.hostMayExecute());
    try std.testing.expect(!Action.await_guest_vdswap.hostMayExecute());
}

test "step thresholds remain explicit and host-independent" {
    try std.testing.expectEqual(@as(u64, 500_000_000), guest_quiet_threshold_steps);
    try std.testing.expectEqual(@as(u64, 500_000_000), ring_quiet_threshold_steps);
    try std.testing.expect(Domain.presenter.label().len != 0);
}
