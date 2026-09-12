//! Static facts for the SHCore Windows DLL import surface.
//!
//! SHCore is the per-monitor DPI surface. Nothing links against it: a caller
//! loads it at runtime and probes for the entry points, because it does not
//! exist before Windows 8.1. Xenia's `Win32WindowedAppContext::Initialize`
//! does exactly that and keeps `per_monitor_dpi_v1_api_available_` off if the
//! probe fails.
//!
//! Naming these here is what lets the probe get a real answer. The names were
//! previously absent, so `GetProcAddress` returned NULL and Rosetta reported
//! an export refusal for a call it can in fact answer correctly - Rosetta
//! presents one virtual display at a fixed scale, which is precisely what
//! this API describes.

const std = @import("std");

pub const dll_name = "SHCore.dll";
pub const stem = "shcore";
pub const match_prefix = "";
pub const subsystem_name = "shell";

pub const degraded_imports = [_][]const u8{
    // The per-monitor DPI v1 API Xenia probes for.
    "GetDpiForMonitor",
    "GetScaleFactorForMonitor",
    // Process-wide DPI awareness. A guest that sets awareness and then reads
    // it back must see what it set, not a zero that means "unaware".
    "SetProcessDpiAwareness",
    "GetProcessDpiAwareness",
    // The stream and shell helpers SHCore also exports; named so a lookup
    // against them is classified as this library rather than as an
    // unattributed dynamic name.
    "CreateRandomAccessStreamOnFile",
    "CreateStreamOverRandomAccessStream",
    "SHCreateStreamOnFileEx",
    "SHQueryValueExW",
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

test "SHCore identity is case-insensitive, as a runtime-probed library's name always is" {
    try std.testing.expect(matches("SHCore.dll"));
    try std.testing.expect(matches("shcore.dll"));
    try std.testing.expect(matches("shcore"));
    try std.testing.expect(!matches("shcore2.dll"));
}

test "the per-monitor DPI probe Xenia performs resolves against this package" {
    try std.testing.expect(hasDegradedImport("GetDpiForMonitor"));
    try std.testing.expect(hasDegradedImport("SetProcessDpiAwareness"));
    try std.testing.expect(!hasDegradedImport("GetDpiForWindow")); // user32's, not this one's
}
