//! Which guest memory Rosette keeps provenance for.
//!
//! Write provenance answers "who last stored here", and it is the only thing
//! that can distinguish a field someone *cleared* from a field nobody ever
//! *initialised* — different bugs with different fixes. It was gated behind
//! `ROSETTE_MACHO_WRITE_DIAGNOSTICS`, off by default, because recording a
//! before-image for every guest store across ~1.5 billion steps is not
//! affordable.
//!
//! So the run kept ending with "the single remaining question is who wrote this
//! field; re-run with the flag" — a diagnostic that knows exactly what it needs
//! and cannot have it. A flag is a bad answer to that: it asks the operator to
//! predict, before the run, which address will matter.
//!
//! A watch set is the affordable version. Provenance is recorded for a small,
//! bounded set of regions rather than for everything, and the regions are
//! **discovered from behaviour**: generated code reveals which structures it
//! treats as state every time it addresses one with a small displacement from a
//! base register. Watching those pages costs a handful of range compares per
//! store and covers exactly the fields these faults are about.

const std = @import("std");

pub const page_size: u64 = 0x1000;

pub const Region = struct {
    base: u64,
    size: u64,

    pub fn contains(self: Region, address: u64) bool {
        return address >= self.base and address - self.base < self.size;
    }
};

/// Why a region became watched. Reported so a run can distinguish a region it
/// chose from one the operator forced.
pub const Origin = enum {
    /// Seeded from a generated-code memory operand: base register plus a small
    /// displacement, which is how compiled code addresses a structure field.
    generated_structure_base,
    /// Registered explicitly by a subsystem that knows what it needs.
    declared,
};

pub const Entry = struct {
    region: Region,
    origin: Origin,
    /// Stores recorded because of this entry.
    hits: u64 = 0,
};

/// Fixed capacity: a watch set that can grow without bound is just the global
/// flag again, with worse locality. Eight pages covers the guest context and
/// its immediate neighbours; overflow is counted and reported rather than
/// silently dropping evidence.
pub const max_entries: usize = 8;
const index_capacity: usize = 16;

/// A displacement larger than this is not a structure field access — it is an
/// array index or an unrelated computation, and seeding on it would watch
/// arbitrary memory.
pub const max_field_displacement: u64 = 0x1000;

pub const Set = struct {
    entries: [max_entries]Entry = undefined,
    count: usize = 0,
    // Open-addressed page index. The previous implementation linearly walked
    // all watched pages on every interpreted store. Eight entries sounds
    // small, but that scan sits inside capture and commit and therefore grows
    // into billions of comparisons during Xenia's JIT emission. Zero means an
    // empty slot; populated slots store entry index + 1.
    page_index: [index_capacity]u8 = [_]u8{0} ** index_capacity,
    /// Seed attempts that arrived after the set was full.
    overflows: u64 = 0,
    /// Stores that matched some watched region.
    recorded: u64 = 0,
    /// Stores checked and not matched. With `recorded`, this is the observed
    /// cost of the mechanism.
    rejected: u64 = 0,

    fn initialSlot(page_base: u64) usize {
        const page = page_base / page_size;
        const mixed = page ^ (page >> 16) ^ (page >> 32);
        return @as(usize, @truncate(mixed)) & (index_capacity - 1);
    }

    fn entryIndexFor(self: *const Set, address: u64) ?usize {
        const page_base = address & ~(page_size - 1);
        var slot = initialSlot(page_base);
        var probes: usize = 0;
        while (probes < index_capacity) : (probes += 1) {
            const encoded = self.page_index[slot];
            if (encoded == 0) return null;
            const entry_index: usize = encoded - 1;
            if (self.entries[entry_index].region.contains(address)) return entry_index;
            slot = (slot + 1) & (index_capacity - 1);
        }
        return null;
    }

    fn indexEntry(self: *Set, entry_index: usize) void {
        const page_base = self.entries[entry_index].region.base;
        var slot = initialSlot(page_base);
        var probes: usize = 0;
        while (probes < index_capacity) : (probes += 1) {
            if (self.page_index[slot] == 0) {
                self.page_index[slot] = @intCast(entry_index + 1);
                return;
            }
            slot = (slot + 1) & (index_capacity - 1);
        }
        unreachable;
    }

    pub fn contains(self: *Set, address: u64) bool {
        if (self.entryIndexFor(address)) |entry_index| {
            self.entries[entry_index].hits +|= 1;
            self.recorded +|= 1;
            return true;
        }
        self.rejected +|= 1;
        return false;
    }

    /// Non-mutating membership, for reporting.
    pub fn covers(self: *const Set, address: u64) bool {
        return self.entryIndexFor(address) != null;
    }

    pub fn watchPage(self: *Set, address: u64, origin: Origin) bool {
        const base = address & ~(page_size - 1);
        if (self.entryIndexFor(base) != null) return false;
        if (self.count == self.entries.len) {
            self.overflows +|= 1;
            return false;
        }
        const entry_index = self.count;
        self.entries[entry_index] = .{
            .region = .{ .base = base, .size = page_size },
            .origin = origin,
        };
        self.count += 1;
        self.indexEntry(entry_index);
        return true;
    }

    /// Seed from a generated-code memory operand. Returns true when a new page
    /// was added.
    ///
    /// The displacement gate is what keeps this a structure-field heuristic
    /// rather than "watch whatever generated code touches": compiled code
    /// reaches a field as `base + small constant`, and an operand with a large
    /// or register-computed displacement is indexing, not field access.
    pub fn seedFromOperand(self: *Set, base_value: u64, displacement: u64) bool {
        if (base_value == 0) return false;
        if (displacement == 0 or displacement > max_field_displacement) return false;
        return self.watchPage(base_value +% displacement, .generated_structure_base);
    }

    pub fn full(self: *const Set) bool {
        return self.count == self.entries.len;
    }
};

test "a watched page records, an unwatched address does not" {
    var set = Set{};
    try std.testing.expect(!set.contains(0x40e0000130));

    try std.testing.expect(set.watchPage(0x40e0000130, .declared));
    try std.testing.expect(set.contains(0x40e0000130));
    // Same page, different field.
    try std.testing.expect(set.contains(0x40e0000ff8));
    // Next page along is not covered.
    try std.testing.expect(!set.contains(0x40e0001000));
    try std.testing.expectEqual(@as(u64, 2), set.recorded);
    try std.testing.expectEqual(@as(u64, 2), set.rejected);
}

test "seeding is idempotent per page" {
    var set = Set{};
    try std.testing.expect(set.seedFromOperand(0x40e0000000, 0x130));
    // A different field of the same structure must not consume another slot.
    try std.testing.expect(!set.seedFromOperand(0x40e0000000, 0x138));
    try std.testing.expectEqual(@as(usize, 1), set.count);
    try std.testing.expectEqual(Origin.generated_structure_base, set.entries[0].origin);
}

test "only small displacements look like structure fields" {
    var set = Set{};
    // Array indexing or an unrelated computation: watching this would put
    // arbitrary memory under provenance.
    try std.testing.expect(!set.seedFromOperand(0x40e0000000, 0x8000));
    // A zero displacement is a plain pointer dereference, not a field.
    try std.testing.expect(!set.seedFromOperand(0x40e0000000, 0));
    // A null base is never a structure.
    try std.testing.expect(!set.seedFromOperand(0, 0x130));
    try std.testing.expectEqual(@as(usize, 0), set.count);
}

test "capacity is bounded and overflow is counted, not silent" {
    var set = Set{};
    var page: u64 = 0;
    while (page < max_entries) : (page += 1) {
        try std.testing.expect(set.watchPage(page * page_size, .declared));
    }
    try std.testing.expect(set.full());
    try std.testing.expect(!set.watchPage(0x9999_0000, .declared));
    try std.testing.expectEqual(@as(u64, 1), set.overflows);
    // The set that filled up still works for what it holds.
    try std.testing.expect(set.contains(0));
}

test "covers does not disturb the counters used to report cost" {
    var set = Set{};
    _ = set.watchPage(0x1000, .declared);
    try std.testing.expect(set.covers(0x1010));
    try std.testing.expect(!set.covers(0x2000));
    try std.testing.expectEqual(@as(u64, 0), set.recorded);
    try std.testing.expectEqual(@as(u64, 0), set.rejected);
}

test "page index resolves collisions without scanning the watch set" {
    var set = Set{};
    // These page numbers share the same initial slot in the compact index.
    try std.testing.expect(set.watchPage(0, .declared));
    try std.testing.expect(set.watchPage(0x1_0000, .declared));
    try std.testing.expect(set.contains(0x80));
    try std.testing.expect(set.contains(0x1_0080));
    try std.testing.expect(!set.contains(0x2_0080));
}
