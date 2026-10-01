//! Bounded counters for direct-TLB admission and cross-executor invalidation.
//! These are deliberately separate from the TLB itself: they explain why a
//! safe mapping stayed on the helper path without changing admission policy.

const std = @import("std");

pub const RefusalReason = enum(u8) {
    guest_no_access,
    guest_write_protected,
    native_device_alias,
    process_backing_bounds,
    executable_image_write,
    mapped_code_write,
    mapped_range_unbacked,
    unmapped_page,
};

pub const refusal_reason_count = @typeInfo(RefusalReason).@"enum".fields.len;
pub const no_page: u64 = std.math.maxInt(u64);

/// Fixed-size per-executor memo for stable TLB admission refusals. A hit only
/// skips repeating the admission proof; the actual translated memory access
/// still takes the coordinated helper, so cached device aliases retain their
/// device ordering boundary. Mapping/protection changes key the entry by the
/// shared TLB epoch. Stale entries are conservative too: they can only keep a
/// page on the helper path longer.
pub const refusal_cache_capacity = 1024;

pub const RefusalCache = struct {
    const Entry = struct {
        page: u64 = no_page,
        epoch: u64 = 0,
        reason: RefusalReason = .native_device_alias,
        is_write: bool = false,
    };

    entries: [refusal_cache_capacity]Entry = @splat(.{}),
    lookups: u64 = 0,
    hits: u64 = 0,
    misses: u64 = 0,

    pub fn lookup(self: *RefusalCache, page: u64, is_write: bool, epoch: u64) ?RefusalReason {
        self.lookups +|= 1;
        const entry = &self.entries[slotFor(page, is_write)];
        if (entry.page == page and entry.is_write == is_write and entry.epoch == epoch) {
            self.hits +|= 1;
            return entry.reason;
        }
        self.misses +|= 1;
        return null;
    }

    pub fn record(self: *RefusalCache, page: u64, is_write: bool, epoch: u64, reason: RefusalReason) void {
        self.entries[slotFor(page, is_write)] = .{
            .page = page,
            .epoch = epoch,
            .reason = reason,
            .is_write = is_write,
        };
    }

    fn slotFor(page: u64, is_write: bool) usize {
        var hash = page >> 12;
        hash ^= hash >> 33;
        hash *%= 0xff51_afd7_ed55_8ccd;
        hash ^= hash >> 33;
        if (is_write) hash ^= 0x9e37_79b9_7f4a_7c15;
        return @intCast(hash & (refusal_cache_capacity - 1));
    }
};

/// Per-executor counters. Each block-JIT state belongs to one executor, so
/// these remain plain integers on the miss path; `first_pages` helps a later
/// run identify the address class behind each aggregate.
pub const RefusalStats = struct {
    counts: [refusal_reason_count]u64 = @splat(0),
    first_pages: [refusal_reason_count]u64 = @splat(no_page),

    pub fn record(self: *RefusalStats, reason: RefusalReason, page: u64) void {
        const index = @intFromEnum(reason);
        self.counts[index] +|= 1;
        if (self.first_pages[index] == no_page) self.first_pages[index] = page;
    }

    pub fn merge(self: *RefusalStats, other: RefusalStats) void {
        for (&self.counts, other.counts, 0..) |*count, other_count, index| {
            count.* +|= other_count;
            if (self.first_pages[index] == no_page and other.first_pages[index] != no_page) {
                self.first_pages[index] = other.first_pages[index];
            }
        }
    }

    /// One compact summary, in enum order, with a first example guest page.
    pub fn format(self: RefusalStats, buffer: []u8) []const u8 {
        var written: usize = 0;
        inline for (std.meta.fields(RefusalReason), 0..) |field, index| {
            const reason: RefusalReason = @enumFromInt(index);
            const page = self.first_pages[index];
            const piece = if (page == no_page)
                std.fmt.bufPrint(buffer[written..], " {s}={d}", .{ @tagName(reason), self.counts[index] }) catch break
            else
                std.fmt.bufPrint(buffer[written..], " {s}={d}@0x{x}", .{ field.name, self.counts[index], page }) catch break;
            written += piece.len;
        }
        return buffer[0..written];
    }
};

pub const InvalidationSnapshot = struct {
    range_calls: u64,
    requested_pages: u64,
    wide_range_flushes: u64,
    explicit_flushes: u64,
    table_visits: u64,
    tag_slots_touched: u64,
};

/// Process-wide work estimates for cross-executor invalidations. They count
/// the tags the invalidator probes or writes, not TLB misses or guest memory
/// operations. Atomic updates are only made on mapping/protection changes.
pub const InvalidationWork = struct {
    range_calls: std.atomic.Value(u64) = .init(0),
    requested_pages: std.atomic.Value(u64) = .init(0),
    wide_range_flushes: std.atomic.Value(u64) = .init(0),
    explicit_flushes: std.atomic.Value(u64) = .init(0),
    table_visits: std.atomic.Value(u64) = .init(0),
    tag_slots_touched: std.atomic.Value(u64) = .init(0),

    pub fn noteRange(
        self: *InvalidationWork,
        pages: u64,
        table_count: u64,
        entries: u64,
        scan_limit: u64,
    ) void {
        _ = self.range_calls.fetchAdd(1, .monotonic);
        _ = self.requested_pages.fetchAdd(pages, .monotonic);
        _ = self.table_visits.fetchAdd(table_count, .monotonic);
        const wide = pages >= @min(entries, scan_limit);
        if (wide) _ = self.wide_range_flushes.fetchAdd(1, .monotonic);
        const slots_per_table = if (wide) entries * 2 else pages * 2;
        _ = self.tag_slots_touched.fetchAdd(slots_per_table * table_count, .monotonic);
    }

    pub fn noteFlush(self: *InvalidationWork, reads: bool, writes: bool, table_count: u64, entries: u64) void {
        _ = self.explicit_flushes.fetchAdd(1, .monotonic);
        _ = self.table_visits.fetchAdd(table_count, .monotonic);
        const directions: u64 = @as(u64, @intFromBool(reads)) + @as(u64, @intFromBool(writes));
        _ = self.tag_slots_touched.fetchAdd(entries * directions * table_count, .monotonic);
    }

    pub fn snapshot(self: *const InvalidationWork) InvalidationSnapshot {
        return .{
            .range_calls = self.range_calls.load(.monotonic),
            .requested_pages = self.requested_pages.load(.monotonic),
            .wide_range_flushes = self.wide_range_flushes.load(.monotonic),
            .explicit_flushes = self.explicit_flushes.load(.monotonic),
            .table_visits = self.table_visits.load(.monotonic),
            .tag_slots_touched = self.tag_slots_touched.load(.monotonic),
        };
    }
};

test "TLB refusal stats preserve per-reason counts and first pages when merged" {
    var first: RefusalStats = .{};
    first.record(.native_device_alias, 0x2000);
    first.record(.native_device_alias, 0x2000);
    var second: RefusalStats = .{};
    second.record(.native_device_alias, 0x9000);
    second.record(.mapped_code_write, 0xA000);

    first.merge(second);
    try std.testing.expectEqual(@as(u64, 3), first.counts[@intFromEnum(RefusalReason.native_device_alias)]);
    try std.testing.expectEqual(@as(u64, 0x2000), first.first_pages[@intFromEnum(RefusalReason.native_device_alias)]);
    try std.testing.expectEqual(@as(u64, 1), first.counts[@intFromEnum(RefusalReason.mapped_code_write)]);
    try std.testing.expectEqual(@as(u64, 0xA000), first.first_pages[@intFromEnum(RefusalReason.mapped_code_write)]);
}

test "TLB refusal cache keys direction and epoch and reports saved admission checks" {
    var cache: RefusalCache = .{};
    const page = 0x7040_4c0000;

    try std.testing.expect(cache.lookup(page, false, 7) == null);
    cache.record(page, false, 7, .native_device_alias);
    try std.testing.expectEqual(RefusalReason.native_device_alias, cache.lookup(page, false, 7).?);
    try std.testing.expect(cache.lookup(page, true, 7) == null);
    try std.testing.expect(cache.lookup(page, false, 8) == null);
    cache.record(page, true, 8, .executable_image_write);
    try std.testing.expectEqual(RefusalReason.executable_image_write, cache.lookup(page, true, 8).?);
    try std.testing.expectEqual(@as(u64, 5), cache.lookups);
    try std.testing.expectEqual(@as(u64, 2), cache.hits);
    try std.testing.expectEqual(@as(u64, 3), cache.misses);
}

test "TLB invalidation work distinguishes page ranges from full-table flushes" {
    var work: InvalidationWork = .{};
    work.noteRange(3, 4, 8192, 1024);
    work.noteRange(2048, 4, 8192, 1024);
    work.noteFlush(false, true, 4, 8192);
    const snapshot = work.snapshot();
    try std.testing.expectEqual(@as(u64, 2), snapshot.range_calls);
    try std.testing.expectEqual(@as(u64, 2051), snapshot.requested_pages);
    try std.testing.expectEqual(@as(u64, 1), snapshot.wide_range_flushes);
    try std.testing.expectEqual(@as(u64, 1), snapshot.explicit_flushes);
    try std.testing.expectEqual(@as(u64, 12), snapshot.table_visits);
    try std.testing.expectEqual(@as(u64, 3 * 2 * 4 + 8192 * 2 * 4 + 8192 * 4), snapshot.tag_slots_touched);
}
