//! CPU recording FIFO source comparison. Every draw/barrier callback is checked;
//! no Vulkan device or GPU work. Before lacks the snapshot variant, so it uses
//! the old mandatory drain and synchronous barrier, with the same callbacks.
const std = @import("std");
const gpu = @import("gpu");
const fifo = gpu.vulkan.async_command_worker;
const abi = gpu.vulkan.abi;
const clock = gpu.vulkan.transport_timing;

const Capture = struct {
    events: u64 = 0,
    errors: u64 = 0,
    checksum: u64 = 0,
    scalar: bool = false,
    fn context(buffer: abi.CommandBuffer) *Capture {
        return @ptrCast(@alignCast(buffer.?));
    }
    fn draw(buffer: abi.CommandBuffer, _: u32, _: u32, value: u32, _: u32) callconv(.c) void {
        const self = context(buffer);
        if (!self.scalar and self.events % 3 == 1) self.errors += 1;
        self.events += 1;
        self.checksum +%= value;
    }
    fn barrier(buffer: abi.CommandBuffer, src: u32, dst: u32, deps: u32, m: u32, memory: ?*const anyopaque, b: u32, buffers: ?*const anyopaque, i: u32, images: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {
        const self = context(buffer);
        const mem: [*]const abi.MemoryBarrier = @ptrCast(@alignCast(memory.?));
        const buf: [*]const abi.BufferMemoryBarrier = @ptrCast(@alignCast(buffers.?));
        if (self.events % 3 != 1 or src != 0x80 or dst != 0x1000 or deps != 1 or m != 1 or b != 1 or i != 1) self.errors += 1;
        if (mem[0].src_access_mask != 0x20 or mem[0].dst_access_mask != 0x40 or buf[0].buffer != 0x1234 or buf[0].size != 4096 or images.?[0].image != 0x5678 or images.?[0].new_layout != 5) self.errors += 1;
        self.events += 1;
        self.checksum +%= buf[0].offset;
    }
};

fn draw(worker: *fifo.Worker, buffer: abi.CommandBuffer, value: u32) void {
    if (worker.trySubmit(.{ .draw = .{ .function = Capture.draw, .command_buffer = buffer, .vertex_count = 3, .instance_count = 1, .first_vertex = value, .first_instance = 0 } }) == .queued) return;
    worker.drain();
    Capture.draw(buffer, 3, 1, value, 0);
}

pub fn main() !void {
    const selected = if (std.c.getenv("ROSETTE_BARRIER_BENCH_CASE")) |v| std.mem.span(v) else "";
    for (0..2) |mode| {
        if (std.mem.eql(u8, selected, "mixed") and mode != 0) continue;
        if (std.mem.eql(u8, selected, "scalar") and mode != 1) continue;
        const worker = try std.heap.page_allocator.create(fifo.Worker);
        defer std.heap.page_allocator.destroy(worker);
        worker.* = .{};
        var capture: Capture align(64) = .{ .scalar = mode == 1 };
        const command: abi.CommandBuffer = @ptrCast(&capture);
        try worker.start();
        const groups: u32 = if (mode == 0) 20000 else 100000;
        // Match steady-state CPU scheduling/frequency before either timing.
        // The preceding mixed paths have very different durations. Isolate
        // the control and warm both sides instead of assuming equal scheduling.
        capture.scalar = true;
        const warm_until = clock.nowNs() + 70_000_000;
        var warm_count: u32 = 0;
        while (clock.nowNs() < warm_until) {
            for (0..32) |_| {
                draw(worker, command, warm_count);
                warm_count += 1;
            }
            worker.drain();
        }
        worker.drain();
        const warm_stats = worker.stats();
        capture = .{ .scalar = mode == 1 };
        const started = clock.nowNs();
        for (0..groups) |index| {
            draw(worker, command, @intCast(index));
            if (mode == 0) {
                var memory = [_]abi.MemoryBarrier{.{ .src_access_mask = 0x20, .dst_access_mask = 0x40 }};
                var buffers = [_]abi.BufferMemoryBarrier{.{ .buffer = 0x1234, .offset = index, .size = 4096 }};
                var images = [_]abi.ImageMemoryBarrier{.{ .image = 0x5678, .new_layout = 5 }};
                if (comptime @hasField(fifo.Job, "pipeline_barrier")) {
                    const snapshot = fifo.barriers.Snapshot.init(Capture.barrier, command, 0x80, 0x1000, 1, &memory, &buffers, &images).?;
                    if (worker.trySubmit(.{ .pipeline_barrier = snapshot }) != .queued) {
                        worker.drain();
                        snapshot.execute();
                    }
                } else {
                    worker.drain();
                    Capture.barrier(command, 0x80, 0x1000, 1, 1, &memory, 1, &buffers, 1, &images);
                }
                // Reuse the producer arrays as soon as the call returns.
                memory[0].src_access_mask = 0;
                buffers[0].buffer = 0;
                images[0].image = 0;
                draw(worker, command, @intCast(index));
            }
            if (index % 32 == 31) worker.drain();
        }
        worker.drain();
        const elapsed = clock.nowNs() - started;
        const stats = worker.stats();
        worker.deinit();
        const multiplier: u64 = if (mode == 0) 3 else 1;
        try std.testing.expectEqual(@as(u64, groups) * multiplier, capture.events);
        try std.testing.expectEqual(@as(u64, 0), capture.errors);
        try std.testing.expectEqual(@as(u64, groups) * (groups - 1) / 2 * multiplier, capture.checksum);
        const barriers = if (@hasField(fifo.Stats, "barrier_snapshots")) stats.barrier_snapshots else 0;
        std.debug.print("barrier_flow case={s} groups={d} callbacks={d} elapsed_ns={d} broadcasts={d} snapshots={d} job_bytes={d} checksum={d} warmup_commands={d}\n", .{ if (mode == 0) "draw-barrier-draw" else "scalar-control", groups, capture.events, elapsed, stats.drain_broadcasts - warm_stats.drain_broadcasts, barriers, @sizeOf(fifo.Job), capture.checksum, warm_count });
    }
}
