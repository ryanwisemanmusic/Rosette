//! Stateful Xenia PowerPC graphics-callback transaction evidence.

const std = @import("std");
const contract = @import("xenia_interrupt_callback_contract");

pub const Stage = contract.Stage;
pub const Effect = contract.Effect;
pub const Finding = contract.Finding;
pub const Domain = contract.Domain;

/// How many distinct interrupt source values are tracked before the tail is
/// folded into an "other" bucket. The console raises a small, fixed set; a run
/// that needs more than this has found something worth naming rather than
/// counting.
pub const tracked_sources: usize = 8;

/// One observed interrupt source value and how often the domain raised it.
pub const SourceCount = struct {
    source: u32 = 0,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
};

pub const Ledger = struct {
    domain: Domain = .xenia_powerpc,
    observed_mask: u8 = 0,
    registrations: u64 = 0,
    dispatch_attempts: u64 = 0,
    callback_returns: u64 = 0,
    dispatch_skips: u64 = 0,
    dispatch_deferrals: u64 = 0,
    context_before_samples: u64 = 0,
    context_after_samples: u64 = 0,
    context_changes: u64 = 0,
    payload_samples: u64 = 0,
    payload_changes: u64 = 0,
    payload_appearances: u64 = 0,
    callback_address: u32 = 0,
    user_data: u32 = 0,
    last_dispatch_id: u64 = 0,
    /// Whether a later registration replaced this domain's callback before
    /// anything dispatched it.
    superseded: bool = false,
    superseded_step: u64 = 0,
    successor_callback: u32 = 0,
    last_source: u32 = 0,
    /// Every distinct source value this domain has raised, with counts.
    ///
    /// `last_source` alone cannot answer the question the callback ledger
    /// actually needs: whether the title's handler has ever been asked more
    /// than one question. A handler entered two hundred times with one source
    /// and a handler entered two hundred times across four sources produce the
    /// same `last_source`, the same entry count, and completely different
    /// conclusions when the handler changes nothing.
    sources: [tracked_sources]SourceCount = [_]SourceCount{.{}} ** tracked_sources,
    distinct_sources: usize = 0,
    /// Raises whose source did not fit the table. Non-zero means the reading
    /// below undercounts the diversity rather than describing it.
    unbucketed_sources: u64 = 0,
    last_cpu: u32 = 0,
    last_duration_ms: u64 = 0,
    first_step: u64 = 0,
    /// The first step at which the domain actually attempted a callback.
    /// `first_step` intentionally remains the first transaction stage (which
    /// is normally registration), so consumers that need ordering evidence do
    /// not have to infer dispatch timing from a mixed-stage timestamp.
    first_dispatch_step: u64 = 0,
    /// The first step at which the callback transaction completed. A return
    /// is stronger evidence than a generic "dispatch entered" tracepoint:
    /// the callback was selected, entered, and came back through Xenia's
    /// transaction boundary.
    first_return_step: u64 = 0,
    /// The first step at which this domain registered a non-zero callback.
    /// `first_step` remains the first stage seen, which can otherwise be a
    /// completion on a log-only path with no registration breadcrumb.
    first_registration_step: u64 = 0,
    last_step: u64 = 0,

    /// Record one raise of one source value. O(1) against a fixed table: this
    /// is called from the dispatch path, which is not a place for a scan that
    /// grows with the run.
    fn noteSource(self: *Ledger, source: u32, step: u64) void {
        for (self.sources[0..self.distinct_sources]) |*slot| {
            if (slot.source != source) continue;
            slot.count +|= 1;
            slot.last_step = step;
            return;
        }
        if (self.distinct_sources >= tracked_sources) {
            self.unbucketed_sources +|= 1;
            return;
        }
        self.sources[self.distinct_sources] = .{
            .source = source,
            .count = 1,
            .first_step = step,
            .last_step = step,
        };
        self.distinct_sources += 1;
    }

    /// How many distinct source values the domain has raised. One is the
    /// reading that makes "the handler ran and changed nothing" a statement
    /// about the experiment rather than about the handler.
    pub fn sourceDiversity(self: *const Ledger) usize {
        return self.distinct_sources;
    }

    /// The only source raised, when there is exactly one.
    pub fn soleSource(self: *const Ledger) ?u32 {
        if (self.distinct_sources != 1) return null;
        return self.sources[0].source;
    }

    fn observe(self: *Ledger, stage: Stage, step: u64) void {
        if (self.observed_mask == 0) self.first_step = step;
        self.observed_mask |= contract.bit(stage);
        self.last_step = step;
    }

    pub fn observeRegistration(self: *Ledger, count: u64, callback: u32, user_data: u32, step: u64) void {
        if (count != 0 and self.registrations == 0) {
            self.first_registration_step = step;
        }
        self.registrations = @max(self.registrations, count);
        self.callback_address = callback;
        self.user_data = user_data;
        self.observe(.registered, step);
    }

    pub fn observeDispatch(self: *Ledger, count: u64, source: u32, cpu: u32, step: u64) void {
        if (count != 0 and self.dispatch_attempts == 0) {
            self.first_dispatch_step = step;
        }
        self.dispatch_attempts = @max(self.dispatch_attempts, count);
        self.last_dispatch_id = @max(self.last_dispatch_id, count);
        self.last_source = source;
        self.noteSource(source, step);
        self.last_cpu = cpu;
        self.observe(.dispatch_attempted, step);
    }

    pub fn observeCompletion(
        self: *Ledger,
        id: u64,
        attempts: u64,
        completions: u64,
        callback: u32,
        source: u32,
        cpu: u32,
        duration_ms: u64,
        payload_before: bool,
        payload_after: bool,
        payload_changed: bool,
        step: u64,
    ) void {
        if (attempts != 0 and self.dispatch_attempts == 0) {
            self.first_dispatch_step = step;
        }
        if (completions != 0 and self.callback_returns == 0) {
            self.first_return_step = step;
        }
        self.dispatch_attempts = @max(self.dispatch_attempts, attempts);
        self.callback_returns = @max(self.callback_returns, completions);
        self.last_dispatch_id = @max(self.last_dispatch_id, id);
        self.callback_address = callback;
        self.last_source = source;
        self.noteSource(source, step);
        self.last_cpu = cpu;
        self.last_duration_ms = duration_ms;
        self.payload_samples +|= 1;
        if (payload_changed) self.payload_changes +|= 1;
        if (!payload_before and payload_after) self.payload_appearances +|= 1;
        self.observe(.registered, step);
        self.observe(.dispatch_attempted, step);
        self.observe(.callback_returned, step);
    }

    /// Adopt the callback executor's own entered/returned totals.
    ///
    /// Xenia has two carriers for the same fact and Rosette was reading only
    /// the weaker one. `GPU callback dispatch completed:` is printed for the
    /// first four dispatches and then only under a trace flag; the executor in
    /// `EmulateCPInterruptDPC` restates `entered=`/`returned=` on a fixed
    /// cadence for as long as it keeps running. On 2026-08-31 the first said
    /// four and stopped at step 3 006 534 266, the second said two hundred and
    /// forty and was still speaking at 7 493 776 604, and this ledger — fed
    /// only the first — reported a callback that had "never been entered" for
    /// the remaining four and a half billion steps.
    ///
    /// The totals are adopted as maxima and the first-step witnesses are left
    /// alone. This line is a restatement, not a new transaction: it must not
    /// claim to be the first dispatch when an earlier carrier already saw one,
    /// and it carries no payload sample, so it must not inflate the effect
    /// evidence either.
    pub fn observeExecutorCounters(self: *Ledger, entered: u64, returned: u64, step: u64) void {
        if (entered == 0 and returned == 0) return;
        if (entered != 0) {
            if (self.dispatch_attempts == 0) self.first_dispatch_step = step;
            self.dispatch_attempts = @max(self.dispatch_attempts, entered);
            self.last_dispatch_id = @max(self.last_dispatch_id, entered);
            self.observe(.dispatch_attempted, step);
        }
        if (returned != 0) {
            if (self.callback_returns == 0) self.first_return_step = step;
            self.callback_returns = @max(self.callback_returns, returned);
            self.observe(.callback_returned, step);
        }
    }

    pub fn observeSkip(self: *Ledger) void {
        self.dispatch_skips +|= 1;
    }

    pub fn observeDeferral(self: *Ledger, total: u64) void {
        self.dispatch_deferrals = @max(self.dispatch_deferrals, total);
    }

    pub fn observeContextBefore(self: *Ledger) void {
        self.context_before_samples +|= 1;
    }

    pub fn observeContextAfter(self: *Ledger, changed: bool) void {
        self.context_after_samples +|= 1;
        if (changed) self.context_changes +|= 1;
    }

    pub fn effect(self: *const Ledger) Effect {
        if (self.payload_appearances != 0) return .payload_appeared;
        if (self.payload_changes != 0) return .payload_changed;
        if (self.payload_samples != 0) return .no_sampled_ring_change;
        return .unobserved;
    }

    /// A later registration in this domain replaced the one recorded here.
    ///
    /// Kept as its own fact rather than folded into the callback address:
    /// "the address changed" and "the previous owner stood down before anyone
    /// dispatched it" are different claims, and only the second one retracts
    /// the missing-producer finding.
    pub fn noteSuperseded(self: *Ledger, successor: u32, step: u64) void {
        if (self.superseded) return;
        self.superseded = true;
        self.superseded_step = step;
        self.successor_callback = successor;
    }

    pub fn finding(self: *const Ledger) Finding {
        return contract.findingWithSupersession(self.observed_mask, self.effect(), self.superseded);
    }

    pub fn firstGap(self: *const Ledger) ?Stage {
        return contract.firstGap(self.observed_mask);
    }

    pub fn counterInvariantHolds(self: *const Ledger) bool {
        return self.callback_returns <= self.dispatch_attempts;
    }

    /// A dispatch breadcrumb is not title-callback evidence unless the same
    /// domain recorded a non-zero registration first. Completion lines retain
    /// their own transaction facts, but cannot backfill this ordering witness.
    pub fn registrationPrecedesDispatch(self: *const Ledger) bool {
        return self.registrations != 0 and
            self.dispatch_attempts != 0 and
            (self.observed_mask & contract.bit(.registered)) != 0 and
            (self.observed_mask & contract.bit(.dispatch_attempted)) != 0 and
            self.first_registration_step <= self.first_dispatch_step;
    }

    /// Whether this ledger has an end-to-end title callback transaction.
    ///
    /// A generic `EmulateCPInterruptDPC` tracepoint is not enough: that
    /// boundary can enter Rosette's host callback as well as the title's
    /// callback. Registration ordering, a returned dispatch, and a callback
    /// address in the console title window together are the independent
    /// evidence that the interrupt actually reached the guest.
    pub fn guestTitleRoundTripProven(self: *const Ledger) bool {
        const guest_callback = self.callback_address >= 0x8000_0000 and
            self.callback_address < 0xC000_0000;
        return self.domain == .xenia_powerpc and
            guest_callback and
            self.registrationPrecedesDispatch() and
            self.callback_returns != 0 and
            (self.observed_mask & contract.bit(.callback_returned)) != 0 and
            self.first_dispatch_step <= self.first_return_step and
            self.counterInvariantHolds();
    }
};

test "completion proves the Xenia callback transaction without a ring effect" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0x40001F00, 100);
    ledger.observeCompletion(168, 168, 168, 0x821951F8, 0, 2, 0, false, false, false, 200);
    try std.testing.expectEqual(@as(u64, 100), ledger.first_registration_step);
    try std.testing.expectEqual(@as(u64, 200), ledger.first_dispatch_step);
    try std.testing.expectEqual(@as(u64, 200), ledger.first_return_step);
    try std.testing.expectEqual(Finding.returning_no_sampled_ring_effect, ledger.finding());
    try std.testing.expect(ledger.firstGap() == null);
    try std.testing.expect(ledger.counterInvariantHolds());
}

test "host callback ledger cannot masquerade as a PowerPC callback" {
    var ledger = Ledger{ .domain = .xenia_host };
    ledger.observeRegistration(1, 0xFFFF0010, 0, 100);
    ledger.observeCompletion(1, 1, 1, 0xFFFF0010, 0, 0, 0, false, false, false, 200);

    try std.testing.expectEqual(Domain.xenia_host, ledger.domain);
    try std.testing.expectEqualStrings("xenia:host-gpu-callback", ledger.domain.label());
    try std.testing.expectEqual(Finding.returning_no_sampled_ring_effect, ledger.finding());
    try std.testing.expect(!contract.comparable(ledger.domain, .xenia_powerpc));
}

test "dispatch without return names the callback executor boundary" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0, 100);
    ledger.observeDispatch(1, 0, 2, 110);
    try std.testing.expectEqual(@as(u64, 100), ledger.first_registration_step);
    try std.testing.expectEqual(@as(u64, 110), ledger.first_dispatch_step);
    try std.testing.expectEqual(@as(u64, 0), ledger.first_return_step);
    try std.testing.expectEqual(Stage.callback_returned, ledger.firstGap().?);
    try std.testing.expectEqual(Finding.dispatch_no_return, ledger.finding());
    try std.testing.expect(std.mem.indexOf(u8, ledger.finding().guidance(), "callback executor") != null);
}

test "dispatch without an ordered registration is not a title route" {
    var ledger = Ledger{};
    ledger.observeDispatch(1, 0, 2, 110);
    try std.testing.expect(!ledger.registrationPrecedesDispatch());
    ledger.observeRegistration(1, 0x821951F8, 0, 120);
    try std.testing.expect(!ledger.registrationPrecedesDispatch());

    var ordered = Ledger{};
    ordered.observeRegistration(1, 0x821951F8, 0, 120);
    ordered.observeDispatch(1, 0, 2, 130);
    try std.testing.expect(ordered.registrationPrecedesDispatch());
}

test "a returned guest callback proves the title interrupt route" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0x40001F00, 100);
    ledger.observeCompletion(1, 1, 1, 0x821951F8, 0, 2, 0, false, false, false, 200);
    try std.testing.expect(ledger.guestTitleRoundTripProven());

    var host = Ledger{ .domain = .xenia_host };
    host.observeRegistration(1, 0xFFFF0010, 0, 100);
    host.observeCompletion(1, 1, 1, 0xFFFF0010, 0, 0, 0, false, false, false, 200);
    try std.testing.expect(!host.guestTitleRoundTripProven());
}

test "a title callback transaction may begin at guest step zero" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0x40001F00, 0);
    ledger.observeCompletion(1, 1, 1, 0x821951F8, 0, 2, 0, false, false, false, 0);
    try std.testing.expect(ledger.guestTitleRoundTripProven());
}

test "payload appearance is retained as optional effect evidence" {
    var ledger = Ledger{};
    ledger.observeCompletion(1, 1, 1, 1, 0, 2, 3, false, true, true, 100);
    try std.testing.expectEqual(Effect.payload_appeared, ledger.effect());
    try std.testing.expectEqual(Finding.returning_with_ring_effect, ledger.finding());
}

// The 2026-08-31 reading. Four completion breadcrumbs and then silence, while
// the executor kept restating its own totals for another four and a half
// billion steps. A ledger that read only the breadcrumbs reported a callback
// route that had never been entered, and the completion-route report turned
// that into "an emulator defect and not a title one".
test "the executor's restated totals overtake a throttled breadcrumb" {
    var ledger = Ledger{};
    ledger.observeRegistration(2, 0x8219_51F8, 0x4000_1F00, 2_864_443_826);
    ledger.observeCompletion(4, 4, 4, 0x8219_51F8, 0, 2, 0, false, false, false, 3_006_534_266);
    try std.testing.expectEqual(@as(u64, 4), ledger.dispatch_attempts);

    ledger.observeExecutorCounters(240, 240, 7_493_776_604);
    try std.testing.expectEqual(@as(u64, 240), ledger.dispatch_attempts);
    try std.testing.expectEqual(@as(u64, 240), ledger.callback_returns);
    try std.testing.expectEqual(@as(u64, 7_493_776_604), ledger.last_step);
    // The first-dispatch and first-return witnesses stay with the carrier that
    // actually saw them first; a restatement is not a first sighting.
    try std.testing.expectEqual(@as(u64, 3_006_534_266), ledger.first_dispatch_step);
    try std.testing.expectEqual(@as(u64, 3_006_534_266), ledger.first_return_step);
    // No payload was sampled by this carrier, so the effect evidence is
    // unchanged by adopting its counters.
    try std.testing.expectEqual(@as(u64, 1), ledger.payload_samples);
    try std.testing.expect(ledger.counterInvariantHolds());
    try std.testing.expect(ledger.registrationPrecedesDispatch());
}

test "executor counters alone still need an ordered registration" {
    var ledger = Ledger{};
    ledger.observeExecutorCounters(240, 240, 100);
    try std.testing.expectEqual(@as(u64, 100), ledger.first_dispatch_step);
    try std.testing.expect(!ledger.registrationPrecedesDispatch());
    try std.testing.expectEqual(@as(u64, 0), ledger.registrations);
}

test "a zero restatement changes nothing" {
    var ledger = Ledger{};
    ledger.observeExecutorCounters(0, 0, 500);
    try std.testing.expectEqual(@as(u8, 0), ledger.observed_mask);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_step);
}

// `last_source` cannot answer the question the effect ledger needs: a handler
// entered two hundred times with one source and one entered two hundred times
// across four sources produce the same last value, the same entry count, and
// opposite conclusions when the handler changes nothing.
test "the source histogram separates one question asked often from several" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 200) : (index += 1) {
        ledger.observeDispatch(index + 1, 0, 0, 1000 + index);
    }
    try std.testing.expectEqual(@as(u32, 0), ledger.last_source);
    try std.testing.expectEqual(@as(usize, 1), ledger.sourceDiversity());
    try std.testing.expectEqual(@as(u32, 0), ledger.soleSource().?);
    try std.testing.expectEqual(@as(u64, 200), ledger.sources[0].count);
    try std.testing.expectEqual(@as(u64, 1000), ledger.sources[0].first_step);
    try std.testing.expectEqual(@as(u64, 1199), ledger.sources[0].last_step);

    // One raise of a second source and the reading changes, while
    // `last_source` would have said the same thing either way.
    ledger.observeDispatch(201, 3, 0, 2000);
    try std.testing.expectEqual(@as(usize, 2), ledger.sourceDiversity());
    try std.testing.expect(ledger.soleSource() == null);
    try std.testing.expectEqual(@as(u64, 0), ledger.unbucketed_sources);
}

// The table is fixed so the dispatch path stays O(1). Overflow has to be
// reported, because a run that silently drops sources would understate the
// diversity and license exactly the conclusion the diversity reading exists to
// withhold.
test "a source that does not fit the table is counted rather than dropped" {
    var ledger = Ledger{};
    var source: u32 = 0;
    while (source < tracked_sources) : (source += 1) {
        ledger.observeDispatch(source + 1, source, 0, source);
    }
    try std.testing.expectEqual(tracked_sources, ledger.sourceDiversity());
    try std.testing.expectEqual(@as(u64, 0), ledger.unbucketed_sources);

    ledger.observeDispatch(100, 0xDEAD, 0, 500);
    try std.testing.expectEqual(tracked_sources, ledger.sourceDiversity());
    try std.testing.expectEqual(@as(u64, 1), ledger.unbucketed_sources);
    // A repeat of a source already in the table still lands in it.
    ledger.observeDispatch(101, 0, 0, 600);
    try std.testing.expectEqual(@as(u64, 2), ledger.sources[0].count);
    try std.testing.expectEqual(@as(u64, 1), ledger.unbucketed_sources);
}

// Both entry points feed the histogram. A completion carries a source too, and
// a run whose only carrier is the completion path would otherwise read as
// having raised nothing.
test "a completion's source reaches the histogram as well as a dispatch's" {
    var ledger = Ledger{};
    ledger.observeCompletion(1, 1, 1, 0x821951F8, 2, 0, 0, false, true, true, 700);
    try std.testing.expectEqual(@as(usize, 1), ledger.sourceDiversity());
    try std.testing.expectEqual(@as(u32, 2), ledger.soleSource().?);
    try std.testing.expectEqual(@as(u64, 1), ledger.payload_changes);
}

// The host placeholder's whole life: installed, never dispatched, replaced by
// the title's own registration. Reported as a missing interrupt producer at
// every checkpoint for the rest of the run.
test "a superseded host placeholder stops reading as a missing producer" {
    var ledger = Ledger{ .domain = .xenia_host };
    ledger.observeRegistration(1, 0xFFFF0010, 0, 8_587);
    try std.testing.expectEqual(Finding.registered_no_dispatch, ledger.finding());

    ledger.noteSuperseded(0x821951F8, 25_347);
    try std.testing.expectEqual(Finding.superseded_before_dispatch, ledger.finding());
    try std.testing.expectEqual(@as(u32, 0x821951F8), ledger.successor_callback);
    try std.testing.expectEqual(@as(u64, 25_347), ledger.superseded_step);

    // The first handover is the one that matters; a later repeat must not move
    // the step and lose when the placeholder actually stood down.
    ledger.noteSuperseded(0xDEADBEEF, 99_999);
    try std.testing.expectEqual(@as(u32, 0x821951F8), ledger.successor_callback);
    try std.testing.expectEqual(@as(u64, 25_347), ledger.superseded_step);
}

// Supersession must not launder a real dispatch gap in a domain that did run.
test "supersession does not excuse a callback that was dispatched" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0, 100);
    ledger.observeDispatch(1, 0, 0, 200);
    ledger.noteSuperseded(0x1234, 300);
    try std.testing.expectEqual(Finding.dispatch_no_return, ledger.finding());
}
