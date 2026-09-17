//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "api-ms-win-crt-string-l1-1-0.dll";
pub const stem = "api-ms-win-crt-string-l1-1-0";
pub const match_prefix = "";
pub const subsystem_name = "unrecognized";

pub const degraded_imports = [_][]const u8{
    "_strdup",
    "_stricmp",
    "_strnicmp",
    "_strrev",
    "_wcsicmp",
    "_wcsnicmp",
    "isalnum",
    "isalpha",
    "isblank",
    "iscntrl",
    "isgraph",
    "islower",
    "isprint",
    "ispunct",
    "isspace",
    "isupper",
    "iswctype",
    "isxdigit",
    "mbrlen",
    "strcoll",
    "strcspn",
    "strncat",
    "strspn",
    "strtok",
    "strxfrm",
    "towlower",
    "towupper",
    "wcscat",
    "wcscmp",
    "wcscoll",
    "wcscpy",
    "wcsxfrm",
    "wctype",
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
    try std.testing.expect(matches("api-ms-win-crt-string-l1-1-0.dll"));
    try std.testing.expect(matches("api-ms-win-crt-string-l1-1-0"));
    try std.testing.expect(hasDegradedImport("_strdup"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from api-ms-win-crt-string-l1-1-0.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "_strdup", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "_stricmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "_strnicmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "_strrev", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "_wcsicmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "_wcsnicmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "isalnum", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "isalpha", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "isblank", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "iscntrl", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "isgraph", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "islower", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "isprint", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "ispunct", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "isspace", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "isupper", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "iswctype", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "isxdigit", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
    .{ .name = "mbrlen", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "memset", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "strcmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "strcoll", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "strcpy", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "strcspn", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "strlen", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "strncat", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "strncmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "strncpy", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "strspn", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "strtok", .convention = .handle, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "strxfrm", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "tolower", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "toupper", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "towlower", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "towupper", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "wcscat", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "wcscmp", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "wcscoll", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "wcscpy", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns its destination or NULL; the string family never sets errno" },
    .{ .name = "wcslen", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "wcsxfrm", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a comparison or a length: zero means equal or empty, never failure" },
    .{ .name = "wctype", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a character classification: zero means the predicate is false, which is the answer" },
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
