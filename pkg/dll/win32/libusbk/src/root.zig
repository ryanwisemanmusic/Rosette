//! Static facts for the optional libusbK Windows backend.
//!
//! Xenia probes this third-party backend while looking for a USB transport.
//! Rosetta deliberately has no libusbK device backend on macOS, but the DLL
//! identity is still owned explicitly so a missing optional probe is reported
//! as policy rather than as an unclassified import gap.

const std = @import("std");

pub const dll_name = "libusbK.dll";
pub const stem = "libusbk";
pub const match_prefix = "";
pub const subsystem_name = "device_enumeration";

/// The module is a deliberate no-backend policy. Its exports are not
/// resolved because LoadLibraryA returns the documented absent-module result
/// before Xenia asks for them.
pub const degraded_imports = [_][]const u8{};

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

test "libusbK is an explicit optional backend package" {
    try std.testing.expect(matches("libusbK.dll"));
    try std.testing.expect(matches("LIBUSBK"));
    try std.testing.expect(!hasDegradedImport("libusbK_Initialize"));
}
