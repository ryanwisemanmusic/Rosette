//! Render target cache with dirty tracking.
//!
//! A render target lives in EDRAM while it is being drawn to and is resolved
//! out to main memory when the title is finished with it. The cache tracks
//! which surfaces are resident and which have been written since their last
//! resolve.
//!
//! ## Why "dirty" has to mean "written", not "bound"
//!
//! The obvious implementation marks a target dirty when it is bound. That is
//! wrong in both directions: a target bound and never drawn to gets resolved
//! for nothing, and — much worse — a target written by a previous draw and then
//! rebound looks freshly clean. The second one loses a frame's worth of
//! rendering with no error anywhere, and it happens only when a title rebinds,
//! so it reproduces on some scenes and not others.

const std = @import("std");
const contract = @import("xenia_render_target_contract");
const edram_surface = @import("edram_surface.zig");

pub const Error = error{
    CacheFull,
    NotResident,
};

/// How many surfaces the cache tracks at once.
pub const max_entries: usize = 32;

pub const Entry = struct {
    surface: edram_surface.Surface,
    /// Where this target resolves to in guest memory. Zero means unresolved
    /// scratch — a target the title never reads back.
    resolve_address: u32 = 0,
    dirty: bool = false,
    draws_since_resolve: u64 = 0,
    resolves: u64 = 0,
};

pub const Cache = struct {
    entries: [max_entries]?Entry = @splat(null),

    inserts: u64 = 0,
    evictions: u64 = 0,
    /// Resolves requested for a target nothing had drawn to. Counted because a
    /// high number means the title is resolving speculatively, which is
    /// expensive but correct — not a bug to chase.
    clean_resolves: u64 = 0,
    /// Surfaces evicted while still dirty. This one *is* a bug: a frame's
    /// rendering was discarded.
    dirty_evictions: u64 = 0,

    pub fn find(self: *Cache, base_tile: u32) ?*Entry {
        for (&self.entries) |*slot| {
            if (slot.*) |*entry| {
                if (entry.surface.base_tile == base_tile) return entry;
            }
        }
        return null;
    }

    /// Make a surface resident, returning its entry.
    ///
    /// Rebinding an already-resident surface returns the existing entry with
    /// its dirty flag intact. Replacing it with a fresh, clean entry is the
    /// bug described above: a target written by a previous draw and rebound
    /// would look clean and its contents would be lost at resolve time.
    pub fn bind(self: *Cache, surface: edram_surface.Surface, resolve_address: u32) Error!*Entry {
        if (self.find(surface.base_tile)) |existing| {
            existing.surface = surface;
            existing.resolve_address = resolve_address;
            return existing;
        }
        for (&self.entries) |*slot| {
            if (slot.* == null) {
                slot.* = .{ .surface = surface, .resolve_address = resolve_address };
                self.inserts +|= 1;
                return &slot.*.?;
            }
        }
        return error.CacheFull;
    }

    /// Record that a draw wrote to a resident target.
    pub fn noteDraw(self: *Cache, base_tile: u32) Error!void {
        const entry = self.find(base_tile) orelse return error.NotResident;
        entry.dirty = true;
        entry.draws_since_resolve +|= 1;
    }

    /// Resolve a target out to guest memory, clearing its dirty flag.
    ///
    /// Returns whether there was anything to resolve.
    pub fn resolve(self: *Cache, base_tile: u32) Error!bool {
        const entry = self.find(base_tile) orelse return error.NotResident;
        entry.resolves +|= 1;
        if (!entry.dirty) {
            self.clean_resolves +|= 1;
            return false;
        }
        entry.dirty = false;
        entry.draws_since_resolve = 0;
        return true;
    }

    /// Remove a surface from the cache.
    pub fn evict(self: *Cache, base_tile: u32) Error!void {
        for (&self.entries) |*slot| {
            if (slot.*) |entry| {
                if (entry.surface.base_tile == base_tile) {
                    if (entry.dirty) self.dirty_evictions +|= 1;
                    self.evictions +|= 1;
                    slot.* = null;
                    return;
                }
            }
        }
        return error.NotResident;
    }

    pub fn residentCount(self: *const Cache) u32 {
        var count: u32 = 0;
        for (self.entries) |slot| {
            if (slot != null) count += 1;
        }
        return count;
    }

    pub fn dirtyCount(self: *const Cache) u32 {
        var count: u32 = 0;
        for (self.entries) |slot| {
            if (slot) |entry| {
                if (entry.dirty) count += 1;
            }
        }
        return count;
    }

    /// What the cache's own numbers say.
    pub fn verdict(self: *const Cache) []const u8 {
        if (self.dirty_evictions > 0) {
            return "rendering discarded: a dirty target was evicted before it resolved";
        }
        if (self.inserts == 0) return "no render target has been bound";
        if (self.dirtyCount() > 0) {
            return "targets pending resolve: drawn to and not yet written back";
        }
        return "clean: every bound target has resolved everything drawn to it";
    }
};

fn target(base: u32) edram_surface.Surface {
    return .{ .base_tile = base, .width = 640, .height = 480 };
}

test "a fresh cache holds nothing" {
    const cache = Cache{};
    try std.testing.expectEqual(@as(u32, 0), cache.residentCount());
    try std.testing.expectEqualStrings("no render target has been bound", cache.verdict());
}

test "binding makes a surface resident and findable" {
    var cache = Cache{};
    const entry = try cache.bind(target(0), 0xA000_0000);
    try std.testing.expect(!entry.dirty);
    try std.testing.expectEqual(@as(u32, 1), cache.residentCount());
    try std.testing.expect(cache.find(0) != null);
    try std.testing.expect(cache.find(100) == null);
}

test "dirty means written, not bound" {
    // Marking dirty at bind time resolves untouched targets for nothing.
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    try std.testing.expectEqual(@as(u32, 0), cache.dirtyCount());
    try std.testing.expect(!try cache.resolve(0));
    try std.testing.expectEqual(@as(u64, 1), cache.clean_resolves);
}

test "rebinding a written target does not clear its dirty flag" {
    // The expensive version of the bug: a rebind that resets the entry makes
    // a written target look clean, and a frame's rendering is lost at resolve
    // time with no error anywhere.
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    try cache.noteDraw(0);
    try std.testing.expectEqual(@as(u32, 1), cache.dirtyCount());

    _ = try cache.bind(target(0), 0xA000_0000);
    try std.testing.expectEqual(@as(u32, 1), cache.dirtyCount());
    try std.testing.expect(try cache.resolve(0));
}

test "rebinding does not duplicate the entry" {
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    _ = try cache.bind(target(0), 0xB000_0000);
    try std.testing.expectEqual(@as(u32, 1), cache.residentCount());
    try std.testing.expectEqual(@as(u64, 1), cache.inserts);
    // The new resolve address took effect.
    try std.testing.expectEqual(@as(u32, 0xB000_0000), cache.find(0).?.resolve_address);
}

test "a resolve clears dirty and resets the draw count" {
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    try cache.noteDraw(0);
    try cache.noteDraw(0);
    try std.testing.expectEqual(@as(u64, 2), cache.find(0).?.draws_since_resolve);

    try std.testing.expect(try cache.resolve(0));
    try std.testing.expect(!cache.find(0).?.dirty);
    try std.testing.expectEqual(@as(u64, 0), cache.find(0).?.draws_since_resolve);
    try std.testing.expectEqual(@as(u64, 1), cache.find(0).?.resolves);
}

test "operating on a non-resident target is refused, not silently ignored" {
    var cache = Cache{};
    try std.testing.expectError(error.NotResident, cache.noteDraw(0));
    try std.testing.expectError(error.NotResident, cache.resolve(0));
    try std.testing.expectError(error.NotResident, cache.evict(0));
}

test "evicting a dirty target is recorded as discarded rendering" {
    // The one case in this file that is unambiguously a bug rather than a
    // cost, so it gets its own counter and its own verdict.
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    try cache.noteDraw(0);
    try cache.evict(0);
    try std.testing.expectEqual(@as(u64, 1), cache.dirty_evictions);
    try std.testing.expectEqualStrings(
        "rendering discarded: a dirty target was evicted before it resolved",
        cache.verdict(),
    );
}

test "evicting a clean target is not recorded as a loss" {
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    try cache.evict(0);
    try std.testing.expectEqual(@as(u64, 1), cache.evictions);
    try std.testing.expectEqual(@as(u64, 0), cache.dirty_evictions);
    try std.testing.expectEqual(@as(u32, 0), cache.residentCount());
}

test "the cache refuses to overfill rather than evicting silently" {
    // A silent eviction here would discard a target the title still expects.
    var cache = Cache{};
    var index: u32 = 0;
    while (index < max_entries) : (index += 1) {
        _ = try cache.bind(target(index * 100), 0);
    }
    try std.testing.expectEqual(@as(u32, max_entries), cache.residentCount());
    try std.testing.expectError(error.CacheFull, cache.bind(target(9999), 0));
}

test "pending resolves are distinguishable from a clean cache" {
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    try cache.noteDraw(0);
    try std.testing.expectEqualStrings(
        "targets pending resolve: drawn to and not yet written back",
        cache.verdict(),
    );
    _ = try cache.resolve(0);
    try std.testing.expectEqualStrings(
        "clean: every bound target has resolved everything drawn to it",
        cache.verdict(),
    );
}

test "several targets are tracked independently" {
    var cache = Cache{};
    _ = try cache.bind(target(0), 0xA000_0000);
    _ = try cache.bind(target(300), 0xB000_0000);
    try cache.noteDraw(300);
    try std.testing.expectEqual(@as(u32, 1), cache.dirtyCount());
    try std.testing.expect(!cache.find(0).?.dirty);
    try std.testing.expect(cache.find(300).?.dirty);
}

test "a cached target is placed inside real EDRAM" {
    // The cache keys on base tile, so a base outside EDRAM would produce an
    // entry that can never correspond to storage.
    var cache = Cache{};
    const entry = try cache.bind(target(0), 0xA000_0000);
    try std.testing.expect(contract.isTileIndex(entry.surface.base_tile));
    try std.testing.expect(!contract.isTileIndex(contract.tile_count));
}
