//! Update a packed word under the existing Table writer lock. Readers still
//! use atomic words, existing epochs and leaf-reclamation protocol.
const std = @import("std");
pub threadlocal var enabled = true; // offline differential control
pub threadlocal var same_page = true; // independent access-check control
pub fn update(table: anytype, leaf: anytype, chunk: usize, page: u64, last: u64, protection: anytype) u64 {
    const index: usize = @intCast(page & 65535);
    const count: u7 = @intCast(@min(last - page + 1, 32 - index % 32));
    const shift: u6 = @intCast((index % 32) * 2);
    const mask = (if (count == 32) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(count * 2)) - 1) << shift;
    const word = &leaf[index / 32];
    const old = word.load(.monotonic);
    const next = (old & ~mask) | ((@as(u64, @intFromEnum(protection)) * 0x5555555555555555) & mask);
    if (old != next) {
        const low = @as(u64, 0x5555555555555555) & mask;
        const old_read = @popCount(old & ~(old >> 1) & low);
        const old_none = @popCount((old >> 1) & ~old & low);
        const new_read = if (@intFromEnum(protection) == 1) count else 0;
        const new_none = if (@intFromEnum(protection) == 2) count else 0;
        word.store(next, .release);
        table.read_only_pages = table.read_only_pages - old_read + new_read;
        table.no_access_pages = table.no_access_pages - old_none + new_none;
        table.restricted_in_chunk[chunk] = table.restricted_in_chunk[chunk] - old_read - old_none + new_read + new_none;
    }
    return count;
}

pub fn changed(old: u64, next: u64) u64 {
    const difference = old ^ next;
    return @popCount((difference | (difference >> 1)) & 0x5555555555555555);
}
