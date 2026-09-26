//! A mutex that sleeps instead of spinning, and says who holds it.
//!
//! Three states on one futex word: unlocked, locked, and locked with
//! sleepers. The uncontended lock and unlock are one atomic each. A
//! contended lock spins for a moment - most Rosette critical sections are a
//! few hundred nanoseconds - and then parks through `park.zig`, which keeps
//! the host main thread serving its dispatch queue while it waits.
//!
//! Every mutex records its holder's thread id and counts its contention, so
//! a stall report can name the thread a waiter is behind and an exit report
//! can say which lock the run fought over. The processor's previous lock was
//! a bare spin lock: a waiter burned a core for as long as the holder took,
//! including while the holder was itself asleep.

const std = @import("std");
const futex = @import("futex.zig");
const park = @import("park.zig");

const unlocked: u32 = 0;
const locked: u32 = 1;
const locked_with_sleepers: u32 = 2;

threadlocal var cached_thread_id: u64 = 0;

/// The calling thread's id, cached: a mutex records its holder on every
/// acquisition.
pub fn currentThreadId() u64 {
    if (cached_thread_id == 0) cached_thread_id = @intCast(std.Thread.getCurrentId());
    return cached_thread_id;
}

pub const Mutex = struct {
    state: futex.Word = futex.Word.init(unlocked),
    /// Thread id of the holder, zero when unlocked. Diagnostic only.
    holder: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// What this lock protects, for park labels and reports.
    label: [*:0]const u8 = "mutex",
    stats: Stats = .{},

    pub const Stats = struct {
        acquisitions: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        contended: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        parks: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        wait_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        longest_wait_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    };

    pub fn init(label: [*:0]const u8) Mutex {
        return .{ .label = label };
    }

    pub fn tryLock(self: *Mutex) bool {
        if (self.state.cmpxchgStrong(unlocked, locked, .acquire, .monotonic) != null) return false;
        self.noteAcquired();
        return true;
    }

    pub fn lock(self: *Mutex) void {
        if (self.state.cmpxchgWeak(unlocked, locked, .acquire, .monotonic) == null) {
            self.noteAcquired();
            return;
        }
        self.lockContended();
    }

    pub fn unlock(self: *Mutex) void {
        self.holder.store(0, .monotonic);
        if (self.state.swap(unlocked, .release) == locked_with_sleepers) futex.wake(&self.state, .one);
    }

    /// Whether the calling thread holds this mutex. Diagnostic: the holder
    /// field is written after acquisition and cleared before release.
    pub fn heldByCurrentThread(self: *const Mutex) bool {
        return self.holder.load(.monotonic) == currentThreadId();
    }

    fn noteAcquired(self: *Mutex) void {
        self.holder.store(currentThreadId(), .monotonic);
        _ = self.stats.acquisitions.fetchAdd(1, .monotonic);
    }

    fn lockContended(self: *Mutex) void {
        const started = futex.monotonicNanoseconds();
        _ = self.stats.contended.fetchAdd(1, .monotonic);
        var backoff: park.Backoff = .{};
        while (backoff.spin()) {
            if (self.state.load(.monotonic) == unlocked and
                self.state.cmpxchgWeak(unlocked, locked, .acquire, .monotonic) == null)
            {
                self.finishContended(started);
                return;
            }
        }
        // Announce a sleeper by setting the third state; whoever unlocks
        // then wakes one. Taking the lock this way leaves the state at
        // `locked_with_sleepers`, which costs at most one spurious wake.
        while (self.state.swap(locked_with_sleepers, .acquire) != unlocked) {
            _ = self.stats.parks.fetchAdd(1, .monotonic);
            park.park(&self.state, locked_with_sleepers, null, self.label);
        }
        self.finishContended(started);
    }

    fn finishContended(self: *Mutex, started: u64) void {
        self.noteAcquired();
        const waited = futex.monotonicNanoseconds() -| started;
        _ = self.stats.wait_ns.fetchAdd(waited, .monotonic);
        _ = self.stats.longest_wait_ns.fetchMax(waited, .monotonic);
    }
};

/// The same algorithm without holder tracking or statistics, for locks taken
/// on a per-instruction path and striped so they are rarely contended. One
/// cache line each, so neighbouring stripes do not share a line.
pub const LeanMutex = struct {
    state: futex.Word align(128) = futex.Word.init(unlocked),

    pub fn tryLock(self: *LeanMutex) bool {
        return self.state.cmpxchgStrong(unlocked, locked, .acquire, .monotonic) == null;
    }

    pub fn lock(self: *LeanMutex) void {
        if (self.state.cmpxchgWeak(unlocked, locked, .acquire, .monotonic) == null) return;
        var backoff: park.Backoff = .{};
        while (backoff.spin()) {
            if (self.state.load(.monotonic) == unlocked and
                self.state.cmpxchgWeak(unlocked, locked, .acquire, .monotonic) == null) return;
        }
        while (self.state.swap(locked_with_sleepers, .acquire) != unlocked) {
            park.park(&self.state, locked_with_sleepers, null, "lean mutex");
        }
    }

    pub fn unlock(self: *LeanMutex) void {
        if (self.state.swap(unlocked, .release) == locked_with_sleepers) futex.wake(&self.state, .one);
    }
};

test "a lean mutex excludes contending threads" {
    const Shared = struct {
        mutex: LeanMutex = .{},
        value: u64 = 0,
        fn run(shared: *@This()) void {
            for (0..20_000) |_| {
                shared.mutex.lock();
                const seen = shared.value;
                std.mem.doNotOptimizeAway(seen);
                shared.value = seen + 1;
                shared.mutex.unlock();
            }
        }
    };
    var shared: Shared = .{};
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Shared.run, .{&shared});
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(u64, 80_000), shared.value);
}

test "an uncontended lock and unlock record the holder" {
    var mutex = Mutex.init("test");
    try std.testing.expect(mutex.tryLock());
    try std.testing.expect(mutex.heldByCurrentThread());
    try std.testing.expect(!mutex.tryLock());
    mutex.unlock();
    try std.testing.expect(!mutex.heldByCurrentThread());
    mutex.lock();
    mutex.unlock();
    try std.testing.expectEqual(@as(u64, 2), mutex.stats.acquisitions.load(.monotonic));
}

test "contending threads exclude each other and all finish" {
    const Shared = struct {
        mutex: Mutex = Mutex.init("counter"),
        value: u64 = 0,

        fn run(shared: *@This()) void {
            for (0..20_000) |_| {
                shared.mutex.lock();
                // A non-atomic read-modify-write: a lost update means two
                // holders overlapped.
                const seen = shared.value;
                std.mem.doNotOptimizeAway(seen);
                shared.value = seen + 1;
                shared.mutex.unlock();
            }
        }
    };
    var shared: Shared = .{};
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Shared.run, .{&shared});
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(u64, 80_000), shared.value);
}

test "a waiter sleeps while the holder works, and wakes when it unlocks" {
    const Shared = struct {
        mutex: Mutex = Mutex.init("sleeper"),
        acquired: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn waiter(shared: *@This()) void {
            shared.mutex.lock();
            shared.acquired.store(true, .release);
            shared.mutex.unlock();
        }
    };
    var shared: Shared = .{};
    shared.mutex.lock();
    const thread = try std.Thread.spawn(.{}, Shared.waiter, .{&shared});
    // Long enough for the waiter to exhaust its spin and park.
    var request = std.c.timespec{ .sec = 0, .nsec = 10 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&request, null);
    try std.testing.expect(!shared.acquired.load(.acquire));
    shared.mutex.unlock();
    thread.join();
    try std.testing.expect(shared.acquired.load(.acquire));
    try std.testing.expect(shared.mutex.stats.contended.load(.monotonic) >= 1);
}
