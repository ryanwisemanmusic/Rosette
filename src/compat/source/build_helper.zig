const std = @import("std");

pub fn addMacOSCompatIncludePath(b: *std.Build, module: *std.Build.Module, is_macos: bool) void {
    if (is_macos) module.addIncludePath(b.path("../include/shims/macos"));
    module.addIncludePath(b.path("../include/shims/win32"));
    module.addIncludePath(b.path("../include"));
}

pub fn compatCFlags(is_macos: bool) []const []const u8 {
    if (!is_macos) return &.{};
    return &.{ "-include", "shims/macos/compiler_compat.h" };
}

pub fn stbCompatCFlag(is_macos: bool) []const []const u8 {
    if (!is_macos) return &.{};
    return &.{ "-include", "shims/macos/stb_compat.h" };
}

pub fn posixCompatCFlag(is_macos: bool) []const []const u8 {
    if (!is_macos) return &.{};
    return &.{ "-include", "shims/macos/posix_compat.h" };
}
