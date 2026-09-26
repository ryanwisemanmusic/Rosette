//! A bounded, executor-owned x86 store buffer.
//!
//! Stores retire into it in program order and become visible to memory in
//! FIFO order when it drains; a load by the owning executor forwards the
//! newest buffered byte for every address it covers. It is deliberately
//! allocation-free and must never be shared by two host executors at once.
//!
//! The first version indexed forwarding with a per-byte open-addressed hash
//! table: an 8-byte store cost eight probes and inserts, a drain eight probes
//! and tombstones, and whenever the buffer emptied it cleared the whole
//! 1,024-slot table - 24 KiB of memset, once per interpreted store in code
//! that stores every few instructions. On the 2026-09-24 Halo 3 run that was
//! 65.5% (`drainOne`) plus 15.9% (`enqueue`) of the only host thread that
//! runs guest code, and the instruction rate fell from ~300M/s to 6.5M/s.
//!
//! This version keeps the entries as a ring and a counting filter of hashed
//! 8-byte granules beside it. Enqueue and drain touch one or two counters, so
//! both are O(1), and the filter stays exact under steady-state churn - a
//! ring that never empties never saturates it. A load whose granules all read
//! zero cannot overlap a buffered store and costs one or two byte loads. One
//! that may overlap scans the ring newest first and stops as soon as every
//! byte it asked for has been found.

const std = @import("std");
const stripes = @import("access_stripes.zig");

/// Buffers, process-wide, that hold at least one entry. Exact: every empty
/// to non-empty transition adds one and every non-empty to empty transition
/// takes it away, so a zero proves nothing is queued anywhere and lets a
/// flush of every context's buffer return without visiting any of them.
var nonempty_buffers = std.atomic.Value(usize).init(0);

pub const StoreBuffer = struct {
    pub const capacity = 64;
    pub const maximum_store_bytes = 8;
    /// Bounded background progress: one entry drains per this many retired
    /// instructions while the buffer holds anything.
    pub const retire_interval = 16;
    const index_mask = capacity - 1;
    const filter_bits = 10;
    const filter_slots = 1 << filter_bits;
    /// A query this long or shorter is answered through the filter and a
    /// newest-first scan with a byte-coverage mask.
    const precise_query_limit = 64;

    comptime {
        std.debug.assert(std.math.isPowerOfTwo(capacity));
        // Every counter can hold every entry's granules at once.
        std.debug.assert(capacity * 2 <= std.math.maxInt(u8));
    }

    pub const Entry = struct {
        address: usize = 0,
        length: u8 = 0,
        bytes: [maximum_store_bytes]u8 = @splat(0),
    };

    entries: [capacity]Entry = @splat(.{}),
    head: usize = 0,
    count: usize = 0,
    /// Buffered entries covering each hashed granule. An entry covers one
    /// granule, or two when it straddles an 8-byte boundary.
    filter: [filter_slots]u8 = @splat(0),
    retired_since_drain: u8 = 0,

    // Counters for the exit report. Plain fields: the buffer has one owner.
    enqueued_count: u64 = 0,
    drained_count: u64 = 0,
    /// Loads (scalar or bulk) that took at least one byte from the buffer.
    forwarded_loads: u64 = 0,
    /// Queries the filter could not answer on its own.
    forward_scans: u64 = 0,
    /// Entries drained because an enqueue found the ring full.
    capacity_drains: u64 = 0,
    /// Entries drained by the retire-interval progress rule.
    retire_drains: u64 = 0,
    peak_depth: usize = 0,

    pub fn pendingCount(self: *const StoreBuffer) usize {
        return self.count;
    }

    pub fn isEmpty(self: *const StoreBuffer) bool {
        return self.count == 0;
    }

    /// False only when no buffer in the process holds an entry.
    pub fn anyBufferPending() bool {
        return nonempty_buffers.load(.acquire) != 0;
    }

    fn filterSlot(granule: usize) usize {
        return @intCast((@as(u64, @intCast(granule)) *% 0x9E37_79B9_7F4A_7C15) >> (64 - filter_bits));
    }

    fn adjustFilter(self: *StoreBuffer, address: usize, length: usize, comptime increment: bool) void {
        const first = address >> 3;
        const last = (address + length - 1) >> 3;
        var granule = first;
        while (granule <= last) : (granule += 1) {
            const slot = &self.filter[filterSlot(granule)];
            if (increment) slot.* += 1 else slot.* -= 1;
        }
    }

    /// False when no buffered entry can overlap `[address, address+length)`.
    fn mayOverlap(self: *const StoreBuffer, address: usize, length: usize) bool {
        const first = address >> 3;
        const last = (address + length - 1) >> 3;
        var granule = first;
        while (granule <= last) : (granule += 1) {
            if (self.filter[filterSlot(granule)] != 0) return true;
        }
        return false;
    }

    pub fn enqueue(self: *StoreBuffer, address: usize, bytes: []const u8) void {
        std.debug.assert(bytes.len != 0 and bytes.len <= maximum_store_bytes);
        if (self.count == capacity) {
            self.drainOne();
            self.capacity_drains +|= 1;
        }
        const entry = &self.entries[(self.head + self.count) & index_mask];
        entry.address = address;
        entry.length = @intCast(bytes.len);
        @memcpy(entry.bytes[0..bytes.len], bytes);
        if (self.count == 0) _ = nonempty_buffers.fetchAdd(1, .monotonic);
        self.count += 1;
        if (self.count > self.peak_depth) self.peak_depth = self.count;
        self.enqueued_count +|= 1;
        self.adjustFilter(address, bytes.len, true);
    }

    /// Overlay buffered bytes onto `destination`, a snapshot of the backing
    /// memory at `address`, so the newest buffered store of every byte wins.
    /// True when any byte came from the buffer.
    pub fn forwardInto(self: *StoreBuffer, destination: []u8, address: usize) bool {
        if (self.count == 0 or destination.len == 0) return false;
        if (destination.len > precise_query_limit) return self.forwardBulk(destination, address);
        if (!self.mayOverlap(address, destination.len)) return false;
        self.forward_scans +|= 1;
        const end = address + destination.len;
        const wanted: u64 = if (destination.len == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(destination.len)) - 1;
        var covered: u64 = 0;
        var remaining = self.count;
        while (remaining != 0 and covered != wanted) {
            remaining -= 1;
            const entry = &self.entries[(self.head + remaining) & index_mask];
            const start = @max(entry.address, address);
            const stop = @min(entry.address + entry.length, end);
            if (start >= stop) continue;
            for (start..stop) |byte_address| {
                const bit = @as(u64, 1) << @intCast(byte_address - address);
                if (covered & bit != 0) continue;
                covered |= bit;
                destination[byte_address - address] = entry.bytes[byte_address - entry.address];
            }
        }
        if (covered == 0) return false;
        self.forwarded_loads +|= 1;
        return true;
    }

    /// A long range: apply every overlapping entry oldest first.
    fn forwardBulk(self: *StoreBuffer, destination: []u8, address: usize) bool {
        self.forward_scans +|= 1;
        const end = address + destination.len;
        var forwarded = false;
        for (0..self.count) |logical| {
            const entry = &self.entries[(self.head + logical) & index_mask];
            const start = @max(entry.address, address);
            const stop = @min(entry.address + entry.length, end);
            if (start >= stop) continue;
            @memcpy(destination[start - address .. stop - address], entry.bytes[start - entry.address .. stop - entry.address]);
            forwarded = true;
        }
        if (forwarded) self.forwarded_loads +|= 1;
        return forwarded;
    }

    /// The buffered value of one byte, or null when no entry covers it.
    pub fn forwardedByte(self: *StoreBuffer, address: usize) ?u8 {
        var byte: [1]u8 = undefined;
        if (!self.forwardInto(&byte, address)) return null;
        return byte[0];
    }

    fn drainEntryBytes(entry: *const Entry) void {
        switch (entry.length) {
            1 => {
                const pointer: *u8 = @ptrFromInt(entry.address);
                @atomicStore(u8, pointer, entry.bytes[0], .release);
                return;
            },
            2 => if (entry.address & 1 == 0) {
                const pointer: *u16 = @ptrFromInt(entry.address);
                const value = std.mem.readInt(u16, entry.bytes[0..2], .little);
                @atomicStore(u16, pointer, stripes.littleEndian(value), .release);
                return;
            },
            4 => if (entry.address & 3 == 0) {
                const pointer: *u32 = @ptrFromInt(entry.address);
                const value = std.mem.readInt(u32, entry.bytes[0..4], .little);
                @atomicStore(u32, pointer, stripes.littleEndian(value), .release);
                return;
            },
            8 => if (entry.address & 7 == 0) {
                const pointer: *u64 = @ptrFromInt(entry.address);
                const value = std.mem.readInt(u64, entry.bytes[0..8], .little);
                @atomicStore(u64, pointer, stripes.littleEndian(value), .release);
                return;
            },
            else => {},
        }

        // x86 permits unaligned stores. Preserve their byte layout (under
        // the stripe drainOne holds, when coordinated) instead of issuing an
        // unaligned host atomic, which is not portable across hosts.
        for (0..@as(usize, entry.length)) |index| {
            const pointer: *u8 = @ptrFromInt(entry.address + index);
            @atomicStore(u8, pointer, entry.bytes[index], .release);
        }
    }

    /// Make the oldest buffered store visible.
    pub fn drainOne(self: *StoreBuffer) void {
        if (self.count == 0) return;
        const entry = &self.entries[self.head];
        const destination: [*]const u8 = @ptrFromInt(entry.address);
        // Only a peer executor on another host thread can observe the
        // stripe; serial execution skips it.
        const guard = stripes.AccessGuard.lockMode(destination[0..entry.length], stripes.coordinated(), false);
        drainEntryBytes(entry);
        guard.unlock();
        self.adjustFilter(entry.address, entry.length, false);
        self.head = (self.head + 1) & index_mask;
        self.count -= 1;
        self.drained_count +|= 1;
        if (self.count == 0) {
            self.retired_since_drain = 0;
            _ = nonempty_buffers.fetchSub(1, .release);
        }
    }

    /// Make every buffered store visible, in order, then order them before
    /// whatever the caller does next. Returns the number of entries drained.
    pub fn drain(self: *StoreBuffer) usize {
        const drained = self.count;
        if (drained == 0) return 0;
        while (self.count != 0) self.drainOne();
        stripes.fullBarrier();
        return drained;
    }

    /// Bounded background progress prevents a producer from leaving a store
    /// hidden indefinitely while its peer polls without an explicit fence.
    pub fn retireInstruction(self: *StoreBuffer) void {
        if (self.count == 0) return;
        self.retired_since_drain +|= 1;
        if (self.retired_since_drain >= retire_interval) {
            self.drainOne();
            self.retire_drains +|= 1;
            self.retired_since_drain = 0;
        }
    }

    pub fn reset(self: *StoreBuffer) void {
        std.debug.assert(self.count == 0);
        self.* = .{};
    }

    /// True when every filter counter is zero. Tests and invariant checks.
    pub fn filterIsClear(self: *const StoreBuffer) bool {
        for (self.filter) |slot| {
            if (slot != 0) return false;
        }
        return true;
    }
};

test "the process-wide pending count follows empty and non-empty transitions" {
    var memory: [16]u8 align(8) = @splat(0);
    const before = nonempty_buffers.load(.acquire);
    var first = StoreBuffer{};
    var second = StoreBuffer{};
    first.enqueue(@intFromPtr(&memory[0]), &.{1});
    first.enqueue(@intFromPtr(&memory[1]), &.{2});
    second.enqueue(@intFromPtr(&memory[8]), &.{3});
    try std.testing.expectEqual(before + 2, nonempty_buffers.load(.acquire));
    try std.testing.expect(StoreBuffer.anyBufferPending());
    first.drainOne();
    try std.testing.expectEqual(before + 2, nonempty_buffers.load(.acquire));
    _ = first.drain();
    _ = second.drain();
    try std.testing.expectEqual(before, nonempty_buffers.load(.acquire));
}

test "an empty buffer forwards nothing and costs no scan" {
    var buffer: StoreBuffer = .{};
    var bytes = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expect(!buffer.forwardInto(&bytes, 0x1000));
    try std.testing.expectEqual(@as(u64, 0), buffer.forward_scans);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &bytes);
}

test "store buffer forwarding stays consistent while the ring wraps and overlaps" {
    var memory = [_]u8{0} ** 96;
    var expected = memory;
    var buffer = StoreBuffer{};

    for (0..512) |operation| {
        const offset = (operation * 29 + operation / 3) % 72;
        const length = 1 + (operation % StoreBuffer.maximum_store_bytes);
        const value: u64 = 0xD6A5_9B3C_2718_4E0F ^ @as(u64, @intCast(operation));
        const bytes = std.mem.asBytes(&value);
        const address = @intFromPtr(&memory[offset]);
        buffer.enqueue(address, bytes[0..length]);
        for (0..length) |index| {
            expected[offset + index] = bytes[index];
        }

        if (operation % 11 == 10) buffer.drainOne();

        var view = memory;
        _ = buffer.forwardInto(&view, @intFromPtr(&memory[0]));
        try std.testing.expectEqualSlices(u8, &expected, &view);
        for (0..memory.len) |index| {
            const forwarded = buffer.forwardedByte(@intFromPtr(&memory[index]));
            try std.testing.expectEqual(expected[index], forwarded orelse memory[index]);
        }
    }

    _ = buffer.drain();
    try std.testing.expectEqualSlices(u8, &expected, &memory);
    try std.testing.expect(buffer.filterIsClear());
}

test "the filter never hides a buffered byte from a load of any width and alignment" {
    // Randomised against a byte-exact model of program-order memory; the
    // ring spends most of the run full, which is the steady state that
    // saturated the first design's filter.
    var memory: [512]u8 align(64) = @splat(0);
    var model: [512]u8 = @splat(0);
    var buffer = StoreBuffer{};
    var prng = std.Random.DefaultPrng.init(0x7505_B0FF);
    const random = prng.random();
    for (0..40_000) |_| {
        const roll = random.uintLessThan(u32, 100);
        if (roll < 55) {
            const length = 1 + random.uintLessThan(usize, StoreBuffer.maximum_store_bytes);
            const offset = random.uintLessThan(usize, memory.len - length);
            var bytes: [8]u8 = undefined;
            random.bytes(&bytes);
            buffer.enqueue(@intFromPtr(&memory[offset]), bytes[0..length]);
            @memcpy(model[offset..][0..length], bytes[0..length]);
        } else if (roll < 60) {
            buffer.drainOne();
        } else if (roll < 61) {
            _ = buffer.drain();
            try std.testing.expect(buffer.filterIsClear());
        } else {
            const length = 1 + random.uintLessThan(usize, 96);
            const offset = random.uintLessThan(usize, memory.len - length);
            var view: [96]u8 = undefined;
            @memcpy(view[0..length], memory[offset..][0..length]);
            _ = buffer.forwardInto(view[0..length], @intFromPtr(&memory[offset]));
            try std.testing.expectEqualSlices(u8, model[offset..][0..length], view[0..length]);
        }
        if (random.uintLessThan(u32, 8) == 0) buffer.retireInstruction();
    }
    _ = buffer.drain();
    try std.testing.expectEqualSlices(u8, &model, &memory);
    try std.testing.expect(buffer.filterIsClear());
}

test "a load outside every buffered granule skips the scan" {
    var memory: [256]u8 align(64) = @splat(0);
    var buffer = StoreBuffer{};
    buffer.enqueue(@intFromPtr(&memory[0]), &.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    var view: [8]u8 = @splat(0);
    // Different granules; a colliding hash would only cost a scan.
    const scans_before = buffer.forward_scans;
    _ = buffer.forwardInto(&view, @intFromPtr(&memory[128]));
    try std.testing.expect(buffer.forward_scans - scans_before <= 1);
    try std.testing.expectEqualSlices(u8, &(@as([8]u8, @splat(0))), &view);
    try std.testing.expect(buffer.forwardInto(&view, @intFromPtr(&memory[0])));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8 }, &view);
}

test "a full ring drains its oldest entry and records why" {
    var memory: [StoreBuffer.capacity + 1]u8 = @splat(0);
    var buffer = StoreBuffer{};
    for (0..StoreBuffer.capacity + 1) |index| {
        buffer.enqueue(@intFromPtr(&memory[index]), &.{@as(u8, @intCast(index + 1))});
    }
    try std.testing.expectEqual(@as(usize, StoreBuffer.capacity), buffer.pendingCount());
    try std.testing.expectEqual(@as(u64, 1), buffer.capacity_drains);
    try std.testing.expectEqual(@as(u8, 1), memory[0]);
    try std.testing.expectEqual(@as(u8, 0), memory[1]);
    try std.testing.expectEqual(@as(usize, StoreBuffer.capacity), buffer.peak_depth);
    try std.testing.expectEqual(@as(usize, StoreBuffer.capacity), buffer.drain());
    try std.testing.expectEqual(@as(u8, StoreBuffer.capacity + 1), memory[StoreBuffer.capacity]);
    try std.testing.expect(buffer.filterIsClear());
}

test "retirement drains one entry per interval" {
    var backing: [8]u8 align(8) = @splat(0);
    var buffer = StoreBuffer{};
    buffer.enqueue(@intFromPtr(&backing), &.{ 0xD4, 0xC3, 0xB2, 0xA1 });
    for (0..StoreBuffer.retire_interval - 1) |_| buffer.retireInstruction();
    try std.testing.expectEqual(@as(usize, 1), buffer.pendingCount());
    buffer.retireInstruction();
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u64, 1), buffer.retire_drains);
    try std.testing.expectEqualSlices(u8, &.{ 0xD4, 0xC3, 0xB2, 0xA1 }, backing[0..4]);
}

test "aligned scalar widths and unaligned byte runs drain with their layout" {
    var backing: [32]u8 align(16) = [_]u8{0} ** 32;
    var buffer: StoreBuffer = .{};
    buffer.enqueue(@intFromPtr(&backing[0]), &.{ 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11 });
    buffer.enqueue(@intFromPtr(&backing[8]), &.{ 0xd4, 0xc3, 0xb2, 0xa1 });
    buffer.enqueue(@intFromPtr(&backing[14]), &.{ 0x66, 0x55 });
    buffer.enqueue(@intFromPtr(&backing[17]), &.{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 });
    try std.testing.expectEqual(@as(usize, 4), buffer.drain());

    var expected = [_]u8{0} ** 32;
    @memcpy(expected[0..8], &[_]u8{ 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11 });
    @memcpy(expected[8..12], &[_]u8{ 0xd4, 0xc3, 0xb2, 0xa1 });
    @memcpy(expected[14..16], &[_]u8{ 0x66, 0x55 });
    @memcpy(expected[17..25], &[_]u8{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 });
    try std.testing.expectEqualSlices(u8, &expected, &backing);
}
