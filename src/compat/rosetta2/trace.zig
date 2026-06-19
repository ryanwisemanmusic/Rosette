const std = @import("std");
const types = @import("types.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub fn defaultTracePath(allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_COMPAT_TRACE")) |path| {
        if (path.len != 0) return try allocator.dupe(u8, path);
    }
    if (try routeRoot(allocator)) |root| {
        return std.fs.path.join(allocator, &.{ root, ".rosette", "rosetta2-handoff.trace.log" });
    }
    const home = getenvSlice("HOME") orelse return "rosette2-handoff.trace.log";
    return std.fs.path.join(allocator, &.{ home, ".rosette", "logs", "rosetta2-handoff.trace.log" });
}

fn routeRoot(allocator: std.mem.Allocator) !?[]const u8 {
    const env_names = [_][:0]const u8{
        "ROSETTE_TRACE_ROOT",
        "ROSETTE_ROUTE_ROOT",
        "ROSETTE_CALLER_CWD",
        "PWD",
    };
    for (env_names) |name| {
        if (getenvSlice(name)) |value| {
            if (value.len != 0) return try allocator.dupe(u8, value);
        }
    }
    return null;
}

pub fn appendDecision(
    allocator: std.mem.Allocator,
    trace_path: []const u8,
    class: types.Classification,
    decision: types.Decision,
    argv: []const []const u8,
) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "# Rosette compatibility route\n");
    try appendKV(&out, allocator, "requested", class.requested_path);
    try appendKV(&out, allocator, "executable", class.executable_path);
    try appendKV(&out, allocator, "target_kind", class.target_kind.label());
    try appendKV(&out, allocator, "format", class.format.label());
    try appendKV(&out, allocator, "arch", class.arch.label());
    try appendKV(&out, allocator, "has_arm64", if (class.has_arm64) "true" else "false");
    try appendKV(&out, allocator, "has_x86_64", if (class.has_x86_64) "true" else "false");
    try appendKV(&out, allocator, "has_i386", if (class.has_i386) "true" else "false");
    try appendKV(&out, allocator, "classifier_note", class.note);
    try appendKV(&out, allocator, "selected_backend", decision.backend.label());
    try appendKV(&out, allocator, "fallback_reason", decision.reason.label());
    try appendKV(&out, allocator, "detail", decision.detail);
    try out.appendSlice(allocator, "argv = ");
    try appendArgs(&out, allocator, argv);
    try out.append(allocator, '\n');
    try out.append(allocator, '\n');

    try appendFilePath(allocator, trace_path, out.items);
}

fn appendKV(out: *std.ArrayList(u8), allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    try out.appendSlice(allocator, key);
    try out.appendSlice(allocator, " = ");
    try appendQuoted(out, allocator, value);
    try out.append(allocator, '\n');
}

fn appendArgs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, argv: []const []const u8) !void {
    for (argv, 0..) |arg, index| {
        if (index != 0) try out.append(allocator, ' ');
        try appendQuoted(out, allocator, arg);
    }
}

fn appendQuoted(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
    try out.append(allocator, '"');
}

fn appendFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const parent = std.fs.path.dirname(path);
    if (parent) |dir| try makePathRecursive(allocator, dir);
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "ab");
    if (fp == null) return error.FileWriteFailed;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.FileWriteFailed;
    }
}

fn makePathRecursive(allocator: std.mem.Allocator, raw_path: []const u8) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);

    if (raw_path[0] == '/') try current.append(allocator, '/');
    var it = std.mem.splitScalar(u8, raw_path, '/');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') try current.append(allocator, '/');
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        if (c.mkdir(path_z.ptr, 0o755) != 0) {
            if (c.access(path_z.ptr, 0) != 0) return error.MakePathFailed;
        }
    }
}

fn getenvSlice(name: [:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(value, 0);
}
