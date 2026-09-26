//! The address-stripe coordinator for guest memory once guest executors can
//! overlap on different host threads, and the per-host-thread switch that
//! says whether they do.
//!
//! Every guest access in coordinated mode takes the stripe of each cache line
//! it touches, so a LOCK-prefixed update stays indivisible relative to plain
//! and mixed-width accesses by a peer executor. Loads share a stripe; stores
//! and locked updates take it exclusively. Serial (cooperative) execution has
//! no peer executor, so it takes no stripe at all.

const std = @import("std");
const builtin = @import("builtin");

pub const stripe_count: usize = 1024;
pub const cache_line_shift: u6 = 6;
pub const cache_line_bytes: usize = @as(usize, 1) << cache_line_shift;

const stripe_writer: u32 = 1 << 31;
const stripe_writer_pending: u32 = 1 << 30;
const stripe_reader_mask: u32 = stripe_writer_pending - 1;

const AccessStripe = struct {
    // Keep unrelated guest cache lines from contending on the same host lock
    // cache line when native guest executors run on different cores. Most
    // guest memory traffic is read-only (instruction fetches, texture and
    // object data); a shared-reader state lets those accesses proceed without
    // serializing each other. Stores and LOCK operations retain exclusivity.
    lock: std.atomic.Value(u32) align(128) = std.atomic.Value(u32).init(0),
};

var stripes = [_]AccessStripe{.{}} ** stripe_count;

/// Whether the calling host thread's guest accesses must coordinate with a
/// peer executor. Set by the executor for the duration of a step.
threadlocal var coordinated_guest_access: bool = false;

pub fn setCoordinated(enabled: bool) bool {
    const previous = coordinated_guest_access;
    coordinated_guest_access = enabled;
    return previous;
}

pub fn coordinated() bool {
    return coordinated_guest_access;
}

fn stripeFor(address: usize) usize {
    var key: u64 = @intCast(address >> cache_line_shift);
    key ^= key >> 17;
    key *%= 0x9E37_79B9_7F4A_7C15;
    key ^= key >> 29;
    return @intCast(key & (stripe_count - 1));
}

pub const AccessGuard = struct {
    first: ?usize = null,
    second: ?usize = null,
    shared: bool = false,

    /// Exclusive guard in the calling thread's current mode.
    pub fn lock(bytes: []const u8) AccessGuard {
        return lockMode(bytes, coordinated_guest_access, false);
    }

    /// A guard over `bytes`, which must span at most two cache lines. No
    /// stripe is taken unless `coordinated_mode` is set.
    pub fn lockMode(bytes: []const u8, coordinated_mode: bool, shared: bool) AccessGuard {
        if (!coordinated_mode or bytes.len == 0) return .{};
        const start = @intFromPtr(bytes.ptr);
        const end = start + (bytes.len - 1);
        const first_line = start >> cache_line_shift;
        const last_line = end >> cache_line_shift;
        var first = stripeFor(start);
        var second: ?usize = if (first_line == last_line) null else stripeFor(end);
        if (second) |stripe| {
            if (stripe == first) {
                second = null;
            } else if (stripe < first) {
                // A fixed order: two executors locking the same pair of
                // stripes from opposite ends cannot deadlock.
                first = stripe;
                second = stripeFor(start);
            }
        }
        lockStripe(first, shared);
        if (second) |stripe| lockStripe(stripe, shared);
        return .{ .first = first, .second = second, .shared = shared };
    }

    pub fn unlock(self: AccessGuard) void {
        if (self.second) |stripe| unlockStripe(stripe, self.shared);
        if (self.first) |stripe| unlockStripe(stripe, self.shared);
    }

    pub fn holdsAny(self: AccessGuard) bool {
        return self.first != null;
    }
};

fn lockStripe(index: usize, shared: bool) void {
    const stripe = &stripes[index].lock;
    if (shared) {
        while (true) {
            const state = stripe.load(.acquire);
            // A queued writer closes reader admission so a continuous stream
            // of guest loads cannot starve a guest store or locked update.
            if (state & (stripe_writer | stripe_writer_pending) != 0 or
                state & stripe_reader_mask == stripe_reader_mask)
            {
                std.atomic.spinLoopHint();
                continue;
            }
            if (stripe.cmpxchgWeak(state, state + 1, .acquire, .monotonic) == null) return;
        }
    }

    while (true) {
        const state = stripe.load(.acquire);
        if (state & stripe_writer != 0) {
            std.atomic.spinLoopHint();
            continue;
        }
        if (state & stripe_writer_pending == 0) {
            // Stop new readers before waiting for current readers to drain.
            _ = stripe.cmpxchgWeak(state, state | stripe_writer_pending, .acq_rel, .acquire);
            continue;
        }
        if (state & stripe_reader_mask == 0 and
            stripe.cmpxchgWeak(state, stripe_writer, .acquire, .monotonic) == null)
        {
            return;
        }
        std.atomic.spinLoopHint();
    }
}

fn unlockStripe(index: usize, shared: bool) void {
    const stripe = &stripes[index].lock;
    if (shared) {
        const prior = stripe.fetchSub(1, .release);
        std.debug.assert(prior & stripe_reader_mask != 0);
    } else {
        stripe.store(0, .release);
    }
}

/// The raw lock word of the stripe that `lockMode` would take first for
/// `bytes`. Tests only.
fn stripeWord(bytes: []const u8) u32 {
    return stripes[stripeFor(@intFromPtr(bytes.ptr))].lock.load(.acquire);
}

pub fn littleEndian(value: anytype) @TypeOf(value) {
    return if (builtin.target.cpu.arch.endian() == .little) value else @byteSwap(value);
}

pub fn fullBarrier() void {
    if (comptime builtin.target.cpu.arch == .aarch64) {
        asm volatile ("dmb ish" ::: .{ .memory = true });
    } else if (comptime builtin.target.cpu.arch == .x86_64) {
        asm volatile ("mfence" ::: .{ .memory = true });
    } else {
        std.atomic.fence(.seq_cst);
    }
}

test "parallel access stripes do not false-share a host cache line" {
    try std.testing.expectEqual(@as(usize, 128), @alignOf(AccessStripe));
    try std.testing.expect(@sizeOf(AccessStripe) >= 128);
}

test "parallel guest reads share a stripe and writes take it exclusively" {
    var bytes: [64]u8 align(64) = [_]u8{0} ** 64;
    {
        const first = AccessGuard.lockMode(bytes[0..8], true, true);
        defer first.unlock();
        try std.testing.expectEqual(@as(u32, 1), stripeWord(bytes[0..8]));

        {
            const second = AccessGuard.lockMode(bytes[0..8], true, true);
            defer second.unlock();
            try std.testing.expectEqual(first.first.?, second.first.?);
            try std.testing.expectEqual(@as(u32, 2), stripeWord(bytes[0..8]));
        }
        try std.testing.expectEqual(@as(u32, 1), stripeWord(bytes[0..8]));
    }

    const writer = AccessGuard.lockMode(bytes[0..8], true, false);
    defer writer.unlock();
    try std.testing.expectEqual(stripe_writer, stripeWord(bytes[0..8]));
}

test "serial mode takes no stripe" {
    var bytes: [16]u8 align(16) = [_]u8{0} ** 16;
    const guard = AccessGuard.lockMode(bytes[0..8], false, false);
    try std.testing.expect(!guard.holdsAny());
    guard.unlock();
    try std.testing.expectEqual(@as(u32, 0), stripeWord(bytes[0..8]));
}

test "a guard spanning two cache lines takes both stripes in a fixed order" {
    var bytes: [128]u8 align(64) = [_]u8{0} ** 128;
    const guard = AccessGuard.lockMode(bytes[60..68], true, false);
    defer guard.unlock();
    if (guard.second) |second| {
        try std.testing.expect(guard.first.? < second);
    }
}
