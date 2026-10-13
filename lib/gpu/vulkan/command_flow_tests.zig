//! CPU-only production FIFO proofs; callbacks never dispatch GPU work.
const std = @import("std");
const abi = @import("abi.zig");
const fifo = @import("async_command_worker.zig");
const clock = @import("transport_timing.zig");

const Capture = struct {
    events: u64 = 0,
    errors: u64 = 0,
    entered: std.atomic.Value(bool) = .init(false),
    released: std.atomic.Value(bool) = .init(false),
    sets: [32]u64 = @splat(0),
    offsets: [64]u32 = @splat(0),
    bytes: [256]u8 = @splat(0),
    zero_offsets: bool = false,
    zero_push: bool = false,

    fn context(buffer: abi.CommandBuffer) *Capture {
        return @ptrCast(@alignCast(buffer.?));
    }
    fn block(buffer: abi.CommandBuffer, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {
        const self = context(buffer);
        self.entered.store(true, .release);
        while (!self.released.load(.acquire)) std.atomic.spinLoopHint();
        self.events += 1;
    }
    fn setsFn(buffer: abi.CommandBuffer, point: u32, layout: u64, first: u32, count: u32, sets: [*]const u64, offset_count: u32, offsets: ?[*]const u32) callconv(.c) void {
        const self = context(buffer);
        if (point != 1 or layout != 0x123 or first != 3) self.errors += 1;
        @memcpy(self.sets[0..count], sets[0..count]);
        if (offsets) |values| @memcpy(self.offsets[0..offset_count], values[0..offset_count]);
        if (offset_count == 0) self.zero_offsets = offsets == null;
        self.events += 1;
    }
    fn pushFn(buffer: abi.CommandBuffer, layout: u64, stages: u32, offset: u32, size: u32, bytes: ?*const anyopaque) callconv(.c) void {
        const self = context(buffer);
        if (layout != 0x123 or stages != 0x20 or offset != 16) self.errors += 1;
        if (bytes) |values| {
            const slice: [*]const u8 = @ptrCast(values);
            @memcpy(self.bytes[0..size], slice[0..size]);
        }
        if (size == 0) self.zero_push = bytes == null;
        self.events += 1;
    }
};

test "FSI command flow owns descriptor and push arrays through delayed execution and reuse" {
    var capture = Capture{};
    var worker = fifo.Worker{};
    try worker.start();
    defer worker.deinit();
    defer capture.released.store(true, .release);
    const buffer: abi.CommandBuffer = @ptrCast(&capture);
    try std.testing.expect(worker.trySubmit(.{ .draw = .{ .function = Capture.block, .command_buffer = buffer, .vertex_count = 3, .instance_count = 1, .first_vertex = 0, .first_instance = 0 } }) == .queued);
    const deadline = clock.nowNs() + 5_000_000_000;
    while (!capture.entered.load(.acquire) and clock.nowNs() < deadline) std.atomic.spinLoopHint();
    try std.testing.expect(capture.entered.load(.acquire));
    var sets: [32]u64 = undefined;
    var offsets: [64]u32 = undefined;
    var bytes: [256]u8 = undefined;
    for (&sets, 0..) |*v, i| v.* = 0x8000 + i;
    for (&offsets, 0..) |*v, i| v.* = @intCast(i * 4);
    for (&bytes, 0..) |*v, i| v.* = @truncate(i);
    const expected_sets = sets;
    const expected_offsets = offsets;
    const expected_bytes = bytes;
    try std.testing.expect(worker.trySubmit(.{ .bind_descriptor_sets = fifo.owned.DescriptorSets.init(Capture.setsFn, buffer, 1, 0x123, 3, &sets, &offsets).? }) == .queued);
    try std.testing.expect(worker.trySubmit(.{ .push_constants = fifo.owned.PushConstants.init(Capture.pushFn, buffer, 0x123, 0x20, 16, &bytes).? }) == .queued);
    // Caller storage is immediately reused while the worker is blocked.
    @memset(&sets, 0xdead);
    @memset(&offsets, 0xdead);
    @memset(&bytes, 0xde);
    capture.released.store(true, .release);
    worker.drain();
    try std.testing.expectEqual(@as(u64, 3), capture.events);
    try std.testing.expectEqual(@as(u64, 0), capture.errors);
    try std.testing.expectEqualDeep(expected_sets, capture.sets);
    try std.testing.expectEqualDeep(expected_offsets, capture.offsets);
    try std.testing.expectEqualDeep(expected_bytes, capture.bytes);
    try std.testing.expect(worker.trySubmit(.{ .bind_descriptor_sets = fifo.owned.DescriptorSets.init(Capture.setsFn, buffer, 1, 0x123, 3, &.{}, &.{}).? }) == .queued);
    try std.testing.expect(worker.trySubmit(.{ .push_constants = fifo.owned.PushConstants.init(Capture.pushFn, buffer, 0x123, 0x20, 16, &.{}).? }) == .queued);
    worker.drain();
    try std.testing.expect(capture.zero_offsets and capture.zero_push);
}

const Flow = struct {
    events: u64 = 0,
    errors: u64 = 0,
    checksum: u64 = 0,
    fn context(buffer: abi.CommandBuffer) *Flow {
        return @ptrCast(@alignCast(buffer.?));
    }
    fn record(self: *Flow, phase: u64, value: u64) void {
        if (self.events % 4 != phase) self.errors += 1;
        self.events += 1;
        self.checksum +%= value;
    }
    fn draw(buffer: abi.CommandBuffer, _: u32, _: u32, first: u32, _: u32) callconv(.c) void {
        const self = context(buffer);
        self.record(if (self.events % 4 == 0) 0 else 3, first);
    }
    fn sets(buffer: abi.CommandBuffer, _: u32, _: u64, _: u32, count: u32, values: [*]const u64, offset_count: u32, offsets: ?[*]const u32) callconv(.c) void {
        const self = context(buffer);
        if (count != 3 or offset_count != 2 or offsets == null) {
            self.errors += 1;
            return;
        }
        self.record(1, values[0] +% values[1] +% values[2] +% offsets.?[0] +% offsets.?[1]);
    }
    fn push(buffer: abi.CommandBuffer, _: u64, _: u32, _: u32, size: u32, data: ?*const anyopaque) callconv(.c) void {
        const self = context(buffer);
        if (size != 16 or data == null) {
            self.errors += 1;
            return;
        }
        const bytes: [*]const u8 = @ptrCast(data.?);
        self.record(2, std.mem.readInt(u32, bytes[0..4], .little));
    }
};

fn submit(worker: *fifo.Worker, job: fifo.Job) void {
    if (worker.trySubmit(job) == .queued) return;
    // The production overflow route drains before its synchronous call.
    worker.drain();
    switch (job) {
        .draw => |v| v.function(v.command_buffer, v.vertex_count, v.instance_count, v.first_vertex, v.first_instance),
        .bind_descriptor_sets => |v| v.execute(),
        .push_constants => |v| v.execute(),
        else => unreachable,
    }
}

test "FSI command flow CPU benchmark compares drained binds with owned FIFO snapshots" {
    const benchmark = if (std.c.getenv("ROSETTE_COMMAND_FLOW_BENCH")) |v| std.mem.eql(u8, std.mem.span(v), "1") else false;
    const iterations: u32 = if (benchmark) 20000 else 512;
    const samples = if (benchmark) @as(usize, 7) else 1;
    for (0..samples) |sample| {
        for (0..2) |position| {
            const queued = (position + sample) % 2 != 0;
            var flow = Flow{};
            var worker = fifo.Worker{};
            try worker.start();
            defer worker.deinit();
            const buffer: abi.CommandBuffer = @ptrCast(&flow);
            const started = clock.nowNs();
            for (0..iterations) |i| {
                const draw = fifo.Job{ .draw = .{ .function = Flow.draw, .command_buffer = buffer, .vertex_count = 3, .instance_count = 1, .first_vertex = @intCast(i), .first_instance = 0 } };
                submit(&worker, draw);
                var values = [_]u64{ i, i + 1, i + 2 };
                var offsets = [_]u32{ @intCast(i * 4), @intCast(i * 8) };
                var bytes: [16]u8 = @splat(0);
                std.mem.writeInt(u32, bytes[0..4], @intCast(i), .little);
                const sets = fifo.owned.DescriptorSets.init(Flow.sets, buffer, 0, 0x123, 0, &values, &offsets).?;
                const push = fifo.owned.PushConstants.init(Flow.push, buffer, 0x123, 0x10, 0, &bytes).?;
                if (queued) {
                    submit(&worker, .{ .bind_descriptor_sets = sets });
                    submit(&worker, .{ .push_constants = push });
                } else {
                    worker.drain();
                    sets.execute();
                    worker.drain();
                    push.execute();
                }
                submit(&worker, draw);
                if (i % 16 == 15) worker.drain(); // continuation boundary
            }
            worker.drain();
            const elapsed = clock.nowNs() - started;
            try std.testing.expectEqual(@as(u64, iterations) * 4, flow.events);
            try std.testing.expectEqual(@as(u64, 0), flow.errors);
            const expected = @as(u64, 18) * iterations * (iterations - 1) / 2 + 3 * iterations;
            try std.testing.expectEqual(expected, flow.checksum);
            if (benchmark) std.debug.print("command_flow sample={d} route={s} iterations={d} ns={d} events={d} checksum={d} batches={d} signals={d} broadcasts={d} saturations={d}; production CPU FIFO with stub callbacks, no GPU or gameplay FPS\n", .{ sample, if (queued) "owned" else "drained", iterations, elapsed, flow.events, flow.checksum, worker.stats().batches, worker.stats().work_signals, worker.stats().drain_broadcasts, worker.stats().saturated_submissions });
        }
    }
}
