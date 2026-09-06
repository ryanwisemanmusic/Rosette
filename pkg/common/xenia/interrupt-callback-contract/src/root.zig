//! Immutable graphics-interrupt callback transaction facts.
//!
//! Xenia's PowerPC callback and Rosette's modelled x86 callback have similar
//! names but live in different execution domains. This contract prevents an
//! observer from comparing their addresses or counters as though they were one
//! transaction, then defines the mandatory stages within either domain.

const std = @import("std");

pub const schema_version: u16 = 1;

pub const Domain = enum(u8) {
    xenia_powerpc,
    rosette_model,
    /// The callback Rosette installs in Xenia to keep the host-side bring-up
    /// path alive. It is observable and useful, but it is not a callback
    /// registered by the title and must never satisfy a PowerPC callback
    /// boundary.
    xenia_host,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .xenia_powerpc => "xenia:powerpc-title-callback",
            .rosette_model => "rosette:x64-model-callback",
            .xenia_host => "xenia:host-gpu-callback",
        };
    }
};

pub fn comparable(left: Domain, right: Domain) bool {
    return left == right;
}

pub const Stage = enum(u8) {
    registered,
    dispatch_attempted,
    callback_returned,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .registered => "callback registered",
            .dispatch_attempted => "dispatch attempted",
            .callback_returned => "callback returned",
        };
    }

    pub fn owner(self: Stage) []const u8 {
        return switch (self) {
            .registered => "graphics-system registration",
            .dispatch_attempted => "interrupt producer",
            .callback_returned => "CPU callback executor",
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;
pub const complete_mask: u8 = (1 << stage_count) - 1;

pub fn bit(stage: Stage) u8 {
    return @as(u8, 1) << @as(u3, @intCast(@intFromEnum(stage)));
}

pub fn firstGap(observed_mask: u8) ?Stage {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        if (observed_mask & bit(stage) == 0) return stage;
    }
    return null;
}

pub const Effect = enum(u8) {
    unobserved,
    no_sampled_ring_change,
    payload_changed,
    payload_appeared,

    pub fn label(self: Effect) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .no_sampled_ring_change => "no_sampled_ring_change",
            .payload_changed => "payload_changed",
            .payload_appeared => "payload_appeared",
        };
    }

    pub fn provesRingEffect(self: Effect) bool {
        return self == .payload_changed or self == .payload_appeared;
    }
};

pub const Finding = enum(u8) {
    unobserved,
    registered_no_dispatch,
    dispatch_no_return,
    returning_no_sampled_ring_effect,
    returning_with_ring_effect,
    /// The registration was replaced by another before anything dispatched it.
    /// Not a gap: a placeholder that did its job and stood down.
    superseded_before_dispatch,

    pub fn label(self: Finding) []const u8 {
        return @tagName(self);
    }

    pub fn guidance(self: Finding) []const u8 {
        return switch (self) {
            .unobserved => "no registration was observed in this callback domain",
            .registered_no_dispatch => "the callback is installed, but no interrupt producer attempted to execute it",
            .superseded_before_dispatch => "the registration was replaced by a later one before any producer dispatched it. A placeholder that stands down when the real owner arrives has done what it was for, and its zero dispatch count is the expected outcome rather than a missing producer",
            .dispatch_no_return => "dispatch began without a matching return observation; inspect the callback executor and the guest callback body",
            .returning_no_sampled_ring_effect => "the callback executor returns successfully. The sampled ring did not change, which is advisory rather than failure because acknowledgement may occur outside that ring window",
            .returning_with_ring_effect => "the callback executor returns and a sampled ring payload changed or appeared during the transaction",
        };
    }
};

pub fn finding(observed_mask: u8, effect: Effect) Finding {
    return findingWithSupersession(observed_mask, effect, false);
}

/// The same judgement, with the knowledge that a later registration replaced
/// this one.
///
/// A domain that installs a placeholder and hands over to the real owner ends
/// the run with `registered=1 attempts=0`, which is indistinguishable from a
/// producer that never ran — and reads as a finding for the rest of the log.
/// On 2026-09-01 the host callback `0xFFFF0010` was installed at step 8 587,
/// replaced by the title's own `0x821951F8` at step 25 347, and reported as
/// `registered_no_dispatch owner=interrupt producer` at every checkpoint after
/// that.
///
/// Supersession only answers the *dispatch* gap. A registration that was
/// dispatched and then replaced is judged on what its dispatches did, because
/// there the effect is real evidence and the handover is not.
pub fn findingWithSupersession(observed_mask: u8, effect: Effect, superseded: bool) Finding {
    if (observed_mask & bit(.registered) == 0) return .unobserved;
    if (observed_mask & bit(.dispatch_attempted) == 0) {
        return if (superseded) .superseded_before_dispatch else .registered_no_dispatch;
    }
    if (observed_mask & bit(.callback_returned) == 0) return .dispatch_no_return;
    return if (effect.provesRingEffect())
        .returning_with_ring_effect
    else
        .returning_no_sampled_ring_effect;
}

pub fn contractIsWellFormed() bool {
    if (schema_version == 0 or stage_count != 3) return false;
    if (comparable(.xenia_powerpc, .rosette_model)) return false;
    if (comparable(.xenia_powerpc, .xenia_host)) return false;
    if (comparable(.xenia_host, .rosette_model)) return false;
    if (!comparable(.xenia_powerpc, .xenia_powerpc)) return false;
    if (!comparable(.xenia_host, .xenia_host)) return false;
    if (firstGap(0) != .registered) return false;
    if (firstGap(complete_mask) != null) return false;
    if (finding(complete_mask, .no_sampled_ring_change) != .returning_no_sampled_ring_effect) return false;
    return true;
}

test "execution domains cannot be reconciled as one callback" {
    try std.testing.expect(!comparable(.xenia_powerpc, .rosette_model));
    try std.testing.expect(!comparable(.xenia_powerpc, .xenia_host));
    try std.testing.expect(!comparable(.xenia_host, .rosette_model));
    try std.testing.expectEqualStrings("xenia:powerpc-title-callback", Domain.xenia_powerpc.label());
    try std.testing.expectEqualStrings("xenia:host-gpu-callback", Domain.xenia_host.label());
}

test "first gap follows registration dispatch and return" {
    try std.testing.expectEqual(Stage.registered, firstGap(0).?);
    try std.testing.expectEqual(Stage.dispatch_attempted, firstGap(bit(.registered)).?);
    try std.testing.expectEqual(Stage.callback_returned, firstGap(bit(.registered) | bit(.dispatch_attempted)).?);
    try std.testing.expect(firstGap(complete_mask) == null);
}

test "no sampled ring mutation does not erase a proven callback return" {
    const result = finding(complete_mask, .no_sampled_ring_change);
    try std.testing.expectEqual(Finding.returning_no_sampled_ring_effect, result);
    try std.testing.expect(std.mem.indexOf(u8, result.guidance(), "advisory") != null);
}

test "contract is well formed" {
    try std.testing.expect(contractIsWellFormed());
}

// A placeholder that stands down when the real owner arrives ends the run with
// `registered=1 attempts=0`, which is exactly the shape of a producer that
// never ran — and was reported as one for five billion steps.
test "a registration replaced before dispatch is not a missing producer" {
    const registered_only = bit(.registered);
    try std.testing.expectEqual(
        Finding.registered_no_dispatch,
        findingWithSupersession(registered_only, .unobserved, false),
    );
    try std.testing.expectEqual(
        Finding.superseded_before_dispatch,
        findingWithSupersession(registered_only, .unobserved, true),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        Finding.superseded_before_dispatch.guidance(),
        "has done what it was for",
    ) != null);

    // Supersession answers the dispatch gap and nothing else: a callback that
    // ran and was then replaced is still judged on what its dispatches did.
    try std.testing.expectEqual(
        Finding.returning_no_sampled_ring_effect,
        findingWithSupersession(complete_mask, .no_sampled_ring_change, true),
    );
    try std.testing.expectEqual(
        Finding.dispatch_no_return,
        findingWithSupersession(registered_only | bit(.dispatch_attempted), .unobserved, true),
    );
    // A domain that never registered says nothing either way.
    try std.testing.expectEqual(Finding.unobserved, findingWithSupersession(0, .unobserved, true));

    // The plain entry point keeps its old answer, so every existing caller is
    // unchanged until it opts in.
    try std.testing.expectEqual(
        Finding.registered_no_dispatch,
        finding(registered_only, .unobserved),
    );
}
