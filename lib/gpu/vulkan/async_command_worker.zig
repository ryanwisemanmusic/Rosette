//! Bounded host worker for Vulkan commands with scalar or owned snapshot
//! arguments. The queue is a FIFO; callers must drain it
//! before issuing any Vulkan call that is not submitted through this worker.
const std = @import("std");
const abi = @import("abi.zig");
pub const owned = @import("owned_command_payloads.zig");
const queued_command = @import("queued_command.zig");

/// The dispatch gate and command implementation share this list. Snapshot
/// commands copy their arrays before admission and retain synchronous fallback.
pub fn isCandidate(name: []const u8) bool {
    inline for (.{ "vkCmdBindPipeline", "vkCmdBindIndexBuffer", "vkCmdDraw", "vkCmdDrawIndexed", "vkCmdBindDescriptorSets", "vkCmdPushConstants" }) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

pub const queue_capacity = 128;

pub const BindPipeline = struct {
    function: abi.PfnCmdBindPipeline,
    command_buffer: abi.CommandBuffer,
    bind_point: u32,
    pipeline: u64,
};

pub const BindIndexBuffer = struct {
    function: abi.PfnCmdBindIndexBuffer,
    command_buffer: abi.CommandBuffer,
    buffer: abi.Buffer,
    offset: u64,
    index_type: u32,
};

pub const Draw = struct {
    function: abi.PfnCmdDraw,
    command_buffer: abi.CommandBuffer,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
};

pub const DrawIndexed = struct {
    function: abi.PfnCmdDrawIndexed,
    command_buffer: abi.CommandBuffer,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
};

pub const Job = union(enum) {
    bind_pipeline: BindPipeline,
    bind_index_buffer: BindIndexBuffer,
    draw: Draw,
    draw_indexed: DrawIndexed,
    bind_descriptor_sets: owned.DescriptorSets,
    push_constants: owned.PushConstants,
};

/// Result of a non-blocking queue admission. A full queue is not an error:
/// the caller drains prior work and executes that Vulkan call synchronously.
pub const Submission = union(enum) {
    queued: u64,
    full,
    stopped,
};

const QueuedJob = struct {
    sequence: u64,
    command: queued_command.Command,
};

pub const max_batch_size: usize = 16;

pub const Stats = struct {
    submitted: u64,
    completed: u64,
    saturated_submissions: u64,
    batches: u64,
    max_batch_size: usize,
    max_depth: usize,
    work_signals: u64,
    drain_broadcasts: u64,
    last_submitted_sequence: u64,
    completed_sequence: u64,
    descriptor_snapshots: u64,
    push_snapshots: u64,
};

pub const Worker = struct {
    mutex: std.c.pthread_mutex_t = .{},
    work_available: std.c.pthread_cond_t = .{},
    drained: std.c.pthread_cond_t = .{},
    slots: [queue_capacity]QueuedJob = undefined,
    payloads: [queue_capacity]queued_command.Payload = undefined,
    read_index: usize = 0,
    write_index: usize = 0,
    count: usize = 0,
    max_depth: usize = 0,
    max_batch: usize = 0,
    batches: u64 = 0,
    work_signals: u64 = 0,
    drain_broadcasts: u64 = 0,
    drain_waiters: usize = 0,
    last_submitted_sequence: u64 = 0,
    completed_sequence: u64 = 0,
    /// The worker publishes completion after executing every Vulkan command
    /// in that sequence. Barriers can check the common already-drained case
    /// without taking the worker mutex a second time.
    completed_sequence_atomic: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    submitted: u64 = 0,
    completed: u64 = 0,
    saturated_submissions: u64 = 0,
    descriptor_snapshots: u64 = 0,
    push_snapshots: u64 = 0,
    stopping: bool = false,
    thread: ?std.Thread = null,

    pub fn start(self: *Worker) (std.Thread.SpawnError || error{AlreadyStarted})!void {
        if (self.thread != null) return error.AlreadyStarted;
        self.thread = try std.Thread.spawn(.{ .stack_size = 1024 * 1024 }, workerMain, .{self});
    }

    /// Admit a command without blocking the guest thread. Each accepted call
    /// receives a monotonically increasing sequence in Vulkan call order.
    pub fn trySubmit(self: *Worker, job: Job) Submission {
        lock(&self.mutex);
        if (self.stopping) {
            unlock(&self.mutex);
            return .stopped;
        }
        if (self.count == queue_capacity) {
            self.saturated_submissions +|= 1;
            unlock(&self.mutex);
            return .full;
        }

        const was_empty = self.count == 0;
        self.last_submitted_sequence +|= 1;
        const sequence = self.last_submitted_sequence;
        self.slots[self.write_index] = .{ .sequence = sequence, .command = queued_command.Command.pack(&job, &self.payloads[self.write_index]) };
        self.write_index = (self.write_index + 1) % queue_capacity;
        self.count += 1;
        self.max_depth = @max(self.max_depth, self.count);
        self.submitted +|= 1;
        switch (job) {
            .bind_descriptor_sets => self.descriptor_snapshots +|= 1,
            .push_constants => self.push_snapshots +|= 1,
            else => {},
        }
        // The worker sleeps only while the queue is empty. Submissions to a
        // nonempty queue are already covered by that first wake and need no
        // pthread condition signal (millions of redundant calls per run).
        if (was_empty) {
            signal(&self.work_available);
            self.work_signals +|= 1;
        }
        unlock(&self.mutex);
        return .{ .queued = sequence };
    }

    /// Snapshot the last command admitted before the caller's barrier.
    pub fn checkpoint(self: *Worker) u64 {
        lock(&self.mutex);
        const sequence = self.last_submitted_sequence;
        unlock(&self.mutex);
        return sequence;
    }

    /// Lock-free completion watermark for a checkpoint returned by
    /// `checkpoint`. A true result proves every command through that point
    /// has finished; a false result must still go through `drainThrough`.
    pub fn completedThrough(self: *const Worker, sequence: u64) bool {
        return self.completed_sequence_atomic.load(.acquire) >= sequence;
    }

    /// Wait until all calls through `sequence` have run on the Vulkan thread.
    pub fn drainThrough(self: *Worker, sequence: u64) void {
        if (self.completedThrough(sequence)) return;
        lock(&self.mutex);
        if (self.completed_sequence < sequence) {
            self.drain_waiters += 1;
            defer self.drain_waiters -= 1;
            while (self.completed_sequence < sequence) wait(&self.drained, &self.mutex);
        }
        unlock(&self.mutex);
    }

    /// Establishes a host-side Vulkan ordering barrier for all prior jobs.
    pub fn drain(self: *Worker) void {
        self.drainThrough(self.checkpoint());
    }

    pub fn stats(self: *const Worker) Stats {
        // Statistics are a read-only snapshot; the mutex is interior state
        // used only to make the bounded queue counters coherent.
        const mutex = @constCast(&self.mutex);
        lock(mutex);
        const result = Stats{
            .submitted = self.submitted,
            .completed = self.completed,
            .saturated_submissions = self.saturated_submissions,
            .batches = self.batches,
            .max_batch_size = self.max_batch,
            .max_depth = self.max_depth,
            .work_signals = self.work_signals,
            .drain_broadcasts = self.drain_broadcasts,
            .last_submitted_sequence = self.last_submitted_sequence,
            .completed_sequence = self.completed_sequence,
            .descriptor_snapshots = self.descriptor_snapshots,
            .push_snapshots = self.push_snapshots,
        };
        unlock(mutex);
        return result;
    }

    pub fn deinit(self: *Worker) void {
        self.drain();
        lock(&self.mutex);
        self.stopping = true;
        signal(&self.work_available);
        unlock(&self.mutex);
        if (self.thread) |*thread| {
            thread.join();
            self.thread = null;
        }
        _ = std.c.pthread_cond_destroy(&self.work_available);
        _ = std.c.pthread_cond_destroy(&self.drained);
        _ = std.c.pthread_mutex_destroy(&self.mutex);
    }
};

fn workerMain(worker: *Worker) void {
    var batch: [max_batch_size]QueuedJob = undefined;
    var payloads: [max_batch_size]queued_command.Payload = undefined;
    while (true) {
        lock(&worker.mutex);
        while (worker.count == 0 and !worker.stopping) wait(&worker.work_available, &worker.mutex);
        if (worker.count == 0 and worker.stopping) {
            unlock(&worker.mutex);
            return;
        }
        const batch_len = @min(worker.count, max_batch_size);
        for (0..batch_len) |index| {
            batch[index] = worker.slots[worker.read_index];
            batch[index].command.relocate(&payloads[index]);
            worker.read_index = (worker.read_index + 1) % queue_capacity;
        }
        worker.count -= batch_len;
        unlock(&worker.mutex);

        for (batch[0..batch_len]) |*queued| queued.command.execute();

        lock(&worker.mutex);
        worker.completed +|= batch_len;
        worker.completed_sequence = batch[batch_len - 1].sequence;
        worker.completed_sequence_atomic.store(worker.completed_sequence, .release);
        worker.batches +|= 1;
        worker.max_batch = @max(worker.max_batch, batch_len);
        if (worker.drain_waiters != 0) {
            broadcast(&worker.drained);
            worker.drain_broadcasts +|= 1;
        }
        unlock(&worker.mutex);
    }
}

test {
    _ = owned;
    _ = @import("command_flow_tests.zig");
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

var order: [32]u32 = undefined;
var order_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var blocking_started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var blocking_released: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn captureDraw(_: abi.CommandBuffer, _: u32, _: u32, first_vertex: u32, _: u32) callconv(.c) void {
    const index = order_len.fetchAdd(1, .monotonic);
    if (index < order.len) order[index] = first_vertex;
}

fn captureEndRenderPass(_: abi.CommandBuffer) callconv(.c) void {
    const index = order_len.fetchAdd(1, .monotonic);
    if (index < order.len) order[index] = 0xffff_fffe;
}

fn captureEndCommandBuffer(_: abi.CommandBuffer) callconv(.c) abi.Result {
    const index = order_len.fetchAdd(1, .monotonic);
    if (index < order.len) order[index] = 0xffff_ffff;
    return abi.SUCCESS;
}

fn captureBlockingDraw(_: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {
    blocking_started.store(true, .release);
    while (!blocking_released.load(.acquire)) std.atomic.spinLoopHint();
}

test "bounded Vulkan command worker preserves FIFO order and drains" {
    order_len.store(0, .monotonic);
    var worker: Worker = .{};
    try worker.start();
    defer worker.deinit();

    var last_sequence: u64 = 0;
    for (0..order.len) |index| {
        const submission = worker.trySubmit(.{ .draw = .{
            .function = captureDraw,
            .command_buffer = null,
            .vertex_count = 3,
            .instance_count = 1,
            .first_vertex = @intCast(index),
            .first_instance = 0,
        } });
        switch (submission) {
            .queued => |sequence| {
                try std.testing.expectEqual(last_sequence + 1, sequence);
                last_sequence = sequence;
            },
            .full => return error.UnexpectedQueueSaturation,
            .stopped => return error.UnexpectedWorkerShutdown,
        }
    }
    worker.drainThrough(last_sequence);
    try std.testing.expect(worker.completedThrough(last_sequence));
    try std.testing.expect(!worker.completedThrough(last_sequence + 1));

    const stats = worker.stats();
    try std.testing.expectEqual(@as(u64, order.len), stats.submitted);
    try std.testing.expectEqual(@as(u64, order.len), stats.completed);
    try std.testing.expectEqual(last_sequence, stats.last_submitted_sequence);
    try std.testing.expectEqual(last_sequence, stats.completed_sequence);
    try std.testing.expect(stats.batches > 0);
    try std.testing.expect(stats.max_batch_size > 0 and stats.max_batch_size <= max_batch_size);
    try std.testing.expectEqual(@as(usize, order.len), order_len.load(.monotonic));
    for (order, 0..) |value, index| try std.testing.expectEqual(@as(u32, @intCast(index)), value);
}

test "drain completes queued Vulkan draws before a synchronous FSI split boundary" {
    order_len.store(0, .monotonic);
    var worker: Worker = .{};
    try worker.start();
    defer worker.deinit();

    const draw = worker.trySubmit(.{ .draw = .{
        .function = captureDraw,
        .command_buffer = null,
        .vertex_count = 3,
        .instance_count = 1,
        .first_vertex = 7,
        .first_instance = 0,
    } });
    try std.testing.expect(draw == .queued);
    worker.drain();
    captureEndRenderPass(null);
    try std.testing.expectEqual(abi.SUCCESS, captureEndCommandBuffer(null));

    try std.testing.expectEqual(@as(usize, 3), order_len.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 7), order[0]);
    try std.testing.expectEqual(@as(u32, 0xffff_fffe), order[1]);
    try std.testing.expectEqual(@as(u32, 0xffff_ffff), order[2]);
}

test "full Vulkan worker queue requests ordered synchronous fallback" {
    blocking_started.store(false, .monotonic);
    blocking_released.store(false, .monotonic);
    var worker: Worker = .{};
    try worker.start();
    defer worker.deinit();
    defer blocking_released.store(true, .release);

    const first = worker.trySubmit(.{ .draw = .{
        .function = captureBlockingDraw,
        .command_buffer = null,
        .vertex_count = 3,
        .instance_count = 1,
        .first_vertex = 0,
        .first_instance = 0,
    } });
    try std.testing.expect(first == .queued);
    while (!blocking_started.load(.acquire)) std.atomic.spinLoopHint();

    for (0..queue_capacity) |_| {
        const submission = worker.trySubmit(.{ .draw = .{
            .function = captureDraw,
            .command_buffer = null,
            .vertex_count = 3,
            .instance_count = 1,
            .first_vertex = 0,
            .first_instance = 0,
        } });
        try std.testing.expect(submission == .queued);
    }
    try std.testing.expect(worker.trySubmit(.{ .draw = .{
        .function = captureDraw,
        .command_buffer = null,
        .vertex_count = 3,
        .instance_count = 1,
        .first_vertex = 0,
        .first_instance = 0,
    } }) == .full);
    try std.testing.expect(!worker.completedThrough(worker.checkpoint()));

    blocking_released.store(true, .release);
    worker.drain();
    try std.testing.expect(worker.completedThrough(worker.checkpoint()));
    const stats = worker.stats();
    try std.testing.expectEqual(@as(u64, queue_capacity + 1), stats.submitted);
    try std.testing.expectEqual(@as(u64, queue_capacity + 1), stats.completed);
    try std.testing.expectEqual(@as(u64, 1), stats.saturated_submissions);
    // The blocked native call keeps the worker busy while the entire queue
    // fills. Only the two empty-to-nonempty transitions need a wake signal.
    try std.testing.expectEqual(@as(u64, 2), stats.work_signals);
}
