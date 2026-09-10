//! Static facts for one Windows DLL import surface.
//!
//! This package deliberately contains no runtime effects. The dispatcher
//! owns behavior; this folder owns the names that may be classified as
//! recognized-but-degraded for this DLL.

const std = @import("std");

pub const dll_name = "ole32.dll";
pub const stem = "ole32";
pub const match_prefix = "";
pub const subsystem_name = "component_object";

pub const degraded_imports = [_][]const u8{
    "CLSIDFromString",
    "CoCreateInstance",
    "PropVariantClear",
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
    try std.testing.expect(matches("ole32.dll"));
    try std.testing.expect(matches("ole32"));
    try std.testing.expect(hasDegradedImport("CLSIDFromString"));
    try std.testing.expect(!hasDegradedImport("__not_in_this_dll__"));
}
