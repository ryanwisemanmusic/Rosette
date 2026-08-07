//! When Rosette itself destroys a guest range's backing.
//!
//! Four subsystems keep state keyed by *guest address* and outlive the memory
//! they describe: write provenance ("who last stored here"), the provenance
//! watch set, the guest field-access profile, and the vtable tracker. The
//! address is the key, so none of them notices when the bytes behind that
//! address are replaced.
//!
//! The sparse manager replaces a mapping whenever a MAP_FIXED request matches
//! an existing range exactly — POSIX semantics, and correct — and it re-homes a
//! fixed mapping to an OS-chosen host base when the requested host address is
//! unavailable. Both discard the previous contents. Neither tells anyone.
//!
//! The observable consequence is a diagnosis that states a falsehood with
//! confidence. A dispatch target loaded from a field inside such a range reads
//! zero, write provenance holds no entry for it, and the runtime concludes "this
//! field was never written — look for the missing guest store". The guest may
//! well have written it; Rosette threw the write away. "Nobody ever stored here"
//! and "the storage was replaced under us" are different findings with different
//! fixes, and only this registry can tell them apart.
//!
//! It owns the *record*, not the policy: it does not decide what a consumer
//! should do about a discarded range, only that one happened, when, and how
//! many times. Zero-allocation and bounded, because it is consulted from fault
//! paths.

const std = @import("std");

/// Why the backing behind a guest range stopped being the backing the guest's
/// earlier stores went to.
pub const Reason = enum(u8) {
    /// A MAP_FIXED request matched an existing mapping exactly. The previous
    /// host pages were unmapped and the guest received fresh (zero) pages.
    fixed_map_replaced,
    /// The range was unmapped. Any later mapping at the same guest address is a
    /// different lifetime that happens to share a name.
    unmapped,
    /// The fixed mapping could not be placed at the requested host address and
    /// was re-homed to a host base the guest never asked for. The guest address
    /// still resolves; the host bytes behind it are new.
    rehomed,
};

pub const Record = struct {
    base: u64,
    size: u64,
    reason: Reason,
    /// How many discards this exact range has seen. A range discarded once may
    /// be ordinary lifecycle; a range discarded repeatedly is a pattern, and the
    /// count is the difference.
    generation: u32,
    /// Executed-step count at the most recent discard, so a consumer can ask
    /// whether its evidence predates the discard.
    step: u64,

    pub fn contains(self: Record, address: u64) bool {
        return address >= self.base and address - self.base < self.size;
    }
};

/// Fixed capacity. A registry that grows without bound would keep every heap
/// page a run ever recycled and answer "discarded" for all of them, which is
/// the same as answering nothing. Sixteen is comfortably more than the number
/// of distinct ranges a run re-maps in place, and overflow evicts the oldest
/// rather than dropping the newest — a stale record is worth less than a fresh
/// one, and the eviction is counted.
pub const max_entries: usize = 16;

pub const Registry = struct {
    entries: [max_entries]Record = undefined,
    /// Records currently retained, saturating at `max_entries`.
    count: usize = 0,
    /// Write cursor for the eviction ring.
    next: usize = 0,
    /// Discards recorded, including those that only bumped a generation.
    events: u64 = 0,
    /// Records evicted because the ring was full.
    evictions: u64 = 0,
    /// Queries that landed inside a discarded range.
    hits: u64 = 0,
    /// Queries that did not. With `hits`, the observed cost of consulting this.
    misses: u64 = 0,

    /// Record a discard. Re-discarding a range that is already recorded bumps
    /// its generation instead of consuming another slot, so a range re-mapped
    /// once per guest thread stays one record with an honest count.
    pub fn note(self: *Registry, base: u64, size: u64, reason: Reason, step: u64) void {
        if (size == 0) return;
        self.events +|= 1;
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const record = &self.entries[index];
            if (record.base != base or record.size != size) continue;
            record.generation +|= 1;
            record.reason = reason;
            record.step = step;
            return;
        }
        if (self.count == self.entries.len) self.evictions +|= 1;
        self.entries[self.next] = .{
            .base = base,
            .size = size,
            .reason = reason,
            .generation = 1,
            .step = step,
        };
        self.next = (self.next + 1) % self.entries.len;
        if (self.count < self.entries.len) self.count += 1;
    }

    /// The discard record covering `address`, counting the query. Returns the
    /// most recently written match, because a range discarded twice is best
    /// described by its latest discard.
    pub fn lookup(self: *Registry, address: u64) ?Record {
        const found = self.covers(address);
        if (found != null) self.hits +|= 1 else self.misses +|= 1;
        return found;
    }

    /// Non-mutating membership, for reporting and for callers that must not
    /// disturb the cost counters.
    pub fn covers(self: *const Registry, address: u64) ?Record {
        var found: ?Record = null;
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const record = self.entries[index];
            if (!record.contains(address)) continue;
            if (found == null or record.step >= found.?.step) found = record;
        }
        return found;
    }

    pub fn discarded(self: *const Registry, address: u64) bool {
        return self.covers(address) != null;
    }
};

test "a discarded range is remembered, an untouched address is not" {
    var registry = Registry{};
    try std.testing.expect(!registry.discarded(0x40e0000130));

    registry.note(0x40dfffc000, 19136, .fixed_map_replaced, 1000);
    const found = registry.lookup(0x40e0000130) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u64, 0x40dfffc000), found.base);
    try std.testing.expectEqual(Reason.fixed_map_replaced, found.reason);
    try std.testing.expectEqual(@as(u32, 1), found.generation);
    // One past the end is a different lifetime.
    try std.testing.expect(registry.lookup(0x40dfffc000 + 19136) == null);
    try std.testing.expectEqual(@as(u64, 1), registry.hits);
    try std.testing.expectEqual(@as(u64, 1), registry.misses);
}

test "re-discarding a range counts generations instead of consuming slots" {
    // The observed shape: one guest range re-mapped in place once per guest
    // thread. Six records of the same range would say less than one record
    // saying six.
    var registry = Registry{};
    var iteration: u32 = 0;
    while (iteration < 6) : (iteration += 1) {
        registry.note(0x40dfffc000, 19136, .fixed_map_replaced, 1000 + iteration);
    }
    try std.testing.expectEqual(@as(usize, 1), registry.count);
    try std.testing.expectEqual(@as(u64, 6), registry.events);
    const found = registry.covers(0x40e0000130) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 6), found.generation);
    try std.testing.expectEqual(@as(u64, 1005), found.step);
}

test "a range discarded before the evidence is distinguishable by step" {
    // The question a consumer actually asks: did the discard happen after the
    // last thing I know about this address? The record carries the step so the
    // consumer can answer it rather than guess.
    var registry = Registry{};
    registry.note(0x1000, 0x1000, .unmapped, 500);
    const found = registry.covers(0x1080) orelse return error.TestFailed;
    try std.testing.expect(found.step > 400);
    try std.testing.expect(found.step < 600);
}

test "capacity is bounded and eviction is counted, not silent" {
    var registry = Registry{};
    var page: u64 = 0;
    while (page < max_entries) : (page += 1) {
        registry.note(0x1_0000 + page * 0x1000, 0x1000, .unmapped, page);
    }
    try std.testing.expectEqual(@as(usize, max_entries), registry.count);
    try std.testing.expectEqual(@as(u64, 0), registry.evictions);

    registry.note(0x9999_0000, 0x1000, .rehomed, 999);
    try std.testing.expectEqual(@as(u64, 1), registry.evictions);
    // The newest record survived; the oldest is the one that went.
    try std.testing.expect(registry.discarded(0x9999_0000));
    try std.testing.expect(!registry.discarded(0x1_0000));
    // Everything after the evicted slot is still answerable.
    try std.testing.expect(registry.discarded(0x1_1000));
}

test "the most recent discard describes an overlapping range" {
    var registry = Registry{};
    registry.note(0x2000, 0x4000, .fixed_map_replaced, 100);
    registry.note(0x3000, 0x1000, .rehomed, 200);
    const found = registry.covers(0x3010) orelse return error.TestFailed;
    try std.testing.expectEqual(Reason.rehomed, found.reason);
    try std.testing.expectEqual(@as(u64, 200), found.step);
}

test "a zero-length discard is not a discard" {
    var registry = Registry{};
    registry.note(0x1000, 0, .unmapped, 1);
    try std.testing.expectEqual(@as(usize, 0), registry.count);
    try std.testing.expectEqual(@as(u64, 0), registry.events);
    try std.testing.expect(!registry.discarded(0x1000));
}
