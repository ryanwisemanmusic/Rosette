//! Counters many threads bump without sharing a cache line on every bump.
//!
//! `Batch` keeps a thread's increments locally and publishes them to the
//! shared total every `threshold` counts, so a per-instruction count costs a
//! local add and, once in a few thousand instructions, one atomic. The PE
//! worker loop used to publish three shared totals with a compare-and-swap
//! loop after every guest instruction.
//!
//! `Sharded` gives each writer its own cache line and sums the lines on read,
//! for totals that must be exact at any moment but are read rarely.

const std = @import("std");

pub const Batch = struct {
    pending: u64 = 0,
    threshold: u64 = default_threshold,

    pub const default_threshold: u64 = 4096;

    pub fn add(self: *Batch, total: *std.atomic.Value(u64), amount: u64) void {
        self.pending +|= amount;
        if (self.pending >= self.threshold) self.flush(total);
    }

    pub fn flush(self: *Batch, total: *std.atomic.Value(u64)) void {
        if (self.pending == 0) return;
        _ = total.fetchAdd(self.pending, .monotonic);
        self.pending = 0;
    }
};

pub fn Sharded(comptime shard_count: usize) type {
    return struct {
        const Self = @This();

        const Cell = struct {
            value: std.atomic.Value(u64) align(128) = std.atomic.Value(u64).init(0),
        };

        cells: [shard_count]Cell = [_]Cell{.{}} ** shard_count,

        /// For a shard with exactly one writing thread: no read-modify-write.
        pub fn addSingleWriter(self: *Self, shard: usize, amount: u64) void {
            const cell = &self.cells[shard % shard_count];
            cell.value.store(cell.value.load(.monotonic) +% amount, .monotonic);
        }

        /// For a shard that several threads may write.
        pub fn add(self: *Self, shard: usize, amount: u64) void {
            _ = self.cells[shard % shard_count].value.fetchAdd(amount, .monotonic);
        }

        pub fn sum(self: *const Self) u64 {
            var total: u64 = 0;
            for (&self.cells) |*cell| total +%= cell.value.load(.monotonic);
            return total;
        }
    };
}

test "a batch publishes at its threshold and on flush" {
    var total = std.atomic.Value(u64).init(0);
    var batch: Batch = .{ .threshold = 10 };
    for (0..9) |_| batch.add(&total, 1);
    try std.testing.expectEqual(@as(u64, 0), total.load(.monotonic));
    batch.add(&total, 1);
    try std.testing.expectEqual(@as(u64, 10), total.load(.monotonic));
    batch.add(&total, 3);
    batch.flush(&total);
    try std.testing.expectEqual(@as(u64, 13), total.load(.monotonic));
}

test "sharded counts from many threads sum exactly" {
    const Counter = Sharded(8);
    const Shared = struct {
        counter: Counter = .{},
        fn run(shared: *@This(), shard: usize) void {
            for (0..10_000) |_| shared.counter.addSingleWriter(shard, 1);
        }
    };
    var shared: Shared = .{};
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, Shared.run, .{ &shared, index });
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(u64, 40_000), shared.counter.sum());
}
