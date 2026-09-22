//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");
const export_contract = @import("dll_win32_export_contract");

pub const dll_name = "SETUPAPI.dll";
pub const stem = "setupapi";
pub const match_prefix = "";
pub const subsystem_name = "device_enumeration";

pub const degraded_imports = [_][]const u8{
    "CM_Get_Device_IDA",
    "CM_Get_Parent",
    "CM_Locate_DevNodeA",
    "SetupDiDestroyDeviceInfoList",
    "SetupDiEnumDeviceInfo",
    "SetupDiEnumDeviceInterfaces",
    "SetupDiGetClassDevsA",
    "SetupDiGetDeviceInterfaceDetailA",
    "SetupDiGetDeviceRegistryPropertyA",
    // libusb's `init_dlls` resolves these three after the ones above, all
    // with `ret_on_failure = true`: missing any one of them costs the whole
    // WinUSB backend, not one call.
    "SetupDiGetDeviceInstanceIdA",
    "SetupDiGetDeviceInstanceIdW",
    "SetupDiOpenDevRegKey",
    "SetupDiOpenDeviceInterfaceRegKey",
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
    try std.testing.expect(matches("SETUPAPI.dll"));
    try std.testing.expect(matches("setupapi"));
    try std.testing.expect(hasDegradedImport("CM_Get_Device_IDA"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}

// --- generated export table: tools/dll/generate_export_tables.py ---
/// Every name this image imports from SETUPAPI.dll, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{
    .{ .name = "CM_Get_Device_IDA", .convention = .ntstatus, .behaviour = .refused_by_policy, .reviewed = true, .note = "a CONFIGRET, which shares NTSTATUS' shape: CR_SUCCESS is zero" },
    .{ .name = "CM_Get_Parent", .convention = .ntstatus, .behaviour = .refused_by_policy, .reviewed = true, .note = "a CONFIGRET, which shares NTSTATUS' shape: CR_SUCCESS is zero" },
    .{ .name = "CM_Locate_DevNodeA", .convention = .ntstatus, .behaviour = .refused_by_policy, .reviewed = true, .note = "a CONFIGRET, which shares NTSTATUS' shape: CR_SUCCESS is zero" },
    .{ .name = "SetupDiDestroyDeviceInfoList", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetupDiEnumDeviceInfo", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetupDiEnumDeviceInterfaces", .convention = .bool32, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetupDiGetClassDevsA", .arity = 4, .convention = .invalid_handle, .behaviour = .modelled, .reviewed = true },
    .{ .name = "SetupDiGetDeviceInterfaceDetailA", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetupDiGetDeviceRegistryPropertyA", .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetupDiGetDeviceInstanceIdA", .arity = 5, .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetupDiGetDeviceInstanceIdW", .arity = 5, .convention = .bool32, .behaviour = .refused_by_policy, .reviewed = true, .note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS." },
    .{ .name = "SetupDiOpenDevRegKey", .convention = .invalid_handle, .behaviour = .refused_by_policy, .reviewed = true, .note = "returns a registry key or INVALID_HANDLE_VALUE, not NULL" },
    .{ .name = "SetupDiOpenDeviceInterfaceRegKey", .convention = .invalid_handle, .behaviour = .refused_by_policy, .reviewed = true, .note = "returns a registry key or INVALID_HANDLE_VALUE, not NULL" },
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
