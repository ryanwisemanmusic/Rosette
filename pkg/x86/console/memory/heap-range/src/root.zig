//! x86-64-route page-range selection for Xenia's guest memory heaps.
//!
//! This package is intentionally a selector, not an allocator. Xenia owns the
//! page-table lock, host mapping, allocation state writes, and release
//! semantics. The provider receives the page-table qwords while Xenia holds
//! that lock and returns only a candidate base page. A missing provider is
//! safe: Xenia retains its reference scan.

const std = @import("std");

pub const host_architecture = "x86_64";
pub const host_codegen = "x86_64-native-bridge";
pub const abi_version: u32 = 1;
pub const no_page: u32 = std.math.maxInt(u32);

// PageEntry is a qword in Xenia. The state bitfield occupies bits 48..49:
// base_address:20, region_page_count:20, allocation_protect:4,
// current_protect:4, state:2, reserved:14.
pub const page_state_shift: u6 = 48;
pub const page_state_mask: u64 = 0x3;

/// Describes how a page allocator encodes its free/reserved state in each
/// entry. The selector only reads this field; it never interprets or changes
/// the rest of an allocator's entry format.
pub const PageStateLayout = struct {
    shift: u6,
    mask: u64,
    free_value: u64 = 0,

    pub fn isValid(self: PageStateLayout) bool {
        const max_value: u64 = std.math.maxInt(u64);
        return self.mask != 0 and (self.free_value & ~self.mask) == 0 and
            self.mask <= (max_value >> self.shift);
    }
};

/// Xenia's current PageEntry stores its two-bit state at bits 48..49.
pub const xenia_page_state_layout = PageStateLayout{
    .shift = page_state_shift,
    .mask = page_state_mask,
};

pub fn pageIsFreeWithLayout(entry: u64, layout: PageStateLayout) bool {
    if (!layout.isValid()) return false;
    return ((entry >> layout.shift) & layout.mask) == layout.free_value;
}

pub fn pageIsFree(entry: u64) bool {
    return pageIsFreeWithLayout(entry, xenia_page_state_layout);
}

fn roundUp(value: u32, multiple: u32) ?u32 {
    if (multiple == 0) return null;
    const remainder = value % multiple;
    if (remainder == 0) return value;
    return std.math.add(u32, value, multiple - remainder) catch null;
}

fn rangeIsFree(
    entries: [*]const u64,
    total_page_count: u32,
    base_page: u32,
    allocation_pages: u32,
    state_layout: PageStateLayout,
) bool {
    if (base_page >= total_page_count or
        allocation_pages > total_page_count - base_page)
    {
        return false;
    }

    var page = base_page;
    const end_page = base_page + allocation_pages;
    while (page < end_page) : (page += 1) {
        if (!pageIsFreeWithLayout(entries[@intCast(page)], state_layout)) return false;
    }
    return true;
}

fn selectTopDown(
    entries: [*]const u64,
    total_page_count: u32,
    low_page: u32,
    search_high_page: u32,
    allocation_pages: u32,
    alignment_pages: u32,
    state_layout: PageStateLayout,
) ?u32 {
    var candidate: i64 = @intCast(search_high_page -
        (search_high_page % alignment_pages));
    const low: i64 = @intCast(low_page);
    const stride: i64 = @intCast(alignment_pages);

    while (candidate >= low) : (candidate -= stride) {
        const base_page: u32 = @intCast(candidate);
        if (rangeIsFree(entries, total_page_count, base_page, allocation_pages, state_layout)) {
            return base_page;
        }
    }
    return null;
}

fn selectBottomUp(
    entries: [*]const u64,
    total_page_count: u32,
    low_page: u32,
    high_page: u32,
    allocation_pages: u32,
    alignment_pages: u32,
    state_layout: PageStateLayout,
) ?u32 {
    const last_candidate = high_page - allocation_pages;
    var candidate = low_page;
    while (candidate <= last_candidate) : (candidate += alignment_pages) {
        if (rangeIsFree(entries, total_page_count, candidate, allocation_pages, state_layout)) {
            return candidate;
        }
        if (candidate > std.math.maxInt(u32) - alignment_pages) break;
    }
    return null;
}

/// Select a range using caller-supplied entry-state semantics and the same
/// inclusive upper page bound used by the existing allocator adapter.
/// `hint_page` is the highest candidate tried first for top-down requests.
pub fn selectWithLayout(
    entries: [*]const u64,
    total_page_count: u32,
    low_page: u32,
    high_page_input: u32,
    allocation_pages: u32,
    alignment_pages: u32,
    top_down: bool,
    hint_page: u32,
    state_layout: PageStateLayout,
) u32 {
    if (total_page_count == 0 or allocation_pages == 0 or
        alignment_pages == 0 or low_page > high_page_input or
        !state_layout.isValid())
    {
        return no_page;
    }

    const high_page = @min(high_page_input, total_page_count - 1);
    if (low_page > high_page or
        allocation_pages > high_page - low_page)
    {
        return no_page;
    }

    const aligned_high = high_page - (high_page % alignment_pages);
    const search_span = roundUp(allocation_pages, alignment_pages) orelse return no_page;
    if (aligned_high < search_span) return no_page;
    const first_candidate = aligned_high - search_span;

    if (!top_down) {
        return selectBottomUp(
            entries,
            total_page_count,
            low_page,
            high_page,
            allocation_pages,
            alignment_pages,
            state_layout,
        ) orelse no_page;
    }

    var first_search_high = first_candidate;
    if (hint_page != no_page and hint_page < first_search_high) {
        first_search_high = hint_page;
    }

    if (selectTopDown(
        entries,
        total_page_count,
        low_page,
        first_search_high,
        allocation_pages,
        alignment_pages,
        state_layout,
    )) |candidate| {
        return candidate;
    }

    // A release can create a free range above the cursor. Falling back to the
    // full upper window preserves allocator correctness and top-down intent.
    if (first_search_high != first_candidate) {
        if (selectTopDown(
            entries,
            total_page_count,
            low_page,
            first_candidate,
            allocation_pages,
            alignment_pages,
            state_layout,
        )) |candidate| {
            return candidate;
        }
    }
    return no_page;
}

/// Compatibility selector for Xenia's current PageEntry layout. Existing
/// callers keep the same ABI while other allocators can pass their own layout
/// to `selectWithLayout`.
pub fn select(
    entries: [*]const u64,
    total_page_count: u32,
    low_page: u32,
    high_page_input: u32,
    allocation_pages: u32,
    alignment_pages: u32,
    top_down: bool,
    hint_page: u32,
) u32 {
    return selectWithLayout(
        entries,
        total_page_count,
        low_page,
        high_page_input,
        allocation_pages,
        alignment_pages,
        top_down,
        hint_page,
        xenia_page_state_layout,
    );
}

pub fn abiVersion() u32 {
    return abi_version;
}

pub fn selectC(
    entries: [*]const u64,
    total_page_count: u32,
    low_page: u32,
    high_page: u32,
    allocation_pages: u32,
    alignment_pages: u32,
    top_down: u32,
    hint_page: u32,
) callconv(.c) u32 {
    return select(
        entries,
        total_page_count,
        low_page,
        high_page,
        allocation_pages,
        alignment_pages,
        top_down != 0,
        hint_page,
    );
}

test "package identity and ABI version are fixed" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("x86_64-native-bridge", host_codegen);
    try std.testing.expectEqual(@as(u32, 1), abiVersion());
}

test "PageEntry state bits distinguish free and reserved pages" {
    try std.testing.expect(pageIsFree(0));
    try std.testing.expect(!pageIsFree(@as(u64, 1) << page_state_shift));
    try std.testing.expect(!pageIsFree(@as(u64, 3) << page_state_shift));
}

test "page-state layout selects ranges for another allocator entry format" {
    const layout = PageStateLayout{ .shift = 3, .mask = 0x3, .free_value = 1 };
    try std.testing.expect(layout.isValid());
    try std.testing.expect(pageIsFreeWithLayout(@as(u64, 1) << 3, layout));
    try std.testing.expect(!pageIsFreeWithLayout(@as(u64, 2) << 3, layout));

    var entries = [_]u64{0} ** 16;
    @memset(&entries, @as(u64, 1) << 3);
    entries[0] = @as(u64, 2) << 3;
    entries[4] = @as(u64, 2) << 3;
    try std.testing.expectEqual(
        @as(u32, 2),
        selectWithLayout(&entries, entries.len, 0, 15, 2, 2, false, no_page, layout),
    );
}

test "invalid page-state layouts fail closed" {
    const layout = PageStateLayout{ .shift = 63, .mask = 0x3 };
    var entries = [_]u64{0} ** 4;
    try std.testing.expect(!layout.isValid());
    try std.testing.expect(!pageIsFreeWithLayout(0, layout));
    try std.testing.expectEqual(
        no_page,
        selectWithLayout(&entries, entries.len, 0, 3, 1, 1, true, no_page, layout),
    );
}

test "bottom-up selection honors alignment and occupied pages" {
    var entries = [_]u64{0} ** 16;
    entries[0] = @as(u64, 1) << page_state_shift;
    entries[4] = @as(u64, 1) << page_state_shift;
    try std.testing.expectEqual(
        @as(u32, 2),
        select(&entries, entries.len, 0, 15, 2, 2, false, no_page),
    );
}

test "top-down cursor advances and does not hide a released upper range" {
    var entries = [_]u64{0} ** 32;
    const first = select(&entries, entries.len, 0, 31, 1, 1, true, no_page);
    try std.testing.expectEqual(@as(u32, 30), first);
    entries[first] = @as(u64, 1) << page_state_shift;
    const second = select(&entries, entries.len, 0, 31, 1, 1, true, first - 1);
    try std.testing.expectEqual(@as(u32, 29), second);
    entries[first] = 0;
    const released = select(&entries, entries.len, 0, 31, 1, 1, true, 30);
    try std.testing.expectEqual(@as(u32, 30), released);
}

test "a failed cursor search falls back to the full top-down window" {
    var entries = [_]u64{0} ** 16;
    entries[0] = @as(u64, 1) << page_state_shift;
    entries[1] = @as(u64, 1) << page_state_shift;
    entries[2] = @as(u64, 1) << page_state_shift;
    const candidate = select(&entries, entries.len, 0, 15, 1, 1, true, 2);
    try std.testing.expectEqual(@as(u32, 14), candidate);
}

test "invalid and too-wide requests are rejected" {
    var entries = [_]u64{0} ** 8;
    try std.testing.expectEqual(no_page, select(&entries, entries.len, 4, 3, 1, 1, true, no_page));
    try std.testing.expectEqual(no_page, select(&entries, entries.len, 0, 3, 4, 1, true, no_page));
    try std.testing.expectEqual(no_page, select(&entries, entries.len, 0, 7, 1, 0, true, no_page));
}
