const std = @import("std");
const abi = @import("abi.zig");
const fifo = @import("async_command_worker.zig");

const Capture = struct {
    events: u32 = 0,
    errors: u32 = 0,
    fn context(buffer: abi.CommandBuffer) *Capture {
        return @ptrCast(@alignCast(buffer.?));
    }
    fn draw(buffer: abi.CommandBuffer, _: u32, _: u32, first: u32, _: u32) callconv(.c) void {
        const self = context(buffer);
        if (self.events % 2 != 0 or first != self.events / 2) self.errors += 1;
        self.events += 1;
    }
    fn barrier(buffer: abi.CommandBuffer, source: u32, dest: u32, deps: u32, m: u32, memory: ?*const anyopaque, b: u32, buffers: ?*const anyopaque, i: u32, images: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {
        const self = context(buffer);
        if (self.events % 2 != 1 or source != 0x80 or dest != 0x1000 or deps != 1) self.errors += 1;
        const group = self.events / 2;
        if (group % 2 == 0) {
            const mem: [*]const abi.MemoryBarrier = @ptrCast(@alignCast(memory.?));
            const buf: [*]const abi.BufferMemoryBarrier = @ptrCast(@alignCast(buffers.?));
            if (m != 2 or b != 4 or i != 2 or mem[1].src_access_mask != group or buf[3].offset != group or images.?[1].image != group + 1) self.errors += 1;
        } else if (m != 0 or b != 0 or i != 0 or memory != null or buffers != null or images != null) self.errors += 1;
        self.events += 1;
    }
};

test "FSI barrier FIFO owns maximum and empty snapshots across wrap, batch relocation and saturation" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(fifo.Worker, "mutex"));
    try std.testing.expect(@alignOf(fifo.Worker) >= std.atomic.cache_line);
    var worker = fifo.Worker{};
    try worker.start();
    defer worker.deinit();
    var capture = Capture{};
    const command: abi.CommandBuffer = @ptrCast(&capture);
    for (0..2000) |group| {
        if (worker.trySubmit(.{ .draw = .{ .function = Capture.draw, .command_buffer = command, .vertex_count = 3, .instance_count = 1, .first_vertex = @intCast(group), .first_instance = 0 } }) != .queued) {
            worker.drain();
            Capture.draw(command, 3, 1, @intCast(group), 0);
        }
        var memory: [2]abi.MemoryBarrier = @splat(.{ .src_access_mask = @intCast(group) });
        var buffers: [4]abi.BufferMemoryBarrier = @splat(.{ .offset = group });
        var images: [2]abi.ImageMemoryBarrier = @splat(.{ .image = group + 1 });
        const even = group % 2 == 0;
        const snapshot = fifo.barriers.Snapshot.init(Capture.barrier, command, 0x80, 0x1000, 1, if (even) &memory else &.{}, if (even) &buffers else &.{}, if (even) &images else &.{}).?;
        if (worker.trySubmit(.{ .pipeline_barrier = snapshot }) != .queued) {
            worker.drain();
            snapshot.execute();
        }
        // Every caller array is overwritten before the next iteration.
        @memset(std.mem.asBytes(&memory), 0xff);
        @memset(std.mem.asBytes(&buffers), 0xff);
        @memset(std.mem.asBytes(&images), 0xff);
    }
    worker.drain();
    try std.testing.expectEqual(@as(u32, 4000), capture.events);
    try std.testing.expectEqual(@as(u32, 0), capture.errors);
    try std.testing.expect(worker.stats().barrier_snapshots > 0);
}
