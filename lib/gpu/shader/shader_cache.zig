//! Compiled shader cache.
//!
//! Translating microcode is expensive and titles rebind the same shaders every
//! frame, so the translation is done once and keyed on the microcode itself.
//!
//! ## The key must be the bytes, not the address
//!
//! A title reuses a microcode address for a different shader — that is the
//! whole point of a shader heap. A cache keyed on guest address hands back the
//! previous shader at that address, and the title draws with the wrong program.
//! The result is geometry rendered with someone else's pixel shader, which
//! looks like a material bug and is not one.
//!
//! So the key is a hash of the microcode bytes, and the length is stored
//! alongside: two different programs that hash alike would otherwise collide
//! into one, and the length check makes that vanishingly unlikely to matter.

const std = @import("std");
const contract = @import("xenia_shader_contract");

pub const Error = error{
    CacheFull,
    NotPresent,
    MalformedMicrocode,
};

pub const max_entries: usize = 512;

/// A shader's identity: what it is, not where it was.
pub const Key = struct {
    hash: u64,
    byte_length: u32,
    stage: contract.ShaderStage,

    pub fn eql(self: Key, other: Key) bool {
        return self.hash == other.hash and
            self.byte_length == other.byte_length and
            self.stage == other.stage;
    }
};

/// Derive a key from microcode bytes.
///
/// Refuses a blob whose length the hardware could not have produced, so a
/// truncated fetch becomes an error here rather than a distinct cache entry
/// that translates into a broken shader.
pub fn keyFor(microcode: []const u8, stage: contract.ShaderStage) Error!Key {
    if (!contract.isPlausibleMicrocodeLength(microcode.len)) return error.MalformedMicrocode;
    return .{
        .hash = std.hash.Wyhash.hash(0, microcode),
        .byte_length = @intCast(microcode.len),
        .stage = stage,
    };
}

pub const Entry = struct {
    key: Key,
    /// Opaque host pipeline or module identifier.
    host_id: u64,
    /// Whether translation succeeded. A failed translation is cached too:
    /// re-attempting a translation that cannot succeed, every frame, turns a
    /// missing feature into a frame-rate problem and hides the real cause.
    translated: bool,
    hits: u64 = 0,
};

pub const Cache = struct {
    entries: [max_entries]?Entry = @splat(null),

    lookups: u64 = 0,
    hits: u64 = 0,
    translations: u64 = 0,
    translation_failures: u64 = 0,

    pub fn lookup(self: *Cache, key: Key) ?*Entry {
        self.lookups +|= 1;
        for (&self.entries) |*slot| {
            if (slot.*) |*entry| {
                if (entry.key.eql(key)) {
                    entry.hits +|= 1;
                    self.hits +|= 1;
                    return entry;
                }
            }
        }
        return null;
    }

    pub fn insert(self: *Cache, key: Key, host_id: u64, translated: bool) Error!*Entry {
        self.translations +|= 1;
        if (!translated) self.translation_failures +|= 1;

        for (&self.entries) |*slot| {
            if (slot.*) |*entry| {
                if (entry.key.eql(key)) {
                    entry.host_id = host_id;
                    entry.translated = translated;
                    return entry;
                }
            }
        }
        for (&self.entries) |*slot| {
            if (slot.* == null) {
                slot.* = .{ .key = key, .host_id = host_id, .translated = translated };
                return &slot.*.?;
            }
        }
        return error.CacheFull;
    }

    pub fn count(self: *const Cache) u32 {
        var total: u32 = 0;
        for (self.entries) |slot| {
            if (slot != null) total += 1;
        }
        return total;
    }

    pub fn failedCount(self: *const Cache) u32 {
        var total: u32 = 0;
        for (self.entries) |slot| {
            if (slot) |entry| {
                if (!entry.translated) total += 1;
            }
        }
        return total;
    }

    pub fn verdict(self: *const Cache) []const u8 {
        if (self.translations == 0) return "no shader has been translated";
        if (self.failedCount() == self.count() and self.count() > 0) {
            return "every shader failed to translate: nothing can draw";
        }
        if (self.translation_failures > 0) {
            return "some shaders failed to translate: draws using them will be missing";
        }
        return "translating: every shader offered has translated";
    }
};

test "identity is the bytes, not the address" {
    // The bug this prevents: a title reuses a microcode address, and an
    // address-keyed cache hands back the previous shader. Geometry then draws
    // with someone else's pixel shader, which looks like a material bug.
    const first = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const second = [_]u8{ 8, 7, 6, 5, 4, 3, 2, 1 };
    const a = try keyFor(&first, .pixel);
    const b = try keyFor(&second, .pixel);
    try std.testing.expect(!a.eql(b));
    // The same bytes always give the same key, wherever they came from.
    try std.testing.expect(a.eql(try keyFor(&first, .pixel)));
}

test "the stage is part of the identity" {
    // The same microcode as a vertex and a pixel shader are different
    // programs, and sharing a translation between them binds the wrong one.
    const bytes = [_]u8{ 1, 2, 3, 4 };
    const vertex = try keyFor(&bytes, .vertex);
    const pixel = try keyFor(&bytes, .pixel);
    try std.testing.expect(!vertex.eql(pixel));
    try std.testing.expectEqual(vertex.hash, pixel.hash);
}

test "a malformed blob cannot become a key" {
    // A truncated fetch would otherwise become its own cache entry and
    // translate into a broken shader that is then reused.
    try std.testing.expectError(error.MalformedMicrocode, keyFor(&[_]u8{}, .pixel));
    try std.testing.expectError(error.MalformedMicrocode, keyFor(&[_]u8{ 1, 2, 3 }, .pixel));
}

test "an inserted shader is found again" {
    var cache = Cache{};
    const key = try keyFor(&[_]u8{ 1, 2, 3, 4 }, .pixel);
    _ = try cache.insert(key, 0xAAAA, true);
    const found = cache.lookup(key).?;
    try std.testing.expectEqual(@as(u64, 0xAAAA), found.host_id);
    try std.testing.expect(found.translated);
    try std.testing.expectEqual(@as(u64, 1), cache.hits);
}

test "a miss returns null rather than a neighbour" {
    var cache = Cache{};
    _ = try cache.insert(try keyFor(&[_]u8{ 1, 2, 3, 4 }, .pixel), 0xAAAA, true);
    try std.testing.expect(cache.lookup(try keyFor(&[_]u8{ 5, 6, 7, 8 }, .pixel)) == null);
}

test "a failed translation is cached rather than retried every frame" {
    // Retrying a translation that cannot succeed turns a missing feature into
    // a frame-rate problem, and the real cause disappears into the noise.
    var cache = Cache{};
    const key = try keyFor(&[_]u8{ 1, 2, 3, 4 }, .pixel);
    _ = try cache.insert(key, 0, false);
    const found = cache.lookup(key).?;
    try std.testing.expect(!found.translated);
    try std.testing.expectEqual(@as(u64, 1), cache.translation_failures);
    try std.testing.expectEqualStrings(
        "every shader failed to translate: nothing can draw",
        cache.verdict(),
    );
}

test "reinserting replaces rather than duplicating" {
    var cache = Cache{};
    const key = try keyFor(&[_]u8{ 1, 2, 3, 4 }, .pixel);
    _ = try cache.insert(key, 0, false);
    _ = try cache.insert(key, 0xBBBB, true);
    try std.testing.expectEqual(@as(u32, 1), cache.count());
    try std.testing.expect(cache.lookup(key).?.translated);
    try std.testing.expectEqual(@as(u64, 0xBBBB), cache.lookup(key).?.host_id);
}

test "partial translation failure is distinguishable from total" {
    var cache = Cache{};
    _ = try cache.insert(try keyFor(&[_]u8{ 1, 2, 3, 4 }, .pixel), 0xAAAA, true);
    _ = try cache.insert(try keyFor(&[_]u8{ 5, 6, 7, 8 }, .pixel), 0, false);
    try std.testing.expectEqualStrings(
        "some shaders failed to translate: draws using them will be missing",
        cache.verdict(),
    );
    try std.testing.expectEqual(@as(u32, 1), cache.failedCount());
}

test "a fully translating cache says so" {
    var cache = Cache{};
    _ = try cache.insert(try keyFor(&[_]u8{ 1, 2, 3, 4 }, .vertex), 1, true);
    _ = try cache.insert(try keyFor(&[_]u8{ 5, 6, 7, 8 }, .pixel), 2, true);
    try std.testing.expectEqualStrings(
        "translating: every shader offered has translated",
        cache.verdict(),
    );
}

test "an empty cache says nothing has been translated" {
    const cache = Cache{};
    try std.testing.expectEqualStrings("no shader has been translated", cache.verdict());
}

test "the cache refuses to overfill" {
    var cache = Cache{};
    var index: u32 = 0;
    while (index < max_entries) : (index += 1) {
        const bytes = std.mem.toBytes(index);
        _ = try cache.insert(try keyFor(&bytes, .pixel), index, true);
    }
    const extra = std.mem.toBytes(@as(u64, 0xDEAD_BEEF_CAFE_0000));
    try std.testing.expectError(error.CacheFull, cache.insert(try keyFor(&extra, .pixel), 0, true));
}
