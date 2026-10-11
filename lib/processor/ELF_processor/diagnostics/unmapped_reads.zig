//! Reads of memory nothing maps, counted by page with their first reader.
//!
//! A Windows process reads several structures the OS provides without any
//! call: KUSER_SHARED_DATA at 0x7FFE0000, the TEB through gs, the PEB. A
//! structure Rosette does not provide reads as zeros, silently: for every
//! run until 2026-10-02 the guest's interrupt time was zero because Xenia
//! took it from KUSER_SHARED_DATA, and nothing said so. This census names
//! every such page and the code that read it first, so the next missing
//! structure is a log line rather than a stall.
//!
//! Lock-free: a page claims a slot with one compare-and-swap and is counted
//! with a relaxed add; only the unmapped path, never a mapped access, comes
//! here.

const std = @import("std");

pub const capacity = 32;

pub const Entry = struct {
    page: std.atomic.Value(u64) = .init(0),
    reads: std.atomic.Value(u64) = .init(0),
    first_rip: std.atomic.Value(u64) = .init(0),
    first_address: std.atomic.Value(u64) = .init(0),
};

pub const Census = struct {
    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    overflow: std.atomic.Value(u64) = .init(0),

    /// Count one unmapped read of `address` by the instruction at `rip`.
    pub fn note(self: *Census, address: u64, rip: u64) void {
        const page = (address & ~@as(u64, 0xFFF)) | 1; // never zero
        var index: usize = @intCast(((page >> 12) *% 0x9E37_79B9) % capacity);
        var probes: usize = 0;
        while (probes < capacity) : (probes += 1) {
            const entry = &self.entries[index];
            const current = entry.page.load(.acquire);
            if (current == page) {
                _ = entry.reads.fetchAdd(1, .monotonic);
                return;
            }
            if (current == 0) {
                if (entry.page.cmpxchgStrong(0, page, .acq_rel, .acquire) == null) {
                    entry.first_rip.store(rip, .monotonic);
                    entry.first_address.store(address, .monotonic);
                    _ = entry.reads.fetchAdd(1, .monotonic);
                    return;
                }
                continue;
            }
            index = (index + 1) % capacity;
        }
        _ = self.overflow.fetchAdd(1, .monotonic);
    }

    /// The `out.len` most-read pages, most first.
    pub fn top(self: *const Census, out: []*const Entry) []*const Entry {
        var count: usize = 0;
        for (&self.entries) |*entry| {
            if (entry.page.load(.acquire) == 0) continue;
            const reads = entry.reads.load(.monotonic);
            var position = count;
            while (position > 0 and out[position - 1].reads.load(.monotonic) < reads) position -= 1;
            if (position >= out.len) continue;
            var move: usize = @min(count, out.len - 1);
            while (move > position) : (move -= 1) out[move] = out[move - 1];
            out[position] = entry;
            if (count < out.len) count += 1;
        }
        return out[0..count];
    }
};

pub fn pageOf(entry: *const Entry) u64 {
    return entry.page.load(.acquire) & ~@as(u64, 0xFFF);
}

test "the census counts unmapped reads by page and keeps the first reader" {
    var census = Census{};
    census.note(0x7FFE_0008, 0x1405_9CE20);
    census.note(0x7FFE_0010, 0x1405_9CE40);
    census.note(0x1000_0004, 0x1400_1000);
    var storage: [4]*const Entry = undefined;
    const ranked = census.top(&storage);
    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqual(@as(u64, 0x7FFE_0000), pageOf(ranked[0]));
    try std.testing.expectEqual(@as(u64, 2), ranked[0].reads.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0x1405_9CE20), ranked[0].first_rip.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0x7FFE_0008), ranked[0].first_address.load(.monotonic));
}
