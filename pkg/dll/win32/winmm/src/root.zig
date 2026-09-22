//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "WINMM.dll";
pub const stem = "winmm";
pub const match_prefix = "";
pub const subsystem_name = "multimedia";

pub const degraded_imports = [_][]const u8{
    "PlaySoundW",
    "timeBeginPeriod",
    "timeEndPeriod",
    "waveInAddBuffer",
    "waveInClose",
    "waveInGetDevCapsW",
    "waveInGetNumDevs",
    "waveInOpen",
    "waveInPrepareHeader",
    "waveInReset",
    "waveInStart",
    "waveInUnprepareHeader",
    "waveOutClose",
    "waveOutGetDevCapsW",
    "waveOutGetErrorTextW",
    "waveOutGetNumDevs",
    "waveOutOpen",
    "waveOutPrepareHeader",
    "waveOutReset",
    "waveOutUnprepareHeader",
    "waveOutWrite",
};

pub fn matches(name: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(name, stem)) return true;
    return name.len == stem.len + 4 and
        std.ascii.eqlIgnoreCase(name[0..stem.len], stem) and
        std.ascii.eqlIgnoreCase(name[stem.len..], ".dll");
}

pub fn hasDegradedImport(function_name: []const u8) bool {
    for (degraded_imports) |known| {
        if (std.mem.eql(u8, function_name, known)) return true;
    }
    return false;
}

test "DLL identity is case-insensitive and the degraded inventory is local" {
    try std.testing.expect(matches("WINMM.dll"));
    try std.testing.expect(matches("winmm"));
    try std.testing.expect(hasDegradedImport("PlaySoundW"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from WINMM.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "PlaySoundW", .arity = 3, .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "timeBeginPeriod", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "timeEndPeriod", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInAddBuffer", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInClose", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInGetDevCapsW", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInGetNumDevs", .arity = 0, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the device count; zero means no devices, which is an answer and not a failure" },
    .{ .name = "waveInOpen", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInPrepareHeader", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInReset", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInStart", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveInUnprepareHeader", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutClose", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutGetDevCapsW", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutGetErrorTextW", .arity = 3, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: zero is MMSYSERR_NOERROR" },
    .{ .name = "waveOutGetNumDevs", .arity = 0, .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "returns the device count; zero means no devices, which is an answer and not a failure" },
    .{ .name = "waveOutOpen", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutPrepareHeader", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutReset", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutUnprepareHeader", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
    .{ .name = "waveOutWrite", .convention = .zero_count, .behaviour = .served, .zero_is_an_answer = true, .reviewed = true, .note = "an MMRESULT: MMSYSERR_NOERROR is zero, so zero is success and non-zero is the error" },
};

pub const surface = export_contract.Surface{
    .dll_name = dll_name,
    .stem = stem,
    .exports = &exports,
};

/// What this library's ABI says about one export, or null when the image does
/// not import it. Null is a real answer: it means the guest cannot reach this
/// name through the import table, whatever else it might do.
pub fn findExport(function_name: []const u8) ?export_contract.Export {
    return surface.find(function_name);
}

test "the declared surface is complete, unique, and agrees with itself" {
    try std.testing.expect(exports.len != 0);
    try std.testing.expect(!export_contract.hasDuplicate(&exports));
    for (exports) |entry| {
        try std.testing.expect(entry.name.len != 0);
        if (entry.arity) |arity| try std.testing.expect(arity <= export_contract.max_declared_arity);
        // A name declared here must also be findable, or `findExport` and the
        // table would disagree about the same library.
        try std.testing.expect(findExport(entry.name) != null);
    }
    try std.testing.expectEqual(@as(?export_contract.Export, null), findExport("__not_in_this_dll__"));
    // Every degraded name is part of the surface: the two lists described the
    // same library and nothing compared them.
    for (degraded_imports) |name| {
        try std.testing.expect(findExport(name) != null);
    }
}
// --- end generated export table ---
