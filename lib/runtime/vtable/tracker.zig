const std = @import("std");
const types = @import("types.zig");

pub const VtableTracker = struct {
    allocator: std.mem.Allocator,
    policy: types.Policy,
    records: std.AutoHashMap(u64, types.AllocationRecord),
    next_generation: u64 = 1,

    // Compatibility-facing metric names used by existing diagnostics.
    live_vtable_guard_checks: u64 = 0,
    live_vtable_guard_recoveries: u64 = 0,
    live_vtable_write_protections: u64 = 0,
    heap_corruption_detections: u64 = 0,
    /// Count of non-prologue code_address writes that were silently skipped
    /// (legitimate initialization: Export struct function pointers, hash table
    /// bucket counts, CommandVar default value pointers). Reported in the
    /// terminal summary but not logged per-event to avoid log spam.
    non_prologue_code_writes: u64 = 0,

    trusted_establishments: u64 = 0,
    trusted_transitions: u64 = 0,
    rejected_candidates: u64 = 0,
    rejection_counts: [std.meta.fields(types.IdentityRejection).len]u64 =
        [_]u64{0} ** std.meta.fields(types.IdentityRejection).len,
    low_clears_observed: u64 = 0,
    retired_records: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) VtableTracker {
        return initWithPolicy(allocator, .{});
    }

    pub fn initWithPolicy(allocator: std.mem.Allocator, policy: types.Policy) VtableTracker {
        return .{
            .allocator = allocator,
            .policy = policy,
            .records = std.AutoHashMap(u64, types.AllocationRecord).init(allocator),
        };
    }

    pub fn deinit(self: *VtableTracker) void {
        self.records.deinit();
    }

    /// Observe a write at the exact base of a live allocation.  This method
    /// never mutates guest memory.  In particular, zero and ordinary pointer
    /// writes cannot become vtable identities merely because they occur at an
    /// allocation boundary.
    pub fn observeWrite(
        self: *VtableTracker,
        address: u64,
        evidence: types.IdentityEvidence,
        provenance: types.Provenance,
    ) types.WriteResult {
        const rejection = evidence.rejection(self.policy);
        if (rejection) |reason| {
            self.rejection_counts[@intFromEnum(reason)] +|= 1;
            if (evidence.value >= 0x1000 and evidence.symbol_name != null) {
                self.rejected_candidates +|= 1;
            }
            const record = self.records.getPtr(address) orelse {
                return .{ .disposition = .ignored_non_vtable };
            };
            record.last_write = provenance;
            record.last_observed_value = evidence.value;
            if (evidence.value < 0x1000) {
                record.low_clears_observed +|= 1;
                self.low_clears_observed +|= 1;
                return .{
                    .disposition = .trusted_value_cleared,
                    .generation = record.generation,
                    .previous_vptr = record.trusted_vptr,
                    .trusted_vptr = record.trusted_vptr,
                };
            }
            return .{
                .disposition = .observed_non_vtable,
                .generation = record.generation,
                .previous_vptr = record.trusted_vptr,
                .trusted_vptr = record.trusted_vptr,
            };
        }

        if (self.records.getPtr(address)) |record| {
            const previous = record.trusted_vptr;
            record.last_write = provenance;
            record.last_observed_value = evidence.value;
            if (previous == evidence.value) {
                return .{
                    .disposition = .repeated,
                    .generation = record.generation,
                    .previous_vptr = previous,
                    .trusted_vptr = previous,
                };
            }

            // Base-to-derived construction and derived-to-base destruction
            // legitimately replace the primary vptr.  This is a transition,
            // not an allocation collision.
            record.trusted_vptr = evidence.value;
            record.trusted_symbol_offset = evidence.symbol_offset;
            record.established_by = provenance;
            record.valid_transitions +|= 1;
            self.trusted_transitions +|= 1;
            return .{
                .disposition = .valid_transition,
                .generation = record.generation,
                .previous_vptr = previous,
                .trusted_vptr = evidence.value,
            };
        }

        const generation = self.next_generation;
        self.next_generation +|= 1;
        self.records.put(address, .{
            .generation = generation,
            .trusted_vptr = evidence.value,
            .trusted_symbol_offset = evidence.symbol_offset,
            .established_by = provenance,
            .last_write = provenance,
            .last_observed_value = evidence.value,
        }) catch return .{ .disposition = .ignored_non_vtable };
        self.trusted_establishments +|= 1;
        return .{
            .disposition = .established,
            .generation = generation,
            .trusted_vptr = evidence.value,
        };
    }

    /// Return a recovery proposal only for a low read at the exact base of a
    /// still-live allocation.  The caller owns the actual memory write and
    /// must call noteRecovery only after that write succeeds.
    pub fn assessLowRead(
        self: *VtableTracker,
        address: u64,
        current_value: u64,
        exact_live_allocation_base: bool,
    ) ?types.Recovery {
        self.live_vtable_guard_checks +|= 1;
        if (self.policy.recovery_mode != .repair_trusted_low_read) return null;
        if (!exact_live_allocation_base or current_value >= 0x1000) return null;
        const record = self.records.get(address) orelse return null;
        return .{
            .value = record.trusted_vptr,
            .generation = record.generation,
            .symbol_offset = record.trusted_symbol_offset,
            .established_by = record.established_by,
            .last_write = record.last_write,
            .prior_recoveries = record.recoveries,
        };
    }

    /// Propose recovery when a value at a tracked allocation base is read as
    /// non-zero but is NOT a valid vtable identity.  The caller must pass the
    /// rejection reason (or null if the current value IS a trusted vtable).
    ///
    /// Unlike `assessLowRead` (which requires `current_value < 0x1000`), this
    /// method handles corruption patterns where the vptr is overwritten with
    /// a non-zero invalid pointer (e.g. a kernel-space address, a scrambled
    /// offset, or a small integer that happens to land at ≥ 0x1000).
    pub fn assessCorruption(
        self: *VtableTracker,
        address: u64,
        current_value: u64,
        current_rejection: ?types.IdentityRejection,
        exact_live_allocation_base: bool,
    ) ?types.Recovery {
        self.live_vtable_guard_checks +|= 1;
        if (!self.policy.repair_nonzero_corruption) return null;
        if (!exact_live_allocation_base) return null;
        // If current value IS a valid vtable identity, there's no corruption.
        // The object legitimately has a (possibly new) vtable.
        if (current_rejection == null) return null;
        // Don't intervene when the current value is low (< 0x1000) — that
        // path is handled by assessLowRead already.
        if (current_value < 0x1000) return null;
        const record = self.records.get(address) orelse return null;
        // If the current value is the same as the trusted vptr yet the
        // tracker says the value was rejected, something went wrong in the
        // evidence collection (e.g. the symbol was unloaded).  Treat this
        // as a stable state, not corruption — don't oscillate.
        if (record.trusted_vptr == current_value) return null;
        return .{
            .value = record.trusted_vptr,
            .generation = record.generation,
            .symbol_offset = record.trusted_symbol_offset,
            .established_by = record.established_by,
            .last_write = record.last_write,
            .prior_recoveries = record.recoveries,
        };
    }

    pub fn noteRecovery(self: *VtableTracker, address: u64, generation: u64) bool {
        const record = self.records.getPtr(address) orelse return false;
        if (record.generation != generation) return false;
        record.recoveries +|= 1;
        self.live_vtable_guard_recoveries +|= 1;
        return true;
    }

    /// Retiring on free/reuse is the collision barrier: no vptr from a former
    /// occupant can be proposed for the next object at the same address.
    pub fn retireAddress(self: *VtableTracker, address: u64) bool {
        if (!self.records.remove(address)) return false;
        self.retired_records +|= 1;
        return true;
    }

    pub fn forgetAddress(self: *VtableTracker, address: u64) void {
        _ = self.retireAddress(address);
    }

    pub fn hasTrustedHistory(self: *const VtableTracker, address: u64) bool {
        return self.records.contains(address);
    }

    /// Look up the full allocation record for an address.
    /// Returns null if no trusted vtable history exists at this address.
    /// This is a public query method for the ownership diagnostics library.
    pub fn lookupRecord(self: *const VtableTracker, address: u64) ?types.AllocationRecord {
        return self.records.get(address);
    }

    pub fn trackedAllocationCount(self: *const VtableTracker) usize {
        return self.records.count();
    }

    pub fn rejectionCount(self: *const VtableTracker, reason: types.IdentityRejection) u64 {
        return self.rejection_counts[@intFromEnum(reason)];
    }
};

fn trustedEvidence(value: u64, offset: u64) types.IdentityEvidence {
    return .{
        .value = value,
        .symbol_name = "__ZTVN4test6ObjectE",
        .symbol_offset = offset,
        .header_mapped = true,
        .typeinfo_plausible = true,
        .first_slot_plausible = true,
    };
}

test "ordinary allocation pointers are never protected as vtables" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const result = tracker.observeWrite(0x4000, .{
        .value = 0x46b85c0,
        .symbol_name = "__ZTVN4test6ObjectE",
        .symbol_offset = 0x26501ff,
        .header_mapped = true,
    }, .{ .writer_rip = 0x100 });
    try std.testing.expectEqual(types.WriteDisposition.ignored_non_vtable, result.disposition);
    try std.testing.expectEqual(@as(usize, 0), tracker.trackedAllocationCount());
    try std.testing.expect(tracker.assessLowRead(0x4000, 0, true) == null);
}

test "trusted write then low read creates a narrow recovery proposal" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const established = tracker.observeWrite(
        0x4000,
        trustedEvidence(0x1950b28, 0x50),
        .{ .writer_rip = 0x200, .writer_step = 10, .writer_thread = 3 },
    );
    try std.testing.expectEqual(types.WriteDisposition.established, established.disposition);

    const cleared = tracker.observeWrite(
        0x4000,
        .{ .value = 0 },
        .{ .writer_rip = 0x300, .writer_step = 20, .writer_thread = 3 },
    );
    try std.testing.expectEqual(types.WriteDisposition.trusted_value_cleared, cleared.disposition);

    const recovery = tracker.assessLowRead(0x4000, 0, true).?;
    try std.testing.expectEqual(@as(u64, 0x1950b28), recovery.value);
    try std.testing.expect(tracker.noteRecovery(0x4000, recovery.generation));
    try std.testing.expectEqual(@as(u64, 1), tracker.live_vtable_guard_recoveries);
}

test "valid construction transition is not a collision" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});
    const transition = tracker.observeWrite(0x4000, trustedEvidence(0x1950c18, 0x30), .{});
    try std.testing.expectEqual(types.WriteDisposition.valid_transition, transition.disposition);
    try std.testing.expectEqual(@as(u64, 0x1950b28), transition.previous_vptr);
    try std.testing.expectEqual(@as(u64, 0x1950c18), transition.trusted_vptr);
}

test "allocation retirement prevents stale recovery after address reuse" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});
    try std.testing.expect(tracker.retireAddress(0x4000));
    try std.testing.expect(tracker.assessLowRead(0x4000, 0, true) == null);
}

test "observe-only policy never proposes mutation" {
    var tracker = VtableTracker.initWithPolicy(std.testing.allocator, .{
        .recovery_mode = .observe_only,
    });
    defer tracker.deinit();

    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});
    try std.testing.expect(tracker.assessLowRead(0x4000, 0, true) == null);
}

test "assessCorruption returns recovery for non-zero invalid value at trusted address" {
    var tracker = VtableTracker.initWithPolicy(std.testing.allocator, .{
        .repair_nonzero_corruption = true,
    });
    defer tracker.deinit();

    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});

    // Current value is a kernel-space address — not a valid vtable.
    const corrupted_evidence = types.IdentityEvidence{
        .value = 0xfffffc0000000042,
        .symbol_name = null,
        .symbol_offset = std.math.maxInt(u64),
        .header_mapped = false,
    };
    const rejection = corrupted_evidence.rejection(tracker.policy);
    try std.testing.expect(rejection != null);

    const recovery = tracker.assessCorruption(
        0x4000,
        0xfffffc0000000042,
        rejection,
        true,
    );
    try std.testing.expect(recovery != null);
    try std.testing.expectEqual(@as(u64, 0x1950b28), recovery.?.value);

    // When the current value matches the trusted vptr (and yet evidence says rejected),
    // assessCorruption should NOT return a recovery — it's a stable state.
    const stable = tracker.assessCorruption(
        0x4000,
        0x1950b28,
        types.IdentityRejection.missing_symbol, // evidence says rejected (e.g. symbol was unloaded)
        true,
    );
    try std.testing.expect(stable == null);
}

test "assessCorruption returns null when repair_nonzero_corruption is false" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});

    const result = tracker.assessCorruption(
        0x4000,
        0xdeadbeef,
        types.IdentityRejection.missing_symbol,
        true,
    );
    try std.testing.expect(result == null);
}

test "assessCorruption returns null when not exact live allocation" {
    var tracker = VtableTracker.initWithPolicy(std.testing.allocator, .{
        .repair_nonzero_corruption = true,
    });
    defer tracker.deinit();

    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});

    const result = tracker.assessCorruption(
        0x4000,
        0xdeadbeef,
        types.IdentityRejection.missing_symbol,
        false, // not exact live allocation base
    );
    try std.testing.expect(result == null);
}
