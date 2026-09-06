//! Identity-preserving credit for GPU work.
//!
//! Runtime reports are observations of work, not new work. A retained PM4
//! batch reported by 100 heartbeats therefore earns one credit, not 100. Every
//! credit includes the run, producer domain, stream identity, generation,
//! sequence, and kind; disagreeing payloads under one identity are conflicts.

const std = @import("std");
const contract = @import("cocoa_graphics_control_contract");

pub const Domain = contract.Domain;

pub const Kind = enum(u8) {
    ring_publication,
    pm4_batch,
    pm4_packet,
    draw_submission,
    completion_signal,
    callback_dispatch,
    guest_swap_request,
    guest_frame,
    native_submission,
    native_present_request,
    native_gpu_completion,
    diagnostic_present,
    native_present,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .ring_publication => "ring-publication",
            .pm4_batch => "pm4-batch",
            .pm4_packet => "pm4-packet",
            .draw_submission => "draw-submission",
            .completion_signal => "completion-signal",
            .callback_dispatch => "callback-dispatch",
            .guest_swap_request => "guest-swap-request",
            .guest_frame => "guest-frame",
            .native_submission => "native-submission",
            .native_present_request => "native-present-request",
            .native_gpu_completion => "native-gpu-completion",
            .diagnostic_present => "diagnostic-present",
            .native_present => "native-present",
        };
    }
};

pub const kind_count: usize = @typeInfo(Kind).@"enum".fields.len;

pub const Key = struct {
    run: u64 = 0,
    producer: Domain = .unknown,
    stream: u64 = 0,
    generation: u64 = 0,
    sequence: u64 = 0,
    kind: Kind = .pm4_batch,

    pub fn valid(self: Key) bool {
        return self.run != 0 and self.producer != .unknown and self.stream != 0 and
            self.generation != 0 and self.sequence != 0;
    }

    pub fn eql(self: Key, other: Key) bool {
        return self.run == other.run and self.producer == other.producer and
            self.stream == other.stream and self.generation == other.generation and
            self.sequence == other.sequence and self.kind == other.kind;
    }
};

pub const Claim = struct {
    key: Key,
    units: u64 = 1,
    payload_digest: u64,
    parent_digest: u64 = 0,
    step: u64 = 0,

    pub fn valid(self: Claim) bool {
        return self.key.valid() and self.units != 0 and self.payload_digest != 0;
    }
};

pub const Result = enum(u8) {
    credited,
    duplicate_observation,
    identity_conflict,
    malformed,
};

pub const Record = struct {
    claim: Claim = .{ .key = .{}, .payload_digest = 0 },
    observations: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    conflict: bool = false,
};

pub const Summary = struct {
    observations: u64 = 0,
    unique_claims: u64 = 0,
    duplicates: u64 = 0,
    conflicts: u64 = 0,
    malformed: u64 = 0,
    credited_units: u64 = 0,
    units_by_kind: [kind_count]u64 = [_]u64{0} ** kind_count,

    pub fn units(self: Summary, kind: Kind) u64 {
        return self.units_by_kind[@intFromEnum(kind)];
    }
};

pub const max_records: usize = 256;

pub const Ledger = struct {
    records: [max_records]Record = [_]Record{.{}} ** max_records,
    count: usize = 0,
    next: usize = 0,
    observations: u64 = 0,
    unique_claims: u64 = 0,
    duplicates: u64 = 0,
    conflicts: u64 = 0,
    malformed: u64 = 0,
    credited_units: u64 = 0,
    units_by_kind: [kind_count]u64 = [_]u64{0} ** kind_count,

    pub fn claim(self: *Ledger, candidate: Claim) Result {
        self.observations +|= 1;
        if (!candidate.valid()) {
            self.malformed +|= 1;
            return .malformed;
        }
        if (self.find(candidate.key)) |existing| {
            existing.observations +|= 1;
            if (candidate.step > existing.last_step) existing.last_step = candidate.step;
            if (existing.claim.units != candidate.units or
                existing.claim.payload_digest != candidate.payload_digest or
                existing.claim.parent_digest != candidate.parent_digest)
            {
                if (!existing.conflict) self.conflicts +|= 1;
                existing.conflict = true;
                return .identity_conflict;
            }
            self.duplicates +|= 1;
            return .duplicate_observation;
        }

        self.unique_claims +|= 1;
        self.credited_units +|= candidate.units;
        self.units_by_kind[@intFromEnum(candidate.key.kind)] +|= candidate.units;
        self.store(.{
            .claim = candidate,
            .observations = 1,
            .first_step = candidate.step,
            .last_step = candidate.step,
        });
        return .credited;
    }

    pub fn credited(self: *const Ledger, key: Key) bool {
        for (self.records[0..self.count]) |record| {
            if (record.claim.key.eql(key) and !record.conflict) return true;
        }
        return false;
    }

    pub fn units(self: *const Ledger, kind: Kind) u64 {
        return self.units_by_kind[@intFromEnum(kind)];
    }

    pub fn summary(self: *const Ledger) Summary {
        return .{
            .observations = self.observations,
            .unique_claims = self.unique_claims,
            .duplicates = self.duplicates,
            .conflicts = self.conflicts,
            .malformed = self.malformed,
            .credited_units = self.credited_units,
            .units_by_kind = self.units_by_kind,
        };
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 14_695_981_039_346_656_037;
        hash = mix(hash, self.unique_claims);
        hash = mix(hash, self.conflicts);
        inline for (0..kind_count) |index| hash = mix(hash, self.units_by_kind[index]);
        return hash;
    }

    fn find(self: *Ledger, key: Key) ?*Record {
        for (self.records[0..self.count]) |*record| if (record.claim.key.eql(key)) return record;
        return null;
    }

    fn store(self: *Ledger, record: Record) void {
        self.records[self.next] = record;
        self.next = (self.next + 1) % max_records;
        if (self.count < max_records) self.count += 1;
    }
};

fn mix(hash: u64, value: u64) u64 {
    return (hash ^ value) *% 1_099_511_628_211;
}

fn drawClaim(sequence: u64) Claim {
    return .{
        .key = .{
            .run = 1,
            .producer = .xenia_host,
            .stream = 0x1FC0_0000,
            .generation = 7,
            .sequence = sequence,
            .kind = .draw_submission,
        },
        .units = 24,
        .payload_digest = 0x1234,
        .step = 100,
    };
}

test "repeated heartbeats do not inflate one draw batch" {
    var ledger = Ledger{};
    const claim_value = drawClaim(1);
    try std.testing.expectEqual(Result.credited, ledger.claim(claim_value));
    var repeat = claim_value;
    repeat.step = 200;
    var index: usize = 0;
    while (index < 147) : (index += 1)
        try std.testing.expectEqual(Result.duplicate_observation, ledger.claim(repeat));

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 148), totals.observations);
    try std.testing.expectEqual(@as(u64, 1), totals.unique_claims);
    try std.testing.expectEqual(@as(u64, 24), totals.units(.draw_submission));
}

test "same identity with different work is quarantined" {
    var ledger = Ledger{};
    const first = drawClaim(1);
    _ = ledger.claim(first);
    var contradiction = first;
    contradiction.units = 25;
    try std.testing.expectEqual(Result.identity_conflict, ledger.claim(contradiction));
    try std.testing.expectEqual(@as(u64, 1), ledger.conflicts);
    try std.testing.expect(!ledger.credited(first.key));
}

test "generation and sequence distinguish real new work" {
    var ledger = Ledger{};
    const first = drawClaim(1);
    var second = drawClaim(2);
    second.payload_digest = 0x5678;
    try std.testing.expectEqual(Result.credited, ledger.claim(first));
    try std.testing.expectEqual(Result.credited, ledger.claim(second));
    try std.testing.expectEqual(@as(u64, 48), ledger.units(.draw_submission));
}

test "a run and producer domain are mandatory identity" {
    var ledger = Ledger{};
    var malformed = drawClaim(1);
    malformed.key.run = 0;
    try std.testing.expectEqual(Result.malformed, ledger.claim(malformed));
    try std.testing.expectEqual(@as(u64, 0), ledger.credited_units);
}
