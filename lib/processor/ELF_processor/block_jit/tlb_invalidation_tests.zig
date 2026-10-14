//! Old/new TLB oracle and CPU-only invalidation/fill comparisons.
const std = @import("std");
const New = @import("tlb.zig").Tlb;
const Old = @import("tlb_reference.zig").Tlb;
fn compare(old: *Old, new: *New) !void {
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&old.read), std.mem.sliceAsBytes(&new.read));
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&old.write), std.mem.sliceAsBytes(&new.write));
}
test "TLB region filter preserves every old tag and delta across random fills and invalidations" {
    const old = try std.testing.allocator.create(Old);
    defer std.testing.allocator.destroy(old);
    const new = try std.testing.allocator.create(New);
    defer std.testing.allocator.destroy(new);
    old.* = Old.empty;
    new.* = New.empty;
    var page: [4096]u8 align(4096) = undefined;
    var generator = std.Random.DefaultPrng.init(0x918246);
    const random = generator.random();
    const bases = [_]u64{ 0, 0xA0000000, 0x140000000, 0x1_0000_0000, 0xFFFF000000000000, std.math.maxInt(u64) - 0xFFFFFF };
    for (0..512) |step| {
        const base = bases[random.uintLessThan(usize, bases.len)];
        const address = (base +| random.uintLessThan(u64, 0x1000000)) & ~@as(u64, 4095);
        const write = random.boolean();
        old.fillOrdered(write, address, &page);
        new.fillOrdered(write, address, &page);
        const length = ([_]u64{ 0, 1, 4096, 511 * 4096, 1023 * 4096, 1024 * 4096, std.math.maxInt(u64) })[random.uintLessThan(usize, 7)];
        const reads = random.boolean();
        const writes = random.boolean();
        const start = if (step % 3 == 0) address else bases[random.uintLessThan(usize, bases.len)];
        old.invalidateRangeOrderedTables(start, length, reads, writes);
        new.invalidateRangeOrderedTables(start, length, reads, writes);
        try compare(old, new);
    }
    // Probe layout remains identical; metadata is appended after both arrays.
    try std.testing.expectEqual(@offsetOf(Old, "read"), @offsetOf(New, "read"));
    try std.testing.expectEqual(@offsetOf(Old, "write"), @offsetOf(New, "write"));
    try std.testing.expectEqual(@sizeOf(Old.Entry), @sizeOf(New.Entry));
}
test "TLB region filter retains collisions and reset history while skipping absent directions" {
    const tlb = try std.testing.allocator.create(New);
    defer std.testing.allocator.destroy(tlb);
    tlb.* = New.empty;
    var page: [4096]u8 align(4096) = undefined;
    tlb.fillOrdered(false, 0x140000000, &page);
    const delta = tlb.read[New.index(0x140000000 >> 12)].delta;
    const miss = tlb.invalidateRangeOrderedMeasured(0xA0000000, 511 * 4096, true, true);
    try std.testing.expectEqual(@as(u64, 0), miss.slots);
    try std.testing.expectEqual(@as(u64, 2), miss.skipped_directions);
    try std.testing.expect(tlb.lookup(false, 0x140000010) != null);
    const hit = tlb.invalidateRangeOrderedMeasured(0x140000000, 4096, true, true);
    try std.testing.expectEqual(@as(u64, 1), hit.slots);
    try std.testing.expect(tlb.lookup(false, 0x140000010) == null);
    try std.testing.expectEqual(delta, tlb.read[New.index(0x140000000 >> 12)].delta);
    tlb.flushOrdered(true, true);
    const stale = tlb.invalidateRangeOrderedMeasured(0x140000000, 4096, true, false);
    try std.testing.expectEqual(@as(u64, 1), stale.slots); // Stale bits only cost a scan.
    tlb.fillOrdered(false, 0x140000000, &page);
    tlb.invalidateRangeOrdered(0x140000000, 1);
    try std.testing.expect(tlb.lookup(false, 0x140000000) == null);
}
test "TLB region filter preserves raced-fill epoch retirement before and after summary publication" {
    const tlb = try std.testing.allocator.create(New);
    defer std.testing.allocator.destroy(tlb);
    var page: [4096]u8 align(4096) = undefined;
    for (0..3) |phase| {
        tlb.* = New.empty;
        var epoch: std.atomic.Value(u64) = .init(0);
        const observed = epoch.load(.seq_cst);
        if (phase == 0) tlb.fillOrdered(true, 0xA0000000, &page);
        if (phase == 1) tlb.membership.note(true, 0xA0000000 >> 12, true);
        _ = epoch.fetchAdd(1, .seq_cst);
        tlb.invalidateRangeOrdered(0xA0000000, 4096);
        if (phase != 0) tlb.fillOrdered(true, 0xA0000000, &page);
        if (epoch.load(.seq_cst) != observed) tlb.retireOrdered(true, 0xA0000000);
        try std.testing.expect(tlb.lookup(true, 0xA0000000) == null);
    }
}
test "TLB region filter publication and raced-fill rechecks survive concurrent invalidators" {
    const Shared = struct {
        tlb: *New,
        epoch: std.atomic.Value(u64) = .init(0),
        stop: std.atomic.Value(bool) = .init(false),
        fills: std.atomic.Value(u64) = .init(0),
        raced: std.atomic.Value(u64) = .init(0),
        ready: std.atomic.Value(bool) = .init(false),
        page: [4096]u8 align(4096) = undefined,
        fn writer(self: *@This()) void {
            while (!self.stop.load(.acquire)) {
                const seen = self.epoch.load(.seq_cst);
                self.tlb.fillOrdered(true, 0xA0000000, &self.page);
                if (self.epoch.load(.seq_cst) != seen) {
                    self.tlb.retireOrdered(true, 0xA0000000);
                    _ = self.raced.fetchAdd(1, .monotonic);
                }
                _ = self.fills.fetchAdd(1, .monotonic);
                self.ready.store(true, .release);
            }
        }
    };
    const tlb = try std.testing.allocator.create(New);
    defer std.testing.allocator.destroy(tlb);
    tlb.* = New.empty;
    var shared: Shared = .{ .tlb = tlb };
    const writer = try std.Thread.spawn(.{}, Shared.writer, .{&shared});
    while (!shared.ready.load(.acquire)) std.Thread.yield() catch {};
    for (0..20000) |_| {
        _ = shared.epoch.fetchAdd(1, .seq_cst);
        tlb.invalidateRangeOrdered(0xA0000000, 4096);
    }
    shared.stop.store(true, .release);
    writer.join();
    tlb.invalidateRangeOrdered(0xA0000000, 4096);
    try std.testing.expect(shared.fills.load(.acquire) > 0);
    try std.testing.expect(tlb.lookup(true, 0xA0000000) == null);
}

fn now() u64 {
    var t: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.MONOTONIC, &t) == 0);
    return @as(u64, @intCast(t.sec)) * std.time.ns_per_s + @as(u64, @intCast(t.nsec));
}
const Result = struct { ns: u64, checks: u64 };
fn sample(comptime Type: type, pages: usize, active: usize, saturated: bool) !Result {
    const tables = try std.testing.allocator.alloc(Type, 16);
    defer std.testing.allocator.free(tables);
    var page: [4096]u8 align(4096) = undefined;
    for (tables, 0..) |*t, i| {
        t.* = Type.empty;
        t.fillOrdered(false, 0x140000000 + i * 4096, &page);
        if (saturated) for (0..512) |block| t.fillOrdered(false, block * 1024 * 4096, &page);
        if (i < active) t.fillOrdered(true, 0xA0000000, &page);
    }
    const begin = now();
    var checks: u64 = 0;
    for (0..if (pages >= 1024) @as(usize, 8) else @as(usize, 4000)) |_| {
        for (tables) |*t| t.invalidateRangeOrderedTables(0xA0000000, pages * 4096, true, true);
        checks += tables.len;
    }
    const elapsed = now() - begin;
    for (tables) |*t| try std.testing.expect(t.lookup(true, 0xA0000000) == null);
    return .{ .ns = elapsed, .checks = checks };
}
fn fills(comptime Type: type, varied: bool) !Result {
    const tlb = try std.testing.allocator.create(Type);
    defer std.testing.allocator.destroy(tlb);
    tlb.* = Type.empty;
    var page: [4096]u8 align(4096) = undefined;
    const begin = now();
    for (0..200000) |i| tlb.fillOrdered(i % 2 != 0, 0xA0000000 + (i % 512) * (if (varied) @as(u64, 4096 * 1024) else @as(u64, 4096)), &page);
    const elapsed = now() - begin;
    for (0..512) |i| try std.testing.expect(tlb.lookup(i % 2 != 0, 0xA0000000 + i * (if (varied) @as(u64, 4096 * 1024) else @as(u64, 4096))) != null);
    return .{ .ns = elapsed, .checks = 512 };
}
test "TLB region filter production range and fill benchmark (ROSETTE_TLB_FLUSH_BENCH=1)" {
    if (std.c.getenv("ROSETTE_TLB_FLUSH_BENCH") == null) return error.SkipZigTest;
    for (0..7) |pair| {
        for ([_]struct { pages: usize, active: usize, saturated: bool }{ .{ .pages = 1, .active = 1, .saturated = false }, .{ .pages = 64, .active = 1, .saturated = false }, .{ .pages = 512, .active = 1, .saturated = false }, .{ .pages = 512, .active = 16, .saturated = true }, .{ .pages = 1024, .active = 16, .saturated = true } }) |c| {
            for (0..2) |arm| {
                const enabled = (pair + arm) % 2 != 0;
                const result = if (enabled) try sample(New, c.pages, c.active, c.saturated) else try sample(Old, c.pages, c.active, c.saturated);
                std.debug.print("TLB_FLUSH pair={d} enabled={} pages={d} active={d} saturated={} ns={d} checked={d}\n", .{ pair, enabled, c.pages, c.active, c.saturated, result.ns, result.checks });
            }
        }
        for ([_]bool{ false, true }) |varied| for (0..2) |arm| {
            const enabled = (pair + arm) % 2 != 0;
            const result = if (enabled) try fills(New, varied) else try fills(Old, varied);
            std.debug.print("TLB_FILL pair={d} enabled={} varied={} ns={d} checked={d}\n", .{ pair, enabled, varied, result.ns, result.checks });
        };
    }
}
test {
    _ = @import("tlb_membership.zig");
}
