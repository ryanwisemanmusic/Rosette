//! Host thread CPU, distinct from guest instruction counts and elapsed waits.
//! One host worker writes its own ledger, at start, five-second progress
//! boundaries and exit. Readers never inspect a foreign live register file.
const std = @import("std");
const builtin = @import("builtin");
const metadata = @import("import_metadata.zig");
const interval = 5 * std.time.ns_per_s;
pub fn current() ?u64 {
    if (builtin.os.tag != .macos and builtin.os.tag != .linux) return null;
    var time: std.c.timespec = undefined;
    if (std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) != 0 or time.sec < 0 or time.nsec < 0) return null;
    return @as(u64, @intCast(time.sec)) *| std.time.ns_per_s +| @as(u64, @intCast(time.nsec));
}
pub const Snapshot = struct { wall_ns: u64, cpu_ns: u64, imports: metadata.Counts = .{} };
pub const Ledger = struct {
    sequence: std.atomic.Value(u64) = .init(0),
    wall_ns: std.atomic.Value(u64) = .init(0),
    cpu_ns: std.atomic.Value(u64) = .init(0),
    imports: [std.meta.fields(metadata.Counts).len]std.atomic.Value(u64) = @splat(.init(0)),
    // Worker-owned clocks. No other executor reads these fields.
    start_wall: u64 = 0,
    start_cpu: ?u64 = null,
    last_wall: u64 = 0,
    pub fn begin(self: *@This(), now: u64) void {
        metadata.reset();
        self.start_wall = now;
        self.last_wall = now;
        self.start_cpu = current();
    }
    pub fn publish(self: *@This(), snapshot: Snapshot) void {
        // Seq-cst publication gives readers one coherent pair. This happens
        // once per five seconds, not on instruction or draw hot paths.
        _ = self.sequence.fetchAdd(1, .seq_cst);
        self.wall_ns.store(snapshot.wall_ns, .seq_cst);
        self.cpu_ns.store(snapshot.cpu_ns, .seq_cst);
        inline for (std.meta.fields(metadata.Counts), 0..) |field, i| self.imports[i].store(@field(snapshot.imports, field.name), .seq_cst);
        _ = self.sequence.fetchAdd(1, .seq_cst);
    }
    pub fn read(self: *const @This()) ?Snapshot {
        for (0..8) |_| {
            const first = self.sequence.load(.seq_cst);
            if (first == 0 or first & 1 != 0) continue;
            var snapshot: Snapshot = .{ .wall_ns = self.wall_ns.load(.seq_cst), .cpu_ns = self.cpu_ns.load(.seq_cst) };
            inline for (std.meta.fields(metadata.Counts), 0..) |field, i| @field(snapshot.imports, field.name) = self.imports[i].load(.seq_cst);
            if (first == self.sequence.load(.seq_cst)) return snapshot;
        }
        return null;
    }
    pub fn observe(self: *@This(), now: u64, cpu: ?u64) bool {
        const before = self.start_cpu orelse return false;
        const after = cpu orelse return false;
        if (now < self.start_wall or after < before) return false;
        self.publish(.{ .wall_ns = now - self.start_wall, .cpu_ns = after - before, .imports = metadata.snapshot() });
        self.last_wall = now;
        return true;
    }
    pub fn poll(self: *@This(), now: u64) void {
        if (now >= self.last_wall and now - self.last_wall < interval) return;
        _ = self.observe(now, current());
    }
    pub fn finish(self: *@This(), now: u64) void {
        _ = self.observe(now, current());
    }
    pub fn report(self: *const @This(), slot: usize, handle: u64, name: []const u8) void {
        const s = self.read() orelse return;
        std.log.info("PE64 WORKER HOST CPU: slot={d} handle=0x{x} name='{s}' cpu_us={d} elapsed_us={d} sampled_at_lifetime_us={d}; THREAD_CPUTIME_ID includes this host worker's compute and kernel CPU, excludes parked/off-core time; elapsed includes waits; worker sums overlap and are not frame critical-path fractions", .{ slot, handle, name, s.cpu_ns / 1000, s.wall_ns / 1000, s.wall_ns / 1000 });
        if (s.imports.stub_lookups != 0 or s.imports.callsites != 0) std.log.info("PE64 IMPORT METADATA: slot={d} name='{s}' stub_lookups={d} stub_hits={d} stub_scanned={d} dynamic_entries_peak={d} callsites={d} callsite_hits={d} callsite_rebuilds={d} callsite_fallbacks={d}; worker-owned counts published with host CPU; identities and code bytes rechecked, targets remain live; not saved CPU milliseconds", .{ slot, name, s.imports.stub_lookups, s.imports.stub_hits, s.imports.stub_scanned, s.imports.dynamic_entries_peak, s.imports.callsites, s.imports.callsite_hits, s.imports.callsite_rebuilds, s.imports.callsite_fallbacks });
    }
};

test "worker host CPU ledger distinguishes busy CPU from parked elapsed time" {
    const t = std.testing;
    const start = current() orelse return error.SkipZigTest;
    var ledger: Ledger = .{};
    ledger.start_wall = 100;
    ledger.start_cpu = start;
    var pause: std.c.timespec = .{ .sec = 0, .nsec = 20_000_000 };
    _ = std.c.nanosleep(&pause, null);
    const after = current().?;
    try t.expect(ledger.observe(20_000_100, after));
    const row = ledger.read().?;
    try t.expectEqual(@as(u64, 20_000_000), row.wall_ns);
    try t.expect(row.cpu_ns < row.wall_ns / 2);
    try t.expect(!ledger.observe(99, after));
    try t.expect(!ledger.observe(21_000_100, null));
    try t.expectEqual(row, ledger.read().?);
    var unknown: Ledger = .{};
    try t.expect(!unknown.observe(100, after));
    try t.expect(unknown.read() == null);
}

test "worker host CPU concurrent publication keeps elapsed and CPU coherent" {
    const Writer = struct {
        fn run(ledger: *Ledger, done: *std.atomic.Value(bool)) void {
            for (1..10_001) |n| ledger.publish(.{ .wall_ns = n * 2, .cpu_ns = n, .imports = .{ .stub_lookups = n * 3, .callsite_hits = n * 5 } });
            done.store(true, .release);
        }
    };
    var ledger: Ledger = .{};
    var done: std.atomic.Value(bool) = .init(false);
    const thread = try std.Thread.spawn(.{}, Writer.run, .{ &ledger, &done });
    defer thread.join();
    while (!done.load(.acquire)) if (ledger.read()) |row| {
        try std.testing.expectEqual(row.cpu_ns * 2, row.wall_ns);
        try std.testing.expectEqual(row.cpu_ns * 3, row.imports.stub_lookups);
        try std.testing.expectEqual(row.cpu_ns * 5, row.imports.callsite_hits);
    };
    const row = ledger.read().?;
    try std.testing.expectEqual(@as(u64, 20_000), row.wall_ns);
    try std.testing.expectEqual(@as(u64, 10_000), row.cpu_ns);
}
