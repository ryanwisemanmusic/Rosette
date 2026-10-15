//! Thread-safe synthetic-to-native Vulkan object identity maps.
//!
//! Guest Vulkan work can arrive from Xenia's pipeline workers as well as its
//! main GPU thread. Lookups are therefore lock-free and have per-host-thread
//! caches; insertion and removal are serialized so two creators cannot claim
//! the same free slot. A sequence word publishes each slot coherently to
//! lock-free readers.

const std = @import("std");

const RealHandle = u64;
const cache_bits = 14;
const cache_capacity = 1 << cache_bits;

const CacheEntry = struct {
    base: usize = 0,
    synthetic: u64 = 0,
    index: u32 = 0,
};

/// These handles are queried on every forwarded command. Keeping the cache
/// thread-local avoids both a shared-cache data race and a lock on the hot
/// path. 16K slots still cover Halo 3's large descriptor-set working set while
/// keeping each Vulkan worker's TLS allocation below half a megabyte.
threadlocal var lookup_cache: [cache_capacity]CacheEntry = @splat(.{});

/// Creation and destruction are far less frequent than command translation.
/// One registry lock protects all fixed maps, while readers remain lock-free.
var mutation_mutex: std.atomic.Mutex = .unlocked;

fn cacheSlot(base: usize, synthetic: u64) usize {
    const mixed = (synthetic ^ (@as(u64, @intCast(base)) >> 4)) *% 0x9E37_79B9_7F4A_7C15;
    return @intCast(mixed >> (64 - cache_bits));
}

pub const Snapshot = struct {
    synthetic: u64,
    real: RealHandle,
    owner: u64,
};

pub const Entry = struct {
    /// A null synthetic handle means this slot is free. These fields are only
    /// read or written atomically; `generation` makes their tuple coherent.
    synthetic: u64 = 0,
    real: RealHandle = 0,
    /// Descriptor sets are children of a descriptor pool. Other map families
    /// leave owner zero.
    owner: u64 = 0,
    generation: u64 = 0,

    pub const InsertResult = enum { inserted, existing, replaced, invalid, exhausted };

    /// Read one stable mapping. A writer holds the mutation mutex and marks
    /// the generation odd only while publishing a few atomic words.
    pub fn snapshot(entry: *const Entry) ?Snapshot {
        while (true) {
            const before = @atomicLoad(u64, &entry.generation, .acquire);
            if ((before & 1) != 0) {
                std.atomic.spinLoopHint();
                continue;
            }

            // Pair with each publisher's release store. If any payload load
            // observes a value from an in-progress replacement, its preceding
            // odd-generation store happens-before the trailing generation
            // load, which therefore cannot validate the old even generation.
            const synthetic = @atomicLoad(u64, &entry.synthetic, .acquire);
            const real = @atomicLoad(u64, &entry.real, .acquire);
            const owner = @atomicLoad(u64, &entry.owner, .acquire);
            // The trailing SC read also prevents the payload loads moving
            // past validation on weakly ordered hosts such as Apple silicon.
            const after = @atomicLoad(u64, &entry.generation, .seq_cst);
            if (before != after or (after & 1) != 0) continue;
            if (synthetic == 0) return null;
            return .{ .synthetic = synthetic, .real = real, .owner = owner };
        }
    }

    pub fn snapshotAt(map: []const Entry, index: usize) ?Snapshot {
        if (index >= map.len) return null;
        return Entry.snapshot(&map[index]);
    }

    pub fn findReal(map: []const Entry, synthetic: u64) ?RealHandle {
        if (synthetic == 0) return null;
        const base = @intFromPtr(map.ptr);
        const cached = &lookup_cache[cacheSlot(base, synthetic)];
        if (cached.synthetic == synthetic and cached.base == base and cached.index < map.len) {
            // One coherent snapshot already proves identity and value. The
            // old findIndex + snapshotAt path validated this same slot twice.
            if (Entry.snapshotAt(map, cached.index)) |mapped| {
                if (mapped.synthetic == synthetic and mapped.real != 0) return mapped.real;
            }
        }
        const index = findIndex(map, synthetic) orelse return null;
        const mapped = Entry.snapshotAt(map, index) orelse return null;
        if (mapped.synthetic != synthetic or mapped.real == 0) return null;
        return mapped.real;
    }

    /// Resolve a native identity back to its guest-visible token.
    pub fn findSynthetic(map: []const Entry, real: RealHandle) ?u64 {
        if (real == 0) return null;
        for (map) |*entry| {
            // A key is only a rejection filter; a matching slot still needs
            // the full seqlock validation before any identity is returned.
            if (@atomicLoad(u64, &entry.real, .acquire) != real) continue;
            const mapped = Entry.snapshot(entry) orelse continue;
            if (mapped.real == real) return mapped.synthetic;
        }
        return null;
    }

    fn findIndex(map: []const Entry, synthetic: u64) ?usize {
        if (synthetic == 0) return null;
        const base = @intFromPtr(map.ptr);
        const cached = &lookup_cache[cacheSlot(base, synthetic)];
        if (cached.synthetic == synthetic and cached.base == base and cached.index < map.len) {
            if (Entry.snapshotAt(map, cached.index)) |mapped| {
                if (mapped.synthetic == synthetic) return cached.index;
            }
        }

        for (map, 0..) |*entry, index| {
            if (@atomicLoad(u64, &entry.synthetic, .acquire) != synthetic) continue;
            const mapped = Entry.snapshot(entry) orelse continue;
            if (mapped.synthetic == synthetic) {
                cached.* = .{ .base = base, .synthetic = synthetic, .index = @intCast(index) };
                return index;
            }
        }
        return null;
    }

    fn publish(entry: *Entry, synthetic: u64, real: RealHandle, owner: u64) void {
        const generation = @atomicLoad(u64, &entry.generation, .monotonic);
        std.debug.assert((generation & 1) == 0);
        @atomicStore(u64, &entry.generation, generation +% 1, .seq_cst);
        @atomicStore(u64, &entry.synthetic, synthetic, .release);
        @atomicStore(u64, &entry.real, real, .release);
        @atomicStore(u64, &entry.owner, owner, .release);
        @atomicStore(u64, &entry.generation, generation +% 2, .release);
    }

    fn lockMutations() void {
        while (!mutation_mutex.tryLock()) std.atomic.spinLoopHint();
    }

    fn unlockMutations() void {
        mutation_mutex.unlock();
    }

    pub fn alloc(map: []Entry, synthetic: u64, real: RealHandle) InsertResult {
        return Entry.allocOrFindOwned(map, synthetic, real, 0);
    }

    pub fn allocOrFind(map: []Entry, synthetic: u64, real: RealHandle) InsertResult {
        return Entry.allocOrFindOwned(map, synthetic, real, 0);
    }

    pub fn allocOrFindOwned(map: []Entry, synthetic: u64, real: RealHandle, owner: u64) InsertResult {
        if (synthetic == 0 or real == 0) return .invalid;
        Entry.lockMutations();
        defer Entry.unlockMutations();

        if (Entry.findIndex(map, synthetic)) |index| {
            const entry = &map[index];
            const previous = Entry.snapshot(entry) orelse return .exhausted;
            const unchanged = previous.real == real and previous.owner == owner;
            Entry.publish(entry, synthetic, real, owner);
            return if (unchanged) .existing else .replaced;
        }

        for (map, 0..) |*entry, index| {
            if (Entry.snapshot(entry) == null) {
                Entry.publish(entry, synthetic, real, owner);
                const base = @intFromPtr(map.ptr);
                lookup_cache[cacheSlot(base, synthetic)] = .{
                    .base = base,
                    .synthetic = synthetic,
                    .index = @intCast(index),
                };
                return .inserted;
            }
        }
        return .exhausted;
    }

    pub fn freeSlots(map: []const Entry) usize {
        var free: usize = 0;
        for (map) |*entry| {
            if (Entry.snapshot(entry) == null) free += 1;
        }
        return free;
    }

    pub fn occupied(map: []const Entry) usize {
        return map.len - Entry.freeSlots(map);
    }

    pub fn removeOwned(map: []Entry, owner: u64) usize {
        if (owner == 0) return 0;
        Entry.lockMutations();
        defer Entry.unlockMutations();
        var removed: usize = 0;
        for (map) |*entry| {
            const mapped = Entry.snapshot(entry) orelse continue;
            if (mapped.owner != owner) continue;
            Entry.publish(entry, 0, 0, 0);
            removed += 1;
        }
        return removed;
    }

    pub fn remove(map: []Entry, synthetic: u64) bool {
        if (synthetic == 0) return false;
        Entry.lockMutations();
        defer Entry.unlockMutations();
        const index = Entry.findIndex(map, synthetic) orelse return false;
        const mapped = Entry.snapshotAt(map, index) orelse return false;
        if (mapped.synthetic != synthetic) return false;
        Entry.publish(&map[index], 0, 0, 0);
        return true;
    }

    /// Clear a map coherently for device teardown. Readers never observe the
    /// plain-byte memset that previously raced with guest worker lookups.
    pub fn clear(map: []Entry) void {
        Entry.lockMutations();
        defer Entry.unlockMutations();
        for (map) |*entry| Entry.publish(entry, 0, 0, 0);
    }
};

test "Vulkan handle lookup retains cache lifetime and concurrent identity checks" {
    try @import("handle_lookup_tests.zig").check(Entry);
}

test "handle registry maps, replaces, removes and reclaims owned handles" {
    var map: [2]Entry = .{ .{}, .{} };
    try std.testing.expectEqual(Entry.InsertResult.inserted, Entry.allocOrFind(&map, 0x11, 0x21));
    try std.testing.expectEqual(Entry.InsertResult.inserted, Entry.allocOrFindOwned(&map, 0x12, 0x22, 0xA));
    try std.testing.expectEqual(Entry.InsertResult.existing, Entry.allocOrFindOwned(&map, 0x12, 0x22, 0xA));
    try std.testing.expectEqual(Entry.InsertResult.replaced, Entry.allocOrFindOwned(&map, 0x12, 0x23, 0xB));
    try std.testing.expectEqual(@as(?u64, 0x21), Entry.findReal(&map, 0x11));
    try std.testing.expectEqual(@as(?u64, 0x23), Entry.findReal(&map, 0x12));
    try std.testing.expectEqual(@as(?u64, 0x12), Entry.findSynthetic(&map, 0x23));
    try std.testing.expectEqual(@as(usize, 2), Entry.occupied(&map));
    try std.testing.expectEqual(@as(usize, 1), Entry.removeOwned(&map, 0xB));
    try std.testing.expectEqual(@as(?u64, null), Entry.findReal(&map, 0x12));
    try std.testing.expect(Entry.remove(&map, 0x11));
    try std.testing.expectEqual(@as(usize, 2), Entry.freeSlots(&map));
}

test "parallel Vulkan handle-map writers publish every mapping" {
    const worker_count = 8;
    const handles_per_worker = 96;
    const capacity = worker_count * handles_per_worker;
    var map: [capacity]Entry = @splat(.{});

    const Worker = struct {
        fn run(shared_map: []Entry, worker_index: usize) void {
            for (0..handles_per_worker) |item| {
                const ordinal = worker_index * handles_per_worker + item + 1;
                const synthetic = 0x1000 + ordinal * 0x10;
                const real = 0x8000 + ordinal * 0x20;
                const result = Entry.allocOrFind(shared_map, synthetic, real);
                if (result != .inserted) std.debug.panic("parallel handle insertion returned {s}", .{@tagName(result)});
                if ((Entry.findReal(shared_map, synthetic) orelse 0) != real)
                    std.debug.panic("parallel handle lookup lost synthetic handle 0x{x}", .{synthetic});
            }
        }
    };

    var threads: [worker_count]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &map, index });
    for (threads) |thread| thread.join();

    try std.testing.expectEqual(@as(usize, capacity), Entry.occupied(&map));
    for (0..capacity) |ordinal| {
        const synthetic = 0x1000 + (ordinal + 1) * 0x10;
        const real = 0x8000 + (ordinal + 1) * 0x20;
        try std.testing.expectEqual(@as(?u64, real), Entry.findReal(&map, synthetic));
    }
}
