//! Bounded, thread-affine Win32 message queue shared by parallel PE workers.
//!
//! A message posted to an HWND belongs to the guest thread that created the
//! window. The queue stores that owner with the message so a different worker
//! cannot consume a UI callback while racing the intended message pump.

const std = @import("std");
const concurrency = @import("concurrency");

pub const capacity: usize = 512;

pub const Message = struct {
    hwnd: u64 = 0,
    message: u32 = 0,
    wparam: u64 = 0,
    lparam: u64 = 0,
    /// Guest thread that called PostMessage, retained for handoff reports.
    posted_by_thread_id: u64 = 0,
    /// Zero denotes a thread-wide/synthetic message with no HWND owner.
    owner_thread_id: u64 = 0,
};

pub const Snapshot = struct {
    count: usize = 0,
    high_water: usize = 0,
    posts: u64 = 0,
    deliveries: u64 = 0,
    drops: u64 = 0,
    affinity_skips: u64 = 0,
    last_posted_by_thread_id: u64 = 0,
    last_post_owner_thread_id: u64 = 0,
    last_delivery_by_thread_id: u64 = 0,
    last_delivery_owner_thread_id: u64 = 0,
    last_affinity_skip_by_thread_id: u64 = 0,
    last_affinity_skip_owner_thread_id: u64 = 0,
};

pub const Queue = struct {
    mutex: concurrency.mutex.LeanMutex = .{},
    entries: [capacity]Message = [_]Message{.{}} ** capacity,
    head: usize = 0,
    tail: usize = 0,
    live_count: usize = 0,
    published_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    high_water: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    posts: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    deliveries: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    drops: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    affinity_skips: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_posted_by_thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_post_owner_thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_delivery_by_thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_delivery_owner_thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_affinity_skip_by_thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_affinity_skip_owner_thread_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Publishes one message. The bounded capacity keeps a guest from
    /// turning PostMessage into unbounded host allocation.
    pub fn post(self: *Queue, message: Message) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.live_count == capacity) {
            _ = self.drops.fetchAdd(1, .monotonic);
            return false;
        }
        self.entries[self.tail] = message;
        self.tail = (self.tail + 1) % capacity;
        self.live_count += 1;
        self.published_count.store(self.live_count, .release);
        _ = self.high_water.fetchMax(self.live_count, .monotonic);
        self.last_posted_by_thread_id.store(message.posted_by_thread_id, .monotonic);
        self.last_post_owner_thread_id.store(message.owner_thread_id, .monotonic);
        _ = self.posts.fetchAdd(1, .monotonic);
        return true;
    }

    /// Records a rejected post that failed before it reached the queue, such
    /// as an invalid HWND.
    pub fn reject(self: *Queue) void {
        _ = self.drops.fetchAdd(1, .monotonic);
    }

    /// Lock-free occupancy query for scheduler and progress checks.
    pub fn count(self: *const Queue) usize {
        return self.published_count.load(.acquire);
    }

    pub fn snapshot(self: *const Queue) Snapshot {
        return .{
            .count = self.published_count.load(.acquire),
            .high_water = self.high_water.load(.acquire),
            .posts = self.posts.load(.acquire),
            .deliveries = self.deliveries.load(.acquire),
            .drops = self.drops.load(.acquire),
            .affinity_skips = self.affinity_skips.load(.acquire),
            .last_posted_by_thread_id = self.last_posted_by_thread_id.load(.acquire),
            .last_post_owner_thread_id = self.last_post_owner_thread_id.load(.acquire),
            .last_delivery_by_thread_id = self.last_delivery_by_thread_id.load(.acquire),
            .last_delivery_owner_thread_id = self.last_delivery_owner_thread_id.load(.acquire),
            .last_affinity_skip_by_thread_id = self.last_affinity_skip_by_thread_id.load(.acquire),
            .last_affinity_skip_owner_thread_id = self.last_affinity_skip_owner_thread_id.load(.acquire),
        };
    }

    /// `remove=false` is PeekMessage: it observes but does not consume the
    /// message. Matching and ownership checks happen under the same lock as
    /// post/removal, so parallel pumps cannot consume one entry twice.
    pub fn take(
        self: *Queue,
        filter_hwnd: u64,
        minimum: u64,
        maximum: u64,
        caller_thread_id: u64,
        enforce_thread_affinity: bool,
        remove: bool,
    ) ?Message {
        const minimum_message: u32 = @truncate(minimum);
        const maximum_message: u32 = @truncate(maximum);
        if (minimum_message > maximum_message and !(minimum_message == 0 and maximum_message == 0)) return null;

        self.mutex.lock();
        defer self.mutex.unlock();
        for (0..self.live_count) |offset| {
            const index = (self.head + offset) % capacity;
            const message = self.entries[index];
            if (!matches(message, filter_hwnd, minimum_message, maximum_message)) continue;
            if (enforce_thread_affinity and message.owner_thread_id != 0 and message.owner_thread_id != caller_thread_id) {
                if (remove) {
                    _ = self.affinity_skips.fetchAdd(1, .monotonic);
                    self.last_affinity_skip_by_thread_id.store(caller_thread_id, .monotonic);
                    self.last_affinity_skip_owner_thread_id.store(message.owner_thread_id, .monotonic);
                }
                continue;
            }
            if (!remove) return message;

            var shift = offset;
            while (shift + 1 < self.live_count) : (shift += 1) {
                const current = (self.head + shift) % capacity;
                const next = (self.head + shift + 1) % capacity;
                self.entries[current] = self.entries[next];
            }
            self.tail = (self.tail + capacity - 1) % capacity;
            self.entries[self.tail] = .{};
            self.live_count -= 1;
            self.published_count.store(self.live_count, .release);
            self.last_delivery_by_thread_id.store(caller_thread_id, .monotonic);
            self.last_delivery_owner_thread_id.store(message.owner_thread_id, .monotonic);
            _ = self.deliveries.fetchAdd(1, .monotonic);
            return message;
        }
        return null;
    }

    pub fn matches(message: Message, filter_hwnd: u64, minimum: u32, maximum: u32) bool {
        if (filter_hwnd != 0 and message.hwnd != filter_hwnd) return false;
        if (minimum == 0 and maximum == 0) return true;
        return message.message >= minimum and message.message <= maximum;
    }
};

test "thread-affine messages remain queued for their window owner" {
    var queue: Queue = .{};
    try std.testing.expect(queue.post(.{ .hwnd = 0x13, .message = 0x400, .posted_by_thread_id = 8, .owner_thread_id = 7 }));

    try std.testing.expect(queue.take(0, 0, 0, 8, true, true) == null);
    try std.testing.expectEqual(@as(usize, 1), queue.count());
    try std.testing.expectEqual(@as(u64, 1), queue.snapshot().affinity_skips);
    try std.testing.expectEqual(@as(u64, 8), queue.snapshot().last_posted_by_thread_id);
    try std.testing.expectEqual(@as(u64, 7), queue.snapshot().last_affinity_skip_owner_thread_id);
    const delivered = queue.take(0, 0, 0, 7, true, true).?;
    try std.testing.expectEqual(@as(u64, 7), delivered.owner_thread_id);
    try std.testing.expectEqual(@as(usize, 0), queue.count());
    try std.testing.expectEqual(@as(u64, 7), queue.snapshot().last_delivery_by_thread_id);
    try std.testing.expectEqual(@as(u64, 7), queue.snapshot().last_delivery_owner_thread_id);
}

test "filters and peeks preserve the message order and delivery count" {
    var queue: Queue = .{};
    try std.testing.expect(queue.post(.{ .hwnd = 1, .message = 0x10 }));
    try std.testing.expect(queue.post(.{ .hwnd = 2, .message = 0x20 }));
    const peeked = queue.take(0, 0x20, 0x20, 1, false, false).?;
    try std.testing.expectEqual(@as(u64, 2), peeked.hwnd);
    try std.testing.expectEqual(@as(u64, 2), queue.count());
    try std.testing.expectEqual(@as(u64, 0), queue.snapshot().deliveries);
    const first = queue.take(0, 0, 0, 1, false, true).?;
    const second = queue.take(0, 0, 0, 1, false, true).?;
    try std.testing.expectEqual(@as(u64, 1), first.hwnd);
    try std.testing.expectEqual(@as(u64, 2), second.hwnd);
    try std.testing.expectEqual(@as(u64, 2), queue.snapshot().deliveries);
}

test "messages posted concurrently publish exactly once" {
    const Producer = struct {
        queue: *Queue,
        base: u64,

        fn run(self: *@This()) void {
            for (0..100) |offset| {
                if (!self.queue.post(.{ .hwnd = self.base + offset, .message = 0x400 })) unreachable;
            }
        }
    };

    var queue: Queue = .{};
    var producers: [4]Producer = undefined;
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        producers[index] = .{ .queue = &queue, .base = index * 100 };
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{&producers[index]});
    }
    for (threads) |thread| thread.join();

    try std.testing.expectEqual(@as(usize, 400), queue.count());
    var removed: usize = 0;
    while (queue.take(0, 0, 0, 1, false, true) != null) removed += 1;
    const stats = queue.snapshot();
    try std.testing.expectEqual(@as(usize, 400), removed);
    try std.testing.expectEqual(@as(u64, 400), stats.posts);
    try std.testing.expectEqual(@as(u64, 400), stats.deliveries);
    try std.testing.expectEqual(@as(u64, 0), stats.drops);
}

test "a full message queue rejects without corrupting existing entries" {
    var queue: Queue = .{};
    for (0..capacity) |index| {
        try std.testing.expect(queue.post(.{ .hwnd = index + 1, .message = 0x400 }));
    }
    try std.testing.expect(!queue.post(.{ .hwnd = 0xFFFF, .message = 0x400 }));
    try std.testing.expectEqual(@as(usize, capacity), queue.count());
    try std.testing.expectEqual(@as(u64, 1), queue.snapshot().drops);
    try std.testing.expectEqual(@as(u64, 1), queue.take(0, 0, 0, 1, false, true).?.hwnd);
}
