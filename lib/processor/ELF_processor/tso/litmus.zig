//! Parallel regression and stress tests for the bounded guest TSO model.
//!
//! The workers below are real host threads. Their atomic phase counters are
//! test-harness rendezvous only; they do not touch guest memory and therefore
//! cannot publish a guest store buffer. This lets the store-buffering test
//! check the store-to-load outcome permitted by x86 TSO, verify that MFENCE
//! forbids it, and separately pin the stronger queue-drain contract used by
//! Rosette's SFENCE helper before bulk runtime writes.

const std = @import("std");
const tso = @import("tso_memory");

const rounds = 128;

const StoreLoadFence = enum {
    none,
    load,
    store,
    full,
};

fn runStoreBuffering(fence: StoreLoadFence) ![2][rounds]u32 {
    const Shared = struct {
        // Each round has a private pair of guest words. Keeping rounds
        // independent avoids reset races and makes every observed value
        // attributable to the current store-to-load sequence.
        bytes: [rounds * 16]u8 align(64) = @splat(0),
        start: std.atomic.Value(bool) = .init(false),
        stores_ready: std.atomic.Value(u32) = .init(0),
        loads_done: std.atomic.Value(u32) = .init(0),
        drains_done: std.atomic.Value(u32) = .init(0),
        observed: [2][rounds]u32 = @splat(@splat(0)),

        fn worker(shared: *@This(), executor: usize, mode: StoreLoadFence) void {
            var buffer = tso.StoreBuffer{};
            const previous_mode = tso.setCoordinatedGuestAccess(true);
            defer _ = tso.setCoordinatedGuestAccess(previous_mode);
            const previous_buffer = tso.setActiveStoreBuffer(&buffer);
            defer _ = tso.setActiveStoreBuffer(previous_buffer);

            while (!shared.start.load(.acquire)) std.atomic.spinLoopHint();

            for (0..rounds) |round| {
                const base = round * 16;
                const own_offset = base + executor * 8;
                const peer_offset = base + (1 - executor) * 8;
                tso.store(u32, shared.bytes[own_offset..][0..4], 1);

                switch (mode) {
                    .none => {},
                    .load => tso.loadFence(),
                    .store => tso.storeFence(),
                    .full => tso.memoryFence(),
                }

                const phase: u32 = @intCast((round + 1) * 2);
                _ = shared.stores_ready.fetchAdd(1, .release);
                while (shared.stores_ready.load(.acquire) < phase) std.atomic.spinLoopHint();

                shared.observed[executor][round] = tso.load(u32, shared.bytes[peer_offset..][0..4]);
                _ = shared.loads_done.fetchAdd(1, .release);
                while (shared.loads_done.load(.acquire) < phase) std.atomic.spinLoopHint();

                // End-of-round cleanup happens only after both guest loads.
                // It prevents a previous iteration's stores from filling the
                // bounded queue and influencing the next iteration.
                tso.memoryFence();
                _ = shared.drains_done.fetchAdd(1, .release);
                while (shared.drains_done.load(.acquire) < phase) std.atomic.spinLoopHint();
            }
        }
    };

    var shared = Shared{};
    const first = try std.Thread.spawn(.{}, Shared.worker, .{ &shared, 0, fence });
    const second = try std.Thread.spawn(.{}, Shared.worker, .{ &shared, 1, fence });
    shared.start.store(true, .release);
    first.join();
    second.join();
    return shared.observed;
}

test "parallel store buffering allows 0,0 without a fence and with LFENCE" {
    inline for (.{ StoreLoadFence.none, StoreLoadFence.load }) |fence| {
        const observed = try runStoreBuffering(fence);
        for (0..rounds) |round| {
            // x86 TSO preserves load/load order but permits a later load to
            // pass an earlier store to a different address.
            try std.testing.expectEqual(@as(u32, 0), observed[0][round]);
            try std.testing.expectEqual(@as(u32, 0), observed[1][round]);
        }
    }
}

test "parallel MFENCE forbids the 0,0 store-buffering outcome" {
    const observed = try runStoreBuffering(.full);
    for (0..rounds) |round| {
        try std.testing.expectEqual(@as(u32, 1), observed[0][round]);
        try std.testing.expectEqual(@as(u32, 1), observed[1][round]);
    }
}

test "parallel SFENCE publishes queued stores before a following access" {
    // The software SFENCE helper drains the executor queue because Rosette
    // also uses this boundary before bulk writes that bypass the queue. That
    // is stronger than the ISA's store-store minimum; it is tested here as
    // the explicit helper contract, not as a claim that SFENCE forbids every
    // store-to-load outcome on x86.
    const observed = try runStoreBuffering(.store);
    for (0..rounds) |round| {
        try std.testing.expectEqual(@as(u32, 1), observed[0][round]);
        try std.testing.expectEqual(@as(u32, 1), observed[1][round]);
    }
}

test "parallel locked fetch-add is linearizable under executor contention" {
    const worker_count = 4;
    const iterations = 2048;
    const Shared = struct {
        counter: [8]u8 align(8) = [_]u8{0} ** 8,
        ready: std.atomic.Value(u32) = .init(0),
        old_values: [worker_count][iterations]u64 = @splat(@splat(0)),

        fn worker(shared: *@This(), slot: usize) void {
            var buffer = tso.StoreBuffer{};
            const previous_mode = tso.setCoordinatedGuestAccess(true);
            defer _ = tso.setCoordinatedGuestAccess(previous_mode);
            const previous_buffer = tso.setActiveStoreBuffer(&buffer);
            defer _ = tso.setActiveStoreBuffer(previous_buffer);

            _ = shared.ready.fetchAdd(1, .release);
            while (shared.ready.load(.acquire) != worker_count) std.atomic.spinLoopHint();
            for (0..iterations) |iteration| {
                shared.old_values[slot][iteration] = tso.fetchAdd(u64, shared.counter[0..8], 1) orelse unreachable;
            }
            tso.memoryFence();
        }
    };

    var shared = Shared{};
    var threads: [worker_count]std.Thread = undefined;
    for (0..worker_count) |slot| {
        threads[slot] = try std.Thread.spawn(.{}, Shared.worker, .{ &shared, slot });
    }
    for (&threads) |thread| thread.join();

    const total: u64 = worker_count * iterations;
    try std.testing.expectEqual(total, tso.loadCoordinated(u64, shared.counter[0..8]));

    // Every returned old value must be one distinct point in the completed
    // sequential history. This catches duplicate/lost updates, not only the
    // final sum.
    var seen: [worker_count * iterations]bool = @splat(false);
    for (shared.old_values) |worker_values| {
        for (worker_values) |old| {
            try std.testing.expect(old < total);
            const index: usize = @intCast(old);
            try std.testing.expect(!seen[index]);
            seen[index] = true;
        }
    }
    for (seen) |present| try std.testing.expect(present);
}

test "parallel compare-exchange loops make progress without losing updates" {
    const worker_count = 4;
    const iterations = 1024;
    const Shared = struct {
        counter: [8]u8 align(8) = [_]u8{0} ** 8,
        ready: std.atomic.Value(u32) = .init(0),

        fn worker(shared: *@This()) void {
            var buffer = tso.StoreBuffer{};
            const previous_mode = tso.setCoordinatedGuestAccess(true);
            defer _ = tso.setCoordinatedGuestAccess(previous_mode);
            const previous_buffer = tso.setActiveStoreBuffer(&buffer);
            defer _ = tso.setActiveStoreBuffer(previous_buffer);

            _ = shared.ready.fetchAdd(1, .release);
            while (shared.ready.load(.acquire) != worker_count) std.atomic.spinLoopHint();
            for (0..iterations) |_| {
                var expected = tso.loadCoordinated(u64, shared.counter[0..8]);
                while (true) {
                    const result = tso.compareExchange(u64, shared.counter[0..8], expected, expected +% 1) orelse unreachable;
                    if (result.exchanged) break;
                    expected = result.previous;
                }
            }
            tso.memoryFence();
        }
    };

    var shared = Shared{};
    var threads: [worker_count]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Shared.worker, .{&shared});
    for (&threads) |thread| thread.join();
    try std.testing.expectEqual(
        @as(u64, worker_count * iterations),
        tso.loadCoordinated(u64, shared.counter[0..8]),
    );
}

test "parallel guest context switch publishes only the context being left" {
    const Shared = struct {
        memory: [16]u8 align(8) = [_]u8{0} ** 16,
        phase: std.atomic.Value(u32) = .init(0),
        ack: std.atomic.Value(bool) = .init(false),
        owner_context_saw_own_store: std.atomic.Value(bool) = .init(false),
        owner_context_did_not_see_peer_queue: std.atomic.Value(bool) = .init(false),
        observer_a: std.atomic.Value(u64) = .init(0),
        observer_b_before_drain: std.atomic.Value(u64) = .init(0),
        observer_b_after_drain: std.atomic.Value(u64) = .init(0),

        fn switchContexts(shared: *@This(), buffers: *tso.GuestStoreBuffers) void {
            const previous_mode = tso.setCoordinatedGuestAccess(true);
            defer _ = tso.setCoordinatedGuestAccess(previous_mode);

            const first_context = buffers.forContext(0).?;
            const second_context = buffers.forContext(1).?;
            const previous_buffer = tso.setActiveStoreBuffer(first_context);
            defer _ = tso.setActiveStoreBuffer(previous_buffer);
            tso.store(u64, shared.memory[0..8], 0xA1);
            buffers.drainContext(0, .context_switch);

            // A distinct guest context has a distinct forwarding queue even
            // though this host executor is now running it.
            _ = tso.setActiveStoreBuffer(second_context);
            tso.store(u64, shared.memory[8..16], 0xB2);
            shared.owner_context_saw_own_store.store(
                tso.load(u64, shared.memory[8..16]) == 0xB2,
                .release,
            );
            _ = tso.setActiveStoreBuffer(first_context);
            shared.owner_context_did_not_see_peer_queue.store(
                tso.load(u64, shared.memory[8..16]) == 0,
                .release,
            );
            _ = tso.setActiveStoreBuffer(second_context);

            shared.phase.store(1, .release);
            while (!shared.ack.load(.acquire)) std.atomic.spinLoopHint();
            buffers.drainContext(1, .context_switch);
            shared.phase.store(2, .release);
            tso.memoryFence();
        }

        fn observe(shared: *@This()) void {
            const previous_mode = tso.setCoordinatedGuestAccess(true);
            defer _ = tso.setCoordinatedGuestAccess(previous_mode);
            while (shared.phase.load(.acquire) < 1) std.atomic.spinLoopHint();
            shared.observer_a.store(tso.load(u64, shared.memory[0..8]), .release);
            shared.observer_b_before_drain.store(tso.load(u64, shared.memory[8..16]), .release);
            shared.ack.store(true, .release);
            while (shared.phase.load(.acquire) < 2) std.atomic.spinLoopHint();
            shared.observer_b_after_drain.store(tso.load(u64, shared.memory[8..16]), .release);
        }
    };

    var buffers = try tso.GuestStoreBuffers.init(std.testing.allocator, 2);
    defer buffers.deinit(std.testing.allocator);
    var shared = Shared{};
    const observer = try std.Thread.spawn(.{}, Shared.observe, .{&shared});
    const executor = try std.Thread.spawn(.{}, Shared.switchContexts, .{ &shared, &buffers });
    executor.join();
    observer.join();

    try std.testing.expect(shared.owner_context_saw_own_store.load(.acquire));
    try std.testing.expect(shared.owner_context_did_not_see_peer_queue.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0xA1), shared.observer_a.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), shared.observer_b_before_drain.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0xB2), shared.observer_b_after_drain.load(.acquire));
    try std.testing.expect(!buffers.anyPending());
}
