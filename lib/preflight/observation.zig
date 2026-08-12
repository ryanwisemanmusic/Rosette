//! Preflight facts gathered from outside the guest.
//!
//! The obvious way to build a health gate is to have the application report its
//! own health. That is also the wrong way, for two reasons. It requires editing
//! the application — so the runtime's diagnostics become a patch set that has to
//! be carried against every version — and it trusts the very component whose
//! correctness is in question. An application whose config never bound will
//! cheerfully report that its config bound.
//!
//! Rosette is already positioned to do better. It is the thing that maps the
//! image, resolves the imports, owns the memory, forwards the graphics calls and
//! captures the output. Every fact preflight needs is already crossing a
//! boundary Rosette controls. Nothing has to be added to the guest, because
//! nothing about the guest has to be asked.
//!
//! ## The observation that makes this work
//!
//! For a configured value, two independent readings exist and Rosette sees both:
//!
//!   * what the **configuration file** says, read from the bytes the guest
//!     opened — Rosette serviced that open;
//!   * what the **guest itself believes**, read from the configuration dump the
//!     guest prints at startup — Rosette captured that output.
//!
//! When those disagree, the option did not bind, and the disagreement is visible
//! without asking the guest anything and without trusting its answer. That is a
//! stronger check than an in-process assertion could be: an in-process check
//! reads one storage location and cannot notice that the file said something
//! else.
//!
//! The same shape applies throughout. A graphics device is "acquired" because
//! Rosette forwarded a real creation call and got a real handle back, not
//! because the guest thinks so. An ordinal is resolved because Rosette's own
//! import table says so. A kernel structure field holds a poisoned constant
//! because Rosette watched the store that put it there.
//!
//! ## Consequence for where this runs
//!
//! Because every source is a Rosette boundary, preflight has no single natural
//! moment — the facts arrive as the guest reaches them. So the collector is
//! incremental: facts are deposited as they are observed, and the gate is
//! evaluated at named phases. A phase that arrives with a fact still unobserved
//! reports `indeterminate` for it, which is exactly right and is why that
//! outcome exists.

const std = @import("std");
const check = @import("check.zig");
const xenia = @import("xenia.zig");

/// When the gate is evaluated. Each phase can only judge what is knowable by
/// then; judging earlier produces false alarms and judging later wastes the run.
pub const Phase = enum(u8) {
    /// Image mapped, imports resolved, before any guest code runs. Export
    /// resolution and image integrity are decidable here and nothing else is.
    image_ready,
    /// The guest has read its configuration and printed what it believes.
    /// Config binding becomes decidable.
    configuration_loaded,
    /// The guest has begun bringing up graphics. Device and queue binding
    /// become decidable.
    graphics_bringup,

    pub fn label(self: Phase) []const u8 {
        return switch (self) {
            .image_ready => "image_ready",
            .configuration_loaded => "configuration_loaded",
            .graphics_bringup => "graphics_bringup",
        };
    }
};

/// One configured option, as seen from both sides of the boundary.
pub const ConfigReading = struct {
    key: []const u8,
    /// Parsed from the configuration file Rosette serviced the open for.
    file_value: []const u8 = "",
    file_present: bool = false,
    /// Parsed from the guest's own startup dump, captured from guest stdout.
    guest_value: []const u8 = "",
    guest_present: bool = false,
    /// Whether a run without this option is still worth having.
    severity: check.Severity = .degraded,
};

/// Everything the collector has been told, deposited as Rosette observes it.
/// Nothing here is asked of the guest.
pub const Sources = struct {
    /// Config readings gathered so far. Bounded: preflight must not allocate.
    config: []const ConfigReading = &.{},
    /// Whether the guest's configuration dump has been captured yet. Until it
    /// has, config binding is unknown rather than fine.
    guest_dump_captured: bool = false,
    /// Whether the configuration file itself was read. If Rosette never
    /// serviced that open, there is nothing to compare against.
    config_file_read: bool = false,

    graphics: xenia.GraphicsObservation = .{},
    exports: []const xenia.ExportBinding = &.{},
    kernel_fields: []const xenia.KernelPointerField = &.{},
};

/// Compare a configured option against what the guest believes it is.
///
/// This is the check that no in-process assertion can make: the guest reads one
/// storage location, and an assertion inside it can only confirm that location
/// agrees with itself. Only an observer holding both readings can see that the
/// file said 7500 and the process is running on 0.
pub fn checkConfigAgreement(reading: ConfigReading, dump_captured: bool, file_read: bool) check.Result {
    if (!file_read) {
        return check.indeterminateAbout(
            "config-agreement",
            "config",
            reading.severity,
            "the value the guest runs on is the value its configuration file declares",
            "the configuration file was never read through this runtime, so there is nothing to compare against",
            reading.key,
        );
    }
    if (!dump_captured) {
        return check.indeterminateAbout(
            "config-agreement",
            "config",
            reading.severity,
            "the value the guest runs on is the value its configuration file declares",
            "the guest has not printed its own effective configuration, so its belief is unknown",
            reading.key,
        );
    }
    if (!reading.file_present) {
        // The file does not mention it, so the guest is running on a compiled
        // default. That is not a defect; it is worth recording only because a
        // default that differs from expectations reads identically to a binding
        // failure in every downstream symptom.
        return check.satisfied("config-agreement", "config", "the option is absent from the file and the guest runs on its default");
    }
    if (!reading.guest_present) {
        return check.violated(
            "config-agreement",
            "config",
            reading.severity,
            "the value the guest runs on is the value its configuration file declares",
            .{ .expected = reading.file_value, .observed = "absent from the guest's own dump", .source = reading.key },
            "The file sets this option and the guest does not list it at all. The key is not one the guest declares — check its spelling against the runtime's own option table",
        );
    }
    if (std.mem.eql(u8, reading.file_value, reading.guest_value)) {
        return check.satisfied("config-agreement", "config", "the file and the guest agree on this option");
    }
    return check.violated(
        "config-agreement",
        "config",
        reading.severity,
        "the value the guest runs on is the value its configuration file declares",
        .{ .expected = reading.file_value, .observed = reading.guest_value, .source = reading.key },
        "The file and the guest disagree. Either the option bound to a different storage location than the one the code reads — a duplicate definition of the same name in two translation units does this — or a later assignment overrode it. Until they agree, every behaviour this option controls is off regardless of the file",
    );
}

/// Evaluate everything decidable at `phase`. Facts not yet observable are
/// reported as indeterminate rather than skipped: a gate that quietly omits what
/// it could not see is the same green-means-nothing failure the library exists
/// to prevent.
pub fn evaluate(phase: Phase, sources: Sources, report: *check.Report) void {
    // Decidable as soon as the image is mapped.
    xenia.checkExports(sources.exports, report);
    xenia.checkKernelPointerFields(sources.kernel_fields, report);
    if (phase == .image_ready) return;

    for (sources.config) |reading| {
        report.record(checkConfigAgreement(reading, sources.guest_dump_captured, sources.config_file_read));
    }
    if (phase == .configuration_loaded) return;

    xenia.checkGraphicsBinding(sources.graphics, report);
}

// The bug this whole library was built for, caught without touching the guest:
// the file says 7500, the process is running on 0.
test "a file and guest disagreement is caught from outside the guest" {
    const result = checkConfigAgreement(.{
        .key = "gpu_debug_force_swap_after_ms",
        .file_value = "7500",
        .file_present = true,
        .guest_value = "0",
        .guest_present = true,
    }, true, true);
    try std.testing.expectEqual(check.Outcome.violated, result.outcome);
    try std.testing.expectEqualStrings("7500", result.evidence.expected);
    try std.testing.expectEqualStrings("0", result.evidence.observed);
    try std.testing.expect(std.mem.indexOf(u8, result.remedy, "duplicate definition") != null);
}

test "agreement is satisfied and silent" {
    const result = checkConfigAgreement(.{
        .key = "gpu_log_no_swap_after_ms",
        .file_value = "5000",
        .file_present = true,
        .guest_value = "5000",
        .guest_present = true,
    }, true, true);
    try std.testing.expectEqual(check.Outcome.satisfied, result.outcome);
}

// An option the file never sets is not a binding failure. Saying otherwise would
// flag every compiled default in the program.
test "an option absent from the file is not a binding failure" {
    const result = checkConfigAgreement(.{ .key = "k", .file_present = false }, true, true);
    try std.testing.expectEqual(check.Outcome.satisfied, result.outcome);
}

// A key the file sets and the guest has never heard of is a spelling error, and
// it is invisible from inside the guest by construction.
test "a key the guest does not declare is reported against the file" {
    const result = checkConfigAgreement(.{
        .key = "gpu_debug_force_swp_after_ms",
        .file_value = "7500",
        .file_present = true,
        .guest_present = false,
    }, true, true);
    try std.testing.expectEqual(check.Outcome.violated, result.outcome);
    try std.testing.expect(std.mem.indexOf(u8, result.remedy, "spelling") != null);
}

// Before either reading exists, the honest answer is "unknown" — never "fine".
test "config agreement is unknown until both readings exist" {
    const no_file = checkConfigAgreement(.{ .key = "k", .file_present = true, .file_value = "1" }, true, false);
    try std.testing.expectEqual(check.Outcome.indeterminate, no_file.outcome);
    const no_dump = checkConfigAgreement(.{ .key = "k", .file_present = true, .file_value = "1" }, false, true);
    try std.testing.expectEqual(check.Outcome.indeterminate, no_dump.outcome);
}

// Each phase judges only what is knowable by then. Judging graphics at
// image_ready would fail every run for a reason that is not yet true.
test "phases judge only what is decidable by then" {
    const sources = Sources{
        .exports = &.{.{ .name = "VdSwap", .ordinal = 0x25B, .resolved = true }},
        .config = &.{.{ .key = "k", .file_present = true, .file_value = "7500", .guest_present = true, .guest_value = "0" }},
        .config_file_read = true,
        .guest_dump_captured = true,
        .graphics = .{ .surface_bound = true },
    };

    var early = check.Report{};
    evaluate(.image_ready, sources, &early);
    try std.testing.expectEqual(@as(usize, 1), early.count);
    try std.testing.expect(early.mayLaunch());

    var mid = check.Report{};
    evaluate(.configuration_loaded, sources, &mid);
    try std.testing.expectEqual(@as(usize, 2), mid.count);
    // The binding failure is degraded by default, so it does not stop the run.
    try std.testing.expect(mid.mayLaunch());
    try std.testing.expectEqual(@as(usize, 1), mid.tally(.violated));

    var late = check.Report{};
    evaluate(.graphics_bringup, sources, &late);
    // A surface with no device beneath it is fatal, and only visible this late.
    try std.testing.expect(!late.mayLaunch());
    try std.testing.expectEqualStrings("gpu-physical-device", late.firstBlocker().?.id);
}
