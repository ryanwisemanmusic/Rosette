//! Small per-host-thread staging cache for the hot decode path.
//!
//! The process-wide decode cache remains authoritative for fills, replacement,
//! and diagnostics. This cache only avoids taking its shared shard lock for a
//! repeated instruction on the same host thread. Callers must validate the
//! cached entry against the live source bytes before using it.

// Keep a larger per-host-thread working set than the shared-cache set count
// would suggest: interpreter-heavy runs revisit hot Xenia blocks across
// thousands of guest addresses, while the cache still validates live bytes
// before returning any resident decode.
// 2026-09-30: 256 entries served 912M of 2.4G parallel lookups; every miss
// took a shared shard lock. The entries live in thread-local storage, so the
// larger table costs each executing thread, not the process.
pub const default_capacity: usize = 4096;

/// Hits a thread counts before publishing them to the shared counter, so the
/// hot path does not move one cache line between every core on every hit.
pub const hit_publish_batch: u32 = 1024;

/// Build an owner-scoped cache whose entries belong to the current host
/// thread. An owner change clears the entries so one thread cannot reuse a
/// different process's resident state accidentally.
pub fn Cache(comptime Entry: type, comptime capacity: usize) type {
    comptime {
        if (capacity == 0 or (capacity & (capacity - 1)) != 0) @compileError("worker-local cache capacity must be a power of two");
    }

    return struct {
        const State = struct {
            owner: ?*anyopaque = null,
            pending_hits: u32 = 0,
            entries: [capacity]Entry = @splat(.{}),
        };

        threadlocal var state: State = .{};

        /// Return this thread's cache entries for `owner`, resetting them if
        /// the thread has started working on another owner since its last use.
        pub fn entriesFor(owner: *anyopaque) *[capacity]Entry {
            if (state.owner != owner) {
                state.owner = owner;
                state.pending_hits = 0;
                @memset(&state.entries, .{});
            }
            return &state.entries;
        }

        /// Count one hit toward `shared`, publishing in batches.
        pub fn noteHit(shared: *std.atomic.Value(u64)) void {
            state.pending_hits += 1;
            if (state.pending_hits >= hit_publish_batch) publishHits(shared);
        }

        /// Publish the calling thread's unpublished hits now. Other threads'
        /// remainders, under one batch each, publish with their next batch.
        pub fn publishHits(shared: *std.atomic.Value(u64)) void {
            if (state.pending_hits == 0) return;
            _ = shared.fetchAdd(state.pending_hits, .monotonic);
            state.pending_hits = 0;
        }
    };
}

const std = @import("std");

test "worker-local hits publish in batches and on demand" {
    const Entry = struct { valid: bool = false };
    const LocalCache = Cache(Entry, 8);
    var owner: u8 = 0;
    _ = LocalCache.entriesFor(&owner);
    var shared = std.atomic.Value(u64).init(0);
    LocalCache.noteHit(&shared);
    try std.testing.expectEqual(@as(u64, 0), shared.load(.monotonic));
    LocalCache.publishHits(&shared);
    try std.testing.expectEqual(@as(u64, 1), shared.load(.monotonic));
    for (0..hit_publish_batch) |_| LocalCache.noteHit(&shared);
    try std.testing.expectEqual(@as(u64, 1 + hit_publish_batch), shared.load(.monotonic));
}

test "worker-local entries are reset when the owning process changes" {
    const Entry = struct { valid: bool = false, value: u64 = 0 };
    const LocalCache = Cache(Entry, 8);
    var first_owner: u8 = 0;
    var second_owner: u8 = 0;

    const first_entries = LocalCache.entriesFor(&first_owner);
    first_entries[3] = .{ .valid = true, .value = 17 };
    try @import("std").testing.expectEqual(@as(u64, 17), first_entries[3].value);

    const second_entries = LocalCache.entriesFor(&second_owner);
    try @import("std").testing.expect(!second_entries[3].valid);
}
