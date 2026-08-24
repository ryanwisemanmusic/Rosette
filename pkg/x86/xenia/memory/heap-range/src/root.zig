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

pub fn pageIsFree(entry: u64) bool {
    return ((entry >> page_state_shift) & page_state_mask) == 0;
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
) bool {
    if (base_page >= total_page_count or
        allocation_pages > total_page_count - base_page)
    {
        return false;
    }

    var page = base_page;
    const end_page = base_page + allocation_pages;
    while (page < end_page) : (page += 1) {
        if (!pageIsFree(entries[@intCast(page)])) return false;
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
) ?u32 {
    var candidate: i64 = @intCast(search_high_page -
        (search_high_page % alignment_pages));
    const low: i64 = @intCast(low_page);
    const stride: i64 = @intCast(alignment_pages);

    while (candidate >= low) : (candidate -= stride) {
        const base_page: u32 = @intCast(candidate);
        if (rangeIsFree(entries, total_page_count, base_page, allocation_pages)) {
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
) ?u32 {
    const last_candidate = high_page - allocation_pages;
    var candidate = low_page;
    while (candidate <= last_candidate) : (candidate += alignment_pages) {
        if (rangeIsFree(entries, total_page_count, candidate, allocation_pages)) {
            return candidate;
        }
        if (candidate > std.math.maxInt(u32) - alignment_pages) break;
    }
    return null;
}

/// Select a page range using the same legacy inclusive/exclusive upper bound
/// as Xenia's reference scan. `hint_page` is the highest candidate to try
/// first for a top-down request; `no_page` means start at the full upper bound.
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
    if (total_page_count == 0 or allocation_pages == 0 or
        alignment_pages == 0 or low_page > high_page_input)
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
        )) |candidate| {
            return candidate;
        }
    }
    return no_page;
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
