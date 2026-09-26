//! The store buffers of a Windows PE process: one for the process owner's
//! context and one stable buffer per guest worker slot.
//!
//! Buffers live outside copied CPU contexts, so context snapshots never
//! duplicate pending stores. Each buffer keeps its slot for the process
//! lifetime, so recycling a guest-thread slot cannot lose queued stores.
//! Parallel workers own their buffers; an instruction-retirement drain uses
//! the shared address coordinator, and drains outside an instruction lease
//! rendezvous through the stop-the-world execution gate before mappings or
//! backing allocations can be changed.

const std = @import("std");
const StoreBuffer = @import("store_buffer.zig").StoreBuffer;
const ledger = @import("boundary_ledger.zig");

pub const GuestStoreBuffers = struct {
    owner: StoreBuffer = .{},
    slots: []StoreBuffer = &.{},
    /// False sends every guest store straight to memory
    /// (`ROSETTE_TSO_STORE_BUFFERS=0`), for an A/B run against the model.
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator, slot_count: usize) std.mem.Allocator.Error!GuestStoreBuffers {
        const slots = try allocator.alloc(StoreBuffer, slot_count);
        @memset(slots, .{});
        return .{ .slots = slots };
    }

    /// Publish every queued store, then release the slot buffers. Pending
    /// entries hold host addresses, so this runs before any mapping or
    /// backing allocation is torn down.
    pub fn deinit(self: *GuestStoreBuffers, allocator: std.mem.Allocator) void {
        self.flushAll(.shutdown);
        if (self.slots.len != 0) allocator.free(self.slots);
        self.slots = &.{};
    }

    /// The buffer for the owner context (`slot == null`) or a worker slot.
    /// Null when buffering is off or the slot is out of range.
    pub fn forContext(self: *GuestStoreBuffers, slot: ?usize) ?*StoreBuffer {
        if (!self.enabled) return null;
        const index = slot orelse return &self.owner;
        if (index >= self.slots.len) return null;
        return &self.slots[index];
    }

    /// Drain one context's buffer at `boundary`.
    pub fn drainContext(self: *GuestStoreBuffers, slot: ?usize, boundary: ledger.Boundary) void {
        const buffer: *StoreBuffer = if (slot) |index|
            (if (index < self.slots.len) &self.slots[index] else return)
        else
            &self.owner;
        ledger.noteFlush(boundary, buffer.drain());
    }

    /// Drain every context's buffer at `boundary`. Pending entries contain
    /// host addresses, so this runs before runtime mutation can recycle or
    /// remap guest storage.
    pub fn flushAll(self: *GuestStoreBuffers, boundary: ledger.Boundary) void {
        if (!StoreBuffer.anyBufferPending()) return;
        var drained = self.owner.drain();
        for (self.slots) |*buffer| drained += buffer.drain();
        ledger.noteFlush(boundary, drained);
    }

    pub fn anyPending(self: *const GuestStoreBuffers) bool {
        if (!self.owner.isEmpty()) return true;
        for (self.slots) |*buffer| {
            if (!buffer.isEmpty()) return true;
        }
        return false;
    }

    pub const Totals = struct {
        contexts_used: usize = 0,
        enqueued: u64 = 0,
        drained: u64 = 0,
        pending: usize = 0,
        forwarded_loads: u64 = 0,
        forward_scans: u64 = 0,
        capacity_drains: u64 = 0,
        retire_drains: u64 = 0,
        peak_depth: usize = 0,

        fn add(self: *Totals, buffer: *const StoreBuffer) void {
            if (buffer.enqueued_count != 0) self.contexts_used += 1;
            self.enqueued +|= buffer.enqueued_count;
            self.drained +|= buffer.drained_count;
            self.pending += buffer.pendingCount();
            self.forwarded_loads +|= buffer.forwarded_loads;
            self.forward_scans +|= buffer.forward_scans;
            self.capacity_drains +|= buffer.capacity_drains;
            self.retire_drains +|= buffer.retire_drains;
            self.peak_depth = @max(self.peak_depth, buffer.peak_depth);
        }
    };

    pub fn totals(self: *const GuestStoreBuffers) Totals {
        var result: Totals = .{};
        result.add(&self.owner);
        for (self.slots) |*buffer| result.add(buffer);
        return result;
    }
};

test "each context owns a stable buffer and a disabled set owns none" {
    var buffers = try GuestStoreBuffers.init(std.testing.allocator, 4);
    defer buffers.deinit(std.testing.allocator);
    const owner = buffers.forContext(null).?;
    const worker = buffers.forContext(2).?;
    try std.testing.expect(owner != worker);
    try std.testing.expect(worker == buffers.forContext(2).?);
    try std.testing.expect(buffers.forContext(9) == null);
    buffers.enabled = false;
    try std.testing.expect(buffers.forContext(null) == null);
    try std.testing.expect(buffers.forContext(1) == null);
}

test "draining a context publishes its stores and leaves the others queued" {
    ledger.resetForTest();
    defer ledger.resetForTest();
    var memory: [16]u8 align(8) = @splat(0);
    var buffers = try GuestStoreBuffers.init(std.testing.allocator, 2);
    defer buffers.deinit(std.testing.allocator);
    buffers.forContext(0).?.enqueue(@intFromPtr(&memory[0]), &.{ 1, 2, 3, 4 });
    buffers.forContext(null).?.enqueue(@intFromPtr(&memory[8]), &.{ 5, 6 });
    try std.testing.expect(buffers.anyPending());
    buffers.drainContext(0, .context_switch);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, memory[0..4]);
    try std.testing.expectEqual(@as(u8, 0), memory[8]);
    buffers.flushAll(.runtime_call);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6 }, memory[8..10]);
    try std.testing.expect(!buffers.anyPending());
    const totals = buffers.totals();
    try std.testing.expectEqual(@as(usize, 2), totals.contexts_used);
    try std.testing.expectEqual(@as(u64, 2), totals.enqueued);
    try std.testing.expectEqual(@as(u64, 2), totals.drained);
    const recorded = ledger.snapshot();
    try std.testing.expectEqual(@as(u64, 1), recorded.flushes[@intFromEnum(ledger.Boundary.context_switch)]);
    try std.testing.expectEqual(@as(u64, 1), recorded.flushes[@intFromEnum(ledger.Boundary.runtime_call)]);
}
