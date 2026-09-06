//! Bounded causal evidence for Xenia's graphics producer.
//!
//! The GPU bootstrap ladder answers whether a title reached the command ring.
//! This ledger answers the next question: did the title submit a draw, did the
//! command processor consume it, and where did the authentic handoff stop?
//!
//! This is deliberately an observer, not a recovery path.  It never changes a
//! guest pointer, writes a packet, wakes a thread, or asks a presenter to
//! refresh.  It records Xenia's own evidence and Rosette's read-only ring
//! observations in one bounded stream so a later report can identify the first
//! missing owner instead of inferring it from a wall of zero counters.

const std = @import("std");
const event_log = @import("event_log");
const vd_ring = @import("xenia_vd_ring_contract");
const pm4 = @import("xenia_pm4_contract");
const pm4_walk = @import("xenia_pm4_walk.zig");

const machoCapturePrint = event_log.machoCapturePrint;

pub const max_events: usize = 96;
pub const recent_signature_capacity: usize = 16;
pub const cycle_width: usize = 8;
const packet_class_count: usize = @typeInfo(pm4.PacketClass).@"enum".fields.len;

pub const EventKind = enum(u8) {
    stage,
    ring_payload,
    ring_write_pointer,
    pm4_packet,
    draw,
    swap,
    wait,
    signal,
    module_initialization,
    scheduler,
    kernel_export,
    indirect_buffer,
    unproven_handoff,

    pub fn label(self: EventKind) []const u8 {
        return switch (self) {
            .stage => "stage",
            .ring_payload => "ring-payload",
            .ring_write_pointer => "ring-write-pointer",
            .pm4_packet => "pm4-packet",
            .draw => "draw",
            .swap => "swap",
            .wait => "wait",
            .signal => "signal",
            .module_initialization => "module-init",
            .scheduler => "scheduler",
            .kernel_export => "kernel-export",
            .indirect_buffer => "indirect-buffer",
            .unproven_handoff => "unproven-handoff",
        };
    }
};

pub const Event = struct {
    sequence: u64 = 0,
    kind: EventKind = .stage,
    stage: ?vd_ring.CausalStage = null,
    step: u64 = 0,
    thread: u64 = 0,
    program_counter: u64 = 0,
    object: u64 = 0,
    value: u64 = 0,
    secondary: u64 = 0,
    opcode: ?u8 = null,
    packet_class: ?pm4.PacketClass = null,
    authentic: bool = false,
};

pub const StageRecord = struct {
    seen: bool = false,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    last_value: u64 = 0,
};

const Signature = struct {
    kind: EventKind,
    stage: u8,
    object: u64,
    value: u64,
    opcode: u8,
};

pub const Ledger = struct {
    observed_mask: u16 = 0,
    stages: [vd_ring.causal_stage_count]StageRecord = [_]StageRecord{.{}} ** vd_ring.causal_stage_count,

    events: [max_events]Event = [_]Event{.{}} ** max_events,
    event_count: usize = 0,
    event_cursor: usize = 0,
    total_events: u64 = 0,
    events_dropped: u64 = 0,

    packet_classes: [packet_class_count]u64 = [_]u64{0} ** packet_class_count,
    indirect_walk_observations: u64 = 0,
    indirect_walk_unique: u64 = 0,
    indirect_walk_repeats: u64 = 0,
    indirect_draw_observations: u64 = 0,
    indirect_swap_observations: u64 = 0,
    indirect_unreadable_observations: u64 = 0,
    indirect_cycle_observations: u64 = 0,
    last_indirect_summary: pm4_walk.Summary = .{},
    last_indirect_references: [pm4.max_indirect_references]pm4_walk.Reference = [_]pm4_walk.Reference{.{}} ** pm4.max_indirect_references,
    last_indirect_reference_count: usize = 0,
    last_indirect_references_dropped: u64 = 0,
    last_indirect_fingerprint: u64 = 0,
    ring_payload_observations: u64 = 0,
    pm4_consumption_observations: u64 = 0,
    draw_observations: u64 = 0,
    swap_observations: u64 = 0,
    first_draw_consumed_step: u64 = 0,
    first_draw_consumed_recorded: bool = false,
    wait_events_after_draw: u64 = 0,
    signal_events_after_draw: u64 = 0,

    out_of_order: u64 = 0,
    last_progress_step: u64 = 0,
    last_event_step: u64 = 0,
    last_wptr: ?u32 = null,

    recent_signatures: [recent_signature_capacity]Signature = undefined,
    recent_count: usize = 0,
    cycle_reports: u64 = 0,
    cycle_repetitions: u64 = 0,
    last_cycle_signature: u64 = 0,
    last_cycle_step: u64 = 0,

    pub fn observed(self: *const Ledger, stage: vd_ring.CausalStage) bool {
        return self.observed_mask & vd_ring.causalStageBit(stage) != 0;
    }

    pub fn firstGap(self: *const Ledger) ?vd_ring.CausalStage {
        return vd_ring.firstCausalGap(self.observed_mask);
    }

    pub fn noProgressSteps(self: *const Ledger, current_step: u64) ?u64 {
        if (self.last_progress_step == 0) return null;
        return current_step -| self.last_progress_step;
    }

    /// The first consumed draw is the anchor for the producer-to-VdSwap
    /// handoff.  A wait observed before that point belongs to bring-up and
    /// cannot explain why the title failed to request its next frame.
    pub fn postDrawWaitObserved(self: *const Ledger) bool {
        return self.wait_events_after_draw != 0;
    }

    pub fn firstDrawConsumedStep(self: *const Ledger) ?u64 {
        if (!self.first_draw_consumed_recorded) return null;
        return self.first_draw_consumed_step;
    }

    /// Observe a stage owned by the supplied producer.  The stage is recorded
    /// even when it arrives out of order; the order violation is evidence, not
    /// a reason to discard the event or invent a repair.
    pub fn observeStage(self: *Ledger, stage: vd_ring.CausalStage, step: u64) void {
        self.observeStageWith(stage, step, .stage, 0, 0, 0, 0, 0, null, null, true);
    }

    fn observeStageWith(
        self: *Ledger,
        stage: vd_ring.CausalStage,
        step: u64,
        kind: EventKind,
        thread: u64,
        program_counter: u64,
        object: u64,
        value: u64,
        secondary: u64,
        opcode: ?u8,
        packet_class: ?pm4.PacketClass,
        authentic: bool,
    ) void {
        const bit = vd_ring.causalStageBit(stage);
        const record = &self.stages[@intFromEnum(stage)];
        const first_observation = !record.seen;
        if (first_observation) {
            record.seen = true;
            record.first_step = step;
            if (stage.required() and !vd_ring.causalPrerequisitesMet(self.observed_mask, stage)) {
                self.out_of_order +|= 1;
            }
            self.observed_mask |= bit;
            if (stage.required()) self.last_progress_step = step;
        }
        record.count +|= 1;
        record.last_step = step;
        record.last_value = value;
        if (first_observation) {
            if (stage == .first_draw_consumed) {
                self.first_draw_consumed_recorded = true;
                self.first_draw_consumed_step = step;
            }
            self.recordEvent(.{
                .kind = kind,
                .stage = stage,
                .step = step,
                .thread = thread,
                .program_counter = program_counter,
                .object = object,
                .value = value,
                .secondary = secondary,
                .opcode = opcode,
                .packet_class = packet_class,
                .authentic = authentic,
            });
        }
    }

    /// Record an authentic downstream observation and only close the prefix it
    /// actually proves.  In particular, consuming XE_SWAP never implies that
    /// the guest entered VdSwap: Xenia can receive a packet through more than
    /// one producer path, and the trace must preserve that distinction.
    pub fn observeEvidence(self: *Ledger, stage: vd_ring.CausalStage, step: u64) void {
        switch (stage) {
            .pm4_packet_consumed => {
                self.observeStage(.ring_payload_prepared, step);
                self.observeStage(.ring_write_pointer_published, step);
            },
            .first_draw_consumed => {
                self.observeStage(.ring_payload_prepared, step);
                self.observeStage(.ring_write_pointer_published, step);
                self.observeStage(.pm4_packet_consumed, step);
                self.observeStage(.first_draw_submitted, step);
            },
            .authentic_swap_consumed => {
                self.observeStage(.frontbuffer_selected, step);
                self.observeStage(.swap_published, step);
            },
            .output_refresh => self.observeStage(.issue_swap, step),
            .native_presented => self.observeStage(.output_refresh, step),
            else => {},
        }
        self.observeStage(stage, step);
    }

    /// A read-only ring survey proves that the guest wrote bytes.  It proves a
    /// submitted draw only when a draw packet is present in that guest-owned
    /// memory; it does not prove that the command processor consumed anything.
    pub fn observeRingPayload(
        self: *Ledger,
        real_packets: u32,
        draws: u32,
        swaps: u32,
        step: u64,
        authentic_guest_memory: bool,
    ) void {
        if (real_packets == 0 and draws == 0 and swaps == 0) return;
        self.ring_payload_observations +|= 1;
        self.recordEvent(.{
            .kind = .ring_payload,
            .step = step,
            .value = real_packets,
            .secondary = (@as(u64, draws) << 32) | swaps,
            .authentic = authentic_guest_memory,
        });
        if (!authentic_guest_memory) return;
        if (real_packets != 0) self.observeStage(.pm4_state_programmed, step);
        if (draws != 0) {
            self.draw_observations +|= 1;
            self.observeStage(.first_draw_submitted, step);
        }
        if (swaps != 0) {
            self.swap_observations +|= 1;
            self.observeStage(.frontbuffer_selected, step);
        }
    }

    /// A command-processor execution summary is stronger than a memory scan,
    /// but it receives an explicit authenticity bit so a diagnostic injection
    /// cannot silently become a guest frame.
    pub fn observeConsumedBatch(
        self: *Ledger,
        packets: u32,
        draws: u32,
        swaps: u32,
        step: u64,
        authentic_guest_publication: bool,
    ) void {
        if (packets == 0 and draws == 0 and swaps == 0) return;
        self.pm4_consumption_observations +|= 1;
        self.recordEvent(.{
            .kind = .pm4_packet,
            .step = step,
            .value = packets,
            .secondary = (@as(u64, draws) << 32) | swaps,
            .authentic = authentic_guest_publication,
        });
        if (!authentic_guest_publication) return;
        if (packets != 0) self.observeEvidence(.pm4_packet_consumed, step);
        if (draws != 0) {
            self.draw_observations +|= 1;
            self.observeEvidence(.first_draw_consumed, step);
        }
        if (swaps != 0) {
            self.swap_observations +|= 1;
            self.observeEvidence(.authentic_swap_consumed, step);
        }
    }

    /// Classify one PM4 opcode using the immutable package table, then attach
    /// the packet to the appropriate producer/consumer boundary.
    pub fn observePm4Opcode(
        self: *Ledger,
        opcode: u8,
        step: u64,
        consumed: bool,
        authentic_guest_publication: bool,
    ) void {
        const class = pm4.classifyOpcode(opcode);
        self.packet_classes[@intFromEnum(class)] +|= 1;
        self.recordEvent(.{
            .kind = if (class == .draw) .draw else if (class == .emulator_extension) .swap else .pm4_packet,
            .step = step,
            .opcode = opcode,
            .packet_class = class,
            .authentic = authentic_guest_publication,
        });
        if (!authentic_guest_publication) return;
        if (class == .draw) {
            if (consumed) self.observeEvidence(.first_draw_consumed, step) else self.observeStage(.first_draw_submitted, step);
        } else if (class == .emulator_extension and consumed) {
            self.observeEvidence(.authentic_swap_consumed, step);
        } else if (consumed and class.contributesGuestWork()) {
            self.observeEvidence(.pm4_packet_consumed, step);
        } else if (class == .state) {
            self.observeStage(.pm4_state_programmed, step);
        }
    }

    /// Walk a bounded guest-owned span and retain PM4 semantic classes.  This
    /// is a diagnostic walk only; it does not execute packets or follow
    /// indirect buffers.  The stateful Xenos runtime remains the sole owner of
    /// execution and memory side effects.
    pub fn observePm4Span(
        self: *Ledger,
        bytes: []const u8,
        start_dword: u32,
        count_dwords: u32,
        ring_dwords: u32,
        step: u64,
        consumed: bool,
        authentic_guest_publication: bool,
    ) void {
        if (ring_dwords == 0 or @as(u64, ring_dwords) * 4 > bytes.len) return;
        const bounded = @min(count_dwords, ring_dwords);
        var index: u32 = 0;
        while (index < bounded) {
            const ring_index: u32 = @intCast((@as(u64, start_dword) + index) % ring_dwords);
            const offset = @as(usize, ring_index) * 4;
            const raw = std.mem.readInt(u32, bytes[offset..][0..4], .big);
            if (pm4.isLikelyEmptyRing(raw)) {
                index += 1;
                continue;
            }
            const packet = pm4.decode(raw);
            switch (packet.packet_type) {
                .type3 => self.observePm4Opcode(packet.opcode, step, consumed, authentic_guest_publication),
                .type0, .type1 => {
                    self.packet_classes[@intFromEnum(pm4.PacketClass.state)] +|= 1;
                    self.recordEvent(.{
                        .kind = .pm4_packet,
                        .step = step,
                        .value = packet.body_dwords,
                        .authentic = authentic_guest_publication,
                        .packet_class = .state,
                    });
                    if (authentic_guest_publication) {
                        if (consumed) self.observeEvidence(.pm4_packet_consumed, step) else self.observeStage(.pm4_state_programmed, step);
                    }
                },
                .type2 => {},
            }
            const advance = packet.advance();
            if (advance == 0 or advance > bounded - index) break;
            index += advance;
        }
    }

    /// Walk a retained PM4 envelope and follow its indirect-buffer references
    /// through a read-only guest-memory callback.  The primary ring often
    /// contains only setup plus INDIRECT_BUFFER packets; Xenia can execute
    /// every draw from the referenced ranges while a primary-only scan says
    /// `draws=0`.  This method keeps that distinction explicit.
    pub fn observePm4SpanWithIndirects(
        self: *Ledger,
        bytes: []const u8,
        start_dword: u32,
        count_dwords: u32,
        ring_dwords: u32,
        publication_generation: u64,
        step: u64,
        consumed: bool,
        authentic_guest_publication: bool,
        memory_context: ?*anyopaque,
        memory_callback: ?pm4_walk.MemoryReadCallback,
    ) pm4_walk.Summary {
        var walker = pm4_walk.Walker.init(memory_context, memory_callback);
        walker.walkRoot(bytes, start_dword, count_dwords, ring_dwords);
        const summary = walker.summary();
        const references = walker.referenceSlice();
        var fingerprint = indirectFingerprint(summary, references);
        fingerprint = (fingerprint ^ publication_generation) *% 0x100000001b3;
        fingerprint = (fingerprint ^ @intFromBool(consumed)) *% 0x100000001b3;
        fingerprint = (fingerprint ^ @intFromBool(authentic_guest_publication)) *% 0x100000001b3;
        const changed = self.indirect_walk_observations == 0 or fingerprint != self.last_indirect_fingerprint;

        self.indirect_walk_observations +|= 1;
        if (changed) self.indirect_walk_unique +|= 1 else self.indirect_walk_repeats +|= 1;

        if (changed) {
            if (summary.nested_draw_packets != 0) self.indirect_draw_observations +|= 1;
            if (summary.nested_swap_packets != 0) self.indirect_swap_observations +|= 1;
            if (summary.unreadable_references != 0) self.indirect_unreadable_observations +|= 1;
            if (summary.cycle_references != 0) self.indirect_cycle_observations +|= 1;
            for (summary.packet_class_counts, 0..) |count, index| {
                self.packet_classes[index] +|= count;
            }
            self.last_indirect_fingerprint = fingerprint;
            self.last_indirect_summary = summary;
            self.last_indirect_reference_count = @min(references.len, self.last_indirect_references.len);
            self.last_indirect_references_dropped = walker.droppedReferenceCount();
            for (references[0..self.last_indirect_reference_count], 0..) |reference, index| {
                self.last_indirect_references[index] = reference;
                self.recordEvent(.{
                    .kind = .indirect_buffer,
                    .step = step,
                    .object = reference.address,
                    .value = reference.size_dwords,
                    .secondary = (@as(u64, reference.draws) << 32) | reference.packets,
                    .opcode = reference.opcode,
                    .packet_class = .indirect,
                    .authentic = authentic_guest_publication,
                });
            }
        }

        // Re-reading the same publication is a diagnostic observation, not a
        // second PM4 submission. Only a new content/generation/disposition key
        // may advance semantic stages or packet-class totals.
        if (!changed or !authentic_guest_publication or summary.packets_walked == 0) return summary;
        if (summary.draw_packets != 0) {
            self.draw_observations +|= 1;
            if (consumed) self.observeEvidence(.first_draw_consumed, step) else self.observeStage(.first_draw_submitted, step);
        } else if (consumed) {
            self.observeEvidence(.pm4_packet_consumed, step);
        } else {
            self.observeStage(.pm4_state_programmed, step);
        }
        if (summary.swap_packets != 0) {
            self.swap_observations +|= 1;
            self.observeStage(.swap_packet_encoded, step);
            if (consumed) self.observeEvidence(.authentic_swap_consumed, step);
        }
        return summary;
    }

    /// Record a write even when it is a repeated value.  A changed value is
    /// the only pointer observation that proves publication; the first value
    /// is deliberately not treated as an advance because its predecessor is
    /// unknown.
    pub fn observeWritePointer(self: *Ledger, value: u32, step: u64) void {
        const previous = self.last_wptr;
        self.last_wptr = value;
        self.recordEvent(.{ .kind = .ring_write_pointer, .step = step, .value = value });
        if (previous) |old| {
            if (old != value) self.observeStage(.ring_write_pointer_published, step);
        }
    }

    /// Consume the structured Xenia/Rosette evidence stream.  Unknown lines
    /// are ignored, so the tracer can be attached to an existing run without
    /// changing the logging contract of unrelated subsystems.
    pub fn observeLine(self: *Ledger, line: []const u8, step: u64) bool {
        var recognized = false;
        const thread = parseHexField64(line, "thread=") orelse 0;
        const program_counter = parseHexField64(line, "guest_pc=") orelse
            parseHexField64(line, "rip=") orelse 0;

        if (contains(line, "VDSWAP PATH: stage=entered")) {
            self.observeStageWith(.guest_vdswap_entered, step, .stage, thread, program_counter, 0, 0, 0, null, null, true);
            recognized = true;
        } else if (contains(line, "VDSWAP PATH: stage=packet_encoded")) {
            self.observeStageWith(.swap_packet_encoded, step, .stage, thread, program_counter, 0, 0, 0, null, null, true);
            recognized = true;
        } else if (contains(line, "VDSWAP PATH: stage=completed")) {
            self.observeStageWith(.guest_vdswap_completed, step, .stage, thread, program_counter, 0, 0, 0, null, null, true);
            recognized = true;
        }

        if (contains(line, "RING BUFFER: authentic payload prepared")) {
            self.observeStageWith(.ring_payload_prepared, step, .ring_payload, thread, program_counter, 0, 0, 0, null, null, true);
            recognized = true;
        }
        if (contains(line, "RING BUFFER: first authentic PM4 packet consumed") or
            contains(line, "PM4 AUTHENTIC MILESTONE: first guest-published command batch consumed"))
        {
            self.observeEvidence(.pm4_packet_consumed, step);
            recognized = true;
        }
        if (contains(line, "PM4 AUTHENTIC MILESTONE: first guest-published PM4_XE_SWAP consumed")) {
            self.observeEvidence(.authentic_swap_consumed, step);
            recognized = true;
        }

        if (contains(line, "DEBUG: REGISTER WRITE: CP_RB_WPTR")) {
            if (parseHexField(line, "CP_RB_WPTR = ")) |value| {
                self.observeWritePointer(value, step);
                recognized = true;
            } else if (parseHexField(line, "CP_RB_WPTR=")) |value| {
                self.observeWritePointer(value, step);
                recognized = true;
            }
        }

        // These summaries are also accepted here for replay tests and for a
        // future Xenia-side structured log sink. The live process feeds the
        // same data directly through observeRingPayload/observeConsumedBatch,
        // which keeps provenance explicit even when a line is interleaved.
        if (contains(line, "RING PAYLOAD:")) {
            const real_packets = parseDecimalField(line, "real_packets=") orelse 0;
            const draws = parseDecimalField(line, "draws=") orelse 0;
            const swaps = parseDecimalField(line, "swaps=") orelse 0;
            if (real_packets != 0 or draws != 0 or swaps != 0) {
                self.observeRingPayload(real_packets, draws, swaps, step, true);
                recognized = true;
            }
        }
        if (contains(line, "XENOS PM4 execution:")) {
            const packets = parseDecimalField(line, "packets=") orelse 0;
            const draws = parseDecimalField(line, "draws=") orelse 0;
            const swaps = parseDecimalField(line, "swaps=") orelse 0;
            const authentic = contains(line, "authentic") or contains(line, "guest_wptr") or contains(line, "provenance=guest");
            if (packets != 0 or draws != 0 or swaps != 0) {
                self.observeConsumedBatch(packets, draws, swaps, step, authentic);
                recognized = true;
            }
        }

        const authentic = contains(line, "AUTHENTIC") or contains(line, "guest-published") or contains(line, "provenance=guest");
        if (contains(line, "IssueSwap")) {
            self.recordEvent(.{ .kind = if (authentic) .swap else .unproven_handoff, .step = step, .program_counter = program_counter, .authentic = authentic });
            if (authentic) self.observeEvidence(.issue_swap, step);
            recognized = true;
        }
        if (contains(line, "RefreshGuestOutput")) {
            self.recordEvent(.{ .kind = if (authentic) .swap else .unproven_handoff, .step = step, .program_counter = program_counter, .authentic = authentic });
            if (authentic) self.observeEvidence(.output_refresh, step);
            recognized = true;
        }
        if (contains(line, "presentation authority=native provenance=AUTHENTIC") or
            contains(line, "authentic native presentation"))
        {
            self.observeEvidence(.native_presented, step);
            recognized = true;
        }

        if (contains(line, "KeWaitForSingleObject") or contains(line, "KeWaitForMutex") or contains(line, "KeWaitForEvent")) {
            self.recordEvent(.{
                .kind = .wait,
                .step = step,
                .thread = thread,
                .object = parseHexField64(line, "guest_obj=") orelse parseHexField64(line, "obj_ptr=") orelse parseHexField64(line, "handle=") orelse 0,
                .value = parseHexField64(line, "result=") orelse 0,
                .secondary = parseHexField64(line, "wait=") orelse 0,
            });
            recognized = true;
        }
        if (contains(line, "KeSetEvent") or contains(line, "KeReleaseSemaphore") or contains(line, "GPU CRITICAL SECTION: released")) {
            self.recordEvent(.{
                .kind = .signal,
                .step = step,
                .thread = thread,
                .object = parseHexField64(line, "guest_obj=") orelse parseHexField64(line, "obj_ptr=") orelse parseHexField64(line, "handle=") orelse 0,
                .value = parseHexField64(line, "result=") orelse 0,
            });
            recognized = true;
        }
        if (contains(line, "FinishLoadingUserModule") or contains(line, "DllMain")) {
            self.recordEvent(.{ .kind = .module_initialization, .step = step, .thread = thread, .program_counter = program_counter });
            recognized = true;
        }
        if (contains(line, "scheduler:") or contains(line, "guest log cycle:")) {
            self.recordEvent(.{ .kind = .scheduler, .step = step, .thread = thread, .program_counter = program_counter, .value = parseDecimalField(line, "step=") orelse 0 });
            recognized = true;
        }

        return recognized;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.total_events == 0) return "no causal GPU evidence observed";
        if (self.firstGap()) |gap| return gap.guidance();
        return "the complete authentic causal graphics path was observed";
    }

    /// Emit a compact summary plus the retained tail.  The tail is useful for
    /// a live timeout because the clean exit path may never run, while the
    /// fixed ring keeps a chatty wait loop from growing without bound.
    pub fn logSummary(self: *const Ledger, current_step: u64, force: bool) void {
        if (self.total_events == 0 and !force) return;
        const gap = self.firstGap();
        machoCapturePrint(
            "macho-processor: XENIA GPU CAUSAL TRACE: observed_mask=0x{x:0>4} frontier={s} owner={s} events={d} tail_evictions={d} out_of_order={d} cycles={d} cycle_repetitions={d} last_progress_step={d} quiet_steps={d} post_draw_waits={d} post_draw_signals={d} verdict={s}; tail_evictions only age records out of this bounded diagnostic view—the live run journal receives new events before eviction\n",
            .{
                self.observed_mask,
                if (gap) |stage| stage.label() else "<complete>",
                if (gap) |stage| stage.owner() else "-",
                self.total_events,
                self.events_dropped,
                self.out_of_order,
                self.cycle_reports,
                self.cycle_repetitions,
                self.last_progress_step,
                self.noProgressSteps(current_step) orelse 0,
                self.wait_events_after_draw,
                self.signal_events_after_draw,
                self.verdict(),
            },
        );
        inline for (@typeInfo(pm4.PacketClass).@"enum".fields) |field| {
            const class: pm4.PacketClass = @enumFromInt(field.value);
            const count = self.packet_classes[@intFromEnum(class)];
            if (force or count != 0) {
                machoCapturePrint(
                    "  pm4 class={s: <20} packets={d} contributes_guest_work={s}\n",
                    .{ class.label(), count, if (class.contributesGuestWork()) "YES" else "NO" },
                );
            }
        }
        if (force or self.indirect_walk_observations != 0) {
            const indirect = self.last_indirect_summary;
            machoCapturePrint(
                "macho-processor: XENIA PM4 INDIRECT WALK: observations={d} unique={d} repeats={d} root_packets={d} nested_packets={d} indirect_packets={d} refs={d} readable={d} unreadable={d} truncated_refs={d} budget_refs={d} draws(root/nested/total)={d}/{d}/{d} swaps(root/nested/total)={d}/{d}/{d} waits={d} unknown={d} cycles={d} truncated={s} budget={s}\n",
                .{
                    self.indirect_walk_observations,
                    self.indirect_walk_unique,
                    self.indirect_walk_repeats,
                    indirect.root_packets,
                    indirect.nested_packets,
                    indirect.indirect_packets,
                    indirect.indirect_references,
                    indirect.readable_references,
                    indirect.unreadable_references,
                    indirect.truncated_references,
                    indirect.budget_limited_references,
                    indirect.root_draw_packets,
                    indirect.nested_draw_packets,
                    indirect.draw_packets,
                    indirect.root_swap_packets,
                    indirect.nested_swap_packets,
                    indirect.swap_packets,
                    indirect.wait_packets,
                    indirect.unknown_packets,
                    indirect.cycle_references,
                    if (indirect.root_truncated) "YES" else "NO",
                    if (indirect.packet_budget_exhausted) "YES" else "NO",
                },
            );
            for (self.last_indirect_references[0..self.last_indirect_reference_count]) |reference| {
                machoCapturePrint(
                    "  pm4 indirect depth={d} opcode=0x{x:0>2} address=0x{x:0>8} size_dwords={d} status={s} missing_address=0x{x:0>8} packets={d} draws={d} swaps={d} words_read={d}\n",
                    .{
                        reference.depth,
                        reference.opcode,
                        reference.address,
                        reference.size_dwords,
                        reference.status.label(),
                        reference.missing_address orelse 0,
                        reference.packets,
                        reference.draws,
                        reference.swaps,
                        reference.words_read,
                    },
                );
            }
        }
        for (vd_ring.causal_order) |stage| {
            const record = self.stages[@intFromEnum(stage)];
            if (!force and !record.seen) continue;
            machoCapturePrint(
                "  causal stage={s: <31} owner={s: <28} seen={s} count={d} first_step={d} last_step={d} value=0x{x}\n",
                .{
                    stage.label(),
                    stage.owner(),
                    if (record.seen) "YES" else "NO",
                    record.count,
                    record.first_step,
                    record.last_step,
                    record.last_value,
                },
            );
        }
        inline for (@typeInfo(vd_ring.HandoffBoundary).@"enum".fields) |field| {
            const boundary: vd_ring.HandoffBoundary = @enumFromInt(field.value);
            const prerequisite = boundary.prerequisite();
            machoCapturePrint(
                "  causal boundary={s: <31} owner={s: <28} state={s} prerequisite={s}\n",
                .{
                    boundary.label(),
                    boundary.owner(),
                    if (vd_ring.handoffReady(self.observed_mask, boundary)) "READY" else "WAITING",
                    prerequisite.label(),
                },
            );
        }
        if (self.cycle_reports != 0) {
            machoCapturePrint(
                "  causal cycle: repeated semantic tail reports={d} repetitions={d} last_step={d}; inspect the retained wait/signal/module events before assigning ownership to the presenter\n",
                .{ self.cycle_reports, self.cycle_repetitions, self.last_cycle_step },
            );
        }
        const retained = @min(self.event_count, @as(usize, 8));
        var index: usize = 0;
        while (index < retained) : (index += 1) {
            const event = self.retainedEvent(self.event_count - retained + index);
            machoCapturePrint(
                "  causal event seq={d} kind={s: <18} step={d} thread=0x{x} object=0x{x} value=0x{x} authentic={s} stage={s} opcode=0x{x:0>2} class={s}\n",
                .{
                    event.sequence,
                    event.kind.label(),
                    event.step,
                    event.thread,
                    event.object,
                    event.value,
                    if (event.authentic) "YES" else "NO",
                    if (event.stage) |stage| stage.label() else "-",
                    event.opcode orelse 0xFF,
                    if (event.packet_class) |class| class.label() else "-",
                },
            );
        }
    }

    fn recordEvent(self: *Ledger, event: Event) void {
        var recorded = event;
        self.total_events +|= 1;
        recorded.sequence = self.total_events;
        self.last_event_step = event.step;
        if (self.event_count < max_events) {
            const index = (self.event_cursor + self.event_count) % max_events;
            self.events[index] = recorded;
            self.event_count += 1;
        } else {
            self.events[self.event_cursor] = recorded;
            self.event_cursor = (self.event_cursor + 1) % max_events;
            self.events_dropped +|= 1;
        }
        self.noteSignature(.{
            .kind = recorded.kind,
            .stage = if (recorded.stage) |stage| @intFromEnum(stage) else 0xFF,
            .object = recorded.object,
            .value = recorded.value,
            .opcode = recorded.opcode orelse 0xFF,
        }, event.step);
        if (recorded.kind == .wait and self.first_draw_consumed_recorded and
            recorded.step >= self.first_draw_consumed_step)
        {
            self.wait_events_after_draw +|= 1;
        } else if (recorded.kind == .signal and self.first_draw_consumed_recorded and
            recorded.step >= self.first_draw_consumed_step)
        {
            self.signal_events_after_draw +|= 1;
        }
    }

    fn retainedEvent(self: *const Ledger, ordinal: usize) Event {
        return self.events[(self.event_cursor + ordinal) % max_events];
    }

    /// Retrieve a just-recorded event by its durable sequence. The guest-log
    /// bridge calls this immediately, before the small diagnostic tail can
    /// overwrite it, and copies the event into the larger run journal.
    pub fn eventForSequence(self: *const Ledger, sequence: u64) ?Event {
        if (sequence == 0 or self.event_count == 0) return null;
        const first_retained = self.total_events - @as(u64, @intCast(self.event_count)) + 1;
        if (sequence < first_retained or sequence > self.total_events) return null;
        return self.retainedEvent(@intCast(sequence - first_retained));
    }

    fn noteSignature(self: *Ledger, signature: Signature, step: u64) void {
        if (self.recent_count < recent_signature_capacity) {
            self.recent_signatures[self.recent_count] = signature;
            self.recent_count += 1;
        } else {
            var index: usize = 1;
            while (index < recent_signature_capacity) : (index += 1) {
                self.recent_signatures[index - 1] = self.recent_signatures[index];
            }
            self.recent_signatures[recent_signature_capacity - 1] = signature;
        }
        if (self.recent_count < recent_signature_capacity) return;

        var equal_halves = true;
        var index: usize = 0;
        while (index < cycle_width) : (index += 1) {
            if (!signatureEqual(
                self.recent_signatures[index],
                self.recent_signatures[index + cycle_width],
            )) {
                equal_halves = false;
                break;
            }
        }
        if (!equal_halves) return;
        const fingerprint = signatureFingerprint(self.recent_signatures[0..recent_signature_capacity]);
        if (fingerprint == self.last_cycle_signature) {
            self.cycle_repetitions +|= 1;
        } else {
            self.last_cycle_signature = fingerprint;
            self.cycle_reports +|= 1;
            self.cycle_repetitions = 1;
        }
        self.last_cycle_step = step;
    }
};

fn signatureEqual(left: Signature, right: Signature) bool {
    return left.kind == right.kind and left.stage == right.stage and
        left.object == right.object and left.value == right.value and left.opcode == right.opcode;
}

fn signatureFingerprint(signatures: []const Signature) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (signatures) |signature| {
        hash = (hash ^ @intFromEnum(signature.kind)) *% 0x100000001b3;
        hash = (hash ^ signature.stage) *% 0x100000001b3;
        hash = (hash ^ signature.object) *% 0x100000001b3;
        hash = (hash ^ signature.value) *% 0x100000001b3;
        hash = (hash ^ signature.opcode) *% 0x100000001b3;
    }
    return hash;
}

fn indirectFingerprint(summary: pm4_walk.Summary, references: []const pm4_walk.Reference) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    const values = [_]u64{
        summary.root_packets,
        summary.nested_packets,
        summary.root_draw_packets,
        summary.nested_draw_packets,
        summary.root_swap_packets,
        summary.nested_swap_packets,
        summary.indirect_references,
        summary.unreadable_references,
        summary.truncated_references,
        summary.budget_limited_references,
        summary.cycle_references,
        summary.content_fingerprint,
        if (summary.root_truncated) 1 else 0,
    };
    for (values) |value| hash = (hash ^ value) *% 0x100000001b3;
    for (references) |reference| {
        hash = (hash ^ reference.address) *% 0x100000001b3;
        hash = (hash ^ reference.size_dwords) *% 0x100000001b3;
        hash = (hash ^ @intFromEnum(reference.status)) *% 0x100000001b3;
        hash = (hash ^ (reference.missing_address orelse 0)) *% 0x100000001b3;
        hash = (hash ^ reference.packets) *% 0x100000001b3;
        hash = (hash ^ reference.draws) *% 0x100000001b3;
        hash = (hash ^ reference.swaps) *% 0x100000001b3;
    }
    return hash;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn parseHexField(line: []const u8, marker: []const u8) ?u32 {
    const value = parseHexField64(line, marker) orelse return null;
    return @intCast(value);
}

fn parseHexField64(line: []const u8, marker: []const u8) ?u64 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[marker_index + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 16) catch null;
}

fn parseDecimalField(line: []const u8, marker: []const u8) ?u32 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    const text = line[marker_index + marker.len ..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isDigit(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u32, text[0..length], 10) catch null;
}

test "causal trace identifies the first draw frontier" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.observeLine("RING BUFFER: authentic payload prepared", 10));
    try std.testing.expect(ledger.observeLine("DEBUG: REGISTER WRITE: CP_RB_WPTR = 00000000", 11));
    try std.testing.expect(ledger.observeLine("DEBUG: REGISTER WRITE: CP_RB_WPTR = 00000019", 12));
    try std.testing.expect(ledger.observeLine(
        "XENOS PM4 execution: packets=8 draws=0 events=1 swaps=0 authentic=YES",
        20,
    ));

    try std.testing.expect(ledger.observed(.pm4_packet_consumed));
    try std.testing.expectEqual(vd_ring.CausalStage.first_draw_submitted, ledger.firstGap().?);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "draw packet") != null);
}

test "a consumed draw advances the draw boundary but not VdSwap" {
    var ledger = Ledger{};
    ledger.observeConsumedBatch(8, 1, 0, 100, true);
    try std.testing.expect(ledger.observed(.first_draw_submitted));
    try std.testing.expect(ledger.observed(.first_draw_consumed));
    try std.testing.expectEqual(vd_ring.CausalStage.guest_vdswap_entered, ledger.firstGap().?);
    try std.testing.expect(!vd_ring.handoffReady(ledger.observed_mask, .title_to_command_processor));
}

test "a newly recorded causal event is retrievable before tail eviction" {
    var ledger = Ledger{};
    ledger.observeWritePointer(0x16, 10);
    const event = ledger.eventForSequence(1).?;
    try std.testing.expectEqual(EventKind.ring_write_pointer, event.kind);
    try std.testing.expectEqual(@as(u64, 0x16), event.value);
    try std.testing.expect(ledger.eventForSequence(0) == null);
    try std.testing.expect(ledger.eventForSequence(2) == null);
}

test "post-draw wait and signal evidence is anchored after draw consumption" {
    var ledger = Ledger{};
    ledger.observeConsumedBatch(8, 1, 0, 100, true);
    _ = ledger.observeLine("KeWaitForSingleObject guest_obj=827CEC14 result=00000000 wait=0", 101);
    _ = ledger.observeLine("KeReleaseSemaphore guest_obj=827CEC14 result=00000000", 102);
    try std.testing.expectEqual(@as(?u64, 100), ledger.firstDrawConsumedStep());
    try std.testing.expect(ledger.postDrawWaitObserved());
    try std.testing.expectEqual(@as(u64, 1), ledger.wait_events_after_draw);
    try std.testing.expectEqual(@as(u64, 1), ledger.signal_events_after_draw);
}

test "diagnostic PM4 execution never becomes authentic evidence" {
    var ledger = Ledger{};
    ledger.observeConsumedBatch(12, 1, 1, 100, false);
    try std.testing.expect(!ledger.observed(.pm4_packet_consumed));
    try std.testing.expect(!ledger.observed(.first_draw_consumed));
    try std.testing.expect(!ledger.observed(.authentic_swap_consumed));
    try std.testing.expectEqual(@as(u64, 1), ledger.pm4_consumption_observations);
}

test "the bounded PM4 walk classifies a draw without executing it" {
    var bytes = [_]u8{0} ** 16;
    const draw_header: u32 = 0xC000_0000 | (@as(u32, 0x22) << 8);
    std.mem.writeInt(u32, bytes[0..4], draw_header, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x0000_0001, .big);

    var ledger = Ledger{};
    ledger.observeStage(.ring_payload_prepared, 1);
    ledger.observeStage(.ring_write_pointer_published, 2);
    ledger.observePm4Span(&bytes, 0, 2, 4, 3, false, true);
    try std.testing.expect(ledger.observed(.first_draw_submitted));
    try std.testing.expectEqual(@as(u64, 1), ledger.packet_classes[@intFromEnum(pm4.PacketClass.draw)]);

    ledger.observePm4Span(&bytes, 0, 2, 4, 4, true, true);
    try std.testing.expect(ledger.observed(.first_draw_consumed));
}

test "causal trace promotes a draw found in an indirect buffer" {
    const Memory = struct {
        words: [128]u32 = [_]u32{0} ** 128,

        fn read(context: *anyopaque, address: u32) ?u32 {
            const self: *@This() = @ptrCast(@alignCast(context));
            if ((address & 3) != 0 or address / 4 >= self.words.len) return null;
            return self.words[address / 4];
        }
    };

    var bytes = [_]u8{0} ** 16;
    const indirect_header: u32 = 0xC000_0000 | (@as(u32, 1) << 16) | (@as(u32, 0x3F) << 8);
    std.mem.writeInt(u32, bytes[0..4], indirect_header, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x0000_0100, .big);
    std.mem.writeInt(u32, bytes[8..12], 2, .big);

    var memory = Memory{};
    memory.words[0x100 / 4] = 0xC000_0000 | (@as(u32, 0x22) << 8);
    memory.words[0x104 / 4] = 1;

    var ledger = Ledger{};
    const summary = ledger.observePm4SpanWithIndirects(
        &bytes,
        0,
        4,
        4,
        1,
        100,
        true,
        true,
        &memory,
        Memory.read,
    );
    try std.testing.expectEqual(@as(u32, 1), summary.nested_draw_packets);
    try std.testing.expect(ledger.observed(.first_draw_consumed));
    try std.testing.expectEqual(@as(usize, 1), ledger.last_indirect_reference_count);
    try std.testing.expectEqual(@as(u32, 1), ledger.last_indirect_references[0].draws);

    const draw_classes = ledger.packet_classes[@intFromEnum(pm4.PacketClass.draw)];
    _ = ledger.observePm4SpanWithIndirects(
        &bytes,
        0,
        4,
        4,
        1,
        101,
        true,
        true,
        &memory,
        Memory.read,
    );
    try std.testing.expectEqual(@as(u64, 2), ledger.indirect_walk_observations);
    try std.testing.expectEqual(@as(u64, 1), ledger.indirect_walk_unique);
    try std.testing.expectEqual(@as(u64, 1), ledger.indirect_walk_repeats);
    try std.testing.expectEqual(draw_classes, ledger.packet_classes[@intFromEnum(pm4.PacketClass.draw)]);

    _ = ledger.observePm4SpanWithIndirects(
        &bytes,
        0,
        4,
        4,
        2,
        102,
        true,
        true,
        &memory,
        Memory.read,
    );
    try std.testing.expectEqual(@as(u64, 2), ledger.indirect_walk_unique);
    try std.testing.expect(ledger.packet_classes[@intFromEnum(pm4.PacketClass.draw)] > draw_classes);
}

test "repeated wait and signal semantics are retained as a bounded cycle" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < 24) : (index += 1) {
        _ = ledger.observeLine("KeWaitForSingleObject guest_obj=827CEC14 result=00000000 wait=0", index + 1);
        _ = ledger.observeLine("KeReleaseSemaphore guest_obj=827CEC14 result=00000000", index + 1);
    }
    try std.testing.expect(ledger.total_events >= 48);
    try std.testing.expect(ledger.event_count <= max_events);
    try std.testing.expect(ledger.cycle_reports != 0);
    try std.testing.expect(ledger.events_dropped == 0);
}

test "event retention is bounded when the guest is chatty" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < max_events + 17) : (index += 1) {
        ledger.observePm4Opcode(0x7F, index + 1, false, false);
    }
    try std.testing.expectEqual(max_events, ledger.event_count);
    try std.testing.expectEqual(@as(u64, 17), ledger.events_dropped);
    try std.testing.expectEqual(@as(u64, max_events + 17), ledger.total_events);
}
