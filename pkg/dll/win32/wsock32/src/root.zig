//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "WSOCK32.dll";
pub const stem = "wsock32";
pub const match_prefix = "";
pub const subsystem_name = "networking";

pub const degraded_imports = [_][]const u8{
    "__WSAFDIsSet",
    "accept",
    "bind",
    "getsockname",
    "htonl",
    "inet_addr",
    "listen",
    "ntohl",
    "recvfrom",
    "sendto",
    "shutdown",
    "WSAGetLastError",
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
    try std.testing.expect(matches("WSOCK32.dll"));
    try std.testing.expect(matches("wsock32"));
    try std.testing.expect(hasDegradedImport("__WSAFDIsSet"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from WSOCK32.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "WSAGetLastError", .arity = 0, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "the error code itself; zero means no error" },
    .{ .name = "WSAStartup", .convention = .winsock_status, .behaviour = .modelled, .reviewed = true },
    .{ .name = "__WSAFDIsSet", .arity = 2, .convention = .bool32, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true },
    .{ .name = "accept", .convention = .invalid_handle, .behaviour = .modelled, .reviewed = true, .note = "INVALID_SOCKET is (SOCKET)-1, not NULL" },
    .{ .name = "bind", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "closesocket", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "connect", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "getsockname", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "getsockopt", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "htonl", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a pure byte-order or parse conversion" },
    .{ .name = "inet_addr", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a pure byte-order or parse conversion" },
    .{ .name = "ioctlsocket", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "listen", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "ntohl", .arity = 1, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "a pure byte-order or parse conversion" },
    .{ .name = "recv", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns bytes received; zero means the peer performed an orderly shutdown, which is an answer" },
    .{ .name = "recvfrom", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns bytes received; zero means the peer performed an orderly shutdown, which is an answer" },
    .{ .name = "select", .arity = 5, .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns ready descriptors; zero means the timeout expired" },
    .{ .name = "send", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns bytes sent; -1 is SOCKET_ERROR" },
    .{ .name = "sendto", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "returns bytes sent; -1 is SOCKET_ERROR" },
    .{ .name = "setsockopt", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "shutdown", .convention = .zero_count, .behaviour = .modelled, .zero_is_an_answer = true, .reviewed = true, .note = "zero is success and SOCKET_ERROR (-1) is failure, so a zero here must never read as a refusal" },
    .{ .name = "socket", .convention = .invalid_handle, .behaviour = .modelled, .reviewed = true, .note = "INVALID_SOCKET is (SOCKET)-1, not NULL" },
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
