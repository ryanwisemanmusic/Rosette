//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "api-ms-win-crt-runtime-l1-1-0.dll";
pub const stem = "api-ms-win-crt-runtime-l1-1-0";
pub const match_prefix = "";
pub const subsystem_name = "unrecognized";

pub const degraded_imports = [_][]const u8{
    "__p___argc",
    "__p___argv",
    "__p__wcmdln",
    "_assert",
    "_cexit",
    "_configure_narrow_argv",
    "_configure_wide_argv",
    "_crt_at_quick_exit",
    "_crt_atexit",
    "_errno",
    "_exit",
    "_get_errno",
    "_get_wpgmptr",
    "_initialize_narrow_environment",
    "_initialize_wide_environment",
    "_register_thread_local_exe_atexit_callback",
    "_set_app_type",
    "_set_errno",
    "_set_invalid_parameter_handler",
    "abort",
    "exit",
    "signal",
    "strerror",
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
    try std.testing.expect(matches("api-ms-win-crt-runtime-l1-1-0.dll"));
    try std.testing.expect(matches("api-ms-win-crt-runtime-l1-1-0"));
    try std.testing.expect(hasDegradedImport("__p___argc"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from api-ms-win-crt-runtime-l1-1-0.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "__p___argc", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "__p___argv", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "__p___wargv", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "__p__wcmdln", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "_assert", .convention = .void_call, .behaviour = .refused_by_policy, .zero_is_an_answer = true, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "_beginthreadex", .arity = 6, .convention = .handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "_cexit", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "_configure_narrow_argv", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_configure_wide_argv", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_crt_at_quick_exit", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t: zero registers the guest callback, nonzero rejects it" },
    .{ .name = "_crt_atexit", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t: zero registers the guest callback, nonzero rejects it" },
    .{ .name = "_endthreadex", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "_errno", .convention = .handle, .behaviour = .modelled, .reviewed = true, .note = "returns a pointer to a CRT global the caller dereferences without checking; NULL is a guest crash" },
    .{ .name = "_exit", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "_get_errno", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t; zero is success and the errno value is read or written through the argument" },
    .{ .name = "_get_wpgmptr", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t; zero is success and writes the guest-owned executable path through wchar_t**" },
    .{ .name = "_initialize_narrow_environment", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_initialize_wide_environment", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_initterm", .arity = 2, .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "_register_thread_local_exe_atexit_callback", .arity = 1, .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "stores one guest TLS-exit callback; it is invoked with DLL_PROCESS_DETACH during full CRT cleanup" },
    .{ .name = "_set_app_type", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "_set_errno", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns errno_t; zero is success and the errno value is read or written through the argument" },
    .{ .name = "_set_invalid_parameter_handler", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a CRT bootstrap hook whose zero is success or is ignored entirely" },
    .{ .name = "abort", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "exit", .convention = .void_call, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "signal", .arity = 2, .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns the previous handler, or SIG_ERR (-1)" },
    .{ .name = "strerror", .arity = 1, .convention = .handle, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
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
