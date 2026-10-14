//! Per-module host stages; none of these values are GPU execution times.
const std = @import("std");
pub const Stage = enum { marshal, inspect, guest_evidence, hdr, rectangle, pixel, robust, driver, native_evidence, other };
const size = @typeInfo(Stage).@"enum".fields.len;
pub fn now() u64 {
    var t: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &t) != 0) return 0;
    return @as(u64, @intCast(t.sec)) * std.time.ns_per_s + @as(u64, @intCast(t.nsec));
}
pub const Call = struct {
    last: u64,
    elapsed: [size]u64 = @splat(0),
    pub fn start() Call {
        return .{ .last = now() };
    }
    pub fn mark(self: *Call, stage: Stage) void {
        const end = now();
        self.elapsed[@intFromEnum(stage)] +|= end -| self.last;
        self.last = end;
    }
};
pub const Stats = struct {
    calls: u64 = 0,
    total: [size]u64 = @splat(0),
    maximum: [size]u64 = @splat(0),
    pub fn add(self: *Stats, call: Call) void {
        self.calls +|= 1;
        for (&self.total, &self.maximum, call.elapsed) |*sum, *peak, ns| {
            sum.* +|= ns;
            peak.* = @max(peak.*, ns);
        }
    }
    pub fn report(self: *const Stats) void {
        inline for (@typeInfo(Stage).@"enum".fields, 0..) |field, i| std.log.info("VULKAN SHADER HOST STAGE: stage={s} calls={d} total_us={d} max_us={d}; owned module host work; stage times include scheduling, not GPU utilization", .{ field.name, self.calls, self.total[i] / 1000, self.maximum[i] / 1000 });
    }
};
