const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

/// The asynchronous diagnostic transport, installed by the process when
/// `ROSETTE_ASYNC_LOG=1` selects it.
///
/// Function pointers rather than a direct import: this file lives in a module
/// the diagnostics module depends on, so importing the ring here would be a
/// cycle. The indirection also keeps the default path exactly as it was — one
/// null test — for runs that do not opt in.
///
/// Why the transport exists: the synchronous path below puts two syscalls and
/// a process-wide stderr mutex on a translated guest thread for every line.
/// That cost lands hardest on whichever subsystem is doing the most work, which
/// during a graphics investigation is the subsystem under investigation — so
/// the observer becomes a participant in the scheduling it is trying to
/// measure, and a livelock or lost wakeup can be created, hidden or moved by
/// the logging alone.
pub const OfferFn = *const fn ([]const u8) bool;
pub const FlushFn = *const fn () void;
pub const ClassifyFn = *const fn ([]const u8) bool;

var async_offer: ?OfferFn = null;
var async_flush: ?FlushFn = null;
/// Returns true when a line must take the synchronous path regardless. A crash
/// diagnostic queued behind a writer thread that may never run again is a crash
/// diagnostic that does not exist.
var async_is_critical: ?ClassifyFn = null;

pub fn installAsyncTransport(offer: OfferFn, flush: FlushFn, is_critical: ClassifyFn) void {
    async_offer = offer;
    async_flush = flush;
    async_is_critical = is_critical;
}

pub fn clearAsyncTransport() void {
    if (async_flush) |flush| flush();
    async_offer = null;
    async_flush = null;
    async_is_critical = null;
}

pub fn asyncTransportInstalled() bool {
    return async_offer != null;
}

/// Write everything queued without stopping. Used before a report that must not
/// appear out of order with the lines it summarises, and from the crash path.
pub fn flushAsyncTransport() void {
    if (async_flush) |flush| flush();
}

/// True when the transport handled this line. The caller must return
/// immediately on true: falling through to the synchronous path would
/// reintroduce exactly the stall the ring exists to avoid, and would do it
/// precisely when the system is busiest.
fn asyncHandled(text: []const u8) bool {
    const offer = async_offer orelse return false;
    const critical = if (async_is_critical) |classify| classify(text) else false;
    if (critical) {
        // Order matters more than latency here: everything already queued must
        // reach the log before the fault that ends the run.
        if (async_flush) |flush| flush();
        return false;
    }
    // A dropped line is already counted by the ring, so a full ring costs a
    // counted gap rather than a pause.
    _ = offer(text);
    return true;
}

threadlocal var thread_macho_fd: i32 = -1;
threadlocal var thread_scheduler_fd: i32 = -1;
threadlocal var thread_primitive_fd: i32 = -1;
// Unlike the three historical thread-local streams, the readiness stream is
// intentionally process-wide. Compiler failures are often reported from a
// translated guest thread, and a thread-local descriptor would silently omit
// exactly the Xbyak line that explains why a generated function was abandoned.
var ready_compiler_fd: i32 = -1;

pub fn setThreadFds(macho: i32, scheduler: i32, primitive: i32) void {
    thread_macho_fd = macho;
    thread_scheduler_fd = scheduler;
    thread_primitive_fd = primitive;
}

pub fn resetThreadFds() void {
    thread_macho_fd = -1;
    thread_scheduler_fd = -1;
    thread_primitive_fd = -1;
    ready_compiler_fd = -1;
}

/// F15 (throughput audit): format into a thread-local stack buffer instead of
/// allocating.
///
/// `std.heap.page_allocator` on Darwin is `mmap`/`munmap`, so every diagnostic
/// line cost a syscall pair before it wrote anything. That is not a throughput
/// problem at the ~20K lines a normal run emits, but it is the reason this
/// function is expensive to *call*: its inlined expansion (allocPrint + Writer
/// + free) is what grew `readMemVal` to 16 KB and `run` to 99 KB, since a
/// thousand call sites each carried a copy. Making the body cheap and small is
/// what lets diagnostics live near the code they describe without the hot path
/// paying for them.
///
/// A line longer than the buffer is truncated with a marker rather than
/// dropped: losing the tail of a diagnostic is recoverable, losing the fact
/// that it fired is not.
// Formatting can happen concurrently on translated guest threads and host/UI
// callbacks. Keep each caller's scratch buffer private; otherwise one thread
// can overwrite the bytes another thread is about to enqueue or write, which
// turns an otherwise ordered diagnostic into a false cross-thread finding.
threadlocal var capture_buffer: [8192]u8 = undefined;

fn formatCapture(buffer: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buffer, fmt, args) catch blk: {
        const marker = " <truncated>\n";
        @memcpy(buffer[buffer.len - marker.len ..], marker);
        break :blk buffer;
    };
}

pub fn machoCapturePrint(comptime fmt: []const u8, args: anytype) void {
    const text = formatCapture(&capture_buffer, fmt, args);

    // Scheduler tables have their own complete log. Do not print them to
    // stderr because the route wrapper captures stderr in rosette-runtime.log.
    // Checked before the transport: these lines belong to a different stream,
    // and routing them through the shared ring would both reorder them against
    // that stream and let a scheduler dump evict the diagnostics the ring is
    // there to protect.
    if (isSchedulerTableLine(text)) {
        if (thread_scheduler_fd >= 0) {
            writeAll(thread_scheduler_fd, text);
            if (text.len == 0 or text[text.len - 1] != '\n')
                _ = c.write(thread_scheduler_fd, "\n", 1);
        }
        return;
    }

    if (asyncHandled(text)) return;

    // Always write to stderr first so diagnostics survive a crash
    std.debug.print("{s}", .{text});

    if (thread_macho_fd >= 0) {
        writeLineAtomic(thread_macho_fd, text);
    }
    if (ready_compiler_fd >= 0 and isReadyCompilerLine(text)) {
        writeLineAtomic(ready_compiler_fd, text);
    }
}

/// Write one diagnostic line as a single write syscall, adding the newline
/// the format may have omitted. The runtime log is shared with the guest log
/// mirror and with other threads' diagnostics, so a multi-part line would let
/// another writer's bytes land inside it; one write keeps lines atomic on a
/// regular file.
fn writeLineAtomic(fd: i32, text: []const u8) void {
    if (text.len == 0 or text[text.len - 1] == '\n') {
        writeAll(fd, text);
        return;
    }
    if (text.len + 1 <= 8192) {
        var buffer: [8192]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = '\n';
        writeAll(fd, buffer[0 .. text.len + 1]);
        return;
    }
    writeAll(fd, text);
    _ = c.write(fd, "\n", 1);
}

pub fn primitiveCapturePrint(comptime fmt: []const u8, args: anytype) void {
    const text = formatCapture(&capture_buffer, fmt, args);

    // Deliberately not routed through the async transport: this stream has its
    // own descriptor, and the ring drains to the runtime log. Queuing these
    // here would move them into the wrong file.

    // Always write to stderr first so diagnostics survive a crash
    std.debug.print("{s}", .{text});

    if (thread_primitive_fd >= 0) {
        writeLineAtomic(thread_primitive_fd, text);
    }
}

fn isSchedulerTableLine(text: []const u8) bool {
    return std.mem.startsWith(u8, text, "scheduler: THREAD TABLE") or
        std.mem.startsWith(u8, text, "scheduler: CTX") or
        std.mem.startsWith(u8, text, "scheduler: REG");
}

/// Keep a compact, high-signal companion log for the runtime readiness gate.
/// The full stream remains in rosette-runtime.log; this filter deliberately
/// includes both the gate's own records and the native/JIT diagnostics that
/// explain why a generated function was not usable.
fn isReadyCompilerLine(text: []const u8) bool {
    const markers = [_][]const u8{
        "READY COMPILER",
        "undefined label",
        "label is not found",
        "Xbyak",
        "function left undefined",
        "X64Emitter",
        "X64Assembler",
        "PPCTranslator",
        "PPCFrontend",
        "DEFERRED WORK PREDICTOR",
        "GUEST EXCEPTION PREDICTOR",
        "ResolveFunction",
        "codegen",
        "generated guest function",
        "NEAR NULL PREDICTOR",
    };
    for (markers) |marker| {
        if (std.mem.indexOf(u8, text, marker) != null) return true;
    }
    return false;
}

test "scheduler tables are routed away from the runtime console" {
    try std.testing.expect(isSchedulerTableLine(
        "scheduler: THREAD TABLE BEGIN reason=runnable rotation quantum\n",
    ));
    try std.testing.expect(isSchedulerTableLine(
        "scheduler: CTX  run  0xfffff90000000003\n",
    ));
    try std.testing.expect(isSchedulerTableLine(
        "scheduler: REG  00   0x000000007fff2000\n",
    ));
    try std.testing.expect(!isSchedulerTableLine(
        "scheduler: runnable context selected handle=0x7fff2090\n",
    ));
    try std.testing.expect(!isSchedulerTableLine(
        "[xenia] i> Module \\Device\\Cdrom0\\default.xex:\n",
    ));
}

test "ready compiler filter keeps code-generation evidence and drops ordinary lines" {
    try std.testing.expect(isReadyCompilerLine(
        "macho-processor: Xbyak exception detail: code=11 reason='label is not found'\n",
    ));
    try std.testing.expect(isReadyCompilerLine(
        "macho-processor: DEFERRED WORK PREDICTOR: latent_failure id=0x1\n",
    ));
    try std.testing.expect(isReadyCompilerLine(
        "macho-processor: READY COMPILER: BLOCKED kind=LABEL_REFERENCE_UNBOUND\n",
    ));
    try std.testing.expect(!isReadyCompilerLine(
        "[xenia] i> VdInitializeEngines completed\n",
    ));
}

pub const Kind = enum {
    process_launch,
    heartbeat,
    process_exit,
    import_resolution,
};

pub const Event = struct {
    kind: Kind,
    step: u64 = 0,
    thread_id: u64 = 0,
    guest_addr: u64 = 0,
    runnable: u32 = 0,
    blocked: u32 = 0,
    condvar_waits: u64 = 0,
    import_calls: u64 = 0,
    exit_code: i32 = 0,
    reason: []const u8 = "",
    symbol: []const u8 = "",
};

pub const Logger = struct {
    macho_fd: i32 = -1,
    scheduler_fd: i32 = -1,
    primitive_fd: i32 = -1,
    ready_compiler_fd: i32 = -1,

    pub fn isOpen(self: *const Logger) bool {
        return self.macho_fd >= 0;
    }

    pub fn open(self: *Logger, allocator: std.mem.Allocator) void {
        if (environmentPath("ROSETTE_MACHO_LOG")) |override_path| {
            if (override_path.len == 0 or std.ascii.eqlIgnoreCase(override_path, "off")) return;
            self.openPath(allocator, override_path);
            return;
        }
        const root = routeRoot() orelse return;
        const macho_path = std.fs.path.join(allocator, &.{ root, ".rosette", "rosette-macho.log" }) catch return;
        defer allocator.free(macho_path);
        self.openPath(allocator, macho_path);
    }

    pub fn openPath(self: *Logger, allocator: std.mem.Allocator, path: []const u8) void {
        const directory = std.fs.path.dirname(path) orelse return;
        makePathRecursive(allocator, directory) catch return;

        self.close();

        {
            const path_z = allocator.dupeZ(u8, path) catch return;
            defer allocator.free(path_z);
            const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
            if (fd < 0) return;
            self.macho_fd = fd;
            _ = c.write(fd, "=== rosette-macho.log opened ===\n", 33);
        }

        {
            const ext = std.fs.path.extension(path);
            const base_len = path.len - ext.len;
            const sched_path = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
                path[0..base_len],
                "-scheduler-table",
                ext,
            }) catch return;
            defer allocator.free(sched_path);
            const sched_z = allocator.dupeZ(u8, sched_path) catch return;
            defer allocator.free(sched_z);
            const fd = c.open(sched_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
            if (fd >= 0) {
                self.scheduler_fd = fd;
                _ = c.write(fd, "=== rosette-scheduler-table.log opened ===\n", 45);
            }
        }

        {
            const prim_path = std.fs.path.join(allocator, &.{ directory, "rosette-primitive.log" }) catch return;
            defer allocator.free(prim_path);
            const prim_z = allocator.dupeZ(u8, prim_path) catch return;
            defer allocator.free(prim_z);
            const fd = c.open(prim_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
            if (fd >= 0) {
                self.primitive_fd = fd;
                _ = c.write(fd, "=== rosette-primitive.log opened ===\n", 37);
            }
        }

        if (environmentPath("ROSETTE_READY_COMPILER_LOG")) |ready_path| {
            if (ready_path.len != 0 and !std.ascii.eqlIgnoreCase(ready_path, "off")) {
                self.openReadyCompilerPath(allocator, ready_path);
            }
        } else {
            const ready_path = std.fs.path.join(allocator, &.{ directory, "rosette-ready-compiler.log" }) catch return;
            defer allocator.free(ready_path);
            self.openReadyCompilerPath(allocator, ready_path);
        }

        ready_compiler_fd = self.ready_compiler_fd;
        setThreadFds(self.macho_fd, self.scheduler_fd, self.primitive_fd);
    }

    fn openReadyCompilerPath(self: *Logger, allocator: std.mem.Allocator, path: []const u8) void {
        const directory = std.fs.path.dirname(path) orelse return;
        makePathRecursive(allocator, directory) catch return;
        const path_z = allocator.dupeZ(u8, path) catch return;
        defer allocator.free(path_z);
        const fd = c.open(path_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC, @as(c_uint, 0o644));
        if (fd < 0) return;
        self.ready_compiler_fd = fd;
        writeAll(
            fd,
            "=== rosette-ready-compiler.log opened ===\n# Filtered readiness/compiler evidence; rosette-runtime.log remains the complete stream.\n",
        );
    }

    pub fn close(self: *Logger) void {
        resetThreadFds();
        if (self.macho_fd >= 0) {
            _ = c.write(self.macho_fd, "=== rosette-macho.log closed ===\n", 33);
            _ = c.close(self.macho_fd);
        }
        if (self.scheduler_fd >= 0) {
            _ = c.write(self.scheduler_fd, "=== rosette-scheduler-table.log closed ===\n", 45);
            _ = c.close(self.scheduler_fd);
        }
        if (self.primitive_fd >= 0) {
            _ = c.write(self.primitive_fd, "=== rosette-primitive.log closed ===\n", 37);
            _ = c.close(self.primitive_fd);
        }
        if (self.ready_compiler_fd >= 0) {
            writeAll(self.ready_compiler_fd, "=== rosette-ready-compiler.log closed ===\n");
            _ = c.close(self.ready_compiler_fd);
        }
        self.macho_fd = -1;
        self.scheduler_fd = -1;
        self.primitive_fd = -1;
        self.ready_compiler_fd = -1;
    }

    pub fn captureLine(self: *Logger, text: []const u8) void {
        if (self.macho_fd < 0) return;
        writeAll(self.macho_fd, text);
        if (text.len == 0 or text[text.len - 1] != '\n')
            _ = c.write(self.macho_fd, "\n", 1);
    }

    pub fn flush(self: *Logger) void {
        if (self.macho_fd >= 0) _ = c.fsync(self.macho_fd);
        if (self.scheduler_fd >= 0) _ = c.fsync(self.scheduler_fd);
        if (self.primitive_fd >= 0) _ = c.fsync(self.primitive_fd);
        if (self.ready_compiler_fd >= 0) _ = c.fsync(self.ready_compiler_fd);
    }

    pub fn emit(self: *Logger, event: Event) void {
        if (self.macho_fd < 0) return;
        var buffer: [4096]u8 = undefined;

        const line = switch (event.kind) {
            .process_launch => std.fmt.bufPrint(
                &buffer,
                "[process_launch] step=0 path={s}\n",
                .{event.reason},
            ) catch return,
            .heartbeat => std.fmt.bufPrint(
                &buffer,
                "[heartbeat] step={d} thread=0x{x} rip=0x{x} runnable={d} blocked={d} condvar={d} imports={d} symbol={s}\n",
                .{
                    event.step,
                    event.thread_id,
                    event.guest_addr,
                    event.runnable,
                    event.blocked,
                    event.condvar_waits,
                    event.import_calls,
                    event.symbol,
                },
            ) catch return,
            .process_exit => std.fmt.bufPrint(
                &buffer,
                "[process_exit] step={d} thread=0x{x} runnable={d} blocked={d} condvar={d} imports={d} exit_code={d} reason={s}\n",
                .{
                    event.step,
                    event.thread_id,
                    event.runnable,
                    event.blocked,
                    event.condvar_waits,
                    event.import_calls,
                    event.exit_code,
                    event.reason,
                },
            ) catch return,
            .import_resolution => std.fmt.bufPrint(
                &buffer,
                "[import_resolution] step={d} thread=0x{x} imports={d} reason={s}\n",
                .{
                    event.step,
                    event.thread_id,
                    event.import_calls,
                    event.reason,
                },
            ) catch return,
        };
        writeAll(self.macho_fd, line);
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

pub fn checkPointSync() void {
    if (thread_macho_fd >= 0) _ = c.fsync(thread_macho_fd);
    if (thread_scheduler_fd >= 0) _ = c.fsync(thread_scheduler_fd);
    if (thread_primitive_fd >= 0) _ = c.fsync(thread_primitive_fd);
    if (ready_compiler_fd >= 0) _ = c.fsync(ready_compiler_fd);
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
