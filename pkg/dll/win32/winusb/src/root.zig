//! Static facts for the WinUSB user-mode USB DLL.
//!
//! libusb resolves this DLL as a **whole list**. `winusbx_init` calls
//! `WinUSB_Set(hWinUSB, <name>, true)` twelve times, and the `true` means
//! "required": one missing name tears the whole WinUSB sub-API down and
//! `FreeLibrary`s the module. Serving the names one at a time therefore
//! achieves nothing - each run simply reports the next one. The 2026-09-12
//! runs reported `WinUsb_AbortPipe`, then `WinUsb_ControlTransfer`, which is
//! that pattern exactly.
//!
//! ## The optional one is load-bearing
//!
//! After the twelve, libusb probes `WinUSB_Set(hWinUSB, ReadIsochPipeAsap,
//! false)` - optional - and only if that resolves does it go on to require
//! `QueryPipeEx`, `RegisterIsochBuffer`, `UnregisterIsochBuffer` and
//! `WriteIsochPipeAsap`. Rosetta models no isochronous USB transport, so
//! refusing `ReadIsochPipeAsap` is the correct answer and it keeps the four
//! isochronous names out of the conversation entirely. Serving it would
//! promise a transport that does not exist and turn four more names into
//! required ones.
//!
//! ## What this package proves, and what it does not
//!
//! It is the name list and the required/optional split, nothing more. Whether
//! a call is served, what it returns, and what a refused optional probe does
//! to libusb's control flow all stay in the dispatcher.

const std = @import("std");

pub const dll_name = "WINUSB.dll";
pub const stem = "winusb";
pub const match_prefix = "";
pub const subsystem_name = "device_enumeration";

/// The twelve names `winusbx_init` requires. Missing any one of them makes
/// libusb discard the whole WinUSB backend.
pub const required_imports = [_][]const u8{
    "WinUsb_AbortPipe",
    "WinUsb_ControlTransfer",
    "WinUsb_FlushPipe",
    "WinUsb_Free",
    "WinUsb_GetAssociatedInterface",
    "WinUsb_Initialize",
    "WinUsb_ReadPipe",
    "WinUsb_ResetPipe",
    "WinUsb_SetCurrentAlternateSetting",
    "WinUsb_SetPipePolicy",
    "WinUsb_GetPipePolicy",
    "WinUsb_WritePipe",
};

/// Probed with `required = false`. Its absence is a supported configuration -
/// Windows before 8.1 did not have it - and its absence is what keeps
/// `isochronous_imports` from ever being asked for.
pub const optional_probe = "WinUsb_ReadIsochPipeAsap";

/// Required only when `optional_probe` resolves. Rosetta refuses that probe,
/// so these are never reached; they are listed so a future reader can see the
/// whole shape rather than rediscovering it from libusb's source.
pub const isochronous_imports = [_][]const u8{
    "WinUsb_QueryPipeEx",
    "WinUsb_RegisterIsochBuffer",
    "WinUsb_UnregisterIsochBuffer",
    "WinUsb_WriteIsochPipeAsap",
};

pub const degraded_imports = required_imports;

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

/// Whether Rosetta deliberately declines this name.
///
/// Distinct from "not modelled": the probe is optional, and answering it with
/// NULL is the answer that keeps libusb on a transport Rosetta can serve.
pub fn isDeliberateRefusal(function_name: []const u8) bool {
    if (std.mem.eql(u8, function_name, optional_probe)) return true;
    for (isochronous_imports) |name| {
        if (std.mem.eql(u8, function_name, name)) return true;
    }
    return false;
}

pub fn importCount() usize {
    return required_imports.len;
}

test "the whole required list is owned, because libusb takes it all or none" {
    try std.testing.expect(matches("WinUSB.dll"));
    try std.testing.expect(matches("winusb"));
    // Both names the 2026-09-12 runs reported, one per run, because each was
    // served alone and libusb simply asked for the next.
    try std.testing.expect(hasDegradedImport("WinUsb_AbortPipe"));
    try std.testing.expect(hasDegradedImport("WinUsb_ControlTransfer"));
    try std.testing.expectEqual(@as(usize, 12), importCount());
    for (required_imports) |name| {
        try std.testing.expect(std.mem.startsWith(u8, name, "WinUsb_"));
        try std.testing.expect(hasDegradedImport(name));
        try std.testing.expect(!isDeliberateRefusal(name));
    }
}

test "the isochronous probe is refused on purpose, and its dependants with it" {
    // `WinUSB_Set(hWinUSB, ReadIsochPipeAsap, false)` is optional. Serving it
    // would promise a transport Rosetta does not model and would make four
    // more names required.
    try std.testing.expect(isDeliberateRefusal(optional_probe));
    try std.testing.expect(!hasDegradedImport(optional_probe));
    for (isochronous_imports) |name| {
        try std.testing.expect(isDeliberateRefusal(name));
        try std.testing.expect(!hasDegradedImport(name));
    }
}

test "no name appears in both lists" {
    for (required_imports, 0..) |name, index| {
        for (required_imports[0..index]) |earlier| {
            try std.testing.expect(!std.mem.eql(u8, earlier, name));
        }
        for (isochronous_imports) |isoch| {
            try std.testing.expect(!std.mem.eql(u8, isoch, name));
        }
        try std.testing.expect(!std.mem.eql(u8, optional_probe, name));
    }
}
