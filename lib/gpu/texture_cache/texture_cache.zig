//! Texture cache with guest-memory dirty tracking.
//!
//! A texture is uploaded to the host once and reused until the guest changes
//! the memory behind it. Getting the invalidation wrong is expensive in exactly
//! one direction and merely slow in the other:
//!
//! * **Under-invalidating** shows a stale texture. The title updated a render
//!   target or streamed in a new mip and the screen keeps the old one. This is
//!   invisible until someone recognises the specific wrong image.
//! * **Over-invalidating** re-uploads constantly. The image is right and the
//!   frame rate is not, which at least presents as a performance problem
//!   rather than a correctness one.
//!
//! So the cache tracks the guest address range each texture came from and
//! invalidates on any overlapping write, and it counts both directions so the
//! trade can be measured rather than guessed at.

const std = @import("std");
const contract = @import("xenia_texture_contract");

pub const Error = error{
    CacheFull,
    NotResident,
    DegenerateRange,
};

pub const max_entries: usize = 256;

/// The identity of a texture, as the guest describes it.
///
/// Address alone is not identity: a title reuses an address for a different
/// format or extent, and a cache keyed on address alone would hand back a
/// texture of the wrong shape. Every field participates.
pub const Key = struct {
    guest_address: u32,
    width: u32,
    height: u32,
    format: contract.TextureFormat,
    mip_levels: u32 = 1,

    pub fn eql(self: Key, other: Key) bool {
        return self.guest_address == other.guest_address and
            self.width == other.width and
            self.height == other.height and
            self.format == other.format and
            self.mip_levels == other.mip_levels;
    }
};

pub const Entry = struct {
    key: Key,
    /// Bytes of guest memory this texture was built from.
    guest_bytes: u32,
    /// Opaque host resource identifier. Not a pointer: an identifier that
    /// outlives the resource must not be dereferenceable.
    host_id: u64,
    valid: bool = true,
    hits: u64 = 0,
    uploads: u64 = 1,

    /// The half-open guest range this texture covers.
    pub fn range(self: Entry) struct { start: u64, end: u64 } {
        return .{
            .start = self.key.guest_address,
            .end = @as(u64, self.key.guest_address) + self.guest_bytes,
        };
    }

    pub fn coversAddress(self: Entry, address: u32) bool {
        const span = self.range();
        return address >= span.start and address < span.end;
    }
};

pub const Cache = struct {
    entries: [max_entries]?Entry = @splat(null),

    lookups: u64 = 0,
    hits: u64 = 0,
    uploads: u64 = 0,
    invalidations: u64 = 0,
    /// Invalidations that hit a texture which had never been sampled. A high
    /// count means the cache is doing work for textures nothing uses.
    unused_invalidations: u64 = 0,
    evictions: u64 = 0,

    /// Look a texture up. Returns null for a miss or a stale entry.
    pub fn lookup(self: *Cache, key: Key) ?*Entry {
        self.lookups +|= 1;
        for (&self.entries) |*slot| {
            if (slot.*) |*entry| {
                if (entry.key.eql(key) and entry.valid) {
                    entry.hits +|= 1;
                    self.hits +|= 1;
                    return entry;
                }
            }
        }
        return null;
    }

    /// Record an upload.
    ///
    /// A stale entry for the same key is refreshed in place rather than
    /// duplicated: two entries for one key would make eviction order decide
    /// which texture a title sees.
    pub fn insert(self: *Cache, key: Key, guest_bytes: u32, host_id: u64) Error!*Entry {
        if (guest_bytes == 0) return error.DegenerateRange;
        self.uploads +|= 1;

        for (&self.entries) |*slot| {
            if (slot.*) |*entry| {
                if (entry.key.eql(key)) {
                    entry.valid = true;
                    entry.guest_bytes = guest_bytes;
                    entry.host_id = host_id;
                    entry.uploads +|= 1;
                    return entry;
                }
            }
        }
        for (&self.entries) |*slot| {
            if (slot.* == null) {
                slot.* = .{ .key = key, .guest_bytes = guest_bytes, .host_id = host_id };
                return &slot.*.?;
            }
        }
        return error.CacheFull;
    }

    /// Invalidate every texture overlapping a guest write.
    ///
    /// Half-open overlap: a write starting exactly where a texture ends does
    /// not touch it. Getting that wrong invalidates a neighbour on every
    /// sequential upload, which is the over-invalidation case.
    pub fn invalidateRange(self: *Cache, address: u32, length: u32) u32 {
        if (length == 0) return 0;
        const write_start: u64 = address;
        const write_end: u64 = @as(u64, address) + length;

        var count: u32 = 0;
        for (&self.entries) |*slot| {
            if (slot.*) |*entry| {
                if (!entry.valid) continue;
                const span = entry.range();
                if (span.start < write_end and write_start < span.end) {
                    entry.valid = false;
                    count += 1;
                    self.invalidations +|= 1;
                    if (entry.hits == 0) self.unused_invalidations +|= 1;
                }
            }
        }
        return count;
    }

    pub fn evict(self: *Cache, key: Key) Error!void {
        for (&self.entries) |*slot| {
            if (slot.*) |entry| {
                if (entry.key.eql(key)) {
                    slot.* = null;
                    self.evictions +|= 1;
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

    pub fn validCount(self: *const Cache) u32 {
        var count: u32 = 0;
        for (self.entries) |slot| {
            if (slot) |entry| {
                if (entry.valid) count += 1;
            }
        }
        return count;
    }

    /// Hit rate in hundredths, so the report stays integer-typed.
    pub fn hitRatePercent(self: *const Cache) u32 {
        if (self.lookups == 0) return 0;
        return @intCast(self.hits * 100 / self.lookups);
    }

    pub fn verdict(self: *const Cache) []const u8 {
        if (self.uploads == 0) return "no texture has been uploaded";
        if (self.lookups == 0) return "uploaded but never looked up: nothing is sampling these textures";
        if (self.invalidations > self.uploads) {
            return "thrashing: textures are invalidated faster than they are uploaded";
        }
        if (self.hitRatePercent() < 50) {
            return "low hit rate: most lookups miss, so the cache is not paying for itself";
        }
        return "caching: most lookups hit a valid texture";
    }
};

fn textureKey(address: u32) Key {
    return .{ .guest_address = address, .width = 256, .height = 256, .format = .dxt1 };
}

test "a fresh cache holds nothing" {
    const cache = Cache{};
    try std.testing.expectEqual(@as(u32, 0), cache.residentCount());
    try std.testing.expectEqualStrings("no texture has been uploaded", cache.verdict());
}

test "an inserted texture is found again" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 8192, 0xAAAA);
    const found = cache.lookup(textureKey(0x1000)).?;
    try std.testing.expectEqual(@as(u64, 0xAAAA), found.host_id);
    try std.testing.expectEqual(@as(u64, 1), cache.hits);
}

test "address alone is not identity" {
    // A title reuses an address for a different format or extent. A cache
    // keyed on address alone hands back a texture of the wrong shape, which
    // renders as garbage rather than failing.
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 8192, 0xAAAA);

    var different = textureKey(0x1000);
    different.format = .dxt4_5;
    try std.testing.expect(cache.lookup(different) == null);

    different = textureKey(0x1000);
    different.width = 128;
    try std.testing.expect(cache.lookup(different) == null);

    different = textureKey(0x1000);
    different.mip_levels = 4;
    try std.testing.expect(cache.lookup(different) == null);
}

test "a guest write invalidates the overlapping texture" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 8192, 0xAAAA);
    try std.testing.expectEqual(@as(u32, 1), cache.invalidateRange(0x1000, 4));
    try std.testing.expect(cache.lookup(textureKey(0x1000)) == null);
    try std.testing.expectEqual(@as(u32, 0), cache.validCount());
    // The entry is still resident, just stale.
    try std.testing.expectEqual(@as(u32, 1), cache.residentCount());
}

test "a write adjacent to a texture does not invalidate it" {
    // Half-open. Getting this wrong invalidates a neighbour on every
    // sequential upload — the over-invalidation case, which costs frame rate.
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 0xAAAA);
    // The texture covers 0x1000..0x2000.
    try std.testing.expectEqual(@as(u32, 0), cache.invalidateRange(0x2000, 16));
    try std.testing.expectEqual(@as(u32, 0), cache.invalidateRange(0x0F00, 0x100));
    try std.testing.expect(cache.lookup(textureKey(0x1000)) != null);

    // One byte into the range does invalidate.
    try std.testing.expectEqual(@as(u32, 1), cache.invalidateRange(0x1FFF, 1));
}

test "a write spanning several textures invalidates all of them" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 1);
    _ = try cache.insert(textureKey(0x2000), 0x1000, 2);
    _ = try cache.insert(textureKey(0x9000), 0x1000, 3);
    try std.testing.expectEqual(@as(u32, 2), cache.invalidateRange(0x1800, 0x1000));
    try std.testing.expect(cache.lookup(textureKey(0x9000)) != null);
}

test "a zero length write invalidates nothing" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 1);
    try std.testing.expectEqual(@as(u32, 0), cache.invalidateRange(0x1000, 0));
    try std.testing.expect(cache.lookup(textureKey(0x1000)) != null);
}

test "re-uploading a stale entry refreshes it rather than duplicating" {
    // Two entries for one key would make eviction order decide which texture
    // a title sees.
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 8192, 0xAAAA);
    _ = cache.invalidateRange(0x1000, 4);
    _ = try cache.insert(textureKey(0x1000), 8192, 0xBBBB);

    try std.testing.expectEqual(@as(u32, 1), cache.residentCount());
    const found = cache.lookup(textureKey(0x1000)).?;
    try std.testing.expectEqual(@as(u64, 0xBBBB), found.host_id);
    try std.testing.expectEqual(@as(u64, 2), found.uploads);
}

test "invalidating an unused texture is counted separately" {
    // A high count means the cache is doing work for textures nothing uses,
    // which is a different problem from thrashing on hot ones.
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 1);
    _ = cache.invalidateRange(0x1000, 4);
    try std.testing.expectEqual(@as(u64, 1), cache.unused_invalidations);

    _ = try cache.insert(textureKey(0x2000), 0x1000, 2);
    _ = cache.lookup(textureKey(0x2000));
    _ = cache.invalidateRange(0x2000, 4);
    try std.testing.expectEqual(@as(u64, 2), cache.invalidations);
    try std.testing.expectEqual(@as(u64, 1), cache.unused_invalidations);
}

test "a degenerate upload is refused" {
    var cache = Cache{};
    try std.testing.expectError(error.DegenerateRange, cache.insert(textureKey(0x1000), 0, 1));
}

test "eviction removes the entry entirely" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 1);
    try cache.evict(textureKey(0x1000));
    try std.testing.expectEqual(@as(u32, 0), cache.residentCount());
    try std.testing.expectError(error.NotResident, cache.evict(textureKey(0x1000)));
}

test "the cache refuses to overfill" {
    var cache = Cache{};
    var index: u32 = 0;
    while (index < max_entries) : (index += 1) {
        _ = try cache.insert(textureKey(0x1000 + index * 0x1000), 0x100, index);
    }
    try std.testing.expectError(error.CacheFull, cache.insert(textureKey(0xFFFF_0000), 0x100, 999));
}

test "the hit rate is reported and drives the verdict" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 1);
    _ = cache.lookup(textureKey(0x1000));
    _ = cache.lookup(textureKey(0x1000));
    try std.testing.expectEqual(@as(u32, 100), cache.hitRatePercent());
    try std.testing.expectEqualStrings("caching: most lookups hit a valid texture", cache.verdict());

    // Misses drag it down.
    var miss: u32 = 0;
    while (miss < 10) : (miss += 1) _ = cache.lookup(textureKey(0x9999));
    try std.testing.expect(cache.hitRatePercent() < 50);
    try std.testing.expectEqualStrings(
        "low hit rate: most lookups miss, so the cache is not paying for itself",
        cache.verdict(),
    );
}

test "uploaded but never sampled is its own verdict" {
    var cache = Cache{};
    _ = try cache.insert(textureKey(0x1000), 0x1000, 1);
    try std.testing.expectEqualStrings(
        "uploaded but never looked up: nothing is sampling these textures",
        cache.verdict(),
    );
}

test "an entry knows which addresses it covers" {
    var cache = Cache{};
    const entry = try cache.insert(textureKey(0x1000), 0x1000, 1);
    try std.testing.expect(entry.coversAddress(0x1000));
    try std.testing.expect(entry.coversAddress(0x1FFF));
    try std.testing.expect(!entry.coversAddress(0x2000));
    try std.testing.expect(!entry.coversAddress(0x0FFF));
}
