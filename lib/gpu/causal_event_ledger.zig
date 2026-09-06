//! Run-scoped causal identity for the Xenia/Rosette graphics boundary.
//!
//! Counters answer how often a subsystem spoke. They do not answer whether two
//! speakers were describing one request, whether a callback was delivered
//! twice, or whether a later stage was allowed to advance. This ledger is the
//! authority for those questions. It is intentionally bounded and append-only:
//! a full ledger reports loss and refuses to advance a contract edge rather
//! than evicting the parent that makes a later record meaningful.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const Record = bridge.event.Record;
pub const Domain = bridge.contract.Domain;
pub const EventKind = bridge.contract.EventKind;
pub const SourceClass = bridge.contract.SourceClass;
pub const ResultClass = bridge.contract.ResultClass;
pub const Provenance = bridge.contract.Provenance;
pub const ContractEdge = bridge.contract.ContractEdge;
pub const Effect = bridge.contract.Effect;

pub const capacity: usize = 1024;
pub const request_identity_capacity: usize = 256;

pub const AppendOutcome = enum(u8) {
    accepted,
    missing_parent,
    unknown_parent,
    wrong_run,
    duplicate_delivery,
    full,

    pub fn label(self: AppendOutcome) []const u8 {
        return switch (self) {
            .accepted => "accepted",
            .missing_parent => "missing-parent",
            .unknown_parent => "unknown-parent",
            .wrong_run => "wrong-run",
            .duplicate_delivery => "duplicate-delivery",
            .full => "ledger-full",
        };
    }

    pub fn valid(self: AppendOutcome) bool {
        return self == .accepted;
    }
};

pub const Summary = struct {
    run_id: u64 = 0,
    records: u64 = 0,
    accepted: u64 = 0,
    rejected: u64 = 0,
    duplicate_deliveries: u64 = 0,
    missing_parents: u64 = 0,
    unknown_parents: u64 = 0,
    wrong_run: u64 = 0,
    dropped: u64 = 0,
    edge_violations: u64 = 0,
    authenticity_violations: u64 = 0,
    last_guest_step: u64 = 0,
    last_event_id: u64 = 0,
};

const RequestIdentity = struct {
    correlation_id: u64 = 0,
    subject_id: u64 = 0,
    used: bool = false,
};

pub const Ledger = struct {
    run_id: u64 = 0,
    next_event_id: u64 = 1,
    records: [capacity]Record = [_]Record{.{}} ** capacity,
    record_count: usize = 0,
    last_by_edge: [edge_count]u64 = [_]u64{0} ** edge_count,
    delivered_requests: [request_identity_capacity]RequestIdentity = [_]RequestIdentity{.{}} ** request_identity_capacity,
    delivered_request_count: usize = 0,
    summary_state: Summary = .{},

    pub fn open(self: *Ledger, run_id: u64) void {
        self.* = .{ .run_id = run_id, .summary_state = .{ .run_id = run_id } };
    }

    pub fn isOpen(self: *const Ledger) bool {
        return self.run_id != 0;
    }

    pub fn summary(self: *const Ledger) Summary {
        return self.summary_state;
    }

    pub fn retained(self: *const Ledger) []const Record {
        return self.records[0..self.record_count];
    }

    pub fn lastFor(self: *const Ledger, edge: ContractEdge) ?Record {
        const event_id = self.last_by_edge[edgeIndex(edge)];
        if (event_id == 0) return null;
        for (self.retained()) |record| {
            if (record.event_id == event_id) return record;
        }
        return null;
    }

    /// Append one event. The ledger fills the run/event/global identity and
    /// refuses a causal edge whose parent is absent or unretained.
    pub fn append(self: *Ledger, input: Record) AppendOutcome {
        if (!self.isOpen()) return self.reject(.wrong_run, input);
        if (self.record_count >= capacity) {
            self.summary_state.dropped +|= 1;
            self.summary_state.rejected +|= 1;
            return .full;
        }

        var record = input;
        if (record.run_id != 0 and record.run_id != self.run_id) return self.reject(.wrong_run, record);
        record.run_id = self.run_id;
        record.event_id = self.next_event_id;
        record.global_sequence = self.next_event_id;
        self.next_event_id +|= 1;
        self.summary_state.records +|= 1;
        self.summary_state.last_event_id = record.event_id;
        if (record.guest_step > self.summary_state.last_guest_step) self.summary_state.last_guest_step = record.guest_step;

        const edge = record.edgeOf();
        const prerequisite = edge.prerequisite();
        var outcome: AppendOutcome = .accepted;
        if (prerequisite != .none) {
            const required_id = self.last_by_edge[edgeIndex(prerequisite)];
            if (record.parent_event_id == 0) {
                if (required_id == 0) {
                    self.summary_state.missing_parents +|= 1;
                    outcome = .missing_parent;
                } else {
                    record.parent_event_id = required_id;
                }
            } else if (!self.containsEvent(record.parent_event_id)) {
                self.summary_state.unknown_parents +|= 1;
                outcome = .unknown_parent;
            } else if (required_id != 0 and record.parent_event_id != required_id) {
                // A stale parent is just as unsafe as no parent. It can make a
                // previous generation appear to satisfy the current phase.
                self.summary_state.edge_violations +|= 1;
                outcome = .unknown_parent;
            }
        } else if (record.parent_event_id != 0 and !self.containsEvent(record.parent_event_id)) {
            self.summary_state.unknown_parents +|= 1;
            outcome = .unknown_parent;
        }

        if (!provenanceMayAdvance(record.provenanceOf(), edge)) {
            self.summary_state.authenticity_violations +|= 1;
            self.summary_state.edge_violations +|= 1;
            outcome = .missing_parent;
        }

        if (edge == .callback_delivery and self.seenDelivery(record.correlation_id, record.subject_id)) {
            self.summary_state.duplicate_deliveries +|= 1;
            self.summary_state.edge_violations +|= 1;
            outcome = .duplicate_delivery;
        }

        self.records[self.record_count] = record;
        self.record_count += 1;
        self.summary_state.accepted +|= @intFromBool(outcome == .accepted);
        self.summary_state.rejected +|= @intFromBool(outcome != .accepted);
        if (outcome == .accepted) {
            if (edge != .none) self.last_by_edge[edgeIndex(edge)] = record.event_id;
            if (edge == .callback_delivery) self.rememberDelivery(record.correlation_id, record.subject_id);
        }
        return outcome;
    }

    /// Append a normalized event without making every caller know the wire
    /// layout. The result is the event id only when the edge advanced.
    pub fn advance(
        self: *Ledger,
        kind: EventKind,
        domain: Domain,
        edge: ContractEdge,
        provenance: Provenance,
        source: SourceClass,
        parent_event_id: u64,
        correlation_id: u64,
        subject_id: u64,
        generation: u64,
        guest_step: u64,
        guest_thread: u64,
        host_thread: u64,
        state_hash: u64,
        effect_mask: u64,
        effect_hash: u64,
    ) ?u64 {
        const record = Record{
            .kind = @intFromEnum(kind),
            .domain = @intFromEnum(domain),
            .source_class = @intFromEnum(source),
            .result_class = @intFromEnum(if (effect_mask != 0) ResultClass.applied else ResultClass.observed),
            .provenance = @intFromEnum(provenance),
            .contract_edge = @intFromEnum(edge),
            .parent_event_id = parent_event_id,
            .correlation_id = correlation_id,
            .subject_id = subject_id,
            .generation = generation,
            .guest_step = guest_step,
            .guest_thread = guest_thread,
            .host_thread = host_thread,
            .state_hash = state_hash,
            .effect_mask = effect_mask,
            .effect_hash = effect_hash,
        };
        const before = self.next_event_id;
        const outcome = self.append(record);
        if (!outcome.valid()) return null;
        return before;
    }

    pub fn callbackRegistration(self: *Ledger, callback: u64, user_data: u64, generation: u64, step: u64, thread: u64) ?u64 {
        return self.advance(.interrupt_dispatch, .xenia_kernel, .callback_registration, .guest, .guest_authentic, 0, generation, callback, generation, step, thread, 0, 0, 0, user_data);
    }

    pub fn callbackRequest(self: *Ledger, parent: u64, request_id: u64, generation: u64, step: u64, host_thread: u64) ?u64 {
        return self.advance(.callback_request, .xenia_command_processor, .callback_request, .xenia, .host_forwarded, parent, request_id, request_id, generation, step, 0, host_thread, 0, 0, 0);
    }

    pub fn callbackDelivery(self: *Ledger, parent: u64, request_id: u64, generation: u64, step: u64, guest_thread: u64, host_thread: u64) ?u64 {
        return self.advance(.callback_delivery, .xenia_kernel, .callback_delivery, .xenia, .host_forwarded, parent, request_id, request_id, generation, step, guest_thread, host_thread, 0, 0, 0);
    }

    pub fn callbackEffect(self: *Ledger, parent: u64, request_id: u64, generation: u64, step: u64, guest_thread: u64, effect: Effect, state_hash: u64, effect_hash: u64) ?u64 {
        return self.advance(.state_effect, .guest_title, .callback_effect, .guest, .guest_authentic, parent, request_id, request_id, generation, step, guest_thread, 0, state_hash, effect.bit(), effect_hash);
    }

    pub fn firstMissing(self: *const Ledger) ContractEdge {
        inline for (causal_chain) |edge| {
            if (self.last_by_edge[edgeIndex(edge)] == 0) return edge;
        }
        return .none;
    }

    pub fn authenticReady(self: *const Ledger) bool {
        return self.summary_state.edge_violations == 0 and self.summary_state.dropped == 0;
    }

    fn reject(self: *Ledger, outcome: AppendOutcome, record: Record) AppendOutcome {
        self.summary_state.records +|= 1;
        self.summary_state.rejected +|= 1;
        switch (outcome) {
            .wrong_run => self.summary_state.wrong_run +|= 1,
            .missing_parent => self.summary_state.missing_parents +|= 1,
            .unknown_parent => self.summary_state.unknown_parents +|= 1,
            else => {},
        }
        _ = record;
        return outcome;
    }

    fn containsEvent(self: *const Ledger, event_id: u64) bool {
        if (event_id == 0) return false;
        for (self.retained()) |record| {
            if (record.event_id == event_id) return true;
        }
        return false;
    }

    fn seenDelivery(self: *const Ledger, correlation_id: u64, subject_id: u64) bool {
        if (correlation_id == 0 and subject_id == 0) return false;
        for (self.delivered_requests[0..self.delivered_request_count]) |identity| {
            if (identity.correlation_id == correlation_id and identity.subject_id == subject_id) return true;
        }
        return false;
    }

    fn rememberDelivery(self: *Ledger, correlation_id: u64, subject_id: u64) void {
        if (correlation_id == 0 and subject_id == 0) return;
        if (self.delivered_request_count >= request_identity_capacity) {
            self.summary_state.edge_violations +|= 1;
            return;
        }
        self.delivered_requests[self.delivered_request_count] = .{ .correlation_id = correlation_id, .subject_id = subject_id, .used = true };
        self.delivered_request_count += 1;
    }
};

const causal_chain = [_]ContractEdge{
    .callback_registration,
    .callback_request,
    .callback_delivery,
    .callback_effect,
    .wait_object_signal,
    .ring_initialization,
    .ring_initialization_ack,
    .guest_wptr_publication,
    .cp_wptr_update,
    .pm4_execution,
    .draw_state,
    .render_target_state,
    .render_target_update,
    .output_custody,
    .vdswap_entry,
    .xe_swap_encoding,
    .guest_swap_publication,
    .xe_swap_execution,
    .output_refresh,
    .presenter_submission,
    .cocoa_custody,
};

const edge_count: usize = @typeInfo(ContractEdge).@"enum".fields.len;

fn edgeIndex(edge: ContractEdge) usize {
    inline for (@typeInfo(ContractEdge).@"enum".fields, 0..) |field, index| {
        if (field.value == @intFromEnum(edge)) return index;
    }
    return 0;
}

fn provenanceMayAdvance(provenance: Provenance, edge: ContractEdge) bool {
    return switch (edge) {
        .callback_registration,
        .callback_effect,
        .vdswap_entry,
        .xe_swap_encoding,
        .guest_swap_publication,
        .guest_wptr_publication,
        => provenance == .guest,
        .callback_request,
        .callback_delivery,
        .ring_initialization,
        .ring_initialization_ack,
        .cp_wptr_update,
        .pm4_execution,
        .draw_state,
        .render_target_state,
        .render_target_update,
        .xe_swap_execution,
        => provenance == .xenia or provenance == .guest,
        .wait_object_signal => provenance == .guest or provenance == .xenia,
        .output_custody,
        .output_refresh,
        .presenter_submission,
        .cocoa_custody,
        .vulkan_custody,
        .d3d_custody,
        => provenance == .xenia or provenance == .rosette_control,
        .none => true,
    };
}

test "a callback chain receives unique identities and one parent per edge" {
    var ledger = Ledger{};
    ledger.open(0xAA55);
    const registration = ledger.callbackRegistration(0x8219_51F8, 0x4000_1F00, 1, 10, 7).?;
    const request = ledger.callbackRequest(registration, 9, 1, 11, 8).?;
    const delivery = ledger.callbackDelivery(request, 9, 1, 12, 0x7FFF_1000, 23).?;
    const effect = ledger.callbackEffect(delivery, 9, 1, 13, 0x7FFF_1000, .guest_object_signal, 0x1234, 0x5678).?;

    try std.testing.expect(registration != request);
    try std.testing.expect(request != delivery);
    try std.testing.expect(delivery != effect);
    try std.testing.expectEqual(delivery, ledger.lastFor(.callback_delivery).?.event_id);
    try std.testing.expectEqual(effect, ledger.lastFor(.callback_effect).?.event_id);
    try std.testing.expectEqual(ContractEdge.callback_registration, ledger.retained()[0].edgeOf());
    try std.testing.expectEqual(request, ledger.retained()[2].parent_event_id);
}

test "the ledger rejects duplicate callback delivery and does not advance it" {
    var ledger = Ledger{};
    ledger.open(1);
    const registration = ledger.callbackRegistration(1, 2, 1, 1, 3).?;
    const request = ledger.callbackRequest(registration, 42, 1, 2, 4).?;
    try std.testing.expect(ledger.callbackDelivery(request, 42, 1, 3, 3, 4) != null);
    try std.testing.expect(ledger.callbackDelivery(request, 42, 1, 3, 3, 4) == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().duplicate_deliveries);
    try std.testing.expectEqual(@as(u64, 3), ledger.lastFor(.callback_delivery).?.event_id);
}

test "a missing parent fails closed instead of making a later edge authentic" {
    var ledger = Ledger{};
    ledger.open(1);
    try std.testing.expect(ledger.callbackEffect(999, 1, 1, 1, 2, .guest_memory_write, 0, 0) == null);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_by_edge[edgeIndex(.callback_effect)]);
    try std.testing.expect(ledger.summary().unknown_parents != 0);
}

test "diagnostic producers cannot advance guest-owned edges" {
    var ledger = Ledger{};
    ledger.open(1);
    const result = ledger.advance(.state_effect, .rosette_gpu, .callback_effect, .diagnostic, .diagnostic, 0, 1, 1, 1, 1, 1, 1, 0, Effect.guest_memory_write.bit(), 0);
    try std.testing.expect(result == null);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_by_edge[edgeIndex(.callback_effect)]);
    try std.testing.expect(ledger.summary().authenticity_violations != 0);
}

test "the ledger remains bounded and reports loss" {
    var ledger = Ledger{};
    ledger.open(1);
    var index: usize = 0;
    while (index < capacity) : (index += 1) {
        _ = ledger.advance(.register_write, .rosette_gpu, .none, .xenia, .host_forwarded, 0, index + 1, index + 1, 0, 0, index, 0, 0, 0, 0);
    }
    const outcome = ledger.append(.{ .kind = @intFromEnum(EventKind.register_write), .domain = @intFromEnum(Domain.rosette_gpu) });
    try std.testing.expectEqual(AppendOutcome.full, outcome);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().dropped);
    try std.testing.expect(!ledger.authenticReady());
}
