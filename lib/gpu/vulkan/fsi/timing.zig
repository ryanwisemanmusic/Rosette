//! Completion observation latency of each bounded group of adjacent chunks
//! submits, measured by a watcher thread that waits on one bridge-owned fence
//! per group. Each VkSubmitInfo in a group remains a separate command buffer.
//!
//! Before this, a run log could not say how long the GPU took for anything:
//! the 2026-10-05 FSI run only showed the guest's fence waits (293 waits,
//! 41.2 s, longest 1.37 s) and then Metal's "Caused GPU Hang Error". The
//! watcher waits on the oldest outstanding fence with a short timeout. A
//! completion gives an upper bound from submission to fence observation,
//! including queue wait and watcher scheduling delay. Subtracting the previous
//! fence's observation time is invalid: several fences may already have
//! completed when this CPU thread next runs, inventing a zero-cost tail.
//! This conservative bound feeds `budget.zig`; it is not a GPU timestamp.
const std = @import("std");
const budget_mod = @import("budget.zig");

// AppKit can terminate through libc exit without running the forwarder's
// normal device teardown. Register after loading the Vulkan layer so its
// driver-owned dispatch data outlives our last fence wait on that exit path.
extern fn atexit(function: *const fn () callconv(.c) void) c_int;
var exit_mutex: std.c.pthread_mutex_t = .{};
var exit_monitors: [64]?*Monitor = @splat(null);

fn registerExitMonitor(monitor: *Monitor) bool {
    lock(&exit_mutex);
    defer unlock(&exit_mutex);
    for (&exit_monitors) |*slot| {
        if (slot.* == monitor) return true;
    }
    for (&exit_monitors) |*slot| {
        if (slot.* != null) continue;
        // Re-register for each new watcher: a recreated Vulkan loader/layer
        // may have installed later exit destructors. Empty older callbacks
        // are harmless. Registration failure refuses unprotected startup.
        if (atexit(stopExitMonitors) != 0) return false;
        slot.* = monitor;
        return true;
    }
    return false;
}

fn stopExitMonitors() callconv(.c) void {
    lock(&exit_mutex);
    defer unlock(&exit_mutex);
    for (&exit_monitors) |*slot| {
        if (slot.*) |monitor| monitor.stopWatcher();
        slot.* = null;
    }
}

pub const capacity: usize = 1024;
pub const poll_timeout_ns: u64 = 10 * budget_mod.ns_per_ms;
pub const max_in_flight_segments: usize = @import("../../metal/command_buffer_policy.zig").fsi.max_in_flight;
/// Keep one timing fence per small group of adjacent VkSubmitInfo batches.
/// Each VkSubmitInfo still becomes its own Metal command buffer in MoltenVK;
/// grouping only reduces host QueueSubmit calls. The room limit is divided by
/// this width so the number of command buffers queued on the GPU stays within
/// the existing policy ceiling.
pub const max_submit_infos_per_timing_group: usize = 2;
pub const max_in_flight_timing_groups: usize = max_in_flight_segments / max_submit_infos_per_timing_group;

/// Whether admitting a group would exceed the existing Metal command-buffer
/// depth bound. Group sizes vary when semaphore and guest-batch boundaries
/// prevent coalescing, so this must be weighted by VkSubmitInfo count rather
/// than by timing-fence/group count.
pub fn submitInfosWouldExceed(limit: usize, outstanding: usize, incoming: usize) bool {
    return incoming > limit or outstanding > limit - @min(limit, incoming);
}

pub const WaitResult = enum { signaled, timeout, failed };
pub const RoomResult = enum { available, failed, stopped, slow_chunk, runtime_lock_pinned };
pub const FailureStage = enum { none, wait_for_fences, reset_fences };
pub const TrackResult = struct { serial: u64, failed: bool };

/// How the watcher reaches the device: wrappers over vkWaitForFences and
/// vkResetFences in the forwarder, a simulated GPU in tests.
pub const FenceOps = struct {
    context: *anyopaque,
    wait: *const fn (context: *anyopaque, fence: u64, timeout_ns: u64) WaitResult,
    reset: *const fn (context: *anyopaque, fence: u64) bool,
    now: *const fn (context: *anyopaque) u64,
};

pub const Entry = struct {
    /// This group must complete before any later timed group is admitted.
    isolated: bool = false,
    serial: u64 = 0,
    fence: u64 = 0,
    submit_ns: u64 = 0,
    draws: u32 = 0,
    scissor_pixels: u64 = 0,
    max_draw_scissor_pixels: u64 = 0,
    /// Potential interlocked work: scissor pixels times raster samples.
    sample_work: u64 = 0,
    max_draw_sample_work: u64 = 0,
    guest_command_buffer: u64 = 0,
    segment: u16 = 0,
    segments: u16 = 0,
    queue_submit: u64 = 0,
    /// Number of VkSubmitInfo batches covered by this completion fence. A
    /// group is timed together, while every batch remains its own Metal
    /// command buffer and retains its original semaphore boundary.
    submit_infos: u8 = 1,
    first_pipeline_hash: u64 = 0,
    last_pipeline_hash: u64 = 0,
    escalation: budget_mod.Escalation = .none,
};

pub const ReportKind = enum { risk, severe, failed };

pub const Report = struct {
    kind: ReportKind,
    failure_stage: FailureStage = .none,
    /// A delayed observation can reveal a slow group after it completed.
    /// Such a sample tightens limits, but does not pause a healthy queue.
    completion_observed: bool = false,
    entry: Entry,
    running_ns: u64,
    cap: u32,
    outstanding: usize,
};

pub const Stats = struct {
    budget: budget_mod.Budget,
    tracked: u64,
    completed: u64,
    completed_serial: u64,
    outstanding: usize,
    max_outstanding: usize,
    outstanding_submit_infos: usize,
    max_outstanding_submit_infos: usize,
    fences_created: u64,
    room_waits: u64,
    room_wait_ns: u64,
    max_room_wait_ns: u64,
    ready_checks: u64,
    ready_completions: u64,
    failed: bool,
    submissions_paused: bool,
    severe_recoveries: u64,
};

pub const Monitor = struct {
    mutex: std.c.pthread_mutex_t = .{},
    work: std.c.pthread_cond_t = .{},
    room: std.c.pthread_cond_t = .{},
    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    head: usize = 0,
    count: usize = 0,
    max_outstanding: usize = 0,
    outstanding_submit_infos: usize = 0,
    max_outstanding_submit_infos: usize = 0,
    next_serial: u64 = 1,
    completed_serial: u64 = 0,
    last_completion_ns: u64 = 0,
    budget: budget_mod.Budget = .{},
    cap: std.atomic.Value(u32) = std.atomic.Value(u32).init(@import("../../metal/command_buffer_policy.zig").fsi.initial_draws),
    sample_work_cap: std.atomic.Value(u64) = std.atomic.Value(u64).init(@import("../../metal/command_buffer_policy.zig").fsi.initial_sample_work),
    /// Set by the watcher when a chunk reaches an escalation, so the guest
    /// thread can print the wider context it alone may read.
    context_dump_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    free_fences: [capacity]u64 = [_]u64{0} ** capacity,
    free_count: usize = 0,
    fences_created: u64 = 0,
    tracked: u64 = 0,
    completed: u64 = 0,
    room_waits: u64 = 0,
    room_wait_ns: u64 = 0,
    max_room_wait_ns: u64 = 0,
    ready_checks: u64 = 0,
    ready_completions: u64 = 0,
    stopping: bool = false,
    failed: bool = false,
    /// A group exceeded the severe observation-latency bound. Admit no more
    /// FSI work until ALL outstanding fences complete and reset successfully.
    /// A slow fence is not itself device loss. Recovery starts at minimum
    /// work; later qualifying completions may earn the small recovery quantum.
    /// The emergency draw cap stays pinned; actual fence failure stays terminal.
    submissions_paused: bool = false,
    severe_recoveries: u64 = 0,
    thread: ?std.Thread = null,
    ops: ?FenceOps = null,
    report: ?*const fn (Report) void = null,

    pub fn init(config: budget_mod.Config) Monitor {
        var monitor: Monitor = .{ .budget = budget_mod.Budget.init(config) };
        monitor.cap.store(monitor.budget.cap, .monotonic);
        monitor.sample_work_cap.store(monitor.budget.sample_work_cap, .monotonic);
        return monitor;
    }

    pub fn setShaderBoundsVerified(self: *Monitor, verified: bool) void {
        lock(&self.mutex);
        defer unlock(&self.mutex);
        self.budget.setShaderBoundsVerified(verified);
        self.sample_work_cap.store(self.budget.sample_work_cap, .monotonic);
    }

    /// Start the watcher thread. Without a thread `pollOnce` may be driven
    /// directly (tests do).
    pub fn start(self: *Monitor, ops: FenceOps, report: ?*const fn (Report) void) !void {
        self.ops = ops;
        self.report = report;
        if (self.thread == null) {
            self.thread = try std.Thread.spawn(.{ .stack_size = 256 * 1024 }, watcherMain, .{self});
            if (!registerExitMonitor(self)) {
                self.stopWatcher();
                return error.ExitMonitorUnavailable;
            }
        }
    }

    /// Stop the watcher and wait for it. Outstanding entries are abandoned;
    /// the caller destroys every fence `collectFences` returns.
    pub fn stop(self: *Monitor) void {
        // Keep the registry locked through join. An exit callback must not
        // see a monitor whose owner is concurrently freeing its storage.
        lock(&exit_mutex);
        defer unlock(&exit_mutex);
        for (&exit_monitors) |*slot| {
            if (slot.* == self) slot.* = null;
        }
        self.stopWatcher();
    }

    fn stopWatcher(self: *Monitor) void {
        lock(&self.mutex);
        self.stopping = true;
        broadcast(&self.work);
        broadcast(&self.room);
        unlock(&self.mutex);
        if (self.thread) |*thread| {
            thread.join();
            self.thread = null;
        }
    }

    /// Every fence the monitor owns, for destruction after `stop`.
    pub fn collectFences(self: *Monitor, out: []u64) usize {
        lock(&self.mutex);
        defer unlock(&self.mutex);
        var written: usize = 0;
        for (self.free_fences[0..self.free_count]) |fence| {
            if (written == out.len) break;
            out[written] = fence;
            written += 1;
        }
        for (0..self.count) |offset| {
            if (written == out.len) break;
            out[written] = self.entries[(self.head + offset) % capacity].fence;
            written += 1;
        }
        self.free_count = 0;
        self.count = 0;
        return written;
    }

    pub fn capValue(self: *const Monitor) u32 {
        return self.cap.load(.monotonic);
    }

    pub fn sampleWorkCapValue(self: *const Monitor) u64 {
        return self.sample_work_cap.load(.monotonic);
    }

    pub fn shouldSplit(self: *const Monitor, chunk_draws: u32, chunk_pixels: u64, next_draw_pixels: u64) bool {
        if (chunk_draws >= self.capValue()) return true;
        if (chunk_draws == 0) return false;
        const pixel_cap = self.sampleWorkCapValue();
        if (next_draw_pixels > pixel_cap) return true;
        return chunk_pixels > pixel_cap - next_draw_pixels;
    }

    /// Bound the number of Vulkan submissions MoltenVK can leave queued as
    /// Metal command buffers. This is called on the queue-submit thread, not
    /// the GPU watcher, and wakes as soon as the oldest timing fence retires.
    pub fn waitForRoom(self: *Monitor, limit: usize) RoomResult {
        if (limit == 0) return .available;
        lock(&self.mutex);
        defer unlock(&self.mutex);
        var wait_started_ns: ?u64 = null;
        while ((self.count >= limit or self.submissions_paused) and !self.failed and !self.stopping and self.thread != null) {
            if (wait_started_ns == null) {
                if (self.ops) |ops| wait_started_ns = ops.now(ops.context);
            }
            self.room_waits +|= 1;
            wait(&self.room, &self.mutex);
        }
        if (wait_started_ns) |started| {
            if (self.ops) |ops| {
                const elapsed = ops.now(ops.context) -| started;
                self.room_wait_ns +|= elapsed;
                self.max_room_wait_ns = @max(self.max_room_wait_ns, elapsed);
            }
        }
        if (self.failed) return .failed;
        if (self.stopping) return .stopped;
        // A paused monitor without a live watcher cannot prove completion.
        if (self.submissions_paused) return .slow_chunk;
        return .available;
    }

    /// Like `waitForRoom`, but bound actual command buffers represented by
    /// each timing entry. A one-info group consumes one slot; a coalesced
    /// two-info group consumes two.
    pub fn waitForSubmitInfos(self: *Monitor, limit: usize, incoming: usize) RoomResult {
        return self.waitForIsolatedSubmitInfos(limit, incoming, false);
    }

    pub fn waitForIsolatedSubmitInfos(self: *Monitor, limit: usize, incoming: usize, isolated: bool) RoomResult {
        if (incoming == 0) return .available;
        if (incoming > limit) return .failed;
        lock(&self.mutex);
        defer unlock(&self.mutex);
        var wait_started_ns: ?u64 = null;
        while ((submitInfosWouldExceed(limit, self.outstanding_submit_infos, incoming) or self.isolationPending(isolated) or self.submissions_paused) and
            !self.failed and !self.stopping and self.thread != null)
        {
            if (wait_started_ns == null) {
                if (self.ops) |ops| wait_started_ns = ops.now(ops.context);
            }
            self.room_waits +|= 1;
            wait(&self.room, &self.mutex);
        }
        if (wait_started_ns) |started| {
            if (self.ops) |ops| {
                const elapsed = ops.now(ops.context) -| started;
                self.room_wait_ns +|= elapsed;
                self.max_room_wait_ns = @max(self.max_room_wait_ns, elapsed);
            }
        }
        if (self.failed) return .failed;
        if (self.stopping) return .stopped;
        if (self.submissions_paused or self.isolationPending(isolated)) return .slow_chunk;
        return .available;
    }

    fn isolationPending(self: *const Monitor, incoming_isolated: bool) bool {
        if (self.count == 0) return false;
        if (incoming_isolated) return true;
        for (0..self.count) |i| if (self.entries[(self.head + i) % self.entries.len].isolated) return true;
        return false;
    }

    pub fn completedSerial(self: *Monitor) u64 {
        lock(&self.mutex);
        defer unlock(&self.mutex);
        return self.completed_serial;
    }

    /// A recycled, reset fence, or null when the caller must create one
    /// (and hand it over with `adoptFence` or by tracking it).
    pub fn takeFence(self: *Monitor) ?u64 {
        lock(&self.mutex);
        defer unlock(&self.mutex);
        if (self.free_count == 0) return null;
        self.free_count -= 1;
        return self.free_fences[self.free_count];
    }

    pub fn noteFenceCreated(self: *Monitor) void {
        lock(&self.mutex);
        self.fences_created +|= 1;
        unlock(&self.mutex);
    }

    /// Return a fence that was taken but never submitted.
    pub fn returnFence(self: *Monitor, fence: u64) void {
        lock(&self.mutex);
        defer unlock(&self.mutex);
        if (self.free_count < capacity) {
            self.free_fences[self.free_count] = fence;
            self.free_count += 1;
        }
    }

    /// Record a submitted timing group and wake the watcher. Returns its
    /// serial. The queue submitter enforces the much smaller Metal in-flight
    /// policy through `waitForRoom` before calling it.
    pub fn track(self: *Monitor, entry: Entry) u64 {
        return self.trackImpl(entry, false).serial;
    }

    /// Check a freshly submitted fence once, without blocking, before waking
    /// the watcher. Only an empty FIFO permits this: an older fence may be in
    /// the watcher's wait/reset call. Pending work still goes to that watcher.
    pub fn trackSubmitted(self: *Monitor, entry: Entry) TrackResult {
        return self.trackImpl(entry, true);
    }

    fn trackImpl(self: *Monitor, entry: Entry, check_ready: bool) TrackResult {
        var report: ?Report = null;
        lock(&self.mutex);
        defer {
            unlock(&self.mutex);
            if (report) |value| {
                if (self.report) |callback| callback(value);
            }
        }
        while (self.count == capacity and !self.stopping and !self.failed and self.thread != null) {
            self.room_waits +|= 1;
            wait(&self.room, &self.mutex);
        }
        if (self.count == capacity) {
            // No watcher to make room: account the oldest as complete.
            self.retireHeadLocked(self.last_completion_ns, false);
        }
        var stored = entry;
        stored.serial = self.next_serial;
        self.next_serial += 1;
        self.entries[(self.head + self.count) % capacity] = stored;
        self.count += 1;
        self.outstanding_submit_infos += stored.submit_infos;
        self.max_outstanding = @max(self.max_outstanding, self.count);
        self.max_outstanding_submit_infos = @max(self.max_outstanding_submit_infos, self.outstanding_submit_infos);
        self.tracked +|= 1;
        if (check_ready and self.count == 1 and !self.failed and !self.stopping) {
            if (self.ops) |ops| {
                self.ready_checks +|= 1;
                const result = ops.wait(ops.context, stored.fence, 0);
                const now = ops.now(ops.context);
                if (result == .signaled and ops.reset(ops.context, stored.fence)) {
                    self.ready_completions +|= 1;
                    report = self.finishHeadLocked(now);
                    return .{ .serial = stored.serial, .failed = false };
                }
                if (result != .timeout) {
                    // A failed reset is as terminal here as on the watcher.
                    // Do not retire the entry or recycle its fence/buffers.
                    self.failed = true;
                    broadcast(&self.room);
                    broadcast(&self.work);
                    report = .{
                        .kind = .failed,
                        .failure_stage = if (result == .failed) .wait_for_fences else .reset_fences,
                        .entry = stored,
                        .running_ns = now -| stored.submit_ns,
                        .cap = self.budget.cap,
                        .outstanding = self.count,
                    };
                    return .{ .serial = stored.serial, .failed = true };
                }
            }
        }
        signal(&self.work);
        return .{ .serial = stored.serial, .failed = self.failed };
    }

    /// One watcher step: wait for the oldest outstanding fence for up to
    /// `poll_timeout_ns`. Returns false when there is nothing to watch or the
    /// monitor stopped.
    pub fn pollOnce(self: *Monitor) bool {
        const ops = self.ops orelse return false;
        lock(&self.mutex);
        if (self.count == 0 or self.stopping or self.failed) {
            unlock(&self.mutex);
            return false;
        }
        const entry = self.entries[self.head];
        unlock(&self.mutex);

        const result = ops.wait(ops.context, entry.fence, poll_timeout_ns);
        const now = ops.now(ops.context);
        var report: ?Report = null;
        var keep_watching = true;
        lock(&self.mutex);
        switch (result) {
            .signaled => {
                if (ops.reset(ops.context, entry.fence)) {
                    report = self.finishHeadLocked(now);
                } else {
                    self.failed = true;
                    keep_watching = false;
                    broadcast(&self.room);
                    report = .{
                        .kind = .failed,
                        .failure_stage = .reset_fences,
                        .entry = entry,
                        .running_ns = now -| entry.submit_ns,
                        .cap = self.budget.cap,
                        .outstanding = self.count,
                    };
                }
            },
            .timeout => {
                const head = &self.entries[self.head];
                const running = now -| head.submit_ns;
                const reached = self.budget.noteOutstanding(running, head.escalation);
                self.cap.store(self.budget.cap, .monotonic);
                self.sample_work_cap.store(self.budget.sample_work_cap, .monotonic);
                if (reached != .none) {
                    head.escalation = reached;
                    self.context_dump_requested.store(true, .release);
                    if (reached == .severe) {
                        // Hold new work, but do not invent device loss from a
                        // latency upper bound. The submitter remains parked
                        // until every outstanding fence succeeds, or a real
                        // wait/reset failure or shutdown stops the monitor.
                        self.submissions_paused = true;
                        broadcast(&self.room);
                    }
                    report = .{
                        .kind = if (reached == .severe) .severe else .risk,
                        .entry = head.*,
                        .running_ns = running,
                        .cap = self.budget.cap,
                        .outstanding = self.count,
                    };
                }
            },
            .failed => {
                self.failed = true;
                keep_watching = false;
                broadcast(&self.room);
                report = .{ .kind = .failed, .failure_stage = .wait_for_fences, .entry = self.entries[self.head], .running_ns = now -| entry.submit_ns, .cap = self.budget.cap, .outstanding = self.count };
            },
        }
        unlock(&self.mutex);
        if (report) |value| {
            if (self.report) |callback| callback(value);
        }
        return keep_watching;
    }

    pub fn stats(self: *Monitor) Stats {
        lock(&self.mutex);
        defer unlock(&self.mutex);
        return .{
            .budget = self.budget,
            .tracked = self.tracked,
            .completed = self.completed,
            .completed_serial = self.completed_serial,
            .outstanding = self.count,
            .max_outstanding = self.max_outstanding,
            .outstanding_submit_infos = self.outstanding_submit_infos,
            .max_outstanding_submit_infos = self.max_outstanding_submit_infos,
            .fences_created = self.fences_created,
            .room_waits = self.room_waits,
            .room_wait_ns = self.room_wait_ns,
            .max_room_wait_ns = self.max_room_wait_ns,
            .ready_checks = self.ready_checks,
            .ready_completions = self.ready_completions,
            .failed = self.failed,
            .submissions_paused = self.submissions_paused,
            .severe_recoveries = self.severe_recoveries,
        };
    }

    fn finishHeadLocked(self: *Monitor, now: u64) ?Report {
        const entry = self.entries[self.head];
        const latency = now -| entry.submit_ns;
        const reached = self.budget.noteOutstanding(latency, entry.escalation);
        var report: ?Report = null;
        if (reached != .none) {
            self.context_dump_requested.store(true, .release);
            report = .{
                .kind = if (reached == .severe) .severe else .risk,
                .completion_observed = true,
                .entry = entry,
                .running_ns = latency,
                .cap = self.budget.cap,
                .outstanding = self.count,
            };
        }
        self.retireHeadLocked(now, true);
        return report;
    }

    fn retireHeadLocked(self: *Monitor, now: u64, measured: bool) void {
        const head = self.entries[self.head];
        if (measured) {
            const latency_ns = now -| head.submit_ns;
            self.budget.noteChunk(head.draws, head.sample_work, head.max_draw_sample_work, latency_ns);
            self.cap.store(self.budget.cap, .monotonic);
            self.sample_work_cap.store(self.budget.sample_work_cap, .monotonic);
            self.last_completion_ns = now;
        }
        self.completed_serial = head.serial;
        self.completed +|= 1;
        if (self.free_count < capacity) {
            self.free_fences[self.free_count] = head.fence;
            self.free_count += 1;
        }
        self.head = (self.head + 1) % capacity;
        self.count -= 1;
        self.outstanding_submit_infos -|= head.submit_infos;
        if (measured and self.count == 0 and self.submissions_paused and !self.failed and !self.stopping) {
            self.submissions_paused = false;
            self.severe_recoveries +|= 1;
            // Do not reset Budget.emergency or its risk/recovery state.
            // This completion resumes at minimum work. Any later work growth
            // requires the budget's separate, conservative recovery streak.
        }
        broadcast(&self.room);
    }
};

fn watcherMain(monitor: *Monitor) void {
    while (true) {
        lock(&monitor.mutex);
        while (monitor.count == 0 and !monitor.stopping and !monitor.failed) wait(&monitor.work, &monitor.mutex);
        const done = monitor.stopping or monitor.failed;
        unlock(&monitor.mutex);
        if (done) return;
        if (!monitor.pollOnce()) {
            lock(&monitor.mutex);
            const finished = monitor.stopping or monitor.failed;
            unlock(&monitor.mutex);
            if (finished) return;
        }
    }
}

fn lock(mutex: *std.c.pthread_mutex_t) void {
    if (std.c.pthread_mutex_lock(mutex) != .SUCCESS) unreachable;
}

fn unlock(mutex: *std.c.pthread_mutex_t) void {
    if (std.c.pthread_mutex_unlock(mutex) != .SUCCESS) unreachable;
}

fn wait(condition: *std.c.pthread_cond_t, mutex: *std.c.pthread_mutex_t) void {
    if (std.c.pthread_cond_wait(condition, mutex) != .SUCCESS) unreachable;
}

fn signal(condition: *std.c.pthread_cond_t) void {
    if (std.c.pthread_cond_signal(condition) != .SUCCESS) unreachable;
}

fn broadcast(condition: *std.c.pthread_cond_t) void {
    if (std.c.pthread_cond_broadcast(condition) != .SUCCESS) unreachable;
}

/// A GPU that finishes each fence at a scheduled time on a simulated clock.
const SimulatedGpu = struct {
    now_ns: u64 = 0,
    done_at: [16]u64 = [_]u64{std.math.maxInt(u64)} ** 16,
    resets: u32 = 0,
    fail: bool = false,
    fail_reset: bool = false,

    fn ops(self: *SimulatedGpu) FenceOps {
        return .{ .context = self, .wait = waitFn, .reset = resetFn, .now = nowFn };
    }
    fn waitFn(context: *anyopaque, fence: u64, timeout_ns: u64) WaitResult {
        const self: *SimulatedGpu = @ptrCast(@alignCast(context));
        if (self.fail) return .failed;
        const due = self.done_at[fence];
        if (due <= self.now_ns + timeout_ns) {
            self.now_ns = @max(self.now_ns, due);
            return .signaled;
        }
        self.now_ns += timeout_ns;
        return .timeout;
    }
    fn resetFn(context: *anyopaque, fence: u64) bool {
        const self: *SimulatedGpu = @ptrCast(@alignCast(context));
        _ = fence;
        self.resets += 1;
        return !self.fail_reset;
    }
    fn nowFn(context: *anyopaque) u64 {
        const self: *SimulatedGpu = @ptrCast(@alignCast(context));
        return self.now_ns;
    }
};

var test_reports: [8]Report = undefined;

test "FSI ready fence retirement preserves pending FIFO, timing and terminal failures" {
    for (0..5) |mode| {
        var gpu = SimulatedGpu{ .now_ns = 7 * budget_mod.ns_per_ms };
        gpu.done_at[1] = if (mode == 1) 9 * budget_mod.ns_per_ms else 0;
        gpu.fail = mode == 2;
        gpu.fail_reset = mode == 3;
        var monitor = Monitor.init(.{});
        monitor.ops = gpu.ops();
        if (mode == 4) _ = monitor.track(.{ .fence = 2 });
        const result = monitor.trackSubmitted(.{ .fence = 1, .draws = 4, .sample_work = 1024, .submit_infos = if (mode == 4) 1 else 2, .isolated = true });
        try std.testing.expectEqual(mode == 2 or mode == 3, result.failed);
        const stats = monitor.stats();
        try std.testing.expectEqual(@as(u64, if (mode == 4) 0 else 1), stats.ready_checks);
        try std.testing.expectEqual(@as(u64, if (mode == 0) 1 else 0), stats.ready_completions);
        if (mode == 0) {
            try std.testing.expectEqual(result.serial, stats.completed_serial);
            try std.testing.expectEqual(@as(u64, 7 * budget_mod.ns_per_ms), stats.budget.total_observed_ns);
            try std.testing.expectEqual(@as(usize, 0), stats.outstanding_submit_infos);
            try std.testing.expectEqual(@as(?u64, 1), monitor.takeFence());
        } else {
            try std.testing.expectEqual(@as(u64, 0), stats.completed_serial);
            try std.testing.expectEqual(@as(?u64, null), monitor.takeFence());
            try std.testing.expectEqual(@as(usize, 2), stats.outstanding_submit_infos);
            if (mode == 1) {
                try std.testing.expectEqual(RoomResult.slow_chunk, monitor.waitForIsolatedSubmitInfos(2, 1, false));
                try std.testing.expect(monitor.pollOnce());
                try std.testing.expectEqual(result.serial, monitor.stats().completed_serial);
            }
        }
    }
    // A fence already signaled at admission can still have taken too long.
    var gpu = SimulatedGpu{ .now_ns = 400 * budget_mod.ns_per_ms };
    gpu.done_at[1] = 0;
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    _ = monitor.trackSubmitted(.{ .fence = 1, .draws = 4, .sample_work = 1024 });
    try std.testing.expect(monitor.stats().budget.emergency);
    try std.testing.expectEqual(@as(u64, 1), monitor.stats().budget.severe_events);
}

test "FSI ready fence benchmark measures production monitor handoffs without a GPU" {
    const benchmark = if (std.c.getenv("ROSETTE_FSI_FENCE_BENCH")) |value| std.mem.eql(u8, std.mem.span(value), "1") else false;
    const iterations: u32 = if (benchmark) 20000 else 64;
    const ReadyFence = struct {
        resets: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        fn waitFn(_: *anyopaque, _: u64, _: u64) WaitResult {
            return .signaled;
        }
        fn resetFn(context: *anyopaque, _: u64) bool {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = self.resets.fetchAdd(1, .monotonic);
            return true;
        }
        fn nowFn(_: *anyopaque) u64 {
            return @import("../transport_timing.zig").nowNs();
        }
    };
    var elapsed: [2]u64 = undefined;
    for (0..2) |mode| {
        var gpu = ReadyFence{};
        var monitor = Monitor.init(.{});
        try monitor.start(.{ .context = &gpu, .wait = ReadyFence.waitFn, .reset = ReadyFence.resetFn, .now = ReadyFence.nowFn }, null);
        defer monitor.stop();
        const started = ReadyFence.nowFn(&gpu);
        for (0..iterations) |_| {
            try std.testing.expectEqual(RoomResult.available, monitor.waitForSubmitInfos(2, 2));
            const entry = Entry{ .fence = 1, .submit_ns = ReadyFence.nowFn(&gpu), .draws = 2, .sample_work = 1024, .submit_infos = 2 };
            if (mode == 0) {
                _ = monitor.track(entry);
            } else {
                try std.testing.expect(!monitor.trackSubmitted(entry).failed);
            }
        }
        try std.testing.expectEqual(RoomResult.available, monitor.waitForSubmitInfos(2, 2));
        elapsed[mode] = ReadyFence.nowFn(&gpu) - started;
        const stats = monitor.stats();
        try std.testing.expectEqual(@as(u64, iterations), stats.completed);
        try std.testing.expectEqual(iterations, gpu.resets.load(.monotonic));
        try std.testing.expectEqual(@as(u64, if (mode == 1) iterations else 0), stats.ready_completions);
        try std.testing.expectEqual(@as(usize, 2), stats.max_outstanding_submit_infos);
    }
    if (benchmark) std.debug.print("FSI ready fence benchmark: groups={d} watcher_ns={d} ready_ns={d}; production monitor, already-signaled stub fences, not GPU or gameplay FPS\n", .{ iterations, elapsed[0], elapsed[1] });
}

test "FSI process exit joins active and idle watchers before driver dispatch is unloaded" {
    const Driver = struct {
        extern fn exit(code: c_int) noreturn;
        extern fn _exit(code: c_int) noreturn;
        var exit_driver: ?*@This() = null;
        var exit_watchers: ?*[2]Monitor = null;
        calls: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        live: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
        stale: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        fn waitFn(context: *anyopaque, _: u64, timeout_ns: u64) WaitResult {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (!self.live.load(.acquire)) _ = self.stale.fetchAdd(1, .monotonic);
            _ = self.calls.fetchAdd(1, .release);
            const duration = std.c.timespec{ .sec = 0, .nsec = @intCast(timeout_ns) };
            _ = std.c.nanosleep(&duration, null);
            if (!self.live.load(.acquire)) _ = self.stale.fetchAdd(1, .monotonic);
            return .timeout;
        }
        fn resetFn(_: *anyopaque, _: u64) bool {
            return true;
        }
        fn nowFn(_: *anyopaque) u64 {
            return 0;
        }
        fn unloadAtExit() callconv(.c) void {
            for (exit_watchers.?) |*monitor| {
                if (monitor.thread != null) {
                    std.debug.print("FSI libc exit probe FAIL: watcher still live at layer unload\n", .{});
                    _exit(2);
                }
            }
            exit_driver.?.live.store(false, .release);
            std.debug.print("FSI libc exit probe PASS: all watchers joined before layer unload\n", .{});
        }
    };
    var driver = Driver{};
    var monitors = [_]Monitor{ Monitor.init(.{}), Monitor.init(.{}) };
    const probe = if (std.c.getenv("ROSETTE_FSI_EXIT_PROBE")) |value| std.mem.span(value) else "";
    if (probe.len != 0) {
        Driver.exit_driver = &driver;
        Driver.exit_watchers = &monitors;
        // This models the loader/layer destructor installed before its first
        // FSI watcher starts. Run directly as a throwaway test executable.
        if (!std.mem.eql(u8, probe, "wrong-order")) try std.testing.expectEqual(@as(c_int, 0), atexit(Driver.unloadAtExit));
    }
    _ = monitors[0].track(.{ .fence = 1 });
    for (&monitors) |*monitor| try monitor.start(.{ .context = &driver, .wait = Driver.waitFn, .reset = Driver.resetFn, .now = Driver.nowFn }, null);
    defer for (&monitors) |*monitor| monitor.stop();
    while (driver.calls.load(.acquire) == 0) std.Thread.yield() catch {};
    if (probe.len != 0) {
        if (std.mem.eql(u8, probe, "wrong-order")) try std.testing.expectEqual(@as(c_int, 0), atexit(Driver.unloadAtExit));
        Driver.exit(0);
    }
    // Exercise the actual registered callback before simulating layer unload.
    stopExitMonitors();
    driver.live.store(false, .release);
    for (&monitors) |*monitor| {
        try std.testing.expect(monitor.thread == null);
        try std.testing.expectEqual(RoomResult.stopped, monitor.waitForSubmitInfos(2, 1));
    }
    try std.testing.expectEqual(@as(u32, 0), driver.stale.load(.monotonic));
}

test "FSI isolated admission parks for a real watcher with a spare queue slot" {
    const FakeFence = struct {
        signaled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        fn waitFn(context: *anyopaque, _: u64, _: u64) WaitResult {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.signaled.load(.acquire)) return .signaled;
            std.Thread.yield() catch {};
            return .timeout;
        }
        fn resetFn(_: *anyopaque, _: u64) bool {
            return true;
        }
        fn nowFn(_: *anyopaque) u64 {
            return 0;
        }
        fn signalLater(self: *@This()) void {
            const pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
            _ = std.c.nanosleep(&pause, null);
            self.signaled.store(true, .release);
        }
    };
    for (0..2) |mode| {
        var fence: FakeFence = .{};
        var monitor = Monitor.init(.{});
        _ = monitor.track(.{ .fence = 1, .submit_infos = 1, .isolated = mode == 0 });
        try monitor.start(.{ .context = &fence, .wait = FakeFence.waitFn, .reset = FakeFence.resetFn, .now = FakeFence.nowFn }, null);
        defer monitor.stop();
        const signaler = try std.Thread.spawn(.{}, FakeFence.signalLater, .{&fence});
        defer signaler.join();
        try std.testing.expectEqual(RoomResult.available, monitor.waitForIsolatedSubmitInfos(2, 1, mode == 1));
        try std.testing.expect(fence.signaled.load(.acquire));
        try std.testing.expectEqual(@as(u64, 1), monitor.stats().completed);
    }
}

test "FSI isolated groups require successful retirement on both sides" {
    for (0..3) |mode| {
        var gpu: SimulatedGpu = .{};
        var monitor = Monitor.init(.{});
        monitor.ops = gpu.ops();
        _ = monitor.track(.{ .fence = 1, .draws = 1, .isolated = true });
        try std.testing.expectEqual(RoomResult.slow_chunk, monitor.waitForIsolatedSubmitInfos(2, 1, false));
        gpu.done_at[1] = 0;
        gpu.fail = mode == 1;
        gpu.fail_reset = mode == 2;
        _ = monitor.pollOnce();
        try std.testing.expectEqual(if (mode == 0) RoomResult.available else RoomResult.failed, monitor.waitForIsolatedSubmitInfos(2, 1, false));
    }
    var gpu: SimulatedGpu = .{};
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    _ = monitor.track(.{ .fence = 1 });
    try std.testing.expectEqual(RoomResult.slow_chunk, monitor.waitForIsolatedSubmitInfos(2, 1, true));
    gpu.done_at[1] = 0;
    _ = monitor.pollOnce();
    try std.testing.expectEqual(RoomResult.available, monitor.waitForIsolatedSubmitInfos(2, 1, true));
}
var test_report_count: usize = 0;

fn recordReport(report: Report) void {
    if (test_report_count < test_reports.len) test_reports[test_report_count] = report;
    test_report_count += 1;
}

test "FSI completed chunks give conservative submission-to-observation bounds" {
    var gpu: SimulatedGpu = .{};
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    // Two chunks queued together at t=0; the GPU finishes them at 30 ms and
    // 70 ms. The observer only knows conservative bounds of 30 and 70 ms.
    gpu.done_at[1] = 30 * budget_mod.ns_per_ms;
    gpu.done_at[2] = 70 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 1, .submit_ns = 0, .draws = 30, .scissor_pixels = 1_000_000, .sample_work = 1_000_000, .max_draw_scissor_pixels = 200_000 });
    _ = monitor.track(.{ .fence = 2, .submit_ns = 0, .draws = 40, .scissor_pixels = 2_000_000, .sample_work = 2_000_000, .max_draw_scissor_pixels = 400_000 });
    while (monitor.pollOnce()) {}
    const stats = monitor.stats();
    try std.testing.expectEqual(@as(u64, 2), stats.completed);
    try std.testing.expectEqual(@as(u64, 2), stats.completed_serial);
    try std.testing.expectEqual(@as(u64, 70 * budget_mod.ns_per_ms), stats.budget.max_chunk_ns);
    // 1 ms per draw: the cap follows the measured target but stays under the
    // Metal command-buffer policy's hard ceiling.
    try std.testing.expectEqual(@as(u32, 32), monitor.capValue());
    // Both fences were reset and are reusable.
    try std.testing.expectEqual(@as(u32, 2), gpu.resets);
    try std.testing.expect(monitor.takeFence() != null);
    try std.testing.expect(monitor.takeFence() != null);
    try std.testing.expect(monitor.takeFence() == null);
}

test "timing groups account for the bounded number of Metal command buffers they cover" {
    try std.testing.expectEqual(@as(usize, 2), max_submit_infos_per_timing_group);
    try std.testing.expectEqual(@as(usize, 1), max_in_flight_timing_groups);
    try std.testing.expectEqual(max_in_flight_segments, max_in_flight_timing_groups * max_submit_infos_per_timing_group);

    var gpu: SimulatedGpu = .{};
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    gpu.done_at[1] = 10 * budget_mod.ns_per_ms;
    gpu.done_at[2] = 20 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 1, .submit_ns = 0, .draws = 32, .submit_infos = 2 });
    _ = monitor.track(.{ .fence = 2, .submit_ns = 0, .draws = 16, .submit_infos = 2 });

    const queued = monitor.stats();
    try std.testing.expectEqual(@as(usize, 2), queued.outstanding);
    try std.testing.expectEqual(@as(usize, 4), queued.outstanding_submit_infos);
    try std.testing.expectEqual(@as(usize, 2), queued.max_outstanding);
    try std.testing.expectEqual(@as(usize, 4), queued.max_outstanding_submit_infos);
    while (monitor.pollOnce()) {}
    const drained = monitor.stats();
    try std.testing.expectEqual(@as(usize, 0), drained.outstanding);
    try std.testing.expectEqual(@as(usize, 0), drained.outstanding_submit_infos);
}

test "FSI queue room is charged by command buffers rather than timing groups" {
    try std.testing.expect(!submitInfosWouldExceed(4, 2, 2));
    try std.testing.expect(submitInfosWouldExceed(4, 3, 2));
    try std.testing.expect(!submitInfosWouldExceed(4, 3, 1));
    try std.testing.expect(submitInfosWouldExceed(4, 4, 1));
    try std.testing.expect(submitInfosWouldExceed(max_in_flight_segments, 0, max_in_flight_segments + 1));
}

test "a chunk still running is reported and tightens the cap before the watchdog fires" {
    test_report_count = 0;
    var gpu: SimulatedGpu = .{};
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    monitor.report = recordReport;
    gpu.done_at[3] = 1800 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 3, .submit_ns = 0, .draws = 48, .guest_command_buffer = 0x30, .segment = 2, .segments = 9, .submit_infos = 2 });
    while (monitor.pollOnce()) {}
    // Reported once at 200 ms (risk) and once at 350 ms (severe), then
    // completed at 1.8 s.
    try std.testing.expectEqual(@as(usize, 2), test_report_count);
    try std.testing.expectEqual(ReportKind.risk, test_reports[0].kind);
    try std.testing.expectEqual(@as(u16, 2), test_reports[0].entry.segment);
    try std.testing.expectEqual(@as(u8, 2), test_reports[0].entry.submit_infos);
    try std.testing.expectEqual(ReportKind.severe, test_reports[1].kind);
    try std.testing.expect(monitor.context_dump_requested.load(.acquire));
    try std.testing.expectEqual(@as(u32, 4), monitor.capValue());
    try std.testing.expectEqual(@as(u64, 1800 * budget_mod.ns_per_ms), monitor.stats().budget.max_chunk_ns);
    try std.testing.expect(!monitor.stats().submissions_paused);
    try std.testing.expectEqual(@as(u64, 1), monitor.stats().severe_recoveries);
    try std.testing.expectEqual(RoomResult.available, monitor.waitForRoom(max_in_flight_segments));
}

test "a device failure stops the watcher and is reported once" {
    test_report_count = 0;
    var gpu: SimulatedGpu = .{ .fail = true };
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    monitor.report = recordReport;
    _ = monitor.track(.{ .fence = 4, .submit_ns = 0, .draws = 1 });
    try std.testing.expect(!monitor.pollOnce());
    try std.testing.expect(!monitor.pollOnce());
    try std.testing.expectEqual(@as(usize, 1), test_report_count);
    try std.testing.expectEqual(ReportKind.failed, test_reports[0].kind);
    try std.testing.expectEqual(FailureStage.wait_for_fences, test_reports[0].failure_stage);
    try std.testing.expect(monitor.stats().failed);
    var fences: [4]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 1), monitor.collectFences(&fences));
    try std.testing.expectEqual(@as(u64, 4), fences[0]);
}

test "a failed fence reset stops reuse and blocks later Metal submissions" {
    test_report_count = 0;
    var gpu: SimulatedGpu = .{ .fail_reset = true };
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    monitor.report = recordReport;
    gpu.done_at[5] = 1;
    _ = monitor.track(.{ .fence = 5, .submit_ns = 0, .draws = 1 });
    try std.testing.expect(!monitor.pollOnce());
    try std.testing.expectEqual(@as(usize, 1), test_report_count);
    try std.testing.expectEqual(FailureStage.reset_fences, test_reports[0].failure_stage);
    try std.testing.expectEqual(RoomResult.failed, monitor.waitForRoom(max_in_flight_segments));
    try std.testing.expect(monitor.takeFence() == null);
}

test "the watcher thread measures chunks the GPU completes in real time" {
    const Real = struct {
        signaled: [4]std.atomic.Value(bool) = .{ std.atomic.Value(bool).init(false), std.atomic.Value(bool).init(false), std.atomic.Value(bool).init(false), std.atomic.Value(bool).init(false) },
        fn waitFn(context: *anyopaque, fence: u64, timeout_ns: u64) WaitResult {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = timeout_ns;
            var spins: u32 = 0;
            while (!self.signaled[fence].load(.acquire)) : (spins += 1) {
                if (spins > 1000) return .timeout;
                std.atomic.spinLoopHint();
            }
            return .signaled;
        }
        fn resetFn(context: *anyopaque, fence: u64) bool {
            _ = context;
            _ = fence;
            return true;
        }
        fn nowFn(context: *anyopaque) u64 {
            _ = context;
            return 1;
        }
    };
    var gpu: Real = .{};
    var monitor = Monitor.init(.{});
    try monitor.start(.{ .context = &gpu, .wait = Real.waitFn, .reset = Real.resetFn, .now = Real.nowFn }, null);
    const serial = monitor.track(.{ .fence = 1, .draws = 3 });
    gpu.signaled[1].store(true, .release);
    var waited: u32 = 0;
    while (monitor.completedSerial() < serial and waited < 10_000_000) : (waited += 1) std.atomic.spinLoopHint();
    monitor.stop();
    try std.testing.expectEqual(serial, monitor.completedSerial());
}

test "the FSI submitter waits for Metal queue room and resumes when a chunk completes" {
    const Real = struct {
        signaled: [5]std.atomic.Value(bool) = .{
            std.atomic.Value(bool).init(false),
            std.atomic.Value(bool).init(false),
            std.atomic.Value(bool).init(false),
            std.atomic.Value(bool).init(false),
            std.atomic.Value(bool).init(false),
        },
        fn waitFn(context: *anyopaque, fence: u64, timeout_ns: u64) WaitResult {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = timeout_ns;
            var spins: u32 = 0;
            while (!self.signaled[fence].load(.acquire)) : (spins += 1) {
                if (spins > 1000) return .timeout;
                std.atomic.spinLoopHint();
            }
            return .signaled;
        }
        fn resetFn(context: *anyopaque, fence: u64) bool {
            _ = context;
            _ = fence;
            return true;
        }
        fn nowFn(context: *anyopaque) u64 {
            _ = context;
            return 1;
        }
        fn ops(self: *@This()) FenceOps {
            return .{ .context = self, .wait = waitFn, .reset = resetFn, .now = nowFn };
        }
        fn signalLater(self: *@This()) void {
            var pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
            _ = std.c.nanosleep(&pause, null);
            self.signaled[1].store(true, .release);
        }
    };
    var gpu: Real = .{};
    var monitor = Monitor.init(.{});
    _ = monitor.track(.{ .fence = 1, .draws = 4, .submit_infos = 2 });

    try monitor.start(gpu.ops(), null);
    const signaler = try std.Thread.spawn(.{}, Real.signalLater, .{&gpu});
    try std.testing.expectEqual(RoomResult.available, monitor.waitForSubmitInfos(max_in_flight_segments, 2));
    signaler.join();
    monitor.stop();
    try std.testing.expect(monitor.stats().room_waits > 0);
    try std.testing.expectEqual(@as(usize, 0), monitor.stats().outstanding_submit_infos);
    try std.testing.expectEqual(max_in_flight_segments, monitor.stats().max_outstanding_submit_infos);
}

test "a failed Metal timing fence stops queue submissions instead of growing the lost-device queue" {
    var gpu: SimulatedGpu = .{ .fail = true };
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    _ = monitor.track(.{ .fence = 4, .submit_ns = 0, .draws = 1 });
    try std.testing.expect(!monitor.pollOnce());
    try std.testing.expectEqual(RoomResult.failed, monitor.waitForRoom(max_in_flight_segments));
}

test "FSI delayed fence observation never invents a zero-cost second chunk" {
    var gpu: SimulatedGpu = .{ .now_ns = 100 * budget_mod.ns_per_ms };
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    gpu.done_at[1] = 30 * budget_mod.ns_per_ms;
    gpu.done_at[2] = 70 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 1, .submit_ns = 0, .draws = 16, .scissor_pixels = 1_000_000, .sample_work = 1_000_000 });
    _ = monitor.track(.{ .fence = 2, .submit_ns = 0, .draws = 16, .scissor_pixels = 1_000_000, .sample_work = 1_000_000 });
    while (monitor.pollOnce()) {}
    // The watcher only knows when it observed completion. Both upper bounds
    // are 100 ms, even though the GPU actually finished at 30 and 70 ms.
    try std.testing.expectEqual(@as(u64, 200 * budget_mod.ns_per_ms), monitor.stats().budget.total_observed_ns);
    try std.testing.expectEqual(@as(u64, 100), monitor.stats().budget.ns_per_sample);
}

test "FSI late completed-fence observations tighten budgets without pausing a completed queue" {
    test_report_count = 0;
    var gpu: SimulatedGpu = .{ .now_ns = 800 * budget_mod.ns_per_ms };
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    monitor.report = recordReport;
    gpu.done_at[1] = 30 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 1, .submit_ns = 0, .draws = 16, .sample_work = 1_000_000 });
    while (monitor.pollOnce()) {}
    try std.testing.expectEqual(@as(usize, 1), test_report_count);
    try std.testing.expectEqual(ReportKind.severe, test_reports[0].kind);
    try std.testing.expect(test_reports[0].completion_observed);
    try std.testing.expect(monitor.stats().budget.emergency);
    try std.testing.expect(!monitor.stats().submissions_paused);
    try std.testing.expectEqual(RoomResult.available, monitor.waitForSubmitInfos(max_in_flight_segments, 2));
}

test "FSI campaign completion at 466 ms recovers the severe pause without inventing device loss" {
    var gpu: SimulatedGpu = .{};
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    // The supplied campaign: two Metal buffers, 16 draws, severe at 356 ms,
    // then a successful fence observed at 466 ms. No driver failure occurred.
    gpu.done_at[1] = 466 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 1, .draws = 16, .sample_work = 11_796_480, .max_draw_sample_work = 737_280, .submit_infos = 2 });
    while (!monitor.stats().submissions_paused) try std.testing.expect(monitor.pollOnce());
    try std.testing.expectEqual(@as(u64, 0), monitor.stats().severe_recoveries);
    try std.testing.expectEqual(@as(u32, 4), monitor.capValue());
    try std.testing.expectEqual(@as(u64, 512 * 1024), monitor.sampleWorkCapValue());
    // Without a live watcher, pending work still cannot be submitted past.
    try std.testing.expectEqual(RoomResult.slow_chunk, monitor.waitForSubmitInfos(max_in_flight_segments, 1));
    while (monitor.pollOnce()) {}
    const recovered = monitor.stats();
    try std.testing.expect(!recovered.failed and !recovered.submissions_paused);
    try std.testing.expectEqual(@as(u64, 1), recovered.severe_recoveries);
    try std.testing.expectEqual(@as(u64, 466 * budget_mod.ns_per_ms), recovered.budget.max_chunk_ns);
    try std.testing.expectEqual(RoomResult.available, monitor.waitForSubmitInfos(max_in_flight_segments, 2));
    // Unverified/short follow-up work cannot restore the pre-severe ceilings.
    for (0..1000) |_| {
        const fence = monitor.takeFence().?;
        gpu.done_at[fence] = gpu.now_ns + budget_mod.ns_per_ms;
        _ = monitor.track(.{ .fence = fence, .submit_ns = gpu.now_ns, .draws = 4, .sample_work = 512 * 1024 });
        while (monitor.pollOnce()) {}
    }
    try std.testing.expect(monitor.stats().budget.emergency);
    try std.testing.expectEqual(@as(u32, 4), monitor.capValue());
    try std.testing.expectEqual(@as(u64, 512 * 1024), monitor.sampleWorkCapValue());
}

test "FSI monitor publishes bounded recovery work only after completed and reset fences" {
    const policy = @import("../../metal/command_buffer_policy.zig").fsi;
    var gpu: SimulatedGpu = .{};
    var monitor = Monitor.init(.{});
    monitor.ops = gpu.ops();
    monitor.setShaderBoundsVerified(true);
    gpu.done_at[1] = 509 * budget_mod.ns_per_ms;
    _ = monitor.track(.{ .fence = 1, .draws = 64, .sample_work = 30_234_368, .submit_infos = 2 });
    while (monitor.pollOnce()) {}
    try std.testing.expectEqual(@as(u64, 1), monitor.stats().severe_recoveries);
    try std.testing.expectEqual(policy.min_sample_work, monitor.sampleWorkCapValue());
    for (0..policy.recovery_samples * 2) |_| {
        const fence = monitor.takeFence().?;
        const work = monitor.sampleWorkCapValue();
        gpu.done_at[fence] = gpu.now_ns + budget_mod.ns_per_ms;
        _ = monitor.track(.{ .fence = fence, .submit_ns = gpu.now_ns, .draws = 2, .sample_work = work, .submit_infos = 2 });
        while (monitor.pollOnce()) {}
    }
    try std.testing.expectEqual(policy.recovery_max_sample_work, monitor.sampleWorkCapValue());
    try std.testing.expectEqual(policy.min_draws, monitor.capValue());
    try std.testing.expectEqual(@as(u64, 2), monitor.stats().budget.recovery_growths);
    try std.testing.expectEqual(@as(usize, 2), monitor.stats().max_outstanding_submit_infos);
    // A reset failure cannot publish another successful calibration sample.
    const samples = monitor.stats().budget.samples;
    const fence = monitor.takeFence().?;
    gpu.done_at[fence] = gpu.now_ns + budget_mod.ns_per_ms;
    gpu.fail_reset = true;
    _ = monitor.track(.{ .fence = fence, .submit_ns = gpu.now_ns, .draws = 2, .sample_work = monitor.sampleWorkCapValue() });
    while (monitor.pollOnce()) {}
    try std.testing.expectEqual(samples, monitor.stats().budget.samples);
    try std.testing.expectEqual(RoomResult.failed, monitor.waitForRoom(max_in_flight_segments));
}

test "FSI severe recovery requires all outstanding fences and successful resets" {
    for (0..2) |failure| {
        var gpu: SimulatedGpu = .{};
        var monitor = Monitor.init(.{});
        monitor.ops = gpu.ops();
        gpu.done_at[1] = 400 * budget_mod.ns_per_ms;
        gpu.done_at[2] = 466 * budget_mod.ns_per_ms;
        _ = monitor.track(.{ .fence = 1, .draws = 8 });
        _ = monitor.track(.{ .fence = 2, .draws = 8 });
        while (monitor.completedSerial() < 1) try std.testing.expect(monitor.pollOnce());
        try std.testing.expect(monitor.stats().submissions_paused);
        try std.testing.expectEqual(@as(u64, 0), monitor.stats().severe_recoveries);
        // Even the spare slot is unavailable during a severe pause.
        try std.testing.expectEqual(RoomResult.slow_chunk, monitor.waitForSubmitInfos(max_in_flight_segments, 1));
        gpu.fail_reset = failure == 0;
        gpu.fail = failure == 1;
        while (monitor.pollOnce()) {}
        try std.testing.expect(monitor.stats().failed);
        try std.testing.expect(monitor.stats().submissions_paused);
        try std.testing.expectEqual(@as(u64, 0), monitor.stats().severe_recoveries);
        try std.testing.expectEqual(RoomResult.failed, monitor.waitForSubmitInfos(max_in_flight_segments, 1));
        try std.testing.expectEqual(@as(u64, 1), monitor.completedSerial());
    }
}

test "FSI severe pause parks the live submitter even with spare queue room" {
    const Real = struct {
        signaled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        fn waitFn(context: *anyopaque, fence: u64, timeout_ns: u64) WaitResult {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = fence;
            _ = timeout_ns;
            if (self.signaled.load(.acquire)) return .signaled;
            std.Thread.yield() catch {};
            return .timeout;
        }
        fn resetFn(context: *anyopaque, fence: u64) bool {
            _ = context;
            _ = fence;
            return true;
        }
        fn nowFn(context: *anyopaque) u64 {
            _ = context;
            return 466 * budget_mod.ns_per_ms;
        }
        fn signalLater(self: *@This()) void {
            const pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
            _ = std.c.nanosleep(&pause, null);
            self.signaled.store(true, .release);
        }
    };
    for (0..2) |mode| {
        var gpu: Real = .{};
        var monitor = Monitor.init(.{});
        _ = monitor.track(.{ .fence = 1, .draws = 8, .submit_infos = 1 });
        try monitor.start(.{ .context = &gpu, .wait = Real.waitFn, .reset = Real.resetFn, .now = Real.nowFn }, null);
        defer monitor.stop();
        var spins: u32 = 0;
        while (!monitor.stats().submissions_paused and spins < 1_000_000) : (spins += 1) std.atomic.spinLoopHint();
        try std.testing.expect(monitor.stats().submissions_paused);
        const signaler = try std.Thread.spawn(.{}, Real.signalLater, .{&gpu});
        defer signaler.join();
        const room = if (mode == 0) monitor.waitForRoom(2) else monitor.waitForSubmitInfos(2, 1);
        try std.testing.expectEqual(RoomResult.available, room);
        try std.testing.expect(gpu.signaled.load(.acquire));
        try std.testing.expectEqual(@as(u64, 1), monitor.stats().severe_recoveries);
        try std.testing.expect(monitor.stats().budget.emergency);
        try std.testing.expect(!monitor.stats().failed);
    }
}
