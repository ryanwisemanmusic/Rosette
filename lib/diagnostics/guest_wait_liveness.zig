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
const wait_policy = @import("xenia_wait_handshake_policy");

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
    timeout: wait_policy.TimeoutEvidence = .{},
};

/// A wait entry observed before its completion record exists.
///
/// This is intentionally separate from `WaitObservation`: an entered wait is
/// not a completed wait, and must not be counted as a signal, timeout, or
/// proof of a deadlock. Retaining the entry gives the next diagnostic
/// checkpoint enough identity to name the exact guest thread and continuation
/// that stopped making progress.
pub const WaitEntry = struct {
    handle: u32 = 0,
    guest_object: u32 = 0,
    object_type: u32 = 0,
    wait_reason: u32 = 0,
    wait_mode: u32 = 0,
    alertable: bool = false,
    timeout_ms: i64 = 0,
    thread_id: u32 = 0,
    pc: u64 = 0,
    pc_domain: wait_policy.PcDomain = .unknown,
    pc_quality: wait_policy.PcQuality = .unavailable,
    lr: u64 = 0,
    main_thread: bool = false,
    bootstrap_thread: bool = false,
    handle_valid: bool = false,
    entered_step: u64 = 0,

    /// Classify the dependency without claiming that it is already a deadlock.
    /// A thread-object wait from the guest main/bootstrap thread is the exact
    /// boundary at which graphics is not yet reachable; an open entry still
    /// needs a missing completion, not a fabricated signal.
    pub fn classLabel(self: WaitEntry) []const u8 {
        if (self.object_type == 12 and self.main_thread and self.bootstrap_thread)
            return "bootstrap-thread-dependency";
        if (self.timeout_ms < 0) return "indefinite-guest-wait";
        return "guest-wait";
    }

    pub fn pcEvidence(self: WaitEntry) wait_policy.PcEvidence {
        return .{
            .address = self.pc,
            .domain = self.pc_domain,
            .quality = self.pc_quality,
        };
    }
};

pub const minimum_sample: u64 = 64;
pub const dominant_ratio_percent: u64 = 95;

pub const Verdict = enum {
    insufficient_sample,
    timing_unobserved,
    bounded_poll,
    consuming_signals,
    ready_on_entry,
    mixed_outcomes,
    signal_never_arrives,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient_sample => "insufficient_sample",
            .timing_unobserved => "TIMING_UNOBSERVED",
            .bounded_poll => "bounded_poll",
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
            .bounded_poll => "explicit finite manual-reset timeout results were observed. They are producer-side polling evidence, not proof of an indefinitely parked waiter and they do not authorize a synthetic signal",
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
    timeout_class: wait_policy.TimeoutClass = .none,
    timeout_ms: i64 = 0,
    bounded_poll_timeouts: u64 = 0,
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

    pub fn policyTimingSamples(self: Object) u64 {
        return self.ready_on_entry +| self.blocked_signalled +|
            self.actionableTimedOut();
    }

    pub fn actionableTimedOut(self: Object) u64 {
        if (self.timeout_class == .bounded_poll and
            self.bounded_poll_timeouts == self.timed_out)
        {
            return 0;
        }
        return self.timed_out;
    }

    pub fn verdict(self: Object) Verdict {
        if (self.waits < minimum_sample) return .insufficient_sample;
        if (self.timeout_class == .bounded_poll and
            self.bounded_poll_timeouts == self.timed_out and
            self.timed_out != 0)
            return .bounded_poll;
        const samples = self.timingSamples();
        if (samples < minimum_sample) return .timing_unobserved;
        const policy_samples = self.policyTimingSamples();
        if (policy_samples != 0 and
            self.actionableTimedOut() * 100 / policy_samples >= dominant_ratio_percent)
            return .signal_never_arrives;
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
pub const max_open_waits = 16;

pub const Ledger = struct {
    objects: [max_objects]Object = [_]Object{.{}} ** max_objects,
    count: usize = 0,
    open_waits: [max_open_waits]WaitEntry = [_]WaitEntry{.{}} ** max_open_waits,
    open_wait_count: usize = 0,
    wait_entries: u64 = 0,
    wait_entries_completed: u64 = 0,
    ambiguous_completions: u64 = 0,
    wait_entries_dropped: u64 = 0,
    untracked_waits: u64 = 0,
    unattributed_waits: u64 = 0,
    total_waits: u64 = 0,
    total_signalled: u64 = 0,
    total_timed_out: u64 = 0,
    total_bounded_poll_timeouts: u64 = 0,
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

    fn matches(entry: WaitEntry, identity: u32) bool {
        return identity != 0 and
            (entry.handle == identity or entry.guest_object == identity);
    }

    /// Record an entered wait without pretending that it has completed.
    pub fn observeWaitEntry(self: *Ledger, entry: WaitEntry) void {
        self.wait_entries +|= 1;
        for (self.open_waits[0..self.open_wait_count]) |*pending| {
            const same_handle = entry.handle != 0 and pending.handle == entry.handle;
            const fills_missing_handle = entry.guest_object != 0 and
                pending.guest_object == entry.guest_object and
                (entry.handle == 0 or pending.handle == 0);
            if ((same_handle or fills_missing_handle) and pending.thread_id == entry.thread_id) {
                pending.* = entry;
                return;
            }
        }
        if (self.open_wait_count == max_open_waits) {
            self.wait_entries_dropped +|= 1;
            return;
        }
        self.open_waits[self.open_wait_count] = entry;
        self.open_wait_count += 1;
    }

    /// Add identity/state learned from the emulator's follow-up wait detail.
    pub fn observeWaitDetail(
        self: *Ledger,
        handle: u32,
        guest_object: u32,
        handle_valid: bool,
    ) void {
        for (self.open_waits[0..self.open_wait_count]) |*pending| {
            if (!matches(pending.*, handle) and !matches(pending.*, guest_object)) continue;
            if (pending.handle == 0) pending.handle = handle;
            if (pending.guest_object == 0) pending.guest_object = guest_object;
            pending.handle_valid = handle_valid;
            return;
        }
    }

    /// Attach the wait reason emitted on the emulator's companion diagnostic
    /// line to the already-retained entry. It is contextual evidence only: a
    /// reason code cannot turn an open wait into a completed wait.
    pub fn observeWaitContext(self: *Ledger, handle: u32, wait_reason: u32) void {
        for (self.open_waits[0..self.open_wait_count]) |*pending| {
            if (!matches(pending.*, handle)) continue;
            pending.wait_reason = wait_reason;
            return;
        }
    }

    /// Remove a pending entry only when a matching completion was observed.
    /// An unmatched completion is deliberately ignored: it cannot prove that
    /// this particular open wait returned.
    pub fn observeWaitCompletion(self: *Ledger, handle: u32) void {
        self.observeWaitCompletionForThread(handle, 0);
    }

    /// Shared event handles can have multiple waiters. A result identifies
    /// exactly one thread; an anonymous result is usable only when unique.
    pub fn observeWaitCompletionForThread(self: *Ledger, handle: u32, thread_id: u32) void {
        if (handle == 0) return;
        var matched: ?usize = null;
        for (self.open_waits[0..self.open_wait_count], 0..) |pending, index| {
            if (!matches(pending, handle)) continue;
            if (thread_id != 0 and pending.thread_id != thread_id) continue;
            if (matched != null) {
                self.ambiguous_completions +|= 1;
                return;
            }
            matched = index;
        }
        const index = matched orelse return;
        self.open_waits[index] = self.open_waits[self.open_wait_count - 1];
        self.open_wait_count -= 1;
        self.wait_entries_completed +|= 1;
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
            .timed_out => {
                object.timed_out +|= 1;
                const timeout_class = wait_policy.classifyTimeout(observation.timeout);
                if (object.timeout_class == .none or object.timeout_class == .unknown) {
                    object.timeout_class = timeout_class;
                    if (observation.timeout.timeout_known)
                        object.timeout_ms = observation.timeout.timeout_ms;
                } else if (object.timeout_class != timeout_class) {
                    object.timeout_class = .mixed;
                }
                if (timeout_class == .bounded_poll) {
                    object.bounded_poll_timeouts +|= 1;
                    self.total_bounded_poll_timeouts +|= 1;
                }
            },
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

    pub fn aggregatePolicyTimingSamples(self: *const Ledger) u64 {
        return self.total_ready_on_entry +| self.total_blocked_signalled +|
            (self.total_timed_out -| self.total_bounded_poll_timeouts);
    }

    pub fn aggregateReadyPercent(self: *const Ledger) u64 {
        const samples = self.aggregateTimingSamples();
        if (samples == 0) return 0;
        return self.total_ready_on_entry * 100 / samples;
    }

    pub fn aggregateVerdict(self: *const Ledger) Verdict {
        if (self.total_timed_out != 0 and
            self.total_bounded_poll_timeouts == self.total_timed_out and
            self.total_waits >= minimum_sample)
            return .bounded_poll;
        const samples = self.aggregatePolicyTimingSamples();
        // A sufficiently sampled timeout majority is stronger than any
        // successful handoff elsewhere in the run: it identifies a producer
        // that never arrives. Keep that defect visible when the aggregate is
        // mature enough to support the ratio.
        if (samples >= minimum_sample and
            (self.total_timed_out -| self.total_bounded_poll_timeouts) * 100 / samples >= dominant_ratio_percent)
            return .signal_never_arrives;
        // One or more observed blocked-to-signalled returns is direct evidence
        // that a guest waiter consumed a release. Do not erase that evidence
        // merely because this run has not accumulated the aggregate's larger
        // statistical sample yet. The per-object rows still retain the exact
        // objects and unknown timing counts.
        if (self.total_blocked_signalled != 0) return .consuming_signals;
        if (self.total_waits < minimum_sample) return .insufficient_sample;
        if (samples < minimum_sample) return .timing_unobserved;
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
        // `total_waits` counts waits that *returned*: the ledger learns a
        // wait's outcome from its result. A wait that entered and never came
        // back contributes nothing to it, so a run whose main thread has been
        // parked since bootstrap read "no guest wait has been observed" beside
        // an open entry four hundred million steps old. Those are opposite
        // findings and the line has to separate them.
        if (self.total_waits == 0) {
            if (self.open_wait_count != 0) {
                return "no guest wait has completed, and at least one is still open. The open-wait rows below carry the waiter and its age; an outcome nothing has returned is not the same as a wait nothing has made";
            }
            return "no guest wait has been observed";
        }
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

// A wait the ledger learns about from its *result* contributes nothing until
// it returns. The 2026-09-03 run printed "no guest wait has been observed"
// beside an open bootstrap wait 400M steps old, which is the opposite finding.
test "an open wait is not the same as no wait" {
    var ledger = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "no guest wait has been observed") != null);

    ledger.observeWaitEntry(.{
        .handle = 0xF8000014,
        .guest_object = 0x3002E018,
    });
    try std.testing.expectEqual(@as(usize, 1), ledger.open_wait_count);
    try std.testing.expectEqual(@as(u64, 0), ledger.total_waits);
    const open = ledger.verdict();
    try std.testing.expect(std.mem.indexOf(u8, open, "has completed") != null);
    try std.testing.expect(std.mem.indexOf(u8, open, "still open") != null);
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

test "direct consumption evidence survives a short aggregate" {
    var ledger = Ledger{};
    observeMany(&ledger, .{ .handle = 0xF8000168, .status = .signalled, .timing = .blocked }, 4);
    try std.testing.expectEqual(Verdict.consuming_signals, ledger.aggregateVerdict());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "block and return") != null);
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

test "explicit bounded poll timeouts do not identify a missing producer" {
    var ledger = Ledger{};
    const timeout: wait_policy.TimeoutEvidence = .{
        .timeout_ms = 32,
        .timeout_known = true,
        .requested_known = true,
        .requested = true,
        .object_kind = .guest_manual_reset_event,
        .event_mode_known = true,
        .manual_reset = true,
    };
    observeMany(&ledger, .{
        .handle = 0xF8000158,
        .status = .timed_out,
        .timing = .blocked,
        .event_mode = .manual_reset,
        .timeout = timeout,
    }, minimum_sample);
    try std.testing.expectEqual(Verdict.bounded_poll, ledger.objects[0].verdict());
    try std.testing.expectEqual(Verdict.bounded_poll, ledger.aggregateVerdict());
    try std.testing.expect(!ledger.objects[0].verdict().isDefect());
    try std.testing.expectEqual(@as(u64, minimum_sample), ledger.total_bounded_poll_timeouts);
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

test "open wait identity is retained until its completion is observed" {
    var ledger = Ledger{};
    ledger.observeWaitEntry(.{
        .handle = 0xF8000014,
        .guest_object = 0x3002E018,
        .object_type = 12,
        .wait_reason = 3,
        .wait_mode = 1,
        .timeout_ms = -1,
        .thread_id = 6,
        .pc = 0x82582A98,
        .lr = 0x82081740,
        .main_thread = true,
        .bootstrap_thread = true,
        .entered_step = 1_200_000_000,
    });
    ledger.observeWaitDetail(0xF8000014, 0x3002E018, true);
    try std.testing.expectEqual(@as(usize, 1), ledger.open_wait_count);
    try std.testing.expectEqual(@as(u64, 1), ledger.wait_entries);
    try std.testing.expect(ledger.open_waits[0].handle_valid);
    try std.testing.expectEqual(@as(i64, -1), ledger.open_waits[0].timeout_ms);
    try std.testing.expectEqual(@as(u32, 6), ledger.open_waits[0].thread_id);
    try std.testing.expectEqual(@as(u32, 3), ledger.open_waits[0].wait_reason);
    try std.testing.expectEqualStrings("bootstrap-thread-dependency", ledger.open_waits[0].classLabel());
    try std.testing.expectEqual(@as(u64, 0x82582A98), ledger.open_waits[0].pc);
    try std.testing.expectEqual(@as(u64, 0x82081740), ledger.open_waits[0].lr);

    ledger.observeWaitCompletion(0xDEADBEEF);
    try std.testing.expectEqual(@as(usize, 1), ledger.open_wait_count);
    ledger.observeWaitCompletion(0xF8000014);
    try std.testing.expectEqual(@as(usize, 0), ledger.open_wait_count);
    try std.testing.expectEqual(@as(u64, 1), ledger.wait_entries_completed);
}

test "repeated wait detail updates the existing open entry" {
    var ledger = Ledger{};
    ledger.observeWaitEntry(.{ .guest_object = 0x3002E018, .entered_step = 10 });
    ledger.observeWaitEntry(.{
        .handle = 0xF8000014,
        .guest_object = 0x3002E018,
        .entered_step = 11,
    });
    try std.testing.expectEqual(@as(usize, 1), ledger.open_wait_count);
    try std.testing.expectEqual(@as(u64, 2), ledger.wait_entries);
    try std.testing.expectEqual(@as(u32, 0xF8000014), ledger.open_waits[0].handle);
    try std.testing.expectEqual(@as(u64, 11), ledger.open_waits[0].entered_step);
}

test "two threads waiting on one handle retain independent dependencies" {
    var ledger = Ledger{};
    ledger.observeWaitEntry(.{ .handle = 0xf8000014, .thread_id = 6, .entered_step = 100 });
    ledger.observeWaitEntry(.{ .handle = 0xf8000014, .thread_id = 12, .entered_step = 200 });
    try std.testing.expectEqual(@as(usize, 2), ledger.open_wait_count);
    ledger.observeWaitCompletion(0xf8000014);
    try std.testing.expectEqual(@as(usize, 2), ledger.open_wait_count);
    try std.testing.expectEqual(@as(u64, 1), ledger.ambiguous_completions);
    ledger.observeWaitCompletionForThread(0xf8000014, 12);
    try std.testing.expectEqual(@as(usize, 1), ledger.open_wait_count);
    try std.testing.expectEqual(@as(u32, 6), ledger.open_waits[0].thread_id);
    try std.testing.expectEqual(@as(u64, 100), ledger.open_waits[0].entered_step);
    ledger.observeWaitCompletionForThread(0xf8000014, 12);
    try std.testing.expectEqual(@as(usize, 1), ledger.open_wait_count);
}
