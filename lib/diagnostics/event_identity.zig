//! One identity for every boundary event in a run, so records can be joined
//! without guessing.
//!
//! The graphics investigation has repeatedly been misled by joining evidence
//! that did not belong together: a critical-section state from one run read
//! against a ladder count from another, a `VdSwap=0` from a triage summary read
//! against a ring pointer from a different log. Both readings were reasonable
//! and both were wrong, because nothing in either record said which run it came
//! from or what order it happened in.
//!
//! So every record carries a run identifier and a monotonic sequence. The run
//! identifier makes cross-run joins impossible rather than merely discouraged;
//! the sequence makes ordering a fact rather than an inference from wall-clock
//! timestamps, which interleave badly across threads and do not survive log
//! merging at all.
//!
//! The budget is not politeness. Xenia executes ten billion steps in a run, and
//! an unbounded per-event log would change the scheduling it is trying to
//! observe and fill the disk before the interesting part. Each kind gets its
//! own allowance, and exhausting one is itself recorded — a suppressed count is
//! information, and silently dropping events is how a log comes to imply
//! something stopped happening when it only stopped being written down.

const std = @import("std");

/// Event families, budgeted separately. A flood of one kind must not consume
/// the allowance of another: the rare event is usually the informative one.
pub const Kind = enum(u8) {
    /// Entry to or return from a traced execution boundary.
    execution_boundary,
    /// Guest GPU frame-boundary operations.
    swap,
    /// Ring publication and command-processor consumption.
    ring,
    /// Render-target and front-buffer writes.
    render_target,
    /// Presenter acquire/submit/present.
    presentation,
    /// Thread state, waits and wake sources.
    scheduler,
    /// Guest assertions, declines and import anomalies.
    anomaly,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .execution_boundary => "boundary",
            .swap => "swap",
            .ring => "ring",
            .render_target => "render_target",
            .presentation => "presentation",
            .scheduler => "scheduler",
            .anomaly => "anomaly",
        };
    }

    /// How many of this kind a run may record. Chosen so the rare events are
    /// never crowded out by the common ones.
    pub fn budget(self: Kind) u32 {
        return switch (self) {
            // Every one of these matters; there should be very few.
            .swap => 512,
            .render_target => 256,
            .presentation => 512,
            .execution_boundary => 1024,
            .ring => 1024,
            .scheduler => 512,
            .anomaly => 256,
        };
    }
};

pub const kind_count: usize = @typeInfo(Kind).@"enum".fields.len;

/// What every boundary record carries. Nothing here is optional: a record
/// missing its thread or its step cannot be correlated with anything, which
/// makes it decorative.
pub const Identity = struct {
    run_id: u64,
    sequence: u64,
    kind: Kind,
    guest_step: u64,
    guest_thread: u64,
    host_thread: u64,
    caller_pc: u64,
};

/// The extra fields a GPU record carries. Kept separate from `Identity`
/// because a scheduler event has no frame serial, and a struct where half the
/// fields are conventionally zero teaches readers to ignore zeros.
pub const GpuIdentity = struct {
    frame_serial: u64 = 0,
    swap_packet_serial: u64 = 0,
    ring_generation: u32 = 0,
    read_pointer_before: u32 = 0,
    read_pointer_after: u32 = 0,
    write_pointer_before: u32 = 0,
    write_pointer_after: u32 = 0,

    /// Whether the ring pointers actually moved. A record showing identical
    /// before/after pointers documents an operation that published nothing,
    /// and that is the distinction the whole ring investigation turned on.
    pub fn ringAdvanced(self: GpuIdentity) bool {
        return self.write_pointer_before != self.write_pointer_after or
            self.read_pointer_before != self.read_pointer_after;
    }
};

pub const Stream = struct {
    run_id: u64 = 0,
    sequence: u64 = 0,
    emitted: [kind_count]u32 = [_]u32{0} ** kind_count,
    suppressed: [kind_count]u32 = [_]u32{0} ** kind_count,
    started: bool = false,

    /// A run identifier that cannot collide with the previous run by accident.
    /// The seed is supplied rather than read from a clock here so the stream
    /// stays testable; the caller mixes in whatever entropy it has.
    pub fn begin(self: *Stream, seed: u64) void {
        // A cheap avalanche so two runs started in the same millisecond do not
        // produce adjacent-looking identifiers that a reader might equate.
        var value = seed +% 0x9E37_79B9_7F4A_7C15;
        value = (value ^ (value >> 30)) *% 0xBF58_476D_1CE4_E5B9;
        value = (value ^ (value >> 27)) *% 0x94D0_49BB_1331_11EB;
        value ^= value >> 31;
        // Never zero: zero reads as "unset" everywhere else in the runtime.
        self.run_id = if (value == 0) 1 else value;
        self.sequence = 0;
        self.emitted = [_]u32{0} ** kind_count;
        self.suppressed = [_]u32{0} ** kind_count;
        self.started = true;
    }

    /// Take the next identity for `kind`, or `null` when this kind's budget is
    /// spent. A `null` is recorded as suppressed rather than ignored.
    pub fn next(
        self: *Stream,
        kind: Kind,
        guest_step: u64,
        guest_thread: u64,
        host_thread: u64,
        caller_pc: u64,
    ) ?Identity {
        if (!self.started) return null;
        const index = @intFromEnum(kind);
        if (self.emitted[index] >= kind.budget()) {
            self.suppressed[index] +|= 1;
            return null;
        }
        self.emitted[index] += 1;
        self.sequence +%= 1;
        return .{
            .run_id = self.run_id,
            .sequence = self.sequence,
            .kind = kind,
            .guest_step = guest_step,
            .guest_thread = guest_thread,
            .host_thread = host_thread,
            .caller_pc = caller_pc,
        };
    }

    /// Whether anything of this kind was dropped, which a summary must say so
    /// that a reader does not conclude the events stopped occurring.
    pub fn suppressedCount(self: *const Stream, kind: Kind) u32 {
        return self.suppressed[@intFromEnum(kind)];
    }

    pub fn emittedCount(self: *const Stream, kind: Kind) u32 {
        return self.emitted[@intFromEnum(kind)];
    }

    pub fn anySuppressed(self: *const Stream) bool {
        for (self.suppressed) |count| {
            if (count != 0) return true;
        }
        return false;
    }

    /// Whether two records belong to the same run. Written as a predicate so
    /// no caller writes its own version and gets it wrong in the direction
    /// that joins unrelated evidence.
    pub fn sameRun(self: *const Stream, identity: Identity) bool {
        return self.started and identity.run_id == self.run_id;
    }
};

test "a run identifier is never zero and differs between runs" {
    var first = Stream{};
    first.begin(0);
    try std.testing.expect(first.run_id != 0);

    var second = Stream{};
    second.begin(1);
    try std.testing.expect(second.run_id != 0);
    try std.testing.expect(first.run_id != second.run_id);
}

// Adjacent seeds must not produce adjacent identifiers: two runs a millisecond
// apart would otherwise look related enough to join.
test "adjacent seeds do not produce adjacent identifiers" {
    var a = Stream{};
    var b = Stream{};
    a.begin(1000);
    b.begin(1001);
    const difference = if (a.run_id > b.run_id) a.run_id - b.run_id else b.run_id - a.run_id;
    try std.testing.expect(difference > 1000);
}

test "sequence is monotonic across kinds" {
    var stream = Stream{};
    stream.begin(7);
    const first = stream.next(.swap, 100, 1, 2, 0x400).?;
    const second = stream.next(.ring, 200, 1, 2, 0x408).?;
    const third = stream.next(.swap, 300, 1, 2, 0x410).?;
    try std.testing.expectEqual(@as(u64, 1), first.sequence);
    try std.testing.expectEqual(@as(u64, 2), second.sequence);
    try std.testing.expectEqual(@as(u64, 3), third.sequence);
    try std.testing.expectEqual(first.run_id, third.run_id);
}

// An unstarted stream must not hand out identities: a record carrying run_id 0
// would join with every other unstarted record ever written.
test "an unstarted stream issues nothing" {
    var stream = Stream{};
    try std.testing.expect(stream.next(.swap, 1, 1, 1, 1) == null);
}

test "a spent budget suppresses rather than silently dropping" {
    var stream = Stream{};
    stream.begin(3);
    var issued: u32 = 0;
    while (stream.next(.anomaly, 1, 1, 1, 1)) |_| : (issued += 1) {
        if (issued > Kind.anomaly.budget() + 8) break;
    }
    try std.testing.expectEqual(Kind.anomaly.budget(), issued);
    try std.testing.expect(stream.suppressedCount(.anomaly) > 0);
    try std.testing.expect(stream.anySuppressed());
}

// The rare event is the informative one, so a flood of ring records must not
// consume the swap allowance.
test "one kind exhausting its budget does not starve another" {
    var stream = Stream{};
    stream.begin(11);
    var index: u32 = 0;
    while (index < Kind.ring.budget() + 100) : (index += 1) {
        _ = stream.next(.ring, index, 1, 1, 0);
    }
    try std.testing.expect(stream.suppressedCount(.ring) > 0);
    try std.testing.expectEqual(@as(u32, 0), stream.suppressedCount(.swap));
    try std.testing.expect(stream.next(.swap, 1, 1, 1, 1) != null);
}

test "records from a different run are not accepted as this run's" {
    var stream = Stream{};
    stream.begin(5);
    const mine = stream.next(.swap, 1, 1, 1, 1).?;
    try std.testing.expect(stream.sameRun(mine));

    var other = Stream{};
    other.begin(6);
    const theirs = other.next(.swap, 1, 1, 1, 1).?;
    try std.testing.expect(!stream.sameRun(theirs));
}

// Identical before/after pointers document an operation that published
// nothing, which is exactly the distinction the ring investigation turned on.
test "a GPU record says whether the ring actually moved" {
    const stalled = GpuIdentity{ .write_pointer_before = 0x19, .write_pointer_after = 0x19 };
    try std.testing.expect(!stalled.ringAdvanced());

    const advanced = GpuIdentity{ .write_pointer_before = 0x16, .write_pointer_after = 0x19 };
    try std.testing.expect(advanced.ringAdvanced());

    // A consumer catching up is movement too.
    const drained = GpuIdentity{ .read_pointer_before = 0x16, .read_pointer_after = 0x19 };
    try std.testing.expect(drained.ringAdvanced());
}

test "every kind has a label and a non-zero budget" {
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const kind: Kind = @enumFromInt(field.value);
        try std.testing.expect(kind.label().len > 0);
        try std.testing.expect(kind.budget() > 0);
    }
}
