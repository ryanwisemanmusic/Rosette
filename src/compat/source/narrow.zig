const std = @import("std");

pub inline fn toU8(value: anytype) u8 {
    return @intCast(value);
}

pub inline fn toI8(value: anytype) i8 {
    return @intCast(value);
}

pub inline fn toU16(value: anytype) u16 {
    return @intCast(value);
}

pub inline fn toI16(value: anytype) i16 {
    return @intCast(value);
}

pub inline fn toU32(value: anytype) u32 {
    return @intCast(value);
}

pub inline fn toI32(value: anytype) i32 {
    return @intCast(value);
}

pub inline fn toU64(value: anytype) u64 {
    return @intCast(value);
}

pub inline fn toI64(value: anytype) i64 {
    return @intCast(value);
}

pub inline fn toUsize(value: anytype) usize {
    return @intCast(value);
}

pub inline fn toIsize(value: anytype) isize {
    return @intCast(value);
}

pub inline fn truncateToU8(value: anytype) u8 {
    return @truncate(value);
}

pub inline fn truncateToI8(value: anytype) i8 {
    return @truncate(value);
}

pub inline fn truncateToU16(value: anytype) u16 {
    return @truncate(value);
}

pub inline fn truncateToI16(value: anytype) i16 {
    return @truncate(value);
}

pub inline fn truncateToU32(value: anytype) u32 {
    return @truncate(value);
}

pub inline fn truncateToI32(value: anytype) i32 {
    return @truncate(value);
}

test "toU32 narrows safely" {
    try std.testing.expectEqual(@as(u32, 42), toU32(@as(usize, 42)));
}

test "toU8 narrows small values" {
    try std.testing.expectEqual(@as(u8, 7), toU8(@as(usize, 7)));
}

test "toI32 preserves sign" {
    try std.testing.expectEqual(@as(i32, -42), toI32(@as(i64, -42)));
}

test "toUsize from u32" {
    try std.testing.expectEqual(@as(usize, 42), toUsize(@as(u32, 42)));
}

test "truncateToU32 discards high bits" {
    const val: u64 = 0xDEADBEEF_CAFEBABE;
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), truncateToU32(val));
}

test "truncateToU8 takes low byte" {
    const val: u32 = 0xABCD;
    try std.testing.expectEqual(@as(u8, 0xCD), truncateToU8(val));
}

test "toU16 from i32 positive" {
    try std.testing.expectEqual(@as(u16, 100), toU16(@as(i32, 100)));
}
