//! Immutable build-time envelope for the Xenia GPU observation path.
//!
//! The mutable evidence belongs in `lib/gpu`.  This package owns the facts
//! that must not be re-invented by a ring reader, PM4 executor, diagnostic
//! walker, or presenter: bounded memory work, boundary ownership, and the
//! dependency relation used to find the next actionable edge.

const std = @import("std");

// The contract deliberately validates every boundary and dependency at
// compile time. Keep that audit bounded, but do not let the default evaluator
// quota turn a larger future contract into a false build failure.
comptime {
    @setEvalBranchQuota(10_000);
}

pub const schema_version: u16 = 1;

/// Console PM4 dwords are copied into bounded host storage before execution.
/// This is intentionally the same envelope as the existing PM4 contract.
pub const max_ring_dwords: usize = 16 * 1024;
pub const max_indirect_depth: u8 = 8;
pub const max_indirect_dwords: u32 = 16 * 1024;
pub const max_indirect_references: usize = 64;
/// A corrupt or cyclic guest stream must not consume the whole observer even
/// when every individual indirect buffer is under its local limit.
pub const max_indirect_execution_dwords: u64 = 64 * 1024;
/// Recent packet records are evidence, not an unbounded trace file.
pub const packet_timeline_capacity: usize = 128;

pub const pm4_dword_bytes: u8 = 4;
pub const xe_swap_opcode: u8 = 0x64;
pub const xe_swap_signature: u32 = 0x5357_4150;
pub const xe_swap_reservation_dwords: u32 = 64;
pub const front_buffer_fetch_dwords: u8 = 6;

/// Evidence that the guest actually created an output opportunity.
///
/// `raw_draws_consumed` is deliberately retained beside the stronger
/// counters. A syntactically decoded draw is not a renderable draw: it may
/// have come from a retained observation, may have had no explicit colour
/// target, or may have had no writable surface. Consumers that use this
/// record for frame admission must use `hasOutputOpportunity()` rather than
/// the raw draw count.
pub const GuestOutputEvidence = struct {
    raw_draws_consumed: u64 = 0,
    renderable_draws_observed: u64 = 0,
    color_resolve_observations: u64 = 0,
    guest_swap_boundaries: u64 = 0,
    guest_vdswap_packets_encoded: u64 = 0,

    /// At least one live, target-backed draw or successful color resolve was
    /// observed. Swap requests are intentionally not included: they name a
    /// handoff, not pixels.
    pub fn hasRenderablePixels(self: GuestOutputEvidence) bool {
        return self.renderable_draws_observed != 0 or
            self.color_resolve_observations != 0;
    }

    /// A guest has either made pixels or explicitly requested the output
    /// boundary. This is the only predicate that may arm a producer-to-
    /// presenter handoff check.
    pub fn hasOutputOpportunity(self: GuestOutputEvidence) bool {
        return self.hasRenderablePixels() or
            self.guest_swap_boundaries != 0 or
            self.guest_vdswap_packets_encoded != 0;
    }
};

pub const Owner = enum(u8) {
    rosette,
    guest,
    ring,
    pm4,
    presenter,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .rosette => "rosette",
            .guest => "guest",
            .ring => "ring",
            .pm4 => "pm4",
            .presenter => "presenter",
        };
    }
};

/// A boundary is a fact that can be observed independently.  The ordering is
/// intentionally causal: the first unmet actionable boundary is useful in a
/// log, while the prerequisite mask below remains the source of truth for
/// whether that boundary is actually ready to be attempted.
pub const Boundary = enum(u8) {
    native_presenter_ready,
    guest_vulkan_activity,
    tracepoint_armed,
    guest_wait_progressed,
    guest_producer_progressed,
    ring_publication,
    ring_payload_readable,
    command_processor_entered,
    root_pm4_consumed,
    nested_pm4_consumed,
    pm4_state_programmed,
    draw_submitted,
    render_target_state_observed,
    render_target_memory_observed,
    draw_completion_signaled,
    draw_completion_dispatched,
    guest_vdswap_entered,
    guest_swap_encoded,
    xe_swap_decoder_entered,
    xe_swap_candidate_seen,
    authentic_xe_swap_consumed,
    presenter_entered,
    issue_swap_entered,
    guest_output_refreshed,
    native_present_completed,

    pub fn label(self: Boundary) []const u8 {
        return switch (self) {
            .native_presenter_ready => "native presenter ready",
            .guest_vulkan_activity => "guest Vulkan activity",
            .tracepoint_armed => "GPU tracepoints armed",
            .guest_wait_progressed => "guest wait progressed",
            .guest_producer_progressed => "guest producer progressed",
            .ring_publication => "ring publication",
            .ring_payload_readable => "ring payload readable",
            .command_processor_entered => "command processor entered",
            .root_pm4_consumed => "root PM4 consumed",
            .nested_pm4_consumed => "nested PM4 consumed",
            .pm4_state_programmed => "PM4 state programmed",
            .draw_submitted => "draw submitted",
            .render_target_state_observed => "render-target state observed",
            .render_target_memory_observed => "render-target memory observed",
            .draw_completion_signaled => "draw completion signaled",
            .draw_completion_dispatched => "draw completion dispatched",
            .guest_vdswap_entered => "guest VdSwap entered",
            .guest_swap_encoded => "guest XE_SWAP encoded",
            .xe_swap_decoder_entered => "XE_SWAP decoder entered",
            .xe_swap_candidate_seen => "XE_SWAP candidate seen",
            .authentic_xe_swap_consumed => "authentic XE_SWAP consumed",
            .presenter_entered => "presenter entered",
            .issue_swap_entered => "IssueSwap entered",
            .guest_output_refreshed => "guest output refreshed",
            .native_present_completed => "native presentation completed",
        };
    }

    pub fn owner(self: Boundary) Owner {
        return switch (self) {
            .native_presenter_ready, .native_present_completed => .presenter,
            .guest_vulkan_activity,
            .guest_wait_progressed,
            .guest_producer_progressed,
            .guest_vdswap_entered,
            .guest_swap_encoded,
            .guest_output_refreshed,
            => .guest,
            .tracepoint_armed => .rosette,
            .ring_publication, .ring_payload_readable => .ring,
            .command_processor_entered,
            .root_pm4_consumed,
            .nested_pm4_consumed,
            .pm4_state_programmed,
            .draw_submitted,
            .render_target_state_observed,
            .render_target_memory_observed,
            .draw_completion_signaled,
            .draw_completion_dispatched,
            .xe_swap_decoder_entered,
            .xe_swap_candidate_seen,
            .authentic_xe_swap_consumed,
            => .pm4,
            .presenter_entered, .issue_swap_entered => .presenter,
        };
    }
};

pub const boundary_count: usize = @typeInfo(Boundary).@"enum".fields.len;

pub fn bit(boundary: Boundary) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(boundary)));
}

pub fn allMask() u32 {
    @setEvalBranchQuota(10_000);
    // Boundary is deliberately capped at 32 above, so the contiguous enum
    // layout lets this remain a single constant expression instead of
    // re-evaluating a type-info loop at every importing module's call site.
    return (@as(u32, 1) << @as(u5, @intCast(boundary_count))) - 1;
}

pub fn prerequisiteMask(boundary: Boundary) u32 {
    return switch (boundary) {
        .native_presenter_ready,
        .guest_vulkan_activity,
        .tracepoint_armed,
        .guest_wait_progressed,
        .guest_producer_progressed,
        .guest_vdswap_entered,
        => 0,
        .ring_publication => 0,
        .ring_payload_readable => bit(.ring_publication),
        .command_processor_entered => bit(.ring_publication),
        .root_pm4_consumed => bit(.ring_payload_readable),
        .nested_pm4_consumed => bit(.root_pm4_consumed),
        .pm4_state_programmed, .draw_submitted, .render_target_state_observed => bit(.root_pm4_consumed),
        .render_target_memory_observed => bit(.render_target_state_observed),
        .draw_completion_signaled => bit(.draw_submitted),
        .draw_completion_dispatched => bit(.draw_completion_signaled),
        .guest_swap_encoded => bit(.guest_vdswap_entered),
        .xe_swap_decoder_entered => bit(.command_processor_entered),
        .xe_swap_candidate_seen => bit(.root_pm4_consumed),
        .authentic_xe_swap_consumed => bit(.xe_swap_candidate_seen),
        .presenter_entered => 0,
        // IssueSwap is a function boundary and may be entered by an explicit
        // host diagnostic probe. Authentic packet provenance is tracked by its
        // own edge and must not be inferred from a presenter call.
        .issue_swap_entered => 0,
        .guest_output_refreshed => bit(.issue_swap_entered),
        // Native diagnostic presentation can be complete before the guest has
        // produced a frame. Guest output has its own edge and is never implied
        // by a host-owned diagnostic frame.
        .native_present_completed => bit(.native_presenter_ready),
    };
}

/// Return unmet boundaries whose direct prerequisites are already observed.
/// This is a diagnostic frontier, not an instruction to fabricate the edge.
pub fn actionableMask(observed: u32) u32 {
    @setEvalBranchQuota(10_000);
    const unseen = allMask() & ~observed;
    var result: u32 = 0;
    inline for (@typeInfo(Boundary).@"enum".fields) |field| {
        const boundary: Boundary = @enumFromInt(field.value);
        const candidate = bit(boundary);
        if ((unseen & candidate) != 0 and (prerequisiteMask(boundary) & ~observed) == 0) {
            result |= candidate;
        }
    }
    return result;
}

pub fn contractIsWellFormed() bool {
    @setEvalBranchQuota(10_000);
    if (schema_version == 0 or boundary_count == 0 or boundary_count > 32) return false;
    if (max_ring_dwords == 0 or max_indirect_depth == 0 or max_indirect_dwords == 0 or
        max_indirect_references == 0 or max_indirect_execution_dwords == 0 or
        packet_timeline_capacity == 0 or pm4_dword_bytes != 4 or
        xe_swap_opcode != 0x64 or xe_swap_signature != 0x5357_4150 or
        xe_swap_reservation_dwords == 0 or front_buffer_fetch_dwords != 6)
    {
        return false;
    }
    inline for (@typeInfo(Owner).@"enum".fields) |field| {
        if (@as(Owner, @enumFromInt(field.value)).label().len == 0) return false;
    }
    inline for (@typeInfo(Boundary).@"enum".fields) |field| {
        const boundary: Boundary = @enumFromInt(field.value);
        if (boundary.label().len == 0 or boundary.owner().label().len == 0) return false;
        if ((prerequisiteMask(boundary) & ~allMask()) != 0 or
            (prerequisiteMask(boundary) & bit(boundary)) != 0)
        {
            return false;
        }
    }

    // Kahn-style elimination catches a dependency cycle at compile time. The
    // loop is intentionally bounded by the enum size, so malformed future
    // additions cannot make a package test hang.
    var resolved: u32 = 0;
    var remaining = allMask();
    var iterations: usize = 0;
    while (remaining != 0 and iterations < boundary_count) : (iterations += 1) {
        var progressed = false;
        inline for (@typeInfo(Boundary).@"enum".fields) |field| {
            const boundary: Boundary = @enumFromInt(field.value);
            const candidate = bit(boundary);
            if ((remaining & candidate) != 0 and (prerequisiteMask(boundary) & ~resolved) == 0) {
                resolved |= candidate;
                remaining &= ~candidate;
                progressed = true;
            }
        }
        if (!progressed) return false;
    }
    return remaining == 0;
}

test "GPU observation contract is complete and acyclic" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expectEqual(@as(u8, 0x64), xe_swap_opcode);
    try std.testing.expectEqual(@as(u32, 0x5357_4150), xe_swap_signature);
    try std.testing.expect((actionableMask(bit(.ring_publication)) & bit(.ring_payload_readable)) != 0);
    try std.testing.expect((actionableMask(bit(.ring_publication)) & bit(.root_pm4_consumed)) == 0);
}

test "guest VdSwap stays separate from PM4 evidence" {
    try std.testing.expectEqual(@as(u32, 0), prerequisiteMask(.guest_vdswap_entered));
    try std.testing.expectEqual(bit(.guest_vdswap_entered), prerequisiteMask(.guest_swap_encoded));
    try std.testing.expect((actionableMask(bit(.root_pm4_consumed)) & bit(.guest_vdswap_entered)) != 0);
    try std.testing.expect((actionableMask(bit(.root_pm4_consumed)) & bit(.authentic_xe_swap_consumed)) == 0);
}

test "raw PM4 draws do not count as guest output evidence" {
    const evidence = GuestOutputEvidence{ .raw_draws_consumed = 24 };
    try std.testing.expect(!evidence.hasRenderablePixels());
    try std.testing.expect(!evidence.hasOutputOpportunity());
}

test "target-backed output and explicit swap requests are distinct evidence" {
    try std.testing.expect((GuestOutputEvidence{
        .raw_draws_consumed = 24,
        .renderable_draws_observed = 1,
    }).hasOutputOpportunity());
    try std.testing.expect((GuestOutputEvidence{ .color_resolve_observations = 1 }).hasRenderablePixels());
    try std.testing.expect((GuestOutputEvidence{ .guest_swap_boundaries = 1 }).hasOutputOpportunity());
    try std.testing.expect(!(GuestOutputEvidence{ .guest_vdswap_packets_encoded = 0 }).hasOutputOpportunity());
}

test "native diagnostic completion does not require guest output" {
    try std.testing.expectEqual(bit(.native_presenter_ready), prerequisiteMask(.native_present_completed));
    const actionable = actionableMask(bit(.native_presenter_ready));
    try std.testing.expect((actionable & bit(.native_present_completed)) != 0);
    try std.testing.expect((actionable & bit(.guest_output_refreshed)) == 0);
}
