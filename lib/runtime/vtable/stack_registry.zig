//! Lightweight vtable registry for stack-local and modeled objects.
//!
//! Unlike the primary `VtableTracker`, this registry does NOT require an
//! allocation base from `memory_forwarder`.  It is designed for objects
//! whose vtable is written by Rosette's syntheic C++ object model (e.g.
//! modeled `basic_streambuf` subobjects in stringstreams) where the
//! guest address is on the guest stack or in other non-heap memory.
//!
//! Recovery from this registry is a fallback: Phase 3 after the heap-
//! based tracker's assessLowRead and assessCorruption both return null.
//!
//! The coverage is intentionally narrow — only objects explicitly
//! registered via `register()` are candidates for recovery.  This
//! prevents accidental repair of generic stack-allocated objects that
//! Rosette did not create.

const std = @import("std");
const types = @import("types.zig");

pub const StackRecord = struct {
    trusted_vptr: u64,
    generation: u64,
    established_by: types.Provenance,
    recoveries: u64 = 0,
};

/// Address-to-vptr mapping for non-heap objects whose vtable was
/// written by Rosette's synthetic object model.  Entries are added
/// during stream/streambuf construction and removed on destruction.
pub const StackRegistry = struct {
    allocator: std.mem.Allocator,
    records: std.AutoHashMap(u64, StackRecord),
    next_generation: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) StackRegistry {
        return .{
            .allocator = allocator,
            .records = std.AutoHashMap(u64, StackRecord).init(allocator),
        };
    }

    pub fn deinit(self: *StackRegistry) void {
        self.records.deinit();
    }

    /// Register a known vtable write at the given guest address.
    /// Called by the stream bridge after successful object initialization.
    pub fn register(
        self: *StackRegistry,
        address: u64,
        trusted_vptr: u64,
        provenance: types.Provenance,
    ) void {
        const generation = self.next_generation;
        self.next_generation +|= 1;
        self.records.put(address, .{
            .trusted_vptr = trusted_vptr,
            .generation = generation,
            .established_by = provenance,
        }) catch return;
    }

    /// Look up a registered address.  Returns the trusted vptr or null.
    pub fn lookup(self: *const StackRegistry, address: u64) ?u64 {
        const record = self.records.get(address) orelse return null;
        return record.trusted_vptr;
    }

    /// Propose vtable recovery when a low read (< 0x1000) occurs at a
    /// registered address.  Unlike the heap tracker, we only check for
    /// low reads — non-zero corruption recovery for modeled objects is
    /// intentionally not supported to avoid false positives on objects
    /// that legitimately change their vptr (e.g. base-to-derived casts).
    pub fn assessLowRead(
        self: *const StackRegistry,
        address: u64,
        current_value: u64,
    ) ?types.Recovery {
        if (current_value >= 0x1000) return null;
        const record = self.records.get(address) orelse return null;
        return .{
            .value = record.trusted_vptr,
            .generation = record.generation,
            .symbol_offset = 0,
            .established_by = record.established_by,
            .last_write = record.established_by,
            .prior_recoveries = record.recoveries,
        };
    }

    /// Record that a recovery was performed.  Returns false if the
    /// address has been evicted (regeneration collision).
    pub fn noteRecovery(self: *StackRegistry, address: u64, generation: u64) bool {
        const record = self.records.getPtr(address) orelse return false;
        if (record.generation != generation) return false;
        record.recoveries +|= 1;
        return true;
    }

    /// Remove a registered address (called when the stream is destroyed).
    pub fn forget(self: *StackRegistry, address: u64) void {
        _ = self.records.remove(address);
    }

    /// Returns the number of tracked objects.
    pub fn count(self: *const StackRegistry) usize {
        return self.records.count();
    }

    pub fn contains(self: *const StackRegistry, address: u64) bool {
        return self.records.contains(address);
    }
};

test "register and lookup round-trips" {
    var registry = StackRegistry.init(std.testing.allocator);
    defer registry.deinit();

    registry.register(0x7fffdea0, 0x1950b28, .{});
    try std.testing.expectEqual(@as(u64, 0x1950b28), registry.lookup(0x7fffdea0).?);
    try std.testing.expect(registry.contains(0x7fffdea0));
    try std.testing.expect(!registry.contains(0xdeadbeef));
}

test "assessLowRead returns recovery for low value at registered address" {
    var registry = StackRegistry.init(std.testing.allocator);
    defer registry.deinit();

    registry.register(0x7fffdea0, 0x1950b28, .{
        .writer_rip = 0x1000,
        .writer_step = 42,
    });

    // Low value (0) should trigger recovery
    const recovery = registry.assessLowRead(0x7fffdea0, 0).?;
    try std.testing.expectEqual(@as(u64, 0x1950b28), recovery.value);
    try std.testing.expectEqual(@as(u64, 42), recovery.established_by.writer_step);
    try std.testing.expectEqual(@as(u64, 0), recovery.prior_recoveries);

    // Non-zero value should NOT trigger recovery
    try std.testing.expect(registry.assessLowRead(0x7fffdea0, 0xdeadbeef) == null);
}

test "assessLowRead returns null for unregistered address" {
    var registry = StackRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.assessLowRead(0x12345678, 0) == null);
}

test "noteRecovery increments recovery counter" {
    var registry = StackRegistry.init(std.testing.allocator);
    defer registry.deinit();

    registry.register(0x7fffdea0, 0x1950b28, .{});
    const recovery = registry.assessLowRead(0x7fffdea0, 0).?;
    try std.testing.expect(registry.noteRecovery(0x7fffdea0, recovery.generation));

    // Verify recovery count increased
    const record = registry.records.get(0x7fffdea0).?;
    try std.testing.expectEqual(@as(u64, 1), record.recoveries);
}

test "forget removes address from registry" {
    var registry = StackRegistry.init(std.testing.allocator);
    defer registry.deinit();

    registry.register(0x7fffdea0, 0x1950b28, .{});
    try std.testing.expect(registry.contains(0x7fffdea0));

    registry.forget(0x7fffdea0);
    try std.testing.expect(!registry.contains(0x7fffdea0));
    try std.testing.expect(registry.assessLowRead(0x7fffdea0, 0) == null);
}

test "generation collision prevents stale recovery after re-registration" {
    var registry = StackRegistry.init(std.testing.allocator);
    defer registry.deinit();

    registry.register(0x7fffdea0, 0x1950b28, .{});
    const first_recovery = registry.assessLowRead(0x7fffdea0, 0).?;

    // Re-register at the same address (simulating a new object)
    registry.forget(0x7fffdea0);
    registry.register(0x7fffdea0, 0x193c1e0, .{});

    // The old generation should not work
    try std.testing.expect(!registry.noteRecovery(0x7fffdea0, first_recovery.generation));

    // The new generation should work
    const second_recovery = registry.assessLowRead(0x7fffdea0, 0).?;
    try std.testing.expect(registry.noteRecovery(0x7fffdea0, second_recovery.generation));
}
