//! Bounded host worker for Vulkan commands whose arguments contain no
//! pointers into guest memory. The queue is a FIFO; callers must drain it
//! before issuing any Vulkan call that is not submitted through this worker.
const std = @import("std");
const abi = @import("abi.zig");

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

    fn execute(self: Job) void {
        switch (self) {
            .bind_pipeline => |call| call.function(call.command_buffer, call.bind_point, call.pipeline),
            .bind_index_buffer => |call| call.function(call.command_buffer, call.buffer, call.offset, call.index_type),
            .draw => |call| call.function(call.command_buffer, call.vertex_count, call.instance_count, call.first_vertex, call.first_instance),
            .draw_indexed => |call| call.function(call.command_buffer, call.index_count, call.instance_count, call.first_index, call.vertex_offset, call.first_instance),
        }
    }
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
    command: Job,
};

pub const max_batch_size: usize = 16;

pub const Stats = struct {
    submitted: u64,
    completed: u64,
    saturated_submissions: u64,
    batches: u64,
    max_batch_size: usize,
    max_depth: usize,
    last_submitted_sequence: u64,
    completed_sequence: u64,
};

pub const Worker = struct {
    mutex: std.c.pthread_mutex_t = .{},
    work_available: std.c.pthread_cond_t = .{},
    drained: std.c.pthread_cond_t = .{},
    slots: [queue_capacity]QueuedJob = undefined,
    read_index: usize = 0,
    write_index: usize = 0,
    count: usize = 0,
    max_depth: usize = 0,
    max_batch: usize = 0,
    batches: u64 = 0,
    last_submitted_sequence: u64 = 0,
    completed_sequence: u64 = 0,
    submitted: u64 = 0,
    completed: u64 = 0,
    saturated_submissions: u64 = 0,
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

        self.last_submitted_sequence +|= 1;
        const sequence = self.last_submitted_sequence;
        self.slots[self.write_index] = .{ .sequence = sequence, .command = job };
        self.write_index = (self.write_index + 1) % queue_capacity;
        self.count += 1;
        self.max_depth = @max(self.max_depth, self.count);
        self.submitted +|= 1;
        signal(&self.work_available);
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

    /// Wait until all calls through `sequence` have run on the Vulkan thread.
    pub fn drainThrough(self: *Worker, sequence: u64) void {
        lock(&self.mutex);
        while (self.completed_sequence < sequence) wait(&self.drained, &self.mutex);
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
            .last_submitted_sequence = self.last_submitted_sequence,
            .completed_sequence = self.completed_sequence,
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
            worker.read_index = (worker.read_index + 1) % queue_capacity;
        }
        worker.count -= batch_len;
        unlock(&worker.mutex);

        for (batch[0..batch_len]) |queued| queued.command.execute();

        lock(&worker.mutex);
        worker.completed +|= batch_len;
        worker.completed_sequence = batch[batch_len - 1].sequence;
        worker.batches +|= 1;
        worker.max_batch = @max(worker.max_batch, batch_len);
        broadcast(&worker.drained);
        unlock(&worker.mutex);
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

var order: [32]u32 = undefined;
var order_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var blocking_started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var blocking_released: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn captureDraw(_: abi.CommandBuffer, _: u32, _: u32, first_vertex: u32, _: u32) callconv(.c) void {
    const index = order_len.fetchAdd(1, .monotonic);
    if (index < order.len) order[index] = first_vertex;
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

    blocking_released.store(true, .release);
    worker.drain();
    const stats = worker.stats();
    try std.testing.expectEqual(@as(u64, queue_capacity + 1), stats.submitted);
    try std.testing.expectEqual(@as(u64, queue_capacity + 1), stats.completed);
    try std.testing.expectEqual(@as(u64, 1), stats.saturated_submissions);
}
