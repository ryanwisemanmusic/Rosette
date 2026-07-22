const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const Kind = enum {
    thread_created,
    thread_blocked,
    thread_resumed,
    thread_terminated,
    quantum_expired,
    context_switch,
    condvar_signal,
    condvar_broadcast,
    wait_timeout,
    timer_due,
    deadlock,
    quiescence_recovery,
    runnable_count,
};

pub const Event = struct {
    kind: Kind,
    step: u64 = 0,
    thread: u64 = 0,
    peer: u64 = 0,
    object: u64 = 0,
    generation: u64 = 0,
    deadline_ns: u64 = 0,
    runnable: u64 = 0,
    blocked: u64 = 0,
    reason: []const u8 = "",
};

/// Allocation-free, best-effort scheduler event sink. Scheduler diagnostics
/// must never affect guest scheduling, so open and write failures disable the
/// sink instead of becoming runtime failures.
pub const Logger = struct {
    fd: i32 = -1,
    sequence: u64 = 0,

    pub fn open(self: *Logger, allocator: std.mem.Allocator) void {
        if (environmentPath("ROSETTE_SCHEDULER_LOG")) |override_path| {
            if (override_path.len == 0 or std.ascii.eqlIgnoreCase(override_path, "off")) return;
            self.openPath(allocator, override_path);
            return;
        }

        const root = routeRoot() orelse return;
        const path = std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-scheduler.log" }) catch return;
        defer allocator.free(path);
        self.openPath(allocator, path);
    }

    pub fn openPath(self: *Logger, allocator: std.mem.Allocator, path: []const u8) void {
        const directory = std.fs.path.dirname(path) orelse return;
        makePathRecursive(allocator, directory) catch return;
        const path_z = allocator.dupeZ(u8, path) catch return;
        defer allocator.free(path_z);
        const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
        if (fd < 0) return;
        self.close();
        self.fd = fd;
        self.emit(.{ .kind = .runnable_count, .reason = "scheduler_log_opened" });
    }

    pub fn close(self: *Logger) void {
        if (self.fd >= 0) _ = c.close(self.fd);
        self.fd = -1;
    }

    pub fn emit(self: *Logger, event: Event) void {
        if (self.fd < 0) return;
        self.sequence +|= 1;
        var buffer: [1024]u8 = undefined;
        const safe_reason = sanitizeReason(&buffer, event.reason);
        var line_buffer: [1536]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buffer,
            "seq={d} step={d} event={s} thread=0x{x} peer=0x{x} object=0x{x} generation={d} deadline_ns={d} runnable={d} blocked={d} reason={s}\n",
            .{ self.sequence, event.step, @tagName(event.kind), event.thread, event.peer, event.object, event.generation, event.deadline_ns, event.runnable, event.blocked, safe_reason },
        ) catch return;
        writeAll(self.fd, line);
    }
};

fn sanitizeReason(buffer: []u8, reason: []const u8) []const u8 {
    const length = @min(buffer.len, reason.len);
    for (reason[0..length], 0..) |byte, index| {
        buffer[index] = switch (byte) {
            '\n', '\r', '\t', ' ' => '_',
            else => if (byte >= 0x20 and byte <= 0x7e) byte else '?',
        };
    }
    return buffer[0..length];
}

fn writeAll(fd: i32, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const result = c.write(fd, bytes.ptr + written, bytes.len - written);
        if (result <= 0) return;
        written += @intCast(result);
    }
}

fn routeRoot() ?[]const u8 {
    const names = [_][*:0]const u8{
        "ROSETTE_TRACE_ROOT",
        "ROSETTE_ROUTE_ROOT",
        "ROSETTE_CALLER_CWD",
        "PWD",
    };
    for (names) |name| {
        if (environmentPath(name)) |value| {
            if (value.len != 0) return value;
        }
    }
    return null;
}

fn environmentPath(name: [*:0]const u8) ?[]const u8 {
    const value = c.getenv(name) orelse return null;
    return std.mem.span(value);
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
        if (c.mkdir(path_z.ptr, 0o755) != 0 and c.access(path_z.ptr, c.F_OK) != 0) {
            return error.MakePathFailed;
        }
    }
}

test "scheduler event reasons are single-line tokens" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("pthread_cond_wait_now", sanitizeReason(&buffer, "pthread cond\twait\nnow"));
}

test "scheduler event log writes structured records" {
    const path = "/tmp/rosette-scheduler-event-log-test.log";
    const path_z = try std.testing.allocator.dupeZ(u8, path);
    defer std.testing.allocator.free(path_z);
    _ = c.unlink(path_z.ptr);
    defer _ = c.unlink(path_z.ptr);

    var logger = Logger{};
    logger.openPath(std.testing.allocator, path);
    try std.testing.expect(logger.fd >= 0);
    logger.emit(.{
        .kind = .context_switch,
        .step = 42,
        .thread = 0x100,
        .peer = 0x200,
        .reason = "quantum expired",
    });
    logger.close();

    const fd = c.open(path_z.ptr, c.O_RDONLY | c.O_CLOEXEC);
    try std.testing.expect(fd >= 0);
    defer _ = c.close(fd);
    var contents: [2048]u8 = undefined;
    const count = c.read(fd, &contents, contents.len);
    try std.testing.expect(count > 0);
    const text = contents[0..@intCast(count)];
    try std.testing.expect(std.mem.indexOf(u8, text, "event=context_switch") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "thread=0x100") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "reason=quantum_expired") != null);
}
