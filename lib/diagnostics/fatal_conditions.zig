//! Stop the run at the line that decided it.
//!
//! The defect this exists for
//! --------------------------
//! A run whose outcome is already settled keeps going. The emulator refuses its
//! own authentic start at step forty million and Rosette translates another
//! ninety million instructions of a title that will never be admitted, writing
//! thousands of lines of downstream zeros — no ring, no draws, no frames. Every
//! one of those is true, none is the finding, and the reader walks back through
//! all of it to reach the one line that mattered.
//!
//! The refusal was never ambiguous. What was missing was the step from "this
//! line was printed" to "so stop".
//!
//! ## Why this hangs off the log rather than the code
//!
//! Most terminal conditions are the emulator's own words, printed from inside
//! translated guest code Rosette has no call into. The line is the only place
//! the two sides meet. Matching it is not a workaround for absent
//! instrumentation — it is the instrumentation, and it costs one character-set
//! test per line against a comptime filter.
//!
//! ## Where the hook sits, and why that matters
//!
//! At the *end* of the logging funnel, after the shared format buffer is no
//! longer live. Observing earlier would mean the fault's own diagnostics
//! overwrite the line still being written by the call that triggered them. A
//! re-entry guard covers the rest: the fault block names conditions by label
//! and never echoes their text, so it cannot match itself, but the guard is
//! there because relying on that would be relying on wording.

const std = @import("std");
const map = @import("xenia_fatal_condition_map");
const event_log = @import("event_log");
const machoCapturePrint = event_log.machoCapturePrint;
const async_log = @import("async_log.zig");

pub const Condition = map.Condition;
pub const Owner = map.Owner;
pub const conditions = map.conditions;

/// Where the run was when a condition was detected.
///
/// A terminal line says *what* went wrong. It cannot say where the machine was
/// standing when it did, and for a condition printed from inside translated
/// guest code that is the difference between a verdict and a lead: the nearest
/// symbol and the section around the instruction pointer are what turn "the
/// emulator refused" into "it refused from here".
pub const FaultContext = struct {
    valid: bool = false,
    step: u64 = 0,
    rip: u64 = 0,
    thread: u64 = 0,
    /// Nearest preceding symbol to `rip`, and how far past it we are.
    symbol: []const u8 = "",
    symbol_offset: u64 = 0,
    /// Mach-O section containing `rip`, when it is inside the image at all.
    section: []const u8 = "",
    /// Whether `rip` is in the image, unsymbolized, or outside it entirely.
    address_kind: []const u8 = "",
};

/// Supplies the machine context. Installed by the process, which is the only
/// thing that can see registers and the loaded image.
pub const ContextProviderFn = *const fn () FaultContext;

pub const Policy = enum {
    /// Stop at the first condition that is not allowed.
    fault,
    /// Record and report every condition, stop for none.
    warn,
    /// Do not match at all.
    observe,

    pub fn label(self: Policy) []const u8 {
        return switch (self) {
            .fault => "fault",
            .warn => "warn",
            .observe => "observe",
        };
    }
};

pub fn policyFromText(text: ?[]const u8) Policy {
    const value = text orelse return .fault;
    if (std.mem.eql(u8, value, "warn")) return .warn;
    if (std.mem.eql(u8, value, "observe")) return .observe;
    return .fault;
}

/// Longest allow-list this accepts. The vocabulary is one label per condition,
/// so the bound is generous by construction.
pub const allow_text_limit: usize = 512;

pub const Ledger = struct {
    policy: Policy = .fault,
    allow_buffer: [allow_text_limit]u8 = [_]u8{0} ** allow_text_limit,
    allow_length: usize = 0,
    observed: u32 = 0,
    allowed_observations: u32 = 0,
    first: ?Condition = null,
    first_allowed: ?Condition = null,
    /// Occurrences of each condition, so one that is only decisive after
    /// repeating can count without a second ledger.
    seen: [map.conditions.len]u32 = [_]u32{0} ** map.conditions.len,

    pub fn configure(self: *Ledger, new_policy: Policy, allow: ?[]const u8) void {
        self.policy = new_policy;
        self.allow_length = 0;
        if (allow) |text| {
            const length = @min(text.len, self.allow_buffer.len);
            @memcpy(self.allow_buffer[0..length], text[0..length]);
            self.allow_length = length;
        }
    }

    pub fn allowText(self: *const Ledger) []const u8 {
        return self.allow_buffer[0..self.allow_length];
    }

    /// Whether a label appears in the allow-list.
    ///
    /// Separators are comma or whitespace so an operator can paste either
    /// shape. Matching is whole-token: a label is never satisfied by being a
    /// prefix of another, because "graphics-setup-failed" containing
    /// "graphics-setup" would silently exempt more than was asked for.
    pub fn allows(self: *const Ledger, label: []const u8) bool {
        if (label.len == 0) return false;
        var tokens = std.mem.tokenizeAny(u8, self.allowText(), ", \t\r\n");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, label)) return true;
        }
        return false;
    }

    /// Classify one line. Returns the condition when the run should stop for
    /// it, and null otherwise — including when it matched but was allowed.
    /// Occurrences of one condition so far, by label.
    pub fn seenFor(self: *const Ledger, label: []const u8) u32 {
        for (map.conditions, 0..) |condition, index| {
            if (std.mem.eql(u8, condition.label, label)) return self.seen[index];
        }
        return 0;
    }

    pub fn observe(self: *Ledger, line: []const u8) ?Condition {
        if (self.policy == .observe) return null;
        const matched = map.matchIndex(line) orelse return null;
        const condition = map.conditions[matched];
        self.observed +|= 1;
        self.seen[matched] +|= 1;
        if (self.first == null) self.first = condition;
        if (self.allows(condition.label)) {
            self.allowed_observations +|= 1;
            if (self.first_allowed == null) self.first_allowed = condition;
            return null;
        }
        // A condition that is only decisive after repeating stays a warning
        // until its threshold. Counting still happens, so the eventual stop
        // can say how many it took.
        if (self.seen[matched] < condition.repeats) return null;
        return if (self.policy == .fault) condition else null;
    }
};

// The ledger is process-wide because the logging funnel is. Threading a
// context through every diagnostic call site to reach it would put the
// plumbing everywhere the condition is not.
var ledger: Ledger = .{};
var armed: bool = false;
var reporting: bool = false;
var stopped: bool = false;
var context_provider: ?ContextProviderFn = null;

pub fn setContextProvider(provider: ?ContextProviderFn) void {
    context_provider = provider;
}

pub fn configure(new_policy: Policy, allow: ?[]const u8) void {
    ledger.configure(new_policy, allow);
}

pub fn policy() Policy {
    return ledger.policy;
}

pub fn observedCount() u32 {
    return ledger.observed;
}

pub fn firstObserved() ?Condition {
    return ledger.first;
}

/// Begin watching the log. Idempotent.
pub fn arm() void {
    if (armed) return;
    armed = true;
    event_log.setLineObserver(observeLine);
    machoCapturePrint(
        "macho-processor: FATAL CONDITIONS: armed policy={s} conditions={d} allow=[{s}] (ROSETTE_FATAL_CONDITIONS=fault|warn|observe, ROSETTE_FATAL_CONDITIONS_ALLOW=<labels>); a line whose presence means the outcome is already decided stops the run where it was decided rather than thousands of lines downstream of it\n",
        .{
            ledger.policy.label(),
            map.conditions.len,
            if (ledger.allow_length == 0) "<none>" else ledger.allowText(),
        },
    );
    // Enumerated up front rather than only at the stop.
    //
    // A count says four conditions are watched and leaves the reader unable to
    // predict which one will fire, or to tell a condition that never occurred
    // from one that is not in the table at all. Listing them also puts every
    // allow-list label in the log, so stepping past one does not require
    // reading the source to find out what it is called.
    for (map.conditions) |condition| {
        machoCapturePrint(
            "  condition {s} owner={s} allowed={s} fatal_after={d} watches=\"{s}\"{s}{s}\n",
            .{
                condition.label,
                condition.owner.label(),
                if (ledger.allows(condition.label)) "YES" else "NO",
                condition.repeats,
                condition.text,
                if (condition.also.len != 0) " and " else "",
                condition.also,
            },
        );
        machoCapturePrint("    remedy: {s}\n", .{condition.remedy});
    }
}

/// The logging funnel's observer. Runs after the shared format buffer is done
/// with, so reporting from here is safe.
fn observeLine(line: []const u8) void {
    if (reporting or stopped) return;
    const condition = ledger.observe(line) orelse return;
    reporting = true;
    terminate(condition);
}

fn terminate(condition: Condition) void {
    stopped = true;
    machoCapturePrint(
        "macho-processor: FATAL CONDITION: label={s} owner={s} policy={s} observed={d} occurrences={d}/{d}; the run stops here because no later line can change this outcome\n",
        .{
            condition.label,
            condition.owner.label(),
            ledger.policy.label(),
            ledger.observed,
            ledger.seenFor(condition.label),
            condition.repeats,
        },
    );
    machoCapturePrint("macho-processor: FATAL CONDITION: {s}\n", .{condition.remedy});
    if (context_provider) |provide| {
        const context = provide();
        if (context.valid) {
            machoCapturePrint(
                "macho-processor: FATAL CONDITION: at step={d} rip=0x{x} thread=0x{x} kind={s} section={s} symbol={s}+0x{x}\n",
                .{
                    context.step,
                    context.rip,
                    context.thread,
                    if (context.address_kind.len == 0) "<unknown>" else context.address_kind,
                    if (context.section.len == 0) "<none>" else context.section,
                    if (context.symbol.len == 0) "<unsymbolized>" else context.symbol,
                    context.symbol_offset,
                },
            );
        } else {
            machoCapturePrint(
                "macho-processor: FATAL CONDITION: no machine context was available; the condition was detected before the image was readable or outside guest execution\n",
                .{},
            );
        }
    }
    // How much of this log actually reached the file. A gate that raises a
    // signal never reaches the normal shutdown path that prints these, so on
    // exactly the runs where a reader is about to conclude "X never happened",
    // the number saying whether X could have been dropped would be missing.
    const transport = async_log.transportStats();
    machoCapturePrint(
        "macho-processor: FATAL CONDITION: log integrity={s} accepted={d} dropped={d} truncated={d} written={d} queued={d}; {s}\n",
        .{
            transport.integrity().label(),
            transport.accepted,
            transport.dropped,
            transport.truncated,
            transport.written,
            transport.queued,
            transport.integrity().guidance(),
        },
    );
    machoCapturePrint(
        "macho-processor: FATAL CONDITION: raising SIGSEGV so the crash report names this condition. Set ROSETTE_FATAL_CONDITIONS_ALLOW={s} to step past this one and reach the next, ROSETTE_FATAL_CONDITIONS=warn to record every condition without stopping, or observe to disarm the watch\n",
        .{condition.label},
    );
    event_log.flushAsyncTransport();
    _ = std.c.raise(std.c.SIG.SEGV);
}

test "a terminal line stops the run and an ordinary one does not" {
    var local = Ledger{};
    local.configure(.fault, null);
    try std.testing.expect(local.observe("macho-processor: AUDIT INPUTS: hashing progress") == null);
    const stop = local.observe("[xenia] !> ROSETTE ADMISSION: refusing authentic guest start because ...") orelse
        return error.ShouldStop;
    try std.testing.expectEqualStrings("guest-admission-refused", stop.label);
    try std.testing.expectEqual(@as(u32, 1), local.observed);
}

test "warn records every condition and stops for none" {
    var local = Ledger{};
    local.configure(.warn, null);
    try std.testing.expect(local.observe("[xenia] !> Failed to setup emulator: C000000D") == null);
    try std.testing.expect(local.observe("[xenia] !> Setup: Failed to setup graphics_system!") == null);
    // Recorded, just not acted on — which is the whole difference from observe.
    try std.testing.expectEqual(@as(u32, 2), local.observed);
    try std.testing.expect(local.first != null);
}

test "observe does not even match, so it costs nothing" {
    var local = Ledger{};
    local.configure(.observe, null);
    try std.testing.expect(local.observe("[xenia] !> Failed to setup emulator: C000000D") == null);
    try std.testing.expectEqual(@as(u32, 0), local.observed);
    try std.testing.expect(local.first == null);
}

test "an allowed condition is recorded, reported and stepped past" {
    var local = Ledger{};
    local.configure(.fault, "device-entry-point-absent");
    try std.testing.expect(local.observe("macho-processor: ensureRealDeviceFnPtrs: absent on this device: vkCmdBeginConditionalRenderingEXT") == null);
    try std.testing.expectEqual(@as(u32, 1), local.observed);
    try std.testing.expectEqual(@as(u32, 1), local.allowed_observations);
    try std.testing.expectEqualStrings("device-entry-point-absent", local.first_allowed.?.label);
    // Allowing one does not disarm the others.
    const stop = local.observe("[xenia] !> Failed to setup emulator: C000000D") orelse
        return error.ShouldStop;
    try std.testing.expectEqualStrings("emulator-setup-failed", stop.label);
}

test "an allow-list entry never matches by prefix" {
    var local = Ledger{};
    // "graphics-setup" is a prefix of the real label and must not exempt it:
    // an operator who mistypes a label should get the stop, not a silent pass.
    local.configure(.fault, "graphics-setup");
    try std.testing.expect(!local.allows("graphics-setup-failed"));
    const stop = local.observe("[xenia] !> Setup: Failed to setup graphics_system!") orelse
        return error.ShouldStop;
    try std.testing.expectEqualStrings("graphics-setup-failed", stop.label);
}

test "an allow-list accepts commas or whitespace" {
    var local = Ledger{};
    local.configure(.fault, "emulator-setup-failed, graphics-setup-failed");
    try std.testing.expect(local.allows("emulator-setup-failed"));
    try std.testing.expect(local.allows("graphics-setup-failed"));
    try std.testing.expect(!local.allows("guest-admission-refused"));

    var spaced = Ledger{};
    spaced.configure(.fault, "emulator-setup-failed graphics-setup-failed");
    try std.testing.expect(spaced.allows("graphics-setup-failed"));
    try std.testing.expect(!spaced.allows(""));
}

test "the policy default is to stop" {
    try std.testing.expectEqual(Policy.fault, policyFromText(null));
    try std.testing.expectEqual(Policy.fault, policyFromText("fault"));
    try std.testing.expectEqual(Policy.warn, policyFromText("warn"));
    try std.testing.expectEqual(Policy.observe, policyFromText("observe"));
    // An unreadable value must not silently disarm the gate.
    try std.testing.expectEqual(Policy.fault, policyFromText("nonsense"));
}

test "an over-long allow list is truncated rather than overrunning" {
    var local = Ledger{};
    const long = [_]u8{'a'} ** (allow_text_limit * 2);
    local.configure(.fault, &long);
    try std.testing.expectEqual(allow_text_limit, local.allowText().len);
}

test "a fault context is reported only when the provider says it is valid" {
    var local = Ledger{};
    local.configure(.fault, null);
    // The ledger itself carries no context; the provider is the process's, and
    // an invalid one must be reported as absent rather than printed as zeros
    // that read like a real instruction pointer at address zero.
    const empty = FaultContext{};
    try std.testing.expect(!empty.valid);
    try std.testing.expectEqual(@as(u64, 0), empty.rip);
    try std.testing.expectEqualStrings("", empty.symbol);
}

// A repeating condition counts before it convicts.
//
// The zero-refresh watchdog fired 42 times in the 2026-09-08 run. Stopping on
// the first would have ended healthy bootstraps, which is why nothing stopped
// on it at all; the threshold is what makes the fortieth mean something the
// first did not.
test "a repeating condition stops only once its threshold is reached" {
    var counting = Ledger{};
    counting.configure(.fault, null);
    const watchdog = map.conditionForLabel("output-never-refreshed").?;
    const firing = "[xenia] w> DEBUG: ZERO-REFRESH WATCHDOG: vblank_id=7 " ++
        "refresh_attempt_count=0 refresh_success_count=0";

    var fired: u32 = 1;
    while (fired < watchdog.repeats) : (fired += 1) {
        try std.testing.expectEqual(@as(?Condition, null), counting.observe(firing));
    }
    // Every one of those was still recorded, so the stop can say what it took.
    try std.testing.expectEqual(watchdog.repeats - 1, counting.seenFor("output-never-refreshed"));

    const stop = counting.observe(firing) orelse return error.ThresholdShouldConvict;
    try std.testing.expectEqualStrings("output-never-refreshed", stop.label);
    try std.testing.expectEqual(watchdog.repeats, counting.seenFor("output-never-refreshed"));

    // A one-shot condition is unaffected: it convicts on its first line.
    var refusal = Ledger{};
    refusal.configure(.fault, null);
    const refused = refusal.observe("ROSETTE ADMISSION: refusing authentic guest start") orelse
        return error.RefusalShouldConvict;
    try std.testing.expectEqualStrings("guest-admission-refused", refused.label);

    // The allow-list still short-circuits before the threshold is consulted,
    // so stepping past a repeating condition does not require waiting for it.
    var allowed = Ledger{};
    allowed.configure(.fault, "output-never-refreshed");
    var index: u32 = 0;
    while (index < watchdog.repeats + 4) : (index += 1) {
        try std.testing.expectEqual(@as(?Condition, null), allowed.observe(firing));
    }
    try std.testing.expect(allowed.allowed_observations > watchdog.repeats);

    // Counts are per condition: one condition's repetitions never advance
    // another's threshold.
    var mixed = Ledger{};
    mixed.configure(.fault, null);
    _ = mixed.observe(firing);
    try std.testing.expectEqual(@as(u32, 0), mixed.seenFor("graphics-setup-failed"));
}
