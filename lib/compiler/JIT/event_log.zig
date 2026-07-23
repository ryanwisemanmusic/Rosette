const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const Kind = enum {
    function_compiled,
    function_executed,
    function_elided,
    code_cache_allocated,
    code_cache_freed,
    thunk_generated,
    guest_to_host_trampoline,
    host_to_guest_call,
    monitor_snapshot,
    module_loaded,
    jit_log_opened,
    process_exit,
};

pub const Event = struct {
    kind: Kind,
    step: u64 = 0,
    guest_addr: u32 = 0,
    host_addr: u64 = 0,
    size: u64 = 0,
    elapsed_ns: u64 = 0,
    call_count: u64 = 0,
    total_functions: u32 = 0,
    unique_ordinals: u32 = 0,
    code_cache_bytes: u64 = 0,
    module_index: u32 = 0,
    thread_id: u64 = 0,
    exit_code: i32 = 0,
    reason: []const u8 = "",
};

pub const Logger = struct {
    fd: i32 = -1,
    sequence: u64 = 0,

    pub fn open(self: *Logger, allocator: std.mem.Allocator) void {
        if (environmentPath("ROSETTE_JIT_LOG")) |override_path| {
            if (override_path.len == 0 or std.ascii.eqlIgnoreCase(override_path, "off")) return;
            self.openPath(allocator, override_path);
            return;
        }

        const root = routeRoot() orelse return;
        const path = std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-jit.log" }) catch return;
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
        self.emit(.{ .kind = .jit_log_opened, .reason = "jit_log_opened" });
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
        var line_buffer: [2048]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buffer,
            "seq={d} event={s} guest=0x{x} host=0x{x} size={d} elapsed_ns={d} calls={d} total_fn={d} unique_ordinals={d} cc_bytes={d} module={d} thread=0x{x} step={d} exit_code={d} reason={s}\n",
            .{
                self.sequence,
                @tagName(event.kind),
                event.guest_addr,
                event.host_addr,
                event.size,
                event.elapsed_ns,
                event.call_count,
                event.total_functions,
                event.unique_ordinals,
                event.code_cache_bytes,
                event.module_index,
                event.thread_id,
                event.step,
                event.exit_code,
                safe_reason,
            },
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

test "jit event reasons are single-line tokens" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("function_0x8200_compiled", sanitizeReason(&buffer, "function 0x8200 compiled"));
}

test "jit event log writes structured records" {
    const path = "/tmp/rosette-jit-event-log-test.log";
    const path_z = try std.testing.allocator.dupeZ(u8, path);
    defer std.testing.allocator.free(path_z);
    _ = c.unlink(path_z.ptr);
    defer _ = c.unlink(path_z.ptr);

    var logger = Logger{};
    logger.openPath(std.testing.allocator, path);
    try std.testing.expect(logger.fd >= 0);
    logger.emit(.{
        .kind = .function_compiled,
        .guest_addr = 0x82000000,
        .host_addr = 0x10000,
        .size = 4096,
        .elapsed_ns = 1_000_000,
        .reason = "xboxkrnl.exe:_RtlTimeToTimeFields",
    });
    logger.emit(.{
        .kind = .code_cache_allocated,
        .host_addr = 0x10000,
        .size = 65536,
        .reason = "xenia code cache grow",
    });
    logger.close();

    const fd = c.open(path_z.ptr, c.O_RDONLY | c.O_CLOEXEC);
    try std.testing.expect(fd >= 0);
    defer _ = c.close(fd);
    var contents: [4096]u8 = undefined;
    const count = c.read(fd, &contents, contents.len);
    try std.testing.expect(count > 0);
    const text = contents[0..@intCast(count)];
    try std.testing.expect(std.mem.indexOf(u8, text, "event=function_compiled") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "guest=0x82000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "event=code_cache_allocated") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "reason=jit_log_opened") != null);
}
