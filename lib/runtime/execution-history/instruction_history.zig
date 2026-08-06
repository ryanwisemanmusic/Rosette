//! Thread-partitioned retained instruction history.
//!
//! The problem this solves is a decidability problem, not a storage one.
//!
//! The previous history was a single 256-entry ring shared by every guest
//! thread, and every consumer filtered it by thread handle. With thirteen live
//! threads a faulting thread's usable window was a couple of dozen entries. A
//! bounded recognizer asking "what did this register hold before it was
//! cleared" would then report "it was always zero" — true of the window,
//! useless as an answer, and indistinguishable from "the register really was
//! always zero". The machine was not undecided because the evidence was
//! ambiguous; it was undecided because the tape could not reach the evidence,
//! and it had no way to say which.
//!
//! Partitioning gives every thread its own contiguous slice of one allocation,
//! so a thread's window no longer depends on how noisy its neighbours are, and
//! `windowFor` reports the actual reach so an undecided result can be
//! attributed to the tape rather than to the program.

const std = @import("std");
const ring_mod = @import("ring.zig");

pub fn History(comptime Entry: type) type {
    return struct {
        const Self = @This();
        const Ring = ring_mod.Ring(Entry);

        pub const unassigned: u64 = std.math.maxInt(u64);

        pub const Slot = struct {
            thread: u64 = unassigned,
            ring: Ring,
            /// Sequence of the most recent push into this slot. Used to pick a
            /// victim when more threads appear than there are slots.
            last_sequence: u64 = 0,
        };

        pub const Window = struct {
            /// Retained entries for the queried thread.
            thread_entries: usize,
            /// Capacity available to any single thread.
            thread_capacity: usize,
            /// Retained entries across all threads.
            total_entries: usize,
            /// Threads currently holding a slot.
            live_threads: usize,
            /// Slots available in total.
            slot_capacity: usize,
            /// A thread was evicted to make room at some point, so the queried
            /// thread's history may have been discarded and restarted.
            evictions: u64,

            pub fn reaches(self: Window) bool {
                return self.thread_entries != 0;
            }

            /// True when the thread has filled its ring, i.e. older evidence
            /// has been overwritten and "not found" may mean "not retained".
            pub fn saturated(self: Window) bool {
                return self.thread_entries >= self.thread_capacity;
            }
        };

        slots: []Slot,
        storage: []Entry,
        thread_capacity: usize,
        sequence: u64 = 0,
        evictions: u64 = 0,

        pub fn init(
            allocator: std.mem.Allocator,
            slot_count: usize,
            thread_capacity: usize,
        ) !Self {
            const storage = try allocator.alloc(Entry, slot_count * thread_capacity);
            errdefer allocator.free(storage);
            const slots = try allocator.alloc(Slot, slot_count);
            for (slots, 0..) |*slot, i| {
                slot.* = .{
                    .ring = Ring.init(storage[i * thread_capacity ..][0..thread_capacity]),
                };
            }
            return .{
                .slots = slots,
                .storage = storage,
                .thread_capacity = thread_capacity,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.slots);
            allocator.free(self.storage);
            self.slots = &.{};
            self.storage = &.{};
        }

        fn findSlot(self: *Self, thread: u64) ?*Slot {
            for (self.slots) |*slot| {
                if (slot.thread == thread) return slot;
            }
            return null;
        }

        fn findSlotConst(self: *const Self, thread: u64) ?*const Slot {
            for (self.slots) |*slot| {
                if (slot.thread == thread) return slot;
            }
            return null;
        }

        /// Slot for `thread`, claiming a free one or evicting the
        /// least-recently-used. Eviction is counted and surfaced in `Window`,
        /// because a thread whose history was discarded and restarted must not
        /// be reported the same way as one that simply has short history.
        fn slotFor(self: *Self, thread: u64) ?*Slot {
            if (self.slots.len == 0) return null;
            if (self.findSlot(thread)) |slot| return slot;

            var victim: *Slot = &self.slots[0];
            for (self.slots) |*slot| {
                if (slot.thread == unassigned) {
                    victim = slot;
                    break;
                }
                if (slot.last_sequence < victim.last_sequence) victim = slot;
            }
            if (victim.thread != unassigned) self.evictions +|= 1;
            victim.thread = thread;
            victim.ring.reset();
            return victim;
        }

        pub fn record(self: *Self, thread: u64, entry: Entry) void {
            const slot = self.slotFor(thread) orelse return;
            self.sequence +|= 1;
            slot.last_sequence = self.sequence;
            slot.ring.push(entry);
        }

        pub fn countFor(self: *const Self, thread: u64) usize {
            const slot = self.findSlotConst(thread) orelse return 0;
            return slot.ring.count();
        }

        pub fn totalCount(self: *const Self) usize {
            var total: usize = 0;
            for (self.slots) |slot| total += slot.ring.count();
            return total;
        }

        pub fn liveThreads(self: *const Self) usize {
            var live: usize = 0;
            for (self.slots) |slot| {
                if (slot.thread != unassigned) live += 1;
            }
            return live;
        }

        pub fn windowFor(self: *const Self, thread: u64) Window {
            return .{
                .thread_entries = self.countFor(thread),
                .thread_capacity = self.thread_capacity,
                .total_entries = self.totalCount(),
                .live_threads = self.liveThreads(),
                .slot_capacity = self.slots.len,
                .evictions = self.evictions,
            };
        }

        /// Chronological access within one thread: 0 is the oldest retained.
        pub fn chronological(self: *const Self, thread: u64, ordinal: usize) ?Entry {
            const slot = self.findSlotConst(thread) orelse return null;
            return slot.ring.chronological(ordinal);
        }

        /// Reverse-chronological access within one thread: 0 is the newest.
        pub fn recent(self: *const Self, thread: u64, ordinal: usize) ?Entry {
            const slot = self.findSlotConst(thread) orelse return null;
            return slot.ring.recent(ordinal);
        }

        pub fn latestFor(self: *const Self, thread: u64) ?Entry {
            const slot = self.findSlotConst(thread) orelse return null;
            return slot.ring.latest();
        }

        /// Newest entry across all threads, for whole-run dumps that do not
        /// care which thread produced it.
        pub fn latestAny(self: *const Self) ?Entry {
            var best: ?Entry = null;
            var best_sequence: u64 = 0;
            for (self.slots) |slot| {
                if (slot.thread == unassigned) continue;
                if (slot.ring.latest()) |entry| {
                    if (best == null or slot.last_sequence > best_sequence) {
                        best = entry;
                        best_sequence = slot.last_sequence;
                    }
                }
            }
            return best;
        }

        /// Iterate every retained entry of every thread. Order is per-thread
        /// chronological, threads in slot order — deliberately *not* claimed to
        /// be globally chronological, because per-thread rings cannot recover a
        /// global order without a per-entry sequence number. Callers that need
        /// causal order must query a single thread.
        pub const AllIterator = struct {
            history: *const Self,
            slot_index: usize = 0,
            ordinal: usize = 0,

            pub fn next(self: *AllIterator) ?Entry {
                while (self.slot_index < self.history.slots.len) {
                    const slot = self.history.slots[self.slot_index];
                    if (slot.thread != unassigned) {
                        if (slot.ring.chronological(self.ordinal)) |entry| {
                            self.ordinal += 1;
                            return entry;
                        }
                    }
                    self.slot_index += 1;
                    self.ordinal = 0;
                }
                return null;
            }
        };

        pub fn iterateAll(self: *const Self) AllIterator {
            return .{ .history = self };
        }
    };
}

const TestEntry = struct { thread: u64 = 0, value: u64 = 0 };
const TestHistory = History(TestEntry);

test "a noisy thread cannot shrink another thread's window" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 4, 8);
    defer history.deinit(allocator);

    history.record(1, .{ .thread = 1, .value = 0xAA });
    // The shared ring this replaces would have evicted thread 1's only entry
    // after eight pushes from thread 2. Partitioned, it cannot.
    var i: u64 = 0;
    while (i < 64) : (i += 1) history.record(2, .{ .thread = 2, .value = i });

    try std.testing.expectEqual(@as(usize, 1), history.countFor(1));
    try std.testing.expectEqual(@as(u64, 0xAA), history.latestFor(1).?.value);
    try std.testing.expectEqual(@as(usize, 8), history.countFor(2));
}

test "window reports reach, capacity and saturation" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 2, 4);
    defer history.deinit(allocator);

    const empty = history.windowFor(9);
    try std.testing.expect(!empty.reaches());
    try std.testing.expectEqual(@as(usize, 0), empty.thread_entries);

    var i: u64 = 0;
    while (i < 3) : (i += 1) history.record(9, .{ .thread = 9, .value = i });
    const partial = history.windowFor(9);
    try std.testing.expect(partial.reaches());
    try std.testing.expect(!partial.saturated());

    history.record(9, .{ .thread = 9, .value = 99 });
    const full = history.windowFor(9);
    try std.testing.expect(full.saturated());
    try std.testing.expectEqual(@as(usize, 4), full.thread_capacity);
    try std.testing.expectEqual(@as(usize, 1), full.live_threads);
}

test "eviction is counted so a restarted history is not read as a short one" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 2, 4);
    defer history.deinit(allocator);

    history.record(1, .{ .thread = 1 });
    history.record(2, .{ .thread = 2 });
    try std.testing.expectEqual(@as(u64, 0), history.windowFor(1).evictions);

    // A third thread must displace the least-recently-used slot.
    history.record(3, .{ .thread = 3 });
    try std.testing.expectEqual(@as(u64, 1), history.evictions);
    try std.testing.expectEqual(@as(usize, 0), history.countFor(1));
    try std.testing.expectEqual(@as(usize, 1), history.countFor(3));
}

test "per-thread chronological order is independent of interleaving" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 4, 8);
    defer history.deinit(allocator);

    var i: u64 = 0;
    while (i < 5) : (i += 1) {
        history.record(1, .{ .thread = 1, .value = i });
        history.record(2, .{ .thread = 2, .value = 100 + i });
    }
    try std.testing.expectEqual(@as(u64, 0), history.chronological(1, 0).?.value);
    try std.testing.expectEqual(@as(u64, 4), history.chronological(1, 4).?.value);
    try std.testing.expectEqual(@as(u64, 100), history.chronological(2, 0).?.value);
    try std.testing.expectEqual(@as(u64, 104), history.recent(2, 0).?.value);
}

test "zero slots degrades to recording nothing rather than trapping" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 0, 8);
    defer history.deinit(allocator);
    history.record(1, .{ .thread = 1 });
    try std.testing.expectEqual(@as(usize, 0), history.totalCount());
    try std.testing.expect(!history.windowFor(1).reaches());
}
