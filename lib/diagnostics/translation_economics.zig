//! Cause-preserving decode-cache economics.
//!
//! A repeated miss does not prove executable code was rewritten. The cache
//! fill path already knows whether it used a vacant way, evicted a live entry,
//! rejected stale bytes, or refilled after a coarse flush. This ledger keeps
//! those causes separate globally and uses a bounded page table only to attach
//! the cost to useful addresses.

const std = @import("std");
const contract = @import("abi_translation_economics_contract");

pub const Cause = contract.Cause;
pub const Verdict = contract.Verdict;

pub const page_shift: u6 = 12;
/// Distinct conflicting addresses retained per page. Enough to tell a hot loop
/// from a working set that does not fit, and small enough that the sample stays
/// a fixed cost.
pub const conflict_witnesses: usize = 4;
pub const page_bytes: u64 = @as(u64, 1) << page_shift;
pub const sample_pages: usize = 512;

pub fn pageOf(address: u64) u64 {
    return address >> page_shift;
}

pub const PageRecord = struct {
    page: u64 = 0,
    occupied: bool = false,
    decodes: u64 = 0,
    vacant_fills: u64 = 0,
    conflict_fills: u64 = 0,
    cold_evictions: u64 = 0,
    stale_refills: u64 = 0,
    flush_refills: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// A concrete address inside the page whose fill was a conflict, so a
    /// reader can resolve a symbol rather than a page number. A page number
    /// says where the pressure is; a symbol says what is causing it, and the
    /// two are four kilobytes apart.
    conflict_address: u64 = 0,
    /// The distinct addresses inside this page seen conflicting, capped. One
    /// address conflicting three thousand times is a hot loop; three thousand
    /// addresses conflicting once each is a working set that does not fit, and
    /// those need opposite fixes.
    distinct_conflict_addresses: u32 = 0,
    recent_conflicts: [conflict_witnesses]u64 = [_]u64{0} ** conflict_witnesses,

    pub fn recurring(self: PageRecord) u64 {
        return self.conflict_fills +| self.stale_refills +| self.flush_refills;
    }

    fn note(self: *PageRecord, cause: Cause, address: u64) void {
        switch (cause) {
            .vacant_fill => self.vacant_fills +|= 1,
            .capacity_conflict => {
                self.conflict_fills +|= 1;
                self.noteConflictAddress(address);
            },
            .cold_eviction => self.cold_evictions +|= 1,
            .stale_bytes => self.stale_refills +|= 1,
            .flush_collateral => self.flush_refills +|= 1,
        }
    }

    fn noteConflictAddress(self: *PageRecord, address: u64) void {
        if (self.conflict_address == 0) self.conflict_address = address;
        for (self.recent_conflicts[0..]) |witness| {
            if (witness == address) return;
        }
        if (self.distinct_conflict_addresses < conflict_witnesses) {
            self.recent_conflicts[self.distinct_conflict_addresses] = address;
        }
        self.distinct_conflict_addresses +|= 1;
    }

    /// Whether the conflicts on this page come from more addresses than the
    /// witness list can hold. A page over the cap is a working set that does
    /// not fit; one under it is a small number of addresses evicting each
    /// other, which is an indexing problem rather than a capacity one.
    pub fn conflictsAreDispersed(self: PageRecord) bool {
        return self.distinct_conflict_addresses > conflict_witnesses;
    }

    pub fn witnesses(self: *const PageRecord) []const u64 {
        const held = @min(self.distinct_conflict_addresses, conflict_witnesses);
        return self.recent_conflicts[0..held];
    }
};

pub const Summary = struct {
    decodes: u64 = 0,
    vacant_fills: u64 = 0,
    conflict_fills: u64 = 0,
    cold_evictions: u64 = 0,
    stale_refills: u64 = 0,
    flush_refills: u64 = 0,
    sampled_pages: u64 = 0,
    /// Fill events whose page could not be attached to the bounded location
    /// sample. This is intentionally not called a distinct-page count.
    unsampled_events: u64 = 0,
    precise_invalidations: u64 = 0,
    wholesale_flushes: u64 = 0,
    invalidated_bytes: u64 = 0,
    hottest_page: u64 = 0,
    hottest_recurring: u64 = 0,

    pub fn verdict(self: Summary) Verdict {
        return contract.verdictOf(
            self.vacant_fills,
            self.conflict_fills,
            self.cold_evictions,
            self.stale_refills,
            self.flush_refills,
        );
    }

    pub fn conflictPercent(self: Summary) u64 {
        return contract.percentage(self.conflict_fills, self.decodes);
    }

    pub fn recoverableDecodes(self: Summary) u64 {
        return self.conflict_fills +| self.stale_refills +| self.flush_refills;
    }

    pub fn sampleComplete(self: Summary) bool {
        return self.unsampled_events == 0;
    }
};

pub const Ledger = struct {
    pages: [sample_pages]PageRecord = [_]PageRecord{.{}} ** sample_pages,
    occupied: usize = 0,

    decodes: u64 = 0,
    vacant_fills: u64 = 0,
    conflict_fills: u64 = 0,
    cold_evictions: u64 = 0,
    stale_refills: u64 = 0,
    flush_refills: u64 = 0,
    unsampled_events: u64 = 0,

    precise_invalidations: u64 = 0,
    wholesale_flushes: u64 = 0,
    invalidated_bytes: u64 = 0,

    fn slot(self: *Ledger, page: u64) ?*PageRecord {
        const mask = sample_pages - 1;
        var index: usize = @intCast(page & mask);
        var probes: usize = 0;
        while (probes < sample_pages) : (probes += 1) {
            const entry = &self.pages[index];
            if (!entry.occupied or entry.page == page) return entry;
            index = (index + 1) & mask;
        }
        return null;
    }

    /// Record one cache fill with the cause proven by the fill path.
    pub fn noteDecode(self: *Ledger, address: u64, step: u64, cause: Cause) void {
        self.decodes +|= 1;
        switch (cause) {
            .vacant_fill => self.vacant_fills +|= 1,
            .capacity_conflict => self.conflict_fills +|= 1,
            .cold_eviction => self.cold_evictions +|= 1,
            .stale_bytes => self.stale_refills +|= 1,
            .flush_collateral => self.flush_refills +|= 1,
        }

        const page = pageOf(address);
        const entry = self.slot(page) orelse {
            self.unsampled_events +|= 1;
            return;
        };
        if (!entry.occupied) {
            entry.* = .{
                .page = page,
                .occupied = true,
                .first_step = step,
                .last_step = step,
            };
            self.occupied += 1;
        }
        entry.decodes +|= 1;
        entry.last_step = step;
        entry.note(cause, address);
    }

    pub fn notePreciseInvalidation(self: *Ledger, address: u64, bytes: u64) void {
        _ = address;
        self.precise_invalidations +|= 1;
        self.invalidated_bytes +|= bytes;
    }

    pub fn noteWholesaleFlush(self: *Ledger, bytes: u64) void {
        self.wholesale_flushes +|= 1;
        self.invalidated_bytes +|= bytes;
    }

    pub fn summary(self: *const Ledger) Summary {
        var totals = Summary{
            .decodes = self.decodes,
            .vacant_fills = self.vacant_fills,
            .conflict_fills = self.conflict_fills,
            .cold_evictions = self.cold_evictions,
            .stale_refills = self.stale_refills,
            .flush_refills = self.flush_refills,
            .sampled_pages = @intCast(self.occupied),
            .unsampled_events = self.unsampled_events,
            .precise_invalidations = self.precise_invalidations,
            .wholesale_flushes = self.wholesale_flushes,
            .invalidated_bytes = self.invalidated_bytes,
        };
        for (self.pages) |entry| {
            if (!entry.occupied) continue;
            const recurring = entry.recurring();
            if (recurring > totals.hottest_recurring) {
                totals.hottest_recurring = recurring;
                totals.hottest_page = entry.page;
            }
        }
        return totals;
    }

    pub fn hottestPages(self: *const Ledger, out: []PageRecord) usize {
        var count: usize = 0;
        for (self.pages) |entry| {
            if (!entry.occupied or entry.recurring() == 0) continue;
            if (count < out.len) {
                out[count] = entry;
                count += 1;
            } else {
                var min_index: usize = 0;
                for (out[0..count], 0..) |candidate, index| {
                    if (candidate.recurring() < out[min_index].recurring()) min_index = index;
                }
                if (entry.recurring() > out[min_index].recurring()) out[min_index] = entry;
            }
        }
        std.mem.sort(PageRecord, out[0..count], {}, struct {
            fn lessThan(_: void, left: PageRecord, right: PageRecord) bool {
                if (left.recurring() != right.recurring()) return left.recurring() > right.recurring();
                return left.page < right.page;
            }
        }.lessThan);
        return count;
    }
};

test "capacity conflict is not reported as executable rewrite" {
    var ledger = Ledger{};
    ledger.noteDecode(0x2d2000, 1, .vacant_fill);
    ledger.noteDecode(0x2d2000, 2, .capacity_conflict);
    ledger.noteDecode(0x2d3000, 3, .capacity_conflict);
    const totals = ledger.summary();
    try std.testing.expectEqual(Verdict.cache_pressure, totals.verdict());
    try std.testing.expectEqual(@as(u64, 2), totals.conflict_fills);
    try std.testing.expectEqual(@as(u64, 0), totals.stale_refills);
}

test "cold eviction is not reported as hot cache pressure" {
    var ledger = Ledger{};
    ledger.noteDecode(0x2d2000, 1, .vacant_fill);
    ledger.noteDecode(0x2d2000, 2, .cold_eviction);
    ledger.noteDecode(0x2d3000, 3, .cold_eviction);
    const totals = ledger.summary();
    try std.testing.expectEqual(Verdict.warming, totals.verdict());
    try std.testing.expectEqual(@as(u64, 2), totals.cold_evictions);
    try std.testing.expectEqual(@as(u64, 0), totals.conflict_fills);
    var hot: [1]PageRecord = undefined;
    try std.testing.expectEqual(@as(usize, 0), ledger.hottestPages(&hot));
}

test "byte mismatch is the only executable rewrite evidence" {
    var ledger = Ledger{};
    ledger.noteDecode(0x1000, 1, .vacant_fill);
    ledger.noteDecode(0x1000, 2, .stale_bytes);
    try std.testing.expectEqual(Verdict.executable_rewrite, ledger.summary().verdict());
}

test "saturated sample preserves global causes" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < sample_pages + 7) : (index += 1) {
        ledger.noteDecode(@as(u64, @intCast(index)) * page_bytes, @intCast(index), .capacity_conflict);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, sample_pages + 7), totals.conflict_fills);
    try std.testing.expectEqual(@as(u64, 7), totals.unsampled_events);
    try std.testing.expect(!totals.sampleComplete());
}

test "hot pages rank by recurring fill cost" {
    var ledger = Ledger{};
    ledger.noteDecode(0x1000, 1, .vacant_fill);
    ledger.noteDecode(0x1000, 2, .capacity_conflict);
    ledger.noteDecode(0x2000, 3, .capacity_conflict);
    ledger.noteDecode(0x2000, 4, .capacity_conflict);
    var hot: [2]PageRecord = undefined;
    try std.testing.expectEqual(@as(usize, 2), ledger.hottestPages(&hot));
    try std.testing.expectEqual(@as(u64, 2), hot[0].page);
}

test "a page names a concrete conflicting address" {
    var ledger = Ledger{};
    ledger.noteDecode(0x26C_040, 10, .capacity_conflict);
    var hot: [1]PageRecord = undefined;
    try std.testing.expectEqual(@as(usize, 1), ledger.hottestPages(&hot));
    try std.testing.expectEqual(@as(u64, 0x26C_040), hot[0].conflict_address);
    try std.testing.expectEqual(@as(u32, 1), hot[0].distinct_conflict_addresses);
}

test "one address conflicting repeatedly is not a dispersed working set" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 50) : (round += 1) ledger.noteDecode(0x26C_040, round, .capacity_conflict);
    var hot: [1]PageRecord = undefined;
    _ = ledger.hottestPages(&hot);
    try std.testing.expectEqual(@as(u64, 50), hot[0].conflict_fills);
    try std.testing.expectEqual(@as(u32, 1), hot[0].distinct_conflict_addresses);
    try std.testing.expect(!hot[0].conflictsAreDispersed());
    try std.testing.expectEqual(@as(usize, 1), hot[0].witnesses().len);
}

test "many addresses conflicting once each is a dispersed working set" {
    var ledger = Ledger{};
    var offset: u64 = 0;
    while (offset < 40) : (offset += 1) ledger.noteDecode(0x26C_000 + offset * 8, offset, .capacity_conflict);
    var hot: [1]PageRecord = undefined;
    _ = ledger.hottestPages(&hot);
    try std.testing.expectEqual(@as(u32, 40), hot[0].distinct_conflict_addresses);
    try std.testing.expect(hot[0].conflictsAreDispersed());
    // The witness list stays bounded however many addresses are seen.
    try std.testing.expectEqual(conflict_witnesses, hot[0].witnesses().len);
}

test "a vacant fill never claims a conflicting address" {
    var ledger = Ledger{};
    ledger.noteDecode(0x26C_040, 10, .vacant_fill);
    // A page with no recurring cost is not a hotspot at all, which is the
    // first half of the claim.
    var hot: [1]PageRecord = undefined;
    try std.testing.expectEqual(@as(usize, 0), ledger.hottestPages(&hot));
    // And the record it did keep names no conflicting address.
    const entry = ledger.slot(pageOf(0x26C_040)).?;
    try std.testing.expectEqual(@as(u64, 1), entry.vacant_fills);
    try std.testing.expectEqual(@as(u64, 0), entry.conflict_address);
    try std.testing.expectEqual(@as(u32, 0), entry.distinct_conflict_addresses);
}
