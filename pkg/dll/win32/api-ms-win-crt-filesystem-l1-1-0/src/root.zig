//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "api-ms-win-crt-filesystem-l1-1-0.dll";
pub const stem = "api-ms-win-crt-filesystem-l1-1-0";
pub const match_prefix = "";
pub const subsystem_name = "unrecognized";

pub const degraded_imports = [_][]const u8{
    "_access",
    "_findclose",
    "_fstat64",
    "_lock_file",
    "_unlock_file",
    "_waccess",
    "_wchdir",
    "_wchmod",
    "_wfindfirst64i32",
    "_wfindnext64i32",
    "_wfullpath",
    "_wmkdir",
    "_wstat64",
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
    try std.testing.expect(matches("api-ms-win-crt-filesystem-l1-1-0.dll"));
    try std.testing.expect(matches("api-ms-win-crt-filesystem-l1-1-0"));
    try std.testing.expect(hasDegradedImport("_access"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from api-ms-win-crt-filesystem-l1-1-0.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "_access", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_findclose", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_fstat64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_lock_file", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_unlock_file", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_waccess", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wchdir", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wchmod", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wfindfirst64i32", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wfindnext64i32", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wfullpath", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wmkdir", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped status where zero is success and -1 is failure; the sign is the answer" },
    .{ .name = "_wstat64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
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
