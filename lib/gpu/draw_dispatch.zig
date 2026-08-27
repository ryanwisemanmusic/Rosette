//! Delivering queued GPU completions, and supplying the front buffer that
//! substitution is blocked on — with provenance kept so neither can ever be
//! mistaken for the title's own behaviour.
//!
//! Two things in the same run are stuck for two different reasons:
//!
//! ```text
//! XENOS COMPLETION EVIDENCE: draw_signals=24 draw_dispatch(attempts/success/failures)=0/0/0
//! XENIA INTERRUPT CALLBACK:  registered=0 callback=0x821951f8
//! SWAP SUBSTITUTION: blocked — no front buffer address and extent are known
//! ```
//!
//! Twenty-four completions queued and **zero delivery attempts**, because the
//! dispatcher holds no callback while the callback's address sits in the line
//! below it. And a substitution ladder that cannot take its lowest rung because
//! nothing knows where a front buffer is.
//!
//! Both are Rosette's to close, and closing them is diagnosis rather than
//! repair. A completion nobody delivers is indistinguishable from a completion
//! nobody generated; delivering one and watching what changes is the only way
//! to tell a consumer missing its signal from a consumer that is not there.
//!
//! ## What keeps this honest
//!
//! Three rules, all enforced here rather than by convention:
//!
//!   1. **Provenance travels with the address.** An address captured at an
//!      intercepted registration is a binding; one parsed from a diagnostic
//!      line is a claim, and this system has already been burned twice by
//!      diagnostic lines that were stale snapshots. They are counted apart and
//!      admitted by different policies.
//!   2. **Nothing Rosette originates is authentic.** `closesAuthenticStage` is
//!      hard-wired false. A run that progressed only because Rosette dispatched
//!      still reads as a run whose title never received its own completion.
//!   3. **A supplied front buffer is Rosette's, permanently.** It carries an
//!      owner tag that no later observation clears, so a substituted frame can
//!      never be counted as guest output.

const std = @import("std");
const contract = @import("xenia_draw_dispatch_contract");
const pm4 = @import("pm4.zig");

pub const Provenance = contract.Provenance;
pub const Outcome = contract.Outcome;
pub const Effect = contract.Effect;
pub const Policy = contract.Policy;
pub const AddressSpace = contract.AddressSpace;

/// A callback address and how much is assumed by entering it.
pub const Callback = struct {
    address: u64 = 0,
    user_data: u64 = 0,
    provenance: Provenance = .none,
    address_space: AddressSpace = .none,
    /// Step at which the strongest provenance was established.
    established_step: u64 = 0,
    /// Times a stronger source replaced a weaker one. A binding arriving after
    /// a claim is the good case and worth seeing.
    upgrades: u32 = 0,
    /// Times two sources named different addresses. Non-zero means the address
    /// is contested and dispatch should be treated with more suspicion, not
    /// less.
    conflicts: u32 = 0,

    pub fn known(self: Callback) bool {
        return self.address != 0 and self.provenance != .none;
    }
};

/// A front buffer Rosette supplied because nothing else could name one.
///
/// Marked at construction and never unmarked. The whole risk of a synthetic
/// surface is that a later reader treats it as the title's, so the tag is part
/// of the value rather than a flag beside it.
pub const SuppliedSurface = struct {
    description: pm4.SwapDescription = .{ .frontbuffer_physical_address = 0, .width = 0, .height = 0 },
    /// Always true for a value of this type. Present so a caller that copies
    /// the description out cannot accidentally drop the fact.
    harness_supplied: bool = true,
    supplied_step: u64 = 0,
    /// Why a surface had to be supplied rather than observed.
    reason: Reason = .frontbuffer_never_named,

    pub const Reason = enum(u8) {
        /// No source ever named a front buffer.
        frontbuffer_never_named,
        /// Sources named front buffers that disagreed.
        frontbuffer_contested,
        /// A front buffer was named and failed plausibility.
        frontbuffer_implausible,

        pub fn label(self: Reason) []const u8 {
            return switch (self) {
                .frontbuffer_never_named => "frontbuffer-never-named",
                .frontbuffer_contested => "frontbuffer-contested",
                .frontbuffer_implausible => "frontbuffer-implausible",
            };
        }
    };
};

/// The console's standard front-buffer geometry.
///
/// Chosen rather than invented: 1280x720 is the mode this title's display path
/// negotiates, and a surface whose extent the command processor would assert on
/// is worse than no surface at all. The address is left to the caller because
/// only the process knows what memory it actually owns — a synthetic surface
/// pointing at memory the guest owns would be a write into the title's heap.
/// The console's guest front-buffer window. Physical memory the video subsystem
/// owns rather than anything on the title's heap: a synthetic surface pointing
/// into memory the guest allocated would make Rosette the writer of the title's
/// own data.
pub const default_frontbuffer_address: u32 = 0x1FC0_0000;
pub const default_width: u32 = 1280;
pub const default_height: u32 = 720;

pub const Attempt = struct {
    outcome: Outcome = .nothing_queued,
    provenance: Provenance = .none,
    effect: Effect = .unmeasured,
    step: u64 = 0,
    queued_before: u64 = 0,
    delivered_count: u64 = 0,
};

pub const Summary = struct {
    policy: Policy = .observe_only,
    callback: Callback = .{},
    attempts: u64 = 0,
    delivered: u64 = 0,
    failures: u64 = 0,
    refused_no_callback: u64 = 0,
    refused_unverified: u64 = 0,
    refused_cross_domain: u64 = 0,
    refused_by_policy: u64 = 0,
    nothing_queued: u64 = 0,
    queued_observed: u64 = 0,
    completions_delivered: u64 = 0,
    /// Attempts whose effect was sampled and found to change nothing.
    inert_deliveries: u64 = 0,
    advancing_deliveries: u64 = 0,
    surface_supplied: bool = false,
    last: Attempt = .{},

    /// The reading a report leads with.
    pub fn finding(self: Summary) Finding {
        if (self.delivered == 0) {
            if (self.refused_cross_domain != 0) return .cross_domain_callback;
            if (self.refused_unverified != 0) return .refused_unverified_address;
            if (self.refused_no_callback != 0) return .no_callback_known;
            if (self.refused_by_policy != 0) return .dispatch_disabled;
            if (self.queued_observed != 0) return .pending_not_serviced;
            return .nothing_to_dispatch;
        }
        if (self.failures != 0) return .dispatch_failed;
        if (self.advancing_deliveries != 0) return .dispatch_advanced_the_run;
        if (self.inert_deliveries != 0) return .consumer_reachable_and_unmoved;
        return .delivered_effect_unmeasured;
    }
};

pub const Finding = enum(u8) {
    nothing_to_dispatch,
    dispatch_disabled,
    no_callback_known,
    refused_unverified_address,
    cross_domain_callback,
    pending_not_serviced,
    delivered_effect_unmeasured,
    consumer_reachable_and_unmoved,
    dispatch_advanced_the_run,
    dispatch_failed,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .nothing_to_dispatch => "nothing_to_dispatch",
            .dispatch_disabled => "dispatch_disabled",
            .no_callback_known => "no_callback_known",
            .refused_unverified_address => "refused_unverified_address",
            .cross_domain_callback => "cross_domain_callback",
            .pending_not_serviced => "pending_not_serviced",
            .delivered_effect_unmeasured => "delivered_effect_unmeasured",
            .consumer_reachable_and_unmoved => "consumer_reachable_and_unmoved",
            .dispatch_advanced_the_run => "dispatch_advanced_the_run",
            .dispatch_failed => "dispatch_failed",
        };
    }

    pub fn guidance(self: Finding) []const u8 {
        return switch (self) {
            .nothing_to_dispatch => "no completion has been queued, so the dispatcher has had nothing to deliver. This is not a refusal and says nothing about whether delivery would work",
            .dispatch_disabled => "completions are queued and policy forbids delivering them. Raise the policy to find out whether delivery is what the run is missing",
            .no_callback_known => "completions are queued and no callback address is known from any source. Until one is, a queued completion and an undeliverable one look identical",
            .refused_unverified_address => "an address is known but only as a claim parsed from a diagnostic line, and the policy will not enter one. Raising the policy transfers control to guest code at a location nothing verified — a deliberate diagnostic act, not a default",
            .cross_domain_callback => "the known callback belongs to Xenia's PowerPC executor while this dispatcher can enter only translated x86 code. No policy escalation can make that address safe; Xenia must dispatch it in its own CPU engine",
            .pending_not_serviced => "completion signals exist, but the dispatcher has made no decision yet. This is pending work rather than nothing_to_dispatch and must be sampled at the callback-domain boundary",
            .delivered_effect_unmeasured => "completions were delivered and their effect has not been sampled yet. Whether it mattered is unknown rather than absent",
            .consumer_reachable_and_unmoved => "completions were delivered, the callback ran, and nothing observable changed. The consumer is reachable and did not act: a missing interrupt is ruled out, and the wait itself is now the question",
            .dispatch_advanced_the_run => "the run advanced after a delivered completion. Delivery was what it was missing — and because Rosette originated it, the title still has not been shown to receive its own",
            .dispatch_failed => "a dispatch was attempted and did not return normally. The address was entered and the guest did not come back, which is stronger evidence against the address than any refusal",
        };
    }
};

pub const max_attempts_retained: usize = 16;

pub const Ledger = struct {
    policy: Policy = .observe_only,
    callback: Callback = .{},
    supplied: ?SuppliedSurface = null,

    attempts: u64 = 0,
    delivered: u64 = 0,
    failures: u64 = 0,
    refused_no_callback: u64 = 0,
    refused_unverified: u64 = 0,
    refused_cross_domain: u64 = 0,
    refused_by_policy: u64 = 0,
    nothing_queued: u64 = 0,
    queued_observed: u64 = 0,
    completions_delivered: u64 = 0,
    inert_deliveries: u64 = 0,
    advancing_deliveries: u64 = 0,

    recent: [max_attempts_retained]Attempt = [_]Attempt{.{}} ** max_attempts_retained,
    recent_count: usize = 0,
    recent_next: usize = 0,
    last: Attempt = .{},

    /// Learn a callback address. A stronger provenance replaces a weaker one; a
    /// weaker one never replaces a stronger, because an intercepted binding
    /// cannot be improved on by a log line.
    pub fn observeCallback(
        self: *Ledger,
        address: u64,
        user_data: u64,
        provenance: Provenance,
        address_space: AddressSpace,
        step: u64,
    ) void {
        if (address == 0 or provenance == .none) return;
        if (self.callback.known() and
            (self.callback.address != address or self.callback.address_space != address_space))
        {
            // Two sources naming different addresses. Counted rather than
            // silently resolved: a contested callback is a reason for more
            // suspicion about dispatch, not less.
            self.callback.conflicts +|= 1;
            // Only a strictly stronger source may move the dispatch target. An
            // equally-strong contradiction must not, or the dispatcher chases
            // whichever line was printed last — which is exactly the
            // stale-snapshot trap that has already cost this project two
            // investigations. Holding the first and flagging the conflict
            // leaves the decision with a human.
            if (@intFromEnum(provenance) <= @intFromEnum(self.callback.provenance)) return;
        }
        if (@intFromEnum(provenance) < @intFromEnum(self.callback.provenance)) return;
        if (self.callback.known() and @intFromEnum(provenance) > @intFromEnum(self.callback.provenance)) {
            self.callback.upgrades +|= 1;
        }
        self.callback.address = address;
        self.callback.user_data = user_data;
        self.callback.provenance = provenance;
        self.callback.address_space = address_space;
        self.callback.established_step = step;
    }

    pub fn observeQueued(self: *Ledger, queued: u64) void {
        self.queued_observed = @max(self.queued_observed, queued);
    }

    /// What a dispatch would do right now, without doing it.
    pub fn wouldDispatch(self: *const Ledger, queued: u64) Outcome {
        return contract.decide(
            self.policy,
            self.callback.provenance,
            self.callback.address_space,
            .translated_x86,
            queued,
        );
    }

    /// Record a dispatch decision and, when it was `delivered`, how many
    /// completions the caller actually handed over.
    ///
    /// The caller performs the call; this records it. Keeping the effect out of
    /// this module is what lets the rule be tested without a guest.
    pub fn recordAttempt(
        self: *Ledger,
        outcome: Outcome,
        queued_before: u64,
        delivered_count: u64,
        step: u64,
    ) void {
        const attempt = Attempt{
            .outcome = outcome,
            .provenance = self.callback.provenance,
            .step = step,
            .queued_before = queued_before,
            .delivered_count = delivered_count,
        };
        switch (outcome) {
            .delivered => {
                self.delivered +|= 1;
                self.completions_delivered +|= delivered_count;
            },
            .failed => self.failures +|= 1,
            .refused_no_callback => self.refused_no_callback +|= 1,
            .refused_unverified => self.refused_unverified +|= 1,
            .refused_cross_domain => self.refused_cross_domain +|= 1,
            .refused_by_policy => self.refused_by_policy +|= 1,
            .nothing_queued => self.nothing_queued +|= 1,
        }
        if (outcome.attempted()) self.attempts +|= 1;
        self.last = attempt;
        self.recent[self.recent_next] = attempt;
        self.recent_next = (self.recent_next + 1) % max_attempts_retained;
        if (self.recent_count < max_attempts_retained) self.recent_count += 1;
    }

    /// Attribute an effect to the most recent delivery.
    ///
    /// Only a delivery can carry an effect: attributing one to a refusal would
    /// credit the dispatcher for something it did not do.
    pub fn noteEffect(self: *Ledger, effect: Effect) void {
        if (self.last.outcome != .delivered) return;
        if (self.last.effect != .unmeasured) return;
        self.last.effect = effect;
        if (effect.advanced()) {
            self.advancing_deliveries +|= 1;
        } else if (effect == .no_observable_change) {
            self.inert_deliveries +|= 1;
        }
        // Mirror into the retained window so the history keeps the effect too.
        const index = (self.recent_next + max_attempts_retained - 1) % max_attempts_retained;
        if (self.recent_count != 0) self.recent[index].effect = effect;
    }

    /// Supply a front buffer because nothing else could name one.
    ///
    /// Refuses an implausible extent: the command processor asserts on one, so
    /// a surface that would crash the consumer is worse than no surface. Also
    /// refuses to replace an existing supply — a second synthetic surface would
    /// make "which one is on screen" a question nobody can answer.
    pub fn supplySurface(
        self: *Ledger,
        physical_address: u32,
        width: u32,
        height: u32,
        reason: SuppliedSurface.Reason,
        step: u64,
    ) bool {
        if (self.supplied != null) return false;
        const description = pm4.SwapDescription{
            .frontbuffer_physical_address = physical_address,
            .width = width,
            .height = height,
        };
        if (!description.plausible()) return false;
        self.supplied = .{
            .description = description,
            .supplied_step = step,
            .reason = reason,
        };
        return true;
    }

    /// The supplied surface, if any. Returned as the tagged type rather than a
    /// bare description so a caller cannot lose the fact that it is Rosette's.
    pub fn suppliedSurface(self: *const Ledger) ?SuppliedSurface {
        return self.supplied;
    }

    pub fn summary(self: *const Ledger) Summary {
        return .{
            .policy = self.policy,
            .callback = self.callback,
            .attempts = self.attempts,
            .delivered = self.delivered,
            .failures = self.failures,
            .refused_no_callback = self.refused_no_callback,
            .refused_unverified = self.refused_unverified,
            .refused_cross_domain = self.refused_cross_domain,
            .refused_by_policy = self.refused_by_policy,
            .nothing_queued = self.nothing_queued,
            .queued_observed = self.queued_observed,
            .completions_delivered = self.completions_delivered,
            .inert_deliveries = self.inert_deliveries,
            .advancing_deliveries = self.advancing_deliveries,
            .surface_supplied = self.supplied != null,
            .last = self.last,
        };
    }
};

test "the live shape: completions queued, address known only as a claim" {
    // 24 queued, callback 0x821951f8 known from a diagnostic line. Under the
    // default policy that is a refusal, and the refusal names the reason.
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0, .emulator_log_claim, .translated_x86, 100);
    ledger.policy = .bound_callbacks_only;

    const outcome = ledger.wouldDispatch(24);
    try std.testing.expectEqual(Outcome.refused_unverified, outcome);
    ledger.recordAttempt(outcome, 24, 0, 100);

    const totals = ledger.summary();
    try std.testing.expectEqual(Finding.refused_unverified_address, totals.finding());
    try std.testing.expectEqual(@as(u64, 0), totals.attempts);
    try std.testing.expect(std.mem.indexOf(u8, totals.finding().guidance(), "nothing verified") != null);
}

test "raising the policy admits the claimed address and records the risk" {
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0x4000_1F00, .emulator_log_claim, .translated_x86, 100);
    ledger.policy = .any_known_address;

    const outcome = ledger.wouldDispatch(24);
    try std.testing.expectEqual(Outcome.delivered, outcome);
    ledger.recordAttempt(outcome, 24, 24, 200);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 1), totals.attempts);
    try std.testing.expectEqual(@as(u64, 24), totals.completions_delivered);
    // The provenance travels with the attempt, so a later reader can see the
    // delivery rested on a parsed line.
    try std.testing.expectEqual(Provenance.emulator_log_claim, totals.last.provenance);
    try std.testing.expectEqual(Finding.delivered_effect_unmeasured, totals.finding());
}

test "a delivery that changes nothing rules out a missing interrupt" {
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0, .intercepted_binding, .translated_x86, 10);
    ledger.policy = .bound_callbacks_only;
    ledger.recordAttempt(ledger.wouldDispatch(24), 24, 24, 100);
    ledger.noteEffect(.no_observable_change);

    const totals = ledger.summary();
    try std.testing.expectEqual(Finding.consumer_reachable_and_unmoved, totals.finding());
    try std.testing.expectEqual(@as(u64, 1), totals.inert_deliveries);
    try std.testing.expect(std.mem.indexOf(u8, totals.finding().guidance(), "ruled out") != null);
}

test "an advancing delivery still does not make the title authentic" {
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0, .intercepted_binding, .translated_x86, 10);
    ledger.policy = .bound_callbacks_only;
    ledger.recordAttempt(ledger.wouldDispatch(24), 24, 24, 100);
    ledger.noteEffect(.present_reached);

    const totals = ledger.summary();
    try std.testing.expectEqual(Finding.dispatch_advanced_the_run, totals.finding());
    try std.testing.expect(std.mem.indexOf(u8, totals.finding().guidance(), "has not been shown to receive its own") != null);
    // The rule that makes the scaffold safe.
    try std.testing.expect(!contract.closesAuthenticStage(.intercepted_binding));
}

test "a stronger provenance upgrades and a weaker one never downgrades" {
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0, .emulator_log_claim, .translated_x86, 10);
    try std.testing.expectEqual(Provenance.emulator_log_claim, ledger.callback.provenance);

    ledger.observeCallback(0x8219_51F8, 0, .intercepted_binding, .translated_x86, 20);
    try std.testing.expectEqual(Provenance.intercepted_binding, ledger.callback.provenance);
    try std.testing.expectEqual(@as(u32, 1), ledger.callback.upgrades);

    // A later log line must not drag a binding back down to a claim.
    ledger.observeCallback(0x8219_51F8, 0, .emulator_log_claim, .translated_x86, 30);
    try std.testing.expectEqual(Provenance.intercepted_binding, ledger.callback.provenance);
    try std.testing.expectEqual(@as(u64, 20), ledger.callback.established_step);
}

test "two sources naming different addresses is counted, not resolved silently" {
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0, .emulator_log_claim, .translated_x86, 10);
    ledger.observeCallback(0x8300_0000, 0, .emulator_log_claim, .translated_x86, 20);
    try std.testing.expectEqual(@as(u32, 1), ledger.callback.conflicts);
    // Equal provenance: the first stands rather than being overwritten by a
    // second claim of the same strength.
    try std.testing.expectEqual(@as(u64, 0x8219_51F8), ledger.callback.address);
}

test "a supplied surface is Rosette's permanently and refuses an implausible extent" {
    var ledger = Ledger{};
    // The command processor asserts on an implausible extent, so a surface that
    // would crash the consumer is worse than no surface at all.
    try std.testing.expect(!ledger.supplySurface(0, default_width, default_height, .frontbuffer_never_named, 1));
    try std.testing.expect(!ledger.supplySurface(0x1FC0_0000, 4, 4, .frontbuffer_never_named, 1));
    try std.testing.expect(ledger.suppliedSurface() == null);

    try std.testing.expect(ledger.supplySurface(0x1FC0_0000, default_width, default_height, .frontbuffer_never_named, 5));
    const surface = ledger.suppliedSurface().?;
    try std.testing.expect(surface.harness_supplied);
    try std.testing.expectEqual(@as(u32, default_width), surface.description.width);
    try std.testing.expectEqual(SuppliedSurface.Reason.frontbuffer_never_named, surface.reason);

    // A second supply would make "which surface is on screen" unanswerable.
    try std.testing.expect(!ledger.supplySurface(0x1FD0_0000, default_width, default_height, .frontbuffer_contested, 6));
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), ledger.suppliedSurface().?.description.frontbuffer_physical_address);
}

test "nothing queued is reported as such and not as a refusal" {
    var ledger = Ledger{};
    ledger.policy = .observe_only;
    ledger.recordAttempt(ledger.wouldDispatch(0), 0, 0, 10);
    const totals = ledger.summary();
    try std.testing.expectEqual(Finding.nothing_to_dispatch, totals.finding());
    try std.testing.expectEqual(@as(u64, 0), totals.refused_by_policy);
    try std.testing.expect(std.mem.indexOf(u8, totals.finding().guidance(), "not a refusal") != null);
}

test "an effect can only be attributed to a delivery" {
    var ledger = Ledger{};
    ledger.policy = .observe_only;
    ledger.recordAttempt(ledger.wouldDispatch(24), 24, 0, 10);
    ledger.noteEffect(.present_reached);
    // Crediting a refusal with an effect would report progress the dispatcher
    // did not cause.
    try std.testing.expectEqual(@as(u64, 0), ledger.advancing_deliveries);
    try std.testing.expectEqual(Effect.unmeasured, ledger.last.effect);
}

test "the retained window keeps effects and wraps without losing counts" {
    var ledger = Ledger{};
    ledger.observeCallback(0x8219_51F8, 0, .intercepted_binding, .translated_x86, 1);
    ledger.policy = .bound_callbacks_only;
    var index: u64 = 0;
    while (index < max_attempts_retained + 5) : (index += 1) {
        ledger.recordAttempt(.delivered, 1, 1, index);
        ledger.noteEffect(.no_observable_change);
    }
    try std.testing.expectEqual(max_attempts_retained, ledger.recent_count);
    try std.testing.expectEqual(max_attempts_retained + 5, ledger.summary().delivered);
    try std.testing.expectEqual(max_attempts_retained + 5, ledger.summary().inert_deliveries);
    for (ledger.recent[0..ledger.recent_count]) |attempt| {
        try std.testing.expectEqual(Effect.no_observable_change, attempt.effect);
    }
}
