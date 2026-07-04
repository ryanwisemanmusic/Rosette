const std = @import("std");
const traps = @import("abort_trap_taxonomy");

extern "C" fn rosette_debug_enabled() c_int;
extern "C" fn rosette_debug_log_path() [*:0]const u8;
extern "C" fn rosette_runtime_abi_fail_fast_enabled() c_int;
extern "c" fn fflush(stream: ?*std.c.FILE) c_int;
extern "c" fn abort() noreturn;

pub const max_log_path = 4096;

var retain_count: usize = 0;
var initialized = false;
var log_file: ?*std.c.FILE = null;
var violation_count: usize = 0;
var validation_count: usize = 0;

fn pathZToSlice(path_z: [*:0]const u8) []const u8 {
    return std.mem.span(path_z);
}

fn buildRuntimeLogPath(buf: *[max_log_path]u8) [:0]const u8 {
    const base = pathZToSlice(rosette_debug_log_path());
    if (base.len == 0) {
        const written = std.fmt.bufPrintZ(buf, "rosette-runtime-abi.log", .{}) catch unreachable;
        return written;
    }
    if (std.mem.endsWith(u8, base, ".log")) {
        const stem = base[0 .. base.len - 4];
        const written = std.fmt.bufPrintZ(buf, "{s}.runtime-abi.log", .{stem}) catch unreachable;
        return written;
    }
    const written = std.fmt.bufPrintZ(buf, "{s}.runtime-abi.log", .{base}) catch unreachable;
    return written;
}

pub fn isEnabled() bool {
    return rosette_debug_enabled() != 0;
}

pub fn acquire() void {
    retain_count += 1;
    if (initialized) return;
    initialized = true;

    var path_buf: [max_log_path]u8 = undefined;
    const log_path = buildRuntimeLogPath(&path_buf);
    log_file = std.c.fopen(log_path.ptr, "w");
    writeLine("# Rosette runtime ABI handshake log\n", .{});
    writeLine("# debug_enabled={d}\n", .{rosette_debug_enabled()});
}

pub fn release() void {
    if (retain_count == 0) return;
    retain_count -= 1;
    if (retain_count != 0) return;
    if (!initialized) return;
    writeLine("# validations={d} violations={d}\n", .{ validation_count, violation_count });
    if (log_file) |file| _ = std.c.fclose(file);
    log_file = null;
    initialized = false;
    violation_count = 0;
    validation_count = 0;
}

pub fn noteValidation() void {
    validation_count += 1;
}

pub fn violationCount() usize {
    return violation_count;
}

pub fn validationCount() usize {
    return validation_count;
}

pub fn writeLine(comptime fmt: []const u8, args: anytype) void {
    if (log_file == null) return;
    var line_buf: [2048]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, fmt, args) catch return;
    if (log_file) |file| {
        _ = std.c.fwrite(line.ptr, 1, line.len, file);
        _ = fflush(file);
    }
}

pub fn violation(comptime domain: []const u8, comptime check: []const u8, comptime fmt: []const u8, args: anytype) void {
    violation_count += 1;
    writeLine("[runtime-abi][{s}][{s}] " ++ fmt ++ "\n", .{ domain, check } ++ args);
    if (rosette_runtime_abi_fail_fast_enabled() != 0) {
        writeLine("[runtime-abi][{s}][{s}] fail-fast abort\n", .{ domain, check });
        abort();
    }
}

pub fn trapViolation(kind: traps.AbortTrap, comptime domain: []const u8, comptime check: []const u8, comptime fmt: []const u8, args: anytype) void {
    violation_count += 1;
    writeLine(
        "[abort-trap][{s}] domain={s} check={s} description=\"{s}\" " ++ fmt ++ "\n",
        .{ @tagName(kind), domain, check, traps.description(kind) } ++ args,
    );
    writeLine("[runtime-abi][{s}][{s}] " ++ fmt ++ "\n", .{ domain, check } ++ args);
    if (rosette_runtime_abi_fail_fast_enabled() != 0) {
        writeLine("[abort-trap][{s}] fail-fast abort\n", .{@tagName(kind)});
        abort();
    }
}
