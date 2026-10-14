//! Diagnostic disk I/O owns its bytes and never blocks shader creation on disk.
//! Bounded admission refuses excess evidence explicitly; it never drops GPU work.
const std = @import("std");
const evidence = @import("evidence.zig");
const Mutex = struct {
    raw: std.c.pthread_mutex_t = .{},
    pub fn lock(self: *@This()) void {
        if (std.c.pthread_mutex_lock(&self.raw) != .SUCCESS) unreachable;
    }
    pub fn unlock(self: *@This()) void {
        if (std.c.pthread_mutex_unlock(&self.raw) != .SUCCESS) unreachable;
    }
};
const Condition = struct {
    raw: std.c.pthread_cond_t = .{},
    fn wait(self: *@This(), mutex: *Mutex) void {
        if (std.c.pthread_cond_wait(&self.raw, &mutex.raw) != .SUCCESS) unreachable;
    }
    fn signal(self: *@This()) void {
        if (std.c.pthread_cond_signal(&self.raw) != .SUCCESS) unreachable;
    }
    fn broadcast(self: *@This()) void {
        if (std.c.pthread_cond_broadcast(&self.raw) != .SUCCESS) unreachable;
    }
};
pub const capacity = 1024;
pub const maximum_pending_bytes = 64 * 1024 * 1024;
pub const Request = struct { directory: []const u8, guest: u64, words: []const u32, version: evidence.Version };
pub const Sink = *const fn (?*anyopaque, Request) evidence.Result;
pub const Result = enum { queued, invalid, limited, failed, stopped };
pub const State = struct {
    enabled: ?bool = null,
    writer: ?*Writer = null,
    start_failures: u64 = 0,
};
pub const Stats = struct {
    accepted: u64 = 0,
    saved: u64 = 0,
    failures: u64 = 0,
    limited: u64 = 0,
    cancelled: u64 = 0,
    accepted_bytes: usize = 0,
    pending_bytes: usize = 0,
    peak_bytes: usize = 0,
    worker_ns: u64 = 0,
    max_worker_ns: u64 = 0,
};
extern fn atexit(function: *const fn () callconv(.c) void) c_int;
var exit_mutex: Mutex = .{};
var exit_writers: [64]?*Writer = @splat(null);
fn stopAtExit() callconv(.c) void {
    exit_mutex.lock();
    defer exit_mutex.unlock();
    for (&exit_writers) |*slot| {
        if (slot.*) |writer| {
            writer.stopWorker();
            writer.report();
        }
        slot.* = null;
    }
}
fn now() u64 {
    var t: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &t) != 0) return 0;
    return @as(u64, @intCast(t.sec)) * std.time.ns_per_s + @as(u64, @intCast(t.nsec));
}
fn disk(_: ?*anyopaque, request: Request) evidence.Result {
    // Admission enforces the cumulative run limit, including pending bytes.
    var writer: evidence.Writer = .{};
    return writer.save(request.directory, request.guest, request.words, request.version);
}
pub const Writer = struct {
    allocator: std.mem.Allocator,
    sink: Sink,
    context: ?*anyopaque,
    mutex: Mutex = .{},
    changed: Condition = .{},
    jobs: [capacity]?Request = @splat(null),
    head: usize = 0,
    count: usize = 0,
    active: bool = false,
    stopping: bool = false,
    thread: ?std.Thread = null,
    stats: Stats = .{},
    pub fn create(allocator: std.mem.Allocator, sink: ?Sink, context: ?*anyopaque) !*Writer {
        const self = try allocator.create(Writer);
        errdefer allocator.destroy(self);
        self.* = .{ .allocator = allocator, .sink = sink orelse disk, .context = context };
        exit_mutex.lock();
        defer exit_mutex.unlock();
        for (&exit_writers) |*slot| {
            if (slot.* != null) continue;
            // Register late so the thread is joined before library unload,
            // including AppKit's libc-exit path that bypasses normal teardown.
            if (atexit(stopAtExit) != 0) return error.ExitRegistrationFailed;
            self.thread = try std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{self});
            slot.* = self;
            return self;
        }
        return error.ExitRegistryFull;
    }
    pub fn enqueue(self: *Writer, request: Request) Result {
        const bytes = std.mem.sliceAsBytes(request.words).len;
        if (request.words.len < 5 or request.words[0] != 0x07230203 or bytes > evidence.maximum_module_bytes or request.directory.len > 4090) return .invalid;
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.stopping) return .stopped;
        if (self.count == capacity or bytes > maximum_pending_bytes - self.stats.pending_bytes or bytes > evidence.maximum_run_bytes - self.stats.accepted_bytes) {
            self.stats.limited +|= 1;
            return .limited;
        }
        const directory = self.allocator.dupe(u8, request.directory) catch {
            self.stats.failures +|= 1;
            return .failed;
        };
        const words = self.allocator.dupe(u32, request.words) catch {
            self.allocator.free(directory);
            self.stats.failures +|= 1;
            return .failed;
        };
        self.jobs[(self.head + self.count) % capacity] = .{ .directory = directory, .words = words, .guest = request.guest, .version = request.version };
        self.count += 1;
        self.stats.accepted +|= 1;
        self.stats.accepted_bytes += bytes;
        self.stats.pending_bytes += bytes;
        self.stats.peak_bytes = @max(self.stats.peak_bytes, self.stats.pending_bytes);
        self.changed.signal();
        return .queued;
    }
    fn free(self: *Writer, job: Request) void {
        self.allocator.free(job.words);
        self.allocator.free(job.directory);
    }
    fn run(self: *Writer) void {
        self.mutex.lock();
        while (true) {
            while (self.count == 0 and !self.stopping) self.changed.wait(&self.mutex);
            if (self.stopping) break;
            const job = self.jobs[self.head].?;
            self.jobs[self.head] = null;
            self.head = (self.head + 1) % capacity;
            self.count -= 1;
            self.active = true;
            self.mutex.unlock();
            const started = now();
            const result = self.sink(self.context, job);
            const elapsed = now() -| started;
            const bytes = std.mem.sliceAsBytes(job.words).len;
            self.free(job);
            self.mutex.lock();
            self.active = false;
            self.stats.pending_bytes -= bytes;
            self.stats.worker_ns +|= elapsed;
            self.stats.max_worker_ns = @max(self.stats.max_worker_ns, elapsed);
            if (result == .saved) self.stats.saved +|= 1 else self.stats.failures +|= 1;
            self.changed.broadcast();
        }
        // Shutdown joins the active write, then cancels queued diagnostics.
        // Never spend minutes draining disk backlog at a library unload.
        while (self.count != 0) {
            const job = self.jobs[self.head].?;
            self.jobs[self.head] = null;
            self.head = (self.head + 1) % capacity;
            self.count -= 1;
            self.stats.pending_bytes -= std.mem.sliceAsBytes(job.words).len;
            self.stats.cancelled +|= 1;
            self.free(job);
        }
        self.changed.broadcast();
        self.mutex.unlock();
    }
    pub fn snapshot(self: *Writer) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }
    /// Offline checks only; gameplay never waits for diagnostic completion.
    pub fn flush(self: *Writer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        while ((self.count != 0 or self.active) and !self.stopping) self.changed.wait(&self.mutex);
    }
    fn stopWorker(self: *Writer) void {
        self.mutex.lock();
        self.stopping = true;
        self.changed.broadcast();
        self.mutex.unlock();
        if (self.thread) |thread| thread.join();
        self.thread = null;
    }
    pub fn stop(self: *Writer) void {
        exit_mutex.lock();
        defer exit_mutex.unlock();
        for (&exit_writers) |*slot| if (slot.* == self) {
            slot.* = null;
        };
        self.stopWorker();
    }
    pub fn report(self: *Writer) void {
        const s = self.snapshot();
        std.log.info("VULKAN FSI EVIDENCE IO: accepted={d} saved={d} failed={d} limited={d} cancelled={d} pending_bytes={d} peak_bytes={d} worker_us={d} max_worker_us={d}; queued is not saved; bounded owned diagnostics only; shader creation never waits for disk completion", .{ s.accepted, s.saved, s.failures, s.limited, s.cancelled, s.pending_bytes, s.peak_bytes, s.worker_ns / 1000, s.max_worker_ns / 1000 });
    }
    pub fn destroy(self: *Writer) void {
        self.stop();
        _ = std.c.pthread_cond_destroy(&self.changed.raw);
        _ = std.c.pthread_mutex_destroy(&self.mutex.raw);
        self.allocator.destroy(self);
    }
};
