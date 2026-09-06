//! Which of several disagreeing statements about the same fact is current.
//!
//! Every observer here states a value and a moment. The ledger keeps both, per
//! (claim, source), and applies one rule: a source that was contradicted and
//! then went quiet was describing a moment that has passed; a source still
//! repeating a contradicted value is disagreeing about the present.
//!
//! The failure this exists to stop is concrete and has cost real time twice in
//! one session. The emulator emits
//!
//! ```text
//! RING BUFFER: no-swap diagnosis stage=BOOTSTRAP_INCOMPLETE ring_init=NO rb_base=00000000
//! ```
//!
//! four times between 515 ms and 1.9 s, then never again. At 2279 ms a
//! different line says
//!
//! ```text
//! gpu_startup_watch ready: ring_init=YES init_ack=YES callback_set=YES rb_base=1FC9B000
//! ```
//!
//! Both are in the log for the rest of the run. The first is the one that
//! repeats often enough to be found by grep, and it is wrong. Reading it sends
//! an investigation after a ring that was configured 1.7 seconds earlier.
//!
//! Nothing about that is Xenia misbehaving — a bring-up diagnostic is supposed
//! to describe bring-up. The defect is that nothing reconciles the snapshots,
//! so the log's loudest statement about a fact is not its truest one.

const std = @import("std");
const contract = @import("xenia_claim_reconciliation_contract");

pub const Claim = contract.Claim;
pub const Source = contract.Source;
pub const Side = contract.Side;
pub const Agreement = contract.Agreement;
pub const Finding = contract.Finding;

pub const claim_count = contract.claim_count;
pub const source_count = contract.source_count;

pub const Observation = struct {
    stated: bool = false,
    value: u64 = 0,
    /// Guest step of the most recent statement.
    last_step: u64 = 0,
    first_step: u64 = 0,
    statements: u64 = 0,
    /// Statements made *after* a differing value was observed from another
    /// source. Non-zero is what turns a stale snapshot into a live contest,
    /// and it is the only field the reconciliation rule reads.
    statements_after_contradiction: u64 = 0,

    pub fn repeatedAfterContradiction(self: Observation) bool {
        return self.statements_after_contradiction != 0;
    }
};

pub const Reconciliation = struct {
    claim: Claim,
    agreement: Agreement = .unobserved,
    observers: usize = 0,
    /// The value from the newest statement.
    current_value: u64 = 0,
    current_source: ?Source = null,
    current_step: u64 = 0,
    /// A source that disagrees with the current value.
    losing_value: u64 = 0,
    losing_source: ?Source = null,
    losing_step: u64 = 0,
    /// Whether the disagreement crosses the harness/emulator boundary.
    crosses_sides: bool = false,

    pub fn hasStaleReadings(self: Reconciliation) bool {
        return self.agreement.hasStaleReadings();
    }

    pub fn isDefect(self: Reconciliation) bool {
        return self.agreement.isDefect();
    }
};

pub const Summary = struct {
    observed: usize = 0,
    /// Claims with more than one source statement. This is the actual
    /// cross-check population; `corroborated` is retained as the historical
    /// field name for consumers that already use it.
    multi_source: usize = 0,
    /// Claims with exactly one source. These are not disagreements, but they
    /// are not independently confirmed either.
    single_source: usize = 0,
    corroborated: usize = 0,
    agreed: usize = 0,
    superseded: usize = 0,
    contested: usize = 0,
    crosses_sides: bool = false,
    statements: u64 = 0,

    pub fn finding(self: Summary) Finding {
        return contract.findingOf(self.corroborated, self.superseded, self.contested, self.crosses_sides);
    }
};

pub const Ledger = struct {
    entries: [claim_count][source_count]Observation =
        .{.{Observation{}} ** source_count} ** claim_count,
    statements: u64 = 0,

    pub fn observation(self: *const Ledger, claim: Claim, source: Source) Observation {
        return self.entries[@intFromEnum(claim)][@intFromEnum(source)];
    }

    /// Record one statement of one claim by one source.
    ///
    /// Called on every emission, not only on change: the count of statements
    /// made after a contradiction is the rule's only input, and skipping the
    /// repeats would erase it.
    /// How many observers other than a boundary tracepoint have spoken about
    /// the claim that corresponds to a GPU bring-up boundary.
    ///
    /// Zero means the only thing that ever looked at this boundary is the
    /// instruction-pointer arming, so a `never crossed` reading below it rests
    /// on one observer and cannot be substantiated. Returns zero for boundaries
    /// with no corresponding claim: an unmapped boundary is uncorroborated by
    /// construction, which is the honest answer.
    pub fn observersForBoundary(self: *const Ledger, boundary: anytype) u32 {
        const claim: Claim = switch (boundary) {
            .query_video_mode => .vd_query_video_mode_entries,
            .initialize_engines => .vd_initialize_engines_entries,
            .initialize_ring_buffer => .vd_initialize_ring_buffer_entries,
            .set_interrupt_callback => .vd_set_graphics_interrupt_callback_entries,
            .issue_swap => .vd_swap_entries,
            else => return 0,
        };
        var others: u32 = 0;
        for (self.entries[@intFromEnum(claim)], 0..) |entry, index| {
            if (!entry.stated) continue;
            const which: Source = @enumFromInt(index);
            if (which == .rosette_boundary_tracepoint) continue;
            others += 1;
        }
        return others;
    }

    pub fn state(self: *Ledger, claim: Claim, source: Source, value: u64, step: u64) void {
        self.statements +|= 1;
        const row = &self.entries[@intFromEnum(claim)];
        const entry = &row[@intFromEnum(source)];

        // Is any other source already saying something different and newer?
        // If so this statement is a re-assertion against a contradiction, and
        // that is what separates a live disagreement from a stale snapshot.
        var contradicted = false;
        for (row, 0..) |other, index| {
            if (index == @intFromEnum(source)) continue;
            if (!other.stated) continue;
            if (other.value != value and other.last_step >= entry.last_step) contradicted = true;
        }

        if (!entry.stated) {
            entry.stated = true;
            entry.first_step = step;
        }
        entry.value = value;
        entry.last_step = step;
        entry.statements +|= 1;
        if (contradicted) entry.statements_after_contradiction +|= 1;
    }

    pub fn stateBool(self: *Ledger, claim: Claim, source: Source, value: bool, step: u64) void {
        self.state(claim, source, @intFromBool(value), step);
    }

    pub fn reconcile(self: *const Ledger, claim: Claim) Reconciliation {
        const row = self.entries[@intFromEnum(claim)];
        var result = Reconciliation{ .claim = claim };

        var newest_step: u64 = 0;
        var any = false;
        for (row, 0..) |entry, index| {
            if (!entry.stated) continue;
            result.observers += 1;
            if (!any or entry.last_step >= newest_step) {
                any = true;
                newest_step = entry.last_step;
                result.current_value = entry.value;
                result.current_source = @enumFromInt(index);
                result.current_step = entry.last_step;
            }
        }
        if (!any) return result;

        // The losing source: the one that disagrees with the current value.
        // A source still repeating after a contradiction is preferred, because
        // that is the case a reader has to be told about.
        var values_differ = false;
        var loser_repeated = false;
        for (row, 0..) |entry, index| {
            if (!entry.stated) continue;
            const which: Source = @enumFromInt(index);
            if (which == result.current_source.?) continue;
            if (entry.value == result.current_value) continue;
            values_differ = true;
            const prefer = result.losing_source == null or
                (entry.repeatedAfterContradiction() and !loser_repeated);
            if (prefer) {
                result.losing_source = which;
                result.losing_value = entry.value;
                result.losing_step = entry.last_step;
                result.crosses_sides = which.side() != result.current_source.?.side();
            }
            if (entry.repeatedAfterContradiction()) loser_repeated = true;
        }

        result.agreement = contract.agreementOf(result.observers, values_differ, loser_repeated);
        return result;
    }

    pub fn summary(self: *const Ledger) Summary {
        var totals = Summary{ .statements = self.statements };
        inline for (@typeInfo(Claim).@"enum".fields) |field| {
            const claim: Claim = @enumFromInt(field.value);
            const result = self.reconcile(claim);
            if (result.observers != 0) totals.observed += 1;
            if (result.observers > 1) {
                totals.corroborated += 1;
                totals.multi_source += 1;
            } else if (result.observers == 1) {
                totals.single_source += 1;
            }
            // A superseded claim can still cross the Rosette/emulator boundary.
            // The headline must expose that fact even though the row is not a
            // live contest; otherwise the summary contradicts its own detail.
            if (result.crosses_sides) totals.crosses_sides = true;
            switch (result.agreement) {
                .agreed => totals.agreed += 1,
                .superseded => totals.superseded += 1,
                .contested => {
                    totals.contested += 1;
                },
                .unobserved, .single_source => {},
            }
        }
        return totals;
    }

    /// The claim a reader should look at first: a live contest before a stale
    /// reading, and a contest that crosses the host boundary before one that
    /// does not.
    pub fn blocking(self: *const Ledger) ?Reconciliation {
        var best: ?Reconciliation = null;
        inline for (@typeInfo(Claim).@"enum".fields) |field| {
            const claim: Claim = @enumFromInt(field.value);
            const result = self.reconcile(claim);
            const rank = severity(result);
            if (rank != 0) {
                const current = best orelse blk: {
                    best = result;
                    break :blk result;
                };
                if (rank > severity(current)) best = result;
            }
        }
        return best;
    }
};

fn severity(result: Reconciliation) u8 {
    if (result.agreement == .contested) return if (result.crosses_sides) 3 else 2;
    if (result.agreement == .superseded) return 1;
    return 0;
}

test "the live stale-snapshot case reconciles to the newer value" {
    // `ring_init=NO` from the no-swap diagnosis at 515 ms, four times, then
    // silence. `ring_init=YES` from the startup watch at 2279 ms.
    var ledger = Ledger{};
    var repeat: u64 = 0;
    while (repeat < 4) : (repeat += 1) {
        ledger.stateBool(.ring_initialised, .xenia_no_swap_diagnosis, false, 500 + repeat);
    }
    ledger.stateBool(.ring_initialised, .xenia_startup_watch, true, 2_279);

    const result = ledger.reconcile(.ring_initialised);
    try std.testing.expectEqual(Agreement.superseded, result.agreement);
    try std.testing.expectEqual(@as(u64, 1), result.current_value);
    try std.testing.expectEqual(Source.xenia_startup_watch, result.current_source.?);
    try std.testing.expectEqual(Source.xenia_no_swap_diagnosis, result.losing_source.?);
    try std.testing.expect(result.hasStaleReadings());
    try std.testing.expect(!result.isDefect());
    // Both sources are inside the emulator, so this is a reading trap and not
    // a model split.
    try std.testing.expect(!result.crosses_sides);
}

test "a source that keeps talking after being contradicted is a contest" {
    var ledger = Ledger{};
    ledger.stateBool(.ring_initialised, .xenia_no_swap_diagnosis, false, 500);
    ledger.stateBool(.ring_initialised, .xenia_startup_watch, true, 2_279);
    // The bring-up diagnostic re-asserts after the contradiction.
    ledger.stateBool(.ring_initialised, .xenia_no_swap_diagnosis, false, 3_000);

    const result = ledger.reconcile(.ring_initialised);
    try std.testing.expectEqual(Agreement.contested, result.agreement);
    try std.testing.expect(result.isDefect());
    try std.testing.expectEqual(
        @as(u64, 1),
        ledger.observation(.ring_initialised, .xenia_no_swap_diagnosis).statements_after_contradiction,
    );
}

test "the same ring claim disagreeing across domains is a model split" {
    var ledger = Ledger{};
    var beat: u64 = 0;
    while (beat < 8) : (beat += 1) {
        ledger.state(.ring_write_pointer, .xenia_startup_watch, 25, 1_000 + beat * 100);
        ledger.state(.ring_write_pointer, .rosette_ring_publication, 0, 1_050 + beat * 100);
    }

    const result = ledger.reconcile(.ring_write_pointer);
    try std.testing.expectEqual(Agreement.contested, result.agreement);
    try std.testing.expect(result.crosses_sides);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.contested);
    try std.testing.expect(totals.crosses_sides);
    try std.testing.expectEqual(Finding.model_split, totals.finding());
    try std.testing.expectEqual(Claim.ring_write_pointer, ledger.blocking().?.claim);
}

test "different callback domains cannot manufacture a model split" {
    var ledger = Ledger{};
    ledger.state(.callback_completions, .xenia_startup_watch, 168, 3_000);
    ledger.state(.draw_completion_dispatches, .rosette_interrupt_dispatch, 0, 3_100);

    try std.testing.expectEqual(Agreement.single_source, ledger.reconcile(.callback_completions).agreement);
    try std.testing.expectEqual(Agreement.single_source, ledger.reconcile(.draw_completion_dispatches).agreement);
    try std.testing.expectEqual(Finding.uncorroborated, ledger.summary().finding());
    try std.testing.expect(ledger.blocking() == null);
}

test "agreeing observers are corroboration, not noise" {
    var ledger = Ledger{};
    ledger.state(.ring_base_address, .xenia_startup_watch, 0x1FC9_B000, 2_279);
    ledger.state(.ring_base_address, .rosette_ring_publication, 0x1FC9_B000, 2_400);
    ledger.state(.ring_base_address, .rosette_kernel_import, 0x1FC9_B000, 2_500);

    const result = ledger.reconcile(.ring_base_address);
    try std.testing.expectEqual(Agreement.agreed, result.agreement);
    try std.testing.expectEqual(@as(usize, 3), result.observers);
    try std.testing.expect(result.losing_source == null);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.corroborated);
    try std.testing.expectEqual(@as(usize, 1), totals.multi_source);
    try std.testing.expectEqual(@as(usize, 0), totals.single_source);
    try std.testing.expectEqual(Finding.consistent, totals.finding());
    try std.testing.expect(ledger.blocking() == null);
}

test "one observer is never consistency" {
    var ledger = Ledger{};
    ledger.stateBool(.guest_main_ready, .xenia_startup_watch, true, 2_279);
    try std.testing.expectEqual(Agreement.single_source, ledger.reconcile(.guest_main_ready).agreement);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.observed);
    try std.testing.expectEqual(@as(usize, 0), totals.corroborated);
    try std.testing.expectEqual(@as(usize, 0), totals.multi_source);
    try std.testing.expectEqual(@as(usize, 1), totals.single_source);
    try std.testing.expectEqual(Finding.uncorroborated, totals.finding());
}

test "a live contest is reported ahead of any number of stale readings" {
    var ledger = Ledger{};
    // Five superseded claims.
    inline for (.{
        Claim.ring_initialised,
        Claim.ring_init_acknowledged,
        Claim.interrupt_callback_set,
        Claim.ring_base_address,
        Claim.ring_size_bytes,
    }) |claim| {
        ledger.state(claim, .xenia_no_swap_diagnosis, 0, 500);
        ledger.state(claim, .xenia_startup_watch, 1, 2_279);
    }
    try std.testing.expectEqual(Finding.stale_readings_present, ledger.summary().finding());

    // One live contest across the boundary now outranks all five.
    ledger.state(.ring_read_pointer, .rosette_ring_publication, 0, 3_000);
    ledger.state(.ring_read_pointer, .xenia_startup_watch, 25, 3_100);
    ledger.state(.ring_read_pointer, .rosette_ring_publication, 0, 3_200);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 5), totals.superseded);
    try std.testing.expectEqual(@as(usize, 1), totals.contested);
    try std.testing.expect(totals.crosses_sides);
    try std.testing.expectEqual(Finding.model_split, totals.finding());
    try std.testing.expectEqual(Claim.ring_read_pointer, ledger.blocking().?.claim);
}

test "an unobserved claim is unknown rather than false" {
    const ledger = Ledger{};
    const result = ledger.reconcile(.swap_packets_consumed);
    try std.testing.expectEqual(Agreement.unobserved, result.agreement);
    try std.testing.expectEqual(@as(usize, 0), result.observers);
    try std.testing.expect(result.current_source == null);
    try std.testing.expectEqual(Finding.uncorroborated, ledger.summary().finding());
}
