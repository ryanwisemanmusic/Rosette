const std = @import("std");

/// Capstone ARM/ARM64 type pre-definitions for macOS ABI compat.
///
/// On Apple Clang in C++ mode, enum types have a different ABI from
/// plain `int`. Libraries like capstone that define e.g. `arm_cc` as
/// an enum in their C headers produce link-time type mismatches when
/// consumed from C++ translation units.
///
/// This module provides the type definitions in both Zig and C forms:
///   - The Zig `extern` types export the correct ABI sizes so that
///     any Zig code that interacts with capstone (or similar libs)
///     uses the right calling convention.
///   - `cHeaderPath` returns the path to a C header that pre-`#define`s
///     the same types before the library's own headers are included.
///
/// Usage from build.zig:
/// ```zig
/// const ft = @import("src/compat/source/force_types.zig");
/// if (comptime ft.detectCapstoneUsage(io, allocator, src_dir)) {
///     mod.addIncludePath(ft.cHeaderDir());
///     // or add -include flag with ft.cHeaderPath()
/// }
/// ```
/// arm_cc treated as c_int (i32) for C ABI compatibility.
pub const arm_cc = c_int;
pub const arm64_cc = c_int;
pub const arm_reg = c_int;
pub const arm64_reg = c_int;
/// arm and arm64 are opaque pointers.
pub const arm = ?*anyopaque;
pub const arm64 = ?*anyopaque;

/// Returns the relative path to the C compat header that pre-defines
/// these types for C/C++ translation units.
pub fn cHeaderPath() []const u8 {
    return "shims/macos/force_types.h";
}

/// Returns the directory containing the compat header (for addIncludePath).
pub fn cHeaderDir() []const u8 {
    return "include";
}

/// Scan a source directory tree for capstone usage patterns.
/// Returns true if any C/C++ file includes capstone headers or
/// uses capstone type names, indicating the type fix is needed.
pub fn detectCapstoneUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.basename;
        if (!hasHeaderExtension(name) and
            !std.ascii.endsWithIgnoreCase(name, ".c") and
            !std.ascii.endsWithIgnoreCase(name, ".cc") and
            !std.ascii.endsWithIgnoreCase(name, ".cpp") and
            !std.ascii.endsWithIgnoreCase(name, ".cxx") and
            !std.ascii.endsWithIgnoreCase(name, ".m") and
            !std.ascii.endsWithIgnoreCase(name, ".mm"))
            continue;
        const content = entry.dir.readFileAlloc(io, name, allocator, .limited(32 * 4096)) catch continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "#include <capstone")) |_| return true;
        if (std.mem.indexOf(u8, content, "#include \"capstone")) |_| return true;
        if (std.mem.indexOf(u8, content, "arm_cc") != null and
            std.mem.indexOf(u8, content, "arm64_cc") != null and
            std.mem.indexOf(u8, content, "arm_reg") != null and
            std.mem.indexOf(u8, content, "arm64_reg") != null)
            return true;
    }
    return false;
}

fn hasHeaderExtension(name: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(name, ".h") or
        std.ascii.endsWithIgnoreCase(name, ".hh") or
        std.ascii.endsWithIgnoreCase(name, ".hpp") or
        std.ascii.endsWithIgnoreCase(name, ".hxx");
}

test "force_types exports match C ABI expectations" {
    try std.testing.expect(@sizeOf(arm_cc) == @sizeOf(c_int));
    try std.testing.expect(@sizeOf(arm64_cc) == @sizeOf(c_int));
    try std.testing.expect(@sizeOf(arm_reg) == @sizeOf(c_int));
    try std.testing.expect(@sizeOf(arm64_reg) == @sizeOf(c_int));
    try std.testing.expect(@sizeOf(arm) == @sizeOf(?*anyopaque));
}

test "cHeaderPath returns valid path" {
    try std.testing.expect(std.mem.endsWith(u8, cHeaderPath(), "force_types.h"));
}

test "detectCapstoneUsage returns false for non-existent dir" {
    try std.testing.expect(!detectCapstoneUsage(.failing, std.testing.allocator, "/nonexistent_R2Jqk9"));
}
