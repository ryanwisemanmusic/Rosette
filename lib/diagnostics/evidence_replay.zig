//! Deterministic, offline replay of the structured evidence stream.
//!
//! The replay path never invokes Xenia, opens a window, or talks to a GPU. It
//! checks only the durable facts: run/schema continuity, producer sequence,
//! parent identity, contract-edge prerequisites, and provenance. An unknown
//! schema is retained as opaque evidence but can never satisfy a gate.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const Record = bridge.event.Record;
pub const Domain = bridge.contract.Domain;
pub const EventKind = bridge.contract.EventKind;
pub const ContractEdge = bridge.contract.ContractEdge;
pub const Provenance = bridge.contract.Provenance;
pub const schema_version = bridge.contract.schema_version;

/// The final custody predicate is selected by the backend that owns the
/// transaction.  A Vulkan frame must not inherit a Cocoa requirement merely
/// because both adapters can write to the same diagnostic window.
pub const Route = enum(u8) {
    cocoa_metal,
    vulkan,
    windows_d3d,
    unknown,

    pub fn custodyEdge(self: Route) ContractEdge {
        return switch (self) {
            .cocoa_metal => .cocoa_custody,
            .vulkan => .vulkan_custody,
            .windows_d3d => .d3d_custody,
            .unknown => .none,
        };
    }
};

pub const FrameReadiness = struct {
    route: Route = .unknown,
    ready: bool = false,
    first_missing: ContractEdge = .none,

    pub fn label(self: FrameReadiness) []const u8 {
        if (self.ready) return "ready";
        return self.first_missing.label();
    }
};

pub const capacity: usize = 2048;
pub const domain_slots: usize = 16;
pub const edge_slots: usize = 64;

pub const Outcome = enum(u8) {
    accepted,
    opaque_schema,
    wrong_run,
    duplicate_event,
    domain_out_of_order,
    domain_gap,
    missing_parent,
    missing_edge,
    wrong_provenance,
    invalid_identity,
    capacity,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .accepted => "accepted",
            .opaque_schema => "opaque-schema",
            .wrong_run => "wrong-run",
            .duplicate_event => "duplicate-event",
            .domain_out_of_order => "domain-out-of-order",
            .domain_gap => "domain-gap",
            .missing_parent => "missing-parent",
            .missing_edge => "missing-edge",
            .wrong_provenance => "wrong-provenance",
            .invalid_identity => "invalid-identity",
            .capacity => "capacity",
        };
    }

    pub fn acceptedForAuthentic(self: Outcome) bool {
        return self == .accepted;
    }
};

pub const Summary = struct {
    run_id: u64 = 0,
    records: u64 = 0,
    accepted: u64 = 0,
    opaque_schema: u64 = 0,
    rejected: u64 = 0,
    gaps: u64 = 0,
    declared_drops: u64 = 0,
    missing_parents: u64 = 0,
    missing_edges: u64 = 0,
    wrong_provenance: u64 = 0,
    duplicates: u64 = 0,
    invalid_identity: u64 = 0,
};

pub const Replay = struct {
    run_id: u64 = 0,
    records: [capacity]Record = [_]Record{.{}} ** capacity,
    count: usize = 0,
    last_domain_sequence: [domain_slots]u64 = [_]u64{0} ** domain_slots,
    last_edge_event: [edge_slots]u64 = [_]u64{0} ** edge_slots,
    summary_state: Summary = .{},
    seen_ids: [capacity]u64 = [_]u64{0} ** capacity,
    seen_count: usize = 0,
    sealed: bool = false,

    pub fn init(run_id: u64) Replay {
        return .{ .run_id = run_id, .summary_state = .{ .run_id = run_id } };
    }

    pub fn append(self: *Replay, record: Record) Outcome {
        if (self.sealed or self.count >= capacity) {
            self.summary_state.rejected +|= 1;
            return .capacity;
        }
        if (record.run_id != self.run_id or self.run_id == 0) {
            self.summary_state.rejected +|= 1;
            self.summary_state.invalid_identity +|= 1;
            return .wrong_run;
        }
        if (record.event_id == 0 or record.domain_sequence == 0) {
            self.summary_state.rejected +|= 1;
            self.summary_state.invalid_identity +|= 1;
            return .invalid_identity;
        }
        if (record.schema != schema_version) {
            // Keep the bytes for an offline human/recovery tool, but do not
            // update authoritative edge or sequence state from an unknown
            // layout. It is an opaque record, not a successful replay fact.
            self.records[self.count] = record;
            self.count += 1;
            self.summary_state.records +|= 1;
            self.summary_state.opaque_schema +|= 1;
            return .opaque_schema;
        }

        if (self.containsEvent(record.event_id)) {
            self.summary_state.rejected +|= 1;
            self.summary_state.duplicates +|= 1;
            return .duplicate_event;
        }

        const domain_slot = domainSlot(record.domainOf()) orelse {
            self.summary_state.rejected +|= 1;
            self.summary_state.invalid_identity +|= 1;
            return .invalid_identity;
        };
        const previous_sequence = self.last_domain_sequence[domain_slot];
        if (previous_sequence != 0 and record.domain_sequence <= previous_sequence) {
            self.summary_state.rejected +|= 1;
            self.summary_state.invalid_identity +|= 1;
            return .domain_out_of_order;
        }
        if (previous_sequence != 0 and record.domain_sequence > previous_sequence + 1) {
            self.summary_state.gaps +|= record.domain_sequence - previous_sequence - 1;
            self.summary_state.rejected +|= 1;
            return .domain_gap;
        }
        if (record.parent_event_id != 0 and !self.containsEvent(record.parent_event_id)) {
            self.summary_state.missing_parents +|= 1;
            self.summary_state.rejected +|= 1;
            return .missing_parent;
        }

        const edge = record.edgeOf();
        if (edge != .none) {
            const edge_slot = edgeSlot(edge) orelse {
                self.summary_state.invalid_identity +|= 1;
                self.summary_state.rejected +|= 1;
                return .invalid_identity;
            };
            const prerequisite = edge.prerequisite();
            if (prerequisite != .none) {
                const prerequisite_slot = edgeSlot(prerequisite) orelse {
                    self.summary_state.missing_edges +|= 1;
                    self.summary_state.rejected +|= 1;
                    return .missing_edge;
                };
                if (self.last_edge_event[prerequisite_slot] == 0) {
                    self.summary_state.missing_edges +|= 1;
                    self.summary_state.rejected +|= 1;
                    return .missing_edge;
                }
            }
            if (edgeRequiresGuestProvenance(edge) and !record.provenanceOf().mayAdvanceGuestState()) {
                self.summary_state.wrong_provenance +|= 1;
                self.summary_state.rejected +|= 1;
                return .wrong_provenance;
            }
            self.last_edge_event[edge_slot] = record.event_id;
        }

        self.records[self.count] = record;
        self.count += 1;
        self.seen_ids[self.seen_count] = record.event_id;
        self.seen_count += 1;
        self.last_domain_sequence[domain_slot] = record.domain_sequence;
        self.summary_state.records +|= 1;
        self.summary_state.accepted +|= 1;
        return .accepted;
    }

    pub fn declareDrop(self: *Replay, count: u64) void {
        self.summary_state.declared_drops +|= count;
    }

    pub fn seal(self: *Replay) void {
        self.sealed = true;
    }

    pub fn hasEdge(self: *const Replay, edge: ContractEdge) bool {
        const slot = edgeSlot(edge) orelse return false;
        return self.last_edge_event[slot] != 0;
    }

    /// Compatibility entry point for the historical Cocoa-only replay gate.
    /// New callers must select the route explicitly.
    pub fn frameReady(self: *const Replay) bool {
        return self.frameReadyFor(.cocoa_metal).ready;
    }

    pub fn frameReadyFor(self: *const Replay, route: Route) FrameReadiness {
        var result = FrameReadiness{ .route = route };
        if (route == .unknown) return result;
        if (!self.sealed or self.summary_state.opaque_schema != 0 or
            self.summary_state.rejected != 0 or self.summary_state.gaps != 0 or
            self.summary_state.declared_drops != 0)
        {
            result.first_missing = if (!self.sealed) .none else .output_custody;
            return result;
        }

        // These are the semantic guest-frame suffixes. Host API activity can
        // only be admitted after the guest has published its own swap.
        const common = [_]ContractEdge{
            .output_custody,
            .vdswap_entry,
            .xe_swap_encoding,
            .guest_swap_publication,
            .xe_swap_execution,
            .output_refresh,
            .presenter_submission,
        };
        for (common) |edge| {
            if (!self.hasEdge(edge)) {
                result.first_missing = edge;
                return result;
            }
        }
        const custody = route.custodyEdge();
        if (custody == .none or !self.hasEdge(custody)) {
            result.first_missing = custody;
            return result;
        }
        result.ready = true;
        return result;
    }

    pub fn summary(self: *const Replay) Summary {
        return self.summary_state;
    }

    pub fn containsEvent(self: *const Replay, id: u64) bool {
        for (self.seen_ids[0..self.seen_count]) |seen| if (seen == id) return true;
        // Opaque records are deliberately not entered in `seen_ids`; a later
        // known-schema record cannot use an opaque parent as authority.
        return false;
    }
};

fn domainSlot(domain: Domain) ?usize {
    return switch (domain) {
        .rosette_scheduler => 0,
        .rosette_memory => 1,
        .rosette_gpu => 2,
        .rosette_run_integrity => 3,
        .xenia_kernel => 4,
        .xenia_command_processor => 5,
        .xenia_vulkan => 6,
        .xenia_presenter => 7,
        .guest_title => 8,
        .unknown => null,
    };
}

fn edgeSlot(edge: ContractEdge) ?usize {
    const value = @intFromEnum(edge);
    return if (value < edge_slots) @intCast(value) else null;
}

fn edgeRequiresGuestProvenance(edge: ContractEdge) bool {
    return switch (edge) {
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
        .vulkan_custody,
        .d3d_custody,
        => true,
        .none => false,
    };
}

fn makeRecord(run_id: u64, event_id: u64, sequence: u64, edge: ContractEdge, parent: u64, provenance: Provenance) Record {
    return .{
        .run_id = run_id,
        .event_id = event_id,
        .domain_sequence = sequence,
        .domain = @intFromEnum(Domain.xenia_kernel),
        .source_class = @intFromEnum(bridge.contract.SourceClass.guest_authentic),
        .provenance = @intFromEnum(provenance),
        .contract_edge = @intFromEnum(edge),
        .parent_event_id = parent,
    };
}

test "replay accepts a causal edge chain and rejects an unclosed frame" {
    var replay = Replay.init(7);
    try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(7, 1, 1, .callback_registration, 0, .guest)));
    try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(7, 2, 2, .callback_request, 1, .guest)));
    try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(7, 3, 3, .callback_delivery, 2, .xenia)));
    try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(7, 4, 4, .callback_effect, 3, .xenia)));
    replay.seal();
    try std.testing.expect(!replay.frameReady());
    try std.testing.expectEqual(@as(u64, 4), replay.summary().accepted);
}

test "replay refuses gaps and missing parents instead of repairing order" {
    var replay = Replay.init(8);
    try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(8, 1, 1, .callback_registration, 0, .guest)));
    try std.testing.expectEqual(Outcome.domain_gap, replay.append(makeRecord(8, 2, 3, .callback_request, 1, .guest)));
    try std.testing.expectEqual(Outcome.missing_parent, replay.append(makeRecord(8, 3, 2, .callback_request, 99, .guest)));
    try std.testing.expectEqual(@as(u64, 1), replay.summary().gaps);
    try std.testing.expectEqual(@as(u64, 1), replay.summary().missing_parents);
}

test "opaque schema records are retained but never satisfy a replay gate" {
    var replay = Replay.init(9);
    var unknown = makeRecord(9, 1, 1, .callback_registration, 0, .guest);
    unknown.schema = schema_version + 1;
    try std.testing.expectEqual(Outcome.opaque_schema, replay.append(unknown));
    replay.seal();
    try std.testing.expectEqual(@as(usize, 1), replay.count);
    try std.testing.expect(!replay.frameReady());
}

test "diagnostic provenance cannot advance a guest-owned edge" {
    var replay = Replay.init(10);
    try std.testing.expectEqual(Outcome.wrong_provenance, replay.append(makeRecord(10, 1, 1, .callback_registration, 0, .diagnostic)));
    try std.testing.expectEqual(@as(u64, 1), replay.summary().wrong_provenance);
}

test "wrong runs and duplicate identities are rejected" {
    var replay = Replay.init(11);
    try std.testing.expectEqual(Outcome.wrong_run, replay.append(makeRecord(12, 1, 1, .none, 0, .diagnostic)));
    try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(11, 1, 1, .none, 0, .diagnostic)));
    try std.testing.expectEqual(Outcome.duplicate_event, replay.append(makeRecord(11, 1, 2, .none, 0, .diagnostic)));
}

test "replay requires the complete output and Cocoa custody suffix" {
    var replay = Replay.init(12);
    const edges = [_]ContractEdge{ .ring_initialization, .ring_initialization_ack, .guest_wptr_publication, .cp_wptr_update, .pm4_execution, .draw_state, .render_target_state, .render_target_update, .output_custody, .vdswap_entry, .xe_swap_encoding, .guest_swap_publication, .xe_swap_execution, .output_refresh, .presenter_submission, .cocoa_custody };
    var parent: u64 = 0;
    for (edges, 0..) |edge, index| {
        const id: u64 = @intCast(index + 1);
        try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(12, id, id, edge, parent, .xenia)));
        parent = id;
    }
    replay.seal();
    try std.testing.expect(replay.frameReady());
}

test "route-aware replay admits Vulkan without Cocoa custody" {
    var replay = Replay.init(13);
    const edges = [_]ContractEdge{
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
        .vulkan_custody,
    };
    var parent: u64 = 0;
    for (edges, 0..) |edge, index| {
        const id: u64 = @intCast(index + 1);
        try std.testing.expectEqual(Outcome.accepted, replay.append(makeRecord(13, id, id, edge, parent, .xenia)));
        parent = id;
    }
    replay.seal();
    try std.testing.expect(replay.frameReadyFor(.vulkan).ready);
    try std.testing.expect(!replay.frameReadyFor(.cocoa_metal).ready);
    try std.testing.expectEqual(ContractEdge.cocoa_custody, replay.frameReadyFor(.cocoa_metal).first_missing);
}
