const std = @import("std");
const fmt = @import("pe_format.zig");

pub const Source = enum {
    adjacent_cfg,
    synthesized,
};

pub const Architecture = enum {
    i386,
    amd64,
    unknown,
};

pub const UiMode = enum {
    console,
    windowed,
    unknown,
};

pub const Profile = struct {
    source: Source,
    executable_path: []const u8,
    working_directory: []const u8,
    config_path: ?[]const u8,
    architecture: Architecture,
    ui_mode: UiMode,
};

pub fn resolve(
    allocator: std.mem.Allocator,
    io: std.Io,
    exe_path: []const u8,
    machine: u16,
    subsystem: u16,
) !Profile {
    const absolute_exe = try std.fs.path.resolve(allocator, &.{exe_path});
    const exe_dir = std.fs.path.dirname(absolute_exe) orelse ".";
    const default_cwd = try allocator.dupe(u8, exe_dir);
    const extension = std.fs.path.extension(absolute_exe);
    const stem = if (std.ascii.eqlIgnoreCase(extension, ".exe"))
        absolute_exe[0 .. absolute_exe.len - extension.len]
    else
        absolute_exe;

    const candidates = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}.cfg", .{absolute_exe}),
        try std.fmt.allocPrint(allocator, "{s}.cfg", .{stem}),
        try std.fs.path.join(allocator, &.{ exe_dir, "rosette.cfg" }),
    };

    for (candidates) |candidate| {
        std.Io.Dir.cwd().access(io, candidate, .{}) catch continue;
        const contents = std.Io.Dir.cwd().readFileAlloc(io, candidate, allocator, .limited(64 * 1024)) catch continue;
        const configured_cwd = configuredWorkingDirectory(contents) orelse ".";
        const working_directory = if (std.fs.path.isAbsolute(configured_cwd))
            try allocator.dupe(u8, configured_cwd)
        else
            try std.fs.path.resolve(allocator, &.{ exe_dir, configured_cwd });
        return .{
            .source = .adjacent_cfg,
            .executable_path = absolute_exe,
            .working_directory = working_directory,
            .config_path = candidate,
            .architecture = architectureFor(machine),
            .ui_mode = uiModeFor(subsystem),
        };
    }

    return .{
        .source = .synthesized,
        .executable_path = absolute_exe,
        .working_directory = default_cwd,
        .config_path = null,
        .architecture = architectureFor(machine),
        .ui_mode = uiModeFor(subsystem),
    };
}

fn configuredWorkingDirectory(contents: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#' or line[0] == ';') continue;
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..separator], " \t");
        if (!std.ascii.eqlIgnoreCase(key, "cwd") and !std.ascii.eqlIgnoreCase(key, "working_directory")) continue;
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t\"");
        if (value.len != 0) return value;
    }
    return null;
}

fn architectureFor(machine: u16) Architecture {
    return switch (machine) {
        fmt.coff.machine_i386 => .i386,
        fmt.coff.machine_amd64 => .amd64,
        else => .unknown,
    };
}

fn uiModeFor(subsystem: u16) UiMode {
    return switch (subsystem) {
        fmt.coff.subsystem_windows_cui => .console,
        fmt.coff.subsystem_windows_gui => .windowed,
        else => .unknown,
    };
}

test "configuration values are optional" {
    try std.testing.expectEqual(@as(?[]const u8, null), configuredWorkingDirectory("# no launch overrides\n"));
    try std.testing.expectEqualStrings("assets", configuredWorkingDirectory("working_directory = \"assets\"\n").?);
    try std.testing.expectEqualStrings("bin", configuredWorkingDirectory("CWD=bin\n").?);
}

test "PE headers provide agnostic launch traits" {
    try std.testing.expectEqual(Architecture.i386, architectureFor(fmt.coff.machine_i386));
    try std.testing.expectEqual(Architecture.amd64, architectureFor(fmt.coff.machine_amd64));
    try std.testing.expectEqual(UiMode.console, uiModeFor(fmt.coff.subsystem_windows_cui));
    try std.testing.expectEqual(UiMode.windowed, uiModeFor(fmt.coff.subsystem_windows_gui));
}
