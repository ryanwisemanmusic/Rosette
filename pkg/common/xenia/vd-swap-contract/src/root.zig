//! Compile-time facts for the Xenia VdSwap -> PM4_XE_SWAP handoff.
//!
//! This package deliberately contains no ring, no pointers and no runtime
//! policy.  It is the immutable vocabulary shared by the Ready Compiler,
//! diagnostics and the live GPU observer.  The important distinction is
//! between a title entering `VdSwap`, a packet existing in retained memory and
//! the command processor consuming that packet.  Those are separate owners
//! and separate facts; collapsing them is how a draw-only batch gets reported
//! as a present request.

const std = @import("std");

/// The ordered handoff stages.  Every stage is observable independently, but
/// `firstGap` deliberately reports the first missing prefix stage.  Later
/// observations are retained as evidence and never close an earlier gap.
pub const Stage = enum(u8) {
    guest_vdswap_entered,
    vdswap_arguments_captured,
    frontbuffer_validated,
    fetch_constant_encoded,
    guest_xe_swap_encoded,
    vdswap_completed,
    ring_write_pointer_published,
    ring_geometry_observed,
    ring_projection_readable,
    pm4_stream_observed,
    pm4_stream_validated,
    pm4_indirects_resolved,
    pm4_state_programmed,
    draw_submitted,
    draw_consumed,
    render_target_state_observed,
    render_target_memory_observed,
    draw_completion_signaled,
    draw_completion_dispatched,
    guest_wait_observed_after_draw,
    guest_producer_progressed_after_draw,
    xe_swap_candidate_seen,
    xe_swap_packet_readable,
    xe_swap_packet_decoded,
    fetch_constant_decoded,
    authentic_xe_swap_consumed,
    issue_swap_entered,
    output_refresh_succeeded,
    native_presented,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .guest_vdswap_entered => "guest VdSwap entered",
            .vdswap_arguments_captured => "VdSwap arguments captured",
            .frontbuffer_validated => "front buffer validated",
            .fetch_constant_encoded => "front-buffer fetch constant encoded",
            .guest_xe_swap_encoded => "guest XE_SWAP encoded",
            .vdswap_completed => "VdSwap completed",
            .ring_write_pointer_published => "ring write pointer published",
            .ring_geometry_observed => "ring geometry observed",
            .ring_projection_readable => "ring projection readable",
            .pm4_stream_observed => "PM4 stream observed",
            .pm4_stream_validated => "PM4 stream validated",
            .pm4_indirects_resolved => "PM4 indirect buffers resolved",
            .pm4_state_programmed => "PM4 state programmed",
            .draw_submitted => "draw submitted",
            .draw_consumed => "draw consumed",
            .render_target_state_observed => "render-target state observed",
            .render_target_memory_observed => "render-target memory observed",
            .draw_completion_signaled => "draw completion signaled",
            .draw_completion_dispatched => "draw completion dispatched",
            .guest_wait_observed_after_draw => "guest wait observed after draw",
            .guest_producer_progressed_after_draw => "guest producer progressed after draw",
            .xe_swap_candidate_seen => "XE_SWAP candidate seen",
            .xe_swap_packet_readable => "XE_SWAP packet readable",
            .xe_swap_packet_decoded => "XE_SWAP packet decoded",
            .fetch_constant_decoded => "fetch constant decoded",
            .authentic_xe_swap_consumed => "authentic XE_SWAP consumed",
            .issue_swap_entered => "IssueSwap entered",
            .output_refresh_succeeded => "guest output refresh succeeded",
            .native_presented => "native presentation completed",
        };
    }

    pub fn owner(self: Stage) Owner {
        return switch (self) {
            .guest_vdswap_entered,
            .vdswap_arguments_captured,
            .frontbuffer_validated,
            .fetch_constant_encoded,
            .guest_xe_swap_encoded,
            .vdswap_completed,
            .ring_write_pointer_published,
            => .guest_title,
            .ring_geometry_observed,
            .ring_projection_readable,
            .pm4_stream_observed,
            .pm4_stream_validated,
            .pm4_indirects_resolved,
            .pm4_state_programmed,
            .draw_submitted,
            .draw_consumed,
            .render_target_state_observed,
            .render_target_memory_observed,
            .draw_completion_signaled,
            => .xenia_command_processor,
            .draw_completion_dispatched => .xenia_kernel,
            .guest_wait_observed_after_draw,
            .guest_producer_progressed_after_draw,
            => .guest_title,
            .xe_swap_candidate_seen,
            .xe_swap_packet_readable,
            .xe_swap_packet_decoded,
            .fetch_constant_decoded,
            => .ring_memory,
            .authentic_xe_swap_consumed => .xenia_command_processor,
            .issue_swap_entered => .xenia_presenter,
            .output_refresh_succeeded => .xenia_presenter,
            .native_presented => .rosette_presenter,
        };
    }

    pub fn guidance(self: Stage) []const u8 {
        return switch (self) {
            .guest_vdswap_entered => "the title has not entered VdSwap; inspect the guest producer thread and its predecessor rather than the presenter",
            .vdswap_arguments_captured => "VdSwap entry was not accompanied by a captured caller-owned front-buffer/extent; preserve the export arguments before interpreting packet absence",
            .frontbuffer_validated => "no trusted, plausible front-buffer address and extent exist; do not substitute a swap packet that would name nothing",
            .fetch_constant_encoded => "the front-buffer description exists but its six-dword fetch constant is unproven; inspect the VdSwap encoder and the register-write sequence",
            .guest_xe_swap_encoded => "VdSwap arguments and fetch state exist, but the guest-origin XE_SWAP packet has not been observed in the encoder",
            .vdswap_completed => "the guest-origin XE_SWAP was encoded, but VdSwap completion/return is unproven",
            .ring_write_pointer_published => "VdSwap completed, but the caller did not publish the command-buffer write pointer; inspect the producer's post-call control flow",
            .ring_geometry_observed => "the ring was published but its read/write geometry is not known; do not infer an outstanding span from a raw base and size",
            .ring_projection_readable => "ring geometry exists but no trusted physical/virtual projection can be read",
            .pm4_stream_observed => "a readable projection exists but no PM4 packet or dword stream has been observed in the selected span",
            .pm4_stream_validated => "PM4 bytes were observed but the stream has not passed bounded framing validation",
            .pm4_indirects_resolved => "the primary PM4 stream references indirect buffers whose readability, bounds or cycle status is unresolved",
            .pm4_state_programmed => "PM4 packets exist, but no state-programming evidence has been retained for the command processor",
            .draw_submitted => "PM4 state exists, but no guest-owned draw packet has been proven in the submitted stream",
            .draw_consumed => "the guest submitted a draw, but command-processor draw consumption is not proven",
            .render_target_state_observed => "a draw was consumed, but no Xenos color/depth target register state has been observed",
            .render_target_memory_observed => "render-target registers exist, but no EDRAM or resolved render-target memory has been read",
            .draw_completion_signaled => "a draw was consumed, but the Xenos draw-completion event was never queued",
            .draw_completion_dispatched => "draw completion was queued, but no guest interrupt callback dispatch completed",
            .guest_wait_observed_after_draw => "draw work completed without a recorded guest wait at the producer boundary; inspect the title's post-draw handoff",
            .guest_producer_progressed_after_draw => "the producer has not advanced after the first consumed draw; inspect the wait, signal and continuation that should lead to VdSwap",
            .xe_swap_candidate_seen => "the PM4 stream is observable and valid, but no XE_SWAP header/signature candidate has been found",
            .xe_swap_packet_readable => "an XE_SWAP candidate exists, but its complete five-dword payload is not readable",
            .xe_swap_packet_decoded => "an XE_SWAP candidate is readable, but its header/signature/extent did not pass the strict decoder",
            .fetch_constant_decoded => "the XE_SWAP decoded, but its preceding six-dword fetch constant is not proven; format, tiling and pitch remain unknown",
            .authentic_xe_swap_consumed => "a readable packet exists, but authentic command-processor consumption is unproven; generic PM4 consumption does not satisfy this stage",
            .issue_swap_entered => "the command processor consumed XE_SWAP, but CommandProcessor::IssueSwap is unproven",
            .output_refresh_succeeded => "IssueSwap was reached, but the guest-output refresh has not completed",
            .native_presented => "guest output refreshed, but native presentation is still unproven",
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

pub const stage_order = [_]Stage{
    .guest_vdswap_entered,
    .vdswap_arguments_captured,
    .frontbuffer_validated,
    .fetch_constant_encoded,
    .guest_xe_swap_encoded,
    .vdswap_completed,
    .ring_write_pointer_published,
    .ring_geometry_observed,
    .ring_projection_readable,
    .pm4_stream_observed,
    .pm4_stream_validated,
    .pm4_indirects_resolved,
    .pm4_state_programmed,
    .draw_submitted,
    .draw_consumed,
    .render_target_state_observed,
    .render_target_memory_observed,
    .draw_completion_signaled,
    .draw_completion_dispatched,
    .guest_wait_observed_after_draw,
    .guest_producer_progressed_after_draw,
    .xe_swap_candidate_seen,
    .xe_swap_packet_readable,
    .xe_swap_packet_decoded,
    .fetch_constant_decoded,
    .authentic_xe_swap_consumed,
    .issue_swap_entered,
    .output_refresh_succeeded,
    .native_presented,
};

/// The contract is a partial order, not a chain.  `stage_order` is a total
/// order chosen so that a dependency always precedes its dependant, which is
/// what makes `firstGap` cheap — but reporting only `firstGap` claims that the
/// twenty-eight stages behind it are waiting on the first, and most of them are
/// not.  A title that never enters `VdSwap` can still have a readable ring, a
/// validated PM4 stream and consumed draws, and the render-target and
/// completion evidence for those draws is missing for reasons that have nothing
/// to do with the producer.  Splitting the contract into independent chains is
/// what lets each of those be reported against its own owner.
pub const Chain = enum(u8) {
    /// The guest producer deciding to present and encoding the request.
    producer,
    /// Getting the guest's dwords into a form an observer can read.
    transport,
    /// What the command processor did with those dwords: state, draws,
    /// targets, completions, and the guest continuation they should cause.
    raster,
    /// The XE_SWAP packet itself, from candidate byte pattern to authentic
    /// consumption.
    packet,
    /// Turning a consumed swap into pixels on a host surface.
    presentation,

    pub fn label(self: Chain) []const u8 {
        return switch (self) {
            .producer => "producer",
            .transport => "transport",
            .raster => "raster",
            .packet => "packet",
            .presentation => "presentation",
        };
    }

    pub fn meaning(self: Chain) []const u8 {
        return switch (self) {
            .producer => "the title deciding to present and encoding the request",
            .transport => "making the published dwords readable and framed",
            .raster => "what the command processor did with the batch, and what the guest did next",
            .packet => "the XE_SWAP packet from byte pattern to authentic consumption",
            .presentation => "turning a consumed swap into a displayed frame",
        };
    }
};

pub const chain_order = [_]Chain{ .producer, .transport, .raster, .packet, .presentation };
pub const chain_count: usize = chain_order.len;

pub fn chainOf(stage: Stage) Chain {
    return switch (stage) {
        .guest_vdswap_entered,
        .vdswap_arguments_captured,
        .frontbuffer_validated,
        .fetch_constant_encoded,
        .guest_xe_swap_encoded,
        .vdswap_completed,
        => .producer,
        .ring_write_pointer_published,
        .ring_geometry_observed,
        .ring_projection_readable,
        .pm4_stream_observed,
        .pm4_stream_validated,
        .pm4_indirects_resolved,
        => .transport,
        .pm4_state_programmed,
        .draw_submitted,
        .draw_consumed,
        .render_target_state_observed,
        .render_target_memory_observed,
        .draw_completion_signaled,
        .draw_completion_dispatched,
        .guest_wait_observed_after_draw,
        .guest_producer_progressed_after_draw,
        => .raster,
        .xe_swap_candidate_seen,
        .xe_swap_packet_readable,
        .xe_swap_packet_decoded,
        .fetch_constant_decoded,
        .authentic_xe_swap_consumed,
        => .packet,
        .issue_swap_entered,
        .output_refresh_succeeded,
        .native_presented,
        => .presentation,
    };
}

/// The causal prerequisites of a stage: the facts without which this one
/// cannot be true, whatever the total order says.
///
/// These are deliberately narrower than "everything earlier in `stage_order`".
/// `frontbuffer_validated` has no prerequisite because a ring-memory scan can
/// name a valid surface without the title ever entering `VdSwap`, and
/// `ring_write_pointer_published` has none because ring bring-up publishes
/// before any present request exists.  Recording the real prerequisites is what
/// lets an unmet stage be classified as blocked upstream rather than as a wall
/// worth investigating.
pub fn dependencies(stage: Stage) []const Stage {
    return switch (stage) {
        .guest_vdswap_entered => &[_]Stage{},
        .vdswap_arguments_captured => &[_]Stage{.guest_vdswap_entered},
        .frontbuffer_validated => &[_]Stage{},
        .fetch_constant_encoded => &[_]Stage{.frontbuffer_validated},
        .guest_xe_swap_encoded => &[_]Stage{.vdswap_arguments_captured},
        .vdswap_completed => &[_]Stage{.guest_vdswap_entered},
        .ring_write_pointer_published => &[_]Stage{},
        .ring_geometry_observed => &[_]Stage{},
        .ring_projection_readable => &[_]Stage{.ring_geometry_observed},
        .pm4_stream_observed => &[_]Stage{.ring_projection_readable},
        .pm4_stream_validated => &[_]Stage{.pm4_stream_observed},
        .pm4_indirects_resolved => &[_]Stage{.pm4_stream_observed},
        .pm4_state_programmed => &[_]Stage{.pm4_stream_validated},
        .draw_submitted => &[_]Stage{.pm4_stream_validated},
        .draw_consumed => &[_]Stage{.draw_submitted},
        .render_target_state_observed => &[_]Stage{.pm4_state_programmed},
        .render_target_memory_observed => &[_]Stage{.render_target_state_observed},
        .draw_completion_signaled => &[_]Stage{.draw_consumed},
        .draw_completion_dispatched => &[_]Stage{.draw_completion_signaled},
        .guest_wait_observed_after_draw => &[_]Stage{.draw_consumed},
        .guest_producer_progressed_after_draw => &[_]Stage{.draw_consumed},
        .xe_swap_candidate_seen => &[_]Stage{.pm4_stream_observed},
        .xe_swap_packet_readable => &[_]Stage{.xe_swap_candidate_seen},
        .xe_swap_packet_decoded => &[_]Stage{.xe_swap_packet_readable},
        .fetch_constant_decoded => &[_]Stage{.xe_swap_packet_decoded},
        .authentic_xe_swap_consumed => &[_]Stage{.xe_swap_packet_decoded},
        .issue_swap_entered => &[_]Stage{.authentic_xe_swap_consumed},
        .output_refresh_succeeded => &[_]Stage{.issue_swap_entered},
        .native_presented => &[_]Stage{.output_refresh_succeeded},
    };
}

pub fn dependenciesMet(stage: Stage, observed: u32) bool {
    for (dependencies(stage)) |prerequisite| {
        if (observed & stageBit(prerequisite) == 0) return false;
    }
    return true;
}

/// The unmet stages whose prerequisites all hold.  These are the real walls:
/// every other unmet stage is waiting on one of them.  A contract at 10/29 with
/// four actionable gaps is four problems, not nineteen.
pub fn actionableMask(observed: u32) u32 {
    var mask: u32 = 0;
    for (stage_order) |stage| {
        const bit = stageBit(stage);
        if (observed & bit != 0) continue;
        if (dependenciesMet(stage, observed)) mask |= bit;
    }
    return mask;
}

pub fn chainMask(chain: Chain) u32 {
    var mask: u32 = 0;
    for (stage_order) |stage| {
        if (chainOf(stage) == chain) mask |= stageBit(stage);
    }
    return mask;
}

/// The first unmet stage within one chain.  Reported per chain so that a
/// stalled producer does not hide an independently broken raster path.
pub fn chainFrontier(chain: Chain, observed: u32) ?Stage {
    for (stage_order) |stage| {
        if (chainOf(stage) != chain) continue;
        if (observed & stageBit(stage) == 0) return stage;
    }
    return null;
}

pub fn chainObservedCount(chain: Chain, observed: u32) usize {
    var count: usize = 0;
    for (stage_order) |stage| {
        if (chainOf(stage) != chain) continue;
        if (observed & stageBit(stage) != 0) count += 1;
    }
    return count;
}

pub fn chainStageCount(chain: Chain) usize {
    var count: usize = 0;
    for (stage_order) |stage| {
        if (chainOf(stage) == chain) count += 1;
    }
    return count;
}

/// A named evidence-gathering path.  The contract records not only what was
/// observed but which probes were run to look for it, because a stage that is
/// unmet because nothing ever looked is a defect in the observer and a stage
/// that is unmet after a probe read real data is a finding about the title or
/// the emulator.  Those two are indistinguishable in a bare count of zero, and
/// they send a reader to opposite ends of the system.
pub const Probe = enum(u8) {
    /// Instruction-pointer tracepoint on the guest export itself.
    guest_export_tracepoint,
    /// Structured `VDSWAP PATH:` breadcrumbs emitted by the emulator.
    guest_log_breadcrumb,
    /// Caller-owned arguments preserved at the export boundary.
    vdswap_argument_capture,
    /// Ring base/size/read/write geometry recovered from memory mapping.
    ring_geometry_capture,
    /// The physical/biased/unbiased alias survey over the whole ring.
    ring_projection_survey,
    /// The bounded walk over the span the ring pointers describe.
    outstanding_span_scan,
    /// The bounded walk over the batch retained in ring memory after the
    /// command processor drained it.
    retained_batch_scan,
    /// The nested walk that follows INDIRECT_BUFFER references.
    nested_indirect_walk,
    /// The stateful Xenos command-processor execution of a batch.
    stateful_pm4_execution,
    /// The Xenos register file, read after execution.
    xenos_register_file,
    /// Delivery of a queued GPU interrupt to the guest callback.
    interrupt_dispatch,
    /// The ordered causal event ledger.
    causal_event_ledger,
    /// A tracepoint inside the emulator's command processor.
    command_processor_tracepoint,
    /// A tracepoint inside the emulator's presenter.
    presenter_tracepoint,
    /// The Rosette-native presenter's own frame counter.
    native_presenter_counter,
    /// Guest-side progress counters sampled after the first consumed draw.
    guest_progress_counter,

    pub fn label(self: Probe) []const u8 {
        return switch (self) {
            .guest_export_tracepoint => "guest-export-tracepoint",
            .guest_log_breadcrumb => "guest-log-breadcrumb",
            .vdswap_argument_capture => "vdswap-argument-capture",
            .ring_geometry_capture => "ring-geometry-capture",
            .ring_projection_survey => "ring-projection-survey",
            .outstanding_span_scan => "outstanding-span-scan",
            .retained_batch_scan => "retained-batch-scan",
            .nested_indirect_walk => "nested-indirect-walk",
            .stateful_pm4_execution => "stateful-pm4-execution",
            .xenos_register_file => "xenos-register-file",
            .interrupt_dispatch => "interrupt-dispatch",
            .causal_event_ledger => "causal-event-ledger",
            .command_processor_tracepoint => "command-processor-tracepoint",
            .presenter_tracepoint => "presenter-tracepoint",
            .native_presenter_counter => "native-presenter-counter",
            .guest_progress_counter => "guest-progress-counter",
        };
    }
};

pub const probe_count: usize = @typeInfo(Probe).@"enum".fields.len;

/// The probes capable of supplying a stage.  A stage every one of whose probes
/// reports starvation has not been shown to be false; it has been shown to be
/// unobserved, which is a different report with a different owner.
pub fn probesFor(stage: Stage) []const Probe {
    return switch (stage) {
        .guest_vdswap_entered => &[_]Probe{ .guest_export_tracepoint, .guest_log_breadcrumb },
        .vdswap_arguments_captured => &[_]Probe{ .vdswap_argument_capture, .guest_log_breadcrumb },
        .frontbuffer_validated => &[_]Probe{ .vdswap_argument_capture, .guest_log_breadcrumb, .retained_batch_scan, .stateful_pm4_execution },
        .fetch_constant_encoded => &[_]Probe{ .guest_log_breadcrumb, .vdswap_argument_capture },
        .guest_xe_swap_encoded => &[_]Probe{.guest_log_breadcrumb},
        .vdswap_completed => &[_]Probe{ .guest_log_breadcrumb, .guest_export_tracepoint },
        .ring_write_pointer_published => &[_]Probe{ .ring_geometry_capture, .guest_log_breadcrumb },
        .ring_geometry_observed => &[_]Probe{.ring_geometry_capture},
        .ring_projection_readable => &[_]Probe{ .ring_projection_survey, .outstanding_span_scan, .retained_batch_scan, .nested_indirect_walk, .stateful_pm4_execution },
        .pm4_stream_observed => &[_]Probe{ .ring_projection_survey, .outstanding_span_scan, .retained_batch_scan, .nested_indirect_walk, .stateful_pm4_execution },
        .pm4_stream_validated => &[_]Probe{ .ring_projection_survey, .outstanding_span_scan, .retained_batch_scan, .nested_indirect_walk, .stateful_pm4_execution },
        .pm4_indirects_resolved => &[_]Probe{ .nested_indirect_walk, .stateful_pm4_execution, .ring_projection_survey, .outstanding_span_scan },
        .pm4_state_programmed => &[_]Probe{ .stateful_pm4_execution, .causal_event_ledger },
        .draw_submitted => &[_]Probe{ .stateful_pm4_execution, .nested_indirect_walk, .causal_event_ledger },
        .draw_consumed => &[_]Probe{ .stateful_pm4_execution, .causal_event_ledger, .command_processor_tracepoint },
        .render_target_state_observed => &[_]Probe{ .xenos_register_file, .stateful_pm4_execution },
        .render_target_memory_observed => &[_]Probe{ .xenos_register_file, .stateful_pm4_execution },
        .draw_completion_signaled => &[_]Probe{ .stateful_pm4_execution, .xenos_register_file },
        .draw_completion_dispatched => &[_]Probe{.interrupt_dispatch},
        .guest_wait_observed_after_draw => &[_]Probe{.causal_event_ledger},
        .guest_producer_progressed_after_draw => &[_]Probe{ .guest_progress_counter, .causal_event_ledger },
        .xe_swap_candidate_seen => &[_]Probe{ .ring_projection_survey, .outstanding_span_scan, .retained_batch_scan, .nested_indirect_walk, .stateful_pm4_execution },
        .xe_swap_packet_readable => &[_]Probe{ .ring_projection_survey, .outstanding_span_scan, .retained_batch_scan, .stateful_pm4_execution },
        .xe_swap_packet_decoded => &[_]Probe{ .ring_projection_survey, .outstanding_span_scan, .retained_batch_scan, .stateful_pm4_execution },
        .fetch_constant_decoded => &[_]Probe{ .stateful_pm4_execution, .xenos_register_file, .outstanding_span_scan, .retained_batch_scan },
        .authentic_xe_swap_consumed => &[_]Probe{ .stateful_pm4_execution, .command_processor_tracepoint, .guest_log_breadcrumb },
        .issue_swap_entered => &[_]Probe{ .presenter_tracepoint, .guest_log_breadcrumb },
        .output_refresh_succeeded => &[_]Probe{ .presenter_tracepoint, .guest_log_breadcrumb },
        .native_presented => &[_]Probe{ .native_presenter_counter, .presenter_tracepoint },
    };
}

/// What one run of a probe achieved.  The distinction that matters is between
/// the outcomes that carry information about the subject and the ones that
/// carry information only about the observer.
pub const ProbeOutcome = enum(u8) {
    /// The probe has never run in this session.
    not_attempted,
    /// The probe ran and could not obtain its input at all: memory it needed
    /// was unmapped, a projection was unreadable, geometry was unknown.
    input_unavailable,
    /// The probe ran against a well-formed but empty input — a zero-length
    /// span, a batch of zero dwords.  It looked at nothing and therefore
    /// found nothing.
    input_empty,
    /// The probe declined by owner rule rather than by failure: performing it
    /// would have satisfied a clause on the title's behalf.
    refused_by_owner,
    /// The probe read real data and the fact was genuinely absent.  This is
    /// the only negative outcome that is evidence about the title or the
    /// emulator rather than about Rosette.
    negative,
    /// The probe observed the fact.
    observed,

    pub fn label(self: ProbeOutcome) []const u8 {
        return switch (self) {
            .not_attempted => "not-attempted",
            .input_unavailable => "input-unavailable",
            .input_empty => "input-empty",
            .refused_by_owner => "refused-by-owner",
            .negative => "negative",
            .observed => "observed",
        };
    }

    /// True when the outcome says something about the subject rather than
    /// about whether the observation could be made.
    pub fn isEvidence(self: ProbeOutcome) bool {
        return self == .negative or self == .observed;
    }

    /// True when the probe produced no information because it could not run
    /// or had nothing to run on.
    pub fn isStarved(self: ProbeOutcome) bool {
        return self == .not_attempted or self == .input_unavailable or self == .input_empty;
    }
};

/// Why one unmet stage is unmet.  Every stage in a report carries one of these
/// so a reader can separate the stages that are waiting on something else from
/// the ones nobody looked at from the ones that are real findings.
pub const Attribution = enum(u8) {
    /// The stage is observed.
    met,
    /// A causal prerequisite is unmet.  Nothing can be concluded about this
    /// stage yet and no work should be aimed at it.
    blocked_upstream,
    /// Prerequisites hold and no probe for this stage has ever run.
    unprobed,
    /// Prerequisites hold, probes ran, and every one of them was starved of
    /// input.  This is a defect in the observer, not a fact about the title.
    starved,
    /// Prerequisites hold and at least one probe read real data and did not
    /// find the fact.  This is a genuine finding, and its owner is the stage's
    /// owner.
    actionable,

    pub fn label(self: Attribution) []const u8 {
        return switch (self) {
            .met => "met",
            .blocked_upstream => "blocked-upstream",
            .unprobed => "unprobed",
            .starved => "starved",
            .actionable => "actionable",
        };
    }

    pub fn guidance(self: Attribution) []const u8 {
        return switch (self) {
            .met => "observed",
            .blocked_upstream => "a prerequisite is unmet; this stage is downstream and carries no independent finding yet",
            .unprobed => "the prerequisites hold and no probe for this stage has ever run; the zero is Rosette's, not the title's",
            .starved => "every probe for this stage ran without input; the stage has not been shown false, only unobserved — repair the probe before reading the absence as a finding",
            .actionable => "a probe read real data and the fact was absent; this is a genuine finding against the stage owner",
        };
    }
};

pub fn stageBit(stage: Stage) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(stage)));
}

pub fn firstGap(observed: u32) ?Stage {
    for (stage_order) |stage| {
        if (observed & stageBit(stage) == 0) return stage;
    }
    return null;
}

pub fn observedCount(observed: u32) usize {
    var count: usize = 0;
    for (stage_order) |stage| {
        if (observed & stageBit(stage) != 0) count += 1;
    }
    return count;
}

pub const Owner = enum(u8) {
    guest_title,
    xenia_kernel,
    ring_memory,
    xenia_command_processor,
    xenia_presenter,
    rosette_presenter,
    evidence,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .guest_title => "guest:title",
            .xenia_kernel => "xenia:kernel",
            .ring_memory => "ring:memory",
            .xenia_command_processor => "xenia:command-processor",
            .xenia_presenter => "xenia:presenter",
            .rosette_presenter => "rosette:presenter",
            .evidence => "evidence:arbitration",
        };
    }
};

/// Where a fact came from.  A source is not a truth level by itself; the
/// runtime ledger keeps source provenance so a log line can say whether a
/// claim came from a guest tracepoint, retained memory or a diagnostic scan.
pub const Source = enum(u5) {
    none,
    guest_tracepoint,
    guest_log,
    vdswap_argument_capture,
    ring_memory_scan,
    nested_pm4_walk,
    stateful_pm4_executor,
    guest_publication,
    command_processor_tracepoint,
    issue_swap_tracepoint,
    output_refresh_tracepoint,
    native_present_tracepoint,
    memory_mapping,
    diagnostic_substitution,
    causal_trace,
    xenos_runtime,
    interrupt_dispatch,
    guest_progress,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .none => "none",
            .guest_tracepoint => "guest-tracepoint",
            .guest_log => "guest-log",
            .vdswap_argument_capture => "vdswap-arguments",
            .ring_memory_scan => "ring-memory-scan",
            .nested_pm4_walk => "nested-pm4-walk",
            .stateful_pm4_executor => "stateful-pm4-executor",
            .guest_publication => "guest-publication",
            .command_processor_tracepoint => "command-processor-tracepoint",
            .issue_swap_tracepoint => "issue-swap-tracepoint",
            .output_refresh_tracepoint => "output-refresh-tracepoint",
            .native_present_tracepoint => "native-present-tracepoint",
            .memory_mapping => "memory-mapping",
            .diagnostic_substitution => "diagnostic-substitution",
            .causal_trace => "causal-trace",
            .xenos_runtime => "xenos-runtime",
            .interrupt_dispatch => "interrupt-dispatch",
            .guest_progress => "guest-progress",
        };
    }

    /// More direct evidence wins only when the facts otherwise describe the
    /// same object.  This ranking is not used to hide disagreements: the
    /// runtime still increments its conflict counter when two valid sources
    /// name different surfaces.
    pub fn strength(self: Source) u8 {
        return switch (self) {
            .none => 0,
            .diagnostic_substitution => 1,
            .ring_memory_scan => 2,
            .nested_pm4_walk => 3,
            .guest_log => 4,
            .guest_tracepoint => 5,
            .vdswap_argument_capture => 6,
            .guest_publication => 7,
            .stateful_pm4_executor => 8,
            .command_processor_tracepoint => 9,
            .issue_swap_tracepoint => 10,
            .output_refresh_tracepoint => 11,
            .native_present_tracepoint => 12,
            .memory_mapping => 2,
            .causal_trace => 7,
            .xenos_runtime => 8,
            .interrupt_dispatch => 9,
            .guest_progress => 7,
        };
    }
};

/// The probe a runtime `Source` corresponds to.  Every positive observation
/// already names its source, so mapping the two vocabularies here lets the
/// ledger record an `observed` probe outcome without the caller repeating
/// itself — and keeps the negative and starved outcomes, which have no source
/// because nothing was found, as the only ones a caller must record by hand.
///
/// `none` and `diagnostic_substitution` map to nothing on purpose: neither is
/// an observation of the guest, and crediting a probe for either would let a
/// substituted frame close a stage that nothing looked at.
pub fn probeForSource(source: Source) ?Probe {
    return switch (source) {
        .none, .diagnostic_substitution => null,
        .guest_tracepoint => .guest_export_tracepoint,
        .guest_log => .guest_log_breadcrumb,
        .vdswap_argument_capture => .vdswap_argument_capture,
        .ring_memory_scan => .ring_projection_survey,
        .nested_pm4_walk => .nested_indirect_walk,
        .stateful_pm4_executor => .stateful_pm4_execution,
        .guest_publication => .ring_geometry_capture,
        .command_processor_tracepoint => .command_processor_tracepoint,
        .issue_swap_tracepoint, .output_refresh_tracepoint => .presenter_tracepoint,
        .native_present_tracepoint => .native_presenter_counter,
        .memory_mapping => .ring_geometry_capture,
        .causal_trace => .causal_event_ledger,
        .xenos_runtime => .xenos_register_file,
        .interrupt_dispatch => .interrupt_dispatch,
        .guest_progress => .guest_progress_counter,
    };
}

pub const Blocker = enum(u8) {
    none,
    vdswap_not_entered,
    arguments_not_captured,
    frontbuffer_unknown,
    frontbuffer_invalid,
    frontbuffer_conflict,
    fetch_not_encoded,
    guest_packet_not_encoded,
    vdswap_not_completed,
    publication_not_observed,
    ring_geometry_missing,
    ring_projection_unreadable,
    pm4_stream_missing,
    pm4_stream_malformed,
    pm4_indirect_unresolved,
    xe_swap_candidate_missing,
    packet_not_readable,
    packet_malformed,
    packet_truncated,
    packet_decode_unproven,
    fetch_decode_unproven,
    pm4_state_unreconstructed,
    draw_submission_missing,
    draw_consumption_unproven,
    render_target_state_missing,
    render_target_memory_missing,
    draw_completion_not_signaled,
    draw_completion_not_dispatched,
    guest_wait_after_draw_missing,
    producer_progress_after_draw_missing,
    authentic_consumption_missing,
    issue_swap_missing,
    output_refresh_missing,
    native_presentation_missing,
    evidence_conflict,

    pub fn label(self: Blocker) []const u8 {
        return switch (self) {
            .none => "none",
            .vdswap_not_entered => "guest_vdswap_not_entered",
            .arguments_not_captured => "vdswap_arguments_not_captured",
            .frontbuffer_unknown => "frontbuffer_unknown",
            .frontbuffer_invalid => "frontbuffer_invalid",
            .frontbuffer_conflict => "frontbuffer_conflict",
            .fetch_not_encoded => "fetch_constant_not_encoded",
            .guest_packet_not_encoded => "guest_xe_swap_not_encoded",
            .vdswap_not_completed => "vdswap_not_completed",
            .publication_not_observed => "ring_write_pointer_not_published",
            .ring_geometry_missing => "ring_geometry_not_observed",
            .ring_projection_unreadable => "ring_projection_not_readable",
            .pm4_stream_missing => "pm4_stream_not_observed",
            .pm4_stream_malformed => "pm4_stream_not_validated",
            .pm4_indirect_unresolved => "pm4_indirect_buffers_unresolved",
            .xe_swap_candidate_missing => "xe_swap_candidate_not_seen",
            .packet_not_readable => "xe_swap_packet_not_readable",
            .packet_malformed => "xe_swap_packet_malformed",
            .packet_truncated => "xe_swap_packet_truncated",
            .packet_decode_unproven => "xe_swap_packet_decode_unproven",
            .fetch_decode_unproven => "fetch_constant_decode_unproven",
            .pm4_state_unreconstructed => "pm4_state_not_reconstructed",
            .draw_submission_missing => "draw_not_submitted",
            .draw_consumption_unproven => "draw_not_consumed",
            .render_target_state_missing => "render_target_state_not_observed",
            .render_target_memory_missing => "render_target_memory_not_observed",
            .draw_completion_not_signaled => "draw_completion_not_signaled",
            .draw_completion_not_dispatched => "draw_completion_not_dispatched",
            .guest_wait_after_draw_missing => "guest_wait_after_draw_not_observed",
            .producer_progress_after_draw_missing => "producer_progress_after_draw_not_observed",
            .authentic_consumption_missing => "authentic_xe_swap_not_consumed",
            .issue_swap_missing => "issue_swap_not_entered",
            .output_refresh_missing => "output_refresh_not_observed",
            .native_presentation_missing => "native_presentation_not_observed",
            .evidence_conflict => "evidence_conflict",
        };
    }

    pub fn owner(self: Blocker) Owner {
        return switch (self) {
            .none => .evidence,
            .vdswap_not_entered,
            .arguments_not_captured,
            .frontbuffer_unknown,
            .frontbuffer_invalid,
            .frontbuffer_conflict,
            .fetch_not_encoded,
            .guest_packet_not_encoded,
            .vdswap_not_completed,
            .publication_not_observed,
            => .guest_title,
            .ring_geometry_missing, .ring_projection_unreadable, .pm4_stream_missing, .pm4_stream_malformed, .pm4_indirect_unresolved, .xe_swap_candidate_missing, .packet_not_readable, .packet_malformed, .packet_truncated, .packet_decode_unproven, .evidence_conflict => .evidence,
            .fetch_decode_unproven,
            .pm4_state_unreconstructed,
            .render_target_state_missing,
            .render_target_memory_missing,
            => .evidence,
            .draw_submission_missing,
            .guest_wait_after_draw_missing,
            .producer_progress_after_draw_missing,
            => .guest_title,
            .draw_consumption_unproven,
            .draw_completion_not_signaled,
            => .xenia_command_processor,
            .draw_completion_not_dispatched => .xenia_kernel,
            .authentic_consumption_missing => .xenia_command_processor,
            .issue_swap_missing,
            .output_refresh_missing,
            => .xenia_presenter,
            .native_presentation_missing => .rosette_presenter,
        };
    }

    pub fn guidance(self: Blocker) []const u8 {
        return switch (self) {
            .none => "the VdSwap contract is complete",
            .vdswap_not_entered => "the title never entered VdSwap; inspect the guest producer frontier",
            .arguments_not_captured => "capture the caller-owned VdSwap arguments before attempting any packet handoff",
            .frontbuffer_unknown => "no front buffer address and extent are known, so a swap packet would name nothing and the command processor would assert on it",
            .frontbuffer_invalid => "a front-buffer candidate was observed but its address or extent is implausible; refuse substitution until the producer names a valid surface",
            .frontbuffer_conflict => "independent sources name different valid front buffers; stop and reconcile physical address, extent and fetch provenance",
            .fetch_not_encoded => "the surface is known but the six-dword fetch constant that carries tiling, format and pitch is missing",
            .guest_packet_not_encoded => "VdSwap entry is not enough; prove that the guest encoder wrote the XE_SWAP packet",
            .vdswap_not_completed => "the guest encoder was entered but the export has not returned to its caller",
            .publication_not_observed => "the caller-owned packet exists only in a local/reserved region until the guest advances CP_RB_WPTR",
            .ring_geometry_missing => "the ring base/size is known but read and write pointers are not; capture CP_RB_RPTR and CP_RB_WPTR before classifying the outstanding span",
            .ring_projection_unreadable => "ring geometry exists but none of the physical, biased virtual or unbiased virtual projections can be read",
            .pm4_stream_missing => "a ring projection is readable but no PM4 stream evidence was retained; preserve the dwords and packet boundaries before deciding the guest did not submit",
            .pm4_stream_malformed => "the observed PM4 span contains a truncated, desynchronised or malformed packet; repair publication ordering or the producer's packet framing before looking at presentation",
            .pm4_indirect_unresolved => "the primary stream points at indirect buffers that are unreadable, invalid, cyclic, depth-limited or budget-limited; resolve those guest ranges before declaring no draw or no swap",
            .xe_swap_candidate_missing => "the PM4 stream is valid and its indirects are accounted for, but no XE_SWAP header/signature candidate exists; this is upstream of packet readability and the presenter",
            .packet_not_readable => "the published packet is not readable through any trusted ring projection",
            .packet_malformed => "ring bytes were found but the PM4 header, signature, count or extent failed strict validation",
            .packet_truncated => "the PM4 span ended inside a candidate packet; wait for a stable publication or inspect the producer's reservation and write-pointer ordering",
            .packet_decode_unproven => "a nested walker saw an XE_SWAP opcode, but it did not retain enough contiguous payload to validate the signature and front-buffer extent",
            .fetch_decode_unproven => "the XE_SWAP payload is valid but the fetch constant that describes its image layout is absent or undecodable; do not present pixels with guessed format or pitch",
            .pm4_state_unreconstructed => "PM4 packet classes are known, but no register-state reconstruction has shown the Xenos draw state that feeds a surface",
            .draw_submission_missing => "PM4 state is present, but no guest-owned draw was submitted before the presentation handoff",
            .draw_consumption_unproven => "the guest submitted a draw, but no command-processor boundary proves that draw was consumed",
            .render_target_state_missing => "a draw was consumed, but color/depth target registers were not observed; the framebuffer destination is still unknown",
            .render_target_memory_missing => "render-target registers are known, but no EDRAM or resolved image memory has been observed",
            .draw_completion_not_signaled => "the command processor consumed a draw without queuing its completion event; inspect event generation and PM4 completion semantics",
            .draw_completion_not_dispatched => "a draw completion exists in the host queue, but the guest graphics callback did not receive it",
            .guest_wait_after_draw_missing => "the first draw completed without a recorded post-draw guest wait; inspect the producer continuation and VdSwap call path",
            .producer_progress_after_draw_missing => "the guest producer did not advance after its first consumed draw; inspect the signal, wait and continuation that should publish VdSwap",
            .authentic_consumption_missing => "generic PM4 consumption is insufficient; prove that this guest-origin XE_SWAP reached the command processor",
            .issue_swap_missing => "the command processor decoded the packet but IssueSwap has not been reached",
            .output_refresh_missing => "IssueSwap ran but the guest-output refresh did not complete",
            .native_presentation_missing => "guest output exists but the native presenter has not displayed it",
            .evidence_conflict => "the sources disagree; preserve both observations and resolve provenance before forwarding pixels",
        };
    }
};

/// Immutable packet facts shared by the ring decoder and the runtime ledger.
pub const xe_swap_opcode: u8 = 0x64;
pub const xe_swap_body_dwords: u8 = 4;
pub const xe_swap_packet_dwords: u8 = 5;
pub const swap_signature: u32 = 0x5357_4150;
pub const fetch_register: u16 = 0x4800;
pub const fetch_dwords: u8 = 6;
pub const reservation_dwords: u8 = 64;

pub fn isPlausibleFrontBuffer(address: u32, width: u32, height: u32) bool {
    return address != 0 and width >= 64 and height >= 64 and width <= 4096 and height <= 4096;
}

pub fn packetShapeIsValid(header_type: u2, opcode: u8, body_dwords: u32, signature: u32) bool {
    return header_type == 3 and opcode == xe_swap_opcode and
        body_dwords == xe_swap_body_dwords and signature == swap_signature;
}

pub fn contractIsWellFormed() bool {
    if (stage_order.len != stage_count) return false;
    if (xe_swap_opcode != 0x64 or xe_swap_body_dwords != 4) return false;
    if (fetch_dwords != 6 or reservation_dwords < xe_swap_packet_dwords) return false;
    if (!isPlausibleFrontBuffer(0x1FC0_0000, 1280, 720)) return false;
    if (isPlausibleFrontBuffer(0, 1280, 720)) return false;
    if (firstGap(0) != .guest_vdswap_entered) return false;

    // The partial order must be a DAG whose edges all point backwards through
    // `stage_order`.  That is what makes `dependenciesMet` terminate without a
    // visited set and what guarantees `actionableMask` is never empty while
    // stages remain unmet: if every unmet stage had an unmet prerequisite there
    // would be a cycle, and the report would name no wall at all.
    var covered: u32 = 0;
    for (stage_order) |stage| {
        const bit = stageBit(stage);
        for (dependencies(stage)) |prerequisite| {
            if (prerequisite == stage) return false;
            if (covered & stageBit(prerequisite) == 0) return false;
        }
        if (probesFor(stage).len == 0) return false;
        covered |= bit;
    }
    if (covered != stageBit(.native_presented) | (stageBit(.native_presented) - 1)) return false;

    // Every stage belongs to exactly one chain, and the chains partition the
    // contract.  A stage missing from every chain would silently vanish from
    // the per-chain report while still counting against `met`.
    var chain_total: usize = 0;
    var chain_union: u32 = 0;
    for (chain_order) |chain| {
        const mask = chainMask(chain);
        if (chain_union & mask != 0) return false;
        chain_union |= mask;
        chain_total += chainStageCount(chain);
    }
    if (chain_total != stage_count or chain_union != covered) return false;

    // An empty contract has exactly one wall, and it is the producer's.
    if (actionableMask(0) == 0) return false;
    if (actionableMask(covered) != 0) return false;
    return true;
}

test "the VdSwap stage order covers every stage exactly once" {
    var mask: u32 = 0;
    for (stage_order) |stage| {
        const bit = stageBit(stage);
        try std.testing.expect(mask & bit == 0);
        mask |= bit;
    }
    try std.testing.expectEqual(stage_count, observedCount(mask));
    try std.testing.expect(firstGap(mask) == null);
}

test "generic PM4 is not the authentic XE_SWAP stage" {
    var mask = stageBit(.guest_vdswap_entered) |
        stageBit(.vdswap_arguments_captured) |
        stageBit(.frontbuffer_validated) |
        stageBit(.fetch_constant_encoded) |
        stageBit(.guest_xe_swap_encoded) |
        stageBit(.vdswap_completed) |
        stageBit(.ring_write_pointer_published) |
        stageBit(.ring_geometry_observed) |
        stageBit(.ring_projection_readable) |
        stageBit(.pm4_stream_observed) |
        stageBit(.pm4_stream_validated) |
        stageBit(.pm4_indirects_resolved) |
        stageBit(.pm4_state_programmed) |
        stageBit(.draw_submitted) |
        stageBit(.draw_consumed) |
        stageBit(.render_target_state_observed) |
        stageBit(.render_target_memory_observed) |
        stageBit(.draw_completion_signaled) |
        stageBit(.draw_completion_dispatched) |
        stageBit(.guest_wait_observed_after_draw) |
        stageBit(.guest_producer_progressed_after_draw) |
        stageBit(.xe_swap_candidate_seen) |
        stageBit(.xe_swap_packet_readable) |
        stageBit(.xe_swap_packet_decoded) |
        stageBit(.fetch_constant_decoded);
    try std.testing.expectEqual(Stage.authentic_xe_swap_consumed, firstGap(mask).?);
    mask |= stageBit(.authentic_xe_swap_consumed);
    try std.testing.expectEqual(Stage.issue_swap_entered, firstGap(mask).?);
}

test "packet shape rejects a signature with the wrong PM4 opcode" {
    try std.testing.expect(packetShapeIsValid(3, xe_swap_opcode, xe_swap_body_dwords, swap_signature));
    try std.testing.expect(!packetShapeIsValid(3, 0x22, xe_swap_body_dwords, swap_signature));
    try std.testing.expect(!packetShapeIsValid(3, xe_swap_opcode, 3, swap_signature));
    try std.testing.expect(!packetShapeIsValid(3, xe_swap_opcode, xe_swap_body_dwords, 0));
}

test "every blocker has an owner and actionable guidance" {
    inline for (@typeInfo(Blocker).@"enum".fields) |field| {
        const blocker: Blocker = @enumFromInt(field.value);
        try std.testing.expect(blocker.label().len != 0);
        try std.testing.expect(blocker.guidance().len > 20);
        _ = blocker.owner();
    }
}

test "the intermediary stages are distinct from swap authenticity" {
    const mask = stageBit(.pm4_state_programmed) |
        stageBit(.draw_submitted) |
        stageBit(.draw_consumed);
    try std.testing.expect(mask & stageBit(.render_target_state_observed) == 0);
    try std.testing.expect(mask & stageBit(.authentic_xe_swap_consumed) == 0);
    try std.testing.expectEqual(Stage.guest_vdswap_entered, firstGap(mask).?);
}

test "the chains partition the contract and each names its own frontier" {
    var seen: u32 = 0;
    var total: usize = 0;
    for (chain_order) |chain| {
        const mask = chainMask(chain);
        try std.testing.expect(mask != 0);
        try std.testing.expectEqual(@as(u32, 0), seen & mask);
        seen |= mask;
        total += chainStageCount(chain);
    }
    try std.testing.expectEqual(stage_count, total);
    try std.testing.expectEqual(stage_count, observedCount(seen));

    try std.testing.expectEqual(Stage.guest_vdswap_entered, chainFrontier(.producer, 0).?);
    try std.testing.expectEqual(Stage.ring_write_pointer_published, chainFrontier(.transport, 0).?);
    try std.testing.expectEqual(Stage.pm4_state_programmed, chainFrontier(.raster, 0).?);
    try std.testing.expectEqual(Stage.xe_swap_candidate_seen, chainFrontier(.packet, 0).?);
    try std.testing.expectEqual(Stage.issue_swap_entered, chainFrontier(.presentation, 0).?);
    for (chain_order) |chain| try std.testing.expect(chainFrontier(chain, seen) == null);
}

test "a stalled producer does not hide an independently reached transport chain" {
    // The observed mask from a run whose title never presented: the whole
    // transport chain is met and the producer chain is empty.  The linear
    // frontier reports the producer, which is correct and says nothing about
    // the six transport stages that did happen.
    const observed = chainMask(.transport);
    try std.testing.expectEqual(Stage.guest_vdswap_entered, firstGap(observed).?);
    try std.testing.expect(chainFrontier(.transport, observed) == null);
    try std.testing.expectEqual(
        chainStageCount(.transport),
        chainObservedCount(.transport, observed),
    );
    try std.testing.expectEqual(@as(usize, 0), chainObservedCount(.producer, observed));
}

test "dependencies point backwards and are narrower than the total order" {
    var covered: u32 = 0;
    for (stage_order) |stage| {
        for (dependencies(stage)) |prerequisite| {
            try std.testing.expect(prerequisite != stage);
            try std.testing.expect(covered & stageBit(prerequisite) != 0);
        }
        covered |= stageBit(stage);
    }
    // A ring scan can name a valid surface without the title entering VdSwap,
    // and ring bring-up publishes before any present request exists.  Treating
    // the total order as the dependency graph would make both unreachable.
    try std.testing.expectEqual(@as(usize, 0), dependencies(.frontbuffer_validated).len);
    try std.testing.expectEqual(@as(usize, 0), dependencies(.ring_write_pointer_published).len);
    try std.testing.expectEqual(@as(usize, 0), dependencies(.ring_geometry_observed).len);
}

test "the actionable set collapses nineteen unmet stages into their real walls" {
    // The 2026-08-25 Halo 3 reading: publication, geometry, projection, stream,
    // validation, indirects, state, draw submitted, draw consumed and the
    // post-draw guest wait are met; nineteen stages are not.
    const observed = stageBit(.ring_write_pointer_published) |
        stageBit(.ring_geometry_observed) |
        stageBit(.ring_projection_readable) |
        stageBit(.pm4_stream_observed) |
        stageBit(.pm4_stream_validated) |
        stageBit(.pm4_indirects_resolved) |
        stageBit(.pm4_state_programmed) |
        stageBit(.draw_submitted) |
        stageBit(.draw_consumed) |
        stageBit(.guest_wait_observed_after_draw);
    try std.testing.expectEqual(@as(usize, 10), observedCount(observed));
    try std.testing.expectEqual(@as(usize, 19), stage_count - observedCount(observed));

    const actionable = actionableMask(observed);
    // Six walls, not nineteen: the producer entry, the front buffer, the
    // render target, the completion signal, the producer's continuation and
    // the swap candidate.  Everything else is downstream of one of these.
    try std.testing.expectEqual(@as(usize, 6), observedCount(actionable));
    try std.testing.expect(actionable & stageBit(.guest_vdswap_entered) != 0);
    try std.testing.expect(actionable & stageBit(.frontbuffer_validated) != 0);
    try std.testing.expect(actionable & stageBit(.render_target_state_observed) != 0);
    try std.testing.expect(actionable & stageBit(.draw_completion_signaled) != 0);
    try std.testing.expect(actionable & stageBit(.guest_producer_progressed_after_draw) != 0);
    try std.testing.expect(actionable & stageBit(.xe_swap_candidate_seen) != 0);

    // The stages the single linear frontier would have sent a reader to are
    // exactly the ones that carry no independent finding.
    try std.testing.expect(actionable & stageBit(.vdswap_arguments_captured) == 0);
    try std.testing.expect(actionable & stageBit(.authentic_xe_swap_consumed) == 0);
    try std.testing.expect(actionable & stageBit(.native_presented) == 0);
    for (stage_order) |stage| {
        if (observed & stageBit(stage) != 0) continue;
        if (actionable & stageBit(stage) != 0) {
            try std.testing.expect(dependenciesMet(stage, observed));
        } else {
            try std.testing.expect(!dependenciesMet(stage, observed));
        }
    }
}

test "probe outcomes separate observer defects from findings" {
    try std.testing.expect(ProbeOutcome.negative.isEvidence());
    try std.testing.expect(ProbeOutcome.observed.isEvidence());
    try std.testing.expect(!ProbeOutcome.input_empty.isEvidence());
    try std.testing.expect(!ProbeOutcome.not_attempted.isEvidence());
    try std.testing.expect(ProbeOutcome.input_empty.isStarved());
    try std.testing.expect(ProbeOutcome.input_unavailable.isStarved());
    try std.testing.expect(ProbeOutcome.not_attempted.isStarved());
    // A refusal is neither: the observation was possible and was declined by
    // owner rule, which is a policy fact rather than a missing capability.
    try std.testing.expect(!ProbeOutcome.refused_by_owner.isEvidence());
    try std.testing.expect(!ProbeOutcome.refused_by_owner.isStarved());

    for (stage_order) |stage| {
        const probes = probesFor(stage);
        try std.testing.expect(probes.len != 0);
        for (probes) |one| try std.testing.expect(one.label().len != 0);
    }
}

test "every attribution has guidance and every chain has meaning" {
    inline for (@typeInfo(Attribution).@"enum".fields) |field| {
        const attribution: Attribution = @enumFromInt(field.value);
        try std.testing.expect(attribution.label().len != 0);
        try std.testing.expect(attribution.guidance().len != 0);
    }
    inline for (@typeInfo(Chain).@"enum".fields) |field| {
        const chain: Chain = @enumFromInt(field.value);
        try std.testing.expect(chain.label().len != 0);
        try std.testing.expect(chain.meaning().len > 20);
    }
    try std.testing.expect(contractIsWellFormed());
}

test "every source that observes the guest maps to a probe" {
    inline for (@typeInfo(Source).@"enum".fields) |field| {
        const source: Source = @enumFromInt(field.value);
        const mapped = probeForSource(source);
        switch (source) {
            // Neither is an observation of the guest. Crediting a probe for a
            // substituted frame would close a stage nothing looked at.
            .none, .diagnostic_substitution => try std.testing.expect(mapped == null),
            else => try std.testing.expect(mapped != null),
        }
    }
    // A source strong enough to close a stage must be able to name the probe
    // that closed it, or the stage would read `met` with every probe still
    // sitting at `not_attempted`.
    try std.testing.expectEqual(Probe.stateful_pm4_execution, probeForSource(.stateful_pm4_executor).?);
    try std.testing.expectEqual(Probe.xenos_register_file, probeForSource(.xenos_runtime).?);
}
