//! Route-independent: which of Xenia's warning-level log lines are findings.
//!
//! Xenia prints at four levels and Rosette can only see the text. Anything
//! carrying `w>`, `!>` or `x>` used to be recorded as
//! `FATAL POINT: guest-warning-unclassified` and written with `log.err`, which
//! meant a run that was going perfectly still produced lines like
//!
//! ```
//! error(elf): PE64 FATAL POINT: guest-warning-unclassified ...
//!             line=w> 00000005 * 0: Apple M2 Max
//! ```
//!
//! That is the adapter list Xenia prints on its way to picking a device. It is
//! not a fault, it is not unclassified, and calling it a fatal point trains a
//! reader to skim past the block that also contains the real ones.
//!
//! ## The three severities, and why they are not two
//!
//! * `informational` - Xenia narrating, at warning level, something that went
//!   right. Device lists, chosen paths, versions.
//! * `advisory` - a real degradation the run survives. A feature is off, a
//!   fallback was taken. Worth reading; not a reason to look for a bug in
//!   Rosette.
//! * `fault` - everything else, which is the default.
//!
//! Collapsing `advisory` into `informational` would hide a tessellation
//! failure; collapsing it into `fault` is what produced the noise. Both
//! mistakes cost the same thing, which is a reader's attention.
//!
//! ## What this package proves, and what it does not
//!
//! It is a pure function of one line of text. It does not decide whether a run
//! failed, it does not stop anything, and it deliberately does not overlap
//! `fatal-condition-map`: a line that is terminal is matched there first, and
//! anything reaching this table has already been found non-terminal. A line
//! this table does not recognize is a `fault`, so a new Xenia warning is
//! loud by default and quiet only once someone has looked at it.

const std = @import("std");
const phrase_filter = @import("phrase_filter");

pub const Severity = enum {
    /// Xenia narrating something that went right.
    informational,
    /// A real degradation the run survives.
    advisory,
    /// Unrecognized, or a known problem. The default.
    fault,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .informational => "informational",
            .advisory => "advisory",
            .fault => "fault",
        };
    }

    /// Whether a reader has to act on this line.
    pub fn isFinding(self: Severity) bool {
        return self != .informational;
    }
};

/// Which Rosette-side ledger substantiates a guest line.
///
/// A guest failure line is a *claim*. `Presenter: Failed to create a DXGI
/// factory` says what Xenia concluded; it says nothing about what Rosette
/// answered that made Xenia conclude it, and a reader looking at that line
/// alone cannot tell a deliberate refusal from a bug. Rosette holds the other
/// half of every one of these - the export that was called, the value it
/// returned, the guest address that called it, the step it happened at - and
/// this field says which half to go and fetch.
///
/// The enum, not a free string, because the caller has to switch on it: each
/// value names a ledger with its own shape. A line with no Rosette-side
/// counterpart is `.none`, and that is itself worth knowing - it means the
/// decision was entirely the guest's.
pub const Evidence = enum {
    /// Nothing on Rosette's side of the boundary took part in this line.
    none,
    /// A `CreateDXGIFactory*` call Rosette answered with an HRESULT refusal.
    dxgi_factory,
    /// Vulkan shader-module or pipeline creation Rosette forwarded, and what
    /// the driver said about it.
    vulkan_shader_creation,
    /// Rosette's own CJK font policy decision.
    guest_font_policy,
    /// A guest heap commit Rosette classified against its backing.
    guest_heap_commit,
    /// The adapter list and device features Rosette's Vulkan bridge exposed.
    vulkan_device_selection,

    pub fn label(self: Evidence) []const u8 {
        return switch (self) {
            .none => "none",
            .dxgi_factory => "dxgi_factory",
            .vulkan_shader_creation => "vulkan_shader_creation",
            .guest_font_policy => "guest_font_policy",
            .guest_heap_commit => "guest_heap_commit",
            .vulkan_device_selection => "vulkan_device_selection",
        };
    }
};

/// Whether a run may continue past a line of this kind.
///
/// A warning is an error until something proves otherwise. Xenia prints real
/// failures at warning level, and the ones a run survives are survivable for
/// a reason that can be named; a row that cannot name one stops the run at
/// the line, with its evidence, instead of letting everything downstream be
/// gathered on top of an unexplained failure.
pub const Continuation = enum {
    /// Nothing says continuing is sound. The run stops at this line, and
    /// `ROSETTE_XENIA_FATAL_POINT_ALLOW=<label>` steps past it deliberately.
    stops,
    /// Rosette itself decided the outcome - a DLL with no host backend, a
    /// withheld font - so the line reports a policy, not a defect.
    rosette_policy,
    /// The emulator's own source takes this branch by design on every start
    /// and says so; the fatal-condition map bounds how often.
    emulator_design,
    /// Xenia narrating something that went right.
    narration,

    pub fn label(self: Continuation) []const u8 {
        return switch (self) {
            .stops => "stops",
            .rosette_policy => "rosette_policy",
            .emulator_design => "emulator_design",
            .narration => "narration",
        };
    }

    pub fn continues(self: Continuation) bool {
        return self != .stops;
    }
};

pub const Entry = struct {
    /// Stable name: what a stop line prints and what an operator puts in
    /// `ROSETTE_XENIA_FATAL_POINT_ALLOW` to step past this row.
    label: []const u8,
    /// Substring that identifies the line.
    text: []const u8,
    severity: Severity,
    /// Why it is classified this way, in one clause. A table of bare strings
    /// is unauditable: the next person cannot tell a considered
    /// `informational` from a guess.
    reason: []const u8,
    /// The Rosette-side ledger that explains how the guest arrived here.
    /// Defaults to `.none` so a row only claims evidence that exists.
    evidence: Evidence = .none,
    /// The named ground for continuing past the line, or `.stops`.
    continuation: Continuation = .stops,
};

/// Ordered most specific first.
pub const entries = [_]Entry{
    // --- Virtual file system. The empty-path form comes first: it matches
    // a strict subset of the general row below it.
    .{
        .label = "vfs-empty-object-name",
        .text = "ResolvePath() failed - device not found",
        .severity = .fault,
        .continuation = .stops,
        .reason = "the title asked the virtual file system to resolve an empty path - the parentheses are empty because the name was; the emitting thread's last kernel call names the export that passed it",
    },
    // A bare module name (`ResolvePath(WavesLibDLL)`) is matched by shape in
    // `bareModuleLookupName` before this table is consulted, so no row names
    // a particular module.
    .{
        .label = "vfs-device-not-found",
        .text = "failed - device not found",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "a path on a device this configuration did not mount; titles probe optional devices such as cache: and update: and continue without them",
    },
    // --- Module linking. Xenia's own failure signal for a title module whose
    // import could not be bound; the device-not-found lines that precede it
    // are not.
    .{
        .label = "xex-import-unresolved",
        .text = "an import variable was not resolved",
        .severity = .fault,
        .continuation = .stops,
        .reason = "a title module imports an ordinal that no loaded module exports; Xenia leaves the import unbound and the first call through it lands in its undefined-import path",
    },

    // --- Vulkan device selection. Xenia prints this whole block at warning
    // level even on a completely healthy pick.
    .{
        .label = "vulkan-adapter-list",
        .text = "Available Vulkan physical devices",
        .severity = .informational,
        .continuation = .narration,
        .reason = "the adapter list Xenia prints before choosing one",
        .evidence = .vulkan_device_selection,
    },
    .{
        .label = "vulkan-device-hint",
        .text = "use the 'vulkan_device' configuration variable",
        .severity = .informational,
        .continuation = .narration,
        .reason = "the hint that accompanies the adapter list",
    },
    .{
        .label = "vulkan-device-chosen",
        .text = "Chosen physical device",
        .severity = .informational,
        .continuation = .narration,
        .reason = "states which adapter was selected; a selection is not a fault",
    },
    .{
        .label = "vulkan-device-features",
        .text = "Vulkan device features",
        .severity = .informational,
        .continuation = .narration,
        .reason = "capability narration, printed whether or not anything is missing",
    },

    // --- Degradations the run survives.
    .{
        .label = "vulkan-tessellation-unavailable",
        .text = "tessellation will not be available",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "a real capability loss: titles using tessellated primitives will render wrong, but everything else proceeds",
        .evidence = .vulkan_shader_creation,
    },
    .{
        .label = "vulkan-draw-failed-in-backend",
        .text = "): Failed in backend",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "Xenia's VulkanCommandProcessor::IssueDraw returned false and the draw was skipped. The numbers are (index count, primitive type, source select). Primitive type 8 is a rectangle list: with no geometry shaders on this host (MoltenVK), Xenia's primitive processor expands it in the vertex shader, and this IssueDraw only accepts plain, point-sprite and domain vertex shaders, so it refuses every rectangle list. A different primitive type failing here is not explained by that and is a lead",
    },
    .{
        .label = "dxgi-factory-refused",
        .text = "Failed to create a DXGI factory",
        .severity = .advisory,
        .continuation = .rosette_policy,
        .reason = "Rosette refused CreateDXGIFactory1: dxgi.dll has no host backend on macOS. Xenia uses this factory for one thing - the DXGI UI tick thread that paces UI-thread repaints - and Presenter::AreDXGIUITicksWaitable is false without an IDXGIOutput, so WaitForUITickFromUIThread returns immediately and painting is unpaced rather than blocked. It does not gate GraphicsSystem::MarkVblank, which is driven by Clock::QueryGuestTickCount on the GPU frame limiter thread",
        .evidence = .dxgi_factory,
    },
    .{
        .label = "guest-cjk-font-withheld",
        .text = "Unable to load Japanese font",
        .severity = .advisory,
        .continuation = .rosette_policy,
        .reason = "Rosette's font policy withheld the CJK font; Japanese glyphs render as boxes and the ImGui atlas stays small",
        .evidence = .guest_font_policy,
    },
    .{
        .label = "windows-fonts-directory-missing",
        .text = "Unable to find Windows fonts directory",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "the guest falls back to its embedded font; only glyph coverage is affected",
    },
    .{
        .label = "guest-custom-font-failed",
        .text = "Failed to load custom font",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "the guest falls back to its embedded font",
    },
    .{
        .label = "guest-scratch-path-unscannable",
        .text = "Unable to scan scratch path",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "an optional mount; the title runs without it",
    },
    .{
        .label = "guest-cache-unscannable",
        .text = "Unable to scan cache",
        .severity = .advisory,
        .continuation = .stops,
        .reason = "an optional mount; the title runs without it",
    },
    .{
        .label = "guest-heap-commit-unreserved",
        .text = "attempting commit on unreserved page",
        .severity = .advisory,
        .continuation = .emulator_design,
        .reason = "Xenia promotes the request internally and continues; Rosette keeps the reservation-versus-commit distinction visible because losing it silently is how a memory contract drifts",
    },
    .{
        .label = "xbox-devkit-debug-memory-fallback",
        .text = "Game is attempting to allocate devkit debug memory",
        .severity = .advisory,
        .continuation = .emulator_design,
        .reason = "Xenia explicitly ignores the devkit-only debug-allocation flag and continues through its normal allocator; the resulting allocation remains subject to Rosette's ordinary memory contract",
    },
    .{
        .label = "xbox-file-allocation-hint-ignored",
        .text = "NtSetInformationFile ignoring alloc",
        .severity = .advisory,
        .continuation = .emulator_design,
        .reason = "Xenia's XFileAllocationInformation branch explicitly ignores the allocation hint, reports the expected output length and returns success; file contents and ordinary virtual-memory allocation remain separate contracts",
    },
};

/// The two volume-cleanup exports below are published by the Xbox kernel but
/// have no Xenia shim in the audited image. Xenia therefore routes them through
/// `UndefinedCallExtern`, which logs the guest line and returns zero. Keep this
/// match deliberately name-based: an unrelated undefined extern is still a
/// fault, and a rebuilt image may assign a different address to the export.
const optional_volume_extern_entry = Entry{
    .label = "xbox-volume-cleanup-extern",
    .text = "undefined extern call to <known Xbox volume cleanup export>",
    .severity = .advisory,
    .continuation = .emulator_design,
    .reason = "Xenia's undefined-extern fallback returned zero for an optional volume-cleanup export; this is an emulator-side cleanup no-op, not a Windows DLL or VFS miss. A title that depends on dismount side effects would still require a real kernel implementation",
};

const filter = phrase_filter.Filter(blk: {
    var texts: [entries.len][]const u8 = undefined;
    for (entries, 0..) |entry, index| texts[index] = entry.text;
    const frozen = texts;
    break :blk &frozen;
});

pub const CharacterSet = phrase_filter.CharacterSet;
pub const characterSet = phrase_filter.characterSet;

/// Whether a line is an item in a list Xenia is printing.
///
/// `Available Vulkan physical devices ...` is followed by one line per
/// adapter, and those lines carry no fixed phrase - the text is the adapter's
/// name, which differs on every machine. Matching them by phrase is
/// impossible; matching them by shape is exact. Xenia's logger writes
/// `<level>> <thread-id> <message>`, and a list item's message begins with
/// `* <index>: `.
///
/// This is the whole reason the run log said
/// `FATAL POINT: guest-warning-unclassified ... line=w> 00000005 * 0: Apple M2 Max`
/// on a machine whose adapter selection was perfect.
fn isListItem(line: []const u8) bool {
    // Skip the `w> ` / `!> ` / `x> ` prefix and the hexadecimal thread id.
    var rest = line;
    if (rest.len >= 3 and rest[1] == '>' and rest[2] == ' ') rest = rest[3..];
    while (rest.len != 0 and rest[0] == ' ') rest = rest[1..];
    var digits: usize = 0;
    while (digits < rest.len and std.ascii.isHex(rest[digits])) digits += 1;
    if (digits != 0) rest = rest[digits..];
    while (rest.len != 0 and rest[0] == ' ') rest = rest[1..];

    if (rest.len < 4 or rest[0] != '*' or rest[1] != ' ') return false;
    var index_digits: usize = 2;
    while (index_digits < rest.len and std.ascii.isDigit(rest[index_digits])) index_digits += 1;
    if (index_digits == 2) return false;
    return index_digits < rest.len and rest[index_digits] == ':';
}

/// Return the name of one of the narrowly scoped Xbox volume-cleanup exports
/// that Xenia's audited image handles through its zero-return undefined-extern
/// fallback. The address is intentionally ignored because it is image-build
/// specific; the export name is the stable part of the diagnostic.
pub fn optionalVolumeExternName(line: []const u8) ?[]const u8 {
    const marker = "undefined extern call to ";
    const marker_start = std.mem.indexOf(u8, line, marker) orelse return null;
    const address_start = marker_start + marker.len;
    const address_end = std.mem.indexOfPos(u8, line, address_start, " ") orelse return null;
    const address = line[address_start..address_end];
    if (address.len == 0) return null;
    for (address) |byte| {
        if (!std.ascii.isHex(byte)) return null;
    }
    const name = std.mem.trim(u8, line[address_end + 1 ..], " \t\r\n");
    const known_names = [_][]const u8{ "IoDismountVolume", "IoDismountVolumeByFileHandle" };
    for (known_names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return name;
    }
    return null;
}

/// The severity of one Xenia warning-level line.
///
/// Unrecognized text is a `fault`: a warning nobody has classified has to stay
/// loud, or the next real one is quiet from the day it is introduced.
pub fn classify(line: []const u8) Severity {
    if (bareModuleLookupName(line) != null) return .informational;
    if (optionalVolumeExternName(line) != null) return .advisory;
    if (filter.firstMatch(line)) |index| return entries[index].severity;
    if (isListItem(line)) return .informational;
    return .fault;
}

/// Whether the VFS line names the empty-path form of `ResolvePath`.
///
/// The raw line remains a fault in this text-only table because an empty path
/// with no provenance is not safe to dismiss. The PE runtime may lower it to
/// an advisory only after its per-thread kernel-call ledger confirms the
/// `NtCreateFile`/status-conversion path that Xenia uses for optional probes.
pub fn isEmptyResolvePath(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "ResolvePath() failed - device not found") != null;
}

/// Why a bare module name failing `ResolvePath` is narration, not a fault.
pub const bare_module_lookup_reason =
    "Xenia's KernelState::GetModule tries every module name as a VFS path before it matches the loaded modules by name, and UserModule::Dump repeats that lookup once per import. A bare name carries no device prefix by construction, so the VFS cannot match a device and says so; the lookup itself continues by name, and the import linker binds against the module's full game: path. Xenia's 'an import variable was not resolved' warning is the failure signal, and Rosette counts it";

/// The module name in `ResolvePath(<name>) failed - device not found` when
/// that name is a bare module name: non-empty, no device prefix, no path
/// separator, and made only of the characters a module file name uses.
///
/// On the 2026-09-13 run this line appeared 324 times for `WavesLibDLL`,
/// a module that is on the disc at `game:\WavesLibDLL.dll`. `Q10.dll` and
/// `L360.dll` import from it; Xenia loaded it by joining the name to the
/// executable's directory, bound every import, and then printed the line
/// twice per import from `UserModule::Dump`. The shape, not the module, is
/// what makes the line harmless, so the shape is what this matches.
pub fn bareModuleLookupName(line: []const u8) ?[]const u8 {
    const open_marker = "ResolvePath(";
    const close_marker = ") failed - device not found";
    const open = std.mem.indexOf(u8, line, open_marker) orelse return null;
    const name_start = open + open_marker.len;
    const close = std.mem.indexOfPos(u8, line, name_start, close_marker) orelse return null;
    const name = line[name_start..close];
    if (name.len == 0 or name.len > 64) return null;
    for (name) |byte| {
        const allowed = std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == '.';
        if (!allowed) return null;
    }
    // `.` and `..` are relative paths, not module names.
    if (std.mem.allEqual(u8, name, '.')) return null;
    return name;
}

/// Whether a line is Xenia's warning that a title module import stayed
/// unbound - the one line that makes a bare-name lookup a real failure.
pub fn isUnresolvedImport(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "an import variable was not resolved") != null;
}

/// Whether the run may continue past a warning-level line.
///
/// Unrecognized text stops: a warning nobody has classified has no ground to
/// continue on, which is the same reason it is a `fault`.
pub fn continuationFor(line: []const u8) Continuation {
    if (bareModuleLookupName(line) != null) return .narration;
    if (optionalVolumeExternName(line) != null) return optional_volume_extern_entry.continuation;
    if (filter.firstMatch(line)) |index| return entries[index].continuation;
    if (isListItem(line)) return .narration;
    return .stops;
}

/// The stable label a stop on this line is reported and allowed under.
pub fn labelFor(line: []const u8) []const u8 {
    if (bareModuleLookupName(line) != null) return "vfs-bare-module-lookup";
    if (optionalVolumeExternName(line) != null) return optional_volume_extern_entry.label;
    if (filter.firstMatch(line)) |index| return entries[index].label;
    if (isListItem(line)) return "guest-list-item";
    return "guest-warning-unclassified";
}

/// The matching entry, for a report that wants to print why.
pub fn entryFor(line: []const u8) ?Entry {
    if (optionalVolumeExternName(line) != null) return optional_volume_extern_entry;
    const index = filter.firstMatch(line) orelse return null;
    return entries[index];
}

pub fn entryCount() usize {
    return entries.len;
}

/// Which Rosette-side ledger explains this line, if any.
///
/// A caller uses this to decide what to print *underneath* the guest's own
/// words. An unmatched line, or one whose row declares no counterpart,
/// answers `.none`: the caller then says nothing rather than inventing a
/// cause, because "Rosette has no record of taking part in this" is a
/// different finding from "Rosette refused something".
pub fn evidenceFor(line: []const u8) Evidence {
    const entry = entryFor(line) orelse return .none;
    return entry.evidence;
}

test "the lines Rosette took part in name the ledger that proves it" {
    // The 2026-09-12 run printed `Presenter: Failed to create a DXGI factory`
    // with nothing beside it. Rosette had answered that exact call and knew
    // the export, the HRESULT, the caller and the step, and printed none of
    // it, so the only reading available was "something failed".
    try std.testing.expectEqual(
        Evidence.dxgi_factory,
        evidenceFor("!> 00000001 Presenter: Failed to create a DXGI factory"),
    );
    try std.testing.expectEqual(
        Evidence.vulkan_shader_creation,
        evidenceFor("w> 0100000C VulkanPipelineCache: Failed to create one or more tessellation shaders - tessellation will not be available"),
    );
    try std.testing.expectEqual(
        Evidence.guest_font_policy,
        evidenceFor("w> 00000001 Unable to load Japanese font; JP characters will be boxes"),
    );
    // No row, no claim.
    try std.testing.expectEqual(Evidence.none, evidenceFor("w> 00000001 something nobody has classified"));
    try std.testing.expectEqual(Evidence.none, evidenceFor(""));
}

test "the DXGI reason states what the missing factory does and does not gate" {
    // The first version of this row called DXGI a vertical-blank pacing
    // mechanism, which reads as "the guest vblank depends on it". It does
    // not: `dxgi_ui_tick_*` in presenter.cc paces UI-thread repaints, and
    // `GraphicsSystem::MarkVblank` is driven from the frame limiter's
    // `Clock::QueryGuestTickCount` delta with no DXGI involvement at all.
    const entry = entryFor("!> 00000001 Presenter: Failed to create a DXGI factory").?;
    try std.testing.expect(std.mem.indexOf(u8, entry.reason, "MarkVblank") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry.reason, "does not gate") != null);
    try std.testing.expectEqual(Severity.advisory, entry.severity);
}

test "every row that claims evidence is a row a reader would ask about" {
    // An `informational` row with a ledger attached would print a paragraph
    // of Rosette state under a line that says nothing went wrong.
    for (entries) |entry| {
        if (entry.evidence == .none) continue;
        if (entry.severity == .informational) {
            // Permitted only for the adapter list, where the reader's next
            // question really is "which device did Rosette expose?".
            try std.testing.expectEqual(Evidence.vulkan_device_selection, entry.evidence);
        }
    }
}

test "the Vulkan adapter list is not a fault" {
    // These two lines produced `FATAL POINT: guest-warning-unclassified` on
    // the 2026-09-11 run, on a machine whose adapter selection was perfect.
    try std.testing.expectEqual(
        Severity.informational,
        classify("w> 00000005 Available Vulkan physical devices (use the 'vulkan_device' configuration variable to force a specific device):"),
    );
    try std.testing.expect(!classify("w> 00000005 Available Vulkan physical devices").isFinding());
}

test "an adapter-list item is recognized by shape, since its text is the machine's" {
    // No phrase can match this: the payload is whatever the host GPU is
    // called. The 2026-09-11 run recorded it as an unclassified fatal point.
    try std.testing.expectEqual(
        Severity.informational,
        classify("w> 00000005 * 0: Apple M2 Max"),
    );
    try std.testing.expectEqual(
        Severity.informational,
        classify("w> 0100000C * 12: NVIDIA GeForce RTX 4090"),
    );
    // Shape, not "starts with a star": a sentence that happens to begin with
    // one is still a fault until somebody classifies it.
    try std.testing.expectEqual(Severity.fault, classify("w> 00000005 * something went wrong"));
    try std.testing.expectEqual(Severity.fault, classify("w> 00000005 *"));
    try std.testing.expectEqual(Severity.fault, classify("w> 00000005 * 0 Apple M2 Max"));
}

test "a real degradation stays a finding without becoming a fault" {
    const tessellation = classify("w> 0100000C VulkanPipelineCache: Failed to create one or more tessellation shaders - tessellation will not be available");
    try std.testing.expectEqual(Severity.advisory, tessellation);
    try std.testing.expect(tessellation.isFinding());

    const dxgi = classify("!> 00000001 Presenter: Failed to create a DXGI factory");
    try std.testing.expectEqual(Severity.advisory, dxgi);
    try std.testing.expect(dxgi.isFinding());
}

test "a bare module name failing ResolvePath is narration, whatever the module" {
    const waves = "!> F8000014 ResolvePath(WavesLibDLL) failed - device not found";
    const waves_dll = "!> F8000014 ResolvePath(WavesLibDLL.dll) failed - device not found";
    try std.testing.expectEqual(Severity.informational, classify(waves));
    try std.testing.expectEqual(Severity.informational, classify(waves_dll));
    try std.testing.expectEqualStrings("WavesLibDLL", bareModuleLookupName(waves).?);
    try std.testing.expectEqualStrings("WavesLibDLL.dll", bareModuleLookupName(waves_dll).?);
    // Not tied to one title's audio library.
    try std.testing.expectEqualStrings("Q10.dll", bareModuleLookupName("!> F8000014 ResolvePath(Q10.dll) failed - device not found").?);
    try std.testing.expect(std.mem.indexOf(u8, bare_module_lookup_reason, "UserModule::Dump") != null);
}

test "a device path, an empty path and a relative path are not bare module names" {
    // A path on an unmounted device is a real degradation.
    try std.testing.expectEqual(@as(?[]const u8, null), bareModuleLookupName("!> F8000014 ResolvePath(cache:\\foo) failed - device not found"));
    try std.testing.expectEqual(Severity.advisory, classify("!> F8000014 ResolvePath(cache:\\foo) failed - device not found"));
    // The empty form keeps its own, louder rule.
    try std.testing.expectEqual(@as(?[]const u8, null), bareModuleLookupName("!> F8000014 ResolvePath() failed - device not found"));
    try std.testing.expectEqual(Severity.fault, classify("!> F8000014 ResolvePath() failed - device not found"));
    try std.testing.expectEqual(@as(?[]const u8, null), bareModuleLookupName("!> F8000014 ResolvePath(..) failed - device not found"));
    try std.testing.expectEqual(@as(?[]const u8, null), bareModuleLookupName("!> F8000014 ResolvePath(a\\b) failed - device not found"));
}

test "an unbound title import is a fault" {
    const line = "w> F8000014 WARNING: an import variable was not resolved! (library: default, import lib: WavesLibDLL.dll, ordinal: 00C)";
    try std.testing.expect(isUnresolvedImport(line));
    try std.testing.expectEqual(Severity.fault, classify(line));
    try std.testing.expect(!isUnresolvedImport("!> F8000014 ResolvePath(WavesLibDLL) failed - device not found"));
}

test "known volume cleanup undefined externs are advisory and unknown ones stay loud" {
    const by_volume = "!> F8000054 undefined extern call to 8270D6E4 IoDismountVolume";
    const by_handle = "!> F8000014 undefined extern call to 8270D7E4 IoDismountVolumeByFileHandle";
    const lines = [_][]const u8{ by_volume, by_handle };
    for (lines) |line| {
        try std.testing.expect(optionalVolumeExternName(line) != null);
        try std.testing.expectEqual(Severity.advisory, classify(line));
        try std.testing.expectEqual(Continuation.emulator_design, continuationFor(line));
        try std.testing.expectEqualStrings("xbox-volume-cleanup-extern", labelFor(line));
        const entry = entryFor(line).?;
        try std.testing.expect(std.mem.indexOf(u8, entry.reason, "returned zero") != null);
    }

    const unknown = "!> F8000054 undefined extern call to 8270AAAA IoQueryUnknownVolumeState";
    try std.testing.expectEqual(@as(?[]const u8, null), optionalVolumeExternName(unknown));
    try std.testing.expectEqual(Severity.fault, classify(unknown));
    try std.testing.expectEqual(Continuation.stops, continuationFor(unknown));

    const malformed = "!> F8000054 undefined extern call to not-an-address IoDismountVolume";
    try std.testing.expectEqual(@as(?[]const u8, null), optionalVolumeExternName(malformed));
    try std.testing.expectEqual(Severity.fault, classify(malformed));
}

test "explicit Xenia allocation fallbacks are advisory emulator design" {
    const debug_memory = "w> F8000054 Game is attempting to allocate devkit debug memory (base: 00000000, size: 000FF000). Ignoring debug flag and using normal allocation.";
    const allocation_hint = "w> F8000064 NtSetInformationFile ignoring alloc";
    try std.testing.expectEqual(Severity.advisory, classify(debug_memory));
    try std.testing.expectEqual(Continuation.emulator_design, continuationFor(debug_memory));
    try std.testing.expectEqualStrings("xbox-devkit-debug-memory-fallback", labelFor(debug_memory));
    try std.testing.expectEqual(Severity.advisory, classify(allocation_hint));
    try std.testing.expectEqual(Continuation.emulator_design, continuationFor(allocation_hint));
    try std.testing.expectEqualStrings("xbox-file-allocation-hint-ignored", labelFor(allocation_hint));
}

test "an empty ResolvePath stays loud until provenance is supplied" {
    try std.testing.expect(isEmptyResolvePath("!> F8000014 ResolvePath() failed - device not found"));
    try std.testing.expectEqual(Severity.fault, classify("!> F8000014 ResolvePath() failed - device not found"));
    try std.testing.expect(!isEmptyResolvePath("!> F8000014 ResolvePath(WavesLibDLL) failed - device not found"));
}

test "a warning stops the run unless a named ground says continuing is sound" {
    const tessellation = "w> 0100000C VulkanPipelineCache: Failed to create one or more tessellation shaders - tessellation will not be available";
    try std.testing.expectEqual(Continuation.stops, continuationFor(tessellation));
    try std.testing.expectEqualStrings("vulkan-tessellation-unavailable", labelFor(tessellation));
    const unknown = "w> 00000001 something nobody has classified";
    try std.testing.expectEqual(Continuation.stops, continuationFor(unknown));
    try std.testing.expectEqualStrings("guest-warning-unclassified", labelFor(unknown));
    try std.testing.expectEqual(Continuation.stops, continuationFor("!> F8000014 ResolvePath() failed - device not found"));
    try std.testing.expectEqualStrings("vfs-empty-object-name", labelFor("!> F8000014 ResolvePath() failed - device not found"));
    try std.testing.expectEqual(Continuation.rosette_policy, continuationFor("w> 00000001 Unable to load Japanese font; JP characters will be boxes"));
    try std.testing.expectEqual(Continuation.narration, continuationFor("w> 00000005 * 0: Apple M2 Max"));
    try std.testing.expectEqual(Continuation.narration, continuationFor("!> F8000014 ResolvePath(WavesLibDLL) failed - device not found"));
}

test "every row has a unique label, and only policy, design or narration continues" {
    for (entries, 0..) |entry, index| {
        try std.testing.expect(entry.label.len != 0);
        for (entries[index + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, entry.label, other.label));
        }
        switch (entry.continuation) {
            .narration => try std.testing.expectEqual(Severity.informational, entry.severity),
            // A policy row has to point at the Rosette ledger that made the
            // decision, or it is a guess wearing a policy's name.
            .rosette_policy => try std.testing.expect(entry.evidence != .none),
            .emulator_design, .stops => try std.testing.expect(entry.severity != .informational),
        }
    }
}

test "an unrecognized warning is a fault, so a new one is loud by default" {
    try std.testing.expectEqual(Severity.fault, classify("w> 00000001 Something nobody has classified yet"));
    try std.testing.expectEqual(Severity.fault, classify(""));
}

test "every entry carries a reason and the filter agrees with an unfiltered scan" {
    for (entries) |entry| {
        try std.testing.expect(entry.text.len != 0);
        try std.testing.expect(entry.reason.len != 0);
    }
    // The rare-character filter is only sound if it never rejects a line an
    // ordinary substring scan would have matched. Check both paths agree over
    // every phrase in the table plus a line that matches nothing.
    const subjects = [_][]const u8{
        "w> 00000005 Available Vulkan physical devices",
        "w> 0100000C tessellation will not be available",
        "!> 00000001 Presenter: Failed to create a DXGI factory",
        "w> 00000005 BaseHeap::AllocFixed attempting commit on unreserved page",
        "w> F8000014 WARNING: an import variable was not resolved! (library: x)",
        "i> 00000001 an ordinary line",
        "",
    };
    for (subjects) |subject| {
        var expected: ?usize = null;
        for (entries, 0..) |entry, index| {
            if (std.mem.indexOf(u8, subject, entry.text) != null) {
                expected = index;
                break;
            }
        }
        try std.testing.expectEqual(expected, filter.firstMatch(subject));
    }
}

test "no entry is shadowed by an earlier one that contains it" {
    for (entries, 0..) |entry, index| {
        for (entries[0..index]) |earlier| {
            if (std.mem.indexOf(u8, entry.text, earlier.text) != null) {
                std.debug.print(
                    "unreachable entry: '{s}' always matches the earlier '{s}' first\n",
                    .{ entry.text, earlier.text },
                );
                return error.ShadowedEntry;
            }
        }
    }
}
