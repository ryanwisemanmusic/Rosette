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

pub const Entry = struct {
    /// Substring that identifies the line.
    text: []const u8,
    severity: Severity,
    /// Why it is classified this way, in one clause. A table of bare strings
    /// is unauditable: the next person cannot tell a considered
    /// `informational` from a guess.
    reason: []const u8,
};

/// Ordered most specific first.
pub const entries = [_]Entry{
    // --- Vulkan device selection. Xenia prints this whole block at warning
    // level even on a completely healthy pick.
    .{
        .text = "Available Vulkan physical devices",
        .severity = .informational,
        .reason = "the adapter list Xenia prints before choosing one",
    },
    .{
        .text = "use the 'vulkan_device' configuration variable",
        .severity = .informational,
        .reason = "the hint that accompanies the adapter list",
    },
    .{
        .text = "Chosen physical device",
        .severity = .informational,
        .reason = "states which adapter was selected; a selection is not a fault",
    },
    .{
        .text = "Vulkan device features",
        .severity = .informational,
        .reason = "capability narration, printed whether or not anything is missing",
    },

    // --- Degradations the run survives.
    .{
        .text = "tessellation will not be available",
        .severity = .advisory,
        .reason = "a real capability loss: titles using tessellated primitives will render wrong, but everything else proceeds",
    },
    .{
        .text = "Failed to create a DXGI factory",
        .severity = .advisory,
        .reason = "Direct3D/DXGI is outside the surface Rosette models; the presenter uses this only for vertical-blank pacing and paints without it",
    },
    .{
        .text = "Unable to load Japanese font",
        .severity = .advisory,
        .reason = "Rosette's font policy withheld the CJK font; Japanese glyphs render as boxes and the ImGui atlas stays small",
    },
    .{
        .text = "Unable to find Windows fonts directory",
        .severity = .advisory,
        .reason = "the guest falls back to its embedded font; only glyph coverage is affected",
    },
    .{
        .text = "Failed to load custom font",
        .severity = .advisory,
        .reason = "the guest falls back to its embedded font",
    },
    .{
        .text = "Unable to scan scratch path",
        .severity = .advisory,
        .reason = "an optional mount; the title runs without it",
    },
    .{
        .text = "Unable to scan cache",
        .severity = .advisory,
        .reason = "an optional mount; the title runs without it",
    },
    .{
        .text = "attempting commit on unreserved page",
        .severity = .advisory,
        .reason = "Xenia promotes the request internally and continues; Rosette keeps the reservation-versus-commit distinction visible because losing it silently is how a memory contract drifts",
    },
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

/// The severity of one Xenia warning-level line.
///
/// Unrecognized text is a `fault`: a warning nobody has classified has to stay
/// loud, or the next real one is quiet from the day it is introduced.
pub fn classify(line: []const u8) Severity {
    if (filter.firstMatch(line)) |index| return entries[index].severity;
    if (isListItem(line)) return .informational;
    return .fault;
}

/// The matching entry, for a report that wants to print why.
pub fn entryFor(line: []const u8) ?Entry {
    const index = filter.firstMatch(line) orelse return null;
    return entries[index];
}

pub fn entryCount() usize {
    return entries.len;
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
