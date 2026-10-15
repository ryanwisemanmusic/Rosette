//! Time only the existing native create call, inside the released-lock scope.
//! Slow-call reports distinguish caller CPU from elapsed compile/driver waits.
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("gpu").vulkan.abi;
pub const Cost = struct { cpu_ns: u64, elapsed_ns: u64 };
pub const Stamp = struct {
    cpu: u64,
    wall: u64,
    fn clock(id: std.c.clockid_t) ?u64 {
        if (builtin.os.tag != .macos and builtin.os.tag != .linux) return null;
        var value: std.c.timespec = undefined;
        if (std.c.clock_gettime(id, &value) != 0 or value.sec < 0 or value.nsec < 0) return null;
        return @as(u64, @intCast(value.sec)) *| std.time.ns_per_s +| @as(u64, @intCast(value.nsec));
    }
    pub fn begin() ?Stamp {
        return .{ .cpu = clock(.THREAD_CPUTIME_ID) orelse return null, .wall = clock(.MONOTONIC) orelse return null };
    }
    pub fn finish(start: Stamp) ?Cost {
        const end = begin() orelse return null;
        if (end.cpu < start.cpu or end.wall < start.wall) return null;
        return .{ .cpu_ns = end.cpu - start.cpu, .elapsed_ns = end.wall - start.wall };
    }
};
fn report(comptime kind: []const u8, stamp: ?Stamp, result: abi.Result) void {
    const start = stamp orelse return;
    const cost = start.finish() orelse return;
    if (cost.elapsed_ns < 50 * std.time.ns_per_ms) return;
    std.log.info("VULKAN PIPELINE NATIVE CALL: scope={s} host_thread={d} calls=1 max_native_elapsed_ns={d} max_native_cpu_ns={d} result={d} threshold_ms=50; one reported slow native create call, not a cumulative total; marshal and runtime-lock reacquisition excluded; clocks included, other compiler threads and GPU execution unmeasured", .{ kind, std.Thread.getCurrentId(), cost.elapsed_ns, cost.cpu_ns, result });
}
pub const Graphics = struct {
    function: abi.PfnCreateGraphicsPipelines,
    device: abi.Device,
    cache: abi.PipelineCache,
    info: *const abi.GraphicsPipelineCreateInfo,
    output: *u64,
    pub fn invoke(call: @This()) abi.Result {
        const start = Stamp.begin();
        const result = call.function(call.device, call.cache, 1, @ptrCast(call.info), null, @ptrCast(call.output));
        report("graphics", start, result);
        return result;
    }
};
pub const Compute = struct {
    function: abi.PfnCreateComputePipelines,
    device: abi.Device,
    cache: abi.PipelineCache,
    info: *const abi.ComputePipelineCreateInfo,
    output: *u64,
    pub fn invoke(call: @This()) abi.Result {
        const start = Stamp.begin();
        const result = call.function(call.device, call.cache, 1, @ptrCast(call.info), null, @ptrCast(call.output));
        report("compute", start, result);
        return result;
    }
};
test "FSI pipeline native timing keeps real call arguments output and failure result" {
    const Stub = struct {
        fn create(device: abi.Device, cache: abi.PipelineCache, count: u32, _: [*]const abi.GraphicsPipelineCreateInfo, allocator: ?*const anyopaque, output: [*]u64) callconv(.c) abi.Result {
            std.debug.assert(@intFromPtr(device.?) == 0x123 and cache == 77 and count == 1 and allocator == null);
            output[0] = 0x9876;
            return abi.ERROR_INITIALIZATION_FAILED;
        }
    };
    var output: u64 = 0;
    var info: abi.GraphicsPipelineCreateInfo = std.mem.zeroes(abi.GraphicsPipelineCreateInfo);
    const result = (Graphics{ .function = Stub.create, .device = @ptrFromInt(0x123), .cache = 77, .info = &info, .output = &output }).invoke();
    try std.testing.expectEqual(abi.ERROR_INITIALIZATION_FAILED, result);
    try std.testing.expectEqual(@as(u64, 0x9876), output);
    const start = Stamp.begin() orelse return error.SkipZigTest;
    var pause: std.c.timespec = .{ .sec = 0, .nsec = 20_000_000 };
    _ = std.c.nanosleep(&pause, null);
    const cost = start.finish().?;
    try std.testing.expect(cost.cpu_ns < cost.elapsed_ns / 2);
}
