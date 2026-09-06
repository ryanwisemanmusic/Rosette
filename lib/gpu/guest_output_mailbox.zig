//! Why the emulator's presenter has no guest image to show, in the presenter's
//! own words, joined to whether Rosette's frontier agrees with it.
//!
//! ## The reading this exists for
//!
//! The 2026-09-01 run reached the presenter and stopped there in a way that
//! reads, at a glance, like a presenter defect:
//!
//! ```text
//! no guest output image available yet (reason=mailbox-inactive-no-refresh,
//!   mailbox=-1, frontbuffer=0x0, refresh_attempt_count=0,
//!   refresh_success_count=0)
//! force_clear_only is auto-latched by missing guest output
//! ```
//!
//! Every one of those numbers is a *consequence*. The mailbox is empty because
//! nothing refreshed it; nothing refreshed it because no swap was produced. The
//! presenter is the last subsystem in the chain and therefore the loudest, and
//! a reader arriving at `mailbox=-1` has arrived at the end of the story.
//!
//! ## What makes this more than a restatement
//!
//! Two independent accounts of one fact. The presenter says how many refreshes
//! it attempted and how many succeeded; Rosette separately knows whether a swap
//! was ever entered, encoded and consumed. Put together they answer a question
//! neither can answer alone:
//!
//! * no swap and no refresh attempts — the mailbox is empty for the reason the
//!   chain predicts, and the presenter has nothing to answer for.
//! * a swap Rosette observed and zero refresh attempts — the two accounts
//!   **contradict** each other, and that is a finding: either the swap did not
//!   reach the presenter or one of the two observers is wrong.
//! * refresh attempts with no successes — the producer did reach the presenter
//!   and the handoff failed, which is the first state where the presenter is
//!   genuinely the owner.
//!
//! ## What it never does
//!
//! It never fills the mailbox, never synthesises a refresh, and never promotes
//! a diagnostic clear to a frame. A presenter that draws a magenta clear
//! because it has nothing else is behaving correctly, and the count of those
//! clears is evidence about the producer rather than about the clear.

const std = @import("std");

/// The presenter's own stated reason for having no guest image.
///
/// Parsed rather than inferred: the emulator writes a `reason=` token and the
/// difference between "nothing has refreshed me" and "a refresh failed" is the
/// difference between a producer question and a presenter question.
pub const Reason = enum(u8) {
    /// Nothing has been observed yet.
    unobserved,
    /// The mailbox has never been refreshed. Downstream of the producer.
    mailbox_inactive_no_refresh,
    /// Refreshes were attempted and the mailbox is still empty.
    mailbox_empty_after_refresh,
    /// The presenter named a reason this build does not know. Reported as
    /// itself rather than folded into the nearest known one.
    unrecognised,

    pub fn label(self: Reason) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .mailbox_inactive_no_refresh => "mailbox-inactive-no-refresh",
            .mailbox_empty_after_refresh => "mailbox-empty-after-refresh",
            .unrecognised => "unrecognised",
        };
    }
};

/// What the two accounts say together.
pub const Verdict = enum(u8) {
    /// The presenter has not reported on its guest output at all.
    unobserved,
    /// No swap was produced and the presenter attempted no refresh. The empty
    /// mailbox is exactly what the chain predicts.
    starved_by_producer,
    /// Rosette observed a swap and the presenter attempted no refresh. The two
    /// accounts disagree.
    swap_observed_without_refresh,
    /// Refreshes were attempted and none succeeded.
    refresh_attempted_without_success,
    /// The mailbox has been filled at least once.
    guest_output_delivered,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .starved_by_producer => "starved-by-producer",
            .swap_observed_without_refresh => "SWAP-OBSERVED-WITHOUT-REFRESH",
            .refresh_attempted_without_success => "REFRESH-ATTEMPTED-WITHOUT-SUCCESS",
            .guest_output_delivered => "guest-output-delivered",
        };
    }

    /// Who to ask. The whole point of joining the two accounts is that this
    /// answer is different in each state, and `mailbox=-1` on its own always
    /// points at the presenter.
    pub fn owner(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "-",
            .starved_by_producer => "guest:title (no swap has been produced)",
            .swap_observed_without_refresh => "rosette:observer or xenia:presenter — the two accounts disagree",
            .refresh_attempted_without_success => "xenia:presenter (the producer reached it and the handoff failed)",
            .guest_output_delivered => "-",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .unobserved => "the presenter has said nothing about its guest output, so neither its emptiness nor its contents is available",
            .starved_by_producer => "the mailbox is empty and the presenter has never attempted a refresh, and no swap has been produced for it to attempt one for. This is the state the chain predicts: the empty mailbox, the null front buffer and the clear-only frames are all one consequence of the producer, and none of them is a presenter defect. A clear frame from here is the presenter working",
            .swap_observed_without_refresh => "a swap was observed and the presenter attempted no refresh for it. These are two accounts of one event and they disagree — either the swap never reached the presenter, or one of the two observers is reporting something that did not happen. Settle which before reading either number again",
            .refresh_attempted_without_success => "the presenter was asked for a guest frame and could not produce one. This is the first state in the chain where the presenter is the owner, and the reason it reports is about its own handoff rather than about the producer",
            .guest_output_delivered => "the mailbox has held a guest image, so the producer reached the presenter and the handoff works",
        };
    }

    pub fn isDefect(self: Verdict) bool {
        return self == .swap_observed_without_refresh or self == .refresh_attempted_without_success;
    }
};

/// One reading of the presenter's guest-output state.
pub const Observation = struct {
    reason: Reason = .unobserved,
    /// The presenter's mailbox slot index. Negative means no slot is held.
    mailbox_index: i64 = -1,
    mailbox_acquired: u64 = 0,
    mailbox_ready: u64 = 0,
    mailbox_writable: u64 = 0,
    frontbuffer: u64 = 0,
    refresh_attempts: u64 = 0,
    refresh_successes: u64 = 0,
    step: u64 = 0,
};

pub const Ledger = struct {
    observations: u64 = 0,
    /// Frames the presenter drew as a clear because it had no guest image.
    /// Evidence about the producer, counted here because it is the visible
    /// symptom and a reader arrives with it.
    force_clear_frames: u64 = 0,
    latest: Observation = .{},
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// High-water marks. The presenter restates its counters on a cadence and
    /// a later line can carry a smaller number after a reset; taking the
    /// maximum keeps "has it ever" answerable, which is the question.
    peak_refresh_attempts: u64 = 0,
    peak_refresh_successes: u64 = 0,
    /// The first step at which a mailbox slot was actually held.
    first_mailbox_step: u64 = 0,

    pub fn observe(self: *Ledger, reading: Observation) void {
        if (self.observations == 0) self.first_step = reading.step;
        self.observations +|= 1;
        self.last_step = reading.step;
        self.latest = reading;
        if (reading.refresh_attempts > self.peak_refresh_attempts) {
            self.peak_refresh_attempts = reading.refresh_attempts;
        }
        if (reading.refresh_successes > self.peak_refresh_successes) {
            self.peak_refresh_successes = reading.refresh_successes;
        }
        if (reading.mailbox_index >= 0 and self.first_mailbox_step == 0) {
            self.first_mailbox_step = reading.step;
        }
    }

    pub fn noteForceClear(self: *Ledger) void {
        self.force_clear_frames +|= 1;
    }

    /// Whether the presenter has ever held a guest image.
    pub fn everHeldGuestOutput(self: *const Ledger) bool {
        return self.peak_refresh_successes != 0 or self.first_mailbox_step != 0;
    }

    /// Join the presenter's account to Rosette's own. `swap_observed` is
    /// Rosette's independent reading that the title asked to present.
    pub fn verdict(self: *const Ledger, swap_observed: bool) Verdict {
        if (self.observations == 0) return .unobserved;
        if (self.everHeldGuestOutput()) return .guest_output_delivered;
        if (self.peak_refresh_attempts != 0) return .refresh_attempted_without_success;
        return if (swap_observed) .swap_observed_without_refresh else .starved_by_producer;
    }
};

/// Classify the presenter's `reason=` token.
pub fn reasonOf(text: []const u8) Reason {
    if (std.mem.eql(u8, text, "mailbox-inactive-no-refresh")) return .mailbox_inactive_no_refresh;
    if (std.mem.eql(u8, text, "mailbox-empty-after-refresh")) return .mailbox_empty_after_refresh;
    return .unrecognised;
}

test "an unobserved presenter says nothing about its mailbox" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict(false));
    try std.testing.expectEqual(Verdict.unobserved, ledger.verdict(true));
    try std.testing.expect(!ledger.everHeldGuestOutput());
    try std.testing.expect(!Verdict.unobserved.isDefect());
}

// The 2026-09-01 shape: mailbox=-1, zero attempts, magenta clears, and no swap
// anywhere in the run. Every number is a consequence of the producer, and the
// presenter has nothing to answer for.
test "an empty mailbox with no swap is the producer's, not the presenter's" {
    var ledger = Ledger{};
    ledger.observe(.{
        .reason = .mailbox_inactive_no_refresh,
        .mailbox_index = -1,
        .frontbuffer = 0,
        .refresh_attempts = 0,
        .refresh_successes = 0,
        .step = 617_948_626,
    });
    var clears: usize = 0;
    while (clears < 76) : (clears += 1) ledger.noteForceClear();

    const verdict = ledger.verdict(false);
    try std.testing.expectEqual(Verdict.starved_by_producer, verdict);
    try std.testing.expect(!verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.owner(), "guest:title") != null);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "none of them is a presenter defect") != null);
    try std.testing.expectEqual(@as(u64, 76), ledger.force_clear_frames);
    try std.testing.expectEqual(@as(u64, 617_948_626), ledger.first_step);
}

// The finding the join exists to produce: two accounts of one event that do
// not agree. Neither number is usable until that is settled.
test "a swap Rosette saw and a presenter that never refreshed is a contradiction" {
    var ledger = Ledger{};
    ledger.observe(.{
        .reason = .mailbox_inactive_no_refresh,
        .mailbox_index = -1,
        .refresh_attempts = 0,
        .step = 100,
    });
    const verdict = ledger.verdict(true);
    try std.testing.expectEqual(Verdict.swap_observed_without_refresh, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.owner(), "disagree") != null);
}

// The first state where the presenter genuinely owns the gap.
test "refreshes attempted without success is the presenter's own handoff" {
    var ledger = Ledger{};
    ledger.observe(.{
        .reason = .mailbox_empty_after_refresh,
        .mailbox_index = -1,
        .refresh_attempts = 12,
        .refresh_successes = 0,
        .step = 200,
    });
    const verdict = ledger.verdict(true);
    try std.testing.expectEqual(Verdict.refresh_attempted_without_success, verdict);
    try std.testing.expect(verdict.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, verdict.owner(), "xenia:presenter") != null);
    // A swap is not needed to reach this state: the attempts themselves are
    // the evidence that something asked the presenter for a frame.
    try std.testing.expectEqual(Verdict.refresh_attempted_without_success, ledger.verdict(false));
}

// A success at any point in the run answers the question for good, even if a
// later line reports a smaller counter after a reset.
test "the counters are high-water marks so a later reset cannot erase a success" {
    var ledger = Ledger{};
    ledger.observe(.{ .refresh_attempts = 40, .refresh_successes = 3, .mailbox_index = 1, .step = 100 });
    ledger.observe(.{ .refresh_attempts = 0, .refresh_successes = 0, .mailbox_index = -1, .step = 200 });

    try std.testing.expectEqual(@as(u64, 40), ledger.peak_refresh_attempts);
    try std.testing.expectEqual(@as(u64, 3), ledger.peak_refresh_successes);
    try std.testing.expect(ledger.everHeldGuestOutput());
    try std.testing.expectEqual(Verdict.guest_output_delivered, ledger.verdict(true));
    // The latest reading is still the latest, so a presenter that went blind
    // after working is still legible.
    try std.testing.expectEqual(@as(i64, -1), ledger.latest.mailbox_index);
    try std.testing.expectEqual(@as(u64, 100), ledger.first_mailbox_step);
}

test "a reason the build does not know is reported as itself" {
    try std.testing.expectEqual(Reason.mailbox_inactive_no_refresh, reasonOf("mailbox-inactive-no-refresh"));
    try std.testing.expectEqual(Reason.mailbox_empty_after_refresh, reasonOf("mailbox-empty-after-refresh"));
    try std.testing.expectEqual(Reason.unrecognised, reasonOf("something-new"));
    try std.testing.expectEqual(Reason.unrecognised, reasonOf(""));
    inline for (@typeInfo(Reason).@"enum".fields) |field| {
        const reason: Reason = @enumFromInt(field.value);
        try std.testing.expect(reason.label().len != 0);
    }
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const verdict: Verdict = @enumFromInt(field.value);
        try std.testing.expect(verdict.label().len != 0);
        try std.testing.expect(verdict.owner().len != 0);
        try std.testing.expect(verdict.describe().len != 0);
    }
}
