//! Evidence-backed guest wait liveness.
//!
//! A successful `KeWaitForSingleObject` says that the object was satisfied. It
//! does not say whether it was ready on entry or whether the caller parked and
//! was released. Treating every success as an immediate return made the old
//! ledger manufacture `NEVER_BLOCKS` from status codes that contained no
//! timing evidence. It also treated a signalled manual-reset event as stale,
//! even though remaining signalled is that object's required contract.
//!
//! This ledger keeps result, timing disposition and event mode separate. Old
//! logs remain readable, but their successful waits are explicitly
//! `unknown_timing` and cannot satisfy or condemn the handshake.

const std = @import("std");

pub const WaitStatus = enum {
    signalled,
    timed_out,
    alerted,
    other,

    pub fn fromCode(code: u32) WaitStatus {
        return switch (code) {
            0x0000_0000 => .signalled,
            0x0000_0101 => .alerted,
            0x0000_0102 => .timed_out,
            else => .other,
        };
    }

    pub fn label(self: WaitStatus) []const u8 {
        return @tagName(self);
    }
};

/// How the observer knows the wait completed. This is independent of status.
pub const TimingEvidence = enum {
    /// Legacy result-only line or a sub-millisecond success with no entry-state
    /// observation. No blocking conclusion may be drawn from it.
    unknown,
    /// The object was observed ready before entering the wait.
    ready_on_entry,
    /// Elapsed time or an internal wait slice proves that the caller parked.
    blocked,

    pub fn label(self: TimingEvidence) []const u8 {
        return @tagName(self);
    }
};

pub const EventMode = enum {
    unknown,
    manual_reset,
    auto_reset,

    pub fn label(self: EventMode) []const u8 {
        return @tagName(self);
    }
};

pub const WaitObservation = struct {
    handle: u32 = 0,
    status: WaitStatus,
    timing: TimingEvidence = .unknown,
    event_mode: EventMode = .unknown,
};

pub const minimum_sample: u64 = 64;
pub const dominant_ratio_percent: u64 = 95;

pub const Verdict = enum {
    insufficient_sample,
    timing_unobserved,
    consuming_signals,
    ready_on_entry,
    mixed_outcomes,
    signal_never_arrives,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient_sample => "insufficient_sample",
            .timing_unobserved => "TIMING_UNOBSERVED",
            .consuming_signals => "consuming_signals",
            .ready_on_entry => "ready_on_entry",
            .mixed_outcomes => "mixed_outcomes",
            .signal_never_arrives => "SIGNAL_NEVER_ARRIVES",
        };
    }

    pub fn meaning(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient_sample => "too few waits were observed to classify this handshake",
            .timing_unobserved => "wait results were observed without entry-state or duration evidence. A success status cannot distinguish ready-on-entry from block-and-release, so this run cannot classify the handshake",
            .consuming_signals => "at least one successful wait was observed to block and return, proving that a producer released the waiter",
            .ready_on_entry => "nearly every timed wait found its object ready on entry. This is not a defect by itself: an auto-reset event consumes that signal, while a manual-reset event intentionally remains open until the guest resets it",
            .mixed_outcomes => "timed evidence contains ready, timeout or interrupted outcomes but no observed block-and-release; the handshake is active but signal consumption is not proven",
            .signal_never_arrives => "nearly every timed wait blocked and timed out; inspect the producer that should signal this object",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .signal_never_arrives;
    }

    /// Retained for callers that only need to distinguish an observed failure.
    pub fn healthy(self: Verdict) bool {
        return !self.isDefect();
    }

    pub fn provesBlockAndRelease(self: Verdict) bool {
        return self == .consuming_signals;
    }
};

pub const Object = struct {
    handle: u32 = 0,
    event_mode: EventMode = .unknown,
    event_mode_conflicts: u64 = 0,
    waits: u64 = 0,
    signalled: u64 = 0,
    timed_out: u64 = 0,
    alerted: u64 = 0,
    ready_on_entry: u64 = 0,
    blocked_signalled: u64 = 0,
    unknown_timing: u64 = 0,
    sets_already_signalled: u64 = 0,
    sets: u64 = 0,

    pub fn timingSamples(self: Object) u64 {
        return self.ready_on_entry +| self.blocked_signalled +| self.timed_out;
    }

    pub fn readyRatioPercent(self: Object) u64 {
        const samples = self.timingSamples();
        if (samples == 0) return 0;
        return self.ready_on_entry * 100 / samples;
    }

    pub fn timeoutRatioPercent(self: Object) u64 {
        const samples = self.timingSamples();
        if (samples == 0) return 0;
        return self.timed_out * 100 / samples;
    }

    pub fn verdict(self: Object) Verdict {
        if (self.waits < minimum_sample) return .insufficient_sample;
        const samples = self.timingSamples();
        if (samples < minimum_sample) return .timing_unobserved;
        if (self.timeoutRatioPercent() >= dominant_ratio_percent) return .signal_never_arrives;
        if (self.blocked_signalled != 0) return .consuming_signals;
        if (self.readyRatioPercent() >= dominant_ratio_percent) return .ready_on_entry;
        return .mixed_outcomes;
    }

    pub fn provesSignalConsumption(self: Object) bool {
        // A block-and-release is direct proof. A successful ready-on-entry wait
        // on an auto-reset event also consumes one signal by definition.
        return self.blocked_signalled != 0 or
            (self.event_mode == .auto_reset and self.ready_on_entry != 0);
    }

    fn observeMode(self: *Object, mode: EventMode) void {
        if (mode == .unknown) return;
        if (self.event_mode == .unknown) {
            self.event_mode = mode;
        } else if (self.event_mode != mode) {
            self.event_mode_conflicts +|= 1;
        }
    }
};

pub const max_objects = 24;

pub const Ledger = struct {
    objects: [max_objects]Object = [_]Object{.{}} ** max_objects,
    count: usize = 0,
    untracked_waits: u64 = 0,
    unattributed_waits: u64 = 0,
    total_waits: u64 = 0,
    total_signalled: u64 = 0,
    total_timed_out: u64 = 0,
    total_ready_on_entry: u64 = 0,
    total_blocked_signalled: u64 = 0,
    total_unknown_timing: u64 = 0,

    fn slot(self: *Ledger, handle: u32) ?*Object {
        for (self.objects[0..self.count]) |*object| {
            if (object.handle == handle) return object;
        }
        if (self.count == max_objects) return null;
        const object = &self.objects[self.count];
        object.* = .{ .handle = handle };
        self.count += 1;
        return object;
    }

    pub fn observeWait(self: *Ledger, observation: WaitObservation) void {
        self.total_waits +|= 1;
        switch (observation.status) {
            .signalled => self.total_signalled +|= 1,
            .timed_out => self.total_timed_out +|= 1,
            else => {},
        }
        if (observation.status != .timed_out) switch (observation.timing) {
            .ready_on_entry => self.total_ready_on_entry +|= 1,
            .blocked => if (observation.status == .signalled) {
                self.total_blocked_signalled +|= 1;
            },
            .unknown => self.total_unknown_timing +|= 1,
        };

        if (observation.handle == 0) {
            self.unattributed_waits +|= 1;
            return;
        }
        const object = self.slot(observation.handle) orelse {
            self.untracked_waits +|= 1;
            return;
        };
        object.observeMode(observation.event_mode);
        object.waits +|= 1;
        switch (observation.status) {
            .signalled => object.signalled +|= 1,
            .timed_out => object.timed_out +|= 1,
            .alerted => object.alerted +|= 1,
            .other => {},
        }
        if (observation.status != .timed_out) switch (observation.timing) {
            .ready_on_entry => object.ready_on_entry +|= 1,
            .blocked => if (observation.status == .signalled) {
                object.blocked_signalled +|= 1;
            },
            .unknown => object.unknown_timing +|= 1,
        };
    }

    pub fn observeSet(self: *Ledger, handle: u32, already_signalled: bool) void {
        if (handle == 0) return;
        const object = self.slot(handle) orelse return;
        object.sets +|= 1;
        if (already_signalled) object.sets_already_signalled +|= 1;
    }

    pub fn worst(self: *const Ledger) ?Object {
        var chosen: ?Object = null;
        for (self.objects[0..self.count]) |object| {
            if (!object.verdict().isDefect()) continue;
            if (chosen == null or object.waits > chosen.?.waits) chosen = object;
        }
        return chosen;
    }

    pub fn aggregateTimingSamples(self: *const Ledger) u64 {
        return self.total_ready_on_entry +| self.total_blocked_signalled +| self.total_timed_out;
    }

    pub fn aggregateReadyPercent(self: *const Ledger) u64 {
        const samples = self.aggregateTimingSamples();
        if (samples == 0) return 0;
        return self.total_ready_on_entry * 100 / samples;
    }

    pub fn aggregateVerdict(self: *const Ledger) Verdict {
        if (self.total_waits < minimum_sample) return .insufficient_sample;
        const samples = self.aggregateTimingSamples();
        if (samples < minimum_sample) return .timing_unobserved;
        if (self.total_timed_out * 100 / samples >= dominant_ratio_percent)
            return .signal_never_arrives;
        if (self.total_blocked_signalled != 0) return .consuming_signals;
        if (self.aggregateReadyPercent() >= dominant_ratio_percent) return .ready_on_entry;
        return .mixed_outcomes;
    }

    pub fn provesSignalConsumption(self: *const Ledger) bool {
        for (self.objects[0..self.count]) |object| {
            if (object.provesSignalConsumption()) return true;
        }
        return self.total_blocked_signalled != 0;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.total_waits == 0) return "no guest wait has been observed";
        if (self.worst()) |object| return object.verdict().meaning();
        if (self.aggregateVerdict() == .timing_unobserved)
            return Verdict.timing_unobserved.meaning();
        if (self.count == 0)
            return "waits have timing evidence but no complete object identity; the aggregate is advisory until a self-contained result record supplies guest_obj or handle";
        return self.aggregateVerdict().meaning();
    }
};

fn observeMany(ledger: *Ledger, observation: WaitObservation, count: u64) void {
    var index: u64 = 0;
    while (index < count) : (index += 1) ledger.observeWait(observation);
}

test "status names do not imply timing" {
    try std.testing.expectEqual(WaitStatus.signalled, WaitStatus.fromCode(0));
    try std.testing.expectEqual(WaitStatus.timed_out, WaitStatus.fromCode(0x102));
    var ledger = Ledger{};
    observeMany(&ledger, .{ .handle = 0xF8000168, .status = .signalled }, 512);
    try std.testing.expectEqual(Verdict.timing_unobserved, ledger.aggregateVerdict());
    try std.testing.expectEqual(@as(u64, 512), ledger.total_unknown_timing);
    try std.testing.expect(!ledger.provesSignalConsumption());
}

test "an observed block and release proves a consuming handshake" {
    var ledger = Ledger{};
    observeMany(&ledger, .{ .handle = 0xF8000168, .status = .signalled, .timing = .blocked }, minimum_sample);
    try std.testing.expectEqual(Verdict.consuming_signals, ledger.objects[0].verdict());
    try std.testing.expect(ledger.provesSignalConsumption());
}

test "ready manual reset event is not diagnosed as a spin" {
    var ledger = Ledger{};
    observeMany(&ledger, .{
        .handle = 0xF8000168,
        .status = .signalled,
        .timing = .ready_on_entry,
        .event_mode = .manual_reset,
    }, minimum_sample);
    try std.testing.expectEqual(Verdict.ready_on_entry, ledger.objects[0].verdict());
    try std.testing.expect(!ledger.objects[0].verdict().isDefect());
    try std.testing.expect(!ledger.objects[0].provesSignalConsumption());
}

test "ready auto reset event consumes its signal" {
    var ledger = Ledger{};
    observeMany(&ledger, .{
        .handle = 0xF8000168,
        .status = .signalled,
        .timing = .ready_on_entry,
        .event_mode = .auto_reset,
    }, minimum_sample);
    try std.testing.expectEqual(Verdict.ready_on_entry, ledger.objects[0].verdict());
    try std.testing.expect(ledger.objects[0].provesSignalConsumption());
}

test "timeouts identify a missing producer" {
    var ledger = Ledger{};
    observeMany(&ledger, .{ .handle = 0xF8000200, .status = .timed_out, .timing = .blocked }, 200);
    try std.testing.expectEqual(Verdict.signal_never_arrives, ledger.objects[0].verdict());
    try std.testing.expect(ledger.objects[0].verdict().isDefect());
}

test "identity and capacity failures are explicit" {
    var ledger = Ledger{};
    ledger.observeWait(.{ .status = .signalled });
    try std.testing.expectEqual(@as(u64, 1), ledger.unattributed_waits);
    var handle: u32 = 1;
    while (handle <= max_objects) : (handle += 1) {
        ledger.observeWait(.{ .handle = handle, .status = .signalled });
    }
    ledger.observeWait(.{ .handle = 0xDEAD, .status = .signalled });
    try std.testing.expectEqual(@as(u64, 1), ledger.untracked_waits);
}

test "conflicting event modes are retained as corruption evidence" {
    var ledger = Ledger{};
    ledger.observeWait(.{ .handle = 1, .status = .signalled, .event_mode = .manual_reset });
    ledger.observeWait(.{ .handle = 1, .status = .signalled, .event_mode = .auto_reset });
    try std.testing.expectEqual(EventMode.manual_reset, ledger.objects[0].event_mode);
    try std.testing.expectEqual(@as(u64, 1), ledger.objects[0].event_mode_conflicts);
}
