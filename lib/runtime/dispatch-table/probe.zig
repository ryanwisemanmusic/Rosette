//! What a zero entry in a dispatch table actually means.
//!
//! A dynamic binary translator keeps a table of code pointers indexed by guest
//! address, and its generated code dispatches through it: load the slot, jump to
//! it. When the load yields zero the runtime has to decide what happened, and
//! the three possibilities need three different responses:
//!
//!   * The table was **never populated** — every neighbour is zero too. The
//!     host program's fill never ran, or its stores never landed. Nothing about
//!     this guest address is special; the whole region is dead.
//!   * The table holds a **uniform default** — every neighbour holds one
//!     identical non-zero value. That value is the host's not-yet-translated
//!     thunk, and *this* slot being zero is a genuine anomaly: something cleared
//!     one entry out of a populated table.
//!   * The table is **populated** with distinct targets, and a zero among them
//!     is an entry that was never filled in a region that otherwise was.
//!
//! From the faulting slot alone these are indistinguishable, and a runtime that
//! cannot distinguish them will report "dispatch target was null" for all three
//! — which is true, useless, and the same sentence every time. The neighbourhood
//! is what separates them, and it costs a bounded number of reads on a path that
//! is already printing diagnostics.
//!
//! Deliberately not a table *implementation*: this owns the question asked of a
//! table it does not manage, so it makes no assumption about who fills it, how
//! wide an entry is, or whether the index is scaled.

const std = @import("std");

pub const Population = enum {
    /// Not one neighbour could be read. The region is unmapped or protected;
    /// nothing can be concluded about the table.
    unreadable,
    /// Every readable neighbour is zero. The table was never filled here.
    all_zero,
    /// Every readable non-zero neighbour holds the *same* value, and none is
    /// zero. That value is the host's default entry, and a zero slot inside
    /// this region is an anomaly rather than an absence.
    uniform_default,
    /// Neighbours hold distinct non-zero values: real, resolved targets.
    populated,
    /// A mix of zero and non-zero. The fill covered part of this region.
    sparse,

    /// Whether the zero that prompted the probe stands out from its
    /// neighbourhood. False means the zero is the region's normal state and the
    /// question to ask is about the fill, not about this address.
    pub fn zeroIsAnomalous(self: Population) bool {
        return self == .uniform_default or self == .populated or self == .sparse;
    }
};

pub const Result = struct {
    population: Population = .unreadable,
    /// Slots the probe attempted, including the faulting one.
    sampled: u16 = 0,
    readable: u16 = 0,
    zero: u16 = 0,
    nonzero: u16 = 0,
    /// The most frequent non-zero value, and how many neighbours held it. When
    /// `population` is `.uniform_default` this is the host's default entry —
    /// which is the address the dispatch *would* have reached had the slot been
    /// filled, and therefore the single most useful value the probe recovers.
    dominant_value: u64 = 0,
    dominant_count: u16 = 0,
    /// Non-zero values that differed from `dominant_value`. Non-zero here is
    /// what separates a populated table from a defaulted one.
    distinct_values: u16 = 0,
    /// Bounds actually covered, so a reader can tell how far the evidence goes.
    first_slot: u64 = 0,
    last_slot: u64 = 0,

    pub fn describe(self: Result) []const u8 {
        return switch (self.population) {
            .unreadable => "no neighbouring slot could be read; the table region is unmapped or unreadable and nothing can be concluded from this fault",
            .all_zero => "every neighbouring slot is zero as well — this table region was NEVER FILLED. The zero is not about this guest address: look for the host's table-fill (its commit/initialise path) and whether its stores reached this range, not for anything specific to the target",
            .uniform_default => "every neighbouring slot holds one identical non-zero value — that is the host's default/not-yet-translated entry, so the fill DID run here and this single slot was cleared or skipped. `dominant_value` is where the dispatch would have gone; that is the resolver the host expected to reach",
            .populated => "neighbouring slots hold distinct non-zero targets, so this region is populated with resolved code and this entry alone is missing",
            .sparse => "neighbouring slots are a mix of zero and non-zero: the fill covered part of this region only, so the boundary of the fill is the thing to find",
        };
    }
};

/// Sample `radius` slots either side of `slot_address` and classify.
///
/// `read` returns the entry value or null when the slot cannot be read.
/// `entry_bytes` is the table's entry width; slots are assumed contiguous,
/// which is the only structural assumption made here.
pub fn probe(
    comptime Context: type,
    context: Context,
    slot_address: u64,
    entry_bytes: u64,
    radius: u16,
    read: *const fn (Context, u64, u64) ?u64,
) Result {
    var result = Result{};
    if (entry_bytes == 0 or radius == 0) return result;

    const span: u64 = @as(u64, radius) * entry_bytes;
    const first = slot_address -| span;
    const last = slot_address +| span;
    result.first_slot = first;
    result.last_slot = last;

    // Tracked without allocation: the dominant value plus a count of everything
    // that disagreed with it is enough to separate "one default everywhere"
    // from "many real targets", which is the only distinction that matters.
    var dominant: u64 = 0;
    var dominant_count: u16 = 0;
    var differing: u16 = 0;

    var address = first;
    while (address <= last) : (address +|= entry_bytes) {
        result.sampled +|= 1;
        const value = read(context, address, entry_bytes) orelse {
            if (address > std.math.maxInt(u64) - entry_bytes) break;
            continue;
        };
        result.readable +|= 1;
        if (value == 0) {
            result.zero +|= 1;
        } else {
            result.nonzero +|= 1;
            if (dominant_count == 0) {
                dominant = value;
                dominant_count = 1;
            } else if (value == dominant) {
                dominant_count +|= 1;
            } else {
                differing +|= 1;
            }
        }
        if (address > std.math.maxInt(u64) - entry_bytes) break;
    }

    result.dominant_value = dominant;
    result.dominant_count = dominant_count;
    result.distinct_values = differing;

    if (result.readable == 0) {
        result.population = .unreadable;
    } else if (result.nonzero == 0) {
        result.population = .all_zero;
    } else if (result.zero <= 1 and differing == 0) {
        // At most the faulting slot is zero and every other value agrees: a
        // defaulted table with one hole.
        result.population = .uniform_default;
    } else if (result.zero <= 1) {
        result.population = .populated;
    } else {
        result.population = .sparse;
    }
    return result;
}

const TestTable = struct {
    base: u64,
    entries: []const u32,

    fn read(self: TestTable, address: u64, bytes: u64) ?u64 {
        if (bytes != 4) return null;
        if (address < self.base) return null;
        const index = (address - self.base) / 4;
        if (index >= self.entries.len) return null;
        return self.entries[@intCast(index)];
    }
};

test "a table that was never filled is not a fact about the faulting address" {
    const entries = [_]u32{0} ** 17;
    const table = TestTable{ .base = 0x8200_0000, .entries = &entries };
    const found = probe(TestTable, table, 0x8200_0020, 4, 8, TestTable.read);
    try std.testing.expectEqual(Population.all_zero, found.population);
    try std.testing.expect(!found.population.zeroIsAnomalous());
    try std.testing.expectEqual(@as(u16, 17), found.readable);
    try std.testing.expectEqual(@as(u16, 17), found.zero);
}

// The case that decides where the dispatch should have gone: the fill ran, the
// default is visible in every neighbour, and one slot is missing it.
test "a uniform default names the resolver the dispatch should have reached" {
    var entries = [_]u32{0xA000_1234} ** 17;
    entries[8] = 0; // the faulting slot
    const table = TestTable{ .base = 0x8200_0000, .entries = &entries };
    const found = probe(TestTable, table, 0x8200_0020, 4, 8, TestTable.read);
    try std.testing.expectEqual(Population.uniform_default, found.population);
    try std.testing.expect(found.population.zeroIsAnomalous());
    try std.testing.expectEqual(@as(u64, 0xA000_1234), found.dominant_value);
    try std.testing.expectEqual(@as(u16, 16), found.dominant_count);
    try std.testing.expectEqual(@as(u16, 0), found.distinct_values);
}

test "distinct targets are a populated region, not a defaulted one" {
    var entries: [17]u32 = undefined;
    for (&entries, 0..) |*entry, index| entry.* = @intCast(0xA000_0000 + index * 0x40);
    entries[8] = 0;
    const table = TestTable{ .base = 0x8200_0000, .entries = &entries };
    const found = probe(TestTable, table, 0x8200_0020, 4, 8, TestTable.read);
    try std.testing.expectEqual(Population.populated, found.population);
    try std.testing.expect(found.population.zeroIsAnomalous());
    try std.testing.expect(found.distinct_values > 0);
}

test "a partial fill is reported as its own finding" {
    var entries = [_]u32{0} ** 17;
    for (entries[0..6]) |*entry| entry.* = 0xA000_1234;
    const table = TestTable{ .base = 0x8200_0000, .entries = &entries };
    const found = probe(TestTable, table, 0x8200_0020, 4, 8, TestTable.read);
    try std.testing.expectEqual(Population.sparse, found.population);
    try std.testing.expectEqual(@as(u16, 6), found.nonzero);
    try std.testing.expectEqual(@as(u16, 11), found.zero);
}

test "an unreadable region concludes nothing rather than guessing" {
    const entries = [_]u32{};
    const table = TestTable{ .base = 0x8200_0000, .entries = &entries };
    const found = probe(TestTable, table, 0x8200_0020, 4, 8, TestTable.read);
    try std.testing.expectEqual(Population.unreadable, found.population);
    try std.testing.expect(!found.population.zeroIsAnomalous());
    try std.testing.expectEqual(@as(u16, 0), found.readable);
}

test "a zero radius or entry width probes nothing instead of looping" {
    const entries = [_]u32{0xA000_1234} ** 4;
    const table = TestTable{ .base = 0x8200_0000, .entries = &entries };
    try std.testing.expectEqual(
        Population.unreadable,
        probe(TestTable, table, 0x8200_0000, 4, 0, TestTable.read).population,
    );
    try std.testing.expectEqual(
        Population.unreadable,
        probe(TestTable, table, 0x8200_0000, 0, 8, TestTable.read).population,
    );
}
