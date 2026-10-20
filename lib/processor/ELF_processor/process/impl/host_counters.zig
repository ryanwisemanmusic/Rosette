//! The calling thread's own ARM64 instructions retired and cycles, from the
//! kernel's fixed performance counters (`thread_selfcounts`, no privilege).
//!
//! Against the x86 instructions a worker retired in the same window they give
//! how many host instructions one guest instruction costs and how many of
//! them retire per cycle. A low IPC says the translated code waits (fetch,
//! data, TLB); a high one says it is simply long, so the remaining lever is
//! emitting fewer instructions. Only the thread itself can read its counters,
//! so the pulse takes them at its own publication boundary.
const std = @import("std");
const builtin = @import("builtin");

pub const Counts = struct { instructions: u64 = 0, cycles: u64 = 0 };

extern "c" fn thread_selfcounts(kind: c_int, buffer: *[2]u64, bytes: usize) c_int;

/// Zero on a host without the counters (or when the kernel refuses them),
/// so a reader reports "unknown" rather than a ratio of garbage.
pub fn read() Counts {
    if (comptime !(builtin.os.tag.isDarwin() and builtin.cpu.arch == .aarch64)) return .{};
    var values: [2]u64 = .{ 0, 0 };
    if (thread_selfcounts(1, &values, @sizeOf([2]u64)) != 0) return .{};
    return .{ .instructions = values[0], .cycles = values[1] };
}

/// Host instructions per guest instruction and per cycle, in hundredths, or
/// zero when either side is unknown.
pub fn ratios(delta: Counts, guest_retired: u64) struct { per_guest_x100: u64, ipc_x100: u64 } {
    return .{
        .per_guest_x100 = if (guest_retired == 0 or delta.instructions == 0) 0 else @intCast(@as(u128, delta.instructions) * 100 / guest_retired),
        .ipc_x100 = if (delta.cycles == 0) 0 else @intCast(@as(u128, delta.instructions) * 100 / delta.cycles),
    };
}

test "host counters advance on this thread and give a plausible IPC" {
    const before = read();
    if (before.instructions == 0) return error.SkipZigTest;
    var sink: u64 = 0;
    for (0..1_000_000) |i| sink +%= i *% 3;
    std.mem.doNotOptimizeAway(sink);
    const after = read();
    const delta: Counts = .{ .instructions = after.instructions - before.instructions, .cycles = after.cycles - before.cycles };
    try std.testing.expect(delta.instructions > 1_000_000);
    const r = ratios(delta, 1_000_000);
    try std.testing.expect(r.per_guest_x100 >= 100);
    try std.testing.expect(r.ipc_x100 > 10 and r.ipc_x100 < 1200);
    try std.testing.expectEqual(@as(u64, 0), ratios(.{}, 5).per_guest_x100);
    try std.testing.expectEqual(@as(u64, 0), ratios(delta, 0).per_guest_x100);
}
