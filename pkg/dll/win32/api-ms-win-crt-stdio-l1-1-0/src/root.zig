//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "api-ms-win-crt-stdio-l1-1-0.dll";
pub const stem = "api-ms-win-crt-stdio-l1-1-0";
pub const match_prefix = "";
pub const subsystem_name = "unrecognized";

pub const degraded_imports = [_][]const u8{
    "__acrt_iob_func",
    "__p__commode",
    "__p__fmode",
    "__stdio_common_vfprintf",
    "__stdio_common_vfwprintf",
    "__stdio_common_vsprintf",
    "__stdio_common_vswprintf",
    "_close",
    "_filelengthi64",
    "_get_osfhandle",
    "_isatty",
    "_lseeki64",
    "_open_osfhandle",
    "_read",
    "_sopen",
    "_telli64",
    "_wfopen_s",
    "_wopen",
    "_write",
    "_wsopen",
    "feof",
    "ferror",
    "fgetc",
    "fgetpos",
    "fgets",
    "fopen_s",
    "fputc",
    "fputs",
    "fputwc",
    "freopen_s",
    "fsetpos",
    "getc",
    "getwc",
    "putc",
    "puts",
    "putwc",
    "setvbuf",
    "ungetc",
    "ungetwc",
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
    try std.testing.expect(matches("api-ms-win-crt-stdio-l1-1-0.dll"));
    try std.testing.expect(matches("api-ms-win-crt-stdio-l1-1-0"));
    try std.testing.expect(hasDegradedImport("__acrt_iob_func"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from api-ms-win-crt-stdio-l1-1-0.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "__acrt_iob_func", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "__p__commode", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "__p__fmode", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "__stdio_common_vfprintf", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns characters written, or negative on error; zero is an empty result" },
    .{ .name = "__stdio_common_vfwprintf", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns characters written, or negative on error; zero is an empty result" },
    .{ .name = "__stdio_common_vsprintf", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns characters written, or negative on error; zero is an empty result" },
    .{ .name = "__stdio_common_vswprintf", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns characters written, or negative on error; zero is an empty result" },
    .{ .name = "_chsize_s", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_close", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_filelengthi64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_fileno", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_get_osfhandle", .arity = 1, .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns the underlying guest handle, or -1 when the descriptor is invalid" },
    .{ .name = "_fseeki64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "_ftelli64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "_isatty", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "_lseeki64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_open_osfhandle", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns a CRT descriptor; zero is a valid descriptor and -1 is failure" },
    .{ .name = "_sopen", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns a CRT descriptor; zero is a valid descriptor and -1 is failure" },
    .{ .name = "_read", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "_telli64", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "_wsopen", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns a CRT descriptor; zero is a valid descriptor and -1 is failure" },
    .{ .name = "_wfopen", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "_wfopen_s", .arity = 3, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t; zero is success and the FILE* is written through the first argument" },
    .{ .name = "_wopen", .arity = 2, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns a CRT descriptor; zero is a valid descriptor and -1 is failure" },
    .{ .name = "_write", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "fclose", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "feof", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "ferror", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "fflush", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "fgetc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "fgetpos", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "fgets", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "fgetwc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "fopen", .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "fopen_s", .arity = 3, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t; zero is success and the FILE* is written through the first argument" },
    .{ .name = "fputc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "fputs", .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "fputwc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "fread", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns items transferred; zero is a short read, not a failure" },
    .{ .name = "freopen_s", .arity = 4, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t; zero is success and the FILE* is written through the first argument" },
    .{ .name = "fseek", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "fsetpos", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "ftell", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "fwrite", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns items transferred; zero is a short read, not a failure" },
    .{ .name = "getc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "getwc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "putc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "puts", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a POSIX-shaped stdio status or count where -1 is the failure value, not zero" },
    .{ .name = "putwc", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "setvbuf", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a stdio status where zero is success and EOF (-1) is failure" },
    .{ .name = "ungetc", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
    .{ .name = "ungetwc", .convention = .zero_count, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "returns the character or EOF" },
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
