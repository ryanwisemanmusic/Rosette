//! A reserved channel for the events a causal claim rests on, and an honest
//! account of what it could not hold.
//!
//! The defect this exists for
//! --------------------------
//! Rosette's startup log is an asynchronous ring with finite slots and
//! non-blocking producers. Xenia's causal trace in the 2026-08-31 run reported
//! 1 293 dropped events against 1 389 retained. At that loss rate the absence
//! of a fault frontier, a callback payload or a signaller is not evidence
//! about the run — it is evidence about the ring.
//!
//! That matters most exactly where the reasoning is hardest. `GPU PRODUCER
//! PAUSED` was printed with no `GUEST FAULT FRONTIER` anywhere in the log, and
//! there was no way to tell "the emulator paused without recording why" from
//! "the record was shed". Those need different fixes.
//!
//! The design
//! ----------
//! Capacity is split. High-volume kinds share a general pool and are shed
//! freely; the kinds whose *absence* is load-bearing get a reserved pool that
//! the general traffic cannot touch. A run then reports one of four
//! completeness states, and a report is only entitled to say "this did not
//! happen" for kinds whose channel is intact.
//!
//! What it never does
//! ------------------
//! It does not block the guest to make room. A journal that stalled execution
//! to record an event would change the scheduling it exists to observe. It
//! sheds, and it says exactly what it shed.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");
const Coverage = @import("pipeline_evidence.zig").Coverage;

pub const Record = bridge.event.Record;
pub const DomainStream = bridge.event.DomainStream;
pub const Completeness = bridge.event.Completeness;
pub const UncertaintyInterval = bridge.event.UncertaintyInterval;
pub const Domain = bridge.contract.Domain;
pub const EventKind = bridge.contract.EventKind;
pub const SourceClass = bridge.contract.SourceClass;
pub const ResultClass = bridge.contract.ResultClass;
pub const domain_count = bridge.contract.domain_count;

/// Slots for events whose absence is load-bearing. Sized so a run can hold
/// every fault, pause, resume, ring transition, target bind, resolve, swap,
/// frame custody record, wait result and signal it is likely to produce
/// during bring-up.
pub const reserved_capacity: usize = 2048;

/// Slots shared by everything else. Shed freely; their absence proves nothing
/// and is never quoted as if it did.
pub const general_capacity: usize = 2048;

/// Maximum number of distinct high-frequency critical event shapes retained
/// as aggregates.  This is not an event limit: one entry can account for an
/// arbitrary number of semantically identical wait results or signals.
///
/// The causal trace in the 2026-09-01 run produced 3 131 post-draw wait and
/// signal events but only a handful of object/thread/result tuples.  Storing
/// every repetition in the reserved lane exhausted it and made the absence of
/// an unrelated fault unknowable.  Aggregating the stable tuple retains the
/// exact count and first/last step without allowing heartbeat traffic to evict
/// a different critical fact.
pub const compaction_capacity: usize = 512;

pub const Slot = struct {
    record: Record = .{},
    used: bool = false,
};

pub const CompactedEntry = struct {
    /// The unstamped producer record used as the semantic key.  Guest step,
    /// host time, run/sequence fields are deliberately excluded by
    /// `sameSemanticEvent`; they describe occurrences, not the event shape.
    key: Record = .{},
    materialized_global_sequence: u64 = 0,
    occurrences: u64 = 0,
    first_guest_step: u64 = 0,
    last_guest_step: u64 = 0,
    used: bool = false,
};

/// Per-domain sequence assignment. The journal owns these so a producer
/// cannot skip one by accident and make its own stream look gapped.
const Sequencer = struct {
    next: [domain_count]u64 = [_]u64{1} ** domain_count,

    fn take(self: *Sequencer, domain: Domain) u64 {
        const index = domainIndex(domain);
        const value = self.next[index];
        self.next[index] = value + 1;
        return value;
    }
};

fn domainIndex(domain: Domain) usize {
    inline for (@typeInfo(Domain).@"enum".fields, 0..) |field, position| {
        if (field.value == @intFromEnum(domain)) return position;
    }
    return domain_count - 1;
}

fn domainAt(index: usize) Domain {
    inline for (@typeInfo(Domain).@"enum".fields, 0..) |field, position| {
        if (position == index) return @enumFromInt(field.value);
    }
    return .unknown;
}

pub const Summary = struct {
    /// Producer events offered to the journal, including repetitions retained
    /// by an aggregate.
    observed: u64 = 0,
    /// Materialized records.  This remains the sequence space used by the
    /// journal and therefore excludes compacted repetitions.
    written: u64 = 0,
    compacted: u64 = 0,
    compaction_groups: usize = 0,
    reserved_used: usize = 0,
    general_used: usize = 0,
    reserved_dropped: u64 = 0,
    general_dropped: u64 = 0,
    observed_gaps: u64 = 0,
    completeness: Completeness = .empty,
    /// The domain with the first gap, so a reader knows where to look.
    first_gap_domain: ?Domain = null,
    first_gap_sequence: u64 = 0,

    pub fn totalDropped(self: Summary) u64 {
        return self.reserved_dropped +| self.general_dropped;
    }
};

pub const WriteAndTakeResult = struct {
    accepted: bool = false,
    stamped: ?Record = null,
};

pub const Journal = struct {
    /// All materialization, sequence assignment, and the durable handoff are
    /// one critical section.  Producers may still prepare records outside the
    /// journal, but no second producer can replace the stamped record between
    /// `write` and the sink handoff.
    mutex: std.Io.Mutex = .init,
    reserved: [reserved_capacity]Slot = [_]Slot{.{}} ** reserved_capacity,
    reserved_count: usize = 0,
    reserved_dropped: u64 = 0,

    general: [general_capacity]Slot = [_]Slot{.{}} ** general_capacity,
    general_count: usize = 0,
    general_write: usize = 0,
    general_dropped: u64 = 0,

    streams: [domain_count]DomainStream = blk: {
        var table: [domain_count]DomainStream = undefined;
        for (&table, 0..) |*entry, index| {
            entry.* = .{ .domain = domainAt(index) };
        }
        break :blk table;
    },
    sequencer: Sequencer = .{},
    compacted_entries: [compaction_capacity]CompactedEntry = [_]CompactedEntry{.{}} ** compaction_capacity,
    compacted_count: usize = 0,
    compacted_events: u64 = 0,
    observed: u64 = 0,
    written: u64 = 0,
    run_id: u64 = 0,
    /// The last materialized record is exposed only long enough for the
    /// durable sink to copy the exact stamped sequence.  Compacted
    /// repetitions intentionally leave this invalid: no new wire record was
    /// created for that occurrence.
    last_accepted_record: Record = .{},
    last_accepted_valid: bool = false,

    pub fn open(self: *Journal, run_id: u64) void {
        self.run_id = run_id;
    }

    /// Write one record.
    ///
    /// A critical kind takes a reserved slot and is never displaced by
    /// ordinary traffic. Everything else rides a ring: the newest records
    /// survive, the oldest are shed, and the shedding is declared so the
    /// domain stream stops supporting negative claims.
    pub fn write(self: *Journal, record: Record) bool {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        return self.writeLocked(record);
    }

    fn writeLocked(self: *Journal, record: Record) bool {
        self.last_accepted_valid = false;
        self.observed +|= 1;
        return self.writeMaterialized(record);
    }

    /// Retain a high-frequency critical event without spending one reserved
    /// slot per identical occurrence.
    ///
    /// Only wait results and signals are eligible.  Faults, pauses, resumes,
    /// ring transitions, swaps and custody changes always remain individual
    /// records because their exact interleaving is load-bearing.  An aggregate
    /// preserves the stable semantic tuple, exact occurrence count, and its
    /// first/last guest-step envelope.  It intentionally does not claim the
    /// raw order of identical repetitions inside that envelope.
    pub fn writeCompacted(self: *Journal, record: Record) bool {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        return self.writeCompactedLocked(record);
    }

    fn writeCompactedLocked(self: *Journal, record: Record) bool {
        self.last_accepted_valid = false;
        self.observed +|= 1;
        const kind = record.kindOf();
        if (kind != .wait_result and kind != .signal) {
            return self.writeMaterialized(record);
        }

        var index: usize = 0;
        while (index < self.compacted_count) : (index += 1) {
            const entry = &self.compacted_entries[index];
            if (!sameSemanticEvent(entry.key, record)) continue;
            entry.occurrences +|= 1;
            if (entry.first_guest_step == 0 or
                (record.guest_step != 0 and record.guest_step < entry.first_guest_step))
            {
                entry.first_guest_step = record.guest_step;
            }
            if (record.guest_step > entry.last_guest_step) entry.last_guest_step = record.guest_step;
            self.compacted_events +|= 1;
            return true;
        }

        // If the distinct-shape table itself is exhausted, fall back to the
        // ordinary reserved path.  That path declares any eventual loss; the
        // journal never silently merges non-identical events.
        if (self.compacted_count >= compaction_capacity) {
            return self.writeMaterialized(record);
        }

        const materialized_before = self.written;
        if (!self.writeMaterialized(record)) return false;
        const entry = &self.compacted_entries[self.compacted_count];
        self.compacted_count += 1;
        entry.* = .{
            .key = record,
            .materialized_global_sequence = materialized_before + 1,
            .occurrences = 1,
            .first_guest_step = record.guest_step,
            .last_guest_step = record.guest_step,
            .used = true,
        };
        return true;
    }

    /// Materialize a record and take the exact stamped value under one lock.
    /// This is the only handoff used by the Mach-O durable writer.  Keeping it
    /// as a value result makes cross-thread replacement impossible and leaves
    /// compacted repetitions correctly represented by `stamped == null`.
    pub fn writeAndTake(self: *Journal, record: Record) WriteAndTakeResult {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        const accepted = self.writeLocked(record);
        const stamped = if (self.last_accepted_valid) self.last_accepted_record else null;
        self.last_accepted_valid = false;
        return .{ .accepted = accepted, .stamped = stamped };
    }

    pub fn writeCompactedAndTake(self: *Journal, record: Record) WriteAndTakeResult {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        const accepted = self.writeCompactedLocked(record);
        const stamped = if (self.last_accepted_valid) self.last_accepted_record else null;
        self.last_accepted_valid = false;
        return .{ .accepted = accepted, .stamped = stamped };
    }

    fn writeMaterialized(self: *Journal, record: Record) bool {
        var stamped = record;
        stamped.run_id = self.run_id;
        stamped.domain_sequence = self.sequencer.take(stamped.domainOf());
        stamped.global_sequence = self.written + 1;
        self.written +|= 1;

        const stream = &self.streams[domainIndex(stamped.domainOf())];
        if (stamped.kindOf().isCritical()) {
            if (self.reserved_count >= reserved_capacity) {
                self.reserved_dropped +|= 1;
                stream.declareDrop(stamped.kindOf(), 1);
                return false;
            }
            self.reserved[self.reserved_count] = .{ .record = stamped, .used = true };
            self.reserved_count += 1;
            self.last_accepted_record = stamped;
            self.last_accepted_valid = true;
            stream.observe(stamped);
            return true;
        }
        if (self.general_count >= general_capacity) {
            // The displaced record's kind is not critical by construction, so
            // the drop is declared against a non-critical kind and the
            // reserved channel stays intact.
            self.general_dropped +|= 1;
            stream.declareDrop(.pm4_packet, 1);
        } else {
            self.general_count += 1;
        }
        self.general[self.general_write] = .{ .record = stamped, .used = true };
        self.general_write = (self.general_write + 1) % general_capacity;
        self.last_accepted_record = stamped;
        self.last_accepted_valid = true;
        stream.observe(stamped);
        return true;
    }

    /// Consume the exact stamped record produced by the immediately preceding
    /// materializing write.  This is intentionally a single-consumer handoff:
    /// the Mach-O owner writes the in-memory journal and the durable journal in
    /// the same call, while compacted repetitions remain represented by the
    /// aggregate rather than by a fabricated wire record.
    pub fn takeLastAccepted(self: *Journal) ?Record {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        if (!self.last_accepted_valid) return null;
        self.last_accepted_valid = false;
        return self.last_accepted_record;
    }

    pub fn compactedRecords(self: *const Journal) []const CompactedEntry {
        return self.compacted_entries[0..self.compacted_count];
    }

    pub fn criticalRecords(self: *const Journal) []const Slot {
        return self.reserved[0..self.reserved_count];
    }

    pub fn streamFor(self: *const Journal, domain: Domain) DomainStream {
        return self.streams[domainIndex(domain)];
    }

    pub fn completeness(self: *const Journal) Completeness {
        if (self.written == 0) return .empty;
        var any_started = false;
        var critical_lost = false;
        var ordinary_lost = false;
        for (self.streams) |stream| {
            if (!stream.started) continue;
            any_started = true;
            if (!stream.criticalChannelIntact()) critical_lost = true;
            if (!stream.supportsNegativeClaim()) ordinary_lost = true;
        }
        if (!any_started) return .empty;
        if (critical_lost) return .incomplete;
        return if (ordinary_lost) .critical_only else .complete;
    }

    /// Whether a report may state that an event of this kind did not happen.
    pub fn absenceIsFact(self: *const Journal, kind: EventKind) bool {
        // The sequencer starts AFTER upstream parsing. Gapless numbers say
        // nothing about omitted/throttled source events or an unarmed producer.
        _ = self;
        _ = kind;
        return false;
    }

    pub fn absenceWithCoverage(self: *const Journal, kind: EventKind, coverage: Coverage, first: u64, last: u64) bool {
        return self.completeness().absenceIsFact(kind) and coverage.negative(first, last) == .covered;
    }

    /// The interval a reader cannot see into, for a domain that lost records.
    pub fn uncertainty(self: *const Journal, domain: Domain) UncertaintyInterval {
        const stream = self.streamFor(domain);
        return .{
            .domain = domain,
            .first_missing_sequence = stream.first_gap_sequence,
            .missing_records = stream.observed_gaps +| stream.declared_drops,
        };
    }

    pub fn summary(self: *const Journal) Summary {
        var out = Summary{
            .observed = self.observed,
            .written = self.written,
            .compacted = self.compacted_events,
            .compaction_groups = self.compacted_count,
            .reserved_used = self.reserved_count,
            .general_used = self.general_count,
            .reserved_dropped = self.reserved_dropped,
            .general_dropped = self.general_dropped,
            .completeness = self.completeness(),
        };
        for (self.streams) |stream| {
            out.observed_gaps +|= stream.observed_gaps;
            if (stream.first_gap_sequence != 0 and out.first_gap_domain == null) {
                out.first_gap_domain = stream.domain;
                out.first_gap_sequence = stream.first_gap_sequence;
            }
        }
        return out;
    }

    /// The audit's G0 criterion: the critical channel has no gap.
    pub fn criticalChannelIntact(self: *const Journal) bool {
        if (self.reserved_dropped != 0) return false;
        return switch (self.completeness()) {
            .complete, .critical_only => true,
            .empty, .incomplete => false,
        };
    }

    pub fn fingerprint(self: *const Journal) u64 {
        var hash: u64 = self.observed;
        hash = hash *% 31 +% self.written;
        hash = hash *% 31 +% self.compacted_events;
        hash = hash *% 31 +% self.compacted_count;
        hash = hash *% 31 +% self.reserved_dropped;
        hash = hash *% 31 +% self.general_dropped;
        hash = hash *% 31 +% @intFromEnum(self.completeness());
        return hash;
    }
};

/// Compare every stable field that changes the meaning of a wait result or
/// signal.  Occurrence identity (time, step, run and bridge-assigned sequence)
/// is retained by the aggregate envelope rather than used to defeat it.
fn sameSemanticEvent(left: Record, right: Record) bool {
    return left.schema == right.schema and
        left.kind == right.kind and
        left.domain == right.domain and
        left.source_class == right.source_class and
        left.result_class == right.result_class and
        left.reason == right.reason and
        left.guest_thread == right.guest_thread and
        left.host_thread == right.host_thread and
        left.location.guest_pc == right.location.guest_pc and
        left.location.guest_lr == right.location.guest_lr and
        left.location.host_rip == right.location.host_rip and
        left.location.module_id == right.location.module_id and
        left.location.provenance == right.location.provenance and
        left.location.quality == right.location.quality and
        left.address.guest_virtual == right.address.guest_virtual and
        left.address.guest_physical == right.address.guest_physical and
        left.address.host == right.address.host and
        left.subject_id == right.subject_id and
        left.generation == right.generation and
        left.expected_value == right.expected_value and
        left.actual_value == right.actual_value and
        left.payload_length == right.payload_length and
        left.payload_crc == right.payload_crc;
}

fn make(kind: EventKind, domain: Domain) Record {
    return .{ .kind = @intFromEnum(kind), .domain = @intFromEnum(domain) };
}

test "an empty journal is not an intact causal channel" {
    const journal = Journal{};
    try std.testing.expectEqual(Completeness.empty, journal.completeness());
    try std.testing.expect(!journal.criticalChannelIntact());
    try std.testing.expect(!journal.absenceIsFact(.fault));
}

test "ordinary traffic sheds without touching the reserved channel" {
    var journal = Journal{};
    journal.open(0x73b0_1ab4_0583_f0e8);
    try std.testing.expect(journal.write(make(.fault, .xenia_kernel)));
    var index: usize = 0;
    while (index < general_capacity + 200) : (index += 1) {
        _ = journal.write(make(.pm4_packet, .xenia_command_processor));
    }
    const totals = journal.summary();
    try std.testing.expectEqual(@as(u64, 200), totals.general_dropped);
    try std.testing.expectEqual(@as(u64, 0), totals.reserved_dropped);
    try std.testing.expectEqual(Completeness.critical_only, totals.completeness);
    try std.testing.expect(journal.criticalChannelIntact());

    // A fault's absence is still a fact; a packet's absence is not.
    try std.testing.expect(!journal.absenceIsFact(.fault));
    try std.testing.expect(!journal.absenceIsFact(.pm4_packet));
}

// The 2026-08-31 ambiguity: a pause warning with no fault record, and no way
// to tell a missing record from a missing event.
test "a shed critical record removes every negative fact in the run" {
    var journal = Journal{};
    journal.open(1);
    var index: usize = 0;
    while (index < reserved_capacity) : (index += 1) {
        var record = make(.wait_result, .xenia_kernel);
        record.subject_id = index + 1;
        _ = journal.write(record);
    }
    try std.testing.expect(journal.criticalChannelIntact());
    try std.testing.expect(!journal.write(make(.fault, .xenia_kernel)));

    try std.testing.expectEqual(@as(u64, 1), journal.summary().reserved_dropped);
    try std.testing.expectEqual(Completeness.incomplete, journal.completeness());
    try std.testing.expect(!journal.criticalChannelIntact());
    try std.testing.expect(!journal.absenceIsFact(.fault));
    try std.testing.expect(!journal.absenceIsFact(.pause));
    try std.testing.expect(std.mem.indexOf(u8, Completeness.incomplete.describe(), "name the interval") != null);
}

test "repeated wait and signal events retain exact counts without exhausting the critical lane" {
    var journal = Journal{};
    journal.open(1);

    var wait = make(.wait_result, .xenia_kernel);
    wait.subject_id = 0x4000_4bf4;
    wait.guest_thread = 0x7fff_2140;
    wait.location.guest_pc = 0x8258_a470;
    wait.actual_value = 0x102;
    var index: u64 = 0;
    while (index < reserved_capacity + 4_000) : (index += 1) {
        wait.guest_step = 100 + index;
        try std.testing.expect(journal.writeCompacted(wait));
    }

    var signal = make(.signal, .xenia_kernel);
    signal.subject_id = 0x827c_ec28;
    signal.guest_thread = 0x7fff_2160;
    signal.guest_step = 9_000;
    try std.testing.expect(journal.writeCompacted(signal));

    const totals = journal.summary();
    try std.testing.expectEqual(@as(u64, reserved_capacity + 4_001), totals.observed);
    try std.testing.expectEqual(@as(u64, 2), totals.written);
    try std.testing.expectEqual(@as(u64, reserved_capacity + 3_999), totals.compacted);
    try std.testing.expectEqual(@as(usize, 2), totals.compaction_groups);
    try std.testing.expectEqual(@as(usize, 2), totals.reserved_used);
    try std.testing.expectEqual(@as(u64, 0), totals.reserved_dropped);
    try std.testing.expect(journal.criticalChannelIntact());

    const groups = journal.compactedRecords();
    try std.testing.expectEqual(@as(u64, reserved_capacity + 4_000), groups[0].occurrences);
    try std.testing.expectEqual(@as(u64, 100), groups[0].first_guest_step);
    try std.testing.expectEqual(@as(u64, 100 + reserved_capacity + 3_999), groups[0].last_guest_step);
    try std.testing.expectEqual(@as(u64, 1), groups[1].occurrences);
}

test "compaction never merges different result values" {
    var journal = Journal{};
    journal.open(1);
    var first = make(.wait_result, .xenia_kernel);
    first.subject_id = 1;
    first.actual_value = 0;
    var second = first;
    second.actual_value = 0x102;
    try std.testing.expect(journal.writeCompacted(first));
    try std.testing.expect(journal.writeCompacted(second));
    try std.testing.expectEqual(@as(usize, 2), journal.summary().compaction_groups);
    try std.testing.expectEqual(@as(u64, 2), journal.summary().written);
}

test "a gapless journal does not certify upstream event coverage" {
    var journal = Journal{};
    journal.open(1);
    _ = journal.write(make(.run_started, .rosette_gpu));
    _ = journal.write(make(.ring_stage, .rosette_gpu));
    _ = journal.write(make(.pm4_packet, .xenia_command_processor));
    try std.testing.expectEqual(Completeness.complete, journal.completeness());
    try std.testing.expect(!journal.absenceIsFact(.fault));
    try std.testing.expect(!journal.absenceIsFact(.pm4_packet));
    try std.testing.expectEqual(@as(u64, 0), journal.summary().totalDropped());
}

test "the journal assigns gapless per-domain sequences" {
    var journal = Journal{};
    journal.open(1);
    _ = journal.write(make(.ring_stage, .rosette_gpu));
    _ = journal.write(make(.fault, .xenia_kernel));
    _ = journal.write(make(.resolve, .rosette_gpu));

    const gpu = journal.streamFor(.rosette_gpu);
    try std.testing.expectEqual(@as(u64, 1), gpu.first_sequence);
    try std.testing.expectEqual(@as(u64, 2), gpu.last_sequence);
    try std.testing.expectEqual(@as(u64, 0), gpu.observed_gaps);
    try std.testing.expect(gpu.supportsNegativeClaim());

    const kernel = journal.streamFor(.xenia_kernel);
    try std.testing.expectEqual(@as(u64, 1), kernel.first_sequence);
    try std.testing.expectEqual(@as(u64, 1), kernel.last_sequence);
}

test "an uncertainty interval is reported instead of a negative fact" {
    var journal = Journal{};
    journal.open(1);
    _ = journal.write(make(.frame_custody, .xenia_presenter));
    var index: usize = 0;
    while (index < general_capacity + 5) : (index += 1) {
        _ = journal.write(make(.register_write, .xenia_presenter));
    }
    const interval = journal.uncertainty(.xenia_presenter);
    try std.testing.expect(interval.any());
    try std.testing.expectEqual(@as(u64, 5), interval.missing_records);
    try std.testing.expectEqual(Domain.xenia_presenter, interval.domain);

    // A domain that lost nothing has no interval at all.
    try std.testing.expect(!journal.uncertainty(.rosette_memory).any());
}

test "records carry the run id and a global order" {
    var journal = Journal{};
    journal.open(0xABCD);
    _ = journal.write(make(.fault, .xenia_kernel));
    _ = journal.write(make(.pause, .xenia_kernel));
    const kept = journal.criticalRecords();
    try std.testing.expectEqual(@as(usize, 2), kept.len);
    try std.testing.expectEqual(@as(u64, 0xABCD), kept[0].record.run_id);
    try std.testing.expectEqual(@as(u64, 1), kept[0].record.global_sequence);
    try std.testing.expectEqual(@as(u64, 2), kept[1].record.global_sequence);
    try std.testing.expect(kept[0].record.identityChecksum() != kept[1].record.identityChecksum());
}

test "an empty journal supports nothing in either direction" {
    const journal = Journal{};
    try std.testing.expectEqual(Completeness.empty, journal.completeness());
    try std.testing.expect(!journal.absenceIsFact(.fault));
    try std.testing.expectEqual(@as(u64, 0), journal.summary().written);
}

test "negative journal evidence requires a complete upstream interval" {
    var journal = Journal{};
    journal.open(1);
    _ = journal.write(make(.run_started, .rosette_gpu));
    const coverage = Coverage{ .armed_step = 0, .through_step = 100, .exhaustive = true };
    try std.testing.expect(journal.absenceWithCoverage(.fault, coverage, 0, 100));
    try std.testing.expect(!journal.absenceWithCoverage(.fault, coverage, 0, 101));
    var lossy = coverage;
    lossy.upstream_lost = 1;
    try std.testing.expect(!journal.absenceWithCoverage(.fault, lossy, 0, 100));
}
