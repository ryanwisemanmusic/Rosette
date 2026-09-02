//! Ring identity, and the ladder a write-pointer update has to climb before
//! anyone may call it applied.
//!
//! The defect this exists for
//! --------------------------
//! One 2026-08-31 report says `SUBMISSION PROVENANCE: PRINTED_BUT_NOT_APPLIED`
//! — the emulator printed a pointer update and the applied-update counter did
//! not see it. Another report, in the same run, says the command processor
//! consumed the batch that update described. Both are correct about the layer
//! they watched, and there is no way to join them, because "the pointer was
//! updated" is not one event. It is eight, and the emulator has four different
//! code paths that can supply the first one: guest `CP_RB_WPTR` MMIO, a PM4
//! `CP_RB_WPTR` packet, a `VDSWAP_WPTR_KICK`, and debug forcing.
//!
//! So a stage is never inferred from the next one. `worker_woken` does not
//! imply `applied`; a printed line does not imply anything at all. A ledger
//! that cannot name the stage it is missing has to say so.

const std = @import("std");
const contract = @import("contract.zig");

pub const SourceClass = contract.SourceClass;
pub const Address = contract.Address;

/// Which code path supplied the write-pointer value. Kept separate from
/// `SourceClass` because two of these are guest-authentic and two are not, and
/// collapsing them loses exactly the distinction the report needs.
pub const PointerSource = enum(u8) {
    /// A guest store into the `CP_RB_WPTR` register aperture.
    guest_mmio = 0,
    /// A `CP_RB_WPTR` write carried inside the PM4 stream.
    pm4_packet = 1,
    /// The kick VdSwap performs on behalf of a caller that published.
    vdswap_kick = 2,
    /// A host forcing path. Never guest-authentic.
    debug_forced = 3,
    /// Observed as applied without the originating write being seen.
    unattributed = 4,
    unknown = 255,

    pub fn label(self: PointerSource) []const u8 {
        return switch (self) {
            .guest_mmio => "guest-mmio",
            .pm4_packet => "pm4-packet",
            .vdswap_kick => "vdswap-kick",
            .debug_forced => "debug-forced",
            .unattributed => "unattributed",
            .unknown => "unknown",
        };
    }

    pub fn sourceClass(self: PointerSource) SourceClass {
        return switch (self) {
            .guest_mmio, .pm4_packet => .guest_authentic,
            .vdswap_kick => .host_forwarded,
            .debug_forced => .synthetic,
            .unattributed, .unknown => .unknown,
        };
    }
};

/// The stages one write-pointer transition passes through, in order. Each is
/// observed independently; none is inferred from its neighbours.
pub const Stage = enum(u8) {
    /// A source wrote a value somewhere Rosette or Xenia could see it.
    source_write = 0,
    /// The address and raw value were checked against the ring's identity.
    validated = 1,
    /// Endianness and units were normalised to a dword index.
    normalised = 2,
    /// The index was checked against ring size and wrap rules.
    range_checked = 3,
    /// The command processor's authoritative write pointer changed.
    applied = 4,
    /// The consumer thread was woken.
    worker_woken = 5,
    /// The read pointer moved, so the consumer actually consumed.
    read_pointer_moved = 6,
    /// The read pointer was written back where the guest can see it.
    guest_writeback = 7,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .source_write => "source write",
            .validated => "validated address/value",
            .normalised => "endian/unit normalised",
            .range_checked => "range/wrap validated",
            .applied => "applied write pointer",
            .worker_woken => "worker wake",
            .read_pointer_moved => "read pointer movement",
            .guest_writeback => "guest writeback",
        };
    }

    pub fn owner(self: Stage) []const u8 {
        return switch (self) {
            .source_write => "guest:title",
            .validated, .normalised, .range_checked, .applied, .worker_woken, .read_pointer_moved => "xenia:command-processor",
            .guest_writeback => "xenia:command-processor",
        };
    }

    /// What a reader should do when this is the first stage missing.
    pub fn gapMeans(self: Stage) []const u8 {
        return switch (self) {
            .source_write => "no source has written a write-pointer value at all. The producer has not submitted, and every stage below this is unreachable rather than broken",
            .validated => "a value was written and rejected before validation. Read the ring identity the writer used against the one the command processor holds — a base or size mismatch lands here",
            .normalised => "the raw value was accepted and could not be converted to a dword index. This is an endianness or unit defect, and it is the emulator's",
            .range_checked => "a normalised index failed the ring's size or wrap rule. Either the guest published an out-of-range index or the ring geometry the consumer believes is wrong",
            .applied => "everything upstream succeeded and the authoritative write pointer did not change. This is the exact meaning of `printed but not applied`, and it names the apply site rather than the print site",
            .worker_woken => "the pointer was applied and no consumer was woken. The submission is sitting in a ring nothing is draining",
            .read_pointer_moved => "the consumer woke and consumed nothing. Look at the reader offsets and the packet decoder, not at the producer",
            .guest_writeback => "the ring was consumed and the guest was never told. A producer that cannot observe consumption may wait forever for progress that already happened",
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

/// A ring's identity. Two observations describe the same ring only when the
/// base and size agree; a report that merges two rings produces counters that
/// are the sum of unrelated things.
pub const Identity = extern struct {
    base: Address = .{},
    size_bytes: u32 = 0,
    /// `log2` of the size in dwords, as the guest states it to
    /// `VdInitializeRingBuffer`.
    size_log2: u8 = 0,
    reserved: u8 = 0,
    reserved2: u16 = 0,

    pub fn known(self: Identity) bool {
        return self.base.any() and self.size_bytes != 0;
    }

    pub fn dwords(self: Identity) u32 {
        return self.size_bytes / 4;
    }

    pub fn sameRing(self: Identity, other: Identity) bool {
        if (!self.known() or !other.known()) return false;
        return self.base.joins(other.base) and self.size_bytes == other.size_bytes;
    }

    /// Whether a dword index is inside this ring at all.
    pub fn indexInRange(self: Identity, index: u32) bool {
        const total = self.dwords();
        return total != 0 and index < total;
    }
};

/// One write-pointer transition, tracked stage by stage.
pub const Transition = struct {
    epoch: u64 = 0,
    source: PointerSource = .unknown,
    raw_value: u64 = 0,
    normalised_index: u32 = 0,
    applied_index: u32 = 0,
    read_index_before: u32 = 0,
    read_index_after: u32 = 0,
    reached: [stage_count]bool = [_]bool{false} ** stage_count,
    step: [stage_count]u64 = [_]u64{0} ** stage_count,

    pub fn note(self: *Transition, stage: Stage, step: u64) void {
        const index = @intFromEnum(stage);
        if (!self.reached[index]) self.step[index] = step;
        self.reached[index] = true;
    }

    pub fn has(self: Transition, stage: Stage) bool {
        return self.reached[@intFromEnum(stage)];
    }

    /// The first stage that did not happen. `null` means the transition
    /// completed end to end.
    pub fn firstGap(self: Transition) ?Stage {
        var index: usize = 0;
        while (index < stage_count) : (index += 1) {
            if (!self.reached[index]) return @enumFromInt(index);
        }
        return null;
    }

    /// The last stage that did happen, which is where a reader should start.
    pub fn lastReached(self: Transition) ?Stage {
        var index: usize = stage_count;
        while (index > 0) {
            index -= 1;
            if (self.reached[index]) return @enumFromInt(index);
        }
        return null;
    }

    /// A transition is effective when the consumer actually moved. Applying a
    /// pointer that the consumer never drains is not submission.
    pub fn effective(self: Transition) bool {
        return self.has(.read_pointer_moved) and self.read_index_after != self.read_index_before;
    }

    /// Whether the guest may be credited with this submission.
    pub fn guestAuthentic(self: Transition) bool {
        return self.source.sourceClass() == .guest_authentic;
    }
};

/// The verdict for a ring, derived from its transitions.
pub const Verdict = enum(u8) {
    /// No source has written anything.
    never_written,
    /// Writes exist and none reached `applied`.
    written_not_applied,
    /// Applied and no consumer woke.
    applied_not_consumed,
    /// Consumed and the guest was never told.
    consumed_not_reported,
    /// At least one transition completed end to end.
    complete,
    /// Every completed transition came from a host path.
    host_driven,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .never_written => "never-written",
            .written_not_applied => "WRITTEN-NOT-APPLIED",
            .applied_not_consumed => "APPLIED-NOT-CONSUMED",
            .consumed_not_reported => "CONSUMED-NOT-REPORTED",
            .complete => "complete",
            .host_driven => "HOST-DRIVEN",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .never_written => "no write-pointer value has been written by any source. The producer has not submitted; nothing below this is judgeable",
            .written_not_applied => "a source wrote a value and the authoritative write pointer never changed. This is the transport defect the phrase `printed but not applied` was pointing at, and the stage ladder names which check rejected it",
            .applied_not_consumed => "the write pointer was applied and no consumer drained it. The submission exists and nothing is reading it",
            .consumed_not_reported => "the ring was consumed and the read pointer was never written back where the guest can see it. A producer that cannot observe consumption can wait forever for progress that already happened",
            .complete => "at least one transition went from a source write to a guest-visible writeback. The transport carried it",
            .host_driven => "every completed transition came from a host forcing path. The transport works and the guest did not drive it, so no title conclusion may rest on this",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return switch (self) {
            .written_not_applied, .applied_not_consumed, .consumed_not_reported => true,
            .never_written, .complete, .host_driven => false,
        };
    }
};

/// Decide a ring from its transitions. Pure so a test can state a shape
/// directly instead of driving a ledger into it.
pub fn classify(transitions: []const Transition) Verdict {
    if (transitions.len == 0) return .never_written;
    var any_source = false;
    var any_applied = false;
    var any_woken = false;
    var any_consumed = false;
    var any_complete = false;
    var any_guest_complete = false;
    for (transitions) |transition| {
        if (transition.has(.source_write)) any_source = true;
        if (transition.has(.applied)) any_applied = true;
        if (transition.has(.worker_woken)) any_woken = true;
        if (transition.has(.read_pointer_moved)) any_consumed = true;
        if (transition.firstGap() == null) {
            any_complete = true;
            if (transition.guestAuthentic()) any_guest_complete = true;
        }
    }
    if (!any_source) return .never_written;
    if (any_complete) return if (any_guest_complete) .complete else .host_driven;
    if (any_consumed) return .consumed_not_reported;
    if (any_applied or any_woken) return .applied_not_consumed;
    return .written_not_applied;
}

test "two rings with different bases are never merged" {
    const primary = Identity{ .base = .{ .guest_physical = 0x1FC9_B000 }, .size_bytes = 0x8000, .size_log2 = 12 };
    const other = Identity{ .base = .{ .guest_physical = 0x1FC9_9000 }, .size_bytes = 0x8000, .size_log2 = 12 };
    try std.testing.expect(primary.sameRing(primary));
    try std.testing.expect(!primary.sameRing(other));
    try std.testing.expect(!primary.sameRing(.{}));
    try std.testing.expectEqual(@as(u32, 8192), primary.dwords());
    try std.testing.expect(primary.indexInRange(8191));
    try std.testing.expect(!primary.indexInRange(8192));
}

// The exact 2026-08-31 disagreement: a printed pointer update and a consumed
// batch, with nothing able to say which stage was missing.
test "printed but not applied names the apply stage rather than the print site" {
    var transition = Transition{ .epoch = 1, .source = .guest_mmio, .raw_value = 0x19 };
    transition.note(.source_write, 3_250_396_192);
    transition.note(.validated, 3_250_396_200);
    transition.note(.normalised, 3_250_396_210);
    transition.note(.range_checked, 3_250_396_220);

    try std.testing.expectEqual(Stage.applied, transition.firstGap().?);
    try std.testing.expectEqual(Stage.range_checked, transition.lastReached().?);
    try std.testing.expect(!transition.effective());
    try std.testing.expect(std.mem.indexOf(u8, Stage.applied.gapMeans(), "printed but not applied") != null);

    const verdict = classify(&[_]Transition{transition});
    try std.testing.expectEqual(Verdict.written_not_applied, verdict);
    try std.testing.expect(verdict.isDefect());
}

test "a completed guest transition is complete and a forced one is host driven" {
    var guest = Transition{ .epoch = 1, .source = .guest_mmio, .read_index_before = 0, .read_index_after = 0x19 };
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        guest.note(@enumFromInt(field.value), 100 + field.value);
    }
    try std.testing.expect(guest.firstGap() == null);
    try std.testing.expect(guest.effective());
    try std.testing.expect(guest.guestAuthentic());
    try std.testing.expectEqual(Verdict.complete, classify(&[_]Transition{guest}));

    var forced = guest;
    forced.source = .debug_forced;
    try std.testing.expect(!forced.guestAuthentic());
    try std.testing.expectEqual(SourceClass.synthetic, PointerSource.debug_forced.sourceClass());
    try std.testing.expectEqual(Verdict.host_driven, classify(&[_]Transition{forced}));
}

test "consuming without telling the guest is its own finding" {
    var transition = Transition{ .epoch = 1, .source = .guest_mmio, .read_index_before = 0, .read_index_after = 4 };
    transition.note(.source_write, 1);
    transition.note(.validated, 2);
    transition.note(.normalised, 3);
    transition.note(.range_checked, 4);
    transition.note(.applied, 5);
    transition.note(.worker_woken, 6);
    transition.note(.read_pointer_moved, 7);

    try std.testing.expectEqual(Stage.guest_writeback, transition.firstGap().?);
    try std.testing.expect(transition.effective());
    const verdict = classify(&[_]Transition{transition});
    try std.testing.expectEqual(Verdict.consumed_not_reported, verdict);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "wait forever") != null);
}

test "an empty ring is never-written rather than defective" {
    const verdict = classify(&[_]Transition{});
    try std.testing.expectEqual(Verdict.never_written, verdict);
    try std.testing.expect(!verdict.isDefect());
}

test "every stage names an owner and what its gap means" {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        try std.testing.expect(stage.label().len != 0);
        try std.testing.expect(stage.owner().len != 0);
        try std.testing.expect(stage.gapMeans().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 8), stage_count);
}
