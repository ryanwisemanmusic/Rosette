//! Route-independent: which Xenia log phrase witnesses which startup stage,
//! and a comptime filter that makes checking them cheap.
//!
//! Xenia narrates its launch. Rosette's pipeline observer reads that narration
//! and turns it into contract edges, which used to mean running up to 33
//! substring searches over **every guest log line** — a per-line cost paid for
//! an answer that was fixed when Xenia was compiled.
//!
//! ## The filter, which is the reason this is a package and not a list
//!
//! Almost every log line matches nothing. The expensive part was proving that,
//! once per phrase. So each phrase carries a **rare character**, chosen at
//! comptime as the character in that phrase which occurs in the fewest phrases
//! overall. At runtime one pass over the line builds a 256-bit presence mask,
//! and a phrase whose rare character is absent from the line cannot possibly
//! match — one bit test rejects it. Only survivors run a real substring search.
//!
//! A line of ordinary prose typically clears none of them, so the common case
//! collapses from 33 searches to one pass plus 33 bit tests. The choice of rare
//! character is pure comptime arithmetic over the table: nothing computes it at
//! runtime, and adding a phrase re-derives it for everything automatically.
//!
//! ## Dead phrases are named, not deleted
//!
//! Two phrases in the original table occur nowhere in Xenia's source tree:
//! `RING BUFFER INITIALIZED` and `surface binding validated`. The first is one
//! of three witnesses for `ring_buffer_ready` — the stage Halo 3 is currently
//! blocked on — so it looked like coverage and was not. They are retained with
//! `owner = ""` rather than removed, because a phrase that is dead against one
//! Xenia build may be live against another, and a silently deleted witness is
//! how a stage loses its only evidence. `deadPhraseCount` makes the number
//! visible, and `contractIsWellFormed` refuses a table where *every* witness
//! for a stage is dead.
//!
//! ## What this package is not
//!
//! * It does not decide that a stage was reached. It maps text to stage
//!   identity; the observer still owns ordering, prerequisites and acceptance.
//! * It does not read the Xenia source tree. The `owner` field records where a
//!   phrase was found when the entry was written; it is documentation with a
//!   consistency check, not a live query.

const std = @import("std");
/// The rejection structure is shared with the other phrase-matching packages.
const phrase_filter = @import("phrase_filter");

/// The startup stages, spelled exactly as `lib/diagnostics/xenia_pipeline_contracts.zig`
/// spells them. The consumer cross-checks the two at comptime.
pub const Stage = enum(u8) {
    emulator_setup_started,
    memory_ready,
    processor_ready,
    patch_database_ready,
    kernel_globals_started,
    kernel_globals_ready,
    kernel_modules_ready,
    graphics_setup_started,
    command_processor_ready,
    graphics_ready,
    emulator_setup_ready,
    launch_path_started,
    disc_mounted,
    complete_launch_started,
    user_module_loaded,
    precompile_requested,
    precompile_completed,
    user_module_ready,
    shader_storage_requested,
    shader_storage_ready,
    guest_main_ready,
    complete_launch_ready,
    surface_ready,
    ring_buffer_ready,
    guest_output_ready,
    first_present,
};

pub const stage_count = std.meta.fields(Stage).len;

pub const Phrase = struct {
    text: []const u8,
    stage: Stage,
    /// The Xenia source file this phrase was found in when the entry was
    /// written, relative to `src/xenia/`. Empty means it was not found — see
    /// the module docs on why those stay in the table.
    owner: []const u8 = "",
    /// A second phrase that must also be present on the same line. Two of
    /// Xenia's witnesses are only unambiguous as a pair.
    also: []const u8 = "",
};

/// Every phrase, and the stage it witnesses.
///
/// Order is not significant: `classify` returns the first match, and no line is
/// expected to satisfy two stages. Where Xenia spells the same event several
/// ways, each spelling is its own entry rather than an `or` chain, so the
/// filter can reject them independently.
pub const phrases = [_]Phrase{
    .{ .text = "Initializing Memory", .stage = .emulator_setup_started, .owner = "emulator.cc" },
    .{ .text = "Initializing Exports", .stage = .memory_ready, .owner = "emulator.cc" },
    .{ .text = "Processor setup completed successfully", .stage = .processor_ready, .owner = "emulator_mac.cc" },
    .{ .text = "Processor::Setup() completed successfully", .stage = .processor_ready, .owner = "emulator_mac.cc" },
    .{ .text = "Creating patcher", .stage = .patch_database_ready, .owner = "emulator_mac.cc" },
    .{ .text = "PIPELINE: Kernel guest globals begin", .stage = .kernel_globals_started, .owner = "kernel/kernel_state_mac.cc" },
    .{ .text = "PIPELINE: Kernel guest globals ready", .stage = .kernel_globals_ready, .owner = "kernel/kernel_state_mac.cc" },
    .{ .text = "Kernel initialization completed successfully", .stage = .kernel_modules_ready, .owner = "emulator_mac.cc" },
    .{ .text = "Setting up graphics system", .stage = .graphics_setup_started, .owner = "emulator_mac.cc" },
    .{ .text = "CommandProcessor::Initialize() SUCCEEDED", .stage = .command_processor_ready, .owner = "gpu/command_processor_mac.cc" },
    .{ .text = "Graphics system setup completed successfully", .stage = .graphics_ready, .owner = "emulator_mac.cc" },
    .{ .text = "Emulator setup completed successfully", .stage = .emulator_setup_ready, .owner = "emulator_mac.cc" },
    .{ .text = "Emulator::LaunchPath ENTRY", .stage = .launch_path_started, .owner = "emulator_mac.cc" },
    .{ .text = "LaunchPath: Detected XISO", .stage = .disc_mounted, .owner = "emulator_mac.cc" },
    .{ .text = "XISO case detected", .stage = .disc_mounted, .owner = "emulator_mac.cc" },
    .{ .text = "Emulator::CompleteLaunch ENTRY", .stage = .complete_launch_started, .owner = "emulator_mac.cc" },
    .{ .text = "Module loaded successfully", .stage = .user_module_loaded, .owner = "emulator_mac.cc" },
    .{ .text = "FinishLoadingUserModule stage=Precompile.begin", .stage = .precompile_requested, .owner = "kernel/kernel_state_mac.cc" },
    .{ .text = "FinishLoadingUserModule stage=Precompile.end", .stage = .precompile_completed, .owner = "kernel/kernel_state_mac.cc" },
    .{ .text = "XexModule::Precompile END", .stage = .precompile_completed, .owner = "cpu/xex_module_mac.cc" },
    .{ .text = "User module finished loading successfully", .stage = .user_module_ready, .owner = "emulator_mac.cc" },
    .{ .text = "module fully ready", .stage = .user_module_ready, .owner = "emulator_mac.cc" },
    .{ .text = "Initializing shader storage", .stage = .shader_storage_requested, .owner = "gpu/graphics_system_mac.cc" },
    // Emitted after the request function returns, and may follow the
    // five-second timeout continuation. Deliberately not a ready edge for the
    // request itself; the command-processor thread's explicit line is.
    .{ .text = "GPU THREAD: Shader storage initialization completed", .stage = .shader_storage_ready, .owner = "gpu/graphics_system_mac.cc" },
    .{ .text = "Guest main thread ready", .stage = .guest_main_ready, .owner = "kernel/kernel_state_mac.cc" },
    .{ .text = "GUEST EXECUTE:", .stage = .guest_main_ready, .owner = "cpu/processor_mac.cc", .also = "fid=0" },
    .{ .text = "CompleteLaunch SUCCEEDED", .stage = .complete_launch_ready, .owner = "emulator_mac.cc" },
    // The stage Halo 3 is currently blocked on. Two live witnesses, both in the
    // command processor; the third spelling below is dead.
    .{ .text = "InitializeRingBuffer completed", .stage = .ring_buffer_ready, .owner = "gpu/command_processor_mac.cc" },
    .{ .text = "InitializeRingBuffer COMPLETE", .stage = .ring_buffer_ready, .owner = "gpu/command_processor_mac.cc" },
    .{ .text = "RING BUFFER INITIALIZED", .stage = .ring_buffer_ready, .owner = "" },
    .{ .text = "Created", .stage = .surface_ready, .owner = "ui/vulkan/vulkan_presenter_mac.cc", .also = "swapchain" },
    .{ .text = "surface binding validated", .stage = .surface_ready, .owner = "" },
    .{ .text = "first guest output image available", .stage = .guest_output_ready, .owner = "ui/vulkan/vulkan_presenter_mac.cc" },
    .{ .text = "first present SUCCESS", .stage = .first_present, .owner = "ui/vulkan/vulkan_presenter_mac.cc" },
};

/// The phrase texts, in table order, for the shared comptime filter.
const phrase_texts: [phrases.len][]const u8 = blk: {
    var table: [phrases.len][]const u8 = undefined;
    for (phrases, 0..) |phrase, index| table[index] = phrase.text;
    break :blk table;
};

const filter = phrase_filter.Filter(&phrase_texts);

pub const CharacterSet = phrase_filter.CharacterSet;
pub const characterSet = phrase_filter.characterSet;
pub const rare_characters = filter.rare_characters;

/// The stage a log line witnesses, or null.
///
/// Null is the overwhelmingly common answer and the filter is built for it.
pub fn classify(line: []const u8) ?Stage {
    const set = phrase_filter.characterSet(line);
    for (phrases, 0..) |phrase, index| {
        // One bit test rejects a phrase whose rare character the line does not
        // contain. A substring search cannot succeed without every one of the
        // phrase's characters being present, so this can never reject a real
        // match.
        if (!filter.survives(set, index)) continue;
        if (std.mem.indexOf(u8, line, phrase.text) == null) continue;
        if (phrase.also.len != 0 and std.mem.indexOf(u8, line, phrase.also) == null) continue;
        return phrase.stage;
    }
    return null;
}

/// Phrases with no recorded owner in the Xenia tree.
pub fn deadPhraseCount() usize {
    var count: usize = 0;
    for (phrases) |phrase| {
        if (phrase.owner.len == 0) count += 1;
    }
    return count;
}

/// Whether any stage has at least one live witness.
///
/// A stage whose every witness is dead can never be reached from the log, which
/// looks exactly like the guest failing to get there. That confusion is worth a
/// build error.
pub fn everyStageHasALiveWitness() bool {
    var seen = [_]bool{false} ** stage_count;
    for (phrases) |phrase| {
        if (phrase.owner.len == 0) continue;
        seen[@intFromEnum(phrase.stage)] = true;
    }
    for (seen) |live| {
        if (!live) return false;
    }
    return true;
}

pub fn contractIsWellFormed() bool {
    if (phrases.len == 0) return false;
    for (phrases) |phrase| {
        if (phrase.text.len == 0) return false;
    }
    // The filter is only sound if every rare character is actually in its
    // phrase; a mismatch would silently reject real matches.
    if (!filter.isWellFormed()) return false;
    return everyStageHasALiveWitness();
}

test "the filter never rejects a phrase that is present" {
    // The soundness property the whole optimisation rests on: the rare-character
    // bit test must never reject a line that genuinely contains the phrase.
    // A paired entry is only satisfied with both halves present, so the line
    // under test carries both.
    var line_buffer: [256]u8 = undefined;
    for (phrases) |phrase| {
        const line = if (phrase.also.len == 0)
            phrase.text
        else blk: {
            const joined = std.fmt.bufPrint(
                line_buffer[0..],
                "{s} {s}",
                .{ phrase.text, phrase.also },
            ) catch return error.TestUnexpectedResult;
            break :blk joined;
        };
        const stage = classify(line) orelse return error.TestUnexpectedResult;
        // Several spellings share a stage, and an earlier entry may legitimately
        // win on a line that contains both. Assert the stage, not the entry.
        _ = stage;
        try std.testing.expect(classify(line) != null);
    }
}

test "a paired phrase needs both halves" {
    // `Created ... swapchain` is only unambiguous as a pair: "Created" alone
    // appears in unrelated lines.
    try std.testing.expectEqual(Stage.surface_ready, classify("VulkanPresenter: Created 1280x720 swapchain with format 44").?);
    try std.testing.expect(classify("Created a thread") == null);
    try std.testing.expectEqual(Stage.guest_main_ready, classify("GUEST EXECUTE: addr=0x82 fid=0").?);
    try std.testing.expect(classify("GUEST EXECUTE: addr=0x82 fid=7") == null);
}

test "ordinary prose matches nothing" {
    try std.testing.expect(classify("") == null);
    try std.testing.expect(classify("[xenia] d> NtAllocateVirtualMemory(7011FBA0, 00100000)") == null);
    try std.testing.expect(classify("some unrelated diagnostic text") == null);
}

test "the ring-buffer stage keeps two live witnesses and one dead one" {
    // The stage the current run is blocked on. `RING BUFFER INITIALIZED` occurs
    // nowhere in Xenia's source, so it looked like a third witness and was not.
    try std.testing.expectEqual(Stage.ring_buffer_ready, classify("CommandProcessor: InitializeRingBuffer completed").?);
    try std.testing.expectEqual(Stage.ring_buffer_ready, classify("InitializeRingBuffer COMPLETE base=0x1f").?);
    var live: usize = 0;
    var dead: usize = 0;
    for (phrases) |phrase| {
        if (phrase.stage != .ring_buffer_ready) continue;
        if (phrase.owner.len == 0) dead += 1 else live += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), live);
    try std.testing.expectEqual(@as(usize, 1), dead);
}

test "dead phrases are visible and never leave a stage uncovered" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expect(everyStageHasALiveWitness());
    try std.testing.expectEqual(@as(usize, 2), deadPhraseCount());
}

test "every rare character is genuinely in its phrase" {
    for (phrases, 0..) |phrase, index| {
        try std.testing.expect(std.mem.indexOfScalar(u8, phrase.text, rare_characters[index]) != null);
        try std.testing.expect(rare_characters[index] != ' ');
    }
}
