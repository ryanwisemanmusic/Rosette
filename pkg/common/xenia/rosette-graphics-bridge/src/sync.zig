//! Guest synchronization objects: one identity, one expected notifier, one
//! classification.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run has four views of the same synchronization state and no
//! way to reconcile them. `GUEST WAIT LIVENESS` aggregates 569 waits and 535
//! signals. `WAIT AUDIT` reports `problems=0` because it excludes finite polls
//! by design. `DEADLOCK PREDICTOR` reports `deadlocked=YES`. `SIGNAL
//! EXPECTATION` reports one orphan wait and two orphan signals. All four are
//! right about their own question, and read together they say nothing is
//! wrong while a guest thread polls object `0x40004BF4` a hundred and twelve
//! times and receives nothing.
//!
//! What is missing is not another view. It is identity: who created the
//! object, who is supposed to signal it, and whether it is an idle worker's
//! condition variable or the GPU completion the frame loop is built on. A
//! never-notified idle worker and a never-notified completion object look
//! identical in every counter and are opposite findings.
//!
//! So classification here is never inferred from the counters. It is stated by
//! whoever knows — the creator's call site, the notifier's owner — and an
//! object nobody classified stays `unclassified`, which blocks the promotion
//! to a primary cause rather than permitting it.

const std = @import("std");
const contract = @import("contract.zig");

pub const Address = contract.Address;
pub const CodeLocation = contract.CodeLocation;

/// The kernel object's own semantics. Wrong semantics here produce a wait that
/// never returns or one that returns when it should not, and both look like a
/// missing signal from outside.
pub const ObjectKind = enum(u8) {
    manual_reset_event = 0,
    auto_reset_event = 1,
    semaphore = 2,
    mutant = 3,
    timer = 4,
    thread = 5,
    critical_section = 6,
    condition_variable = 7,
    io_completion = 8,
    unknown = 255,

    pub fn label(self: ObjectKind) []const u8 {
        return switch (self) {
            .manual_reset_event => "manual-reset-event",
            .auto_reset_event => "auto-reset-event",
            .semaphore => "semaphore",
            .mutant => "mutant",
            .timer => "timer",
            .thread => "thread",
            .critical_section => "critical-section",
            .condition_variable => "condition-variable",
            .io_completion => "io-completion",
            .unknown => "unknown",
        };
    }

    /// Whether a signal persists until an explicit reset. A manual-reset event
    /// signalled once releases every later waiter; an auto-reset event
    /// releases exactly one. A run that models one as the other produces a
    /// waiter that hangs or a waiter that wakes spuriously.
    pub fn signalPersists(self: ObjectKind) bool {
        return switch (self) {
            .manual_reset_event, .thread, .timer => true,
            else => false,
        };
    }

    /// Whether one signal may release more than one waiter.
    pub fn releasesAllWaiters(self: ObjectKind) bool {
        return switch (self) {
            .manual_reset_event, .thread, .condition_variable => true,
            else => false,
        };
    }
};

/// What the object is *for*. This is the field that decides whether a
/// never-notified object is the primary cause or ordinary idleness.
pub const Role = enum(u8) {
    /// A worker parked with nothing to do. Never a primary cause.
    idle_worker = 0,
    /// A startup barrier crossed once. Its silence after startup is expected.
    startup_barrier = 1,
    /// The guest waits here for the GPU to finish something. Its silence is
    /// always a finding.
    gpu_completion = 2,
    /// The guest waits here for a frame boundary.
    frame_pacing = 3,
    /// A thread handle a parent joined on.
    thread_join = 4,
    /// Title-internal, with no notifier expected from outside the title.
    title_local = 5,
    /// Nobody has said. A cause may not be assigned to this.
    unclassified = 255,

    pub fn label(self: Role) []const u8 {
        return switch (self) {
            .idle_worker => "idle-worker",
            .startup_barrier => "startup-barrier",
            .gpu_completion => "gpu-completion",
            .frame_pacing => "frame-pacing",
            .thread_join => "thread-join",
            .title_local => "title-local",
            .unclassified => "unclassified",
        };
    }

    /// Whether a missing notifier on an object in this role is a finding
    /// against someone, as opposed to a description of a quiet system.
    pub fn silenceIsFinding(self: Role) bool {
        return switch (self) {
            .gpu_completion, .frame_pacing => true,
            .idle_worker, .startup_barrier, .thread_join, .title_local => false,
            // An unclassified object is not permitted to be a finding *or* to
            // be dismissed. The missing work is the classification.
            .unclassified => false,
        };
    }

    /// Who owes the signal.
    pub fn notifierOwner(self: Role) []const u8 {
        return switch (self) {
            .idle_worker => "guest:title",
            .startup_barrier => "guest:title",
            .gpu_completion => "emulator:gpu",
            .frame_pacing => "emulator:gpu",
            .thread_join => "emulator:kernel",
            .title_local => "guest:title",
            .unclassified => "-",
        };
    }
};

/// How a waiter is using the object, which decides what its expiry means.
pub const WaitShape = enum(u8) {
    /// No timeout. Returning requires a signal.
    blocking = 0,
    /// A finite timeout, re-entered. Expiry is a normal result.
    bounded_poll = 1,
    /// A zero or near-zero timeout used to test state.
    probe = 2,
    /// A blocking wait a worker is expected to sit in.
    idle_park = 3,
    unknown = 255,

    pub fn label(self: WaitShape) []const u8 {
        return switch (self) {
            .blocking => "blocking",
            .bounded_poll => "bounded-poll",
            .probe => "probe",
            .idle_park => "idle-park",
            .unknown => "unknown",
        };
    }
};

/// The stable identity of one guest synchronization object.
pub const ObjectIdentity = extern struct {
    address: Address = .{},
    handle: u32 = 0,
    /// Incremented when the address is reused for a different object. Without
    /// it a destroyed-and-recreated object inherits the old one's waiters.
    generation: u32 = 0,
    host_object: u64 = 0,
    kind: u8 = @intFromEnum(ObjectKind.unknown),
    role: u8 = @intFromEnum(Role.unclassified),
    reserved: u16 = 0,

    pub fn kindOf(self: ObjectIdentity) ObjectKind {
        return contract.decode(ObjectKind, self.kind, .unknown);
    }

    pub fn roleOf(self: ObjectIdentity) Role {
        return contract.decode(Role, self.role, .unclassified);
    }

    pub fn known(self: ObjectIdentity) bool {
        return self.address.any() or self.handle != 0;
    }

    /// Two records are the same object only when the generation matches too.
    /// The address alone is how a reused handle inherits the previous object's
    /// waiters and turns a completed handshake into a phantom orphan.
    pub fn sameObject(self: ObjectIdentity, other: ObjectIdentity) bool {
        if (!self.known() or !other.known()) return false;
        if (self.generation != other.generation) return false;
        if (self.handle != 0 and other.handle != 0) return self.handle == other.handle;
        return self.address.joins(other.address);
    }
};

/// What the registry concluded about one object.
pub const Standing = enum(u8) {
    /// Waits and signals are both happening.
    healthy,
    /// Waited on, never signalled, and its role says that matters.
    missing_notifier,
    /// Waited on, never signalled, and its role says that is normal.
    quiet_by_role,
    /// Signalled and never waited on. Evidence of a live producer, not of a
    /// released consumer.
    orphan_signal,
    /// Waited on and never signalled, with no role stated. The finding is the
    /// missing classification, not the missing signal.
    unclassified_silence,
    /// Nothing has been recorded.
    unobserved,

    pub fn label(self: Standing) []const u8 {
        return switch (self) {
            .healthy => "healthy",
            .missing_notifier => "MISSING-NOTIFIER",
            .quiet_by_role => "quiet-by-role",
            .orphan_signal => "orphan-signal",
            .unclassified_silence => "UNCLASSIFIED-SILENCE",
            .unobserved => "unobserved",
        };
    }

    pub fn describe(self: Standing) []const u8 {
        return switch (self) {
            .healthy => "waiters are being released by signals on this object",
            .missing_notifier => "a waiter is on an object whose role says something owes it a signal, and no code has ever raised it. Find the notifier and confirm it was reached at all — this is not a late signal",
            .quiet_by_role => "an object nothing has signalled, in a role where that is what idleness looks like. Not a finding, and not evidence of health either",
            .orphan_signal => "a signal with no observed consumer. Keep it as evidence that a producer path ran; it says nothing about whether another object was released",
            .unclassified_silence => "a waiter is on an object nothing has signalled and nothing has classified. The missing work is the classification: an idle worker and a GPU completion look identical here and are opposite findings",
            .unobserved => "nothing has been recorded for this object",
        };
    }

    /// Whether this standing may be named as a run's primary cause.
    pub fn promotableToCause(self: Standing) bool {
        return self == .missing_notifier;
    }
};

/// Counters for one object, kept apart from its identity so a report can print
/// either without the other.
pub const Activity = struct {
    waits: u64 = 0,
    wait_returns: u64 = 0,
    timeouts: u64 = 0,
    signals: u64 = 0,
    /// Waits that blocked and were then released by a signal. The only counter
    /// that proves the handshake completed; a wait that returned because the
    /// object was already signalled proves nothing about the notifier.
    blocked_then_released: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    waiter_threads: u32 = 0,
    signaller_threads: u32 = 0,
    shape: WaitShape = .unknown,
    timeout_ms: i64 = 0,
};

/// Decide one object. Pure: identity and counters in, standing out.
pub fn classify(identity: ObjectIdentity, activity: Activity) Standing {
    if (activity.waits == 0 and activity.signals == 0) return .unobserved;
    if (activity.waits == 0) return .orphan_signal;
    if (activity.signals != 0) return .healthy;
    return switch (identity.roleOf()) {
        .unclassified => .unclassified_silence,
        else => |role| if (role.silenceIsFinding()) .missing_notifier else .quiet_by_role,
    };
}

/// The semantic rules a wait implementation has to obey. Stated here rather
/// than in the implementation so a differential harness can assert them
/// against whatever the emulator actually does.
pub const Semantics = struct {
    /// How many waiters one signal releases.
    pub fn waitersReleasedByOneSignal(kind: ObjectKind, waiting: u32) u32 {
        if (waiting == 0) return 0;
        return if (kind.releasesAllWaiters()) waiting else 1;
    }

    /// Whether a waiter arriving *after* a signal still sees it.
    pub fn lateWaiterSeesSignal(kind: ObjectKind, reset_since_signal: bool) bool {
        if (!kind.signalPersists()) return false;
        return !reset_since_signal;
    }

    /// Whether an expiry is a result the guest asked for, or a failure.
    pub fn expiryIsExpected(shape: WaitShape) bool {
        return shape == .bounded_poll or shape == .probe;
    }
};

test "a reused handle does not inherit the previous object's identity" {
    const first = ObjectIdentity{ .address = .{ .guest_virtual = 0x4000_4BF4 }, .handle = 0xF800_0154, .generation = 1 };
    var second = first;
    second.generation = 2;
    try std.testing.expect(first.sameObject(first));
    try std.testing.expect(!first.sameObject(second));
    try std.testing.expect(!first.sameObject(.{}));
}

// The 2026-08-31 blocker. Object 0x40004BF4, manual reset, 30 ms poll, 112
// expiries, zero signals. Whether that is the run's cause depends entirely on
// what the object is for, and nothing in the run said.
test "an unclassified silence is neither a cause nor a clean bill of health" {
    const unclassified = ObjectIdentity{
        .address = .{ .guest_virtual = 0x4000_4BF4 },
        .handle = 0xF800_0154,
        .generation = 1,
        .kind = @intFromEnum(ObjectKind.manual_reset_event),
    };
    const polling = Activity{ .waits = 112, .timeouts = 112, .signals = 0, .shape = .bounded_poll, .timeout_ms = 30 };

    const standing = classify(unclassified, polling);
    try std.testing.expectEqual(Standing.unclassified_silence, standing);
    try std.testing.expect(!standing.promotableToCause());
    try std.testing.expect(std.mem.indexOf(u8, standing.describe(), "opposite findings") != null);

    // Classified as the GPU completion it is suspected of being, the same
    // counters become the run's primary cause with a named owner.
    var completion = unclassified;
    completion.role = @intFromEnum(Role.gpu_completion);
    const promoted = classify(completion, polling);
    try std.testing.expectEqual(Standing.missing_notifier, promoted);
    try std.testing.expect(promoted.promotableToCause());
    try std.testing.expectEqualStrings("emulator:gpu", Role.gpu_completion.notifierOwner());

    // Classified as an idle worker, the same counters are ordinary idleness.
    var idle = unclassified;
    idle.role = @intFromEnum(Role.idle_worker);
    try std.testing.expectEqual(Standing.quiet_by_role, classify(idle, polling));
}

test "an orphan signal proves a producer ran and nothing else" {
    const identity = ObjectIdentity{ .address = .{ .guest_virtual = 0x827C_EC28 }, .handle = 0xF800_016C, .generation = 1 };
    const signalling = Activity{ .signals = 662, .waits = 0 };
    const standing = classify(identity, signalling);
    try std.testing.expectEqual(Standing.orphan_signal, standing);
    try std.testing.expect(!standing.promotableToCause());
}

test "manual and auto reset events differ in both directions" {
    try std.testing.expectEqual(@as(u32, 3), Semantics.waitersReleasedByOneSignal(.manual_reset_event, 3));
    try std.testing.expectEqual(@as(u32, 1), Semantics.waitersReleasedByOneSignal(.auto_reset_event, 3));
    try std.testing.expectEqual(@as(u32, 0), Semantics.waitersReleasedByOneSignal(.manual_reset_event, 0));

    try std.testing.expect(Semantics.lateWaiterSeesSignal(.manual_reset_event, false));
    try std.testing.expect(!Semantics.lateWaiterSeesSignal(.manual_reset_event, true));
    try std.testing.expect(!Semantics.lateWaiterSeesSignal(.auto_reset_event, false));

    try std.testing.expect(Semantics.expiryIsExpected(.bounded_poll));
    try std.testing.expect(!Semantics.expiryIsExpected(.blocking));
}

test "signals and waits together are healthy whatever the role" {
    const identity = ObjectIdentity{ .handle = 0xF800_0168, .generation = 1, .role = @intFromEnum(Role.unclassified) };
    const cycling = Activity{ .waits = 662, .signals = 662, .blocked_then_released = 654 };
    try std.testing.expectEqual(Standing.healthy, classify(identity, cycling));
    try std.testing.expectEqual(Standing.unobserved, classify(identity, .{}));
}

test "every role and kind states its own vocabulary" {
    inline for (@typeInfo(Role).@"enum".fields) |field| {
        const role: Role = @enumFromInt(field.value);
        try std.testing.expect(role.label().len != 0);
        try std.testing.expect(role.notifierOwner().len != 0);
    }
    inline for (@typeInfo(ObjectKind).@"enum".fields) |field| {
        const kind: ObjectKind = @enumFromInt(field.value);
        try std.testing.expect(kind.label().len != 0);
    }
    // Unclassified must never be a finding by default; that is the whole
    // reason it is a distinct value rather than a synonym for idle.
    try std.testing.expect(!Role.unclassified.silenceIsFinding());
}
