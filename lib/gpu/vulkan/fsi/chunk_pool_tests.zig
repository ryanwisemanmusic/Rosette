//! CPU custody oracle and lifecycle benchmarks; no driver/GPU calls.
const std = @import("std");
const production = @import("chunk_pool.zig");
const reference = @import("chunk_pool_reference.zig");
fn compare(a: anytype, b: anytype) !void {
    try std.testing.expectEqual(a.count, b.count);
    try std.testing.expectEqual(a.allocated, b.allocated);
    try std.testing.expectEqual(a.reuses, b.reuses);
    try std.testing.expectEqual(a.exhausted, b.exhausted);
    try std.testing.expectEqual(a.poisoned_count, b.poisoned_count);
    for (a.entries[0..a.count], b.entries[0..b.count]) |x, y| {
        inline for (.{ "handle", "in_use", "poisoned", "release_after", "last_submit" }) |f| try std.testing.expectEqual(@field(x, f), @field(y, f));
    }
}
test "FSI indexed recycling matches scanning custody under randomized serials releases and poisoning" {
    var old: reference.Pool(192) = .{};
    var new: production.Pool(192) = .{};
    var generator = std.Random.DefaultPrng.init(0x813257);
    const random = generator.random();
    for (0..20000) |_| {
        const index = random.uintLessThan(u64, 220);
        const handle = 0x123000000 + index * 16;
        switch (random.uintLessThan(u8, 5)) {
            0 => try std.testing.expectEqual(old.add(handle), new.add(handle)),
            1 => {
                old.release(handle);
                new.release(handle);
            },
            2 => {
                const serial = random.uintLessThan(u64, 120);
                old.noteSubmitted(handle, serial);
                new.noteSubmitted(handle, serial);
            },
            3 => {
                old.discard(handle);
                new.discard(handle);
            },
            4 => {
                const serial = random.uintLessThan(u64, 120);
                try std.testing.expectEqual(old.acquire(serial), new.acquire(serial));
            },
            else => unreachable,
        }
        try compare(&old, &new);
    }
}
test "FSI indexed recycling preserves empty zero duplicate full and delayed-ready contracts" {
    var old: reference.Pool(4) = .{};
    var new: production.Pool(4) = .{};
    for ([_]u64{ 0, 16, 16, 32, 48 }) |h| try std.testing.expectEqual(old.add(h), new.add(h));
    for ([_]u64{ 0, 16, 32, 999 }) |h| {
        old.noteSubmitted(h, 10);
        new.noteSubmitted(h, 10);
        old.release(h);
        new.release(h);
    }
    for ([_]u64{ 9, 10, 0, 10, 20 }) |s| try std.testing.expectEqual(old.acquire(s), new.acquire(s));
    old.discard(16);
    new.discard(16);
    old.release(16);
    new.release(16);
    try std.testing.expectEqual(old.acquire(1000), new.acquire(1000));
    try compare(&old, &new);
}
fn now() u64 {
    var t: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.MONOTONIC, &t) == 0);
    return @as(u64, @intCast(t.sec)) * std.time.ns_per_s + @as(u64, @intCast(t.nsec));
}
fn lifecycle(comptime Type: type, count: usize, batches: usize) !struct { elapsed: u64, checked: u64 } {
    const pool = try std.testing.allocator.create(Type);
    defer std.testing.allocator.destroy(pool);
    pool.* = .{};
    for (0..count) |i| try std.testing.expect(pool.add(0x200000000 + i * 16));
    const begin = now();
    var checked: u64 = 0;
    for (0..batches) |batch| {
        const serial = batch + 1;
        for (0..count) |i| pool.noteSubmitted(0x200000000 + i * 16, serial);
        for (0..count) |i| pool.release(0x200000000 + i * 16);
        // Driver completion is mandatory; an incomplete frame yields no slot.
        try std.testing.expect(pool.acquire(serial - 1) == null);
        for (0..count) |i| {
            try std.testing.expectEqual(@as(?u64, 0x200000000 + i * 16), pool.acquire(serial));
            checked += 1;
        }
        try std.testing.expect(pool.acquire(serial) == null);
    }
    return .{ .elapsed = now() - begin, .checked = checked };
}
test "FSI indexed recycling production lifecycle benchmark (ROSETTE_RETIREMENT_BENCH=1)" {
    if (std.c.getenv("ROSETTE_RETIREMENT_BENCH") == null) return error.SkipZigTest;
    const Old = reference.Pool(8190);
    const New = production.Pool(8190);
    for (0..7) |pair| for ([_]usize{ 32, 2509, 4095 }) |count| {
        for (0..2) |arm| {
            const enabled = (pair + arm) % 2 != 0;
            const result = if (enabled) try lifecycle(New, count, if (count == 32) 1000 else 20) else try lifecycle(Old, count, if (count == 32) 1000 else 20);
            std.debug.print("RECYCLE pair={d} enabled={} entries={d} ns={d} checked={d}\n", .{ pair, enabled, count, result.elapsed, result.checked });
        }
    };
}

fn retiring(comptime Type: type, count: usize) !u64 {
    const pool = try std.testing.allocator.create(Type);
    defer std.testing.allocator.destroy(pool);
    pool.* = .{};
    const Recording = @import("chain.zig").Recording;
    const recording = try std.testing.allocator.create(Recording);
    defer std.testing.allocator.destroy(recording);
    for (0..count) |i| try std.testing.expect(pool.add(0x300000000 + i * 16));
    var elapsed: u64 = 0;
    for (0..40) |batch| {
        recording.* = .{};
        recording.guest = 0x777;
        recording.chunk_count = count;
        for (0..count) |i| {
            recording.chunks[i] = 0x300000000 + i * 16;
            pool.noteSubmitted(recording.chunks[i], batch + 1);
        }
        const start = now();
        @import("recycling.zig").release(pool, recording);
        elapsed += now() - start;
        try std.testing.expectEqual(@as(u64, 0), recording.guest);
        try std.testing.expectEqual(@as(usize, 0), recording.chunk_count);
        try std.testing.expect(pool.acquire(batch) == null);
        for (0..count) |i| try std.testing.expectEqual(@as(?u64, 0x300000000 + i * 16), pool.acquire(batch + 1));
    }
    return elapsed;
}
test "FSI recording retirement measured full clear benchmark (ROSETTE_RETIREMENT_BENCH=1)" {
    if (std.c.getenv("ROSETTE_RETIREMENT_BENCH") == null) return error.SkipZigTest;
    for (0..7) |pair| for (0..2) |arm| {
        const enabled = (pair + arm) % 2 != 0;
        const ns = if (enabled) try retiring(production.Pool(8190), 2509) else try retiring(reference.Pool(8190), 2509);
        std.debug.print("RETIRE_RECORDING pair={d} enabled={} entries=2509 batches=40 ns={d} checked=100360\n", .{ pair, enabled, ns });
    };
}
