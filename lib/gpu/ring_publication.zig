//! Whether the guest ever published a command span, as opposed to touching the
//! register that would publish one.
//!
//! The supplied Halo 3 run reports `wptr_updates(total=2,guest=2)` alongside
//! `read_ptr=00000019 write_ptr=00000019` and `swap_packets=0`. Read casually
//! that is "the guest advanced the write pointer twice", and it sends the reader
//! downstream to the command processor and then to the presenter. Read exactly
//! it is something else: the register was *written* twice, the pointers are
//! equal, and no packet span was ever outstanding. Those are different failures
//! in different subsystems, and one MMIO counter cannot tell them apart because
//! it counts writes, not changes.
//!
//! So this separates the three facts a write-pointer observation actually
//! carries — that a write happened, that the value changed, and how much of the
//! ring the pointers currently span — and refuses to let the first stand in for
//! the others. A guest that rewrites the same value has published nothing, and
//! saying so is what stops the investigation from moving past the producer.
//!
//! Deliberately generic. It takes values and ring geometry, not addresses,
//! titles, or log formats, so a producer that stalls this way in any title is
//! described the same way. And it never infers a value it was not given: an
//! unknown span is `unknown`, not `empty`, because "nobody looked" and "nothing
//! was there" are the two answers this whole file exists to keep apart.

const std = @import("std");

/// What one write-pointer observation meant.
pub const Outcome = enum {
    /// The first value seen. On its own it proves a write, not a change: the
    /// previous value is not knowable from a single observation.
    first_observation,
    /// The value differs from the last one seen. This is a real advance.
    advanced,
    /// The same value written again. The ring is in exactly the state it was
    /// in before, so nothing was published.
    repeated,
};

/// How much of the ring is outstanding between the consumer and the producer.
pub const Span = enum {
    /// No geometry has been observed. Not the same as empty.
    unknown,
    /// Read and write pointers agree: nothing is outstanding right now.
    empty,
    /// A non-zero span exists or existed: the producer published work.
    non_empty,
};

pub const Geometry = struct {
    base: u32 = 0,
    size_bytes: u32 = 0,
    read_pointer: u32 = 0,
    write_pointer: u32 = 0,

    /// Ring pointers are dword indices while the published size is in bytes,
    /// which is the kind of unit mismatch that silently turns a span of 25
    /// dwords into a span of 25 bytes.
    pub fn sizeDwords(self: Geometry) u32 {
        return self.size_bytes / 4;
    }

    /// Outstanding dwords, wrapped. A write pointer behind the read pointer has
    /// wrapped the ring, not gone backwards.
    pub fn spanDwords(self: Geometry) ?u32 {
        const size = self.sizeDwords();
        if (size == 0) return null;
        if (self.read_pointer >= size or self.write_pointer >= size) return null;
        if (self.write_pointer >= self.read_pointer) return self.write_pointer - self.read_pointer;
        return size - (self.read_pointer - self.write_pointer);
    }
};

pub const max_advance_records: usize = 64;

/// Provenance captured at the actual guest-side publication boundary. The
/// command processor's worker thread is deliberately not an acceptable
/// substitute: it can consume a ring without being the thread that filled or
/// published it.
pub const ProducerContext = struct {
    valid: bool = false,
    guest_thread: u64 = 0,
    guest_pc: u64 = 0,
    guest_lr: u64 = 0,
    publication_epoch: u64 = 0,
    ring_base: u64 = 0,
    ring_size_bytes: u64 = 0,
    span_dwords: u32 = 0,
};

/// One value-changing publication.  Retaining the value and its predecessor
/// lets the transport audit join the source write to the cumulative read
/// pointer write-back instead of manufacturing placeholder indices.
pub const AdvanceRecord = struct {
    previous_value: u32 = 0,
    value: u32 = 0,
    step: u64 = 0,
    applied: bool = false,
    worker_woken: bool = false,
    consumed: bool = false,
    guest_writeback: bool = false,
    applied_step: u64 = 0,
    worker_woken_step: u64 = 0,
    consumed_step: u64 = 0,
    guest_writeback_step: u64 = 0,
    read_before: u32 = 0,
    read_after: u32 = 0,
    consumed_dwords: u32 = 0,
    /// The source of the publication, if the producer logger carried a
    /// guest-side context. `first_thread` in the old bring-up ledger was the
    /// first observer (usually the CP worker), not this thread.
    producer: ProducerContext = .{},
};

pub const Tracker = struct {
    /// Times the register was written, whatever the value.
    writes: u64 = 0,
    /// Times the written value actually differed from the previous one.
    advances: u64 = 0,
    /// Times the same value was written again, publishing nothing.
    repeats: u64 = 0,
    /// A ring snapshot taken before the first write is a valid predecessor.
    /// Keeping it separate from `first_value` preserves the distinction
    /// between an observed register write and a sampled current value.
    baseline_value: ?u32 = null,
    first_value: ?u32 = null,
    last_value: ?u32 = null,
    advance_records: [max_advance_records]AdvanceRecord = [_]AdvanceRecord{.{}} ** max_advance_records,
    advance_record_count: usize = 0,
    advance_records_dropped: u64 = 0,
    geometry: ?Geometry = null,
    /// The largest outstanding span ever observed. Retained because a span the
    /// command processor has since drained still proves the producer published.
    largest_span_dwords: u32 = 0,
    /// High-water evidence from a command processor that actually consumed a
    /// batch. This is deliberately separate from `largest_span_dwords`: a
    /// fast consumer can drain a batch before a heartbeat samples a non-empty
    /// pointer span, so an empty *current* span must not erase proof that work
    /// was consumed. The values are high-water marks because the same retained
    /// ring image may be inspected on several later checkpoints.
    consumed_batch_dwords: u32 = 0,
    consumed_batch_packets: u64 = 0,
    consumed_batch_draws: u64 = 0,
    consumed_batch_swaps: u64 = 0,
    consumed_batch_observations: u64 = 0,
    first_consumed_step: u64 = 0,
    last_consumed_step: u64 = 0,
    /// Times geometry was reported with the pointers equal.
    drained_observations: u64 = 0,
    /// Executed-step stamps for the first and most recent pointer change.
    ///
    /// `published()` is a latch: once the producer submits anything it stays
    /// true for the rest of the run, which is correct for "did this ever
    /// happen" and useless for "is it still happening". A title that publishes
    /// one batch during initialization and then stops looks identical to one
    /// that is submitting every frame, and those are opposite bugs. The stamps
    /// are what let a reader tell a live producer from a latched one.
    first_advance_step: u64 = 0,
    last_advance_step: u64 = 0,
    /// Step of the most recent write of any kind, changed value or not.
    last_write_step: u64 = 0,

    pub fn observeWritePointer(self: *Tracker, value: u32) Outcome {
        return self.observeWritePointerAt(value, 0);
    }

    /// Observe a write pointer value with the executed-step stamp attached.
    /// `executed_steps` of zero means the caller has no clock, which keeps the
    /// stamps at zero and makes `stalledSteps` return null rather than invent
    /// an age.
    pub fn observeWritePointerAt(self: *Tracker, value: u32, executed_steps: u64) Outcome {
        return self.observeWritePointerAtWithContext(value, executed_steps, .{});
    }

    /// Observe a pointer write and retain producer provenance when the caller
    /// has it. A context is optional because older Xenia logs did not expose
    /// it; absence remains `valid=false` and is reported as attribution loss.
    pub fn observeWritePointerAtWithContext(
        self: *Tracker,
        value: u32,
        executed_steps: u64,
        context: ProducerContext,
    ) Outcome {
        const before = self.advance_record_count;
        const outcome = self.observeWritePointerCore(value, executed_steps);
        if (outcome == .advanced and self.advance_record_count > before) {
            self.advance_records[self.advance_record_count - 1].producer = context;
        }
        return outcome;
    }

    fn observeWritePointerCore(self: *Tracker, value: u32, executed_steps: u64) Outcome {
        self.writes +|= 1;
        if (executed_steps != 0) self.last_write_step = executed_steps;
        defer self.last_value = value;
        const previous = self.last_value orelse self.baseline_value;
        if (self.first_value == null) {
            self.first_value = value;
            const baseline = previous orelse return .first_observation;
            if (baseline == value) {
                self.repeats +|= 1;
                return .repeated;
            }
            self.noteAdvance(baseline, value, executed_steps);
            return .advanced;
        }
        if (previous.? == value) {
            self.repeats +|= 1;
            return .repeated;
        }
        self.noteAdvance(previous.?, value, executed_steps);
        return .advanced;
    }

    fn noteAdvance(self: *Tracker, previous: u32, value: u32, executed_steps: u64) void {
        self.advances +|= 1;
        if (self.advance_record_count < max_advance_records) {
            self.advance_records[self.advance_record_count] = .{
                .previous_value = previous,
                .value = value,
                .step = executed_steps,
            };
            self.advance_record_count += 1;
        } else {
            self.advance_records_dropped +|= 1;
        }
        if (executed_steps != 0) {
            if (self.first_advance_step == 0) self.first_advance_step = executed_steps;
            self.last_advance_step = executed_steps;
        }
    }

    pub fn retainedAdvances(self: *const Tracker) []const AdvanceRecord {
        return self.advance_records[0..self.advance_record_count];
    }

    fn findAdvance(self: *Tracker, previous: u32, value: u32) ?*AdvanceRecord {
        var index = self.advance_record_count;
        while (index > 0) {
            index -= 1;
            const record = &self.advance_records[index];
            if (record.previous_value == previous and record.value == value) return record;
        }
        return null;
    }

    /// Join Xenia's authoritative `WPTR advanced` statement to the source
    /// write without treating the earlier diagnostic register print as proof
    /// that the command processor applied it.
    pub fn observeApplied(
        self: *Tracker,
        previous: u32,
        value: u32,
        worker_woken: bool,
        step: u64,
    ) bool {
        return self.observeAppliedWithContext(previous, value, worker_woken, step, .{});
    }

    /// Join the command processor's applied line and its producer context to
    /// one exact advance. The old overload remains for pre-context logs.
    pub fn observeAppliedWithContext(
        self: *Tracker,
        previous: u32,
        value: u32,
        worker_woken: bool,
        step: u64,
        context: ProducerContext,
    ) bool {
        const record = self.findAdvance(previous, value) orelse return false;
        if (!record.applied) record.applied_step = step;
        record.applied = true;
        if (worker_woken) {
            if (!record.worker_woken) record.worker_woken_step = step;
            record.worker_woken = true;
        }
        if (context.valid) record.producer = context;
        return true;
    }

    /// Join the command processor's exact read interval to the publication it
    /// drained. Duplicate summary lines are idempotent.
    pub fn observeConsumption(
        self: *Tracker,
        read_before: u32,
        read_after: u32,
        write_value: u32,
        dwords: u32,
        step: u64,
    ) bool {
        const record = self.findAdvance(read_before, write_value) orelse return false;
        if (!record.consumed) {
            record.consumed_step = step;
            record.read_before = read_before;
            record.read_after = read_after;
            record.consumed_dwords = dwords;
        }
        record.consumed = true;
        return true;
    }

    /// A sampled write-back word acknowledges the transition whose published
    /// index it equals. Earlier transitions remain historical rather than
    /// being rewritten as if each intermediate value had been sampled.
    pub fn observeGuestWriteback(self: *Tracker, value: u32, step: u64) bool {
        var index = self.advance_record_count;
        while (index > 0) {
            index -= 1;
            const record = &self.advance_records[index];
            if (record.value != value or !record.consumed) continue;
            if (!record.guest_writeback) record.guest_writeback_step = step;
            record.guest_writeback = true;
            return true;
        }
        return false;
    }

    /// Best known predecessor for the next write, whether supplied by a prior
    /// write or by a pre-write geometry snapshot.
    pub fn referenceValue(self: *const Tracker) ?u32 {
        return self.last_value orelse self.baseline_value;
    }

    /// How long the producer has been quiet, in executed steps, or null when
    /// it has never published or the caller kept no clock. Deliberately not a
    /// boolean: what counts as "stalled" belongs to the reader, and a number
    /// can be compared against the run's own scale.
    pub fn stalledSteps(self: *const Tracker, executed_steps: u64) ?u64 {
        if (self.last_advance_step == 0) return null;
        if (executed_steps <= self.last_advance_step) return 0;
        return executed_steps - self.last_advance_step;
    }

    pub fn observeGeometry(self: *Tracker, geometry: Geometry) void {
        self.geometry = geometry;
        if (geometry.spanDwords()) |outstanding| {
            // Only an empty snapshot is a safe pre-write baseline. A non-empty
            // snapshot already proves publication, but it does not reveal the
            // value that preceded it.
            if (self.writes == 0 and self.baseline_value == null and outstanding == 0) {
                self.baseline_value = geometry.write_pointer;
            }
            if (outstanding > self.largest_span_dwords) self.largest_span_dwords = outstanding;
            if (outstanding == 0) self.drained_observations +|= 1;
        }
    }

    /// Retain direct consumer evidence even when pointer sampling only ever
    /// sees the drained state. This does not manufacture a publication or
    /// alter pointer provenance; it answers the independent question "did a
    /// command processor consume a batch?".
    pub fn observeConsumedBatch(
        self: *Tracker,
        dwords: u32,
        packets: u64,
        draws: u64,
        swaps: u64,
        executed_steps: u64,
    ) void {
        if (dwords == 0 and packets == 0 and draws == 0 and swaps == 0) return;
        self.consumed_batch_observations +|= 1;
        if (dwords > self.consumed_batch_dwords) self.consumed_batch_dwords = dwords;
        if (packets > self.consumed_batch_packets) self.consumed_batch_packets = packets;
        if (draws > self.consumed_batch_draws) self.consumed_batch_draws = draws;
        if (swaps > self.consumed_batch_swaps) self.consumed_batch_swaps = swaps;
        if (executed_steps != 0) {
            if (self.first_consumed_step == 0) self.first_consumed_step = executed_steps;
            self.last_consumed_step = executed_steps;
        }
    }

    pub fn consumerSawBatch(self: *const Tracker) bool {
        return self.consumed_batch_observations != 0;
    }

    pub fn span(self: *const Tracker) Span {
        if (self.largest_span_dwords != 0) return .non_empty;
        const geometry = self.geometry orelse return .unknown;
        if (geometry.spanDwords() == null) return .unknown;
        return .empty;
    }

    /// Whether the guest ever published a command span. Requires either an
    /// observed pointer change or an observed non-empty span — never merely a
    /// write, and never merely a configured ring.
    pub fn published(self: *const Tracker) bool {
        return self.advances != 0 or self.largest_span_dwords != 0;
    }

    /// The one sentence that names the next thing to look at.
    pub fn verdict(self: *const Tracker) []const u8 {
        if (self.published()) {
            return "the guest published a command span; the write pointer moved and work was outstanding, so the next question is downstream of publication";
        }
        if (self.writes == 0) {
            return "the guest never wrote the ring write pointer; the producer has not reached its submission path at all";
        }
        if (self.advances == 0 and self.repeats != 0) {
            return "the guest wrote the ring write pointer more than once WITHOUT EVER CHANGING ITS VALUE. The ring is configured and nothing was ever published. This is a producer that ran and had no payload to submit, not a command processor that failed to consume one — look at the guest thread that fills the ring, not at the CP or the presenter";
        }
        if (self.span() == .empty) {
            return "the write pointer was written once and the ring's read and write pointers are equal, so no span was ever outstanding. Treat the ring as configured but never filled";
        }
        return "the write pointer was written once and the ring geometry is unknown, so publication can be neither confirmed nor ruled out; capture rb_base/rb_size/read_ptr/write_ptr before concluding anything";
    }
};

test "a repeated write pointer publishes nothing" {
    var tracker = Tracker{};
    try std.testing.expectEqual(Outcome.first_observation, tracker.observeWritePointer(0x19));
    try std.testing.expectEqual(Outcome.repeated, tracker.observeWritePointer(0x19));
    try std.testing.expectEqual(@as(u64, 2), tracker.writes);
    try std.testing.expectEqual(@as(u64, 0), tracker.advances);
    try std.testing.expectEqual(@as(u64, 1), tracker.repeats);
    try std.testing.expect(!tracker.published());
}

// The exact reading the supplied run invites and the exact reading it deserves.
test "two write-pointer writes with equal ring pointers are not two advances" {
    var tracker = Tracker{};
    _ = tracker.observeWritePointer(0x19);
    _ = tracker.observeWritePointer(0x19);
    tracker.observeGeometry(.{
        .base = 0x1FC9B000,
        .size_bytes = 0x8000,
        .read_pointer = 0x19,
        .write_pointer = 0x19,
    });
    try std.testing.expectEqual(Span.empty, tracker.span());
    try std.testing.expect(!tracker.published());
    try std.testing.expect(std.mem.indexOf(u8, tracker.verdict(), "WITHOUT EVER CHANGING ITS VALUE") != null);
    // And it points at the producer rather than the consumer or the presenter.
    try std.testing.expect(std.mem.indexOf(u8, tracker.verdict(), "not at the CP or the presenter") != null);
}

test "a changed write pointer is a publication" {
    var tracker = Tracker{};
    _ = tracker.observeWritePointer(0);
    try std.testing.expectEqual(Outcome.advanced, tracker.observeWritePointer(0x19));
    try std.testing.expect(tracker.published());
    try std.testing.expect(std.mem.indexOf(u8, tracker.verdict(), "downstream of publication") != null);
}

test "an empty geometry snapshot makes the first changed write an advance" {
    var tracker = Tracker{};
    tracker.observeGeometry(.{
        .base = 0x1FC9_B000,
        .size_bytes = 0x8000,
        .read_pointer = 0,
        .write_pointer = 0,
    });
    try std.testing.expectEqual(@as(?u32, 0), tracker.referenceValue());
    try std.testing.expectEqual(Outcome.advanced, tracker.observeWritePointerAt(0x16, 100));
    try std.testing.expectEqual(@as(u64, 1), tracker.advances);
    try std.testing.expectEqual(@as(u64, 100), tracker.first_advance_step);
    try std.testing.expectEqual(@as(usize, 1), tracker.retainedAdvances().len);
    try std.testing.expectEqual(@as(u32, 0), tracker.retainedAdvances()[0].previous_value);
    try std.testing.expectEqual(@as(u32, 0x16), tracker.retainedAdvances()[0].value);
    try std.testing.expect(tracker.published());
}

test "an unbaselined first observation is not stamped as a publication" {
    var tracker = Tracker{};
    try std.testing.expectEqual(Outcome.first_observation, tracker.observeWritePointerAt(0x19, 100));
    try std.testing.expectEqual(@as(u64, 0), tracker.advances);
    try std.testing.expectEqual(@as(u64, 0), tracker.first_advance_step);
    try std.testing.expectEqual(@as(u64, 0), tracker.last_advance_step);
    try std.testing.expect(!tracker.published());
}

test "applied consumed and writeback evidence join the exact publication" {
    var tracker = Tracker{};
    tracker.observeGeometry(.{
        .base = 0x1FC9_B000,
        .size_bytes = 0x8000,
        .read_pointer = 0,
        .write_pointer = 0,
    });
    try std.testing.expectEqual(Outcome.advanced, tracker.observeWritePointerAt(0x16, 100));
    try std.testing.expect(tracker.observeApplied(0, 0x16, true, 110));
    try std.testing.expect(tracker.observeConsumption(0, 0x16, 0x16, 22, 120));
    // The emulator emits both a detailed activity line and a milestone line.
    // Replaying the latter must not double the consumed count.
    try std.testing.expect(tracker.observeConsumption(0, 0x16, 0x16, 22, 121));
    try std.testing.expect(tracker.observeGuestWriteback(0x16, 130));

    const record = tracker.retainedAdvances()[0];
    try std.testing.expect(record.applied);
    try std.testing.expect(record.worker_woken);
    try std.testing.expect(record.consumed);
    try std.testing.expect(record.guest_writeback);
    try std.testing.expectEqual(@as(u32, 0x16), record.read_after);
    try std.testing.expectEqual(@as(u32, 22), record.consumed_dwords);
    try std.testing.expectEqual(@as(u64, 120), record.consumed_step);
}

// A span the command processor has already drained still proves the producer
// did its job, so the largest span ever seen is what matters, not the latest.
test "a drained ring still counts as having been published to" {
    var tracker = Tracker{};
    _ = tracker.observeWritePointer(0x19);
    tracker.observeGeometry(.{ .size_bytes = 0x8000, .read_pointer = 0, .write_pointer = 0x19 });
    tracker.observeGeometry(.{ .size_bytes = 0x8000, .read_pointer = 0x19, .write_pointer = 0x19 });
    try std.testing.expectEqual(Span.non_empty, tracker.span());
    try std.testing.expect(tracker.published());
    try std.testing.expectEqual(@as(u32, 0x19), tracker.largest_span_dwords);
    try std.testing.expectEqual(@as(u64, 1), tracker.drained_observations);
}

test "a fast consumer is retained separately from the sampled outstanding span" {
    var tracker = Tracker{};
    tracker.observeGeometry(.{ .size_bytes = 0x8000, .read_pointer = 0x19, .write_pointer = 0x19 });
    tracker.observeConsumedBatch(25, 3, 24, 0, 4_000);

    try std.testing.expectEqual(@as(u32, 0), tracker.largest_span_dwords);
    try std.testing.expectEqual(@as(u32, 25), tracker.consumed_batch_dwords);
    try std.testing.expectEqual(@as(u64, 3), tracker.consumed_batch_packets);
    try std.testing.expectEqual(@as(u64, 24), tracker.consumed_batch_draws);
    try std.testing.expect(tracker.consumerSawBatch());
    try std.testing.expectEqual(@as(u64, 4_000), tracker.first_consumed_step);
    try std.testing.expectEqual(@as(u64, 4_000), tracker.last_consumed_step);
}

test "a wrapped write pointer is a span, not a negative one" {
    const wrapped = Geometry{ .size_bytes = 0x8000, .read_pointer = 8000, .write_pointer = 16 };
    // 8192 dwords in the ring; 192 outstanding from 8000 through the wrap to 16.
    try std.testing.expectEqual(@as(u32, 8192 - 8000 + 16), wrapped.spanDwords().?);
}

// Byte size against dword pointers is the unit mismatch that makes a full ring
// look like an empty one.
test "ring size is bytes while pointers are dwords" {
    const geometry = Geometry{ .size_bytes = 0x8000, .read_pointer = 0, .write_pointer = 0x19 };
    try std.testing.expectEqual(@as(u32, 8192), geometry.sizeDwords());
    try std.testing.expectEqual(@as(u32, 0x19), geometry.spanDwords().?);
}

test "pointers outside the ring are unknown rather than a fabricated span" {
    const nonsense = Geometry{ .size_bytes = 0x100, .read_pointer = 0x9999, .write_pointer = 0 };
    try std.testing.expect(nonsense.spanDwords() == null);

    const unsized = Geometry{ .size_bytes = 0, .read_pointer = 4, .write_pointer = 8 };
    try std.testing.expect(unsized.spanDwords() == null);

    var tracker = Tracker{};
    _ = tracker.observeWritePointer(0x19);
    tracker.observeGeometry(unsized);
    try std.testing.expectEqual(Span.unknown, tracker.span());
    try std.testing.expect(std.mem.indexOf(u8, tracker.verdict(), "neither confirmed nor ruled out") != null);
}

test "a producer that never wrote is distinguished from one that wrote nothing new" {
    var silent = Tracker{};
    try std.testing.expect(std.mem.indexOf(u8, silent.verdict(), "never wrote the ring write pointer") != null);

    var repeated = Tracker{};
    _ = repeated.observeWritePointer(7);
    _ = repeated.observeWritePointer(7);
    try std.testing.expect(std.mem.indexOf(u8, repeated.verdict(), "never wrote the ring write pointer") == null);
}
