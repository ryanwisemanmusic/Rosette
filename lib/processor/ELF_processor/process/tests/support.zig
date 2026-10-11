const std = @import("std");

pub fn sleepForTest(milliseconds: u64) void {
    var request = std.c.timespec{ .sec = 0, .nsec = @intCast(milliseconds * std.time.ns_per_ms) };
    _ = std.c.nanosleep(&request, null);
}
