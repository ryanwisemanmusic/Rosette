//! Persistent static evidence for the Ready Compiler.
//!
//! This is intentionally a plan cache, not a guest-code cache.  A Mach-O
//! image, its contract, and the set of static reference targets are stable
//! inputs to the preflight scan.  Generated guest code, allocator addresses,
//! Vulkan handles, thread state, and every other activation product remain
//! run-local and are never serialized here.
//!
//! The file format is fixed-width and checksummed so a killed launch cannot
//! turn a partial write into a false green flag.  I/O failures are cache
//! misses, never launch failures.

const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const format_version: u32 = 1;
pub const serialized_size: usize = 88;
const magic = "R3RDYPLN";

pub const Snapshot = struct {
    image_fingerprint: u64 = 0,
    contract_fingerprint: u64 = 0,
    target_fingerprint: u64 = 0,
    target_count: u64 = 0,
    referenced_mask: u64 = 0,
    scanned_bytes: u64 = 0,
    direct_call_sites: u64 = 0,
};

fn putU32(buffer: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, buffer[offset..][0..4], value, .little);
}

fn putU64(buffer: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, buffer[offset..][0..8], value, .little);
}

fn getU32(buffer: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, buffer[offset..][0..4], .little);
}

fn getU64(buffer: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, buffer[offset..][0..8], .little);
}

/// Encode a snapshot into the exact on-disk representation.
pub fn encode(snapshot: Snapshot, output: []u8) ?[]const u8 {
    if (output.len < serialized_size) return null;
    @memset(output[0..serialized_size], 0);
    @memcpy(output[0..magic.len], magic);
    putU32(output, 8, format_version);
    putU64(output, 16, snapshot.image_fingerprint);
    putU64(output, 24, snapshot.contract_fingerprint);
    putU64(output, 32, snapshot.target_fingerprint);
    putU64(output, 40, snapshot.target_count);
    putU64(output, 48, snapshot.referenced_mask);
    putU64(output, 56, snapshot.scanned_bytes);
    putU64(output, 64, snapshot.direct_call_sites);
    // Bytes 72..80 are reserved for a future format extension.  Keeping them
    // zero makes the format forward-checkable without changing its size.
    const checksum = std.hash.Wyhash.hash(0, output[0..80]);
    putU64(output, 80, checksum);
    return output[0..serialized_size];
}

/// Decode only a complete, current, checksummed snapshot.
pub fn decode(input: []const u8) ?Snapshot {
    if (input.len != serialized_size) return null;
    if (!std.mem.eql(u8, input[0..magic.len], magic)) return null;
    if (getU32(input, 8) != format_version) return null;
    if (getU64(input, 80) != std.hash.Wyhash.hash(0, input[0..80])) return null;
    return .{
        .image_fingerprint = getU64(input, 16),
        .contract_fingerprint = getU64(input, 24),
        .target_fingerprint = getU64(input, 32),
        .target_count = getU64(input, 40),
        .referenced_mask = getU64(input, 48),
        .scanned_bytes = getU64(input, 56),
        .direct_call_sites = getU64(input, 64),
    };
}

pub fn matches(
    snapshot: Snapshot,
    image_fingerprint: u64,
    contract_fingerprint: u64,
    target_fingerprint: u64,
    target_count: usize,
) bool {
    return snapshot.image_fingerprint == image_fingerprint and
        snapshot.contract_fingerprint == contract_fingerprint and
        snapshot.target_fingerprint == target_fingerprint and
        snapshot.target_count == target_count and
        target_count <= 64;
}

/// Fold a target fragment and its resolved guest address into a stable key.
/// The address matters: a malformed or unexpectedly changed symbol index must
/// never reuse the reference bitmap for a different target layout.
pub fn foldTarget(fingerprint: u64, fragment: []const u8, address: u64) u64 {
    var address_bytes = address;
    var result = std.hash.Wyhash.hash(fingerprint, fragment);
    result = std.hash.Wyhash.hash(result, std.mem.asBytes(&address_bytes));
    return result;
}

pub fn load(path: []const u8, allocator: std.mem.Allocator) ?Snapshot {
    const path_z = allocator.dupeZ(u8, path) catch return null;
    defer allocator.free(path_z);
    const fd = c.open(path_z.ptr, c.O_RDONLY | c.O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = c.close(fd);

    var bytes: [serialized_size]u8 = undefined;
    var filled: usize = 0;
    while (filled < bytes.len) {
        const amount = c.read(fd, bytes[filled..].ptr, bytes.len - filled);
        if (amount <= 0) return null;
        filled += @intCast(amount);
    }
    return decode(&bytes);
}

pub fn store(path: []const u8, allocator: std.mem.Allocator, snapshot: Snapshot) bool {
    const directory = std.fs.path.dirname(path) orelse return false;
    makePathRecursive(directory, allocator) catch return false;

    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    const fd = c.open(
        path_z.ptr,
        c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_CLOEXEC,
        @as(c_uint, 0o644),
    );
    if (fd < 0) return false;
    defer _ = c.close(fd);

    var bytes: [serialized_size]u8 = undefined;
    const encoded = encode(snapshot, &bytes) orelse return false;
    var written: usize = 0;
    while (written < encoded.len) {
        const amount = c.write(fd, encoded[written..].ptr, encoded.len - written);
        if (amount <= 0) return false;
        written += @intCast(amount);
    }
    _ = c.fsync(fd);
    return true;
}

fn makePathRecursive(raw_path: []const u8, allocator: std.mem.Allocator) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);
    if (raw_path[0] == '/') try current.append(allocator, '/');
    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') {
            try current.append(allocator, '/');
        }
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        defer allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0 and c.access(path_z.ptr, c.F_OK) != 0) {
            return error.MakePathFailed;
        }
    }
}

test "snapshot encoding round trips and rejects corruption" {
    const expected = Snapshot{
        .image_fingerprint = 0x1111,
        .contract_fingerprint = 0x2222,
        .target_fingerprint = 0x3333,
        .target_count = 15,
        .referenced_mask = 0x55,
        .scanned_bytes = 26_378_240,
        .direct_call_sites = 142_948,
    };
    var encoded: [serialized_size]u8 = undefined;
    const bytes = encode(expected, &encoded) orelse return error.TestUnexpectedResult;
    const actual = decode(bytes) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(expected.image_fingerprint, actual.image_fingerprint);
    try std.testing.expectEqual(expected.contract_fingerprint, actual.contract_fingerprint);
    try std.testing.expectEqual(expected.target_fingerprint, actual.target_fingerprint);
    try std.testing.expectEqual(expected.target_count, actual.target_count);
    try std.testing.expectEqual(expected.referenced_mask, actual.referenced_mask);
    try std.testing.expectEqual(expected.scanned_bytes, actual.scanned_bytes);
    try std.testing.expectEqual(expected.direct_call_sites, actual.direct_call_sites);

    encoded[17] ^= 0x80;
    try std.testing.expect(decode(&encoded) == null);
}

test "a snapshot only matches the exact static target set" {
    const snapshot = Snapshot{
        .image_fingerprint = 1,
        .contract_fingerprint = 2,
        .target_fingerprint = 3,
        .target_count = 4,
    };
    try std.testing.expect(matches(snapshot, 1, 2, 3, 4));
    try std.testing.expect(!matches(snapshot, 1, 2, 9, 4));
    try std.testing.expect(!matches(snapshot, 1, 2, 3, 5));
}

test "target folding distinguishes address changes" {
    const first = foldTarget(0, "8Emulator5SetupE", 0x1000);
    const second = foldTarget(0, "8Emulator5SetupE", 0x2000);
    try std.testing.expect(first != second);
}
