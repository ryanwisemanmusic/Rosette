//! When two domains describe one fact, whether they are describing the same
//! fact, and which of them a conclusion may rest on.
//!
//! The rules here are deliberately conservative. The failure mode this file
//! exists to stop is not two observers disagreeing — that is useful — it is
//! two observers being *averaged*, or one silently promoted, so a report
//! prints a number nobody measured. A run that says `packet anomalies 4/0` in
//! one sample and `no truncation` in another has a parser disagreement, and
//! folding those into a health percentage destroys the only evidence that
//! would resolve it.
//!
//! Three separate questions, kept separate:
//!
//! 1. **Are these the same subject?** Identity, not similarity. A ring is the
//!    same ring when base and size agree; an object is the same object when
//!    the generation agrees too.
//! 2. **Are these the same measurement?** Two counters of different things
//!    agreeing is a coincidence and two disagreeing is not a defect. A
//!    dispatch-attempt counter and an entry counter are different measurements
//!    of adjacent events.
//! 3. **Which value stands?** Only ever some observer's own number.

const std = @import("std");
const contract = @import("contract.zig");

pub const Domain = contract.Domain;
pub const SourceClass = contract.SourceClass;

/// What a counter is counting, precisely enough that two observers with the
/// same measurement really are comparable.
pub const Measurement = enum(u8) {
    /// Entries into a function, counted at its first instruction.
    function_entries = 0,
    /// Returns from a function.
    function_returns = 0x01,
    /// Attempts recorded before a gate or validity check.
    attempts_before_gate = 0x02,
    /// Attempts recorded after a gate.
    attempts_after_gate = 0x03,
    /// Items structurally decoded from a buffer.
    decoded_items = 0x04,
    /// Items executed by a consumer.
    executed_items = 0x05,
    /// Bytes or dwords transferred.
    transferred_units = 0x06,
    /// State transitions applied.
    applied_transitions = 0x07,
    unknown = 255,

    pub fn label(self: Measurement) []const u8 {
        return switch (self) {
            .function_entries => "function-entries",
            .function_returns => "function-returns",
            .attempts_before_gate => "attempts-before-gate",
            .attempts_after_gate => "attempts-after-gate",
            .decoded_items => "decoded-items",
            .executed_items => "executed-items",
            .transferred_units => "transferred-units",
            .applied_transitions => "applied-transitions",
            .unknown => "unknown",
        };
    }

    /// Whether two observers with these measurements are counting the same
    /// occurrences. `unknown` is comparable with nothing, including itself:
    /// two observers that have not said what they count cannot be reconciled.
    pub fn comparable(self: Measurement, other: Measurement) bool {
        if (self == .unknown or other == .unknown) return false;
        return self == other;
    }

    /// Whether `self` counts a superset of `other` by construction. A counter
    /// incremented before a gate legitimately exceeds one incremented after
    /// it, and reporting that as a disagreement is a permanent false finding.
    pub fn supersetOf(self: Measurement, other: Measurement) bool {
        return switch (self) {
            .attempts_before_gate => other == .attempts_after_gate or other == .function_entries,
            .attempts_after_gate, .function_entries => other == .function_returns,
            .decoded_items => other == .executed_items,
            else => false,
        };
    }
};

/// One domain's statement about one subject.
pub const Statement = struct {
    domain: Domain,
    measurement: Measurement = .unknown,
    value: u64 = 0,
    step: u64 = 0,
    /// Whether this observer sees every occurrence of what it counts. A
    /// throttled breadcrumb does not; an armed tracepoint does.
    complete: bool = false,
    stated: bool = false,
};

/// What reconciliation concluded.
pub const Agreement = enum(u8) {
    /// Nothing stated.
    unobserved,
    /// One statement. Usable, uncorroborated.
    single,
    /// Two or more comparable statements with the same value.
    agreed,
    /// Comparable statements differ and the difference is explained by one
    /// observer's carrier being incomplete.
    explained_difference,
    /// Comparable statements differ, both observers see everything, and one is
    /// wrong. This is a defect in the observation.
    contradiction,
    /// The statements are not comparable, so the difference means nothing.
    /// Reported, never resolved.
    incomparable,
    /// One observer counts a superset of the other by construction. The
    /// difference is the gate between them and is not a disagreement.
    nested,

    pub fn label(self: Agreement) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .single => "single",
            .agreed => "agreed",
            .explained_difference => "explained-difference",
            .contradiction => "CONTRADICTION",
            .incomparable => "incomparable",
            .nested => "nested",
        };
    }

    pub fn describe(self: Agreement) []const u8 {
        return switch (self) {
            .unobserved => "nobody stated a value, so neither a number nor its absence is available here",
            .single => "one observer, uncorroborated. Its number is the best available and nothing has confirmed it",
            .agreed => "every comparable observer states the same value",
            .explained_difference => "observers differ and the lower one rides a carrier that cannot see every occurrence. Quote the higher; the lower one's silence is about its carrier",
            .contradiction => "two observers that each see every occurrence of the same measurement disagree. One of them is wrong and the report may not choose between them by preference — find which observation is broken",
            .incomparable => "the observers are counting different things. The difference between them is not a disagreement and must not be reported as one",
            .nested => "one observer counts a superset of the other by construction — a gate sits between them — so the difference is the gate's size and not an error",
        };
    }

    pub fn isDefect(self: Agreement) bool {
        return self == .contradiction;
    }

    /// Whether a report may quote a value for this subject at all.
    pub fn quotable(self: Agreement) bool {
        return switch (self) {
            .agreed, .single, .explained_difference, .nested => true,
            .unobserved, .contradiction, .incomparable => false,
        };
    }
};

pub const Result = struct {
    agreement: Agreement = .unobserved,
    /// The value a report should print, when one may be printed.
    value: u64 = 0,
    /// Who supplied it.
    domain: ?Domain = null,
    /// The other side of a difference, when there is one.
    other_value: u64 = 0,
    other_domain: ?Domain = null,
    observers: usize = 0,
};

/// Reconcile a set of statements about one subject.
///
/// Comparability is decided from the measurements before any value is looked
/// at. That order matters: two counters of different things that happen to be
/// equal are a coincidence, not corroboration, and a report that treats them
/// as agreement has manufactured confidence out of an accident.
pub fn reconcile(statements: []const Statement) Result {
    var result = Result{};
    var high: ?Statement = null;
    var low: ?Statement = null;
    var any_incomparable = false;
    var any_nested = false;
    var all_same_measurement = true;
    var first: ?Statement = null;

    for (statements) |statement| {
        if (!statement.stated) continue;
        result.observers += 1;
        if (first == null) first = statement;
        if (high == null or statement.value > high.?.value) high = statement;
        if (low == null or statement.value < low.?.value) low = statement;
        if (statement.measurement != first.?.measurement) all_same_measurement = false;
    }
    if (result.observers == 0) return result;

    result.value = high.?.value;
    result.domain = high.?.domain;
    if (result.observers == 1) {
        result.agreement = .single;
        return result;
    }
    result.other_value = low.?.value;
    result.other_domain = low.?.domain;

    // Every unordered pair, checked for a construction-level relationship
    // before any value is compared.
    for (statements, 0..) |left, index| {
        if (!left.stated) continue;
        for (statements[index + 1 ..]) |right| {
            if (!right.stated) continue;
            if (left.measurement.supersetOf(right.measurement) or
                right.measurement.supersetOf(left.measurement))
            {
                any_nested = true;
                continue;
            }
            if (!left.measurement.comparable(right.measurement)) any_incomparable = true;
        }
    }

    if (any_incomparable) {
        result.agreement = .incomparable;
        // Nothing may be quoted, so no observer is named as the source of a
        // number the report is not entitled to print.
        result.value = 0;
        result.domain = null;
        return result;
    }
    if (any_nested and !all_same_measurement) {
        result.agreement = .nested;
        return result;
    }
    if (high.?.value == low.?.value) {
        result.agreement = .agreed;
        return result;
    }
    // The lowest observer decides. If it cannot see every occurrence, its
    // shortfall is about its carrier; if it can, two complete observers of one
    // measurement disagree and one of them is broken.
    result.agreement = if (low.?.complete) .contradiction else .explained_difference;
    return result;
}

/// Whether an authenticity claim survives a set of contributing sources. One
/// synthetic edge anywhere in a chain taints everything downstream of it, and
/// this is the rule that keeps that from being forgotten between subsystems.
pub fn effectiveAuthenticity(sources: []const SourceClass) SourceClass {
    var result: SourceClass = .unknown;
    var seen = false;
    for (sources) |source| {
        if (source.taintsAuthenticity()) return source;
        if (!seen) {
            result = source;
            seen = true;
            continue;
        }
        // Diagnostic beats host-forwarded beats guest-authentic: the weakest
        // link decides what the chain as a whole may claim.
        if (source == .diagnostic) result = .diagnostic;
        if (source == .unknown and result != .diagnostic) result = .unknown;
        if (source == .host_forwarded and result == .guest_authentic) result = .host_forwarded;
    }
    return result;
}

test "equal values from different measurements are a coincidence" {
    const statements = [_]Statement{
        .{ .domain = .rosette_gpu, .measurement = .function_entries, .value = 24, .complete = true, .stated = true },
        .{ .domain = .xenia_command_processor, .measurement = .decoded_items, .value = 24, .complete = true, .stated = true },
    };
    const result = reconcile(&statements);
    try std.testing.expectEqual(Agreement.incomparable, result.agreement);
    try std.testing.expect(!result.agreement.quotable());
}

// The exact false finding the earlier pass had to design around: Xenia counts
// dispatch attempts before the executor's resolve check and entries after it.
test "a counter before a gate is nested with one after it, never a defect" {
    const statements = [_]Statement{
        .{ .domain = .xenia_kernel, .measurement = .attempts_before_gate, .value = 246, .complete = true, .stated = true },
        .{ .domain = .xenia_kernel, .measurement = .attempts_after_gate, .value = 240, .complete = true, .stated = true },
    };
    const result = reconcile(&statements);
    try std.testing.expectEqual(Agreement.nested, result.agreement);
    try std.testing.expect(!result.agreement.isDefect());
    try std.testing.expect(result.agreement.quotable());
    try std.testing.expectEqual(@as(u64, 246), result.value);
}

// The 2026-08-31 callback ledger: a throttled breadcrumb at 4 against the
// executor's own restated total at 240, both counting entries.
test "an incomplete carrier below a complete one is explained, not contradicted" {
    const statements = [_]Statement{
        .{ .domain = .xenia_kernel, .measurement = .function_entries, .value = 4, .step = 3_006_534_266, .complete = false, .stated = true },
        .{ .domain = .xenia_kernel, .measurement = .function_entries, .value = 240, .step = 7_493_776_604, .complete = true, .stated = true },
    };
    const result = reconcile(&statements);
    try std.testing.expectEqual(Agreement.explained_difference, result.agreement);
    try std.testing.expectEqual(@as(u64, 240), result.value);
    try std.testing.expectEqual(@as(u64, 4), result.other_value);
    try std.testing.expect(!result.agreement.isDefect());
}

// The PM4 truncation disagreement: one report says no truncation, another says
// four anomalies, and both claim to see every packet.
test "two complete observers of one measurement that differ is a contradiction" {
    const statements = [_]Statement{
        .{ .domain = .rosette_gpu, .measurement = .decoded_items, .value = 72, .complete = true, .stated = true },
        .{ .domain = .xenia_command_processor, .measurement = .decoded_items, .value = 68, .complete = true, .stated = true },
    };
    const result = reconcile(&statements);
    try std.testing.expectEqual(Agreement.contradiction, result.agreement);
    try std.testing.expect(result.agreement.isDefect());
    try std.testing.expect(!result.agreement.quotable());
    try std.testing.expect(std.mem.indexOf(u8, result.agreement.describe(), "by preference") != null);
}

test "one observer is usable and uncorroborated, and none is unobserved" {
    const one = [_]Statement{
        .{ .domain = .rosette_gpu, .measurement = .function_entries, .value = 410, .complete = true, .stated = true },
    };
    const single = reconcile(&one);
    try std.testing.expectEqual(Agreement.single, single.agreement);
    try std.testing.expect(single.agreement.quotable());
    try std.testing.expectEqual(@as(u64, 410), single.value);

    const none = [_]Statement{.{ .domain = .rosette_gpu, .stated = false }};
    try std.testing.expectEqual(Agreement.unobserved, reconcile(&none).agreement);
    try std.testing.expect(!Agreement.unobserved.quotable());
}

test "unknown measurements are comparable with nothing, including each other" {
    try std.testing.expect(!Measurement.unknown.comparable(.unknown));
    try std.testing.expect(!Measurement.unknown.comparable(.function_entries));
    try std.testing.expect(Measurement.function_entries.comparable(.function_entries));

    const statements = [_]Statement{
        .{ .domain = .rosette_gpu, .value = 5, .complete = true, .stated = true },
        .{ .domain = .xenia_vulkan, .value = 9, .complete = true, .stated = true },
    };
    try std.testing.expectEqual(Agreement.incomparable, reconcile(&statements).agreement);
}

test "one synthetic edge taints a chain of otherwise authentic ones" {
    try std.testing.expectEqual(
        SourceClass.guest_authentic,
        effectiveAuthenticity(&[_]SourceClass{ .guest_authentic, .guest_authentic }),
    );
    try std.testing.expectEqual(
        SourceClass.host_forwarded,
        effectiveAuthenticity(&[_]SourceClass{ .guest_authentic, .host_forwarded }),
    );
    try std.testing.expectEqual(
        SourceClass.synthetic,
        effectiveAuthenticity(&[_]SourceClass{ .guest_authentic, .synthetic, .guest_authentic }),
    );
    try std.testing.expectEqual(
        SourceClass.diagnostic,
        effectiveAuthenticity(&[_]SourceClass{ .guest_authentic, .diagnostic }),
    );
    try std.testing.expectEqual(SourceClass.unknown, effectiveAuthenticity(&[_]SourceClass{}));
}
