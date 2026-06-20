const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("errno.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/wait.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

pub const SignalPolicy = enum {
    child_only,
    process_group,
};

pub const RunOptions = struct {
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
    label: []const u8 = "rosette-child",
    timeout_ms: ?u64 = null,
    kill_grace_ms: u64 = 750,
    isolate_process_group: bool = true,
    signal_policy: SignalPolicy = .process_group,
    stdin: std.process.SpawnOptions.StdIo = .inherit,
    stdout: std.process.SpawnOptions.StdIo = .inherit,
    stderr: std.process.SpawnOptions.StdIo = .inherit,
};

pub const RunStatus = union(enum) {
    exited: u8,
    signal: u8,
    stopped: u8,
    unknown: u32,
    timed_out: TimeoutReport,

    pub fn exitCode(self: RunStatus) u8 {
        return switch (self) {
            .exited => |code| code,
            .signal => |sig| 128 + sig,
            .stopped => 128,
            .unknown => 1,
            .timed_out => 124,
        };
    }
};

pub const TimeoutReport = struct {
    pid: i32,
    signaled_group: bool,
    survived: bool,
};

pub fn run(io: std.Io, options: RunOptions) !RunStatus {
    if (options.argv.len == 0) return error.EmptyArgv;

    var spawn_options = std.process.SpawnOptions{
        .argv = options.argv,
        .stdin = options.stdin,
        .stdout = options.stdout,
        .stderr = options.stderr,
        .pgid = if (options.isolate_process_group) 0 else null,
    };
    if (options.cwd) |cwd| spawn_options.cwd = .{ .path = cwd };

    var child = std.process.spawn(io, spawn_options) catch |err| {
        std.debug.print("rosette-process-guard: failed to spawn {s}: {s}\n", .{ options.argv[0], @errorName(err) });
        return err;
    };

    const pid = child.id orelse return error.MissingChildPid;
    traceLaunch(options, pid);

    if (options.timeout_ms) |timeout_ms| {
        const status = try waitWithTimeout(&child, pid, timeout_ms, options.kill_grace_ms, options.signal_policy);
        traceExit(options, pid, status);
        return status;
    }

    const term = child.wait(io) catch |err| {
        std.debug.print("rosette-process-guard: failed waiting for {s}: {s}\n", .{ options.argv[0], @errorName(err) });
        return err;
    };
    const status = fromChildTerm(term);
    traceExit(options, pid, status);
    return status;
}

pub fn runExitCode(io: std.Io, options: RunOptions) !u8 {
    const status = try run(io, options);
    return status.exitCode();
}

pub fn timeoutFromEnv(default_timeout_ms: ?u64) ?u64 {
    const raw = getenvSlice("ROSETTE_PROCESS_TIMEOUT_MS") orelse return default_timeout_ms;
    if (raw.len == 0 or std.mem.eql(u8, raw, "0") or std.ascii.eqlIgnoreCase(raw, "off")) return null;
    return std.fmt.parseUnsigned(u64, raw, 10) catch default_timeout_ms;
}

pub fn tracePathFromEnv(allocator: std.mem.Allocator) ?[]const u8 {
    if (getenvSlice("ROSETTE_PROCESS_GUARD_TRACE")) |path| {
        if (path.len != 0 and !std.ascii.eqlIgnoreCase(path, "off")) {
            return allocator.dupe(u8, path) catch null;
        }
    }

    if (routeRoot(allocator)) |root| {
        return std.fs.path.join(allocator, &.{ root, ".rosette", "process-guard.log" }) catch null;
    }

    const home = getenvSlice("HOME") orelse return null;
    return std.fs.path.join(allocator, &.{ home, ".rosette", "process-guard.log" }) catch null;
}

fn quarantinePathFromEnv(allocator: std.mem.Allocator) ?[]const u8 {
    if (getenvSlice("ROSETTE_PROCESS_QUARANTINE")) |path| {
        if (path.len != 0 and !std.ascii.eqlIgnoreCase(path, "off")) {
            return allocator.dupe(u8, path) catch null;
        }
    }

    if (routeRoot(allocator)) |root| {
        return std.fs.path.join(allocator, &.{ root, ".rosette", "process-quarantine.log" }) catch null;
    }

    const home = getenvSlice("HOME") orelse return null;
    return std.fs.path.join(allocator, &.{ home, ".rosette", "process-quarantine.log" }) catch null;
}

fn routeRoot(allocator: std.mem.Allocator) ?[]const u8 {
    const env_names = [_][*:0]const u8{
        "ROSETTE_TRACE_ROOT",
        "ROSETTE_ROUTE_ROOT",
        "ROSETTE_CALLER_CWD",
        "PWD",
    };
    for (env_names) |name| {
        if (getenvSlice(name)) |value| {
            if (value.len != 0) return allocator.dupe(u8, value) catch null;
        }
    }
    return null;
}

fn getenvSlice(name: [*:0]const u8) ?[]const u8 {
    const value = c.getenv(name) orelse return null;
    return std.mem.span(value);
}

fn waitWithTimeout(
    child: *std.process.Child,
    pid: i32,
    timeout_ms: u64,
    kill_grace_ms: u64,
    signal_policy: SignalPolicy,
) !RunStatus {
    var elapsed_ms: u64 = 0;
    const poll_ms: u64 = 50;
    while (elapsed_ms <= timeout_ms) : (elapsed_ms += poll_ms) {
        if (try pollChild(child, pid)) |status| return status;
        sleepMs(poll_ms);
    }

    signalChild(pid, signal_policy, c.SIGTERM);
    var grace_elapsed: u64 = 0;
    while (grace_elapsed <= kill_grace_ms) : (grace_elapsed += poll_ms) {
        if (try pollChild(child, pid) != null) {
            return .{ .timed_out = .{
                .pid = pid,
                .signaled_group = signal_policy == .process_group,
                .survived = false,
            } };
        }
        sleepMs(poll_ms);
    }

    signalChild(pid, signal_policy, c.SIGKILL);
    sleepMs(100);

    const survived = childStillAlive(pid);
    if (!survived) {
        _ = try pollChild(child, pid);
    } else {
        signalChild(pid, signal_policy, c.SIGSTOP);
        quarantineSurvivor(pid, signal_policy);
    }
    child.id = null;
    return .{ .timed_out = .{
        .pid = pid,
        .signaled_group = signal_policy == .process_group,
        .survived = survived,
    } };
}

fn pollChild(child: *std.process.Child, pid: i32) !?RunStatus {
    if (comptime builtin.target.os.tag == .windows) {
        return null;
    }

    var raw_status: c_int = 0;
    while (true) {
        const rc = c.waitpid(pid, &raw_status, c.WNOHANG);
        if (rc == 0) return null;
        if (rc == pid) {
            child.id = null;
            return decodeWaitStatus(raw_status);
        }
        if (rc < 0 and std.c._errno().* == c.EINTR) continue;
        if (rc < 0 and std.c._errno().* == c.ECHILD) {
            child.id = null;
            return .{ .unknown = 0 };
        }
        return error.WaitPidFailed;
    }
}

fn decodeWaitStatus(raw_status: c_int) RunStatus {
    const status: u32 = @bitCast(raw_status);
    if ((status & 0x7f) == 0) return .{ .exited = @intCast((status >> 8) & 0xff) };
    if ((status & 0xff) == 0x7f) return .{ .stopped = @intCast((status >> 8) & 0xff) };
    const sig: u8 = @intCast(status & 0x7f);
    if (sig != 0) return .{ .signal = sig };
    return .{ .unknown = status };
}

fn fromChildTerm(term: std.process.Child.Term) RunStatus {
    return switch (term) {
        .exited => |code| .{ .exited = code },
        .signal => |sig| .{ .signal = @intCast(@intFromEnum(sig)) },
        .stopped => |sig| .{ .stopped = @intCast(@intFromEnum(sig)) },
        .unknown => |value| .{ .unknown = value },
    };
}

fn signalChild(pid: i32, signal_policy: SignalPolicy, sig: c_int) void {
    const target = switch (signal_policy) {
        .child_only => pid,
        .process_group => -pid,
    };
    _ = c.kill(target, sig);
}

fn childStillAlive(pid: i32) bool {
    if (pid <= 0) return false;
    if (c.kill(pid, 0) == 0) return true;
    return std.c._errno().* != c.ESRCH;
}

fn quarantineSurvivor(pid: i32, signal_policy: SignalPolicy) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const path = quarantinePathFromEnv(allocator) orelse return;
    if (std.fs.path.dirname(path)) |parent| makePathRecursive(allocator, parent) catch {};

    const path_z = allocator.dupeZ(u8, path) catch return;
    const fp = c.fopen(path_z.ptr, "a");
    if (fp == null) return;
    defer _ = c.fclose(fp);

    const policy = switch (signal_policy) {
        .child_only => "child_only",
        .process_group => "process_group",
    };
    var buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &buf,
        "{d}\tpid={d}\tstatus=timed_out_survived\taction=sigstop\tpolicy={s}\n",
        .{ @as(i64, @intCast(c.time(null))), pid, policy },
    ) catch return;
    _ = c.fwrite(line.ptr, 1, line.len, fp);
}

fn sleepMs(ms: u64) void {
    if (ms == 0) return;
    const capped = @min(ms, 60_000);
    _ = c.usleep(@intCast(capped * 1000));
}

fn traceLaunch(options: RunOptions, pid: i32) void {
    traceLine(options, pid, "launch", null);
}

fn traceExit(options: RunOptions, pid: i32, status: RunStatus) void {
    traceLine(options, pid, "exit", status);
}

fn traceLine(options: RunOptions, pid: i32, event: []const u8, status: ?RunStatus) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const path = tracePathFromEnv(allocator) orelse return;
    if (std.fs.path.dirname(path)) |parent| makePathRecursive(allocator, parent) catch {};

    const path_z = allocator.dupeZ(u8, path) catch return;
    const fp = c.fopen(path_z.ptr, "a");
    if (fp == null) return;
    defer _ = c.fclose(fp);

    const first_arg = if (options.argv.len > 0) options.argv[0] else "";
    const status_text = if (status) |value| statusName(value) else "pending";
    var buf: [1024]u8 = undefined;
    const line = std.fmt.bufPrint(
        &buf,
        "{d}\t{s}\tpid={d}\tlabel={s}\tstatus={s}\targv0={s}\n",
        .{ @as(i64, @intCast(c.time(null))), event, pid, options.label, status_text, first_arg },
    ) catch return;
    _ = c.fwrite(line.ptr, 1, line.len, fp);
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

fn statusName(status: RunStatus) []const u8 {
    return switch (status) {
        .exited => "exited",
        .signal => "signal",
        .stopped => "stopped",
        .unknown => "unknown",
        .timed_out => |report| if (report.survived) "timed_out_survived" else "timed_out_killed",
    };
}

test "wait status decodes exit codes" {
    const status: c_int = 7 << 8;
    try std.testing.expectEqual(@as(u8, 7), decodeWaitStatus(status).exited);
}

test "run status maps timeout to shell timeout code" {
    const status = RunStatus{ .timed_out = .{ .pid = 10, .signaled_group = true, .survived = false } };
    try std.testing.expectEqual(@as(u8, 124), status.exitCode());
}
