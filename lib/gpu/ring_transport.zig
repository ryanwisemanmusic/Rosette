//! One ledger per ring, and one authority for what its write pointer did.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run reported `SUBMISSION PROVENANCE: PRINTED_BUT_NOT_APPLIED`
//! — the emulator printed a pointer update and the applied-update counter did
//! not see it — while a different layer in the same run consumed the batch
//! that update described. Both statements were true about what they watched
//! and there was nothing to join them, because the emulator has four code
//! paths that can supply a write pointer (guest MMIO, a PM4 packet, a VdSwap
//! kick, and debug forcing) and "the pointer was updated" collapsed all of
//! them into one sentence.
//!
//! So a transition here has one sequence number, one producer epoch, and eight
//! separately observed stages. The report cannot say `printed but not applied`
//! without naming the stage that rejected it and the competing edge that
//! consumed data.
//!
//! What it never does
//! ------------------
//! It does not infer a stage from the next one, and it does not advance a
//! pointer. A stage that was not observed stays unobserved; that is the whole
//! reason the ladder exists.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const Stage = bridge.ring.Stage;
pub const PointerSource = bridge.ring.PointerSource;
pub const Identity = bridge.ring.Identity;
pub const Transition = bridge.ring.Transition;
pub const Verdict = bridge.ring.Verdict;
pub const stage_count = bridge.ring.stage_count;
pub const classify = bridge.ring.classify;
pub const Address = bridge.contract.Address;
pub const SourceClass = bridge.contract.SourceClass;

pub const max_transitions: usize = 64;

pub const Summary = struct {
    identity: Identity = .{},
    transitions: u64 = 0,
    retained: usize = 0,
    dropped: u64 = 0,
    effective: u64 = 0,
    guest_authentic: u64 = 0,
    host_sourced: u64 = 0,
    /// Per-stage counts, so a report can show where the ladder thins out
    /// rather than only where it ends.
    reached: [stage_count]u64 = [_]u64{0} ** stage_count,
    /// A conflicting identity was offered for this ring. Two rings merged into
    /// one ledger produce counters that are the sum of unrelated things.
    identity_conflicts: u64 = 0,
    consumed_dwords: u64 = 0,
};

/// One ring's transport ledger.
pub const Ledger = struct {
    identity: Identity = .{},
    identity_conflicts: u64 = 0,
    transitions: [max_transitions]Transition = [_]Transition{.{}} ** max_transitions,
    count: usize = 0,
    write_index: usize = 0,
    dropped: u64 = 0,
    total: u64 = 0,
    epoch: u64 = 0,
    consumed_dwords: u64 = 0,

    /// State the ring's identity. A conflicting statement is counted and
    /// refused rather than overwriting: the first ring a ledger was told about
    /// is the one its counters describe.
    pub fn declare(self: *Ledger, identity: Identity) bool {
        if (!self.identity.known()) {
            self.identity = identity;
            return true;
        }
        if (self.identity.sameRing(identity)) return true;
        self.identity_conflicts +|= 1;
        return false;
    }

    /// Open a transition. The ring is a window; the totals are durable.
    pub fn begin(self: *Ledger, source: PointerSource, raw_value: u64) *Transition {
        self.total +|= 1;
        self.epoch +|= 1;
        if (self.count >= max_transitions) self.dropped +|= 1;
        const slot = &self.transitions[self.write_index];
        self.write_index = (self.write_index + 1) % max_transitions;
        if (self.count < max_transitions) self.count += 1;
        slot.* = .{ .epoch = self.epoch, .source = source, .raw_value = raw_value };
        return slot;
    }

    pub fn noteConsumed(self: *Ledger, dwords: u64) void {
        self.consumed_dwords +|= dwords;
    }

    pub fn retained(self: *const Ledger) []const Transition {
        return self.transitions[0..self.count];
    }

    pub fn verdict(self: *const Ledger) Verdict {
        return classify(self.retained());
    }

    /// The first stage no transition has ever reached.
    pub fn frontier(self: *const Ledger) ?Stage {
        if (self.count == 0) return .source_write;
        var index: usize = 0;
        while (index < stage_count) : (index += 1) {
            var any = false;
            for (self.retained()) |transition| {
                if (transition.reached[index]) any = true;
            }
            if (!any) return @enumFromInt(index);
        }
        return null;
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{
            .identity = self.identity,
            .transitions = self.total,
            .retained = self.count,
            .dropped = self.dropped,
            .identity_conflicts = self.identity_conflicts,
            .consumed_dwords = self.consumed_dwords,
        };
        for (self.retained()) |transition| {
            if (transition.effective()) out.effective +|= 1;
            if (transition.guestAuthentic()) {
                out.guest_authentic +|= 1;
            } else {
                out.host_sourced +|= 1;
            }
            var index: usize = 0;
            while (index < stage_count) : (index += 1) {
                if (transition.reached[index]) out.reached[index] +|= 1;
            }
        }
        return out;
    }

    /// The audit's G2 criterion: at least two guest publications, each with a
    /// canonical applied record, and each linked to a worker wake and a read
    /// pointer that moved.
    pub fn meetsPublicationGate(self: *const Ledger) bool {
        var complete: u64 = 0;
        for (self.retained()) |transition| {
            if (!transition.guestAuthentic()) continue;
            if (!transition.has(.applied)) continue;
            if (!transition.has(.worker_woken)) continue;
            if (!transition.effective()) continue;
            complete += 1;
        }
        return complete >= 2;
    }

    /// Whether the report is entitled to say `printed but not applied`. It is
    /// only entitled to when it can also name the stage that rejected it.
    pub fn printedButNotApplied(self: *const Ledger) ?Stage {
        if (self.verdict() != .written_not_applied) return null;
        var worst: ?Stage = null;
        for (self.retained()) |transition| {
            const gap = transition.firstGap() orelse continue;
            if (worst == null or @intFromEnum(gap) > @intFromEnum(worst.?)) worst = gap;
        }
        return worst;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        const totals = self.summary();
        var hash: u64 = totals.transitions;
        hash = hash *% 31 +% totals.effective;
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        hash = hash *% 31 +% totals.identity_conflicts;
        return hash;
    }
};

fn completeTransition(ledger: *Ledger, source: PointerSource, read_before: u32, read_after: u32, step: u64) void {
    const transition = ledger.begin(source, read_after);
    transition.read_index_before = read_before;
    transition.read_index_after = read_after;
    transition.normalised_index = read_after;
    transition.applied_index = read_after;
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        transition.note(@enumFromInt(field.value), step + field.value);
    }
}

test "a second ring identity is refused rather than merged in" {
    var ledger = Ledger{};
    const primary = Identity{ .base = .{ .guest_physical = 0x1FC9_B000 }, .size_bytes = 0x8000, .size_log2 = 12 };
    try std.testing.expect(ledger.declare(primary));
    try std.testing.expect(ledger.declare(primary));
    try std.testing.expect(!ledger.declare(.{ .base = .{ .guest_physical = 0x1FC9_9000 }, .size_bytes = 0x8000 }));
    try std.testing.expectEqual(@as(u64, 1), ledger.identity_conflicts);
    try std.testing.expectEqual(@as(u32, 0x1FC9_B000), ledger.identity.base.guest_physical);
}

// The exact 2026-08-31 report, and the sentence it is now required to finish.
test "printed but not applied has to name the stage that rejected it" {
    var ledger = Ledger{};
    _ = ledger.declare(.{ .base = .{ .guest_physical = 0x1FC9_B000 }, .size_bytes = 0x8000 });
    const transition = ledger.begin(.guest_mmio, 0x19);
    transition.note(.source_write, 3_250_396_192);
    transition.note(.validated, 3_250_396_200);
    transition.note(.normalised, 3_250_396_210);
    transition.note(.range_checked, 3_250_396_220);

    try std.testing.expectEqual(Verdict.written_not_applied, ledger.verdict());
    try std.testing.expectEqual(Stage.applied, ledger.printedButNotApplied().?);
    try std.testing.expectEqual(Stage.applied, ledger.frontier().?);
    try std.testing.expect(!ledger.meetsPublicationGate());
}

test "two complete guest publications meet the submission gate" {
    var ledger = Ledger{};
    _ = ledger.declare(.{ .base = .{ .guest_physical = 0x1FC9_B000 }, .size_bytes = 0x8000 });
    completeTransition(&ledger, .guest_mmio, 0, 0x19, 1000);
    try std.testing.expect(!ledger.meetsPublicationGate());
    completeTransition(&ledger, .guest_mmio, 0x19, 0x40, 2000);
    try std.testing.expect(ledger.meetsPublicationGate());
    try std.testing.expectEqual(Verdict.complete, ledger.verdict());
    try std.testing.expect(ledger.printedButNotApplied() == null);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 2), totals.effective);
    try std.testing.expectEqual(@as(u64, 2), totals.guest_authentic);
    try std.testing.expectEqual(@as(u64, 0), totals.host_sourced);
}

test "host-forced publications never satisfy the guest submission gate" {
    var ledger = Ledger{};
    completeTransition(&ledger, .debug_forced, 0, 0x10, 1000);
    completeTransition(&ledger, .debug_forced, 0x10, 0x20, 2000);
    try std.testing.expect(!ledger.meetsPublicationGate());
    try std.testing.expectEqual(Verdict.host_driven, ledger.verdict());
    try std.testing.expectEqual(@as(u64, 2), ledger.summary().host_sourced);
    try std.testing.expectEqual(SourceClass.synthetic, PointerSource.debug_forced.sourceClass());
}

test "an applied pointer nothing drained is its own verdict" {
    var ledger = Ledger{};
    const transition = ledger.begin(.guest_mmio, 4);
    transition.note(.source_write, 1);
    transition.note(.validated, 2);
    transition.note(.normalised, 3);
    transition.note(.range_checked, 4);
    transition.note(.applied, 5);
    try std.testing.expectEqual(Verdict.applied_not_consumed, ledger.verdict());
    try std.testing.expect(ledger.verdict().isDefect());
    try std.testing.expectEqual(Stage.worker_woken, ledger.frontier().?);
}

test "an untouched ring is never-written rather than defective" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.never_written, ledger.verdict());
    try std.testing.expect(!ledger.verdict().isDefect());
    try std.testing.expectEqual(Stage.source_write, ledger.frontier().?);
    try std.testing.expect(ledger.printedButNotApplied() == null);
}

test "the transition window is a ring and the totals are durable" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_transitions + 4) : (index += 1) {
        completeTransition(&ledger, .guest_mmio, @intCast(index), @intCast(index + 1), index * 10);
    }
    try std.testing.expectEqual(max_transitions, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 4), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_transitions + 4), ledger.total);
    try std.testing.expectEqual(@as(u64, max_transitions + 4), ledger.epoch);
}

test "per-stage counts show where the ladder thins rather than only where it ends" {
    var ledger = Ledger{};
    const first = ledger.begin(.guest_mmio, 1);
    first.note(.source_write, 10);
    first.note(.validated, 11);
    const second = ledger.begin(.guest_mmio, 2);
    second.note(.source_write, 20);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 2), totals.reached[@intFromEnum(Stage.source_write)]);
    try std.testing.expectEqual(@as(u64, 1), totals.reached[@intFromEnum(Stage.validated)]);
    try std.testing.expectEqual(@as(u64, 0), totals.reached[@intFromEnum(Stage.applied)]);
}
