//! Own-worker snapshots at the existing progress-publication boundary. Avoid
//! walking another worker's live cache or depending on the UI owner's exit.
const std = @import("std");
const decode = @import("x64_decoder");
const interval_ns = 5 * std.time.ns_per_s;

pub const Snapshot = struct { retired: u64 = 0, fallbacks: u64 = 0, unpack: u64 = 0, native_hops: u64 = 0 };
pub const Row = struct { elapsed_ns: u64, retired: u64, fallbacks: u64, unpack: u64, native_hops: u64 };
pub const Pulse = struct {
    last_ns: u64 = 0,
    last: Snapshot = .{},

    pub fn observe(self: *Pulse, now: u64, current: Snapshot) ?Row {
        if (self.last_ns == 0 or now < self.last_ns or current.retired < self.last.retired) {
            self.last_ns = now;
            self.last = current;
            return null;
        }
        if (now - self.last_ns < interval_ns) return null;
        const row: Row = .{ .elapsed_ns = now - self.last_ns, .retired = current.retired - self.last.retired, .fallbacks = current.fallbacks -| self.last.fallbacks, .unpack = current.unpack -| self.last.unpack, .native_hops = current.native_hops -| self.last.native_hops };
        self.last_ns = now;
        self.last = current;
        return row;
    }

    pub fn poll(self: *Pulse, now: u64, slot: usize, cache: anytype, math: anytype) void {
        if (self.last_ns != 0 and now >= self.last_ns and now - self.last_ns < interval_ns) return;
        const jit = cache orelse return;
        const snapshot: Snapshot = .{ .retired = jit.instructions_retired, .fallbacks = jit.fallback_calls, .unpack = jit.fallback_ops[@intFromEnum(decode.Op.vunpcklpd)], .native_hops = jit.native_chain_hops };
        const row = self.observe(now, snapshot) orelse return;
        const rate: u64 = @intCast(@as(u128, row.retired) * std.time.ns_per_s / row.elapsed_ns);
        std.log.info("PE64 WORKER RUNTIME PULSE: slot={d} elapsed_ms={d} native_retired={d} native_instructions_per_second={d} fallbacks={d} vunpcklpd_fallbacks={d} native_hops={d} code_mib={d} exp2_total={d} exp2f_total={d}; own-worker snapshot; wall interval includes waits/spins, not frame critical-path timing", .{
            slot, row.elapsed_ns / std.time.ns_per_ms, row.retired, rate, row.fallbacks, row.unpack, row.native_hops, jit.memory.used / (1024 * 1024), math.calls[0].load(.acquire), math.calls[1].load(.acquire),
        });
        @import("xenia_register_writes.zig").pulse(now);
    }
};

test "worker runtime pulse deltas are bounded and reset safely without exit reporting" {
    var pulse: Pulse = .{};
    try std.testing.expect(pulse.observe(1, .{ .retired = 100, .fallbacks = 5 }) == null);
    try std.testing.expect(pulse.observe(interval_ns, .{ .retired = 120, .fallbacks = 6 }) == null);
    const row = pulse.observe(interval_ns + 1, .{ .retired = 150, .fallbacks = 8, .unpack = 2 }).?;
    try std.testing.expectEqual(interval_ns, row.elapsed_ns);
    try std.testing.expectEqual(@as(u64, 50), row.retired);
    try std.testing.expectEqual(@as(u64, 3), row.fallbacks);
    try std.testing.expectEqual(@as(u64, 2), row.unpack);
    try std.testing.expect(pulse.observe(2 * interval_ns + 1, .{ .retired = 10 }) == null);
    try std.testing.expect(pulse.observe(1, .{ .retired = 20 }) == null);
    try std.testing.expectEqual(@as(u64, 20), pulse.last.retired);
}
