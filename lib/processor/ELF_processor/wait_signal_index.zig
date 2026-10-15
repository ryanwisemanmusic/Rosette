//! Ledger keys are append-only until the whole ledger is reset. Cache the
//! first matching position or a miss for exactly that table length.
const std = @import("std");
pub threadlocal var enabled = true; // offline control, no launcher option
const Slot = struct { valid: bool = false, key: u64 = 0, count: usize = 0, index: ?usize = null };
pub const Index = struct {
    slots: [128]Slot = @splat(.{}),
    lookups: u64 = 0,
    hits: u64 = 0,
    scanned: u64 = 0,
    pub fn find(self: *Index, sites: anytype, key: u64) ?usize {
        self.lookups +|= 1;
        const slot = &self.slots[@intCast((key *% 0x9E3779B97F4A7C15) >> 57)];
        if (enabled and slot.valid and slot.key == key and slot.count == sites.len) {
            self.hits +|= 1;
            return slot.index;
        }
        var found: ?usize = null;
        var scanned: usize = 0;
        for (sites, 0..) |site, i| {
            scanned += 1;
            if (site.key == key) {
                found = i;
                break;
            }
        }
        self.scanned +|= scanned;
        if (enabled) slot.* = .{ .valid = true, .key = key, .count = sites.len, .index = found };
        return found;
    }
    pub fn report(self: *const Index) void {
        std.log.info("PE64 WAIT SIGNAL INDEX: lookups={d} hits={d} scanned={d}; ledger positions only, producer evidence and wait semantics unchanged", .{ self.lookups, self.hits, self.scanned });
    }
};
