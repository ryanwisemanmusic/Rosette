//! One fact that only ever increases, several counters of it, and which of
//! them a conclusion may rest on.
//!
//! Why this exists
//! ---------------
//! The 2026-08-31 run reported, in the same log, that the title's graphics
//! interrupt callback had been entered **four** times and that it had been
//! entered **two hundred and forty** times. Both lines came from the emulator
//! and both were correct about what they measured. The first is a completion
//! breadcrumb the emulator prints for the first four dispatches and then only
//! under a trace flag; the second is the dispatch counter itself, restated
//! every two hundred and fortieth time. Rosette's callback ledger was fed the
//! first and never the second, so it froze at `attempts=4 returns=4
//! last_step=3006534266` while the callback kept running for another four and
//! a half billion steps.
//!
//! Everything downstream inherited that. `gpu-route INERT: the title
//! registered a callback and the emulator has never entered it ... which is an
//! emulator defect and not a title one` is a verdict, with an owner attached,
//! produced entirely by an observer that had stopped listening. The graphics
//! evidence table then carried the gap forward as a refutation. A reader
//! following it spends the next hour in the interrupt dispatch path, which was
//! healthy the whole time.
//!
//! The rule
//! --------
//! A monotone fact has a **floor**: the largest count any witness has stated.
//! No witness can be right and be below the floor, because the quantity only
//! goes up. So a witness below the floor is undercounting, and its silence is
//! not evidence of absence — it is evidence about the carrier the witness
//! rides on.
//!
//! Whether that undercount is a defect depends on the carrier, which is why
//! `Witness` records the carrier rather than just a name. A breadcrumb the
//! producer prints four times out of two hundred and forty *cannot* count
//! every occurrence, and expecting it to is the reader's error, not the
//! emulator's. An armed instruction-pointer tracepoint *can*: if it reports
//! fewer entries than another witness that also sees each occurrence, one of
//! the two is broken — armed on the wrong address, or not firing — and every
//! absence the lower one reports is unsafe to quote.
//!
//! Only witnesses that see each occurrence are measured against each other.
//! A carrier that is allowed to be short is also allowed to be counting
//! something slightly wider: Xenia increments its dispatch-attempt counter
//! before the executor's resolve check and its entry counter after it, so the
//! attempt breadcrumb legitimately runs ahead by the number of skips. Judging
//! both against one combined floor would report the entry counter as broken
//! every time a callback was skipped, which is a permanent false finding
//! manufactured out of two correct counters.
//!
//! What it never does
//! ------------------
//! It does not invent a count. The floor is always some witness's own stated
//! number; nothing here averages, extrapolates or fills a gap. And it never
//! turns an absence into a presence: a subject no witness has ever counted
//! stays `unobserved`, which is a different answer from zero.

const std = @import("std");

pub const schema_version: u32 = 2;

/// A quantity that only ever increases over a run.
///
/// Every entry here is something at least two independent counters in this
/// codebase claim to measure. A subject with one witness is not wrong to be
/// here — it is a place where a second witness would be worth adding — but the
/// contract only ever *decides* where there are two.
pub const Subject = enum(u8) {
    /// Entries into the title's own PowerPC graphics interrupt handler.
    title_interrupt_callback_entries,
    /// Returns from it. Kept separate from entries: the difference is a
    /// handler that is still inside its call, which is how a display pump dies
    /// with every counter reading healthy.
    title_interrupt_callback_returns,
    /// `GraphicsSystem::DispatchInterruptCallback` entries, before any gate.
    graphics_interrupt_dispatches,
    /// `GraphicsSystem::MarkVblank` entries.
    vblank_marks,
    /// Type-3 PM4 packets the command processor executed.
    pm4_packets_consumed,
    /// `CommandProcessor::IssueDraw` entries.
    draws_issued,
    /// `RenderTargetCache::Update` entries.
    render_target_updates,
    /// Xenos register writes the command processor performed.
    register_writes,
    /// Ring write-pointer advances the producer published.
    ring_write_pointer_advances,
    /// Guest frames that reached a host surface.
    guest_frames_presented,
    /// Executor admissions after registration, load and resolve gates.
    interrupt_executor_entries,
    /// All packet types, unlike the type-3 function-entry subject.
    pm4_packets_all_types,

    pub fn label(self: Subject) []const u8 {
        return switch (self) {
            .title_interrupt_callback_entries => "title interrupt callback entries",
            .title_interrupt_callback_returns => "title interrupt callback returns",
            .graphics_interrupt_dispatches => "graphics interrupt dispatches",
            .vblank_marks => "vblank marks",
            .pm4_packets_consumed => "PM4 packets consumed",
            .draws_issued => "draws issued",
            .render_target_updates => "render target updates",
            .register_writes => "register writes",
            .ring_write_pointer_advances => "ring write pointer advances",
            .guest_frames_presented => "guest frames presented",
            .interrupt_executor_entries => "interrupt executor entries after gates",
            .pm4_packets_all_types => "PM4 packets all types",
        };
    }

    /// Who owns the mechanism being counted. A disagreement between witnesses
    /// is always Rosette's defect — it is Rosette's reading that is wrong —
    /// but the reader still needs to know whose mechanism the number describes
    /// once the reading is repaired.
    pub fn mechanismOwner(self: Subject) []const u8 {
        return switch (self) {
            .title_interrupt_callback_entries,
            .title_interrupt_callback_returns,
            => "guest:title",
            .graphics_interrupt_dispatches,
            .interrupt_executor_entries,
            .pm4_packets_all_types,
            .vblank_marks,
            .pm4_packets_consumed,
            .draws_issued,
            .render_target_updates,
            .register_writes,
            => "emulator:gpu",
            .ring_write_pointer_advances => "guest:title",
            .guest_frames_presented => "rosette:presenter",
        };
    }
};

pub const subject_count: usize = @typeInfo(Subject).@"enum".fields.len;

/// The nine bring-up subjects that must have independent agreeing observers
/// before Rosette may make a closed graphics observation. Guest frames are
/// intentionally outside this set until a real guest frame exists: requiring
/// an observer for a frame that has not been produced would turn a valid
/// pre-present state into an observation failure.
pub const required_subject_count: usize = 9;

pub fn isRequiredSubject(subject: Subject) bool {
    return switch (subject) {
        .guest_frames_presented, .interrupt_executor_entries, .pm4_packets_all_types => false,
        else => true,
    };
}

/// Who is counting, and — the part that decides — what their number rides on.
pub const Witness = enum(u8) {
    /// A line the emulator prints on a throttle that restates its own running
    /// total. The total is authoritative; the number of lines is not.
    emulator_sampled_total,
    /// A line the emulator prints on a throttle that carries no total.
    /// Counting these lines measures the throttle and nothing else.
    emulator_sampled_line,
    /// A counter the emulator restates on a fixed heartbeat, independent of
    /// whether the underlying event happened recently.
    emulator_heartbeat_counter,
    /// Rosette's armed instruction-pointer tracepoint. It sees every entry to
    /// the address it is armed for, and nothing at any other address.
    rosette_tracepoint,
    /// Rosette's own walk of retained data — a ring scan, a replayed packet
    /// stream. Bounded by what was retained, so it can legitimately be short.
    rosette_retained_walk,
    /// A Rosette ledger assembled from parsed emulator lines. It is exactly as
    /// complete as the lines it was fed, which is what this whole contract is
    /// about.
    rosette_derived_ledger,

    pub fn label(self: Witness) []const u8 {
        return switch (self) {
            .emulator_sampled_total => "emulator:sampled-total",
            .emulator_sampled_line => "emulator:sampled-line",
            .emulator_heartbeat_counter => "emulator:heartbeat-counter",
            .rosette_tracepoint => "rosette:tracepoint",
            .rosette_retained_walk => "rosette:retained-walk",
            .rosette_derived_ledger => "rosette:derived-ledger",
        };
    }

    /// Whether being below the floor is a defect in this witness.
    ///
    /// A witness that restates a total, or that observes the mechanism
    /// directly, has no excuse for a low number. A witness that rides a
    /// throttled line, or that reads a bounded retention window, has one — and
    /// the excuse is structural, so treating it as a defect would produce a
    /// permanent false finding.
    pub fn countsEveryOccurrence(self: Witness) bool {
        return switch (self) {
            .emulator_sampled_total,
            .emulator_heartbeat_counter,
            .rosette_tracepoint,
            => true,
            .emulator_sampled_line,
            .rosette_retained_walk,
            .rosette_derived_ledger,
            => false,
        };
    }

    /// Why this witness may legitimately be short. Empty for witnesses that
    /// may not.
    pub fn undercountExcuse(self: Witness) []const u8 {
        return switch (self) {
            .emulator_sampled_total => "",
            .emulator_heartbeat_counter => "",
            .rosette_tracepoint => "",
            .emulator_sampled_line => "the producer prints this line on a throttle and it carries no total, so the count measures the throttle",
            .rosette_retained_walk => "the walk reads a bounded retention window, so occurrences older than the window are outside it by design",
            .rosette_derived_ledger => "this ledger is exactly as complete as the emulator lines it was fed",
        };
    }
};

pub const witness_count: usize = @typeInfo(Witness).@"enum".fields.len;

pub const Finding = enum(u8) {
    /// No witness has stated anything about this subject.
    unobserved,
    /// Exactly one witness. Nothing to reconcile, and nothing corroborated.
    single_witness,
    /// Every witness agrees on the floor.
    corroborated,
    /// Equal values from copied or incomplete evidence are not independent proof.
    dependent_agreement,
    /// A witness is below the floor and its carrier explains why. The floor
    /// is what a reader should quote; the short witness is not a finding.
    undercount_explained,
    /// A witness that counts every occurrence is below another witness that
    /// also counts every occurrence. One of two observations that should be
    /// identical is broken, and every absence the lower one reports is unsafe.
    undercount_unexplained,
    /// A witness that may legitimately be short is *higher* than every witness
    /// that counts each occurrence. That is worth printing and it is not
    /// judgeable: a retained walk finding more draws than the tracepoint saw
    /// is either a byte pattern that resembles a draw or a tracepoint missing
    /// entries, and the count alone cannot say which.
    weak_witness_exceeds,
    /// A witness restated a smaller number than it had already stated. A
    /// monotone quantity does not go backwards, so the witness is reading
    /// something other than the subject.
    regression,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .single_witness => "single-witness",
            .corroborated => "corroborated",
            .dependent_agreement => "dependent-agreement",
            .undercount_explained => "undercount-explained",
            .undercount_unexplained => "UNDERCOUNT-UNEXPLAINED",
            .weak_witness_exceeds => "weak-witness-exceeds",
            .regression => "REGRESSION",
        };
    }

    /// A defect in Rosette's reading, not in the mechanism being read.
    pub fn isDefect(self: Finding) bool {
        return self == .undercount_unexplained or self == .regression;
    }

    /// Whether a reader may quote an absence from the short witness.
    pub fn absenceIsQuotable(self: Finding) bool {
        return switch (self) {
            // One witness is useful evidence, but it is not corroboration.
            // The report's own guidance says that a second carrier is what
            // makes an absence checkable; returning true here made the
            // machine-readable flag contradict that guidance and allowed a
            // single silent observer to be quoted as proof of absence.
            .corroborated => true,
            .single_witness, .dependent_agreement => false,
            .unobserved,
            .undercount_explained,
            .undercount_unexplained,
            .weak_witness_exceeds,
            .regression,
            => false,
        };
    }

    pub fn guidance(self: Finding) []const u8 {
        return switch (self) {
            .unobserved => "no witness has counted this. That is a hole in the observation and not a zero: nothing here licenses a conclusion in either direction",
            .single_witness => "one witness, uncorroborated. Its number is the best available and nothing has confirmed it; a second witness on a different carrier is what would make an absence here quotable",
            .corroborated => "independent complete witnesses agree for this subject; negative claims still require coverage of the interval being discussed",
            .dependent_agreement => "the numbers agree but do not supply two independent complete observations. A parsed total and its derived ledger cannot corroborate one another",
            .undercount_explained => "a witness is below the floor because of how its number reaches Rosette, not because the events did not happen. Quote the floor. Do not read the short witness's last step as the moment the mechanism stopped — it is the moment its carrier last spoke",
            .undercount_unexplained => "a witness that sees every occurrence is reporting fewer than another witness that also sees every occurrence. One of them is misobserving — armed on the wrong address, parsing the wrong line, or scoped to the wrong domain — and every absence the lower one has reported has to be re-derived before any of them is quoted",
            .weak_witness_exceeds => "a witness that is allowed to be short is reporting more than every witness that sees each occurrence. Either the weak witness is counting something adjacent to the subject, or the strong ones are missing entries. Both are worth knowing and neither is decidable from the counts, so this is reported and never judged",
            .regression => "a monotone counter went backwards. The witness is not counting the subject it is registered against; find what else it is counting before using either value",
        };
    }
};

/// One witness's statement about one subject.
pub const Reading = struct {
    witness: Witness,
    /// The largest value this witness has stated. Kept as a maximum rather
    /// than the latest value so a torn or out-of-order line cannot lower it —
    /// a regression is detected separately, from the raw statement.
    count: u64 = 0,
    /// Step at which this witness last spoke. This is the field that turns a
    /// stale ledger into a visible one.
    last_step: u64 = 0,
    first_step: u64 = 0,
    statements: u64 = 0,
    /// A statement lower than one this witness had already made.
    regressions: u64 = 0,
    stated: bool = false,
};

/// The reconciled answer for one subject.
pub const Reconciliation = struct {
    subject: Subject,
    finding: Finding = .unobserved,
    witnesses: usize = 0,
    /// The largest count any witness stated, and who stated it.
    floor: u64 = 0,
    floor_witness: ?Witness = null,
    floor_step: u64 = 0,
    /// The witness furthest below the floor, and how far.
    short_witness: ?Witness = null,
    short_count: u64 = 0,
    short_step: u64 = 0,
    /// How many steps the short witness's last statement predates the floor
    /// witness's. This is the number that says "this ledger stopped listening
    /// four and a half billion steps ago".
    short_quiet_steps: u64 = 0,

    pub fn isDefect(self: Reconciliation) bool {
        return self.finding.isDefect();
    }

    /// The count a report should print. Always some witness's own number.
    pub fn quotable(self: Reconciliation) u64 {
        return self.floor;
    }
};

/// Decide a subject from its readings.
///
/// Pure and total: it takes the readings as an array so a test can state a
/// disagreement directly rather than driving a ledger into one.
pub fn classify(readings: []const Reading) Finding {
    var stated: usize = 0;
    var floor: u64 = 0;
    var regressions: u64 = 0;
    // The floor a *judgement* rests on is the highest witness that sees every
    // occurrence, and only those witnesses are measured against it.
    //
    // This separation is the difference between a gate that works and one that
    // stops healthy runs. Xenia counts dispatch attempts before the executor's
    // resolve check and entries after it, so the attempt breadcrumb can
    // legitimately exceed the entry counter by the number of skips. Judging
    // every witness against one combined floor would call the entry counter
    // broken every time a callback was skipped — a permanent false finding
    // produced by two correct counters counting slightly different things.
    var judgement_floor: u64 = 0;
    var strong_witnesses: usize = 0;
    for (readings) |reading| {
        if (!reading.stated) continue;
        stated += 1;
        regressions +|= reading.regressions;
        if (reading.count > floor) floor = reading.count;
        if (!reading.witness.countsEveryOccurrence()) continue;
        strong_witnesses += 1;
        if (reading.count > judgement_floor) judgement_floor = reading.count;
    }
    if (regressions != 0) return .regression;
    if (stated == 0) return .unobserved;
    if (stated == 1) return .single_witness;

    if (strong_witnesses > 1) {
        for (readings) |reading| {
            if (!reading.stated) continue;
            if (!reading.witness.countsEveryOccurrence()) continue;
            if (reading.count < judgement_floor) return .undercount_unexplained;
        }
    }

    var explained = false;
    var exceeds = false;
    for (readings) |reading| {
        if (!reading.stated) continue;
        if (reading.witness.countsEveryOccurrence()) continue;
        if (reading.count < floor) explained = true;
        if (strong_witnesses != 0 and reading.count > judgement_floor) exceeds = true;
    }
    if (exceeds) return .weak_witness_exceeds;
    if (explained) return .undercount_explained;
    // Both emulator carriers can restate the same underlying counter. The
    // instruction trace is the independent origin; copying a total into a
    // Rosette ledger does not create another measurement.
    var trace = false;
    var emulator = false;
    for (readings) |reading| {
        if (!reading.stated) continue;
        switch (reading.witness) {
            .rosette_tracepoint => trace = true,
            .emulator_sampled_total, .emulator_heartbeat_counter => emulator = true,
            else => {},
        }
    }
    return if (trace and emulator) .corroborated else .dependent_agreement;
}

test "agreeing witnesses corroborate" {
    const readings = [_]Reading{
        .{ .witness = .rosette_tracepoint, .count = 24, .stated = true },
        .{ .witness = .emulator_heartbeat_counter, .count = 24, .stated = true },
    };
    try std.testing.expectEqual(Finding.corroborated, classify(&readings));
    try std.testing.expect(Finding.corroborated.absenceIsQuotable());
}

test "a throttled breadcrumb below the floor is explained, not a defect" {
    // The 2026-08-31 shape: four completion breadcrumbs against a dispatch
    // counter that had reached two hundred and forty.
    const readings = [_]Reading{
        .{ .witness = .emulator_sampled_line, .count = 4, .stated = true },
        .{ .witness = .emulator_sampled_total, .count = 240, .stated = true },
    };
    const finding = classify(&readings);
    try std.testing.expectEqual(Finding.undercount_explained, finding);
    try std.testing.expect(!finding.isDefect());
    // The point of the whole contract: the short witness's absence must not be
    // quotable, because quoting it produced "the emulator has never entered
    // it" about a callback that had run two hundred and forty times.
    try std.testing.expect(!finding.absenceIsQuotable());
}

test "a tracepoint below the floor is Rosette misobserving" {
    const readings = [_]Reading{
        .{ .witness = .rosette_tracepoint, .count = 0, .stated = true },
        .{ .witness = .emulator_heartbeat_counter, .count = 112, .stated = true },
    };
    const finding = classify(&readings);
    try std.testing.expectEqual(Finding.undercount_unexplained, finding);
    try std.testing.expect(finding.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, finding.guidance(), "wrong address") != null);
}

test "a monotone counter that goes backwards is not counting the subject" {
    const readings = [_]Reading{
        .{ .witness = .emulator_sampled_total, .count = 240, .regressions = 1, .stated = true },
        .{ .witness = .rosette_tracepoint, .count = 240, .stated = true },
    };
    try std.testing.expectEqual(Finding.regression, classify(&readings));
}

test "one witness is not corroboration and no witness is not zero" {
    const one = [_]Reading{.{ .witness = .rosette_tracepoint, .count = 5, .stated = true }};
    try std.testing.expectEqual(Finding.single_witness, classify(&one));
    try std.testing.expect(!Finding.single_witness.absenceIsQuotable());

    const none = [_]Reading{.{ .witness = .rosette_tracepoint, .stated = false }};
    try std.testing.expectEqual(Finding.unobserved, classify(&none));
    try std.testing.expect(!Finding.unobserved.absenceIsQuotable());
}

test "every witness either counts everything or says why it cannot" {
    inline for (@typeInfo(Witness).@"enum".fields) |field| {
        const witness: Witness = @enumFromInt(field.value);
        try std.testing.expect(witness.label().len != 0);
        if (witness.countsEveryOccurrence()) {
            try std.testing.expectEqualStrings("", witness.undercountExcuse());
        } else {
            try std.testing.expect(witness.undercountExcuse().len != 0);
        }
    }
}

test "every subject names its mechanism owner" {
    inline for (@typeInfo(Subject).@"enum".fields) |field| {
        const subject: Subject = @enumFromInt(field.value);
        try std.testing.expect(subject.label().len != 0);
        try std.testing.expect(subject.mechanismOwner().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 12), subject_count);
    try std.testing.expectEqual(@as(usize, 9), required_subject_count);
    try std.testing.expectEqual(@as(usize, 6), witness_count);
}

test "guest frames are optional for core corroboration closure" {
    try std.testing.expect(isRequiredSubject(.ring_write_pointer_advances));
    try std.testing.expect(!isRequiredSubject(.guest_frames_presented));
}

// The false finding this separation exists to prevent. Xenia's attempt
// breadcrumb counts dispatches before the executor's resolve check and its
// entry counter counts them after, so the breadcrumb runs ahead by the number
// of skips. A single combined floor would call the entry counter — which is
// correct — an undercounting observer, forever, on every run with one skip.
test "a weak witness running ahead never indicts a strong one" {
    const readings = [_]Reading{
        .{ .witness = .emulator_sampled_line, .count = 246, .stated = true },
        .{ .witness = .emulator_sampled_total, .count = 240, .stated = true },
    };
    const finding = classify(&readings);
    try std.testing.expectEqual(Finding.weak_witness_exceeds, finding);
    try std.testing.expect(!finding.isDefect());
    try std.testing.expect(!finding.absenceIsQuotable());
}

test "two witnesses that each see everything are judged against each other" {
    const readings = [_]Reading{
        .{ .witness = .rosette_tracepoint, .count = 20, .stated = true },
        .{ .witness = .emulator_heartbeat_counter, .count = 63, .stated = true },
        // A weak witness sitting between them changes nothing about the
        // judgement; it is neither the floor nor the accused.
        .{ .witness = .rosette_retained_walk, .count = 40, .stated = true },
    };
    const finding = classify(&readings);
    try std.testing.expectEqual(Finding.undercount_unexplained, finding);
    try std.testing.expect(finding.isDefect());
}

test "one strong witness alone is never indicted by weak company" {
    const readings = [_]Reading{
        .{ .witness = .rosette_tracepoint, .count = 24, .stated = true },
        .{ .witness = .emulator_sampled_line, .count = 5, .stated = true },
    };
    try std.testing.expectEqual(Finding.undercount_explained, classify(&readings));

    const derived = [_]Reading{
        .{ .witness = .emulator_sampled_total, .count = 240, .stated = true },
        .{ .witness = .rosette_derived_ledger, .count = 240, .stated = true },
    };
    try std.testing.expectEqual(Finding.dependent_agreement, classify(&derived));
}

test "weak witnesses alone can neither corroborate nor accuse" {
    const readings = [_]Reading{
        .{ .witness = .emulator_sampled_line, .count = 5, .stated = true },
        .{ .witness = .rosette_retained_walk, .count = 30, .stated = true },
    };
    const finding = classify(&readings);
    try std.testing.expectEqual(Finding.undercount_explained, finding);
    try std.testing.expect(!finding.isDefect());
}

test "two carriers of one emulator counter do not establish independent absence" {
    const readings = [_]Reading{
        .{ .witness = .emulator_sampled_total, .count = 0, .stated = true },
        .{ .witness = .emulator_heartbeat_counter, .count = 0, .stated = true },
    };
    const finding = classify(&readings);
    try std.testing.expectEqual(Finding.dependent_agreement, finding);
    try std.testing.expect(!finding.absenceIsQuotable());
}
