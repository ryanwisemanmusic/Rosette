//! Existing five-second / exit report boundary; no per-flush clock.
const std = @import("std");
pub fn report(state: anytype) void {
    const requests = @atomicLoad(u64, &state.windows_stdio_flush_requests, .monotonic);
    if (requests == 0) return;
    const commits = @atomicLoad(u64, &state.windows_stdio_flush_commits, .monotonic);
    const elided = @atomicLoad(u64, &state.windows_stdio_flush_elided, .monotonic);
    std.log.info("PE64 STDIO FLUSH: requests={d} durable_file_sync_attempts={d} unbuffered_file_visits={d}; independent cumulative process counters, not CPU time; explicit commit streams still sync, ordinary write-through streams have no CRT buffer; FlushFileBuffers retains its separate durable path", .{ requests, commits, elided });
}
