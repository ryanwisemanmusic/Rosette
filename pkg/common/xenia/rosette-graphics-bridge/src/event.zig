//! One causal event, in the shape both processes write it.
//!
//! The human-readable log line is a projection of this record, not the other
//! way round. That inversion is the point: a run's final report currently
//! reconstructs causality by matching text across streams that each dropped
//! records independently, and a missing line is indistinguishable from a
//! missing event.
//!
//! The record carries its own continuity evidence — a per-domain sequence, a
//! global sequence, and a CRC — so a reader can say *which intervals are
//! complete* rather than asserting that something did not happen. An absence in
//! a stream with a known gap is an uncertainty interval, and this file is what
//! makes that statable.

const std = @import("std");
const contract = @import("contract.zig");

pub const Domain = contract.Domain;
pub const EventKind = contract.EventKind;
pub const SourceClass = contract.SourceClass;
pub const ResultClass = contract.ResultClass;
pub const Provenance = contract.Provenance;
pub const ContractEdge = contract.ContractEdge;
pub const Effect = contract.Effect;
pub const Address = contract.Address;
pub const CodeLocation = contract.CodeLocation;
pub const RunIdentity = contract.RunIdentity;

/// A causal event. `extern` and fixed-width throughout so the same bytes mean
/// the same thing when a different process, or a later build, reads them.
pub const Record = extern struct {
    schema: u16 = contract.schema_version,
    /// `EventKind`.
    kind: u16 = @intFromEnum(EventKind.run_started),
    /// `Domain`.
    domain: u8 = @intFromEnum(Domain.unknown),
    /// `SourceClass`.
    source_class: u8 = @intFromEnum(SourceClass.unknown),
    /// `ResultClass`.
    result_class: u8 = @intFromEnum(ResultClass.unknown),
    /// Reason code, meaningful within `kind`. Zero is "no reason stated",
    /// which is different from a reason of zero.
    reason: u8 = 0,
    provenance: u8 = @intFromEnum(Provenance.unknown),
    reserved0: u8 = 0,
    contract_edge: u16 = @intFromEnum(ContractEdge.none),

    run_id: u64 = 0,
    /// Monotonic within `domain`, with no gaps. A gap here is a dropped
    /// record and is reported as one.
    domain_sequence: u64 = 0,
    /// Assigned by the bridge when it merges domains. Zero until merged.
    global_sequence: u64 = 0,
    /// Assigned by the run-scoped causal ledger. Unlike a per-domain sequence
    /// this is the identity used by `parent_event_id` and is never reused in a
    /// run.
    event_id: u64 = 0,

    guest_step: u64 = 0,
    host_monotonic_ns: u64 = 0,

    guest_thread: u64 = 0,
    host_thread: u64 = 0,

    location: CodeLocation = .{},
    address: Address = .{},

    /// Ring, object, buffer or frame identity, interpreted by `kind`.
    subject_id: u64 = 0,
    /// Generation or epoch of the subject. A subject id without a generation
    /// cannot distinguish a reused object from the original.
    generation: u64 = 0,

    expected_value: u64 = 0,
    actual_value: u64 = 0,

    payload_length: u32 = 0,
    payload_crc: u32 = 0,

    /// The parent is the event that made this transition legal. It is not a
    /// timestamp approximation: a non-zero parent must identify a retained
    /// event in the same run, or the ledger must classify the record as
    /// causally incomplete.
    parent_event_id: u64 = 0,
    /// Stable identity shared by all observations of one request/transaction.
    correlation_id: u64 = 0,
    module_epoch: u64 = 0,
    callback_generation: u64 = 0,
    ring_generation: u64 = 0,
    state_hash: u64 = 0,
    effect_mask: u64 = 0,
    effect_hash: u64 = 0,

    pub fn kindOf(self: Record) EventKind {
        return contract.decode(EventKind, self.kind, .journal_gap);
    }

    pub fn domainOf(self: Record) Domain {
        return contract.decode(Domain, self.domain, .unknown);
    }

    pub fn sourceOf(self: Record) SourceClass {
        return contract.decode(SourceClass, self.source_class, .unknown);
    }

    pub fn resultOf(self: Record) ResultClass {
        return contract.decode(ResultClass, self.result_class, .unknown);
    }

    pub fn provenanceOf(self: Record) Provenance {
        return contract.decode(Provenance, self.provenance, .unknown);
    }

    pub fn edgeOf(self: Record) ContractEdge {
        return contract.decode(ContractEdge, self.contract_edge, .none);
    }

    pub fn hasEffect(self: Record, effect: Effect) bool {
        return effect != .unknown and (self.effect_mask & effect.bit()) != 0;
    }

    pub fn causallyIdentified(self: Record) bool {
        return self.event_id != 0 and self.run_id != 0;
    }

    pub fn valuesAgree(self: Record) bool {
        return self.expected_value == self.actual_value;
    }

    /// Whether this record may be cited as the guest doing something. A
    /// record from a domain that does not execute guest code, or one whose
    /// source class is not guest-authentic, is evidence about the emulator.
    pub fn isGuestAction(self: Record) bool {
        return self.sourceOf() == .guest_authentic and self.domainOf().executesGuestCode();
    }

    /// A cheap integrity check over the fields that identify the record.
    /// Deliberately not over the whole struct: reserved and merge-assigned
    /// fields change after the producer wrote it, and a checksum that a
    /// legitimate merge invalidates is a checksum nobody keeps.
    pub fn identityChecksum(self: Record) u32 {
        var hash: u32 = 0x811C_9DC5;
        const parts = [_]u64{
            @as(u64, self.schema),
            @as(u64, self.kind),
            @as(u64, self.domain),
            self.run_id,
            self.domain_sequence,
            self.guest_step,
            self.subject_id,
            self.generation,
            self.parent_event_id,
            self.correlation_id,
            self.module_epoch,
            self.callback_generation,
            self.ring_generation,
            self.contract_edge,
        };
        for (parts) |part| {
            var index: u6 = 0;
            while (index < 8) : (index += 1) {
                const byte: u8 = @truncate(part >> (index * 8));
                hash ^= byte;
                hash = hash *% 0x0100_0193;
            }
        }
        return hash;
    }

    /// Full wire integrity over every semantic byte in the fixed record.
    ///
    /// `identityChecksum` intentionally remains narrow because a bridge may
    /// assign `global_sequence` and result metadata after a producer creates a
    /// record.  It is therefore not strong enough for a durable journal: a
    /// corrupted payload length, effect hash, or mutable result could pass it.
    /// The durable codec calls this method only after the bridge has finished
    /// assigning all fields, so the checksum is stable for the lifetime of the
    /// stored frame.  The reserved byte is included as well; changing it is a
    /// wire mutation, not harmless padding.
    pub fn integrityChecksum(self: Record) u32 {
        var hash: u32 = 0x811C_9DC5;
        const parts = [_]u64{
            @as(u64, self.schema),
            @as(u64, self.kind),
            @as(u64, self.domain),
            @as(u64, self.source_class),
            @as(u64, self.result_class),
            @as(u64, self.reason),
            @as(u64, self.provenance),
            @as(u64, self.reserved0),
            @as(u64, self.contract_edge),
            self.run_id,
            self.domain_sequence,
            self.global_sequence,
            self.event_id,
            self.guest_step,
            self.host_monotonic_ns,
            self.guest_thread,
            self.host_thread,
            self.location.guest_pc,
            self.location.guest_lr,
            self.location.host_rip,
            self.location.module_id,
            self.location.provenance,
            self.location.quality,
            self.location.reserved,
            self.address.guest_virtual,
            self.address.guest_physical,
            self.address.host,
            self.subject_id,
            self.generation,
            self.expected_value,
            self.actual_value,
            self.payload_length,
            self.payload_crc,
            self.parent_event_id,
            self.correlation_id,
            self.module_epoch,
            self.callback_generation,
            self.ring_generation,
            self.state_hash,
            self.effect_mask,
            self.effect_hash,
        };
        for (parts) |part| {
            var index: u6 = 0;
            while (index < 8) : (index += 1) {
                const byte: u8 = @truncate(part >> (index * 8));
                hash ^= byte;
                hash = hash *% 0x0100_0193;
            }
        }
        return hash;
    }
};

/// Continuity over one domain's records. This is the object that answers "is
/// the absence of a fault record evidence that no fault happened".
pub const DomainStream = struct {
    domain: Domain,
    records: u64 = 0,
    first_sequence: u64 = 0,
    last_sequence: u64 = 0,
    /// Records the producer told us it could not write.
    declared_drops: u64 = 0,
    /// Sequence numbers missing between records we did receive.
    observed_gaps: u64 = 0,
    first_gap_sequence: u64 = 0,
    /// Critical-kind records observed and declared dropped, tracked apart
    /// because the reserved channel's integrity is the whole claim.
    critical_records: u64 = 0,
    critical_drops: u64 = 0,
    started: bool = false,

    pub fn observe(self: *DomainStream, record: Record) void {
        if (!self.started) {
            self.started = true;
            self.first_sequence = record.domain_sequence;
        } else if (record.domain_sequence > self.last_sequence + 1) {
            const missing = record.domain_sequence - self.last_sequence - 1;
            self.observed_gaps +|= missing;
            if (self.first_gap_sequence == 0) self.first_gap_sequence = self.last_sequence + 1;
        }
        if (record.domain_sequence > self.last_sequence) {
            self.last_sequence = record.domain_sequence;
        }
        self.records +|= 1;
        if (record.kindOf().isCritical()) self.critical_records +|= 1;
    }

    pub fn declareDrop(self: *DomainStream, kind: EventKind, count: u64) void {
        self.declared_drops +|= count;
        if (kind.isCritical()) self.critical_drops +|= count;
    }

    /// A stream with no gap and no declared drop supports a negative claim.
    /// One with either does not, however many records it contains.
    pub fn supportsNegativeClaim(self: DomainStream) bool {
        return self.started and self.observed_gaps == 0 and self.declared_drops == 0;
    }

    /// The reserved channel is intact even if ordinary records were shed.
    pub fn criticalChannelIntact(self: DomainStream) bool {
        return self.critical_drops == 0;
    }
};

/// What a reader is entitled to conclude from a set of streams.
pub const Completeness = enum(u8) {
    /// Nothing has been recorded.
    empty,
    /// Every stream is gapless. An absence here is an absence of the event.
    complete,
    /// Ordinary records were shed but the reserved channel is whole. Absences
    /// of critical kinds are still facts; absences of other kinds are not.
    critical_only,
    /// A critical record was lost. No absence in this run is a fact.
    incomplete,

    pub fn label(self: Completeness) []const u8 {
        return switch (self) {
            .empty => "empty",
            .complete => "complete",
            .critical_only => "critical-only",
            .incomplete => "INCOMPLETE",
        };
    }

    pub fn describe(self: Completeness) []const u8 {
        return switch (self) {
            .empty => "no records were journalled, so nothing here supports a conclusion in either direction",
            .complete => "all received records were retained without sequence gaps. Producer coverage and upstream log loss are separate; local retention alone cannot prove an event never happened",
            .critical_only => "ordinary records were shed and received critical records were retained. Negative claims additionally require complete upstream observation over the interval",
            .incomplete => "a record of a critical kind was lost. No absence in this run may be quoted as a negative fact, and every causal claim that rests on one has to name the interval it cannot see",
        };
    }

    /// Whether an absence of this kind may be quoted as a fact.
    pub fn absenceIsFact(self: Completeness, kind: EventKind) bool {
        return switch (self) {
            .complete => true,
            .critical_only => kind.isCritical(),
            .empty, .incomplete => false,
        };
    }
};

/// An interval a reader cannot see into. Reported instead of a negative fact.
pub const UncertaintyInterval = struct {
    domain: Domain,
    first_missing_sequence: u64,
    missing_records: u64,

    pub fn any(self: UncertaintyInterval) bool {
        return self.missing_records != 0;
    }
};

test "a stream with a gap cannot support a negative claim" {
    var stream = DomainStream{ .domain = .xenia_kernel };
    stream.observe(.{ .domain_sequence = 1 });
    stream.observe(.{ .domain_sequence = 2 });
    try std.testing.expect(stream.supportsNegativeClaim());

    stream.observe(.{ .domain_sequence = 5 });
    try std.testing.expectEqual(@as(u64, 2), stream.observed_gaps);
    try std.testing.expectEqual(@as(u64, 3), stream.first_gap_sequence);
    try std.testing.expect(!stream.supportsNegativeClaim());
}

// The 2026-08-31 shape. `GPU PRODUCER PAUSED` was printed and no
// `GUEST FAULT FRONTIER` transaction was retained, so "the guest did not
// fault" was never available as a fact — but nothing in the report said so.
test "a shed critical record removes every negative fact in the run" {
    var stream = DomainStream{ .domain = .xenia_kernel };
    stream.observe(.{ .domain_sequence = 1, .kind = @intFromEnum(EventKind.pause) });
    try std.testing.expect(stream.criticalChannelIntact());
    try std.testing.expectEqual(@as(u64, 1), stream.critical_records);

    stream.declareDrop(.fault, 1);
    try std.testing.expect(!stream.criticalChannelIntact());
    try std.testing.expect(!stream.supportsNegativeClaim());

    try std.testing.expect(!Completeness.incomplete.absenceIsFact(.fault));
    try std.testing.expect(!Completeness.incomplete.absenceIsFact(.pm4_packet));
}

test "shedding ordinary records leaves critical absences quotable" {
    try std.testing.expect(Completeness.critical_only.absenceIsFact(.fault));
    try std.testing.expect(Completeness.critical_only.absenceIsFact(.swap_request));
    try std.testing.expect(!Completeness.critical_only.absenceIsFact(.pm4_packet));
    try std.testing.expect(Completeness.complete.absenceIsFact(.pm4_packet));
    try std.testing.expect(!Completeness.empty.absenceIsFact(.fault));
}

test "a record from a non-guest domain is never a guest action" {
    const xenia_side = Record{
        .domain = @intFromEnum(Domain.xenia_command_processor),
        .source_class = @intFromEnum(SourceClass.guest_authentic),
    };
    try std.testing.expect(!xenia_side.isGuestAction());

    const diagnostic_guest = Record{
        .domain = @intFromEnum(Domain.guest_title),
        .source_class = @intFromEnum(SourceClass.diagnostic),
    };
    try std.testing.expect(!diagnostic_guest.isGuestAction());

    const real = Record{
        .domain = @intFromEnum(Domain.guest_title),
        .source_class = @intFromEnum(SourceClass.guest_authentic),
    };
    try std.testing.expect(real.isGuestAction());
}

test "the identity checksum survives a merge assigning a global sequence" {
    var record = Record{
        .kind = @intFromEnum(EventKind.ring_stage),
        .domain = @intFromEnum(Domain.rosette_gpu),
        .run_id = 0x73b0_1ab4_0583_f0e8,
        .domain_sequence = 42,
        .guest_step = 3_259_565_717,
        .subject_id = 0x1FC9_B000,
        .generation = 2,
    };
    const before = record.identityChecksum();
    record.global_sequence = 9001;
    record.result_class = @intFromEnum(ResultClass.applied);
    try std.testing.expectEqual(before, record.identityChecksum());

    record.domain_sequence = 43;
    try std.testing.expect(record.identityChecksum() != before);
}

test "an unrecognised enum decodes to a named unknown rather than crashing" {
    const record = Record{ .kind = 0xFFFF, .domain = 200, .source_class = 200, .result_class = 200 };
    try std.testing.expectEqual(EventKind.journal_gap, record.kindOf());
    try std.testing.expectEqual(Domain.unknown, record.domainOf());
    try std.testing.expectEqual(SourceClass.unknown, record.sourceOf());
    try std.testing.expectEqual(ResultClass.unknown, record.resultOf());
}

test "the record layout is fixed width on every route" {
    // A pointer-sized field whose meaning changes between the two processes is
    // the one thing this ABI may not contain.
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(@FieldType(Record, "run_id")));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(@FieldType(Address, "guest_virtual")));
    try std.testing.expect(@sizeOf(Record) % 8 == 0);
}

test "full integrity covers mutable result and payload fields" {
    var record = Record{ .run_id = 1, .event_id = 2, .payload_length = 4, .payload_crc = 3 };
    const before = record.integrityChecksum();
    record.result_class = @intFromEnum(ResultClass.applied);
    try std.testing.expect(record.integrityChecksum() != before);
    record.result_class = 0;
    record.payload_crc = 4;
    try std.testing.expect(record.integrityChecksum() != before);
}
