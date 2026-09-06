//! The guest producer's own state machine: which epoch it reached, what
//! carried it there, and what it is waiting for if it stopped.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 run advanced the ring write pointer once, effectively, and
//! then went quiet for about one and a half billion steps. Every existing
//! report could describe the silence and none could say what kind of silence
//! it was. "The producer is quiet" covers a title doing unrelated work, a
//! title waiting for a notification that is not coming, and a title that was
//! paused underneath by the emulator — three different investigations that
//! share one counter.
//!
//! So the producer is modelled as epochs rather than as a quiet period. Each
//! transition is observed, dated, attributed to a thread, and given a source
//! class. A run that stops names the epoch it stopped in and the object it is
//! waiting on inside that epoch, which is a question with an owner.
//!
//! What it never does
//! ------------------
//! It does not advance an epoch because one is overdue, and it does not
//! authorise a write-pointer kick, a fabricated callback or an injected swap
//! packet because the producer is late. An epoch the guest did not reach stays
//! unreached; that is the entire value of the ledger.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const SourceClass = bridge.contract.SourceClass;
pub const Address = bridge.contract.Address;
pub const CodeLocation = bridge.contract.CodeLocation;

/// The producer's lifecycle, in the order the guest must climb it.
pub const Epoch = enum(u8) {
    not_started = 0,
    video_initialized = 1,
    callback_registered = 2,
    ring_initialized = 3,
    payload_published = 4,
    payload_consumed = 5,
    draw_activity = 6,
    swap_requested = 7,
    frame_consumed = 8,

    pub fn label(self: Epoch) []const u8 {
        return switch (self) {
            .not_started => "not started",
            .video_initialized => "video initialized",
            .callback_registered => "callback registered",
            .ring_initialized => "ring initialized",
            .payload_published => "payload published",
            .payload_consumed => "payload consumed",
            .draw_activity => "draw activity",
            .swap_requested => "swap requested",
            .frame_consumed => "frame consumed",
        };
    }

    /// Who has to act for this epoch to be reached.
    pub fn owner(self: Epoch) []const u8 {
        return switch (self) {
            .not_started => "-",
            .video_initialized,
            .callback_registered,
            .ring_initialized,
            .payload_published,
            .swap_requested,
            => "guest:title",
            .payload_consumed, .draw_activity => "emulator:gpu",
            .frame_consumed => "rosette:presenter",
        };
    }

    /// What a reader should do when the producer is sitting here.
    pub fn stalledMeans(self: Epoch) []const u8 {
        return switch (self) {
            .not_started => "the title has not called a video export. The frontier is upstream of graphics entirely: look at what the guest is executing instead",
            .video_initialized => "engines are up and no interrupt callback has been registered. The title has not told the GPU where to notify it, so nothing downstream can wake it",
            .callback_registered => "a callback exists and no ring has been handed over. The title is between initialising the GPU and giving it somewhere to read commands from",
            .ring_initialized => "a ring exists and the title has published nothing into it. This is the boundary between command production and submission, and it is the title's",
            .payload_published => "the title published and the command processor has not consumed. Look at the worker wake and the applied write pointer, not at the title",
            .payload_consumed => "commands were consumed and no draw was issued. The batch was state, not rendering — which is normal for a probe batch and the question is what the title wants before it submits one that draws",
            .draw_activity => "draws were issued and no swap was requested. Either the draws produced nothing worth presenting, or the title is waiting for a completion before it asks to present",
            .swap_requested => "a swap was requested and no frame was consumed. This is the only epoch where the presenter is implicated",
            .frame_consumed => "the producer completed a full cycle. A stall here is between frames rather than inside one",
        };
    }

    /// Whether reaching this epoch is the title's own doing. Used to refuse a
    /// host-sourced transition into an epoch the guest owns.
    pub fn guestOwned(self: Epoch) bool {
        return switch (self) {
            .video_initialized,
            .callback_registered,
            .ring_initialized,
            .payload_published,
            .swap_requested,
            => true,
            .not_started, .payload_consumed, .draw_activity, .frame_consumed => false,
        };
    }
};

pub const epoch_count: usize = @typeInfo(Epoch).@"enum".fields.len;

/// Everything one transition carries. The document's requirement is that a
/// transition is never a bare counter increment, because the next question is
/// always "on which thread, from where, and was that the guest".
pub const Transition = struct {
    epoch: Epoch = .not_started,
    sequence: u64 = 0,
    guest_step: u64 = 0,
    host_monotonic_ns: u64 = 0,
    guest_thread: u64 = 0,
    location: CodeLocation = .{},
    ring_base: Address = .{},
    read_index: u32 = 0,
    write_index: u32 = 0,
    ring_generation: u64 = 0,
    packets: u64 = 0,
    draws: u64 = 0,
    swaps: u64 = 0,
    /// The object the producer is expected to wait on next, when the epoch has
    /// one. Zero means the epoch has no handshake.
    wait_object: u64 = 0,
    expected_notifier: u64 = 0,
    source: SourceClass = .unknown,

    pub fn guestAuthentic(self: Transition) bool {
        return self.source == .guest_authentic;
    }
};

/// Why the producer is where it is.
pub const Verdict = enum(u8) {
    /// No transition has been observed at all.
    unobserved,
    /// The producer reached a new epoch recently.
    advancing,
    /// Quiet, and another progress axis is still moving. The producer has
    /// nothing to do rather than being unable to do it.
    quiet_with_progress,
    /// Quiet, nothing else is advancing, and the epoch it is in has a wait
    /// object with no notifier.
    waiting_on_missing_notifier,
    /// Quiet, nothing else advancing, and no wait object is known. The
    /// producer is not visibly waiting for anything, which is a hole in the
    /// observation rather than a diagnosis.
    quiet_without_a_reason,
    /// The emulator paused the guest. Every wait observed after this is a
    /// consequence, and no producer conclusion may be drawn until the pause
    /// transaction is understood.
    suspended_by_pause,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .advancing => "advancing",
            .quiet_with_progress => "quiet-with-progress",
            .waiting_on_missing_notifier => "WAITING-ON-MISSING-NOTIFIER",
            .quiet_without_a_reason => "QUIET-WITHOUT-A-REASON",
            .suspended_by_pause => "SUSPENDED-BY-PAUSE",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "no producer transition has been observed. The epoch ladder has nothing to say and neither does its silence",
            .advancing => "the producer reached a new epoch inside the observation window. There is no stall to explain",
            .quiet_with_progress => "the producer has not advanced and other progress axes have. It is idle rather than blocked, and promoting this to a cause would send a reader after a thread that has nothing to do",
            .waiting_on_missing_notifier => "the producer is parked on an object inside its current epoch, nothing else is advancing, and no code has ever signalled that object. Find the notifier and confirm it ran at all — this is the first missing transition and it has an owner",
            .quiet_without_a_reason => "the producer stopped, nothing else is advancing, and no wait object has been attributed to it. The missing work is the attribution: until the object is known this is a hole in the observation and not a diagnosis",
            .suspended_by_pause => "the emulator paused guest execution. Every wait and quiet period observed after the pause is a consequence of it, and no producer conclusion is available until the pause transaction is read",
        };
    }

    pub fn isFinding(self: Verdict) bool {
        return self == .waiting_on_missing_notifier or self == .quiet_without_a_reason;
    }

    /// Whether the producer's state may be quoted as a cause at all.
    pub fn promotableToCause(self: Verdict) bool {
        return self == .waiting_on_missing_notifier;
    }
};

/// How long the producer may be quiet before the quiet is worth judging.
/// Sized against the observed run, where the effective advance was at step
/// 3 259 565 717 and the gate ran at 100-million-step checkpoints.
pub const quiet_threshold_steps: u64 = 500_000_000;

pub const max_transitions: usize = 64;

/// A refused transition, kept so the refusal is auditable. A ledger that
/// silently dropped a host-sourced claim on a guest-owned epoch would look
/// identical to one that never received it.
pub const Refusal = struct {
    epoch: Epoch = .not_started,
    source: SourceClass = .unknown,
    guest_step: u64 = 0,
};

pub const Ledger = struct {
    reached: [epoch_count]bool = [_]bool{false} ** epoch_count,
    first_step: [epoch_count]u64 = [_]u64{0} ** epoch_count,
    last_step: [epoch_count]u64 = [_]u64{0} ** epoch_count,
    transitions: [max_transitions]Transition = [_]Transition{.{}} ** max_transitions,
    transition_count: usize = 0,
    /// Transitions past the retention window. Counted so a report can say the
    /// list is bounded rather than complete.
    dropped: u64 = 0,
    sequence: u64 = 0,
    refusals: u64 = 0,
    last_refusal: Refusal = .{},
    /// The newest epoch reached, and when.
    current: Epoch = .not_started,
    current_step: u64 = 0,
    /// Set by the pause ledger. A producer conclusion is not available while
    /// this is true.
    paused: bool = false,
    paused_step: u64 = 0,

    /// Record a transition.
    ///
    /// A host or synthetic source may not move a guest-owned epoch. That is
    /// the rule that keeps a ring kick from writing `payload_published` into
    /// the ledger and making the title look like it submitted.
    pub fn observe(self: *Ledger, transition: Transition) bool {
        if (transition.epoch.guestOwned() and !transition.guestAuthentic()) {
            self.refusals +|= 1;
            self.last_refusal = .{
                .epoch = transition.epoch,
                .source = transition.source,
                .guest_step = transition.guest_step,
            };
            return false;
        }
        const index = @intFromEnum(transition.epoch);
        self.sequence +|= 1;
        var stamped = transition;
        stamped.sequence = self.sequence;
        if (!self.reached[index]) {
            self.reached[index] = true;
            self.first_step[index] = transition.guest_step;
        }
        self.last_step[index] = transition.guest_step;
        if (@intFromEnum(transition.epoch) >= @intFromEnum(self.current)) {
            self.current = transition.epoch;
            self.current_step = transition.guest_step;
        }
        if (self.transition_count < max_transitions) {
            self.transitions[self.transition_count] = stamped;
            self.transition_count += 1;
        } else {
            self.dropped +|= 1;
        }
        return true;
    }

    pub fn notePause(self: *Ledger, step: u64) void {
        self.paused = true;
        self.paused_step = step;
    }

    pub fn noteResume(self: *Ledger) void {
        self.paused = false;
    }

    pub fn has(self: *const Ledger, epoch: Epoch) bool {
        return self.reached[@intFromEnum(epoch)];
    }

    pub fn retained(self: *const Ledger) []const Transition {
        return self.transitions[0..self.transition_count];
    }

    /// How many epochs after ring initialisation the producer has driven. The
    /// acceptance criterion in the audit is at least two.
    pub fn effectiveEpochsAfterRing(self: *const Ledger) usize {
        var total: usize = 0;
        var index: usize = @intFromEnum(Epoch.payload_published);
        while (index < epoch_count) : (index += 1) {
            if (self.reached[index]) total += 1;
        }
        return total;
    }

    pub fn quietSteps(self: *const Ledger, step: u64) u64 {
        if (self.current_step == 0) return 0;
        return step -| self.current_step;
    }

    /// Decide the producer.
    ///
    /// `other_axis_advancing` is the independent progress witness — guest
    /// translation, allocation high-water, anything a spin cannot manufacture.
    /// Every predictor in this codebase is gated on one, because a parked
    /// thread beside a run that keeps moving is an idle worker and the same
    /// thread beside a frozen run is the finding.
    pub fn verdict(
        self: *const Ledger,
        step: u64,
        other_axis_advancing: bool,
        wait_object_has_notifier: bool,
    ) Verdict {
        if (self.paused) return .suspended_by_pause;
        if (self.sequence == 0) return .unobserved;
        if (self.quietSteps(step) < quiet_threshold_steps) return .advancing;
        if (other_axis_advancing) return .quiet_with_progress;
        const object = self.currentWaitObject();
        if (object == 0) return .quiet_without_a_reason;
        if (wait_object_has_notifier) return .quiet_with_progress;
        return .waiting_on_missing_notifier;
    }

    /// The object the newest transition said the producer would wait on.
    pub fn currentWaitObject(self: *const Ledger) u64 {
        var index: usize = self.transition_count;
        while (index > 0) {
            index -= 1;
            if (self.transitions[index].wait_object != 0) return self.transitions[index].wait_object;
        }
        return 0;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = @intFromEnum(self.current);
        hash = hash *% 31 +% self.sequence;
        hash = hash *% 31 +% self.refusals;
        hash = hash *% 31 +% @intFromBool(self.paused);
        return hash;
    }
};

test "a host source may not move a guest-owned epoch" {
    var ledger = Ledger{};
    const forced = Transition{
        .epoch = .payload_published,
        .guest_step = 1000,
        .source = .synthetic,
    };
    try std.testing.expect(!ledger.observe(forced));
    try std.testing.expect(!ledger.has(.payload_published));
    try std.testing.expectEqual(@as(u64, 1), ledger.refusals);
    try std.testing.expectEqual(Epoch.payload_published, ledger.last_refusal.epoch);

    // The emulator's own epochs are not guest-owned and may be recorded from
    // the emulator.
    try std.testing.expect(ledger.observe(.{
        .epoch = .payload_consumed,
        .guest_step = 1001,
        .source = .host_forwarded,
    }));
    try std.testing.expect(ledger.has(.payload_consumed));
}

// The 2026-08-31 shape: one effective advance, then quiet, with a bounded poll
// on an object nothing signals.
test "a quiet producer with an unsignalled wait object is the first missing transition" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .epoch = .video_initialized, .guest_step = 2_863_871_902, .source = .guest_authentic });
    _ = ledger.observe(.{ .epoch = .callback_registered, .guest_step = 2_864_407_852, .source = .guest_authentic });
    _ = ledger.observe(.{ .epoch = .ring_initialized, .guest_step = 2_888_386_539, .source = .guest_authentic });
    _ = ledger.observe(.{
        .epoch = .payload_published,
        .guest_step = 3_259_565_717,
        .source = .guest_authentic,
        .wait_object = 0x4000_4BF4,
        .expected_notifier = 0,
    });

    const step: u64 = 7_500_000_000;
    // While something else is advancing, the producer is idle rather than
    // blocked, and the ledger refuses to promote it.
    try std.testing.expectEqual(Verdict.quiet_with_progress, ledger.verdict(step, true, false));

    const verdict = ledger.verdict(step, false, false);
    try std.testing.expectEqual(Verdict.waiting_on_missing_notifier, verdict);
    try std.testing.expect(verdict.promotableToCause());
    try std.testing.expectEqual(@as(u64, 0x4000_4BF4), ledger.currentWaitObject());
    try std.testing.expectEqual(Epoch.payload_published, ledger.current);
    try std.testing.expect(std.mem.indexOf(u8, Epoch.payload_published.stalledMeans(), "not at the title") != null);
}

test "a pause makes every producer conclusion unavailable" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .epoch = .payload_published, .guest_step = 100, .source = .guest_authentic, .wait_object = 5 });
    ledger.notePause(200);
    const verdict = ledger.verdict(9_000_000_000, false, false);
    try std.testing.expectEqual(Verdict.suspended_by_pause, verdict);
    try std.testing.expect(!verdict.promotableToCause());
    ledger.noteResume();
    try std.testing.expectEqual(Verdict.waiting_on_missing_notifier, ledger.verdict(9_000_000_000, false, false));
}

test "a quiet producer with no attributed object is a hole and not a diagnosis" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .epoch = .payload_published, .guest_step = 100, .source = .guest_authentic });
    const verdict = ledger.verdict(9_000_000_000, false, false);
    try std.testing.expectEqual(Verdict.quiet_without_a_reason, verdict);
    try std.testing.expect(verdict.isFinding());
    // A hole is a finding about the observation and never a cause to act on.
    try std.testing.expect(!verdict.promotableToCause());
}

test "the acceptance criterion counts epochs past ring initialisation" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .epoch = .ring_initialized, .guest_step = 10, .source = .guest_authentic });
    try std.testing.expectEqual(@as(usize, 0), ledger.effectiveEpochsAfterRing());
    _ = ledger.observe(.{ .epoch = .payload_published, .guest_step = 20, .source = .guest_authentic });
    _ = ledger.observe(.{ .epoch = .payload_consumed, .guest_step = 30, .source = .host_forwarded });
    try std.testing.expectEqual(@as(usize, 2), ledger.effectiveEpochsAfterRing());
}

test "a signalled wait object leaves the producer merely idle" {
    var ledger = Ledger{};
    _ = ledger.observe(.{ .epoch = .payload_published, .guest_step = 100, .source = .guest_authentic, .wait_object = 7 });
    try std.testing.expectEqual(
        Verdict.quiet_with_progress,
        ledger.verdict(9_000_000_000, false, true),
    );
}

test "every epoch states an owner and what a stall there means" {
    inline for (@typeInfo(Epoch).@"enum".fields) |field| {
        const epoch: Epoch = @enumFromInt(field.value);
        try std.testing.expect(epoch.label().len != 0);
        try std.testing.expect(epoch.owner().len != 0);
        try std.testing.expect(epoch.stalledMeans().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 9), epoch_count);
}

test "the retained transition list is bounded and says so" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < max_transitions + 8) : (index += 1) {
        _ = ledger.observe(.{ .epoch = .payload_consumed, .guest_step = index, .source = .host_forwarded });
    }
    try std.testing.expectEqual(max_transitions, ledger.retained().len);
    try std.testing.expectEqual(@as(u64, 8), ledger.dropped);
    try std.testing.expectEqual(@as(u64, max_transitions + 8), ledger.sequence);
}
