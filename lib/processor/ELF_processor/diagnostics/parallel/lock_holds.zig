//! Which runtime calls hold the runtime lock, and for how long.
//!
//! In parallel mode every import takes the one runtime mutex. A call that
//! keeps it long - a Vulkan fence wait, a file read, an AppKit round trip -
//! holds every other guest thread's next import behind it, and nothing about
//! the guest's own behaviour shows that. `PE64 CONCURRENCY` says how much the
//! mutex was contended in total; this ledger says whose calls did it.
//!
//! Each entry is keyed by the import name's address (the state owns every
//! name for the life of the run), so the per-call cost is one hash probe.
//! The ledger is updated only while the runtime lock is held, so it needs no
//! lock of its own.

const std = @import("std");

pub const capacity = 256;

pub const Entry = struct {
    key: usize = 0,
    name: []const u8 = "",
    calls: u64 = 0,
    /// Time the call held the lock: from entry to exit, less any time it
    /// gave the lock back to wait (an empty `GetMessage`).
    held_ns: u64 = 0,
    max_held_ns: u64 = 0,
    /// Time the calling thread waited to get the lock for this call.
    waited_ns: u64 = 0,
    max_waited_ns: u64 = 0,
    /// Time the call spent with the lock released, blocked for its result.
    released_ns: u64 = 0,
};

pub const Ledger = struct {
    entries: [capacity]Entry = @splat(.{}),
    used: usize = 0,
    calls: u64 = 0,
    held_ns: u64 = 0,
    waited_ns: u64 = 0,
    /// Calls whose name found no free entry.
    overflow_calls: u64 = 0,
    overflow_held_ns: u64 = 0,

    pub fn note(self: *Ledger, name: []const u8, held_ns: u64, waited_ns: u64, released_ns: u64) void {
        self.calls +|= 1;
        self.held_ns +|= held_ns;
        self.waited_ns +|= waited_ns;
        const entry = self.entryFor(name) orelse {
            self.overflow_calls +|= 1;
            self.overflow_held_ns +|= held_ns;
            return;
        };
        entry.calls +|= 1;
        entry.held_ns +|= held_ns;
        entry.max_held_ns = @max(entry.max_held_ns, held_ns);
        entry.waited_ns +|= waited_ns;
        entry.max_waited_ns = @max(entry.max_waited_ns, waited_ns);
        entry.released_ns +|= released_ns;
    }

    fn entryFor(self: *Ledger, name: []const u8) ?*Entry {
        const key = @intFromPtr(name.ptr);
        if (key == 0) return null;
        // Import names are heap blocks at least 8-aligned; mix the bits
        // that differ before taking the table index.
        var probe: usize = @truncate(std.hash.int(@as(u64, key)) % capacity);
        for (0..capacity) |_| {
            const entry = &self.entries[probe];
            if (entry.key == key) return entry;
            if (entry.key == 0) {
                entry.* = .{ .key = key, .name = name };
                self.used += 1;
                return entry;
            }
            probe = (probe + 1) % capacity;
        }
        return null;
    }

    /// Up to `out.len` entries with the most held time, longest first.
    pub fn top(self: *const Ledger, out: []Entry) []Entry {
        var count: usize = 0;
        for (self.entries) |entry| {
            if (entry.key == 0) continue;
            var position = count;
            if (count < out.len) {
                count += 1;
            } else if (out.len == 0 or entry.held_ns <= out[out.len - 1].held_ns) {
                continue;
            } else {
                position = out.len - 1;
            }
            while (position > 0 and out[position - 1].held_ns < entry.held_ns) : (position -= 1) {
                out[position] = out[position - 1];
            }
            out[position] = entry;
        }
        return out[0..count];
    }

    /// The entry whose single longest hold is longest, or null when empty.
    pub fn longestSingleHold(self: *const Ledger) ?Entry {
        var best: ?Entry = null;
        for (self.entries) |entry| {
            if (entry.key == 0) continue;
            if (best == null or entry.max_held_ns > best.?.max_held_ns) best = entry;
        }
        return best;
    }
};

test "the ledger ranks calls by the time they held the lock" {
    var ledger: Ledger = .{};
    const get_message: []const u8 = "GetMessageW";
    const fence_wait: []const u8 = "vkWaitForFences";
    const sleep: []const u8 = "Sleep";
    for (0..1000) |_| ledger.note(get_message, 2_000, 100, 4_000_000);
    ledger.note(fence_wait, 900_000_000, 50, 0);
    for (0..10) |_| ledger.note(sleep, 1_000, 5_000_000, 0);
    var out: [2]Entry = undefined;
    const ranked = ledger.top(&out);
    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqualStrings("vkWaitForFences", ranked[0].name);
    try std.testing.expectEqualStrings("GetMessageW", ranked[1].name);
    try std.testing.expectEqual(@as(u64, 1000), ranked[1].calls);
    try std.testing.expectEqual(@as(u64, 4_000_000_000), ranked[1].released_ns);
    try std.testing.expectEqual(@as(u64, 5_000_000), ledger.entryFor(sleep).?.max_waited_ns);
    try std.testing.expectEqualStrings("vkWaitForFences", ledger.longestSingleHold().?.name);
    try std.testing.expectEqual(@as(u64, 1011), ledger.calls);
    try std.testing.expectEqual(@as(usize, 3), ledger.used);
}

test "a full ledger counts what it cannot name" {
    var ledger: Ledger = .{};
    var names: [capacity + 4][8]u8 = undefined;
    for (&names, 0..) |*name, index| {
        _ = std.fmt.bufPrint(name, "f{d:0>7}", .{index}) catch unreachable;
        ledger.note(name, 10, 0, 0);
    }
    try std.testing.expectEqual(@as(usize, capacity), ledger.used);
    try std.testing.expectEqual(@as(u64, 4), ledger.overflow_calls);
    try std.testing.expectEqual(@as(u64, 40), ledger.overflow_held_ns);
}
