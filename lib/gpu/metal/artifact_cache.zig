//! Stable identity and completeness rules for offline Metal shader artifacts.
//!
//! `.air` and `.metallib` are compiler products, not source files. Reusing
//! either across a changed source, SDK, Metal compiler, or target can bind a
//! shader compiled for the wrong host contract. The offline compiler script
//! uses the same identity inputs before installing a pair in its cache.

const std = @import("std");

pub const digest_bytes = 32;
pub const Key = [digest_bytes]u8;

fn updateField(hasher: *std.crypto.hash.sha2.Sha256, value: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, value.len, .little);
    hasher.update(&length);
    hasher.update(value);
}

/// Derive a content-and-toolchain identity. Length-prefixing keeps distinct
/// field sequences distinct even when their concatenated bytes would match.
pub fn keyFor(
    source: []const u8,
    metal_compiler: []const u8,
    metallib_linker: []const u8,
    sdk_identity: []const u8,
    target_identity: []const u8,
) Key {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("rosette-metal-artifact-v1");
    updateField(&hasher, source);
    updateField(&hasher, metal_compiler);
    updateField(&hasher, metallib_linker);
    updateField(&hasher, sdk_identity);
    updateField(&hasher, target_identity);
    var key: Key = undefined;
    hasher.final(&key);
    return key;
}

pub const Presence = struct {
    air: bool,
    metallib: bool,
    manifest_matches_key: bool,
};

pub const CacheState = enum {
    miss,
    complete,
    incomplete,
};

/// Both binary stages and their manifest must agree before a cache hit is
/// trusted. A partial compile is repaired by a full rebuild.
pub fn inspect(presence: Presence) CacheState {
    if (!presence.air and !presence.metallib and !presence.manifest_matches_key) return .miss;
    if (presence.air and presence.metallib and presence.manifest_matches_key) return .complete;
    return .incomplete;
}

test "source, compiler, SDK, linker, and target all participate in cache identity" {
    const base = keyFor("kernel A", "metal 32023", "metallib 32023", "SDK 14.2/23C53", "arm64-macos");
    try std.testing.expectEqualSlices(u8, &base, &keyFor("kernel A", "metal 32023", "metallib 32023", "SDK 14.2/23C53", "arm64-macos"));
    try std.testing.expect(!std.mem.eql(u8, &base, &keyFor("kernel B", "metal 32023", "metallib 32023", "SDK 14.2/23C53", "arm64-macos")));
    try std.testing.expect(!std.mem.eql(u8, &base, &keyFor("kernel A", "metal 32024", "metallib 32023", "SDK 14.2/23C53", "arm64-macos")));
    try std.testing.expect(!std.mem.eql(u8, &base, &keyFor("kernel A", "metal 32023", "metallib 32023", "SDK 14.2/23C53", "x86_64-macos")));
}

test "cache reuse requires the complete artifact pair and matching key" {
    try std.testing.expectEqual(CacheState.miss, inspect(.{ .air = false, .metallib = false, .manifest_matches_key = false }));
    try std.testing.expectEqual(CacheState.incomplete, inspect(.{ .air = true, .metallib = false, .manifest_matches_key = true }));
    try std.testing.expectEqual(CacheState.incomplete, inspect(.{ .air = true, .metallib = true, .manifest_matches_key = false }));
    try std.testing.expectEqual(CacheState.complete, inspect(.{ .air = true, .metallib = true, .manifest_matches_key = true }));
}
