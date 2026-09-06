//! Runtime provenance for the last seam between the graphics backend and the
//! Cocoa window.
//!
//! A native presenter being alive is not the same fact as a guest frame being
//! alive.  In particular, Rosette may clear the surface diagnostically while a
//! Xenia source is still absent, and a host-side Vulkan request may exist
//! without a drawable ever completing.  This ledger keeps those cases
//! separate, so liveness and frame-custody decisions cannot promote a healthy
//! sink into guest output.

const std = @import("std");

pub const Snapshot = struct {
    step: u64 = 0,
    native_presenter_ready: bool = false,
    guest_source_available: bool = false,
    host_source_available: bool = false,
    guest_frames_presented: u64 = 0,
    host_frames_presented: u64 = 0,
    diagnostic_frames_presented: u64 = 0,
    guest_swap_observed: bool = false,
    presenter_paint_crossed: bool = false,
    presenter_paint_last_step: u64 = 0,
};

pub const Verdict = enum(u8) {
    no_source,
    diagnostic_only,
    guest_source_waiting,
    host_source_waiting,
    host_pixels_presented,
    guest_pixels_presented,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .no_source => "no-source",
            .diagnostic_only => "diagnostic-only",
            .guest_source_waiting => "guest-source-waiting",
            .host_source_waiting => "host-source-waiting",
            .host_pixels_presented => "host-pixels-presented",
            .guest_pixels_presented => "guest-pixels-presented",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .no_source => "no guest or host frame source has been discovered",
            .diagnostic_only => "the Cocoa sink is alive, but only Rosette diagnostic paints completed; they are not guest output",
            .guest_source_waiting => "a guest frame source exists, but no completed guest frame has reached the native presenter",
            .host_source_waiting => "a Xenia/native presentation request exists, but no completed host frame has reached the native presenter",
            .host_pixels_presented => "a host/Xenia frame completed, but it is not counted as guest-title output",
            .guest_pixels_presented => "guest-produced pixels completed the native presentation path",
        };
    }
};

pub const Missing = enum(u8) {
    none,
    native_presenter,
    guest_source,
    guest_frame_refresh,
    host_frame_completion,

    pub fn label(self: Missing) []const u8 {
        return switch (self) {
            .none => "none",
            .native_presenter => "native-presenter",
            .guest_source => "guest-source",
            .guest_frame_refresh => "guest-frame-refresh",
            .host_frame_completion => "host-frame-completion",
        };
    }
};

/// The only frame count that may satisfy a guest-output boundary.  Host
/// frames are deliberately not an input even when they were rendered by the
/// emulator: they prove that the sink can display pixels, not that the title
/// supplied the pixels Rosette promised to protect.
pub fn guestFrameCount(native_guest_frames: u64, window_guest_frames: u64) u64 {
    return native_guest_frames +| window_guest_frames;
}

pub fn classify(snapshot: Snapshot) Verdict {
    if (snapshot.guest_frames_presented != 0) return .guest_pixels_presented;
    if (snapshot.host_frames_presented != 0) return .host_pixels_presented;
    if (snapshot.guest_source_available) return .guest_source_waiting;
    if (snapshot.host_source_available) return .host_source_waiting;
    if (snapshot.diagnostic_frames_presented != 0) return .diagnostic_only;
    return .no_source;
}

/// Diagnostic paints are not a heartbeat promise for guest output.  A real
/// source, a completed real frame, or a real presentation request is enough to
/// make presenter silence meaningful; diagnostic-only activity is not.
pub fn paintLivenessEligible(snapshot: Snapshot) bool {
    return snapshot.guest_source_available or
        snapshot.host_source_available or
        snapshot.guest_frames_presented != 0 or
        snapshot.host_frames_presented != 0;
}

pub fn missing(snapshot: Snapshot) Missing {
    if (!snapshot.native_presenter_ready) return .native_presenter;
    if (snapshot.guest_source_available and snapshot.guest_frames_presented == 0)
        return .guest_frame_refresh;
    if (snapshot.host_source_available and snapshot.host_frames_presented == 0)
        return .host_frame_completion;
    if (!snapshot.guest_source_available and !snapshot.host_source_available and
        snapshot.guest_frames_presented == 0 and snapshot.host_frames_presented == 0)
        return .guest_source;
    return .none;
}

pub const Ledger = struct {
    observations: u64 = 0,
    transitions: u64 = 0,
    last: Snapshot = .{},
    last_verdict: Verdict = .no_source,
    first_source_step: u64 = 0,
    first_guest_frame_step: u64 = 0,
    first_host_frame_step: u64 = 0,

    /// Merge a cumulative snapshot.  Presenter ledgers are sampled from more
    /// than one owner, and an older owner can briefly report a lower counter;
    /// preserving the maximum keeps a report from regressing merely because a
    /// checkpoint observed the sources in a different order.
    pub fn observe(self: *Ledger, snapshot: Snapshot) Verdict {
        var normalized = snapshot;
        normalized.guest_frames_presented = @max(normalized.guest_frames_presented, self.last.guest_frames_presented);
        normalized.host_frames_presented = @max(normalized.host_frames_presented, self.last.host_frames_presented);
        normalized.diagnostic_frames_presented = @max(normalized.diagnostic_frames_presented, self.last.diagnostic_frames_presented);

        const verdict = classify(normalized);
        if (self.observations != 0 and verdict != self.last_verdict) self.transitions +|= 1;
        if (self.first_source_step == 0 and
            (normalized.guest_source_available or normalized.host_source_available or
                normalized.guest_frames_presented != 0 or normalized.host_frames_presented != 0))
        {
            self.first_source_step = normalized.step;
        }
        if (self.first_guest_frame_step == 0 and normalized.guest_frames_presented != 0)
            self.first_guest_frame_step = normalized.step;
        if (self.first_host_frame_step == 0 and normalized.host_frames_presented != 0)
            self.first_host_frame_step = normalized.step;
        self.observations +|= 1;
        self.last = normalized;
        self.last_verdict = verdict;
        return verdict;
    }

    pub fn current(self: *const Ledger) Verdict {
        return self.last_verdict;
    }

    pub fn livenessEligible(self: *const Ledger) bool {
        return paintLivenessEligible(self.last);
    }

    pub fn missingBoundary(self: *const Ledger) Missing {
        return missing(self.last);
    }

    /// Stable across checkpoints that only advance the instruction counter.
    /// This is used to collapse unchanged provenance reports without hiding a
    /// source transition or a newly completed frame.
    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        const add = struct {
            fn value(hash_in: u64, value_in: u64) u64 {
                var result = hash_in;
                result ^= value_in;
                result *%= 0x100_0000_01b3;
                return result;
            }
        }.value;
        hash = add(hash, @intFromEnum(self.last_verdict));
        hash = add(hash, @intFromEnum(self.missingBoundary()));
        hash = add(hash, @intFromBool(self.last.native_presenter_ready));
        hash = add(hash, @intFromBool(self.last.guest_source_available));
        hash = add(hash, @intFromBool(self.last.host_source_available));
        hash = add(hash, @intFromBool(self.last.guest_swap_observed));
        hash = add(hash, @intFromBool(self.last.presenter_paint_crossed));
        hash = add(hash, self.last.guest_frames_presented);
        hash = add(hash, self.last.host_frames_presented);
        hash = add(hash, self.last.diagnostic_frames_presented);
        return hash;
    }
};

test "host frames never satisfy guest presentation" {
    try std.testing.expectEqual(@as(u64, 0), guestFrameCount(0, 0));
    try std.testing.expectEqual(@as(u64, 3), guestFrameCount(2, 1));
    const snapshot = Snapshot{
        .native_presenter_ready = true,
        .host_frames_presented = 5,
        .diagnostic_frames_presented = 2,
    };
    try std.testing.expectEqual(Verdict.host_pixels_presented, classify(snapshot));
    try std.testing.expectEqual(@as(u64, 0), guestFrameCount(0, 0));
    try std.testing.expect(paintLivenessEligible(snapshot));
}

test "diagnostic-only paint is not presenter liveness evidence" {
    const snapshot = Snapshot{
        .native_presenter_ready = true,
        .diagnostic_frames_presented = 5,
        .presenter_paint_crossed = true,
    };
    try std.testing.expectEqual(Verdict.diagnostic_only, classify(snapshot));
    try std.testing.expect(!paintLivenessEligible(snapshot));
    try std.testing.expectEqual(Missing.guest_source, missing(snapshot));

    var ledger = Ledger{};
    _ = ledger.observe(snapshot);
    try std.testing.expectEqual(Verdict.diagnostic_only, ledger.current());
    try std.testing.expect(!ledger.livenessEligible());
    try std.testing.expectEqual(@as(u64, 0), ledger.transitions);
}

test "guest source transition is retained without using step in fingerprint" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .step = 10, .native_presenter_ready = true, .diagnostic_frames_presented = 1 });
    const first = ledger.fingerprint();
    _ = ledger.observe(.{ .step = 20, .native_presenter_ready = true, .guest_source_available = true, .diagnostic_frames_presented = 1 });
    try std.testing.expectEqual(Verdict.guest_source_waiting, ledger.current());
    try std.testing.expectEqual(@as(u64, 1), ledger.transitions);
    try std.testing.expect(first != ledger.fingerprint());
    try std.testing.expectEqual(@as(u64, 20), ledger.first_source_step);
}
