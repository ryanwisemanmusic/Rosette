//! Read-only witnesses of Xenia's own Xbox time, distinct from Rosette's
//! Windows performance counter. Nothing here advances a clock or wakes work.
const std = @import("std");
pub const Symbols = struct {
    frequency: ?u64 = null,
    guest_ticks: ?u64 = null,
    host_ticks: ?u64 = null,
    ratio: ?u64 = null,
    scalar: ?u64 = null,
    no_scaling: ?u64 = null,
    raw_source: ?u64 = null,
    pub fn discover(resolver: anytype) Symbols {
        return .{
            .frequency = resolve(resolver, "_ZN2xe21guest_tick_frequency_E"),
            .guest_ticks = resolve(resolver, "_ZN2xe22last_guest_tick_count_E"),
            .host_ticks = resolve(resolver, "_ZN2xe21last_host_tick_count_E"),
            .ratio = resolve(resolver, "_ZN2xe17guest_tick_ratio_E"),
            .scalar = resolve(resolver, "_ZN2xe18guest_time_scalar_E"),
            .no_scaling = resolve(resolver, "_ZN5cvars16clock_no_scalingE"),
            .raw_source = resolve(resolver, "_ZN5cvars16clock_source_rawE"),
        };
    }
};
fn resolve(resolver: anytype, name: []const u8) ?u64 {
    const address_of = resolver.address_of orelse return null;
    return address_of(resolver.context, name);
}
pub const Snapshot = struct {
    frequency: u64,
    guest_ticks: u64,
    host_ticks: u64,
    ratio_num: u64,
    ratio_den: u64,
    scalar: f64,
    no_scaling: bool = false,
    raw_source: bool = false,
    pub fn read(state: anytype, symbols: Symbols) ?Snapshot {
        const frequency = readWord(state, symbols.frequency) orelse return null;
        const guest_ticks = readWord(state, symbols.guest_ticks) orelse return null;
        const host_ticks = readWord(state, symbols.host_ticks) orelse return null;
        const ratio = symbols.ratio orelse return null;
        return .{
            .frequency = frequency,
            .guest_ticks = guest_ticks,
            .host_ticks = host_ticks,
            .ratio_num = readWord(state, ratio) orelse return null,
            .ratio_den = readWord(state, std.math.add(u64, ratio, 8) catch return null) orelse return null,
            .scalar = @bitCast(readWord(state, symbols.scalar) orelse return null),
            .no_scaling = readFlag(state, symbols.no_scaling) orelse return null,
            .raw_source = readFlag(state, symbols.raw_source) orelse return null,
        };
    }
};
fn readWord(state: anytype, address: ?u64) ?u64 {
    const bytes = state.guestMemoryConst(address orelse return null, 8) orelse return null;
    return std.mem.readInt(u64, bytes[0..8], .little);
}
fn readFlag(state: anytype, address: ?u64) ?bool {
    const bytes = state.guestMemoryConst(address orelse return null, 1) orelse return null;
    // C++ bool is one byte in this image. An unreadable/invalid mode must
    // not be mistaken for the default scaling/source setting.
    return switch (bytes[0]) {
        0 => false,
        1 => true,
        else => null,
    };
}
pub const Observation = struct {
    status: enum { baseline, advancing, stalled, discontinuity, uninitialized, bypassed },
    host_ms: u64 = 0,
    guest_ms: u64 = 0,
    host_tick_delta: u64 = 0,
    speed_permille: u64 = 0,
};
pub const Probe = struct {
    symbols: Symbols = .{},
    previous: ?Snapshot = null,
    previous_ns: u64 = 0,
    pub fn observe(self: *Probe, snapshot: Snapshot, now: u64) Observation {
        defer {
            self.previous = snapshot;
            self.previous_ns = now;
        }
        if (snapshot.no_scaling) return .{ .status = .bypassed };
        if (snapshot.frequency == 0 or snapshot.ratio_den == 0 or snapshot.ratio_num == 0 or
            !std.math.isFinite(snapshot.scalar) or snapshot.scalar <= 0) return .{ .status = .uninitialized };
        const old = self.previous orelse return .{ .status = .baseline };
        if (now <= self.previous_ns or old.frequency != snapshot.frequency or old.no_scaling or old.raw_source != snapshot.raw_source or
            old.ratio_num != snapshot.ratio_num or old.ratio_den != snapshot.ratio_den or old.scalar != snapshot.scalar or
            snapshot.guest_ticks < old.guest_ticks or snapshot.host_ticks < old.host_ticks) return .{ .status = .discontinuity };
        const delta = snapshot.guest_ticks - old.guest_ticks;
        const host_ns = now - self.previous_ns;
        return .{
            .status = if (delta == 0) .stalled else .advancing,
            .host_ms = host_ns / 1_000_000,
            .guest_ms = @intCast(@min(@as(u128, std.math.maxInt(u64)), @as(u128, delta) * 1000 / snapshot.frequency)),
            .host_tick_delta = snapshot.host_ticks - old.host_ticks,
            .speed_permille = @intCast(@min(@as(u128, std.math.maxInt(u64)), @as(u128, delta) * 1_000_000_000_000 / snapshot.frequency / host_ns)),
        };
    }
};

test "Xenia clock probe distinguishes Xbox-time stalls from a healthy Windows clock" {
    var probe: Probe = .{};
    var snapshot: Snapshot = .{ .frequency = 50_000_000, .guest_ticks = 1, .host_ticks = 10, .ratio_num = 50, .ratio_den = 1, .scalar = 1 };
    try std.testing.expectEqual(.baseline, probe.observe(snapshot, 1).status);
    snapshot.guest_ticks += 50_000_000;
    snapshot.host_ticks += 1_000_000;
    const moving = probe.observe(snapshot, 1_000_000_001);
    try std.testing.expectEqual(.advancing, moving.status);
    try std.testing.expectEqual(@as(u64, 1000), moving.guest_ms);
    try std.testing.expectEqual(@as(u64, 1000), moving.speed_permille);
    try std.testing.expectEqual(.stalled, probe.observe(snapshot, 2_000_000_001).status);
    snapshot.guest_ticks = 0;
    try std.testing.expectEqual(.discontinuity, probe.observe(snapshot, 3_000_000_001).status);
    snapshot.no_scaling = true;
    try std.testing.expectEqual(.bypassed, probe.observe(snapshot, 4_000_000_001).status);
    snapshot.no_scaling = false;
    snapshot.ratio_den = 0;
    try std.testing.expectEqual(.uninitialized, probe.observe(snapshot, 5_000_000_001).status);
}
