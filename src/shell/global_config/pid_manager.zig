const std = @import("std");

const c = @cImport({
    @cInclude("errno.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/sysctl.h");
    @cInclude("unistd.h");
});

/// Process tracking entry
const ProcessEntry = struct {
    pid: i32,
    spawn_time: i64,
    label: []const u8,
    command: []const u8,
};

/// Global process tracker
var tracked_processes: std.ArrayList(ProcessEntry) = undefined;
var tracker_initialized = false;
var tracker_mutex = std.Thread.Mutex{};

/// Initialize the process tracker
fn initTracker(allocator: std.mem.Allocator) !void {
    if (!tracker_initialized) {
        tracker_mutex.lock();
        defer tracker_mutex.unlock();

        if (!tracker_initialized) {
            tracked_processes = std.ArrayList(ProcessEntry).init(allocator);
            tracker_initialized = true;
        }
    }
}

/// Track a spawned process
pub fn trackProcess(allocator: std.mem.Allocator, pid: i32, label: []const u8, command: []const u8) !void {
    try initTracker(allocator);

    tracker_mutex.lock();
    defer tracker_mutex.unlock();

    const entry = ProcessEntry{
        .pid = pid,
        .spawn_time = std.time.timestamp(),
        .label = try allocator.dupe(u8, label),
        .command = try allocator.dupe(u8, command),
    };

    try tracked_processes.append(allocator, entry);
    std.debug.print("[PID] Tracked process: pid={d} label='{s}' command='{s}'\n", .{ pid, label, command });
}

/// Remove a process from tracking
pub fn untrackProcess(allocator: std.mem.Allocator, pid: i32) void {
    if (!tracker_initialized) return;

    tracker_mutex.lock();
    defer tracker_mutex.unlock();

    for (tracked_processes.items, 0..) |entry, i| {
        if (entry.pid == pid) {
            allocator.free(entry.label);
            allocator.free(entry.command);
            _ = tracked_processes.orderedRemove(i);
            std.debug.print("[PID] Untracked process: pid={d}\n", .{pid});
            return;
        }
    }
}

/// Check if a process is still running
pub fn isProcessRunning(pid: i32) bool {
    if (pid <= 0) return false;
    if (c.kill(pid, 0) == 0) return true;
    return std.c._errno().* != c.ESRCH;
}

/// Get process command line for a PID (macOS specific)
pub fn getProcessCommand(allocator: std.mem.Allocator, pid: i32) ![]const u8 {
    var mib: [3]c_int = undefined;
    mib[0] = c.CTL_KERN;
    mib[1] = c.KERN_PROCARGS2;
    mib[2] = pid;

    var size: usize = 0;
    if (c.sysctl(&mib, 3, null, &size, null, 0) != 0) {
        return error.SysctlFailed;
    }

    var buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    if (c.sysctl(&mib, 3, buffer.ptr, &size, null, 0) != 0) {
        return error.SysctlFailed;
    }

    // The buffer starts with argc (int)
    const argc_ptr = @as(*align(1) c_int, @ptrCast(buffer.ptr));
    const argc = argc_ptr.*;

    // Skip argc and the NUL after it
    var offset: usize = @sizeOf(c_int) + 1;

    // The first string is the executable path
    if (offset >= buffer.len) return error.InvalidBuffer;

    var start = offset;
    while (offset < buffer.len and buffer[offset] != 0) : (offset += 1) {}

    if (start >= offset) return error.InvalidBuffer;

    return allocator.dupe(u8, buffer[start..offset]);
}

/// Force kill a process with escalating signals
pub fn forceKillProcess(pid: i32, label: []const u8) bool {
    if (pid <= 0) return false;

    std.debug.print("[PID] Attempting to kill process: pid={d} label='{s}'\n", .{ pid, label });

    // Try SIGTERM first
    if (c.kill(pid, c.SIGTERM) == 0) {
        std.time.sleep(100 * std.time.ns_per_ms); // 100ms grace period

        if (!isProcessRunning(pid)) {
            std.debug.print("[PID] Process terminated with SIGTERM: pid={d}\n", .{pid});
            return true;
        }
    }

    // Try SIGKILL
    if (c.kill(pid, c.SIGKILL) == 0) {
        std.time.sleep(50 * std.time.ns_per_ms); // 50ms to verify

        if (!isProcessRunning(pid)) {
            std.debug.print("[PID] Process terminated with SIGKILL: pid={d}\n", .{pid});
            return true;
        }
    }

    std.debug.print("[PID] Failed to kill process: pid={d} (may require manual intervention)\n", .{pid});
    return false;
}

/// Kill all tracked processes
pub fn killAllTrackedProcesses(allocator: std.mem.Allocator) void {
    if (!tracker_initialized) return;

    tracker_mutex.lock();
    defer tracker_mutex.unlock();

    std.debug.print("[PID] Killing all tracked processes (count={d})\n", .{tracked_processes.items.len});

    var i: usize = 0;
    while (i < tracked_processes.items.len) {
        const entry = tracked_processes.items[i];
        _ = forceKillProcess(entry.pid, entry.label);
        allocator.free(entry.label);
        allocator.free(entry.command);
        i += 1;
    }

    tracked_processes.clearRetainingCapacity();
}

/// Kill processes matching a pattern
pub fn killProcessesMatchingPattern(allocator: std.mem.Allocator, pattern: []const u8) !void {
    std.debug.print("[PID] Killing processes matching pattern: '{s}'\n", .{pattern});

    var pids = try findProcessesMatchingPattern(allocator, pattern);
    defer allocator.free(pids);

    for (pids) |pid| {
        var command_buf: [512]u8 = undefined;
        const command = getProcessCommand(allocator, pid) catch "unknown";
        defer allocator.free(command);

        _ = forceKillProcess(pid, command);
    }
}

/// Find all PIDs matching a command pattern
pub fn findProcessesMatchingPattern(allocator: std.mem.Allocator, pattern: []const u8) ![]i32 {
    var pids = std.ArrayList(i32).init(allocator);
    errdefer pids.deinit();

    var mib: [4]c_int = undefined;
    mib[0] = c.CTL_KERN;
    mib[1] = c.KERN_PROC;
    mib[2] = c.KERN_PROC_ALL;
    mib[3] = 0;

    var size: usize = 0;
    if (c.sysctl(&mib, 4, null, &size, null, 0) != 0) {
        return error.SysctlFailed;
    }

    const expected_size = size;
    const buffer = try allocator.alloc(u8, size);
    defer allocator.free(buffer);

    if (c.sysctl(&mib, 4, buffer.ptr, &size, null, 0) != 0) {
        return error.SysctlFailed;
    }

    if (size != expected_size) {
        return error.SizeMismatch;
    }

    const proc_count = size / @sizeOf(c.kinfo_proc);
    const procs = @as([*]c.kinfo_proc, @ptrCast(buffer.ptr));

    for (0..proc_count) |i| {
        const proc = &procs[i];
        const pid = proc.kp_proc.p_pid;

        if (pid <= 1) continue; // Skip init and kernel processes

        var command_buf: [512]u8 = undefined;
        std.mem.copyForwards(u8, &command_buf, &proc.kp_proc.p_comm);
        const command_len = std.mem.indexOfScalar(u8, &command_buf, 0) orelse command_buf.len;
        const command = command_buf[0..command_len];

        if (std.mem.indexOf(u8, command, pattern) != null) {
            try pids.append(allocator, @as(i32, @intCast(pid)));
            std.debug.print("[PID] Found matching process: pid={d} command='{s}'\n", .{ pid, command });
        }
    }

    return pids.toOwnedSlice();
}

/// Kill all Rosette helper processes as a pre-flight check
pub fn killRosetteHelpers(allocator: std.mem.Allocator) !void {
    std.debug.print("[PID] Running pre-flight cleanup of Rosette helper processes\n", .{});

    const patterns = [_][]const u8{
        "rosette-shell",
        "rosette-router",
        "elf_processor",
        "macho_processor",
        "rosette-arch",
        "rosette-compiler-sanitize",
        "rosette-clean-state",
    };

    for (patterns) |pattern| {
        killProcessesMatchingPattern(allocator, pattern) catch |err| {
            std.debug.print("[PID] Warning: failed to kill processes matching '{s}': {s}\n", .{ pattern, @errorName(err) });
        };
    }

    // Also kill any tracked processes
    killAllTrackedProcesses(allocator);

    std.debug.print("[PID] Pre-flight cleanup complete\n", .{});
}

/// Print status of all tracked processes
pub fn printTrackedProcessStatus() void {
    if (!tracker_initialized) {
        std.debug.print("[PID] No processes tracked\n", .{});
        return;
    }

    tracker_mutex.lock();
    defer tracker_mutex.unlock();

    std.debug.print("[PID] Tracked processes (count={d}):\n", .{tracked_processes.items.len});

    for (tracked_processes.items) |entry| {
        const running = isProcessRunning(entry.pid);
        std.debug.print("  pid={d} label='{s}' command='{s}' running={}\n", .{ entry.pid, entry.label, entry.command, running });
    }
}

/// Clean up the tracker (call at program exit)
pub fn deinitTracker(allocator: std.mem.Allocator) void {
    if (!tracker_initialized) return;

    tracker_mutex.lock();
    defer tracker_mutex.unlock();

    for (tracked_processes.items) |entry| {
        allocator.free(entry.label);
        allocator.free(entry.command);
    }

    tracked_processes.deinit();
    tracker_initialized = false;
}
