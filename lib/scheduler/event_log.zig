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

/// Batch size for the event sink. One `write(2)` per event is what this
/// replaces: a real run emits ~1.5 million scheduler events, and at ~165 bytes
/// each that is 1.5 million syscalls and a quarter of a gigabyte pushed through
/// them synchronously, on the scheduler's own thread, while the guest waits.
/// Every other log this runtime keeps totals under a megabyte, so this one sink
/// was three hundred times the I/O of all the others combined.
///
/// 16 KB brings that to roughly one syscall per hundred events — a hundredfold
/// reduction — without changing a byte of what is recorded. Deliberately not
/// larger: the logger is a by-value field of the process state, so its size is
/// paid on every construction of that struct, and the syscall count is already
/// negligible at this capacity. Going to 64 KB would turn 15,000 syscalls into
/// 3,800, which buys nothing against the 1.5 million this replaces.
pub const buffer_capacity: usize = 16 * 1024;

/// Whether an event is rare enough, and structural enough, to be worth a syscall
/// of its own. Buffering trades crash-time visibility for throughput, and the
/// events worth protecting from that trade are the ones that describe the shape
/// of the run rather than its steady state: if the process dies, thread
/// lifecycle and quiescence are what has to have survived.
///
/// These are a rounding error by volume — a few hundred against a million and a
/// half — so flushing on each costs nothing measurable.
fn flushesImmediately(kind: Kind) bool {
    return switch (kind) {
        .thread_created,
        .thread_terminated,
        .deadlock,
        .quiescence_recovery,
        .runnable_count,
        .condvar_broadcast,
        => true,
        else => false,
    };
}

/// Allocation-free, best-effort scheduler event sink. Scheduler diagnostics
/// must never affect guest scheduling, so open and write failures disable the
/// sink instead of becoming runtime failures.
pub const Logger = struct {
    fd: i32 = -1,
    sequence: u64 = 0,
    buffer: [buffer_capacity]u8 = undefined,
    pending: usize = 0,

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
        self.flush();
        if (self.fd >= 0) _ = c.close(self.fd);
        self.fd = -1;
    }

    /// Push whatever is buffered. Safe to call at any time, including when the
    /// sink is disabled or empty.
    pub fn flush(self: *Logger) void {
        if (self.fd < 0 or self.pending == 0) return;
        writeAll(self.fd, self.buffer[0..self.pending]);
        self.pending = 0;
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

        // A line longer than the whole buffer cannot be batched, and silently
        // dropping it would lose an event rather than only its timeliness.
        if (line.len > self.buffer.len) {
            self.flush();
            writeAll(self.fd, line);
            return;
        }
        if (self.pending + line.len > self.buffer.len) self.flush();
        @memcpy(self.buffer[self.pending..][0..line.len], line);
        self.pending += line.len;

        if (flushesImmediately(event.kind)) self.flush();
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

const test_dir = "/private/tmp/claude-501/rosette-sched-log-test";

fn testLogPath(name: []const u8, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "{s}/{s}", .{ test_dir, name }) catch unreachable;
}

// Read back through the same C API the sink writes with, rather than std.fs:
// the module is already committed to it, and the test should observe the file
// the way anything else on the system would.
fn readTestLog(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = c.open(path_z.ptr, c.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return error.OpenFailed;
    defer _ = c.close(fd);

    var contents: std.ArrayList(u8) = .empty;
    errdefer contents.deinit(allocator);
    var chunk: [8192]u8 = undefined;
    while (true) {
        const count = c.read(fd, &chunk, chunk.len);
        if (count < 0) return error.ReadFailed;
        if (count == 0) break;
        try contents.appendSlice(allocator, chunk[0..@intCast(count)]);
    }
    return contents.toOwnedSlice(allocator);
}

test "buffered events reach the file once flushed" {
    var path_buffer: [256]u8 = undefined;
    const file_path = testLogPath("flush.log", &path_buffer);

    var logger = Logger{};
    logger.openPath(std.testing.allocator, file_path);
    try std.testing.expect(logger.fd >= 0);
    defer logger.close();

    // A steady-state event is batched rather than written straight through.
    logger.emit(.{ .kind = .context_switch, .reason = "batched" });
    try std.testing.expect(logger.pending > 0);

    // A structural event takes the buffer with it, so a crash after this point
    // still shows everything up to and including it.
    logger.emit(.{ .kind = .thread_created, .reason = "structural" });
    try std.testing.expectEqual(@as(usize, 0), logger.pending);

    const contents = try readTestLog(std.testing.allocator, file_path);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "reason=batched") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "reason=structural") != null);
}

// Buffering must never cost an event, only its timeliness. Wrapping the buffer
// thousands of times has to leave exactly the same record behind.
test "a full buffer flushes rather than dropping events" {
    var path_buffer: [256]u8 = undefined;
    const file_path = testLogPath("churn.log", &path_buffer);

    var logger = Logger{};
    logger.openPath(std.testing.allocator, file_path);
    try std.testing.expect(logger.fd >= 0);

    var index: usize = 0;
    while (index < 4000) : (index += 1) {
        logger.emit(.{ .kind = .thread_blocked, .step = index, .reason = "churn" });
    }
    logger.close();

    const contents = try readTestLog(std.testing.allocator, file_path);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqual(@as(usize, 4000), std.mem.count(u8, contents, "reason=churn"));
    // Sequence numbers stay dense: the open marker plus all 4000 events.
    try std.testing.expect(std.mem.indexOf(u8, contents, "seq=4001 ") != null);
}
