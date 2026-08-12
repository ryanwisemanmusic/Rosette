//! Preconditions checked before a guest application is allowed to run.
//!
//! A translated process fails in two very different ways. It can fail *loudly*
//! — a fault, a decode error, a refused mapping — and the runtime already has
//! machinery for those. Or it can fail *silently*: a configuration value that
//! never bound, an export that resolved to nothing, a graphics device that was
//! never acquired. Nothing traps, nothing logs, and the run proceeds for twenty
//! minutes producing a wall of zeros that describe the consequence and never the
//! cause.
//!
//! The second kind is more expensive by an order of magnitude, and the reason is
//! structural: by the time the symptom appears, the state that would explain it
//! is gone. A ring pointer frozen at zero cannot tell you that the option meant
//! to force it was parsed as 0 instead of 7500 an hour earlier.
//!
//! So this is a gate, not a monitor. Before the guest runs, every precondition
//! that has to hold is stated, evaluated, and reported with what was expected
//! next to what was found. If something the run genuinely depends on is broken,
//! the run stops *there*, where the evidence still exists.
//!
//! ## The distinction that makes it honest
//!
//! Three outcomes, not two. A check that **could not be evaluated** is not a
//! check that passed, and collapsing the two is the failure mode that makes
//! preflight worse than useless — a green report that only means nobody looked.
//! `indeterminate` is therefore a first-class result, it is never counted as
//! success, and a gate configured to require certainty refuses to launch on it.
//!
//! ## Severity is about what to do, not about how bad it feels
//!
//! `fatal` means: continuing produces results that will mislead whoever reads
//! them. That is the whole test. A missing graphics device is fatal not because
//! graphics matter but because every downstream counter will read zero for a
//! reason that has nothing to do with the code being debugged. `degraded` means
//! the run is still worth having and the report has to say what was lost.
//! `advisory` is for facts worth recording that change nothing.
//!
//! Deliberately does not repair. A preflight that fixes what it finds hides the
//! defect and guarantees the next person meets it too.

const std = @import("std");

pub const Severity = enum(u8) {
    /// Continuing would produce misleading results. Stop here, where the
    /// evidence still exists.
    fatal,
    /// The run remains useful but something it would normally do is gone. The
    /// report must name what.
    degraded,
    /// Worth recording, changes nothing.
    advisory,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .fatal => "FATAL",
            .degraded => "DEGRADED",
            .advisory => "ADVISORY",
        };
    }
};

pub const Outcome = enum(u8) {
    /// The precondition holds, and the check could see enough to say so.
    satisfied,
    /// The precondition does not hold.
    violated,
    /// The check could not be evaluated. Not a pass. The most important state
    /// here, because a preflight that reports green when it could not look is
    /// worse than no preflight at all.
    indeterminate,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .satisfied => "ok",
            .violated => "VIOLATED",
            .indeterminate => "UNKNOWN",
        };
    }
};

/// What a check looked at. Kept as expected/observed rather than as a message
/// because the pair is what makes a failure actionable without a second run:
/// "expected 7500, observed 0" ends an investigation that "force swap disabled"
/// would only start.
pub const Evidence = struct {
    expected: []const u8 = "",
    observed: []const u8 = "",
    /// Where the value came from — a config key, an export name, a device
    /// handle. Names the thing to go and fix.
    source: []const u8 = "",

    pub fn hasDetail(self: Evidence) bool {
        return self.expected.len != 0 or self.observed.len != 0;
    }
};

pub const Result = struct {
    /// Stable identifier, kebab-case. Survives rewording of the description, so
    /// it is what tooling and changelogs should key on.
    id: []const u8,
    /// Which part of the runtime this precondition belongs to.
    subsystem: []const u8 = "",
    outcome: Outcome = .indeterminate,
    severity: Severity = .advisory,
    /// One sentence: what must be true, in the present tense.
    requirement: []const u8 = "",
    evidence: Evidence = .{},
    /// What to do about it. Only meaningful when the outcome is not satisfied,
    /// and required for anything fatal — a gate that stops a run without saying
    /// what to change has moved the dead end rather than removed it.
    remedy: []const u8 = "",

    /// Whether this result should stop the launch. Indeterminate counts when
    /// the check is fatal: not knowing whether a load-bearing precondition
    /// holds is not a basis for proceeding.
    pub fn blocksLaunch(self: Result) bool {
        if (self.severity != .fatal) return false;
        return self.outcome != .satisfied;
    }
};

pub const max_results: usize = 64;

/// Accumulates results and answers one question: may this run proceed.
///
/// Fixed capacity and no allocation, because preflight runs before the
/// allocator's own health has been established and a gate that can fail to
/// record a failure is not a gate.
pub const Report = struct {
    results: [max_results]Result = undefined,
    count: usize = 0,
    /// Checks that arrived after capacity. Tracked rather than dropped
    /// silently: an overflowed report is itself a finding.
    overflowed: usize = 0,

    pub fn record(self: *Report, result: Result) void {
        if (self.count >= self.results.len) {
            self.overflowed +|= 1;
            return;
        }
        self.results[self.count] = result;
        self.count += 1;
    }

    pub fn items(self: *const Report) []const Result {
        return self.results[0..self.count];
    }

    pub fn tally(self: *const Report, outcome: Outcome) usize {
        var total: usize = 0;
        for (self.items()) |result| {
            if (result.outcome == outcome) total += 1;
        }
        return total;
    }

    pub fn severityTally(self: *const Report, severity: Severity) usize {
        var total: usize = 0;
        for (self.items()) |result| {
            if (result.severity == severity and result.outcome != .satisfied) total += 1;
        }
        return total;
    }

    /// The first fatal precondition that did not hold. This is the one to fix;
    /// later failures are frequently downstream of it, and reporting them with
    /// equal weight is how a preflight becomes a wall of text nobody reads.
    pub fn firstBlocker(self: *const Report) ?Result {
        for (self.items()) |result| {
            if (result.blocksLaunch()) return result;
        }
        return null;
    }

    pub fn mayLaunch(self: *const Report) bool {
        return self.firstBlocker() == null;
    }

    /// Whether anything at all was less than clean, including advisories. Lets
    /// a caller stay silent on a perfect run without having to enumerate.
    pub fn isClean(self: *const Report) bool {
        if (self.overflowed != 0) return false;
        for (self.items()) |result| {
            if (result.outcome != .satisfied) return false;
        }
        return true;
    }
};

/// Convenience constructors. They exist so a check site reads as the assertion
/// it is making rather than as struct assembly, which is what keeps a hundred
/// of them legible.
pub fn satisfied(id: []const u8, subsystem: []const u8, requirement: []const u8) Result {
    return .{
        .id = id,
        .subsystem = subsystem,
        .outcome = .satisfied,
        .severity = .advisory,
        .requirement = requirement,
    };
}

pub fn violated(
    id: []const u8,
    subsystem: []const u8,
    severity: Severity,
    requirement: []const u8,
    evidence: Evidence,
    remedy: []const u8,
) Result {
    return .{
        .id = id,
        .subsystem = subsystem,
        .outcome = .violated,
        .severity = severity,
        .requirement = requirement,
        .evidence = evidence,
        .remedy = remedy,
    };
}

pub fn indeterminate(
    id: []const u8,
    subsystem: []const u8,
    severity: Severity,
    requirement: []const u8,
    why: []const u8,
) Result {
    return indeterminateAbout(id, subsystem, severity, requirement, why, "");
}

/// The same, naming what the check was about. An unknown result that cannot say
/// which key, export, or handle it could not decide is unactionable — it tells
/// you something is unverified without telling you what, which is the one thing
/// worse than not checking.
pub fn indeterminateAbout(
    id: []const u8,
    subsystem: []const u8,
    severity: Severity,
    requirement: []const u8,
    why: []const u8,
    source: []const u8,
) Result {
    return .{
        .id = id,
        .subsystem = subsystem,
        .outcome = .indeterminate,
        .severity = severity,
        .requirement = requirement,
        .evidence = .{ .observed = why, .source = source },
        .remedy = "Make this check evaluable before trusting the report: an unknown precondition is not a satisfied one",
    };
}

/// Assert an integer configuration value bound to what the configuration file
/// says. The single most common silent failure there is, and the one that cost
/// a week: a value declared, written in the config, and read back as zero with
/// nothing anywhere reporting the gap.
pub fn expectConfigValue(
    id: []const u8,
    key: []const u8,
    expected: u64,
    observed: u64,
    severity: Severity,
    expected_text: []const u8,
    observed_text: []const u8,
) Result {
    if (expected == observed) {
        return .{
            .id = id,
            .subsystem = "config",
            .outcome = .satisfied,
            .severity = .advisory,
            .requirement = "the configured value is the value the runtime reads",
        };
    }
    return .{
        .id = id,
        .subsystem = "config",
        .outcome = .violated,
        .severity = severity,
        .requirement = "the configured value is the value the runtime reads",
        .evidence = .{ .expected = expected_text, .observed = observed_text, .source = key },
        .remedy = "The option did not bind. Check that the key is spelled as the runtime declares it, that its section header matches, and that no later assignment overrides it. Until it binds, every behaviour it controls is off regardless of what the file says",
    };
}

// An unknown that cannot name its subject is unactionable: it reports that
// something is unverified without saying what.
test "an indeterminate result carries the thing it could not decide" {
    const result = indeterminateAbout("id", "config", .fatal, "req", "no reading yet", "gpu_debug_force_swap_after_ms");
    try std.testing.expectEqualStrings("gpu_debug_force_swap_after_ms", result.evidence.source);
    try std.testing.expectEqual(Outcome.indeterminate, result.outcome);
}

test "a fatal violation blocks launch and an advisory one does not" {
    var report = Report{};
    report.record(violated("a", "gpu", .advisory, "r", .{}, "fix"));
    try std.testing.expect(report.mayLaunch());
    report.record(violated("b", "gpu", .fatal, "r", .{}, "fix"));
    try std.testing.expect(!report.mayLaunch());
    try std.testing.expectEqualStrings("b", report.firstBlocker().?.id);
}

// The distinction the whole library rests on. A check that could not run has
// told you nothing, and treating it as a pass is how a green report comes to
// mean "nobody looked".
test "an unevaluable fatal precondition is not a pass" {
    var report = Report{};
    report.record(indeterminate("probe", "gpu", .fatal, "device is acquirable", "no adapter enumerated"));
    try std.testing.expect(!report.mayLaunch());
    try std.testing.expectEqual(Outcome.indeterminate, report.items()[0].outcome);
    try std.testing.expectEqual(@as(usize, 0), report.tally(.satisfied));
}

// The same uncertainty about something the run does not depend on must not stop
// it, or the gate becomes noise and gets disabled.
test "an unevaluable advisory precondition does not block" {
    var report = Report{};
    report.record(indeterminate("probe", "audio", .advisory, "mixer present", "no device"));
    try std.testing.expect(report.mayLaunch());
    try std.testing.expect(!report.isClean());
}

// The exact failure this library was written for: an option present in the
// config file and read back as zero, with nothing reporting the gap.
test "a config value that did not bind is reported against its key" {
    const result = expectConfigValue(
        "gpu-force-swap-bound",
        "gpu_debug_force_swap_after_ms",
        7500,
        0,
        .degraded,
        "7500",
        "0",
    );
    try std.testing.expectEqual(Outcome.violated, result.outcome);
    try std.testing.expectEqualStrings("gpu_debug_force_swap_after_ms", result.evidence.source);
    try std.testing.expectEqualStrings("7500", result.evidence.expected);
    try std.testing.expectEqualStrings("0", result.evidence.observed);
    try std.testing.expect(std.mem.indexOf(u8, result.remedy, "did not bind") != null);
}

test "a config value that bound is satisfied and silent" {
    const result = expectConfigValue("k", "key", 7500, 7500, .fatal, "7500", "7500");
    try std.testing.expectEqual(Outcome.satisfied, result.outcome);
    try std.testing.expect(!result.blocksLaunch());
}

// The first fatal failure is the one to fix; later ones are usually downstream.
// Reporting them with equal weight is how a gate becomes a wall of text.
test "the first blocker is the one reported, in registration order" {
    var report = Report{};
    report.record(satisfied("ok", "cpu", "r"));
    report.record(violated("first", "gpu", .fatal, "r", .{}, "fix"));
    report.record(violated("second", "gpu", .fatal, "r", .{}, "fix"));
    try std.testing.expectEqualStrings("first", report.firstBlocker().?.id);
    try std.testing.expectEqual(@as(usize, 2), report.severityTally(.fatal));
}

test "a clean report is clean and an overflowed one never is" {
    var report = Report{};
    report.record(satisfied("a", "cpu", "r"));
    try std.testing.expect(report.isClean());

    var full = Report{};
    var index: usize = 0;
    while (index < max_results + 3) : (index += 1) {
        full.record(satisfied("a", "cpu", "r"));
    }
    try std.testing.expectEqual(max_results, full.count);
    try std.testing.expectEqual(@as(usize, 3), full.overflowed);
    // Every recorded result passed, yet the report is not clean: the ones that
    // did not fit are unaccounted for, and unaccounted is not passing.
    try std.testing.expect(!full.isClean());
}

test "severity tallies count only what failed" {
    var report = Report{};
    report.record(satisfied("a", "gpu", "r"));
    report.record(violated("b", "gpu", .degraded, "r", .{}, "fix"));
    report.record(violated("c", "gpu", .degraded, "r", .{}, "fix"));
    try std.testing.expectEqual(@as(usize, 2), report.severityTally(.degraded));
    try std.testing.expectEqual(@as(usize, 0), report.severityTally(.fatal));
    try std.testing.expectEqual(@as(usize, 1), report.tally(.satisfied));
}
