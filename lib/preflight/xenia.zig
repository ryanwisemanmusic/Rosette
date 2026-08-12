//! The preconditions a Xenia run depends on, stated before it starts.
//!
//! Every check here exists because its absence has already cost a debugging
//! session. That is the entry requirement: not "this would be nice to verify"
//! but "this was silently false for hours and the symptom pointed somewhere
//! else". A speculative check is worse than none, because it adds a line to a
//! report whose value depends entirely on every line mattering.
//!
//! The checks are grouped by how the run fails without them:
//!
//!   * **Config binding.** An option declared, written in the config file, and
//!     read back as zero. Nothing traps. Every behaviour that option controls is
//!     simply off, and the log describes the consequence forever.
//!   * **Kernel data shape.** Host-supplied structures the guest walks. A
//!     pointer field seeded with a non-address constant passes every null check
//!     the title makes and faults somewhere unrelated.
//!   * **Graphics binding.** The chain from surface to device to queue. When a
//!     link is synthetic, the counters downstream of it read zero for reasons
//!     that have nothing to do with the guest.
//!   * **Export resolution.** An ordinal the title will call, resolved to
//!     nothing. The call site is thousands of instructions from the failure.
//!
//! Xenia-specific by construction and by intent. The vocabulary here — Vd
//! ordinals, ring buffers, KeDebugMonitorData — has no meaning for another
//! guest, and pretending otherwise would produce an abstraction that fits
//! nothing. `check.zig` is the part that generalises; this is the part that
//! knows what it is looking at.

const std = @import("std");
const check = @import("check.zig");

const Result = check.Result;
const Report = check.Report;
const Severity = check.Severity;

/// What the caller observed about the host graphics stack. Every field is
/// optional-by-default in the sense that a false value means "not established",
/// which the checks translate into the right outcome rather than assuming.
pub const GraphicsObservation = struct {
    /// A native window and its backing layer exist.
    surface_bound: bool = false,
    /// A physical adapter was enumerated and selected.
    physical_device_acquired: bool = false,
    /// A logical device was created on it.
    logical_device_created: bool = false,
    /// A queue capable of submission was obtained.
    submission_queue_ready: bool = false,
    /// Swapchain images exist and are owned by the real driver.
    swapchain_images_native: bool = false,
    /// Whether the runtime could inspect the stack at all. When false, every
    /// field above is meaningless and the checks must say unknown rather than
    /// reading a default as a fact.
    observable: bool = true,
};

/// Config values whose binding has to be confirmed rather than assumed. Each is
/// the pair (what the file says, what the runtime read) — the only form in which
/// a binding failure is visible at all.
pub const ConfigBinding = struct {
    key: []const u8,
    configured: u64,
    observed: u64,
    configured_text: []const u8,
    observed_text: []const u8,
    /// Whether a run without this option is still worth having.
    severity: Severity = .degraded,
};

/// A host-supplied kernel structure field the guest will dereference.
pub const KernelPointerField = struct {
    name: []const u8,
    value: u64,
    /// Values at or below this cannot be addresses. Matches the runtime's own
    /// near-null threshold.
    address_floor: u64 = 0x10000,
    /// Whether the guest is known to dereference it without a null test.
    dereferenced_unchecked: bool = true,
};

/// Graphics is fatal because of what its absence does to everything else: with
/// no device, every counter from swap through present reads zero, and each of
/// those zeros invites an investigation into code that is working correctly.
pub fn checkGraphicsBinding(observation: GraphicsObservation, report: *Report) void {
    if (!observation.observable) {
        report.record(check.indeterminate(
            "gpu-stack-observable",
            "gpu",
            .fatal,
            "the host graphics stack can be inspected before the guest runs",
            "the runtime could not enumerate the graphics stack, so nothing below it can be trusted",
        ));
        return;
    }

    report.record(binary(
        "gpu-surface-bound",
        "gpu",
        .fatal,
        observation.surface_bound,
        "a native window surface is bound",
        "no surface",
        "Without a surface there is nowhere to present. Check window creation and the layer handoff before anything downstream",
    ));

    // The link that has been synthetic in every run so far. It is fatal on its
    // own terms: a synthetic device accepts every call and produces no pixels,
    // so the guest-side counters stay clean while nothing reaches the screen.
    report.record(binary(
        "gpu-physical-device",
        "gpu",
        .fatal,
        observation.physical_device_acquired,
        "a physical adapter is enumerated and selected",
        "no physical adapter acquired; the device layer is synthetic",
        "Until a real adapter is selected, submission and presentation are modelled rather than executed. Every zero downstream of here is caused by this and not by the guest",
    ));

    report.record(binary(
        "gpu-logical-device",
        "gpu",
        .fatal,
        observation.logical_device_created,
        "a logical device is created on the selected adapter",
        "no logical device",
        "Create the device before the guest submits; a modelled device will accept commands and discard them",
    ));

    report.record(binary(
        "gpu-submission-queue",
        "gpu",
        .fatal,
        observation.submission_queue_ready,
        "a queue that can accept submissions is ready",
        "no submission queue",
        "Without a queue, command submission has no destination and swap counters cannot advance for reasons unrelated to the guest",
    ));

    // Not fatal: a run with a modelled swapchain still exercises everything up
    // to presentation, and stopping here would forfeit that.
    report.record(binary(
        "gpu-swapchain-native",
        "gpu",
        .degraded,
        observation.swapchain_images_native,
        "swapchain images are owned by the host driver",
        "swapchain images are modelled",
        "Presentation will be diagnostic rather than authentic. Frames may appear without proving the guest produced them",
    ));
}

/// Confirm each option the runtime reads matches what the configuration says.
pub fn checkConfigBindings(bindings: []const ConfigBinding, report: *Report) void {
    for (bindings) |binding| {
        report.record(check.expectConfigValue(
            "config-bound",
            binding.key,
            binding.configured,
            binding.observed,
            binding.severity,
            binding.configured_text,
            binding.observed_text,
        ));
    }
}

/// Host-seeded pointer fields the guest walks. A small integer here survives
/// every null test the title performs and faults far from the store, with
/// nothing connecting the two.
pub fn checkKernelPointerFields(fields: []const KernelPointerField, report: *Report) void {
    for (fields) |field| {
        if (field.value == 0) {
            // Zero is the documented "not present" encoding, and a title that
            // tests for null handles it. Only flag it where the guest is known
            // not to test.
            if (field.dereferenced_unchecked) {
                report.record(check.violated(
                    "kernel-pointer-null",
                    "kernel",
                    .degraded,
                    "a kernel pointer field the guest dereferences without testing is valid",
                    .{ .expected = "a mapped address", .observed = "0", .source = field.name },
                    "The guest dereferences this without a null test, so zero faults on first use. Either populate it or ensure the structure is never published",
                ));
            } else {
                report.record(check.satisfied("kernel-pointer-null", "kernel", "zero is the absent encoding and the guest tests for it"));
            }
            continue;
        }
        if (field.value <= field.address_floor) {
            report.record(check.violated(
                "kernel-pointer-poisoned",
                "kernel",
                .fatal,
                "a kernel pointer field holds an address rather than a placeholder",
                .{ .expected = "a mapped address", .observed = "a constant below the address floor", .source = field.name },
                "This field is seeded with a small integer, which is not an address. It passes every null test the title makes and then faults on first dereference, far from this store. Seed it with a real address or leave it zero",
            ));
            continue;
        }
        report.record(check.satisfied("kernel-pointer-valid", "kernel", "the field holds a plausible address"));
    }
}

/// An ordinal the title is expected to call, and whether it resolved.
pub const ExportBinding = struct {
    name: []const u8,
    ordinal: u32,
    resolved: bool,
    /// Whether the title cannot proceed without it. Several Vd ordinals are
    /// genuinely optional — a title may own its command ring and never ask for
    /// the system command buffer — and marking those required manufactures a
    /// blocker out of a path the guest was never obliged to take.
    required: bool = true,
};

pub fn checkExports(exports: []const ExportBinding, report: *Report) void {
    for (exports) |entry| {
        if (entry.resolved) {
            report.record(check.satisfied("export-resolved", "kernel", "the ordinal resolves to an implementation"));
            continue;
        }
        report.record(check.violated(
            "export-unresolved",
            "kernel",
            if (entry.required) .fatal else .advisory,
            "an ordinal the title calls resolves to an implementation",
            .{ .expected = "a bound implementation", .observed = "unresolved", .source = entry.name },
            "The call site is thousands of instructions from where this will surface. Bind it now or accept that its failure will be attributed elsewhere",
        ));
    }
}

fn binary(
    id: []const u8,
    subsystem: []const u8,
    severity: Severity,
    holds: bool,
    requirement: []const u8,
    observed: []const u8,
    remedy: []const u8,
) Result {
    if (holds) return check.satisfied(id, subsystem, requirement);
    return check.violated(
        id,
        subsystem,
        severity,
        requirement,
        .{ .expected = "established", .observed = observed },
        remedy,
    );
}

test "a fully bound graphics stack permits launch" {
    var report = Report{};
    checkGraphicsBinding(.{
        .surface_bound = true,
        .physical_device_acquired = true,
        .logical_device_created = true,
        .submission_queue_ready = true,
        .swapchain_images_native = true,
    }, &report);
    try std.testing.expect(report.mayLaunch());
    try std.testing.expect(report.isClean());
}

// The state every run so far has actually been in: a surface and nothing
// beneath it. The gate has to name the device rather than let twenty minutes of
// zero swap counters imply the guest is at fault.
test "a surface without a device blocks and names the device" {
    var report = Report{};
    checkGraphicsBinding(.{ .surface_bound = true }, &report);
    try std.testing.expect(!report.mayLaunch());
    const blocker = report.firstBlocker().?;
    try std.testing.expectEqualStrings("gpu-physical-device", blocker.id);
    try std.testing.expect(std.mem.indexOf(u8, blocker.remedy, "not by the guest") != null);
}

// A modelled swapchain is a real loss and not a reason to refuse the run.
test "a modelled swapchain degrades rather than blocks" {
    var report = Report{};
    checkGraphicsBinding(.{
        .surface_bound = true,
        .physical_device_acquired = true,
        .logical_device_created = true,
        .submission_queue_ready = true,
        .swapchain_images_native = false,
    }, &report);
    try std.testing.expect(report.mayLaunch());
    try std.testing.expectEqual(@as(usize, 1), report.severityTally(.degraded));
}

// An unobservable stack must not read its own defaults as facts.
test "an unobservable graphics stack is unknown rather than broken" {
    var report = Report{};
    checkGraphicsBinding(.{ .observable = false }, &report);
    try std.testing.expectEqual(@as(usize, 1), report.count);
    try std.testing.expectEqual(check.Outcome.indeterminate, report.items()[0].outcome);
    try std.testing.expect(!report.mayLaunch());
}

// The bug that motivated the library: configured 7500, runtime read 0.
test "an option that did not bind is caught before the run" {
    var report = Report{};
    checkConfigBindings(&.{
        .{ .key = "gpu_debug_force_swap_after_ms", .configured = 7500, .observed = 0, .configured_text = "7500", .observed_text = "0" },
        .{ .key = "gpu_log_no_swap_after_ms", .configured = 5000, .observed = 5000, .configured_text = "5000", .observed_text = "5000" },
    }, &report);
    try std.testing.expectEqual(@as(usize, 1), report.tally(.violated));
    try std.testing.expectEqual(@as(usize, 1), report.tally(.satisfied));
    // Degraded by default: a run without the forced probe is still worth having.
    try std.testing.expect(report.mayLaunch());
    try std.testing.expectEqualStrings("gpu_debug_force_swap_after_ms", report.items()[0].evidence.source);
}

// The KeDebugMonitorData shape: offset 0x20 seeded with 1, dereferenced during
// D3D device creation, faulting at guest address 0x00000001.
test "a pointer field seeded with a small constant is fatal" {
    var report = Report{};
    checkKernelPointerFields(&.{
        .{ .name = "KeDebugMonitorData.unk_20", .value = 1 },
        .{ .name = "KeDebugMonitorData.unk_00", .value = 0x3000_2004 },
    }, &report);
    try std.testing.expect(!report.mayLaunch());
    const blocker = report.firstBlocker().?;
    try std.testing.expectEqualStrings("kernel-pointer-poisoned", blocker.id);
    try std.testing.expect(std.mem.indexOf(u8, blocker.remedy, "not an address") != null);
}

test "a null field the guest tests for is not a finding" {
    var report = Report{};
    checkKernelPointerFields(&.{
        .{ .name = "optional", .value = 0, .dereferenced_unchecked = false },
    }, &report);
    try std.testing.expect(report.isClean());
}

// Optional ordinals must not manufacture a blocker: a title may own its command
// ring and never ask for the system command buffer.
test "an unresolved optional export does not block the run" {
    var report = Report{};
    checkExports(&.{
        .{ .name = "VdGetSystemCommandBuffer", .ordinal = 0x1BD, .resolved = false, .required = false },
        .{ .name = "VdSwap", .ordinal = 0x25B, .resolved = true },
    }, &report);
    try std.testing.expect(report.mayLaunch());
    try std.testing.expectEqual(@as(usize, 1), report.tally(.violated));
}

test "an unresolved required export blocks the run" {
    var report = Report{};
    checkExports(&.{
        .{ .name = "VdInitializeRingBuffer", .ordinal = 0x1C3, .resolved = false },
    }, &report);
    try std.testing.expect(!report.mayLaunch());
    try std.testing.expectEqualStrings("VdInitializeRingBuffer", report.firstBlocker().?.evidence.source);
}
