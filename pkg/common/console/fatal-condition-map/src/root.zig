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
    /// How many occurrences make this condition decisive.
    ///
    /// One for a line that settles the outcome the first time it is printed:
    /// a refusal, a setup failure. Some conditions are not like that. A
    /// watchdog is *designed* to fire while a situation might still resolve,
    /// so its first line is a warning and its fortieth is a statement that the
    /// thing it watches never recovered. Stopping on the first would end
    /// healthy bootstraps; never stopping is what the 2026-09-08 run did —
    /// the zero-refresh watchdog fired 42 times across 2,384 host seconds and
    /// the run continued to the end of the operator's patience.
    ///
    /// A threshold is what lets a repeating line be terminal without being
    /// trigger-happy, and it has to be declared per condition because only the
    /// condition knows how long its situation is allowed to persist.
    repeats: u32 = 1,
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
        // The emulator's own watchdog for "nothing has refreshed the output".
        // `refresh_success_count=0` is the half that matters: the watchdog
        // alone fires during ordinary bootstrap, and pairing it with a refresh
        // count that has never left zero is what makes a repetition mean the
        // output path never started rather than that it is still starting.
        //
        // Sixteen is past every bootstrap window observed so far and still
        // ends the run in roughly a third of the time the 2026-09-08 run took
        // to reach 42 of them. It is a declared number, not a derived one: the
        // right value is however long this situation is allowed to persist,
        // and that is a judgement rather than a measurement.
        .label = "output-never-refreshed",
        .text = "ZERO-REFRESH WATCHDOG",
        .also = "refresh_success_count=0",
        .owner = .emulator_build,
        .repeats = 16,
        .remedy = "The emulator's own watchdog has reported an unrefreshed output this many times with the refresh success count still at zero, so the output path never started rather than being slow to start. Read the swap ladder's frontier: the refresh is downstream of it and will not run until that rung is reached. This condition is about the run no longer producing new evidence, not about the refresh itself",
    },
    .{
        .label = "device-entry-point-absent",
        .text = "ensureRealDeviceFnPtrs: absent on this device",
        .owner = .host_driver,
        .remedy = "A device entry point the bridge binds is provided by no extension this host exposes under any spelling. Either the host cannot support this path, or the extension that provides it was not requested at device creation",
    },
    .{
        .label = "sdl-gamecontroller-db-missing",
        .text = "SDL GameControllerDB: file 'gamecontrollerdb.txt' does not exist.",
        .owner = .rosette_harness,
        .remedy = "The Windows bundle must contain gamecontrollerdb.txt beside xenia_canary.exe, or the launcher must supply that file in the guest working directory before SDL initializes. Do not treat missing controller mappings as an invisible input degradation",
    },
    .{
        // Read Xenia's own code before believing the owner here.
        // `BaseHeap::AllocFixed` manages the *Xbox 360* address space inside
        // the view Rosette hands Xenia, not the Windows address space Rosette
        // serves. Its own comment on this branch is "This may be OK": it adds
        // kMemoryAllocationReserve to the request and continues.
        //
        // The first three are Xenia's design, not a title's act.
        // `XamState`'s constructor commits three fixed pages in the
        // 0x80000000 heap without reserving them
        // (src/xenia/kernel/xam/xam_state.cc: the language fallback table at
        // 0x80D00000, the next table at 0x80D10000 and the IPTV service name
        // at 0x80D20000). The 2026-09-13 run printed this line exactly three
        // times, at steps 39.11M-39.15M on Xenia thread 00000005, directly
        // after Rosette committed 0x280D00000, 0x280D10000 and 0x280D20000 -
        // membase plus those three addresses - and before any title code
        // existed. Calling that `guest:title` sent a reader to a title that
        // had not been loaded. A fourth is somebody else's commit, and that
        // one is decisive.
        .label = "guest-heap-commit-unreserved",
        .text = "BaseHeap::AllocFixed attempting commit on unreserved page",
        .owner = .emulator_build,
        .repeats = 4,
        .remedy = "Xenia's XamState commits three fixed pages without reserving them, by design, and each prints this once. A fourth commit on an unreserved page is not XamState's: read the step on the stopping line against PE64 GUEST KERNEL CALLS (NtAllocateVirtualMemory, MmAllocatePhysicalMemoryEx) for the title call that committed memory it never reserved, and PE64 MEMORY CONTRACT for whether Rosette backed it",
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
    const index = matchIndex(line) orelse return null;
    return conditions[index];
}

/// The matching condition's index, for a caller that has to keep per-condition
/// state — a condition declared `repeats > 1` has to be counted, and counting
/// by label would mean a string compare per line on the logging funnel.
pub fn matchIndex(line: []const u8) ?usize {
    const set = phrase_filter.characterSet(line);
    for (conditions, 0..) |condition, index| {
        // One bit test rejects a condition whose rare character the line does
        // not contain. A substring search cannot succeed without every one of
        // the condition's characters being present, so this never rejects a
        // real match.
        if (!filter.survives(set, index)) continue;
        if (std.mem.indexOf(u8, line, condition.text) == null) continue;
        if (condition.also.len != 0 and std.mem.indexOf(u8, line, condition.also) == null) continue;
        return index;
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

test "the refusal matches with the emulator's own diagnostic suffix attached" {
    // The real line carries everything the emulator parsed, and the phrase is
    // only its prefix. Matching has to survive that, because this exact line
    // went unmatched for a whole run: the mirror wrote it straight to the file
    // descriptor and the watch never saw it at all.
    const line = "ROSETTE ADMISSION: refusing authentic guest start; parsed run=0xFCAD20A045D4A25A manifest=0xB3357146F5B444E9 profile=0x4AE3A6ABC0377512 route=vulkan ready=YES. Provide non-zero ROSETTE_RUN_ID, ROSETTE_MANIFEST_HASH (or ROSETTE_BUILD_IDENTITY_HASH), and ROSETTE_BACKEND";
    const condition = match(line) orelse return error.ShouldMatch;
    try std.testing.expectEqualStrings("guest-admission-refused", condition.label);
}

// A watchdog is not a refusal. Its first line is a warning about a situation
// that might still resolve, and its fortieth is a statement that it never did.
// The 2026-09-08 run printed 42 of them across 2,384 host seconds with the
// refresh success count never leaving zero, and nothing stopped.
test "Xenia's own three unreserved commits are not decisive, a fourth is" {
    // XamState commits 0x80D00000, 0x80D10000 and 0x80D20000 without a
    // reservation on every start. A threshold of one stopped every run at
    // step 39M for Xenia's design; a threshold of four still stops the first
    // commit that is not XamState's.
    const condition = conditionForLabel("guest-heap-commit-unreserved") orelse return error.MissingCondition;
    try std.testing.expectEqual(Owner.emulator_build, condition.owner);
    try std.testing.expectEqual(@as(u32, 4), condition.repeats);
    const matched = match("w> 00000005 BaseHeap::AllocFixed attempting commit on unreserved page") orelse return error.ExpectedMatch;
    try std.testing.expectEqualStrings("guest-heap-commit-unreserved", matched.label);
}

test "a repeating condition is decisive only after its declared threshold" {
    const watchdog = conditionForLabel("output-never-refreshed") orelse
        return error.ConditionShouldExist;
    try std.testing.expect(watchdog.repeats > 1);
    // Both halves are required: the watchdog alone fires during ordinary
    // bootstrap, and it is the refresh count still at zero that turns a
    // repetition into "the output path never started".
    try std.testing.expect(watchdog.also.len != 0);

    const firing = "[xenia] w> DEBUG: ZERO-REFRESH WATCHDOG: vblank_id=1264 age=6264ms " ++
        "swap_count=0 rb_init=YES refresh_attempt_count=0 refresh_success_count=0";
    const matched = match(firing) orelse return error.LineShouldMatch;
    try std.testing.expectEqualStrings("output-never-refreshed", matched.label);
    try std.testing.expectEqual(matchIndex(firing).?, blk: {
        for (conditions, 0..) |condition, index| {
            if (std.mem.eql(u8, condition.label, "output-never-refreshed")) break :blk index;
        }
        break :blk conditions.len;
    });

    // A watchdog whose refresh count has moved is a different line and is not
    // this condition at all.
    const recovered = "[xenia] w> DEBUG: ZERO-REFRESH WATCHDOG: vblank_id=90 " ++
        "refresh_attempt_count=3 refresh_success_count=3";
    try std.testing.expectEqual(@as(?Condition, null), match(recovered));

    // Every one-shot condition keeps its meaning: a refusal settles the
    // outcome the first time it is printed.
    for ([_][]const u8{ "guest-admission-refused", "graphics-setup-failed", "emulator-setup-failed" }) |label| {
        const condition = conditionForLabel(label) orelse return error.ConditionShouldExist;
        try std.testing.expectEqual(@as(u32, 1), condition.repeats);
    }

    // A threshold of zero would make a condition fatal before it ever matched.
    for (conditions) |condition| try std.testing.expect(condition.repeats >= 1);
}

test "Windows PE bring-up warnings have stable fatal-point labels" {
    const controller = match("w> 00000001 SDL GameControllerDB: file 'gamecontrollerdb.txt' does not exist.") orelse
        return error.ShouldMatch;
    try std.testing.expectEqualStrings("sdl-gamecontroller-db-missing", controller.label);
    // BaseHeap is Xenia's guest page table, not Rosette's Windows allocator,
    // and the three commits every start makes are XamState's, before any
    // title code exists. Rosette is not a party and neither is the title.
    const heap = match("w> 00000005 BaseHeap::AllocFixed attempting commit on unreserved page") orelse
        return error.ShouldMatch;
    try std.testing.expectEqualStrings("guest-heap-commit-unreserved", heap.label);
    try std.testing.expectEqual(Owner.emulator_build, heap.owner);
}
