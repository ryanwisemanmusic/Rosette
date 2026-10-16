//! Exact memo for the forwarder's tracked-graphics-pipeline table.
//!
//! Every vkCmdBindPipeline reaches `noteCommandPipelineState`, which asks for
//! the bound pipeline's creation metadata. The table is a fixed array of
//! MAX_REAL_PIPELINES records searched front to back, so a bind paid a scan
//! proportional to where its pipeline was recorded, and a pipeline that was
//! never recorded - every compute pipeline: the 2026-10-16 Custom Games run
//! counted 360,581 such binds - paid a scan of the whole table.
//!
//! The memo remembers, per native handle, the slot the scan returned (or
//! that it returned nothing), stamped with the table's generation. Every
//! write to the table bumps the generation, so a stamped entry is exactly
//! what the scan would return now: the first slot holding that handle. A
//! changed table, a collision or `enabled = false` falls back to the scan.

const std = @import("std");

/// Internal control for offline comparison; production keeps it on.
pub var enabled: bool = true;

const slot_bits = 10;
const slot_count = 1 << slot_bits;

pub const Cache = struct {
    /// Bumped by every write to the indexed table. Entries stamped with an
    /// older generation are never used.
    generation: u64 = 1,
    keys: [slot_count]u64 = @splat(0),
    stamps: [slot_count]u64 = @splat(0),
    /// Table index + 1, or 0 when the scan found no record.
    results: [slot_count]u32 = @splat(0),
    hits: u64 = 0,
    misses: u64 = 0,

    pub fn invalidate(self: *Cache) void {
        self.generation +%= 1;
        if (self.generation == 0) self.generation = 1;
    }

    fn slotFor(real: u64) usize {
        return @intCast((real *% 0x9E37_79B9_7F4A_7C15) >> (64 - slot_bits));
    }

    /// The first index of `table` whose record holds `real`, as the original
    /// front-to-back scan answers it.
    pub fn find(self: *Cache, table: anytype, real: u64) ?usize {
        if (real == 0) return null;
        if (!enabled) return scan(table, real);
        const slot = slotFor(real);
        if (self.keys[slot] == real and self.stamps[slot] == self.generation) {
            self.hits +|= 1;
            const stored = self.results[slot];
            return if (stored == 0) null else stored - 1;
        }
        self.misses +|= 1;
        const found = scan(table, real);
        self.keys[slot] = real;
        self.stamps[slot] = self.generation;
        self.results[slot] = if (found) |index| @intCast(index + 1) else 0;
        return found;
    }
};

pub fn scan(table: anytype, real: u64) ?usize {
    if (real == 0) return null;
    for (table, 0..) |*record, index| {
        if (record.real == real) return index;
    }
    return null;
}

test "pipeline memo answers exactly what the front-to-back scan answers" {
    const Record = struct { real: u64 = 0, value: u32 = 0 };
    var table: [64]Record = @splat(.{});
    var cache: Cache = .{};
    var random = std.Random.DefaultPrng.init(0x7ab1e);
    const saved = enabled;
    defer enabled = saved;
    enabled = true;
    for (0..20_000) |_| {
        const r = random.random();
        switch (r.uintLessThan(u8, 10)) {
            // Writers: remember into the first free-or-same slot, forget all
            // copies, or overwrite an arbitrary slot (a duplicate handle).
            0 => {
                const real = 0x1000 + @as(u64, r.uintLessThan(u8, 40)) * 16;
                for (&table) |*record| if (record.real == real or record.real == 0) {
                    record.* = .{ .real = real, .value = r.int(u32) };
                    break;
                };
                cache.invalidate();
            },
            1 => {
                const real = 0x1000 + @as(u64, r.uintLessThan(u8, 40)) * 16;
                for (&table) |*record| if (record.real == real) {
                    record.* = .{};
                };
                cache.invalidate();
            },
            2 => {
                table[r.uintLessThan(usize, table.len)] = .{ .real = 0x1000 + @as(u64, r.uintLessThan(u8, 40)) * 16 };
                cache.invalidate();
            },
            else => {
                const real = if (r.boolean()) 0x1000 + @as(u64, r.uintLessThan(u8, 48)) * 16 else 0;
                try std.testing.expectEqual(scan(&table, real), cache.find(&table, real));
            },
        }
    }
    try std.testing.expect(cache.hits > 0 and cache.misses > 0);
}
