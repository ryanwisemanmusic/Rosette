const std = @import("std");
const testing = std.testing;

fn needsQuotes(value: []const u8) bool {
    if (value.len == 0) return true;
    for (value) |character| {
        if (character == '"' or character == ' ' or character == '\t' or character == '\n' or character == '\r') return true;
    }
    return false;
}

fn appendBackslashes(line: *std.ArrayList(u8), allocator: std.mem.Allocator, count: usize) !void {
    for (0..count) |_| try line.append(allocator, '\\');
}

fn appendArgument(line: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8, executable_path: bool) !void {
    if (line.items.len != 0) try line.append(allocator, ' ');
    if (!needsQuotes(value)) {
        for (value) |character| try line.append(allocator, if (executable_path and character == '/') '\\' else character);
        return;
    }

    try line.append(allocator, '"');
    var backslashes: usize = 0;
    for (value) |character| {
        if (character == '\\') {
            backslashes += 1;
            continue;
        }
        if (character == '"') {
            try appendBackslashes(line, allocator, backslashes * 2 + 1);
            try line.append(allocator, '"');
            backslashes = 0;
            continue;
        }
        try appendBackslashes(line, allocator, backslashes);
        try line.append(allocator, if (executable_path and character == '/') '\\' else character);
        backslashes = 0;
    }
    try appendBackslashes(line, allocator, backslashes * 2);
    try line.append(allocator, '"');
}

/// Build a Windows CRT-compatible ANSI command line. argv[0] is the PE path;
/// `arguments` contains the additional guest arguments supplied to the runner.
pub fn build(allocator: std.mem.Allocator, executable_path: []const u8, arguments: []const []const u8) ![]u8 {
    var line: std.ArrayList(u8) = .empty;
    errdefer line.deinit(allocator);
    try appendArgument(&line, allocator, executable_path, true);
    for (arguments) |argument| try appendArgument(&line, allocator, argument, false);
    return try line.toOwnedSlice(allocator);
}

test "command line quotes executable and guest arguments with CRT backslash rules" {
    const args = [_][]const u8{ "--mode", "one two", "quote\"inside", "ends\\" };
    const line = try build(testing.allocator, "/Games/3D Maze/Loader.exe", &args);
    defer testing.allocator.free(line);
    try testing.expectEqualStrings("\"\\Games\\3D Maze\\Loader.exe\" --mode \"one two\" \"quote\\\"inside\" ends\\", line);
}

test "command line quotes empty guest arguments" {
    const args = [_][]const u8{""};
    const line = try build(testing.allocator, "/Loader.exe", &args);
    defer testing.allocator.free(line);
    try testing.expectEqualStrings("\\Loader.exe \"\"", line);
}
