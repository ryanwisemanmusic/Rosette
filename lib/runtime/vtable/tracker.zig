const std = @import("std");
const types = @import("types.zig");

pub const VtableTracker = struct {
    const filter_word_count: usize = 2048;
    const filter_bit_count: u64 = filter_word_count * 64;
    const page_filter_word_count: usize = 1024;
    const page_filter_bit_count: u64 = page_filter_word_count * 64;

    allocator: std.mem.Allocator,
    policy: types.Policy,
    records: std.AutoHashMap(u64, types.AllocationRecord),
    /// Append-only Bloom filter for exact vptr slot addresses.  Ordinary
    /// stores can ask whether a slot could have trusted history without a hash
    /// table lookup.  Bits intentionally survive retirement: stale positives
    /// cost one lookup, while clearing a bit could create a false negative for
    /// a colliding live object and miss a correctness-bearing clear.
    slot_filter: [filter_word_count]u64 = [_]u64{0} ** filter_word_count,
    /// First-level direct-mapped page filter. This makes byte-at-a-time JIT
    /// emission (Xbyak is a dominant Xenia workload) one shift, mask and bit
    /// test instead of paying the two slot hashes for every emitted byte.
    page_filter: [page_filter_word_count]u64 = [_]u64{0} ** page_filter_word_count,
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
    range_mutations: u64 = 0,
    truncated_range_mutations: u64 = 0,
    atomic_mutation_rollbacks: u64 = 0,
    atomic_qwords_restored: u64 = 0,

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
            if (provenance.owner_base != 0) record.owner_base = provenance.owner_base;
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
            .owner_base = if (provenance.owner_base != 0) provenance.owner_base else address,
        }) catch return .{ .disposition = .ignored_non_vtable };
        self.noteTrackedAddress(address);
        self.trusted_establishments +|= 1;
        return .{
            .disposition = .established,
            .generation = generation,
            .trusted_vptr = evidence.value,
        };
    }

    /// Return a recovery proposal for a low read at a tracked vptr slot inside
    /// a still-live allocation.  The caller owns the actual memory write and
    /// must call noteRecovery only after that write succeeds.
    ///
    /// `within_live_allocation` deliberately does *not* mean "the exact
    /// allocation base". A class with multiple inheritance carries one vptr per
    /// non-primary base, and those live at non-zero offsets inside the object —
    /// `MacConditionHandle<Semaphore>` keeps the `MacConditionBase` vptr eight
    /// bytes in. Requiring offset zero meant the primary vptr was repaired and
    /// the secondary was left cleared, so the very next virtual call through
    /// the secondary base loaded null and dispatched through it. That is not a
    /// weaker safety condition than before: what licenses the repair is the
    /// *record*, which only exists because a value passing the full Itanium
    /// vtable-identity test was previously written to this exact address.
    /// Liveness of the containing allocation is the second condition, not the
    /// first.
    pub fn assessLowRead(
        self: *VtableTracker,
        address: u64,
        current_value: u64,
        within_live_allocation: bool,
    ) ?types.Recovery {
        self.live_vtable_guard_checks +|= 1;
        if (self.policy.recovery_mode != .repair_trusted_low_read) return null;
        if (!within_live_allocation or current_value >= 0x1000) return null;
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
    /// Retire every slot belonging to the object based at `address`, not only
    /// the slot at that address.
    ///
    /// An object with multiple inheritance has a tracked vptr per non-primary
    /// base, all inside one allocation. Removing only the base's record left
    /// the others behind, and a stale secondary record outliving its object is
    /// worse than the null it was meant to repair: the next occupant of that
    /// storage would have a previous class's vtable written into what is now an
    /// ordinary data member, silently and with no fault anywhere.
    ///
    /// The scan is over tracked slots rather than over the allocation's bytes
    /// because the size is not known here, and it runs only on free/reuse.
    pub fn retireAddress(self: *VtableTracker, address: u64) bool {
        var retired = self.records.remove(address);
        if (retired) self.retired_records +|= 1;

        // Bounded probe forwards rather than a scan of every tracked slot.
        // Free is not rare — an interface that allocates and releases objects
        // in a loop would pay for the whole table on each release — and the
        // slots reachable here are exactly the ones the write side could have
        // recorded, because both use `max_subobject_slots`.
        var slot: usize = 1;
        while (slot <= types.max_subobject_slots) : (slot += 1) {
            const candidate = address +| (slot * 8);
            const record = self.records.get(candidate) orelse continue;
            if (record.owner_base != address) continue;
            if (!self.records.remove(candidate)) continue;
            self.retired_records +|= 1;
            retired = true;
        }
        return retired;
    }

    pub fn forgetAddress(self: *VtableTracker, address: u64) void {
        _ = self.retireAddress(address);
    }

    pub fn hasTrustedHistory(self: *const VtableTracker, address: u64) bool {
        return self.records.contains(address);
    }

    /// Cheap, no-false-negative prefilter for hot memory-write paths.  A true
    /// answer is only a candidate and must still be confirmed in `records`.
    pub fn mightContain(self: *const VtableTracker, address: u64) bool {
        if ((address & 7) != 0) return false;
        if (!self.pageMightContain(address)) return false;
        const positions = filterPositions(address);
        return filterContains(self, positions.first) and filterContains(self, positions.second);
    }

    /// Capture trusted vptrs overlapped by an arbitrary write.  This is always
    /// available—unlike the generic provenance trace—because delaying vptr
    /// discovery until the later virtual read loses the actual writer.
    pub fn captureMutation(
        self: *const VtableTracker,
        state: anytype,
        address: u64,
        length: u64,
    ) types.MutationCapture {
        var capture = types.MutationCapture{ .address = address, .length = length };
        if (length == 0 or self.records.count() == 0) return capture;

        const end = std.math.add(u64, address, length) catch std.math.maxInt(u64);
        const first_slot = address & ~@as(u64, 7);
        const last_slot = (end -| 1) & ~@as(u64, 7);
        const slot_count = ((last_slot -| first_slot) / 8) + 1;

        if (slot_count <= types.max_mutation_slots) {
            if (!self.pageMightContain(first_slot) and !self.pageMightContain(last_slot)) {
                return capture;
            }
            var slot = first_slot;
            while (slot <= last_slot) : (slot +|= 8) {
                if (self.mightContain(slot)) captureSlot(self, state, &capture, slot);
                if (slot == last_slot) break;
            }
            return capture;
        }

        var iterator = self.records.iterator();
        while (iterator.next()) |entry| {
            const slot = entry.key_ptr.*;
            if (slot +| 8 <= address or slot >= end) continue;
            if (capture.count == types.max_mutation_slots) {
                capture.truncated = true;
                break;
            }
            const value = readSlot(state, slot) orelse continue;
            capture.slots[capture.count] = .{
                .address = slot,
                .value = value,
                .generation = entry.value_ptr.generation,
            };
            capture.count += 1;
        }
        return capture;
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

    fn noteTrackedAddress(self: *VtableTracker, address: u64) void {
        const page_position = pageFilterPosition(address);
        const page_word: usize = @intCast(page_position / 64);
        const page_bit: u6 = @intCast(page_position % 64);
        self.page_filter[page_word] |= @as(u64, 1) << page_bit;
        const positions = filterPositions(address);
        filterInsert(self, positions.first);
        filterInsert(self, positions.second);
    }

    fn filterInsert(self: *VtableTracker, position: u64) void {
        const word: usize = @intCast(position / 64);
        const bit: u6 = @intCast(position % 64);
        self.slot_filter[word] |= @as(u64, 1) << bit;
    }

    fn filterContains(self: *const VtableTracker, position: u64) bool {
        const word: usize = @intCast(position / 64);
        const bit: u6 = @intCast(position % 64);
        return (self.slot_filter[word] & (@as(u64, 1) << bit)) != 0;
    }

    fn pageMightContain(self: *const VtableTracker, address: u64) bool {
        const position = pageFilterPosition(address);
        const word: usize = @intCast(position / 64);
        const bit: u6 = @intCast(position % 64);
        return (self.page_filter[word] & (@as(u64, 1) << bit)) != 0;
    }
};

fn pageFilterPosition(address: u64) u64 {
    return (address >> 12) & (VtableTracker.page_filter_bit_count - 1);
}

fn filterPositions(address: u64) struct { first: u64, second: u64 } {
    var mixed = address >> 3;
    mixed ^= mixed >> 33;
    mixed *%= 0xff51afd7ed558ccd;
    mixed ^= mixed >> 33;
    const first = mixed % VtableTracker.filter_bit_count;
    mixed *%= 0xc4ceb9fe1a85ec53;
    mixed ^= mixed >> 29;
    return .{
        .first = first,
        .second = mixed % VtableTracker.filter_bit_count,
    };
}

fn captureSlot(
    tracker: *const VtableTracker,
    state: anytype,
    capture: *types.MutationCapture,
    address: u64,
) void {
    if (capture.count == types.max_mutation_slots) {
        capture.truncated = true;
        return;
    }
    const record = tracker.records.get(address) orelse return;
    const value = readSlot(state, address) orelse return;
    capture.slots[capture.count] = .{
        .address = address,
        .value = value,
        .generation = record.generation,
    };
    capture.count += 1;
}

fn readSlot(state: anytype, address: u64) ?u64 {
    const bytes = state.guestMemoryConst(address, 8) orelse return null;
    return std.mem.readInt(u64, bytes[0..8], .little);
}

fn trustedEvidence(value: u64, offset: u64) types.IdentityEvidence {
    return .{
        .value = value,
        .symbol_name = "__ZTVN4test6ObjectE",
        .symbol_offset = offset,
        .header_mapped = true,
        .offset_to_top_plausible = true,
        .typeinfo_plausible = true,
        .first_slot_plausible = true,
    };
}

test "tracked-slot Bloom filter has no false negative across retirement" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try std.testing.expect(!tracker.mightContain(0x4000));
    _ = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});
    try std.testing.expect(tracker.mightContain(0x4000));
    try std.testing.expect(tracker.hasTrustedHistory(0x4000));

    try std.testing.expect(tracker.retireAddress(0x4000));
    try std.testing.expect(tracker.mightContain(0x4000));
    try std.testing.expect(!tracker.hasTrustedHistory(0x4000));
}

test "partial mutation capture finds an overlapping trusted vptr" {
    const FakeMemory = struct {
        const base: u64 = 0x4000;
        bytes: [64]u8 = [_]u8{0} ** 64,

        pub fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            if (address < base or length > self.bytes.len) return null;
            const offset = address - base;
            if (offset > self.bytes.len or length > self.bytes.len - offset) return null;
            return self.bytes[@intCast(offset)..][0..@intCast(length)];
        }
    };

    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();
    const established = tracker.observeWrite(0x4000, trustedEvidence(0x1950b28, 0x50), .{});

    var memory = FakeMemory{};
    std.mem.writeInt(u64, memory.bytes[0..8], 0x1950b28, .little);
    const capture = tracker.captureMutation(&memory, 0x4003, 1);
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    try std.testing.expectEqual(@as(u64, 0x4000), capture.slots[0].address);
    try std.testing.expectEqual(@as(u64, 0x1950b28), capture.slots[0].value);
    try std.testing.expectEqual(established.generation, capture.slots[0].generation);

    const unrelated = tracker.captureMutation(&memory, 0x4020, 1);
    try std.testing.expectEqual(@as(usize, 0), unrelated.count);
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

// A class with multiple inheritance carries one vptr per non-primary base, at
// non-zero offsets inside the object. Repairing only the one at offset zero
// leaves the object half-constructed: the primary dispatches, the secondary
// loads null, and the first virtual call through the secondary base calls
// through it.
//
// Observed as `MacConditionHandle<Semaphore>`, whose `MacConditionBase` vptr
// lives eight bytes in: the primary at 0x473dab0 was restored and the call at
// `[0x473dab8]+0x18` still went through a null.
test "a secondary base's vptr is recoverable, not only the object's primary" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const object: u64 = 0x473dab0;
    const secondary = object + 8;

    // Construction writes both vptrs: the primary and the secondary base's,
    // each a distinct address inside one allocation.
    try std.testing.expectEqual(
        types.WriteDisposition.established,
        tracker.observeWrite(object, trustedEvidence(0x1959688, 0x10), .{ .writer_rip = 0x1d74b4 }).disposition,
    );
    try std.testing.expectEqual(
        types.WriteDisposition.established,
        tracker.observeWrite(secondary, trustedEvidence(0x19596c0, 0x48), .{ .writer_rip = 0x1d74b4 }).disposition,
    );

    // Both are cleared.
    _ = tracker.observeWrite(object, .{ .value = 0 }, .{ .writer_rip = 0x300 });
    _ = tracker.observeWrite(secondary, .{ .value = 0 }, .{ .writer_rip = 0x300 });

    // Both must be recoverable. The second of these was the bug: liveness was
    // asked as "is this the allocation base", which a secondary vptr never is.
    const primary_recovery = tracker.assessLowRead(object, 0, true).?;
    try std.testing.expectEqual(@as(u64, 0x1959688), primary_recovery.value);

    const secondary_recovery = tracker.assessLowRead(secondary, 0, true).?;
    try std.testing.expectEqual(@as(u64, 0x19596c0), secondary_recovery.value);
    try std.testing.expect(tracker.noteRecovery(secondary, secondary_recovery.generation));
}

// Freeing the object has to take its secondary slots with it. A stale
// secondary record outliving its object is worse than the null it repairs: the
// next occupant of that storage gets a previous class's vtable written into
// what is now a data member.
test "retiring an object retires every slot that belongs to it" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const object: u64 = 0x473dab0;
    const owned: types.Provenance = .{ .writer_rip = 0x1d74b4, .owner_base = object };
    _ = tracker.observeWrite(object, trustedEvidence(0x1959688, 0x10), owned);
    _ = tracker.observeWrite(object + 8, trustedEvidence(0x19596c0, 0x48), owned);
    // A different object's slot, which must survive.
    _ = tracker.observeWrite(0x5000, trustedEvidence(0x1950b28, 0x50), .{ .owner_base = 0x5000 });
    try std.testing.expectEqual(@as(usize, 3), tracker.trackedAllocationCount());

    try std.testing.expect(tracker.retireAddress(object));
    try std.testing.expectEqual(@as(usize, 1), tracker.trackedAllocationCount());
    try std.testing.expect(tracker.assessLowRead(object, 0, true) == null);
    try std.testing.expect(tracker.assessLowRead(object + 8, 0, true) == null);
    try std.testing.expect(tracker.assessLowRead(0x5000, 0, true) != null);
}

// Retirement must reach every slot the write side could have recorded. Both
// sides read `types.max_subobject_slots`; this pins that they agree, because a
// slot that can be tracked and cannot be retired is a stale vtable waiting for
// the storage to be reused.
test "retirement reaches the furthest slot the write side can record" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const object: u64 = 0x8000;
    const furthest = object + types.max_subobject_slots * 8;
    const owned: types.Provenance = .{ .owner_base = object };
    _ = tracker.observeWrite(object, trustedEvidence(0x1959688, 0x10), owned);
    _ = tracker.observeWrite(furthest, trustedEvidence(0x19596c0, 0x48), owned);
    try std.testing.expectEqual(@as(usize, 2), tracker.trackedAllocationCount());

    try std.testing.expect(tracker.retireAddress(object));
    try std.testing.expectEqual(@as(usize, 0), tracker.trackedAllocationCount());
}

// A slot claiming an owner it does not have must not be collateral damage when
// that owner is freed.
test "retirement does not take a slot owned by a different object" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const object: u64 = 0x8000;
    _ = tracker.observeWrite(object, trustedEvidence(0x1959688, 0x10), .{ .owner_base = object });
    // An adjacent object whose base happens to fall inside the probe window.
    _ = tracker.observeWrite(object + 8, trustedEvidence(0x1950b28, 0x50), .{ .owner_base = object + 8 });

    try std.testing.expect(tracker.retireAddress(object));
    try std.testing.expectEqual(@as(usize, 1), tracker.trackedAllocationCount());
    try std.testing.expect(tracker.lookupRecord(object + 8) != null);
}

// Ownership is recorded so the caller can refuse a repair into storage that has
// since been handed to something else.
test "a tracked slot remembers which object it belongs to" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const object: u64 = 0x473dab0;
    _ = tracker.observeWrite(
        object + 8,
        trustedEvidence(0x19596c0, 0x48),
        .{ .writer_rip = 0x1d74b4, .owner_base = object },
    );
    try std.testing.expectEqual(@as(u64, object), tracker.lookupRecord(object + 8).?.owner_base);

    // A caller that supplies no owner gets the slot itself, which preserves the
    // old behaviour for primary vptrs.
    _ = tracker.observeWrite(0x6000, trustedEvidence(0x1950b28, 0x50), .{});
    try std.testing.expectEqual(@as(u64, 0x6000), tracker.lookupRecord(0x6000).?.owner_base);
}

// The record is what authorises a repair. An address inside a live allocation
// that never held a trusted vtable is ordinary data and must stay untouched.
test "an untracked offset inside a live allocation is never repaired" {
    var tracker = VtableTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const object: u64 = 0x473dab0;
    _ = tracker.observeWrite(object, trustedEvidence(0x1959688, 0x10), .{ .writer_rip = 0x1d74b4 });
    // +0x10 is a data member, not a vptr slot: no record, so no proposal even
    // though the allocation is live and the value reads as zero.
    try std.testing.expect(tracker.assessLowRead(object + 0x10, 0, true) == null);
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
