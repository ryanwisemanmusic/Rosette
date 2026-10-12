//! Vector-width scans used by coordinated CRT string imports. Callers must
//! obtain TSO-coordinated guest bytes before scanning these local snapshots.

const std = @import("std");
const ByteVector = @Vector(16, u8);
const vector_width = 16;

/// Return the first byte offset whose values differ, or null when equal.
pub fn firstDifference(left: []const u8, right: []const u8) ?usize {
    if (left.len != right.len) return null;
    var offset: usize = 0;
    while (offset + vector_width <= left.len) : (offset += vector_width) {
        const left_vector: ByteVector = @bitCast(left[offset..][0..vector_width].*);
        const right_vector: ByteVector = @bitCast(right[offset..][0..vector_width].*);
        if (!@reduce(.And, left_vector == right_vector)) {
            for (left[offset..][0..vector_width], right[offset..][0..vector_width], offset..) |a, b, index| {
                if (a != b) return index;
            }
        }
    }
    for (left[offset..], right[offset..], offset..) |a, b, index| {
        if (a != b) return index;
    }
    return null;
}

/// Return the first NUL byte offset, or null when the snapshot has none.
pub fn firstZero(bytes: []const u8) ?usize {
    const zeroes: ByteVector = @splat(0);
    var offset: usize = 0;
    while (offset + vector_width <= bytes.len) : (offset += vector_width) {
        const vector: ByteVector = @bitCast(bytes[offset..][0..vector_width].*);
        if (@reduce(.Or, vector == zeroes)) {
            for (bytes[offset..][0..vector_width], offset..) |byte, index| {
                if (byte == 0) return index;
            }
        }
    }
    for (bytes[offset..], offset..) |byte, index| {
        if (byte == 0) return index;
    }
    return null;
}

pub const StringChunkResult = union(enum) {
    continue_scan,
    result: i32,
};

/// Compare a C string chunk, stopping at its first NUL or differing byte.
pub fn compareStringChunk(left: []const u8, right: []const u8) StringChunkResult {
    std.debug.assert(left.len == right.len);
    const zeroes: ByteVector = @splat(0);
    var offset: usize = 0;
    while (offset + vector_width <= left.len) : (offset += vector_width) {
        const left_vector: ByteVector = @bitCast(left[offset..][0..vector_width].*);
        const right_vector: ByteVector = @bitCast(right[offset..][0..vector_width].*);
        const equal = @reduce(.And, left_vector == right_vector);
        const nonzero = @reduce(.And, left_vector != zeroes);
        if (equal and nonzero) continue;
        for (left[offset..][0..vector_width], right[offset..][0..vector_width]) |a, b| {
            if (a != b) return .{ .result = @as(i32, a) - @as(i32, b) };
            if (a == 0) return .{ .result = 0 };
        }
    }
    for (left[offset..], right[offset..]) |a, b| {
        if (a != b) return .{ .result = @as(i32, a) - @as(i32, b) };
        if (a == 0) return .{ .result = 0 };
    }
    return .continue_scan;
}

test "vector scans preserve first difference and zero positions at every lane boundary" {
    var left: [65]u8 = @splat('a');
    var right: [65]u8 = left;
    for (0..left.len) |index| {
        right[index] = 'b';
        try std.testing.expectEqual(@as(?usize, index), firstDifference(&left, &right));
        right[index] = 'a';
    }
    try std.testing.expect(firstDifference(&left, &right) == null);
    for (0..left.len) |index| {
        left[index] = 0;
        try std.testing.expectEqual(@as(?usize, index), firstZero(&left));
        left[index] = 'a';
    }
    try std.testing.expect(firstZero(&left) == null);
}

test "vector C string chunks stop at the first NUL or differing byte" {
    var left: [33]u8 = @splat('x');
    var right: [33]u8 = left;
    try std.testing.expect(compareStringChunk(&left, &right) == .continue_scan);
    right[16] = 'y';
    try std.testing.expectEqual(@as(i32, -1), compareStringChunk(&left, &right).result);
    right[16] = 'x';
    left[31] = 0;
    right[31] = 0;
    try std.testing.expectEqual(@as(i32, 0), compareStringChunk(&left, &right).result);
    left[31] = 'x';
    right[31] = 0;
    try std.testing.expectEqual(@as(i32, 'x'), compareStringChunk(&left, &right).result);
}
