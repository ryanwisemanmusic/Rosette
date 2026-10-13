//! Scalar FIFO control: measures the cost of enlarging the owned job union.
//! Compile against both saved worker versions; no graphics API is called.
const std = @import("std");
const fifo = @import("worker");
const abi = fifo.Draw;
fn now() u64 {
    var value: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &value) != 0) unreachable;
    return @as(u64, @intCast(value.sec)) * 1_000_000_000 + @as(u64, @intCast(value.nsec));
}
var checksum: u64 = 0;
fn draw(_: @FieldType(abi, "command_buffer"), _: u32, _: u32, value: u32, _: u32) callconv(.c) void {
    checksum +%= value;
}
pub fn main() !void {
    var worker = fifo.Worker{};
    try worker.start();
    defer worker.deinit();
    const started = now();
    const count: u32 = 100000;
    for (0..count) |i| {
        const job = fifo.Job{ .draw = .{ .function = draw, .command_buffer = null, .vertex_count = 3, .instance_count = 1, .first_vertex = @intCast(i), .first_instance = 0 } };
        if (worker.trySubmit(job) != .queued) {
            worker.drain();
            draw(null, 3, 1, @intCast(i), 0);
        }
        if (i % 64 == 63) worker.drain();
    }
    worker.drain();
    if (checksum != @as(u64, count) * (count - 1) / 2) return error.WrongOrderOrMissingDraw;
    std.debug.print("scalar_fifo ns={d} commands={d} checksum={d} job_bytes={d}\n", .{ now() - started, count, checksum, @sizeOf(fifo.Job) });
}
