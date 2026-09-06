//! The chain a frame crosses from guest memory to the screen, with no
//! implicit substitution anywhere along it.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run presented forty-three frames and rendered none of the
//! title. Acquire, submit and present all returned success, and the presenter
//! was behaving correctly: with no guest source it drew diagnostic clears. The
//! problem is that "43 frames presented" survives being quoted out of context,
//! and the next reader concludes the pipeline works.
//!
//! So every frame carries its source class from discovery to present, the
//! presenter reports five distinct outcomes instead of one success counter,
//! and the tally keeps diagnostic frames out of the authentic total
//! permanently. A diagnostic frame is useful — it keeps the window alive and
//! proves the sink — and it can never satisfy the title contract.
//!
//! The generation rule
//! -------------------
//! A frame is new when its generation is greater than the last presented one
//! *and* its content differs, unless the producer explicitly declares a
//! repeat. Both halves are needed: a paused title legitimately renders the
//! same picture twice, and a stale buffer looks exactly like that if only the
//! checksum is consulted.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");
const handoff = @import("frame_handoff.zig");

pub const Edge = bridge.frame.Edge;
pub const PresentOutcome = bridge.frame.PresentOutcome;
pub const SourceRecord = bridge.frame.SourceRecord;
pub const Custody = bridge.frame.Custody;
pub const Tally = bridge.frame.Tally;
pub const SourceClass = bridge.contract.SourceClass;
pub const Address = bridge.contract.Address;
pub const edge_count = bridge.frame.edge_count;
pub const outcomeOf = bridge.frame.outcome;

/// What the chain as a whole is doing.
pub const Verdict = enum(u8) {
    /// No candidate has ever been offered.
    no_candidate,
    /// Candidates exist and none has an authentic guest source.
    diagnostic_only,
    /// An authentic candidate exists and stops partway.
    authentic_blocked,
    /// At least one authentic guest frame reached the screen.
    authentic_presented,
    /// An authentic frame was lost between two edges. Someone owns this.
    authentic_lost,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .no_candidate => "no-candidate",
            .diagnostic_only => "diagnostic-only",
            .authentic_blocked => "authentic-blocked",
            .authentic_presented => "authentic-presented",
            .authentic_lost => "AUTHENTIC-LOST",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .no_candidate => "nothing has offered a frame. The window may be showing something and that something is the harness's own",
            .diagnostic_only => "no retained candidate has authenticated title provenance. Host or diagnostic presentations do not prove that the title produced no output elsewhere",
            .authentic_blocked => "an authentic guest candidate exists and stops before the screen. The first missing edge names who to ask",
            .authentic_presented => "an authentic guest frame reached the screen",
            .authentic_lost => "an authentic guest frame was discovered and did not survive the crossing. This is a defect between two named edges and it is not the title's",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .authentic_lost;
    }
};

pub const max_candidates: usize = handoff.max_frames;

/// One candidate frame, its chain, and what the presenter did with it.
pub const Entry = struct {
    custody: Custody = .{},
    outcome: PresentOutcome = .no_guest_frame,
    guest_step: u64 = 0,
    /// Set once the presenter has decided, so a report cannot read an
    /// undecided candidate as `no_guest_frame`.
    decided: bool = false,
    identity: handoff.Identity = .{},
};

pub const Ledger = struct {
    entries: [max_candidates]Entry = [_]Entry{.{}} ** max_candidates,
    count: usize = 0,
    write_index: usize = 0,
    /// Candidates that have left the retained window. The tally still counts
    /// them; only the per-candidate detail is gone.
    dropped: u64 = 0,
    offered: u64 = 0,
    tally: Tally = .{},
    /// The generation and checksum of the last frame actually presented. The
    /// two together are what makes a repeat distinguishable from a stale
    /// buffer.
    last_presented_generation: u64 = 0,
    last_presented_checksum: u64 = 0,
    /// Candidates the chain refused because their source could not satisfy a
    /// title contract. Counted so the refusal is visible rather than being
    /// indistinguishable from never having been offered.
    refused_substitutions: u64 = 0,
    consecutive_authentic: u64 = 0,
    mirrored: [handoff.max_frames]handoff.Identity = [_]handoff.Identity{.{}} ** handoff.max_frames,
    mirrored_states: [handoff.max_frames]handoff.State = [_]handoff.State{.empty} ** handoff.max_frames,

    /// Preserve the canonical frame descriptor and only the custody edges it
    /// actually observed. No aggregate count is expanded into fake frames.
    pub fn syncHandoffs(self: *Ledger, source: *const handoff.Ledger) void {
        for (source.records[0..source.count], 0..) |record, index| {
            const descriptor = record.descriptor;
            const identity = descriptor.identity;
            if (record.state == .empty) continue;
            if (self.mirrored[index].eql(identity) and self.mirrored_states[index] == record.state) continue;
            self.mirrored[index] = identity;
            self.mirrored_states[index] = record.state;
            var candidate: ?*Entry = null;
            for (self.entries[0..self.count]) |*entry| {
                if (entry.identity.eql(identity)) {
                    candidate = entry;
                    break;
                }
            }
            const class: SourceClass = switch (record.frame_class) {
                .authentic_guest_present => .guest_authentic,
                .guest_pixels_host_cadence => .host_forwarded,
                .diagnostic_host => .diagnostic,
                .synthetic_guest_control => .synthetic,
                else => .unknown,
            };
            const entry = candidate orelse self.offer(.{
                .generation = identity.serial,
                .address = .{ .host = descriptor.source_address },
                .width = @intCast(@min(descriptor.width, std.math.maxInt(u16))),
                .height = @intCast(@min(descriptor.height, std.math.maxInt(u16))),
                .format = @intFromEnum(descriptor.format),
                .content_checksum = descriptor.content_digest,
                .source_class = @intFromEnum(class),
                .discovered_step = record.offered_step,
            }, record.offered_step);
            entry.identity = identity;
            // The classification may become authoritative at validation.
            entry.custody.source.source_class = @intFromEnum(class);
            if (record.validated_step != 0) entry.custody.note(.emulator_discovery, record.validated_step);
            if (descriptor.content_digest != 0) entry.custody.note(.content_generation, record.offered_step);
            if (record.acquired_step != 0) entry.custody.note(.presenter_handoff, record.acquired_step);
            if (record.presented_step != 0) {
                // Native completion of this descriptor confirms the host copy,
                // but supplies no evidence of guest render/resolve execution.
                entry.custody.note(.host_image_import, record.presented_step);
                entry.custody.note(.native_present, record.presented_step);
                _ = self.decide(entry);
            } else if (record.rejection == .presentation_failed) {
                _ = self.decide(entry);
            }
        }
    }

    /// Offer a candidate.
    ///
    /// The retained window is a ring rather than a cap, and `offer` never
    /// declines. The tally is the durable record and the entries are only the
    /// most recent examples: a ledger that stopped accepting candidates once
    /// its window filled would stop counting frames, which is the opposite of
    /// what a presenter needs from it.
    pub fn offer(self: *Ledger, source: SourceRecord, guest_step: u64) *Entry {
        self.offered +|= 1;
        if (self.count >= max_candidates) self.dropped +|= 1;
        const slot = &self.entries[self.write_index];
        self.write_index = (self.write_index + 1) % max_candidates;
        if (self.count < max_candidates) self.count += 1;
        slot.* = .{ .custody = .{ .source = source }, .guest_step = guest_step };
        return slot;
    }

    /// Decide a candidate and fold it into the tally.
    ///
    /// The generation baseline only advances for a frame that actually
    /// reached the screen. A candidate that was discovered and dropped must
    /// not raise the bar for the next one.
    pub fn decide(self: *Ledger, entry: *Entry) PresentOutcome {
        if (entry.decided) return entry.outcome;
        const result = outcomeOf(
            entry.custody,
            self.last_presented_generation,
            self.last_presented_checksum,
        );
        entry.outcome = result;
        entry.decided = true;
        const class = entry.custody.source.sourceOf();
        self.tally.note(result, class);
        if (result == .guest_frame_presented and entry.custody.satisfiesTitleContract()) {
            self.consecutive_authentic +|= 1;
        } else {
            self.consecutive_authentic = 0;
        }
        if (result == .guest_frame_presented and class == .guest_authentic) {
            self.last_presented_generation = entry.custody.source.generation;
            self.last_presented_checksum = entry.custody.source.content_checksum;
        }
        return result;
    }

    /// Record that a candidate was refused because its source class cannot
    /// satisfy the title contract. Kept as its own counter because a refusal
    /// and an absence look identical downstream.
    pub fn refuseSubstitution(self: *Ledger) void {
        self.refused_substitutions +|= 1;
    }

    pub fn retained(self: *const Ledger) []const Entry {
        return self.entries[0..self.count];
    }

    /// The first edge no authentic candidate has ever crossed. Diagnostic
    /// candidates are excluded on purpose: a harness frame crossing every edge
    /// says nothing about where the title's frame stops.
    pub fn authenticFrontier(self: *const Ledger) ?Edge {
        var best: ?Edge = null;
        var any_authentic = false;
        for (self.retained()) |entry| {
            if (!entry.custody.source.sourceOf().satisfiesTitleContract()) continue;
            any_authentic = true;
            const gap = entry.custody.firstGap() orelse return null;
            if (best == null or @intFromEnum(gap) > @intFromEnum(best.?)) best = gap;
        }
        if (!any_authentic) return .guest_render_target;
        return best;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.offered == 0) return .no_candidate;
        if (self.tally.authenticFrames() != 0) return .authentic_presented;
        if (self.tally.anyDefect()) return .authentic_lost;
        var any_authentic = false;
        for (self.retained()) |entry| {
            if (entry.custody.source.sourceOf().satisfiesTitleContract()) any_authentic = true;
        }
        return if (any_authentic) .authentic_blocked else .diagnostic_only;
    }

    /// The audit's stable-output gate: ten consecutive authentic frames with
    /// nothing synthetic counted among them.
    pub fn stableOutput(self: *const Ledger) bool {
        return self.consecutive_authentic >= 10;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = self.offered;
        hash = hash *% 31 +% self.tally.authenticFrames();
        hash = hash *% 31 +% self.tally.totalPresented();
        hash = hash *% 31 +% @intFromEnum(self.verdict());
        return hash;
    }
};

fn diagnosticSource(generation: u64) SourceRecord {
    return .{
        .generation = generation,
        .address = .{ .guest_physical = 0x1FC0_0000 },
        .width = 1280,
        .height = 720,
        .content_checksum = generation,
        .source_class = @intFromEnum(SourceClass.diagnostic),
    };
}

fn crossEveryEdge(custody: *Custody) void {
    inline for (@typeInfo(Edge).@"enum".fields) |field| {
        custody.note(@enumFromInt(field.value), 100 + field.value);
    }
}

// The 2026-08-31 presenter state, exactly: 43 successful presents, zero title
// frames, and a report that must not read as progress.
test "forty-three diagnostic presents never become an authentic frame" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 43) : (index += 1) {
        const entry = ledger.offer(diagnosticSource(index + 1), 1000 + index);
        crossEveryEdge(&entry.custody);
        _ = ledger.decide(entry);
    }
    try std.testing.expectEqual(@as(u64, 0), ledger.tally.authenticFrames());
    try std.testing.expectEqual(@as(u64, 43), ledger.tally.totalPresented());
    try std.testing.expectEqual(Verdict.diagnostic_only, ledger.verdict());
    try std.testing.expect(!ledger.stableOutput());
    try std.testing.expectEqual(@as(u64, 0), ledger.last_presented_generation);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_presented_checksum);
    // No authentic candidate has ever existed, so the frontier is the very
    // first guest-owned edge rather than anything the presenter did.
    try std.testing.expectEqual(Edge.guest_render_target, ledger.authenticFrontier().?);
}

test "an authentic frame that stops partway names the edge it stopped at" {
    var ledger = Ledger{};
    var source = diagnosticSource(1);
    source.source_class = @intFromEnum(SourceClass.guest_authentic);
    const entry = ledger.offer(source, 2000);
    entry.custody.note(.guest_render_target, 10);
    entry.custody.note(.guest_resolve_output, 11);
    entry.custody.note(.content_generation, 12);

    try std.testing.expectEqual(Edge.emulator_discovery, ledger.authenticFrontier().?);
    _ = ledger.decide(entry);
    try std.testing.expectEqual(PresentOutcome.no_guest_frame, entry.outcome);
    try std.testing.expectEqual(Verdict.authentic_blocked, ledger.verdict());
}

test "an authentic frame lost in the crossing is a defect with two named edges" {
    var ledger = Ledger{};
    var source = diagnosticSource(1);
    source.source_class = @intFromEnum(SourceClass.guest_authentic);
    const entry = ledger.offer(source, 2000);
    entry.custody.note(.emulator_discovery, 10);
    _ = ledger.decide(entry);
    try std.testing.expectEqual(PresentOutcome.guest_frame_copy_failed, entry.outcome);
    const verdict = ledger.verdict();
    try std.testing.expectEqual(Verdict.authentic_lost, verdict);
    try std.testing.expect(verdict.isDefect());
}

test "the generation baseline only moves for a frame that reached the screen" {
    var ledger = Ledger{};
    var first = diagnosticSource(5);
    first.source_class = @intFromEnum(SourceClass.guest_authentic);
    const dropped = ledger.offer(first, 100);
    dropped.custody.note(.emulator_discovery, 10);
    _ = ledger.decide(dropped);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_presented_generation);

    var second = diagnosticSource(6);
    second.source_class = @intFromEnum(SourceClass.guest_authentic);
    second.content_checksum = 0xAAAA;
    const shown = ledger.offer(second, 200);
    crossEveryEdge(&shown.custody);
    try std.testing.expectEqual(PresentOutcome.guest_frame_presented, ledger.decide(shown));
    try std.testing.expectEqual(@as(u64, 6), ledger.last_presented_generation);
    try std.testing.expectEqual(@as(u64, 0xAAAA), ledger.last_presented_checksum);
}

test "a repeated picture is new output only when the producer declares it" {
    var ledger = Ledger{};
    var source = diagnosticSource(1);
    source.source_class = @intFromEnum(SourceClass.guest_authentic);
    source.content_checksum = 0xFEED;
    const first = ledger.offer(source, 100);
    crossEveryEdge(&first.custody);
    try std.testing.expectEqual(PresentOutcome.guest_frame_presented, ledger.decide(first));

    var repeat = source;
    repeat.generation = 2;
    const second = ledger.offer(repeat, 200);
    crossEveryEdge(&second.custody);
    try std.testing.expectEqual(PresentOutcome.guest_frame_unchanged, ledger.decide(second));

    var declared = repeat;
    declared.generation = 3;
    declared.repeat_declared = 1;
    const third = ledger.offer(declared, 300);
    crossEveryEdge(&third.custody);
    try std.testing.expectEqual(PresentOutcome.guest_frame_presented, ledger.decide(third));
    try std.testing.expectEqual(@as(u64, 2), ledger.tally.authenticFrames());
}

test "stable output needs ten authentic frames and nothing synthetic" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 10) : (index += 1) {
        var source = diagnosticSource(index + 1);
        source.source_class = @intFromEnum(SourceClass.guest_authentic);
        source.content_checksum = 0x1000 + index;
        const entry = ledger.offer(source, index);
        crossEveryEdge(&entry.custody);
        _ = ledger.decide(entry);
    }
    try std.testing.expectEqual(@as(u64, 10), ledger.tally.authenticFrames());
    try std.testing.expect(ledger.stableOutput());
    try std.testing.expectEqual(Verdict.authentic_presented, ledger.verdict());

    const synthetic = ledger.offer(diagnosticSource(11), 11);
    synthetic.custody.source.source_class = @intFromEnum(SourceClass.synthetic);
    crossEveryEdge(&synthetic.custody);
    _ = ledger.decide(synthetic);
    try std.testing.expect(!ledger.stableOutput());
}

test "a refused substitution is counted rather than looking like an absence" {
    var ledger = Ledger{};
    ledger.refuseSubstitution();
    ledger.refuseSubstitution();
    try std.testing.expectEqual(@as(u64, 2), ledger.refused_substitutions);
    try std.testing.expectEqual(Verdict.no_candidate, ledger.verdict());
}

test "the candidate list is bounded and reports what it shed" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_candidates + 3) : (index += 1) {
        const entry = ledger.offer(diagnosticSource(index + 1), index);
        crossEveryEdge(&entry.custody);
        _ = ledger.decide(entry);
    }
    try std.testing.expectEqual(max_candidates, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 3), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_candidates + 3), ledger.offered);
    // The window shed detail and the tally did not lose a single frame.
    try std.testing.expectEqual(@as(u64, max_candidates + 3), ledger.tally.totalPresented());
}

test "canonical handoff retains actual dimensions and completion identity" {
    var frames = handoff.Ledger{};
    frames.count = 1;
    frames.records[0] = .{
        .descriptor = .{
            .identity = .{ .run = 1, .source = 0x1234, .generation = 2, .serial = 24 },
            .source_address = 0x1234,
            .width = 2560,
            .height = 1440,
            .presentations_covered = 24,
        },
        .state = .released,
        .frame_class = .diagnostic_host,
        .offered_step = 100,
        .validated_step = 100,
        .acquired_step = 101,
        .presented_step = 102,
    };
    var ledger = Ledger{};
    ledger.syncHandoffs(&frames);
    ledger.syncHandoffs(&frames);
    try std.testing.expectEqual(@as(u64, 1), ledger.offered);
    try std.testing.expectEqual(@as(u64, 1), ledger.tally.diagnostic_presented);
    try std.testing.expectEqual(@as(u16, 2560), ledger.entries[0].custody.source.width);
    try std.testing.expectEqual(@as(u16, 1440), ledger.entries[0].custody.source.height);
    try std.testing.expect(!ledger.entries[0].custody.has(.guest_render_target));
    try std.testing.expect(!ledger.stableOutput());
}

test "deciding the same candidate twice does not credit two frames" {
    var ledger = Ledger{};
    const entry = ledger.offer(diagnosticSource(1), 10);
    entry.custody.note(.emulator_discovery, 10);
    entry.custody.note(.host_image_import, 11);
    entry.custody.note(.presenter_handoff, 12);
    entry.custody.note(.native_present, 13);
    _ = ledger.decide(entry);
    _ = ledger.decide(entry);
    try std.testing.expectEqual(@as(u64, 1), ledger.tally.totalPresented());
}
