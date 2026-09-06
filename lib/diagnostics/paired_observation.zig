//! Offline contract for observer-on/observer-off non-interference.
//!
//! A diagnostic observer is useful only if it can be shown not to change the
//! semantic run. This module compares sealed run samples by identity and
//! semantic digests; it never treats a missing or damaged observer stream as
//! proof of equivalence.

const std = @import("std");

pub const schema_version: u16 = 1;

pub const ObserverMode = enum(u8) {
    off,
    on,
};

pub const Outcome = enum(u8) {
    equivalent,
    observer_sensitive,
    incomparable,
    invalid,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .equivalent => "equivalent",
            .observer_sensitive => "observer-sensitive",
            .incomparable => "incomparable",
            .invalid => "invalid",
        };
    }
};

pub const Sample = struct {
    schema: u16 = schema_version,
    mode: ObserverMode = .off,
    run_id: u64 = 0,
    identity_fingerprint: u64 = 0,
    profile_fingerprint: u64 = 0,
    input_digest: u64 = 0,
    observer_config_digest: u64 = 0,
    semantic_digest: u64 = 0,
    guest_frontier_digest: u64 = 0,
    frame_digest: u64 = 0,
    wait_digest: u64 = 0,
    pm4_digest: u64 = 0,
    event_digest: u64 = 0,
    observer_overhead_ns: u64 = 0,
    drops: u64 = 0,
    suppression: u64 = 0,
    truncation: u64 = 0,
    sequence_gaps: u64 = 0,
    parser_errors: u64 = 0,
    sealed: bool = false,

    pub fn valid(self: Sample) bool {
        return self.schema == schema_version and self.run_id != 0 and
            self.identity_fingerprint != 0 and self.profile_fingerprint != 0 and
            self.input_digest != 0 and self.semantic_digest != 0 and
            self.sealed;
    }

    pub fn observerIntact(self: Sample) bool {
        return self.drops == 0 and self.suppression == 0 and
            self.truncation == 0 and self.sequence_gaps == 0 and
            self.parser_errors == 0;
    }

    pub fn semanticFingerprint(self: Sample) u64 {
        var hasher = std.hash.Wyhash.init(0x6f62736572766572);
        hasher.update(std.mem.asBytes(&self.semantic_digest));
        hasher.update(std.mem.asBytes(&self.guest_frontier_digest));
        hasher.update(std.mem.asBytes(&self.frame_digest));
        hasher.update(std.mem.asBytes(&self.wait_digest));
        hasher.update(std.mem.asBytes(&self.pm4_digest));
        hasher.update(std.mem.asBytes(&self.event_digest));
        return hasher.final();
    }
};

pub const Comparison = struct {
    outcome: Outcome = .invalid,
    reason: []const u8 = "invalid",
    semantic_fingerprint_off: u64 = 0,
    semantic_fingerprint_on: u64 = 0,

    pub fn equivalent(self: Comparison) bool {
        return self.outcome == .equivalent;
    }
};

pub fn compare(observer_off: Sample, observer_on: Sample) Comparison {
    if (!observer_off.valid() or !observer_on.valid() or
        observer_off.mode != .off or observer_on.mode != .on)
    {
        return .{ .outcome = .invalid, .reason = "invalid sample or mode" };
    }
    if (observer_off.identity_fingerprint != observer_on.identity_fingerprint or
        observer_off.profile_fingerprint != observer_on.profile_fingerprint or
        observer_off.input_digest != observer_on.input_digest)
    {
        return .{ .outcome = .incomparable, .reason = "run identity differs" };
    }
    if (!observer_off.observerIntact() or !observer_on.observerIntact()) {
        return .{ .outcome = .incomparable, .reason = "evidence stream damaged" };
    }

    const off_fingerprint = observer_off.semanticFingerprint();
    const on_fingerprint = observer_on.semanticFingerprint();
    return .{
        .outcome = if (off_fingerprint == on_fingerprint)
            .equivalent
        else
            .observer_sensitive,
        .reason = if (off_fingerprint == on_fingerprint)
            "semantic digests match"
        else
            "semantic digests differ",
        .semantic_fingerprint_off = off_fingerprint,
        .semantic_fingerprint_on = on_fingerprint,
    };
}

test "paired observation accepts equal sealed semantics" {
    const off = Sample{
        .run_id = 1,
        .identity_fingerprint = 2,
        .profile_fingerprint = 3,
        .input_digest = 4,
        .semantic_digest = 5,
        .guest_frontier_digest = 6,
        .frame_digest = 7,
        .wait_digest = 8,
        .pm4_digest = 9,
        .event_digest = 10,
        .sealed = true,
    };
    var on = off;
    on.mode = .on;
    on.observer_config_digest = 11;
    const result = compare(off, on);
    try std.testing.expectEqual(Outcome.equivalent, result.outcome);
    try std.testing.expect(result.equivalent());
}

test "paired observation identifies semantic observer sensitivity" {
    const off = Sample{
        .run_id = 1,
        .identity_fingerprint = 2,
        .profile_fingerprint = 3,
        .input_digest = 4,
        .semantic_digest = 5,
        .guest_frontier_digest = 6,
        .frame_digest = 7,
        .sealed = true,
    };
    var on = off;
    on.mode = .on;
    on.frame_digest = 99;
    const result = compare(off, on);
    try std.testing.expectEqual(Outcome.observer_sensitive, result.outcome);
}

test "paired observation rejects damaged evidence" {
    const off = Sample{
        .run_id = 1,
        .identity_fingerprint = 2,
        .profile_fingerprint = 3,
        .input_digest = 4,
        .semantic_digest = 5,
        .sealed = true,
        .drops = 1,
    };
    var on = off;
    on.mode = .on;
    on.drops = 0;
    const result = compare(off, on);
    try std.testing.expectEqual(Outcome.incomparable, result.outcome);
}

test "paired observation never compares different run identities" {
    const off = Sample{
        .run_id = 1,
        .identity_fingerprint = 2,
        .profile_fingerprint = 3,
        .input_digest = 4,
        .semantic_digest = 5,
        .sealed = true,
    };
    var on = off;
    on.mode = .on;
    on.input_digest = 8;
    const result = compare(off, on);
    try std.testing.expectEqual(Outcome.incomparable, result.outcome);
}
