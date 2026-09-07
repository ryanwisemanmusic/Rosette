//! Route-independent: log lines that mean the run cannot succeed.
//!
//! The defect this exists for
//! --------------------------
//! A run that has already failed keeps going. The emulator refuses its own
//! authentic start at step forty million, and Rosette translates another
//! ninety million instructions of a title that will never be admitted, writing
//! four thousand lines of downstream zeros: no ring, no draws, no frames. Every
//! one of those zeros is true and none of them is the finding, and the reader
//! has to walk back through all of it to reach the one line that mattered.
//!
//! The refusal is not ambiguous. It says so. What was missing is the step from
//! "this line was printed" to "so stop", and this table is that step: a line
//! whose presence means no later evidence can change the outcome.
//!
//! ## Why the log line and not the code that emits it
//!
//! Most of these are the emulator's own words, printed from inside translated
//! guest code that Rosette has no call into. The line is the only place the two
//! sides meet. Matching it is not a workaround for missing instrumentation —
//! it *is* the instrumentation, and it costs one character-set test per line.
//!
//! ## What belongs here
//!
//! A condition earns an entry when its presence means the run's outcome is
//! already decided. Not "something looks wrong" — a run with a warning may
//! still produce a frame, and stopping it would trade a real result for a
//! tidy one. The test is whether any later line could change the verdict.
//!
//! ## What this package is not
//!
//! It reads no log and stops no run. It is handed a line and says whether that
//! line is terminal; the policy, the ledger and the stop live in lib.

const std = @import("std");
const phrase_filter = @import("phrase_filter");

/// Who has to fix the condition. A stop that cannot say whose problem it is
/// sends the operator looking in the wrong tree.
pub const Owner = enum {
    /// The emulator's own build: its source, its parsing, its setup order.
    emulator_build,
    /// The title, or the media it was read from.
    guest_title,
    /// Rosette itself.
    rosette_harness,
    /// The host's driver or device.
    host_driver,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .emulator_build => "emulator:build",
            .guest_title => "guest:title",
            .rosette_harness => "rosette:harness",
            .host_driver => "host:driver",
        };
    }
};

pub const Condition = struct {
    /// Short, stable name. This is what an operator puts in the allow-list to
    /// step past one condition without disarming the rest.
    label: []const u8,
    /// Substring that identifies the condition in a log line.
    text: []const u8,
    /// A second substring that must also be present, for a phrase that is only
    /// unambiguous as a pair.
    also: []const u8 = "",
    owner: Owner,
    /// What the operator has to do about it. Written as an instruction, not a
    /// restatement of the error.
    remedy: []const u8,
};

/// Conditions that end a run.
///
/// Ordered most-specific first: the emulator reports a refusal and then reports
/// the two failures it caused, so the refusal has to match before them or the
/// stop would name a consequence as the cause.
pub const conditions = [_]Condition{
    .{
        .label = "guest-admission-refused",
        .text = "ROSETTE ADMISSION: refusing authentic guest start",
        .owner = .emulator_build,
        .remedy = "The emulator refused its own start over the run identity. Rosette's GUEST ENVIRONMENT lines above record what it was actually handed for each name; if those show the values delivered, the fault is in the emulator's own parse or route selection, not in what Rosette provided",
    },
    .{
        .label = "graphics-setup-failed",
        .text = "Setup: Failed to setup graphics_system",
        .owner = .emulator_build,
        .remedy = "Graphics setup returned a failure. Read the line above it: this is where the failure was reported, not where it happened",
    },
    .{
        .label = "emulator-setup-failed",
        .text = "Failed to setup emulator",
        .owner = .emulator_build,
        .remedy = "Emulator setup returned a failure and no subsystem after this point runs. The first refusal earlier in the log is the cause",
    },
    .{
        .label = "device-entry-point-absent",
        .text = "ensureRealDeviceFnPtrs: absent on this device",
        .owner = .host_driver,
        .remedy = "A device entry point the bridge binds is provided by no extension this host exposes under any spelling. Either the host cannot support this path, or the extension that provides it was not requested at device creation",
    },
};

const condition_texts: [conditions.len][]const u8 = blk: {
    var table: [conditions.len][]const u8 = undefined;
    for (conditions, 0..) |condition, index| table[index] = condition.text;
    break :blk table;
};

const filter = phrase_filter.Filter(&condition_texts);

/// The condition a line reports, or null.
///
/// Null is the overwhelmingly common answer — a run writes thousands of lines
/// and a handful are terminal — so the rejection path is the one that matters.
pub fn match(line: []const u8) ?Condition {
    const set = phrase_filter.characterSet(line);
    for (conditions, 0..) |condition, index| {
        // One bit test rejects a condition whose rare character the line does
        // not contain. A substring search cannot succeed without every one of
        // the condition's characters being present, so this never rejects a
        // real match.
        if (!filter.survives(set, index)) continue;
        if (std.mem.indexOf(u8, line, condition.text) == null) continue;
        if (condition.also.len != 0 and std.mem.indexOf(u8, line, condition.also) == null) continue;
        return condition;
    }
    return null;
}

pub fn conditionForLabel(label: []const u8) ?Condition {
    for (conditions) |condition| {
        if (std.mem.eql(u8, condition.label, label)) return condition;
    }
    return null;
}

pub fn contractIsWellFormed() bool {
    if (conditions.len == 0) return false;
    for (conditions, 0..) |condition, index| {
        if (condition.label.len == 0) return false;
        if (condition.text.len == 0) return false;
        // A remedy that only restates the error tells the operator nothing, so
        // the length floor is deliberate rather than decorative.
        if (condition.remedy.len < 32) return false;
        // Labels are the allow-list vocabulary and have to be unique.
        for (conditions[index + 1 ..]) |other| {
            if (std.mem.eql(u8, condition.label, other.label)) return false;
        }
    }
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the emulator's own refusal is terminal and names the emulator" {
    const line = "[xenia] !> ROSETTE ADMISSION: refusing authentic guest start because the content-bound run identity is incomplete or invalid; provide ROSETTE_RUN_ID, ROSETTE_MANIFEST_HASH (or ROSETTE_BUILD_IDENTITY_HASH), and ROSETTE_BACKEND";
    const condition = match(line) orelse return error.ShouldMatch;
    try std.testing.expectEqualStrings("guest-admission-refused", condition.label);
    try std.testing.expectEqual(Owner.emulator_build, condition.owner);
    try std.testing.expectEqualStrings("emulator:build", condition.owner.label());
}

test "the refusal matches before the failures it causes" {
    // All three appear in one run, in this order. If a later one matched first
    // the stop would name a consequence and send the reader downstream of the
    // cause.
    const refusal = match("[xenia] !> ROSETTE ADMISSION: refusing authentic guest start because ...") orelse
        return error.ShouldMatch;
    try std.testing.expectEqualStrings("guest-admission-refused", refusal.label);

    const graphics = match("[xenia] !> Setup: Failed to setup graphics_system!") orelse
        return error.ShouldMatch;
    try std.testing.expectEqualStrings("graphics-setup-failed", graphics.label);

    const emulator = match("[xenia] !> Failed to setup emulator: C000000D") orelse
        return error.ShouldMatch;
    try std.testing.expectEqualStrings("emulator-setup-failed", emulator.label);
}

test "an absent device entry point is the host's, not the emulator's" {
    const line = "macho-processor: ensureRealDeviceFnPtrs: absent on this device: vkCmdBeginConditionalRenderingEXT, vkCmdEndConditionalRenderingEXT";
    const condition = match(line) orelse return error.ShouldMatch;
    try std.testing.expectEqualStrings("device-entry-point-absent", condition.label);
    try std.testing.expectEqual(Owner.host_driver, condition.owner);
}

test "an ordinary line is not terminal" {
    try std.testing.expect(match("macho-processor: AUDIT INPUTS: hashing progress bytes=1/2 (50%)") == null);
    try std.testing.expect(match("[xenia] i> Initializing Memory") == null);
    try std.testing.expect(match("") == null);
    // The sentence explaining an absence is not itself the absence. Only the
    // line carrying the entry points is terminal, so the explanation that
    // follows it cannot double-count.
    try std.testing.expect(match("macho-processor: ensureRealDeviceFnPtrs: an absence here means no extension this host exposes provides the entry point under any spelling") == null);
}

test "every label is unique and reachable by name" {
    for (conditions) |condition| {
        const found = conditionForLabel(condition.label) orelse return error.LabelShouldResolve;
        try std.testing.expectEqualStrings(condition.text, found.text);
    }
    try std.testing.expect(conditionForLabel("no-such-condition") == null);
}

test "every condition says what to do about it" {
    for (conditions) |condition| {
        // A remedy that merely repeats the phrase leaves the operator where
        // they started.
        try std.testing.expect(std.mem.indexOf(u8, condition.remedy, condition.text) == null);
        try std.testing.expect(condition.remedy.len >= 32);
    }
}
