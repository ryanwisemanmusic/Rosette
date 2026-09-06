//! Runtime evidence ledger for the guest VdSwap -> PM4_XE_SWAP boundary.
//!
//! The static vocabulary lives in `pkg/common/xenia/vd-swap-contract`.  This
//! file owns mutable observations: where a front buffer came from, which ring
//! projections contained a candidate packet, whether that packet passed the
//! strict decoder, and which boundary actually consumed it.  It never writes
//! a guest packet and it never treats a generic PM4 draw as a swap.

const std = @import("std");
const pm4 = @import("pm4.zig");
const probe_ledger = @import("vd_swap_probe.zig");
const contract = @import("xenia_vd_swap_contract");

pub const Stage = contract.Stage;
pub const Chain = contract.Chain;
pub const Probe = contract.Probe;
pub const ProbeOutcome = contract.ProbeOutcome;
pub const StarvationCause = contract.StarvationCause;
pub const StarvationOwner = contract.StarvationOwner;
pub const Attribution = contract.Attribution;
pub const ProbeLedger = probe_ledger.Ledger;
pub const StageDiagnosis = probe_ledger.StageDiagnosis;
pub const DiagnosisSummary = probe_ledger.Summary;
pub const Owner = contract.Owner;
pub const Source = contract.Source;
pub const Blocker = contract.Blocker;

pub const stage_count = contract.stage_count;

/// Pure helpers re-exported so callers do not have to import the package
/// separately to ask a question the ledger already depends on.
pub const stageBit = contract.stageBit;
pub const probesFor = contract.probesFor;
pub const dependencies = contract.dependencies;
pub const chainStageCount = contract.chainStageCount;
pub const chainOf = contract.chainOf;
pub const observedCount = contract.observedCount;

pub const max_frontbuffer_candidates: usize = 8;

pub const Arguments = struct {
    frontbuffer: ?pm4.SwapDescription = null,
    /// The guest pointer passed by the title.  This is intentionally not
    /// treated as a physical surface address; VdSwap may translate it before
    /// encoding the packet.
    frontbuffer_pointer: u32 = 0,
    fetch: ?pm4.FetchConstant = null,
    command_buffer: u32 = 0,
    fetch_pointer: u32 = 0,
    reservation_dwords: u32 = 0,
    guest_pc: u64 = 0,
    thread_id: u64 = 0,
};

pub const Candidate = struct {
    description: ?pm4.SwapDescription = null,
    source: Source = .none,
    first_step: u64 = 0,
    observations: u64 = 0,
    plausible: bool = false,
};

pub const StageObservation = struct {
    seen: bool = false,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    source_mask: u32 = 0,
};

pub const PacketObservation = struct {
    /// A complete five-dword XE_SWAP candidate payload is readable. This is
    /// deliberately not the same fact as a readable ring projection: a ring
    /// can be readable while containing only ordinary PM4 state/draw packets.
    readable: bool = false,
    /// A physical/virtual ring projection was translated and bounds checked.
    projection_readable: bool = false,
    /// At least one PM4 dword or packet was observed in the supplied span.
    stream_observed: bool = false,
    /// The bounded PM4 walk completed without a truncation, desynchronisation
    /// or malformed packet affecting the observed stream.
    stream_validated: bool = false,
    /// All indirect-buffer references in the observed walk were accounted for.
    indirects_resolved: bool = false,
    /// An XE_SWAP header/signature candidate was found, even if its payload is
    /// incomplete or fails strict decoding.
    candidate_seen: bool = false,
    /// The span contained a packet that passed the PM4 header and XE_SWAP
    /// payload checks. This is intentionally separate from `readable`.
    decoded: bool = false,
    /// The scan saw a candidate XE_SWAP description.  A candidate is still
    /// not authentic consumption until `authentic_consumption` is true.
    swap: ?pm4.SwapDescription = null,
    fetch: ?pm4.FetchConstant = null,
    root_packets: u64 = 0,
    nested_packets: u64 = 0,
    indirect_packets: u64 = 0,
    draw_packets: u64 = 0,
    swap_packets: u64 = 0,
    malformed_packets: u64 = 0,
    truncated: bool = false,
    desynchronised: bool = false,
    unknown_opcodes: u64 = 0,
    zero_dwords: u64 = 0,
    dwords_examined: u64 = 0,
    dwords_scanned: u64 = 0,
    span_dwords: u64 = 0,
    unreadable_references: u64 = 0,
    packet_offset: ?u32 = null,
    /// Only a command-processor execution boundary or a provenance-bearing
    /// Xenia milestone may set this.  A retained ring scan must leave it false.
    authentic_consumption: bool = false,
    /// The fetch constant immediately preceding the decoded XE_SWAP was
    /// retained and decoded, rather than merely named by a guest breadcrumb.
    fetch_decoded: bool = false,
};

/// Evidence between a decoded PM4 stream and a present request.  These facts
/// are intentionally independent: a draw can be consumed without a target
/// register state, a target can be programmed without an EDRAM resolve, and a
/// completion event can be queued without the guest callback receiving it.
/// Keeping the distinctions here prevents the contract from treating
/// `draws != 0` as proof that a frame can be displayed.
pub const IntermediaryEvidence = struct {
    pm4_state_programmed: bool = false,
    draw_submitted: bool = false,
    draw_consumed: bool = false,
    render_target_state_observed: bool = false,
    render_target_memory_observed: bool = false,
    draw_completion_signaled: bool = false,
    draw_completion_dispatched: bool = false,
    guest_wait_observed_after_draw: bool = false,
    guest_producer_progressed_after_draw: bool = false,
};

pub const Frontier = struct {
    stage: ?Stage = null,
    blocker: Blocker = .none,
    owner: Owner = .evidence,
    met: usize = 0,
    total: usize = stage_count,
};

pub const Ledger = struct {
    observed_mask: u32 = 0,
    stages: [stage_count]StageObservation = [_]StageObservation{.{}} ** stage_count,
    /// What each evidence path achieved, as distinct from what it found.  A
    /// stage reading `NO` is not a fact about the title until this says a probe
    /// read real data and came back empty.
    probes: probe_ledger.Ledger = .{},

    arguments: Arguments = .{},
    arguments_observed: u64 = 0,
    vdswap_calls: u64 = 0,
    guest_packet_encodes: u64 = 0,
    packet_encoding_observations: u64 = 0,
    packet_encoding_mismatches: u64 = 0,
    encoded_command_buffer: u32 = 0,
    encoded_packet_offset: u32 = 0,
    encoded_packet_dwords: u32 = 0,
    encoded_packet_geometry_observed: bool = false,
    vdswap_completions: u64 = 0,
    publication_observations: u64 = 0,
    ring_geometry_observations: u64 = 0,
    fetch_observations: u64 = 0,

    candidates: [max_frontbuffer_candidates]Candidate = [_]Candidate{.{}} ** max_frontbuffer_candidates,
    candidate_count: usize = 0,
    invalid_candidate_count: u64 = 0,
    frontbuffer_conflicts: u64 = 0,
    active_frontbuffer: ?pm4.SwapDescription = null,
    active_frontbuffer_source: Source = .none,

    packet_observations: u64 = 0,
    projection_readable_observations: u64 = 0,
    stream_observations: u64 = 0,
    stream_validation_observations: u64 = 0,
    indirect_resolution_observations: u64 = 0,
    candidate_observations: u64 = 0,
    readable_packet_observations: u64 = 0,
    decoded_packet_observations: u64 = 0,
    fetch_decoded_observations: u64 = 0,
    root_packets: u64 = 0,
    nested_packets: u64 = 0,
    indirect_packets: u64 = 0,
    draw_packets: u64 = 0,
    swap_packets: u64 = 0,
    malformed_packets: u64 = 0,
    truncated_observations: u64 = 0,
    desynchronised_observations: u64 = 0,
    unknown_opcodes: u64 = 0,
    zero_dwords: u64 = 0,
    dwords_examined: u64 = 0,
    dwords_scanned: u64 = 0,
    span_dwords: u64 = 0,
    unreadable_references: u64 = 0,
    authentic_consumptions: u64 = 0,
    authentic_missing_descriptions: u64 = 0,
    issue_swap_observations: u64 = 0,
    output_refresh_observations: u64 = 0,
    native_present_observations: u64 = 0,
    intermediary_observations: u64 = 0,
    last_packet_offset: ?u32 = null,
    last_observation_step: u64 = 0,
    source_mask: u32 = 0,
    /// Emulator log lines this ledger has been offered.
    ///
    /// The evidence a breadcrumb probe needs to report honestly. "No line ever
    /// named a front buffer" and "no line ever reached this ledger" are
    /// opposite findings — the first is about the title, the second is about
    /// Rosette's log plumbing — and a probe that only counts matches cannot
    /// tell them apart.
    log_lines_seen: u64 = 0,

    pub fn observeStage(self: *Ledger, stage: Stage, step: u64, source: Source) void {
        // Every positive observation already names its source, so the probe
        // that produced it is recorded here rather than at each of the several
        // dozen call sites.  Negative and starved outcomes have no source —
        // nothing was found — so those stay the caller's responsibility.
        if (contract.probeForSource(source)) |which| {
            self.probes.record(stage, which, .observed, 1, step);
        }
        const entry = &self.stages[@intFromEnum(stage)];
        if (!entry.seen) entry.first_step = step;
        entry.seen = true;
        entry.count +|= 1;
        entry.last_step = step;
        entry.source_mask |= sourceBit(source);
        self.observed_mask |= contract.stageBit(stage);
        self.source_mask |= sourceBit(source);
        self.last_observation_step = step;
    }

    pub fn observed(self: *const Ledger, stage: Stage) bool {
        return self.observed_mask & contract.stageBit(stage) != 0;
    }

    pub fn observation(self: *const Ledger, stage: Stage) StageObservation {
        return self.stages[@intFromEnum(stage)];
    }

    pub fn observeVdSwapEntered(self: *Ledger, step: u64, source: Source) void {
        self.vdswap_calls +|= 1;
        self.observeStage(.guest_vdswap_entered, step, source);
    }

    pub fn observeArguments(self: *Ledger, arguments: Arguments, step: u64, source: Source) void {
        self.arguments = arguments;
        self.arguments_observed +|= 1;
        self.observeStage(.vdswap_arguments_captured, step, source);
        if (arguments.frontbuffer) |swap| self.observeFrontBuffer(swap, source, step);
        if (arguments.fetch) |fetch| self.observeFetch(fetch, step, source);
    }

    pub fn observeFrontBuffer(self: *Ledger, swap: pm4.SwapDescription, source: Source, step: u64) void {
        const plausible = swap.plausible() and contract.isPlausibleFrontBuffer(
            swap.frontbuffer_physical_address,
            swap.width,
            swap.height,
        );
        if (!plausible) {
            self.invalid_candidate_count +|= 1;
            return;
        }

        var existing: ?usize = null;
        for (self.candidates[0..self.candidate_count], 0..) |candidate, index| {
            if (candidate.description) |description| {
                if (sameDescription(description, swap)) {
                    existing = index;
                    break;
                }
            }
        }
        if (existing) |index| {
            self.candidates[index].observations +|= 1;
            if (source.strength() > self.candidates[index].source.strength()) {
                self.candidates[index].source = source;
            }
        } else if (self.candidate_count < max_frontbuffer_candidates) {
            self.candidates[self.candidate_count] = .{
                .description = swap,
                .source = source,
                .first_step = step,
                .observations = 1,
                .plausible = true,
            };
            self.candidate_count += 1;
        } else {
            self.frontbuffer_conflicts +|= 1;
            self.observed_mask &= ~contract.stageBit(.frontbuffer_validated);
            return;
        }

        if (self.active_frontbuffer) |active| {
            if (!sameDescription(active, swap)) {
                self.frontbuffer_conflicts +|= 1;
                self.observed_mask &= ~contract.stageBit(.frontbuffer_validated);
                self.source_mask |= sourceBit(source);
                return;
            }
        } else {
            self.active_frontbuffer = swap;
            self.active_frontbuffer_source = source;
        }
        if (source.strength() > self.active_frontbuffer_source.strength()) {
            self.active_frontbuffer_source = source;
        }
        self.observeStage(.frontbuffer_validated, step, source);
    }

    pub fn observeFetch(self: *Ledger, fetch: pm4.FetchConstant, step: u64, source: Source) void {
        self.arguments.fetch = fetch;
        self.fetch_observations +|= 1;
        self.observeStage(.fetch_constant_encoded, step, source);
    }

    /// The encoder breadcrumb proves that VdSwap wrote its six fetch dwords,
    /// even when verbose packet dumping was disabled and the actual dwords
    /// are not available to this process.  Keep this count distinct from an
    /// observed `FetchConstant`, which carries the decoded format/tiling.
    pub fn observeFetchEncoded(self: *Ledger, step: u64, source: Source) void {
        self.fetch_observations +|= 1;
        self.observeStage(.fetch_constant_encoded, step, source);
    }

    pub fn observeGuestPacketEncoded(self: *Ledger, step: u64, source: Source) void {
        self.guest_packet_encodes +|= 1;
        self.observeStage(.guest_xe_swap_encoded, step, source);
    }

    pub fn observeVdSwapCompleted(self: *Ledger, step: u64, source: Source) void {
        self.vdswap_completions +|= 1;
        self.observeStage(.vdswap_completed, step, source);
    }

    pub fn observePublication(self: *Ledger, step: u64, source: Source) void {
        self.publication_observations +|= 1;
        self.observeStage(.ring_write_pointer_published, step, source);
    }

    pub fn observeRingGeometry(self: *Ledger, step: u64, source: Source) void {
        self.ring_geometry_observations +|= 1;
        self.observeStage(.ring_geometry_observed, step, source);
    }

    /// Record the post-PM4 boundaries without collapsing them into a single
    /// "draw happened" bit.  Callers must supply evidence from the owner that
    /// performed each operation; this method has no recovery side effects.
    pub fn observeIntermediary(
        self: *Ledger,
        evidence: IntermediaryEvidence,
        step: u64,
        source: Source,
    ) void {
        self.intermediary_observations +|= 1;
        if (evidence.pm4_state_programmed) self.observeStage(.pm4_state_programmed, step, source);
        if (evidence.draw_submitted) self.observeStage(.draw_submitted, step, source);
        if (evidence.draw_consumed) self.observeStage(.draw_consumed, step, source);
        if (evidence.render_target_state_observed) self.observeStage(.render_target_state_observed, step, source);
        if (evidence.render_target_memory_observed) self.observeStage(.render_target_memory_observed, step, source);
        if (evidence.draw_completion_signaled) self.observeStage(.draw_completion_signaled, step, source);
        if (evidence.draw_completion_dispatched) self.observeStage(.draw_completion_dispatched, step, source);
        if (evidence.guest_wait_observed_after_draw) self.observeStage(.guest_wait_observed_after_draw, step, source);
        if (evidence.guest_producer_progressed_after_draw) self.observeStage(.guest_producer_progressed_after_draw, step, source);
    }

    /// Record a packet scan.  `decoded` means the packet shape passed the
    /// strict XE_SWAP decoder.  It never means that the CP consumed it.
    pub fn observePacket(self: *Ledger, packet: PacketObservation, step: u64, source: Source) void {
        self.packet_observations +|= 1;
        if (packet.projection_readable) {
            self.projection_readable_observations +|= 1;
            self.observeStage(.ring_projection_readable, step, source);
        }
        if (packet.stream_observed) {
            self.stream_observations +|= 1;
            self.observeStage(.pm4_stream_observed, step, source);
        }
        if (packet.stream_validated) {
            self.stream_validation_observations +|= 1;
            self.observeStage(.pm4_stream_validated, step, source);
        }
        if (packet.indirects_resolved) {
            self.indirect_resolution_observations +|= 1;
            self.observeStage(.pm4_indirects_resolved, step, source);
        }
        if (packet.candidate_seen or packet.swap != null) {
            self.candidate_observations +|= 1;
            self.observeStage(.xe_swap_candidate_seen, step, source);
        }
        if (packet.readable) {
            self.readable_packet_observations +|= 1;
            self.observeStage(.xe_swap_packet_readable, step, source);
        }
        if (packet.decoded) {
            self.decoded_packet_observations +|= 1;
            self.observeStage(.xe_swap_packet_decoded, step, source);
        }
        self.root_packets +|= packet.root_packets;
        self.nested_packets +|= packet.nested_packets;
        self.indirect_packets +|= packet.indirect_packets;
        self.draw_packets +|= packet.draw_packets;
        self.swap_packets +|= packet.swap_packets;
        self.malformed_packets +|= packet.malformed_packets;
        if (packet.truncated) self.truncated_observations +|= 1;
        if (packet.desynchronised) self.desynchronised_observations +|= 1;
        self.unknown_opcodes +|= packet.unknown_opcodes;
        self.zero_dwords +|= packet.zero_dwords;
        self.dwords_examined = @max(self.dwords_examined, packet.dwords_examined);
        self.dwords_scanned = @max(self.dwords_scanned, packet.dwords_scanned);
        self.span_dwords = @max(self.span_dwords, packet.span_dwords);
        self.unreadable_references +|= packet.unreadable_references;
        if (packet.packet_offset) |offset| self.last_packet_offset = offset;
        if (packet.swap) |swap| {
            self.observeFrontBuffer(swap, source, step);
            if (packet.fetch) |fetch| self.observeFetch(fetch, step, source);
        }
        if (packet.fetch_decoded or packet.fetch != null) {
            self.fetch_decoded_observations +|= 1;
            self.observeStage(.fetch_constant_decoded, step, source);
        }
        if (packet.authentic_consumption) self.observeAuthenticConsumption(packet.swap, packet.fetch, step, source);
        self.last_observation_step = step;
    }

    /// This is the only method that can close the authentic-consumption stage.
    /// A generic `pm4_packets != 0` counter must not call it.
    pub fn observeAuthenticConsumption(
        self: *Ledger,
        swap: ?pm4.SwapDescription,
        fetch: ?pm4.FetchConstant,
        step: u64,
        source: Source,
    ) void {
        const description = swap orelse {
            self.authentic_missing_descriptions +|= 1;
            return;
        };
        self.observeFrontBuffer(description, source, step);
        self.authentic_consumptions +|= 1;
        self.candidate_observations +|= 1;
        self.observeStage(.xe_swap_candidate_seen, step, source);
        self.observeStage(.xe_swap_packet_readable, step, source);
        self.observeStage(.xe_swap_packet_decoded, step, source);
        if (fetch) |decoded_fetch| {
            self.observeFetch(decoded_fetch, step, source);
            self.fetch_decoded_observations +|= 1;
            self.observeStage(.fetch_constant_decoded, step, source);
        }
        self.observeStage(.authentic_xe_swap_consumed, step, source);
    }

    pub fn observeIssueSwap(self: *Ledger, step: u64, source: Source) void {
        self.issue_swap_observations +|= 1;
        self.observeStage(.issue_swap_entered, step, source);
    }

    pub fn observeOutputRefresh(self: *Ledger, step: u64, source: Source) void {
        self.output_refresh_observations +|= 1;
        self.observeStage(.output_refresh_succeeded, step, source);
    }

    pub fn observeNativePresent(self: *Ledger, step: u64, source: Source) void {
        self.native_present_observations +|= 1;
        self.observeStage(.native_presented, step, source);
    }

    /// Consume the structured VdSwap breadcrumbs already emitted by Xenia.
    /// Parsing remains deliberately narrow: only provenance-bearing stage
    /// markers advance this ledger.  A line that merely mentions VdSwap in an
    /// export table is not a call.
    pub fn observeLogLine(self: *Ledger, line: []const u8, step: u64) bool {
        self.log_lines_seen +|= 1;
        var observed_any = false;
        const source: Source = .guest_log;
        if (contains(line, "VDSWAP PATH: stage=entered") or contains(line, "] d> VdSwap(")) {
            self.observeVdSwapEntered(step, source);
            self.observeArguments(.{
                .frontbuffer = parsedSwap(line),
                .frontbuffer_pointer = parseHexAfter(line, "frontbuffer_ptr=") orelse 0,
                .command_buffer = parseHexAfter(line, "buffer_ptr=") orelse 0,
                .fetch_pointer = parseHexAfter(line, "fetch_ptr=") orelse 0,
                .guest_pc = parseHex64After(line, "pc=") orelse 0,
                .thread_id = parseDecimalAfter(line, "thread_id=") orelse 0,
            }, step, source);
            observed_any = true;
        }
        if (contains(line, "VDSWAP PATH: stage=arguments")) {
            self.observeArguments(.{
                .frontbuffer = parsedSwap(line),
                .frontbuffer_pointer = parseHexAfter(line, "frontbuffer_ptr=") orelse 0,
                .command_buffer = parseHexAfter(line, "command_buffer=") orelse 0,
                .fetch_pointer = parseHexAfter(line, "fetch_ptr=") orelse 0,
                .reservation_dwords = @intCast(parseDecimalAfter(line, "reservation_dwords=") orelse 0),
                .guest_pc = parseHex64After(line, "pc=") orelse 0,
                .thread_id = parseHex64After(line, "thread=") orelse 0,
            }, step, source);
            observed_any = true;
        }
        if (contains(line, "VDSWAP PATH: stage=packet_encoded")) {
            self.packet_encoding_observations +|= 1;
            if (parseHexAfter(line, "buffer_phys=")) |buffer| self.encoded_command_buffer = buffer;
            if (parseDecimalAfter(line, "packet_dword=")) |offset| {
                self.encoded_packet_offset = @intCast(offset);
                self.encoded_packet_geometry_observed = true;
            }
            if (parseDecimalAfter(line, "packet_dwords=")) |count| {
                self.encoded_packet_dwords = @intCast(count);
                self.encoded_packet_geometry_observed = true;
                if (count != contract.xe_swap_packet_dwords) self.packet_encoding_mismatches +|= 1;
            }
            if (parsedSwap(line)) |swap| self.observeFrontBuffer(swap, source, step);
            self.observeFetchEncoded(step, source);
            self.observeGuestPacketEncoded(step, source);
            observed_any = true;
        }
        if (contains(line, "VDSWAP PATH: stage=fetch_encoded")) {
            self.observeStage(.fetch_constant_encoded, step, source);
            self.fetch_observations +|= 1;
            observed_any = true;
        }
        if (contains(line, "VDSWAP PATH: stage=completed")) {
            if (parsedSwap(line)) |swap| self.observeFrontBuffer(swap, source, step);
            self.observeVdSwapCompleted(step, source);
            observed_any = true;
        }
        if (contains(line, "VDSWAP PATH: stage=packet_published")) {
            self.observePublication(step, source);
            observed_any = true;
        }
        if (contains(line, "PM4 AUTHENTIC MILESTONE:") and contains(line, "PM4_XE_SWAP")) {
            self.observeAuthenticConsumption(parsedSwap(line), null, step, source);
            observed_any = true;
        }
        if (contains(line, "IssueSwap") and (contains(line, "XE_SWAP") or contains(line, "swap"))) {
            self.observeIssueSwap(step, source);
            observed_any = true;
        }
        if ((parseDecimalAfter(line, "authentic_swaps=") orelse 0) != 0 and
            (parseDecimalAfter(line, "refresh=") orelse 0) != 0)
        {
            self.observeOutputRefresh(step, source);
            observed_any = true;
        }
        if (contains(line, "authority=native") and contains(line, "provenance=AUTHENTIC")) {
            self.observeNativePresent(step, source);
            observed_any = true;
        }
        return observed_any;
    }

    pub fn frontier(self: *const Ledger) Frontier {
        const stage = contract.firstGap(self.observed_mask) orelse return .{
            .stage = null,
            .blocker = .none,
            .owner = .evidence,
            .met = contract.observedCount(self.observed_mask),
        };
        const gap_blocker = self.blockerFor(stage);
        return .{
            .stage = stage,
            .blocker = gap_blocker,
            .owner = gap_blocker.owner(),
            .met = contract.observedCount(self.observed_mask),
        };
    }

    pub fn blocker(self: *const Ledger) Blocker {
        return self.frontier().blocker;
    }

    /// Record what one probe achieved.  Callers must use this for the outcomes
    /// that have no source — a probe whose input was empty, unreadable, or
    /// never obtained — because those are exactly the ones that make an unmet
    /// stage a defect in the observer rather than a finding about the guest.
    pub fn recordProbe(
        self: *Ledger,
        stage: Stage,
        which: Probe,
        outcome: ProbeOutcome,
        detail: u64,
        step: u64,
    ) void {
        self.probes.record(stage, which, outcome, detail, step);
    }

    /// Record a probe that produced nothing, together with what it was
    /// missing.
    ///
    /// `recordProbe` with a starved outcome still works and is counted as
    /// unattributed, because a caller that genuinely does not know why must
    /// not be forced to invent a cause. But a starvation with no cause names
    /// no work, so every call site that does know says so here.
    pub fn recordStarvation(
        self: *Ledger,
        stage: Stage,
        which: Probe,
        outcome: ProbeOutcome,
        cause: StarvationCause,
        detail: u64,
        step: u64,
    ) void {
        self.probes.recordWithCause(stage, which, outcome, cause, detail, step);
    }

    /// Record a probe that ran with real input: `observed` when it found the
    /// fact, `negative` when it did not.  A probe that had no input must call
    /// `recordProbe` with `.input_empty` instead — passing `false` here claims
    /// it looked, and that claim is what turns a blind spot into a fake finding.
    pub fn observeProbe(
        self: *Ledger,
        stage: Stage,
        which: Probe,
        seen: bool,
        detail: u64,
        step: u64,
    ) void {
        self.probes.observe(stage, which, seen, detail, step);
    }

    pub fn diagnose(self: *const Ledger, stage: Stage) StageDiagnosis {
        return self.probes.diagnose(stage, self.observed_mask);
    }

    pub fn diagnosisSummary(self: *const Ledger) DiagnosisSummary {
        return self.probes.summary(self.observed_mask);
    }

    /// The stage a reader should look at first.  This is deliberately not
    /// `frontier()`: the linear frontier names the first unmet stage in the
    /// total order, which on a stalled producer is always the producer, and
    /// says nothing about whether the nineteen stages behind it are downstream
    /// of it or independently broken.
    pub fn primaryWall(self: *const Ledger) ?StageDiagnosis {
        return self.probes.primaryWall(self.observed_mask);
    }

    /// The unmet stages whose prerequisites all hold: the real walls.  Every
    /// other unmet stage is downstream of one of these.
    pub fn actionableMask(self: *const Ledger) u32 {
        return contract.actionableMask(self.observed_mask);
    }

    pub fn chainFrontier(self: *const Ledger, chain: Chain) ?Stage {
        return contract.chainFrontier(chain, self.observed_mask);
    }

    pub fn chainMet(self: *const Ledger, chain: Chain) usize {
        return contract.chainObservedCount(chain, self.observed_mask);
    }

    /// Whether any front-buffer candidate came from `source`.
    ///
    /// Each probe reports on its own evidence path, and `active_frontbuffer`
    /// is the join of all of them: a probe that reported the joined answer
    /// would claim to have seen what another probe found.
    pub fn frontbufferSeenFrom(self: *const Ledger, source: Source) bool {
        for (self.candidates[0..self.candidate_count]) |candidate| {
            if (candidate.description != null and candidate.source == source) return true;
        }
        return false;
    }

    pub fn frontbufferKnown(self: *const Ledger) bool {
        return self.active_frontbuffer != null and self.frontbuffer_conflicts == 0;
    }

    pub fn packetSeen(self: *const Ledger) bool {
        return self.candidate_observations != 0;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        return self.blocker().guidance();
    }

    pub fn sourceNames(self: *const Ledger, buffer: []u8) []const u8 {
        var used: usize = 0;
        var first = true;
        const sources = [_]Source{
            .guest_tracepoint,
            .guest_log,
            .vdswap_argument_capture,
            .ring_memory_scan,
            .nested_pm4_walk,
            .stateful_pm4_executor,
            .guest_publication,
            .command_processor_tracepoint,
            .issue_swap_tracepoint,
            .output_refresh_tracepoint,
            .native_present_tracepoint,
            .memory_mapping,
            .diagnostic_substitution,
            .causal_trace,
            .xenos_runtime,
            .interrupt_dispatch,
            .guest_progress,
        };
        for (sources) |source| {
            if (self.source_mask & sourceBit(source) == 0) continue;
            if (!first) {
                if (used + 1 >= buffer.len) break;
                buffer[used] = ',';
                used += 1;
            }
            const label = source.label();
            if (used + label.len > buffer.len) break;
            @memcpy(buffer[used .. used + label.len], label);
            used += label.len;
            first = false;
        }
        return buffer[0..used];
    }

    fn blockerFor(self: *const Ledger, stage: Stage) Blocker {
        return switch (stage) {
            .guest_vdswap_entered => .vdswap_not_entered,
            .vdswap_arguments_captured => .arguments_not_captured,
            .frontbuffer_validated => if (self.frontbuffer_conflicts != 0)
                .frontbuffer_conflict
            else if (self.invalid_candidate_count != 0)
                .frontbuffer_invalid
            else
                .frontbuffer_unknown,
            .fetch_constant_encoded => .fetch_not_encoded,
            .guest_xe_swap_encoded => .guest_packet_not_encoded,
            .vdswap_completed => .vdswap_not_completed,
            .ring_write_pointer_published => .publication_not_observed,
            .ring_geometry_observed => .ring_geometry_missing,
            .ring_projection_readable => .ring_projection_unreadable,
            .pm4_stream_observed => .pm4_stream_missing,
            .pm4_stream_validated => .pm4_stream_malformed,
            .pm4_indirects_resolved => .pm4_indirect_unresolved,
            .pm4_state_programmed => .pm4_state_unreconstructed,
            .draw_submitted => .draw_submission_missing,
            .draw_consumed => .draw_consumption_unproven,
            .render_target_state_observed => .render_target_state_missing,
            .render_target_memory_observed => .render_target_memory_missing,
            .draw_completion_signaled => .draw_completion_not_signaled,
            .draw_completion_dispatched => .draw_completion_not_dispatched,
            .guest_wait_observed_after_draw => .guest_wait_after_draw_missing,
            .guest_producer_progressed_after_draw => .producer_progress_after_draw_missing,
            .xe_swap_candidate_seen => .xe_swap_candidate_missing,
            .xe_swap_packet_readable => if (self.truncated_observations != 0)
                .packet_truncated
            else
                .packet_not_readable,
            .xe_swap_packet_decoded => if (self.malformed_packets != 0 or self.desynchronised_observations != 0)
                .packet_malformed
            else if (self.truncated_observations != 0)
                .packet_truncated
            else
                .packet_decode_unproven,
            .fetch_constant_decoded => .fetch_decode_unproven,
            .authentic_xe_swap_consumed => .authentic_consumption_missing,
            .issue_swap_entered => .issue_swap_missing,
            .output_refresh_succeeded => .output_refresh_missing,
            .native_presented => .native_presentation_missing,
        };
    }
};

pub fn sourceBit(source: Source) u32 {
    return @as(u32, 1) << @as(u5, @intCast(@intFromEnum(source)));
}

fn sameDescription(left: pm4.SwapDescription, right: pm4.SwapDescription) bool {
    return left.frontbuffer_physical_address == right.frontbuffer_physical_address and
        left.width == right.width and left.height == right.height;
}

fn contains(line: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, line, needle) != null;
}

fn parseHexAfter(line: []const u8, marker: []const u8) ?u32 {
    const start = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[start + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u32, text[0..length], 16) catch null;
}

fn parseHex64After(line: []const u8, marker: []const u8) ?u64 {
    const start = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[start + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and length < 16 and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 16) catch null;
}

fn parseDecimalAfter(line: []const u8, marker: []const u8) ?u64 {
    const start = std.mem.indexOf(u8, line, marker) orelse return null;
    const text = line[start + marker.len ..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isDigit(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 10) catch null;
}

fn parsedSwap(line: []const u8) ?pm4.SwapDescription {
    const address = parseHexAfter(line, "frontbuffer_physical=") orelse
        parseHexAfter(line, "frontbuffer=") orelse return null;
    const extent = parseExtent(line) orelse return null;
    return .{ .frontbuffer_physical_address = address, .width = extent.width, .height = extent.height };
}

fn parseExtent(line: []const u8) ?struct { width: u32, height: u32 } {
    if (parseDecimalAfter(line, "width=")) |width| {
        const height = parseDecimalAfter(line, "height=") orelse return null;
        return .{ .width = @intCast(width), .height = @intCast(height) };
    }
    const start = std.mem.indexOf(u8, line, "size=") orelse return null;
    const text = line[start + "size=".len ..];
    var width_length: usize = 0;
    while (width_length < text.len and std.ascii.isDigit(text[width_length])) : (width_length += 1) {}
    if (width_length == 0 or width_length >= text.len or text[width_length] != 'x') return null;
    const height_start = width_length + 1;
    var height_length: usize = height_start;
    while (height_length < text.len and std.ascii.isDigit(text[height_length])) : (height_length += 1) {}
    if (height_length == height_start) return null;
    return .{
        .width = std.fmt.parseInt(u32, text[0..width_length], 10) catch return null,
        .height = std.fmt.parseInt(u32, text[height_start..height_length], 10) catch return null,
    };
}

test "an untouched VdSwap contract identifies the producer frontier" {
    const ledger = Ledger{};
    const frontier = ledger.frontier();
    try std.testing.expectEqual(Stage.guest_vdswap_entered, frontier.stage.?);
    try std.testing.expectEqual(Blocker.vdswap_not_entered, frontier.blocker);
    try std.testing.expectEqual(Owner.guest_title, frontier.owner);
}

test "generic PM4 consumption does not close authentic XE_SWAP" {
    var ledger = Ledger{};
    ledger.observeStage(.guest_vdswap_entered, 1, .guest_tracepoint);
    ledger.observeStage(.vdswap_arguments_captured, 2, .vdswap_argument_capture);
    ledger.observeFrontBuffer(.{ .frontbuffer_physical_address = 0x1FC0_0000, .width = 1280, .height = 720 }, .vdswap_argument_capture, 2);
    ledger.observeFetch(.{}, 3, .guest_log);
    ledger.observeGuestPacketEncoded(4, .guest_log);
    ledger.observeVdSwapCompleted(5, .guest_log);
    ledger.observePublication(6, .guest_publication);
    for (contract.stage_order) |stage| {
        if (stage == .authentic_xe_swap_consumed) break;
        if (stage == .guest_vdswap_entered or
            stage == .vdswap_arguments_captured or
            stage == .frontbuffer_validated or
            stage == .fetch_constant_encoded or
            stage == .guest_xe_swap_encoded or
            stage == .vdswap_completed or
            stage == .ring_write_pointer_published)
        {
            continue;
        }
        ledger.observeStage(stage, 7, .ring_memory_scan);
    }
    ledger.observePacket(.{ .readable = true, .decoded = true, .swap = .{ .frontbuffer_physical_address = 0x1FC0_0000, .width = 1280, .height = 720 }, .swap_packets = 1 }, 7, .ring_memory_scan);
    try std.testing.expectEqual(Stage.authentic_xe_swap_consumed, ledger.frontier().stage.?);
    try std.testing.expectEqual(Blocker.authentic_consumption_missing, ledger.blocker());
    try std.testing.expectEqual(@as(u64, 0), ledger.authentic_consumptions);
}

test "intermediary pipeline evidence remains independently observable" {
    var ledger = Ledger{};
    ledger.observeIntermediary(.{
        .pm4_state_programmed = true,
        .draw_submitted = true,
        .draw_consumed = true,
    }, 10, .causal_trace);
    try std.testing.expect(ledger.observed(.pm4_state_programmed));
    try std.testing.expect(ledger.observed(.draw_submitted));
    try std.testing.expect(ledger.observed(.draw_consumed));
    try std.testing.expect(!ledger.observed(.render_target_state_observed));
    try std.testing.expect(!ledger.observed(.draw_completion_signaled));
    try std.testing.expectEqual(@as(u64, 1), ledger.intermediary_observations);
}

test "projection readability is not XE_SWAP packet readability" {
    var ledger = Ledger{};
    ledger.observePacket(.{
        .projection_readable = true,
        .stream_observed = true,
        .stream_validated = true,
        .indirects_resolved = true,
        .root_packets = 240,
    }, 7, .ring_memory_scan);
    try std.testing.expect(ledger.observed(.ring_projection_readable));
    try std.testing.expect(ledger.observed(.pm4_stream_observed));
    try std.testing.expect(!ledger.observed(.xe_swap_candidate_seen));
    try std.testing.expect(!ledger.observed(.xe_swap_packet_readable));
    try std.testing.expectEqual(@as(u64, 0), ledger.readable_packet_observations);
    try std.testing.expectEqual(Blocker.vdswap_not_entered, ledger.blocker());
}

test "an authentic milestone without a swap description remains unresolved" {
    var ledger = Ledger{};
    ledger.observeAuthenticConsumption(null, null, 11, .command_processor_tracepoint);
    try std.testing.expectEqual(@as(u64, 0), ledger.authentic_consumptions);
    try std.testing.expectEqual(@as(u64, 1), ledger.authentic_missing_descriptions);
    try std.testing.expect(!ledger.observed(.authentic_xe_swap_consumed));
}

test "a nested packet can be decoded without becoming an authentic handoff" {
    var ledger = Ledger{};
    ledger.observePacket(.{
        .readable = true,
        .decoded = true,
        .swap = .{ .frontbuffer_physical_address = 0x1FC0_0000, .width = 1280, .height = 720 },
        .root_packets = 3,
        .nested_packets = 69,
        .indirect_packets = 5,
        .draw_packets = 24,
        .swap_packets = 1,
    }, 100, .nested_pm4_walk);
    try std.testing.expect(ledger.packetSeen());
    try std.testing.expect(!ledger.observed(.authentic_xe_swap_consumed));
    try std.testing.expectEqual(Stage.guest_vdswap_entered, ledger.frontier().stage.?);
    try std.testing.expectEqual(@as(u64, 69), ledger.nested_packets);
}

test "packet anomalies remain visible without inventing an authentic swap" {
    var ledger = Ledger{};
    inline for (contract.stage_order[0..10]) |stage| ledger.observeStage(stage, 100, .guest_log);
    ledger.observePacket(.{
        .projection_readable = true,
        .stream_observed = true,
        .malformed_packets = 1,
        .truncated = true,
        .desynchronised = true,
        .zero_dwords = 11,
        .dwords_examined = 25,
        .dwords_scanned = 7,
        .span_dwords = 25,
        .unknown_opcodes = 2,
    }, 200, .ring_memory_scan);
    try std.testing.expectEqual(@as(u64, 1), ledger.malformed_packets);
    try std.testing.expectEqual(@as(u64, 1), ledger.truncated_observations);
    try std.testing.expectEqual(@as(u64, 1), ledger.desynchronised_observations);
    try std.testing.expectEqual(@as(u64, 11), ledger.zero_dwords);
    try std.testing.expectEqual(@as(u64, 25), ledger.dwords_examined);
    try std.testing.expectEqual(Blocker.pm4_stream_malformed, ledger.blocker());
    try std.testing.expectEqual(@as(u64, 0), ledger.authentic_consumptions);
}

test "conflicting valid front buffers reopen the validation stage" {
    var ledger = Ledger{};
    ledger.observeFrontBuffer(.{ .frontbuffer_physical_address = 0x1FC0_0000, .width = 1280, .height = 720 }, .guest_log, 1);
    try std.testing.expect(ledger.observed(.frontbuffer_validated));
    ledger.observeFrontBuffer(.{ .frontbuffer_physical_address = 0x1FD0_0000, .width = 1280, .height = 720 }, .ring_memory_scan, 2);
    try std.testing.expectEqual(@as(u64, 1), ledger.frontbuffer_conflicts);
    try std.testing.expect(!ledger.observed(.frontbuffer_validated));
    try std.testing.expectEqual(Blocker.vdswap_not_entered, ledger.blocker());
}

test "a complete authentic sequence reaches native presentation" {
    var ledger = Ledger{};
    inline for (contract.stage_order) |stage| ledger.observeStage(stage, 1, .guest_tracepoint);
    try std.testing.expect(ledger.frontier().stage == null);
    try std.testing.expectEqual(Blocker.none, ledger.blocker());
}

test "structured VdSwap breadcrumbs advance only their named stages" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.observeLogLine("VDSWAP PATH: stage=entered", 1));
    try std.testing.expect(ledger.observeLogLine("VDSWAP PATH: stage=packet_encoded frontbuffer=0x1fc00000 width=1280 height=720", 2));
    try std.testing.expect(ledger.observeLogLine("VDSWAP PATH: stage=completed", 3));
    try std.testing.expect(ledger.observed(.guest_vdswap_entered));
    try std.testing.expect(ledger.observed(.guest_xe_swap_encoded));
    try std.testing.expect(ledger.observed(.vdswap_completed));
    try std.testing.expect(ledger.frontbufferKnown());
}

test "the exact Xenia Mac VdSwap breadcrumbs retain arguments and extent" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.observeLogLine(
        "VDSWAP PATH: stage=entered call=1 pc=82ABCDEF thread_id=7 buffer_ptr=1FC90000 fetch_ptr=1FC91000 frontbuffer_ptr=1FC92000",
        1,
    ));
    try std.testing.expect(ledger.observeLogLine(
        "VDSWAP PATH: stage=packet_encoded storage=external_command_buffer packet_dword=7 packet_dwords=5 buffer_phys=1FC90000",
        2,
    ));
    try std.testing.expect(ledger.observeLogLine(
        "VDSWAP PATH: stage=completed frontbuffer_physical=1FC00000 size=1280x720 return=void",
        3,
    ));
    try std.testing.expectEqual(@as(u64, 1), ledger.vdswap_calls);
    try std.testing.expectEqual(@as(u64, 1), ledger.arguments_observed);
    try std.testing.expectEqual(@as(u32, 0x1FC9_0000), ledger.arguments.command_buffer);
    try std.testing.expectEqual(@as(u32, 0x1FC9_1000), ledger.arguments.fetch_pointer);
    try std.testing.expectEqual(@as(u32, 0x1FC9_2000), ledger.arguments.frontbuffer_pointer);
    try std.testing.expectEqual(@as(u32, 0x1FC9_0000), ledger.encoded_command_buffer);
    try std.testing.expectEqual(@as(u32, 7), ledger.encoded_packet_offset);
    try std.testing.expectEqual(@as(u32, 5), ledger.encoded_packet_dwords);
    try std.testing.expect(ledger.encoded_packet_geometry_observed);
    try std.testing.expect(ledger.observed(.vdswap_arguments_captured));
    try std.testing.expect(ledger.observed(.fetch_constant_encoded));
    try std.testing.expect(ledger.observed(.guest_xe_swap_encoded));
    try std.testing.expect(ledger.observed(.vdswap_completed));
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), ledger.active_frontbuffer.?.frontbuffer_physical_address);
    try std.testing.expectEqual(@as(u32, 1280), ledger.active_frontbuffer.?.width);
}

test "the package invariants are visible through the runtime module" {
    try std.testing.expect(contract.contractIsWellFormed());
}

// The 2026-09-03 stop. `frontbuffer_validated` declares no prerequisite, so it
// is reachable from step zero; all four of its probes were recorded only from
// inside branches a drained-ring run never takes, and it read `not_attempted`
// for two billion steps while the contract called its zero a fact about the
// title.
test "a front buffer named by one source is not claimed by another probe" {
    var ledger = Ledger{};
    try std.testing.expect(!ledger.frontbufferSeenFrom(.guest_log));
    try std.testing.expect(!ledger.frontbufferSeenFrom(.vdswap_argument_capture));

    ledger.observeFrontBuffer(
        .{ .frontbuffer_physical_address = 0x1FC0_0000, .width = 1280, .height = 720 },
        .guest_log,
        4,
    );
    try std.testing.expect(ledger.frontbufferKnown());
    try std.testing.expect(ledger.frontbufferSeenFrom(.guest_log));
    // The join found it; the argument-capture probe did not, and must not say
    // it did.
    try std.testing.expect(!ledger.frontbufferSeenFrom(.vdswap_argument_capture));
}

// A breadcrumb probe that only counts matches cannot separate "no line named a
// front buffer" from "no line ever reached this ledger". The first is about
// the title, the second is about Rosette's log plumbing.
test "the ledger counts every line it was offered, not only the ones it used" {
    var ledger = Ledger{};
    try std.testing.expectEqual(@as(u64, 0), ledger.log_lines_seen);
    try std.testing.expect(!ledger.observeLogLine("[xenia] i> something unrelated", 1));
    try std.testing.expectEqual(@as(u64, 1), ledger.log_lines_seen);
    try std.testing.expect(ledger.observeLogLine("VDSWAP PATH: stage=entered", 2));
    try std.testing.expectEqual(@as(u64, 2), ledger.log_lines_seen);
}

test "an observed stage credits the probe its source names" {
    var ledger = Ledger{};
    ledger.observeStage(.draw_consumed, 100, .stateful_pm4_executor);
    const entry = ledger.probes.cell(.draw_consumed, .stateful_pm4_execution);
    try std.testing.expectEqual(contract.ProbeOutcome.observed, entry.outcome);
    try std.testing.expectEqual(@as(u64, 1), entry.attempts);
    try std.testing.expectEqual(Attribution.met, ledger.diagnose(.draw_consumed).attribution);
    try std.testing.expectEqual(@as(u64, 0), ledger.probes.unlisted_probe_records);
}

test "a substituted frame credits no probe" {
    var ledger = Ledger{};
    ledger.observeStage(.native_presented, 1, .diagnostic_substitution);
    // The stage is observed because something claimed it; no probe is credited,
    // so the report still shows that nothing looked.
    try std.testing.expect(ledger.observed(.native_presented));
    try std.testing.expectEqual(@as(u64, 0), ledger.probes.records);
    try std.testing.expectEqual(
        contract.ProbeOutcome.not_attempted,
        ledger.probes.cell(.native_presented, .native_presenter_counter).outcome,
    );
}

test "the live reading separates its walls from its blind spots" {
    // Reconstructed from the 2026-08-25 Halo 3 run: publication, geometry,
    // projection, stream, validation, indirects, state, draw submitted, draw
    // consumed and the post-draw guest wait.  Ten of twenty-nine.
    var ledger = Ledger{};
    ledger.observePublication(1, .guest_publication);
    ledger.observeRingGeometry(1, .memory_mapping);
    ledger.observePacket(.{
        .projection_readable = true,
        .stream_observed = true,
        .stream_validated = true,
        .indirects_resolved = true,
        .root_packets = 3,
        .nested_packets = 69,
        .draw_packets = 24,
    }, 1, .nested_pm4_walk);
    ledger.observeIntermediary(.{
        .pm4_state_programmed = true,
        .draw_submitted = true,
        .draw_consumed = true,
        .guest_wait_observed_after_draw = true,
    }, 1, .causal_trace);

    // The probes that did run and came back empty.  The export tracepoint
    // watched VdSwap for the whole run, and the retained-batch scan read every
    // dword of a readable ring: both absences are findings about the title.
    ledger.observeProbe(.guest_vdswap_entered, .guest_export_tracepoint, false, 0, 1);
    ledger.observeProbe(.guest_vdswap_entered, .guest_log_breadcrumb, false, 0, 1);
    ledger.observeProbe(.frontbuffer_validated, .retained_batch_scan, false, 8192, 1);
    ledger.observeProbe(.xe_swap_candidate_seen, .retained_batch_scan, false, 8192, 1);
    ledger.observeProbe(.guest_producer_progressed_after_draw, .guest_progress_counter, false, 0, 1);

    try std.testing.expectEqual(@as(usize, 10), contract.observedCount(ledger.observed_mask));
    try std.testing.expectEqual(Stage.guest_vdswap_entered, ledger.frontier().stage.?);

    // Nineteen unmet stages, but only six of them are walls.
    try std.testing.expectEqual(
        @as(usize, 6),
        contract.observedCount(ledger.actionableMask()),
    );

    // The transport chain is complete while the producer chain is empty; a
    // single linear frontier reports only the producer and hides both facts.
    try std.testing.expect(ledger.chainFrontier(.transport) == null);
    try std.testing.expectEqual(@as(usize, 0), ledger.chainMet(.producer));
    try std.testing.expectEqual(Stage.render_target_state_observed, ledger.chainFrontier(.raster).?);

    // Nothing has probed the render target, so its zero is Rosette's and the
    // report must not offer it as evidence about the title.
    const target = ledger.diagnose(.render_target_state_observed);
    try std.testing.expectEqual(Attribution.unprobed, target.attribution);
    try std.testing.expect(target.observerDefect());
    try std.testing.expectEqual(Stage.render_target_state_observed, ledger.primaryWall().?.stage);

    const totals = ledger.diagnosisSummary();
    try std.testing.expectEqual(@as(usize, 10), totals.met);
    try std.testing.expectEqual(@as(usize, 13), totals.blocked_upstream);
    // Five findings and two blind spots — the render target and the draw
    // completion, both of which only the Xenos executor can supply.
    try std.testing.expectEqual(@as(usize, 4), totals.actionable);
    try std.testing.expectEqual(@as(usize, 2), totals.unprobed);
    try std.testing.expectEqual(@as(usize, 2), totals.observerDefects());
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict(), "hole in the observer") != null);
}

test "a probe that read the whole ring makes the swap absence a finding" {
    var ledger = Ledger{};
    ledger.observePublication(1, .guest_publication);
    ledger.observeRingGeometry(1, .memory_mapping);
    ledger.observePacket(.{
        .projection_readable = true,
        .stream_observed = true,
        .stream_validated = true,
        .indirects_resolved = true,
    }, 1, .nested_pm4_walk);

    // Before the scan reports, the candidate stage is a blind spot.
    try std.testing.expectEqual(Attribution.unprobed, ledger.diagnose(.xe_swap_candidate_seen).attribution);

    // The retained-batch scan walked 8192 dwords of a readable ring and found
    // no XE_SWAP header.  That is the strong form of the absence: the title
    // did not write a present request, and the observer is not at fault.
    ledger.observeProbe(.xe_swap_candidate_seen, .retained_batch_scan, false, 8192, 2);
    const finding = ledger.diagnose(.xe_swap_candidate_seen);
    try std.testing.expectEqual(Attribution.actionable, finding.attribution);
    try std.testing.expect(!finding.observerDefect());
    try std.testing.expectEqual(@as(u64, 8192), finding.detail);
    try std.testing.expectEqual(contract.ProbeOutcome.negative, finding.decided_outcome);

    // An empty span alongside it must not weaken the finding.
    ledger.recordProbe(.xe_swap_candidate_seen, .outstanding_span_scan, .input_empty, 0, 3);
    try std.testing.expectEqual(Attribution.actionable, ledger.diagnose(.xe_swap_candidate_seen).attribution);
    try std.testing.expectEqual(@as(usize, 1), ledger.diagnose(.xe_swap_candidate_seen).probes_starved);
}
