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

        /// What the history is allowed to record.
        ///
        /// This exists because the previous design had a `trace_ring_enabled`
        /// boolean that was declared, defaulted to false, and **never assigned
        /// anywhere**. Every history-based recognizer therefore ran against an
        /// empty ring for the entire life of the code, and reported "no
        /// evidence retained" — which reads as a fact about the program and was
        /// actually a fact about a switch nobody turned on. A policy that
        /// travels with the window makes that indistinguishability impossible.
        pub const Policy = enum {
            /// Record nothing. `Window.reaches()` is false and stays false.
            disabled,
            /// Record only where the recognizers actually ask questions:
            /// JIT-generated code outside the host image. Host code dominates
            /// the step count by orders of magnitude, so this keeps the tape
            /// affordable while making it deep exactly where it is consulted.
            generated_code_only,
            /// Record everything.
            all,
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
            /// What recording was permitted while this window was filling.
            policy: Policy,
            /// Entries accepted, and entries the policy declined.
            recorded: u64,
            skipped: u64,

            /// An empty window means different things depending on why. Callers
            /// must not report "no evidence" when the answer is "no recording".
            pub fn emptyBecauseDisabled(self: Window) bool {
                return self.thread_entries == 0 and self.policy == .disabled;
            }

            /// Whether this thread's window is empty *because the policy
            /// declined its instructions*.
            ///
            /// `recorded` counts the whole process; `thread_entries` counts one
            /// thread. Requiring `recorded == 0` therefore made this predicate
            /// unreachable as soon as any *other* thread recorded anything —
            /// and under `generated_code_only` the JIT threads always do. A
            /// native fault on a UI or callback thread then reported "nothing
            /// was retained for this thread yet", which reads as a transient
            /// and is actually permanent: that thread runs host-image code, and
            /// host-image code is exactly what the policy filters. The question
            /// this answers is about one thread, so every term in it has to be
            /// about that thread.
            pub fn emptyBecauseFiltered(self: Window) bool {
                return self.thread_entries == 0 and
                    self.policy == .generated_code_only and
                    self.skipped != 0;
            }

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
        policy: Policy = .generated_code_only,
        /// See `findSlot`. `slots.len` (an out-of-range value) means "no memo".
        last_slot_index: usize = std.math.maxInt(usize),
        recorded: u64 = 0,
        skipped: u64 = 0,

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

        /// F11 (throughput audit): one-entry memo in front of the slot scan.
        ///
        /// `record` runs per instruction under the `generated_code_only`
        /// policy, and every call walked all 24 slots looking for the active
        /// thread. Guest threads switch cooperatively and rarely, so the last
        /// answer is almost always still the right one — and this becomes a
        /// per-step cost the moment generated code stops being 2% of the run,
        /// which is exactly what a working title would do.
        ///
        /// The memo stores an index, and is validated against the slot's own
        /// `thread` before use, so a slot that was reassigned (eviction) can
        /// never be returned for the wrong thread.
        fn findSlot(self: *Self, thread: u64) ?*Slot {
            if (self.last_slot_index < self.slots.len) {
                const cached = &self.slots[self.last_slot_index];
                if (cached.thread == thread) return cached;
            }
            for (self.slots, 0..) |*slot, index| {
                if (slot.thread == thread) {
                    self.last_slot_index = index;
                    return slot;
                }
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
            self.last_slot_index = (@intFromPtr(victim) - @intFromPtr(self.slots.ptr)) / @sizeOf(Slot);
            return victim;
        }

        pub fn record(self: *Self, thread: u64, entry: Entry) void {
            if (self.policy == .disabled) {
                self.skipped +|= 1;
                return;
            }
            const slot = self.slotFor(thread) orelse {
                self.skipped +|= 1;
                return;
            };
            self.sequence +|= 1;
            self.recorded +|= 1;
            slot.last_sequence = self.sequence;
            slot.ring.push(entry);
        }

        /// Record that the caller's policy gate declined an instruction. Keeps
        /// `skipped` meaningful when the filtering happens at the call site.
        pub fn noteFiltered(self: *Self) void {
            self.skipped +|= 1;
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
                .policy = self.policy,
                .recorded = self.recorded,
                .skipped = self.skipped,
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

        /// Copy the most recent entries for `thread` into `dest`, oldest-first,
        /// and return how many were written.
        ///
        /// The destination's own length is the bound, so a caller cannot
        /// overflow its buffer by asking for a count from somewhere else. That
        /// is not hypothetical: the exit-diagnostics dump sized its stack array
        /// from `TRACE_BUFFER_LEN` (256) while taking its loop count from
        /// `countFor()` (512 after partitioning), and wrote 256 entries past the
        /// end of a stack buffer — corrupting the report and then killing the
        /// process with SIGSEGV *while producing crash diagnostics*. Two
        /// independent constants that had to agree, with nothing enforcing it.
        ///
        /// Most-recent rather than oldest: when a window cannot hold everything,
        /// the instructions nearest the fault are the ones worth keeping.
        pub fn copyRecentInto(self: *const Self, thread: u64, dest: []Entry) usize {
            if (dest.len == 0) return 0;
            const available = self.countFor(thread);
            const wanted = @min(available, dest.len);
            var index: usize = 0;
            while (index < wanted) : (index += 1) {
                // `wanted - 1 - index` counts back from the newest, so the
                // destination ends up oldest-first.
                dest[index] = self.recent(thread, wanted - 1 - index) orelse break;
            }
            return index;
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

test "an empty window distinguishes disabled from filtered from genuinely empty" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 4, 8);
    defer history.deinit(allocator);

    // Genuinely empty: recording allowed, nothing happened yet.
    const fresh = history.windowFor(1);
    try std.testing.expect(!fresh.reaches());
    try std.testing.expect(!fresh.emptyBecauseDisabled());
    try std.testing.expect(!fresh.emptyBecauseFiltered());

    // Filtered: the call site's policy gate declined every instruction.
    history.noteFiltered();
    try std.testing.expect(history.windowFor(1).emptyBecauseFiltered());

    // Disabled: the whole mechanism is off. This is the state the old
    // `trace_ring_enabled` boolean was stuck in, indistinguishable from
    // "the program produced no evidence".
    history.policy = .disabled;
    history.record(1, .{ .thread = 1 });
    const off = history.windowFor(1);
    try std.testing.expect(off.emptyBecauseDisabled());
    try std.testing.expectEqual(@as(u64, 0), off.recorded);
}

test "copyRecentInto is bounded by the destination, not by the caller's count" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 2, 16);
    defer history.deinit(allocator);

    var i: u64 = 0;
    while (i < 16) : (i += 1) history.record(1, .{ .thread = 1, .value = i });
    try std.testing.expectEqual(@as(usize, 16), history.countFor(1));

    // A destination smaller than the retained count must not be overrun. The
    // exit-diagnostics dump did exactly this and wrote past a stack array.
    var small: [4]TestEntry = undefined;
    const written = history.copyRecentInto(1, &small);
    try std.testing.expectEqual(@as(usize, 4), written);
    // Oldest-first within the window, ending at the newest entry.
    try std.testing.expectEqual(@as(u64, 12), small[0].value);
    try std.testing.expectEqual(@as(u64, 15), small[3].value);
}

test "copyRecentInto handles empty history and empty destinations" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 2, 8);
    defer history.deinit(allocator);

    var dest: [4]TestEntry = undefined;
    try std.testing.expectEqual(@as(usize, 0), history.copyRecentInto(7, &dest));

    history.record(7, .{ .thread = 7, .value = 1 });
    var empty: [0]TestEntry = undefined;
    try std.testing.expectEqual(@as(usize, 0), history.copyRecentInto(7, &empty));
    try std.testing.expectEqual(@as(usize, 1), history.copyRecentInto(7, &dest));
}

test "zero slots degrades to recording nothing rather than trapping" {
    const allocator = std.testing.allocator;
    var history = try TestHistory.init(allocator, 0, 8);
    defer history.deinit(allocator);
    history.record(1, .{ .thread = 1 });
    try std.testing.expectEqual(@as(usize, 0), history.totalCount());
    try std.testing.expect(!history.windowFor(1).reaches());
}

test "a filtered thread is not reported as merely empty" {
    // The regression: `recorded` is process-wide and `thread_entries` is not.
    // A window with entries on other threads must still explain *this* thread's
    // emptiness as filtering, or a native fault reads as "nothing yet" forever.
    const window = History(u8).Window{
        .thread_entries = 0,
        .thread_capacity = 512,
        .total_entries = 111,
        .live_threads = 3,
        .slot_capacity = 8,
        .evictions = 0,
        .policy = .generated_code_only,
        .recorded = 111,
        .skipped = 662167987,
    };
    try std.testing.expect(window.emptyBecauseFiltered());
    try std.testing.expect(!window.emptyBecauseDisabled());
    try std.testing.expect(!window.reaches());
}

test "a disabled window is never reported as filtered" {
    const window = History(u8).Window{
        .thread_entries = 0,
        .thread_capacity = 512,
        .total_entries = 0,
        .live_threads = 0,
        .slot_capacity = 8,
        .evictions = 0,
        .policy = .disabled,
        .recorded = 0,
        .skipped = 12,
    };
    try std.testing.expect(window.emptyBecauseDisabled());
    try std.testing.expect(!window.emptyBecauseFiltered());
}

test "a thread with retained entries is neither disabled nor filtered" {
    const window = History(u8).Window{
        .thread_entries = 9,
        .thread_capacity = 512,
        .total_entries = 120,
        .live_threads = 3,
        .slot_capacity = 8,
        .evictions = 0,
        .policy = .generated_code_only,
        .recorded = 120,
        .skipped = 5,
    };
    try std.testing.expect(window.reaches());
    try std.testing.expect(!window.emptyBecauseFiltered());
    try std.testing.expect(!window.emptyBecauseDisabled());
}
