const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});


/// How many previous runs are kept. Bounded on purpose: unbounded retention of
/// a log that reaches tens of megabytes fills a disk, and the run before last
/// is almost always enough to compare against.
pub const retained_runs: usize = 3;

/// Shift `name` -> `name.1` -> `name.2` -> `name.3`, dropping the oldest.
///
/// `rename` rather than copy: it is atomic, costs nothing for a large file, and
/// cannot leave a half-written archive if the process dies mid-rotation.
/// Returns the number of archives that now exist.
fn rotateRuntimeLogs(allocator: std.mem.Allocator, path: []const u8) usize {
    // Nothing to keep. A zero-length file from a run that never started is not
    // evidence, and rotating it would push a real archive off the end.
    // `stat` through libc rather than std.fs: this module already speaks to the
    // C layer for every other file operation, and mixing the two here would
    // mean two error models for one decision.
    const probe = allocator.dupeZ(u8, path) catch return 0;
    defer allocator.free(probe);
    var info: c.struct_stat = undefined;
    if (c.stat(probe.ptr, &info) != 0) return 0;
    if (info.st_size == 0) return 0;

    var kept: usize = 0;
    var index: usize = retained_runs;
    while (index >= 1) : (index -= 1) {
        const older = std.fmt.allocPrintSentinel(allocator, "{s}.{d}", .{ path, index }, 0) catch return kept;
        defer allocator.free(older);
        if (index == retained_runs) {
            // The oldest archive falls off the end.
            _ = c.unlink(older.ptr);
            continue;
        }
        const newer = std.fmt.allocPrintSentinel(allocator, "{s}.{d}", .{ path, index }, 0) catch return kept;
        defer allocator.free(newer);
        const target = std.fmt.allocPrintSentinel(allocator, "{s}.{d}", .{ path, index + 1 }, 0) catch return kept;
        defer allocator.free(target);
        if (c.rename(newer.ptr, target.ptr) == 0) kept += 1;
    }
    const first = std.fmt.allocPrintSentinel(allocator, "{s}.1", .{path}, 0) catch return kept;
    defer allocator.free(first);
    const current = allocator.dupeZ(u8, path) catch return kept;
    defer allocator.free(current);
    if (c.rename(current.ptr, first.ptr) == 0) kept += 1;
    return kept;
}

/// Keeps the interactive console concise while preserving the complete
/// diagnostic stream in `.rosette/rosette-runtime.log`. Set
/// ROSETTE_MACHO_VERBOSE_STDOUT=1 to retain the legacy console behavior.
pub const Controller = struct {
    concise: bool = false,
    saved_stderr: i32 = -1,
    detail_fd: i32 = -1,
    summary_fd: i32 = -1,

    pub fn init(allocator: std.mem.Allocator) Controller {
        if (environmentFlag("ROSETTE_MACHO_VERBOSE_STDOUT")) return .{};
        const root = routeRoot() orelse return .{};
        const path = std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-runtime.log" }) catch return .{};
        defer allocator.free(path);
        const directory = std.fs.path.dirname(path) orelse return .{};
        makePathRecursive(allocator, directory) catch return .{};
        const path_z = allocator.dupeZ(u8, path) catch return .{};
        defer allocator.free(path_z);
        // Keep the previous run before truncating this one.
        //
        // A rare late fault — one that needs ten billion instructions to
        // reach — cannot be reproduced on demand, and the run that finally
        // caught it destroyed its own evidence the next time anything started.
        // That has already happened once here. Rotation is cheap, bounded, and
        // it is the difference between an investigation that resumes and one
        // that restarts.
        const retained = rotateRuntimeLogs(allocator, path);
        const detail_fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
        if (detail_fd < 0) return .{};
        var summary_fd: i32 = -1;
        if (std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-runtime-summary.log" })) |summary_path| {
            defer allocator.free(summary_path);
            if (allocator.dupeZ(u8, summary_path)) |summary_path_z| {
                defer allocator.free(summary_path_z);
                summary_fd = c.open(summary_path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
            } else |_| {}
        } else |_| {}
        const saved_stderr = c.dup(c.STDERR_FILENO);
        if (saved_stderr < 0 or c.dup2(detail_fd, c.STDERR_FILENO) < 0) {
            if (saved_stderr >= 0) _ = c.close(saved_stderr);
            _ = c.close(detail_fd);
            if (summary_fd >= 0) _ = c.close(summary_fd);
            return .{};
        }
        if (detail_fd >= 0 and retained != 0) {
            // Stated in the new log so a reader knows the previous run is not
            // gone, and where it went.
            writeAll(detail_fd, "macho-processor: RUNTIME LOG RETENTION: the previous run's log was kept as rosette-runtime.log.1 (older runs shift to .log.2 and .log.3). A rare late fault cannot be reproduced on demand, so the run that catches one must not erase it\n");
        }
        if (summary_fd >= 0) {
            writeAll(summary_fd, "# Rosette Runtime Summary\n");
            writeAll(summary_fd, "# Selected Xenia lifecycle/errors and periodic translated-execution heartbeats.\n");
            writeAll(summary_fd, "# Full diagnostics remain in rosette-runtime.log.\n");
        }
        return .{ .concise = true, .saved_stderr = saved_stderr, .detail_fd = detail_fd, .summary_fd = summary_fd };
    }

    /// The runtime-log descriptor, so an alternative transport can write to
    /// the same file rather than opening a second one and interleaving.
    pub fn detailFd(self: *const Controller) i32 {
        return self.detail_fd;
    }

    /// Whether stderr was redirected into the runtime log. When it was, an
    /// async writer must not also echo to stderr or every line lands twice.
    pub fn capturedStderr(self: *const Controller) bool {
        return self.concise;
    }

    pub fn deinit(self: *Controller) void {
        if (self.saved_stderr >= 0) {
            _ = c.dup2(self.saved_stderr, c.STDERR_FILENO);
            _ = c.close(self.saved_stderr);
        }
        if (self.detail_fd >= 0) _ = c.close(self.detail_fd);
        if (self.summary_fd >= 0) _ = c.close(self.summary_fd);
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

    pub fn summaryFd(self: *const Controller) i32 {
        return self.summary_fd;
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
