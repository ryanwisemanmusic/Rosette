//! Monotonic coarse membership for TLB invalidation only. A set bit may be
//! stale or collide; an absent bit proves this direction never admitted that
//! region. Never clear bits while an executor can fill. Probes stay unchanged.
const std = @import("std");
pub const Summary = extern struct {
    read: [8]u64 = @splat(0),
    write: [8]u64 = @splat(0),
    // One executor owns fills. Invalidators never read these hints. Bits
    // are monotonic, so a repeated region needs no atomic metadata access.
    last_admitted: [2]u64 = @splat(std.math.maxInt(u64)),
    hint_padding: [6]u64 = @splat(0),
    pub const block_shift: u6 = 10; // 4 MiB guest regions, with 4 KiB pages.
    fn bucket(block: u64) usize {
        return @intCast((block ^ (block >> 9) ^ (block >> 18)) & 511);
    }
    pub fn note(self: *Summary, is_write: bool, tag: u64, ordered: bool) void {
        const region = tag >> block_shift;
        const direction: usize = @intFromBool(is_write);
        if (self.last_admitted[direction] == region) return;
        const bit = bucket(region);
        const word = &(if (is_write) &self.write else &self.read)[bit / 64];
        const mask = @as(u64, 1) << @intCast(bit % 64);
        if (ordered) {
            // Publish before the tag. Combined with the caller's existing
            // epoch recheck this cannot conceal a racing fill/invalidation.
            if (@atomicLoad(u64, word, .seq_cst) & mask == 0) _ = @atomicRmw(u64, word, .Or, mask, .seq_cst);
        } else word.* |= mask;
        self.last_admitted[direction] = region;
    }
    pub fn mightContain(self: *const Summary, is_write: bool, first: u64, last: u64, ordered: bool) bool {
        const begin = first >> block_shift;
        const end = last >> block_shift;
        if (end - begin >= 4) return true;
        const table = if (is_write) &self.write else &self.read;
        var block = begin;
        while (true) : (block += 1) {
            const bit = bucket(block);
            const value = if (ordered) @atomicLoad(u64, &table[bit / 64], .seq_cst) else table[bit / 64];
            if (value & (@as(u64, 1) << @intCast(bit % 64)) != 0) return true;
            if (block == end) return false;
        }
    }
};
test "TLB membership has no false negatives for folded or high-address regions" {
    var summary: Summary = .{};
    var random = std.Random.DefaultPrng.init(0xa1137);
    for (0..10000) |_| {
        const tag = random.random().int(u64) >> 12;
        summary.note(false, tag, true);
        try std.testing.expect(summary.mightContain(false, tag, tag, true));
        try std.testing.expect(summary.mightContain(false, tag -| 700, tag +| 300, true));
    }
    try std.testing.expect(!summary.mightContain(true, 0, 0, true));
}
