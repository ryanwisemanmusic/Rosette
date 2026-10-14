//! Complete host retirement of a guest FSI recording. Buffer custody is
//! released to its last submit serial; this never destroys in-flight work.
const std = @import("std");
fn now() u64 {
    var t: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &t) != 0) return 0;
    return @as(u64, @intCast(t.sec)) * std.time.ns_per_s + @as(u64, @intCast(t.nsec));
}
pub fn release(pool: anytype, recording: anytype) void {
    const start = now();
    const chunks = recording.chunk_count;
    for (recording.chunks[0..chunks]) |chunk| pool.release(chunk);
    recording.* = .{};
    if (comptime @hasField(@typeInfo(@TypeOf(pool)).pointer.child, "work")) {
        const elapsed = now() -| start;
        pool.work.recording_releases +|= 1;
        pool.work.recording_chunks +|= chunks;
        pool.work.recording_host_ns +|= elapsed;
        pool.work.recording_max_host_ns = @max(pool.work.recording_max_host_ns, elapsed);
    }
}
