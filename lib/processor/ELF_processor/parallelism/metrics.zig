//! Small atomic counters used by independent PE guest executors.
//!
//! Most guest state is context-local, and process mutations rendezvous through
//! `GuestExecutionGate`. A few hot totals must still be updated by multiple
//! host workers without taking that gate on every guest instruction.

const std = @import("std");

pub fn load(comptime T: type, counter: *const T) T {
    return @atomicLoad(T, counter, .acquire);
}

/// Saturating addition for a plain integer field that becomes shared once
/// parallel guest execution starts. Serial execution retains its cheaper
/// ordinary `+|=` path at the call site.
pub fn saturatingAdd(comptime T: type, counter: *T, amount: T) T {
    var observed = @atomicLoad(T, counter, .monotonic);
    while (true) {
        const desired = observed +| amount;
        if (@cmpxchgWeak(T, counter, observed, desired, .monotonic, .monotonic)) |actual| {
            observed = actual;
        } else {
            return desired;
        }
    }
}

test "parallel counter additions saturate under concurrent updates" {
    const Shared = struct {
        value: u64 = 0,

        fn add(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            for (0..10_000) |_| _ = saturatingAdd(u64, &self.value, 1);
        }
    };

    var shared: Shared = .{};
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Shared.add, .{@as(*anyopaque, @ptrCast(&shared))});
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(u64, 40_000), load(u64, &shared.value));

    shared.value = std.math.maxInt(u64) - 1;
    try std.testing.expectEqual(std.math.maxInt(u64), saturatingAdd(u64, &shared.value, 2));
}
