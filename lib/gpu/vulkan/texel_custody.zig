//! Bounded lookup-table evidence; interpreting bytes is not shader correctness.
const std = @import("std");
pub const Stats = struct {
    hash: u64 = 14_695_981_039_346_656_037,
    nonzero_bytes: u32 = 0,
    entries: u32 = 0,
    min: [3]u32 = @splat(std.math.maxInt(u32)),
    max: [3]u32 = @splat(0),
};
pub fn analyze(bytes: []const u8, format: u32) !Stats {
    if (bytes.len == 0 or bytes.len > 4096 or bytes.len % 4 != 0) return error.InvalidTable;
    var stats = Stats{};
    for (bytes) |byte| {
        stats.hash = (stats.hash ^ byte) *% 1_099_511_628_211;
        if (byte != 0) stats.nonzero_bytes += 1;
    }
    stats.entries = @intCast(bytes.len / 4);
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) {
        const word = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        const components: [3]u32 = switch (format) {
            64 => .{ word & 1023, (word >> 10) & 1023, (word >> 20) & 1023 }, // A2B10G10R10_UNORM
            81 => .{ word & 65535, word >> 16, 0 }, // R16G16_UINT: PWL base/delta
            else => return error.UnsupportedFormat,
        };
        for (components, 0..) |value, channel| {
            stats.min[channel] = @min(stats.min[channel], value);
            stats.max[channel] = @max(stats.max[channel], value);
        }
    }
    return stats;
}
test "gamma custody decodes packed ten-bit channels without eight-bit truncation" {
    const word: u32 = 1023 | (512 << 10) | (255 << 20);
    var bytes: [8]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[4..8], word, .little);
    const stats = try analyze(&bytes, 64);
    try std.testing.expectEqual([3]u32{ 1023, 512, 255 }, stats.max);
    try std.testing.expectEqual([3]u32{ 0, 0, 0 }, stats.min);
    const pwl = try analyze(&.{ 0x34, 0x12, 0x78, 0x56 }, 81);
    try std.testing.expectEqual([3]u32{ 0x1234, 0x5678, 0 }, pwl.max);
}
test "zero and unbounded lookup tables do not become content proof" {
    const zero = try analyze(&.{ 0, 0, 0, 0 }, 64);
    try std.testing.expectEqual(@as(u32, 0), zero.nonzero_bytes);
    try std.testing.expectError(error.InvalidTable, analyze(&.{ 1, 2, 3 }, 64));
    try std.testing.expectError(error.UnsupportedFormat, analyze(&.{ 1, 2, 3, 4 }, 44));
}
