const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

/// Keeps the interactive console concise while preserving the complete
/// diagnostic stream in `.rosette/rosette-runtime.log`. Set
/// ROSETTE_MACHO_VERBOSE_STDOUT=1 to retain the legacy console behavior.
pub const Controller = struct {
    concise: bool = false,
    saved_stderr: i32 = -1,
    detail_fd: i32 = -1,

    pub fn init(allocator: std.mem.Allocator) Controller {
        if (environmentFlag("ROSETTE_MACHO_VERBOSE_STDOUT")) return .{};
        const root = routeRoot() orelse return .{};
        const path = std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-runtime.log" }) catch return .{};
        defer allocator.free(path);
        const directory = std.fs.path.dirname(path) orelse return .{};
        makePathRecursive(allocator, directory) catch return .{};
        const path_z = allocator.dupeZ(u8, path) catch return .{};
        defer allocator.free(path_z);
        const detail_fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
        if (detail_fd < 0) return .{};
        const saved_stderr = c.dup(c.STDERR_FILENO);
        if (saved_stderr < 0 or c.dup2(detail_fd, c.STDERR_FILENO) < 0) {
            if (saved_stderr >= 0) _ = c.close(saved_stderr);
            _ = c.close(detail_fd);
            return .{};
        }
        return .{ .concise = true, .saved_stderr = saved_stderr, .detail_fd = detail_fd };
    }

    pub fn deinit(self: *Controller) void {
        if (self.saved_stderr >= 0) {
            _ = c.dup2(self.saved_stderr, c.STDERR_FILENO);
            _ = c.close(self.saved_stderr);
        }
        if (self.detail_fd >= 0) _ = c.close(self.detail_fd);
        self.* = .{};
    }

    pub fn human(self: *const Controller, comptime format: []const u8, args: anytype) void {
        if (!self.concise) return;
        var buffer: [512]u8 = undefined;
        const line = std.fmt.bufPrint(&buffer, format, args) catch return;
        writeAll(c.STDOUT_FILENO, line);
    }

    pub fn diagnosticsFd(self: *const Controller) i32 {
        return if (self.concise) c.STDERR_FILENO else c.STDOUT_FILENO;
    }
};

fn writeAll(fd: i32, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const result = c.write(fd, bytes.ptr + written, bytes.len - written);
        if (result <= 0) return;
        written += @intCast(result);
    }
}

fn environmentFlag(name: [*:0]const u8) bool {
    const raw = c.getenv(name) orelse return false;
    const value = std.mem.span(raw);
    if (value.len == 0 or std.mem.eql(u8, value, "0")) return false;
    return !std.ascii.eqlIgnoreCase(value, "false") and !std.ascii.eqlIgnoreCase(value, "off");
}

fn routeRoot() ?[]const u8 {
    const names = [_][*:0]const u8{
        "ROSETTE_TRACE_ROOT",
        "ROSETTE_ROUTE_ROOT",
        "ROSETTE_CALLER_CWD",
        "PWD",
    };
    for (names) |name| {
        const raw = c.getenv(name) orelse continue;
        const value = std.mem.span(raw);
        if (value.len != 0) return value;
    }
    return null;
}

fn makePathRecursive(allocator: std.mem.Allocator, raw_path: []const u8) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);
    if (raw_path[0] == '/') try current.append(allocator, '/');
    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') try current.append(allocator, '/');
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        defer allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0 and c.access(path_z.ptr, c.F_OK) != 0) return error.MakePathFailed;
    }
}

test "verbose override values are interpreted conventionally" {
    try std.testing.expect(!std.ascii.eqlIgnoreCase("true", "off"));
}
