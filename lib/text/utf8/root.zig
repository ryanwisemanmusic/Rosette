//! Strict UTF-8 scalar decoding shared by guest compatibility boundaries.
//!
//! Decoding is intentionally incremental: callers can distinguish malformed
//! bytes from a valid prefix that simply needs more input, without copying or
//! allocating the complete input view.

const std = @import("std");

pub const Scalar = struct {
    code_point: u32,
    byte_length: u8,
};

pub const Decode = union(enum) {
    scalar: Scalar,
    incomplete,
    /// Offset of the offending byte relative to the supplied input slice.
    invalid: usize,
};

/// Decode exactly one Unicode scalar beginning at `offset`.
///
/// An incomplete result leaves the input untouched. Invalid continuation
/// sequences identify the offending continuation byte; invalid leading bytes
/// and incomplete prefixes are reported at the sequence's first byte.
pub fn decodeOne(input: []const u8, offset: usize) Decode {
    if (offset >= input.len) return .incomplete;
    const lead = input[offset];
    if (lead <= 0x7f) return .{ .scalar = .{ .code_point = lead, .byte_length = 1 } };

    const sequence_length: u8 = if (lead >= 0xc2 and lead <= 0xdf)
        2
    else if (lead >= 0xe0 and lead <= 0xef)
        3
    else if (lead >= 0xf0 and lead <= 0xf4)
        4
    else
        return .{ .invalid = offset };

    const available = input.len - offset;
    if (available < 2) return .incomplete;
    const second = input[offset + 1];
    if (second < 0x80 or second > 0xbf) return .{ .invalid = offset + 1 };
    if ((lead == 0xe0 and second < 0xa0) or
        (lead == 0xed and second > 0x9f) or
        (lead == 0xf0 and second < 0x90) or
        (lead == 0xf4 and second > 0x8f))
    {
        return .{ .invalid = offset + 1 };
    }
    if (available < sequence_length) return .incomplete;

    var code_point: u32 = switch (sequence_length) {
        2 => (@as(u32, lead & 0x1f) << 6) | @as(u32, second & 0x3f),
        3 => (@as(u32, lead & 0x0f) << 12) | (@as(u32, second & 0x3f) << 6),
        4 => (@as(u32, lead & 0x07) << 18) | (@as(u32, second & 0x3f) << 12),
        else => unreachable,
    };
    for (2..sequence_length) |index| {
        const continuation = input[offset + index];
        if (continuation < 0x80 or continuation > 0xbf) {
            return .{ .invalid = offset + index };
        }
        const shift: u5 = @intCast((sequence_length - index - 1) * 6);
        code_point |= @as(u32, continuation & 0x3f) << shift;
    }
    return .{ .scalar = .{ .code_point = code_point, .byte_length = sequence_length } };
}

test "decode UTF-8 ASCII and multibyte Unicode scalars" {
    const input = "A¢€😀";
    const expected = [_]Scalar{
        .{ .code_point = 'A', .byte_length = 1 },
        .{ .code_point = 0xa2, .byte_length = 2 },
        .{ .code_point = 0x20ac, .byte_length = 3 },
        .{ .code_point = 0x1f600, .byte_length = 4 },
    };
    var offset: usize = 0;
    for (expected) |want| {
        switch (decodeOne(input, offset)) {
            .scalar => |got| {
                try std.testing.expectEqual(want.code_point, got.code_point);
                try std.testing.expectEqual(want.byte_length, got.byte_length);
                offset += got.byte_length;
            },
            else => return error.ExpectedScalar,
        }
    }
    try std.testing.expectEqual(input.len, offset);
    try std.testing.expectEqual(Decode.incomplete, decodeOne(input, input.len));
}

test "incomplete UTF-8 prefixes remain distinguishable" {
    const incomplete = [_][]const u8{ "\xc2", "\xe2\x82", "\xf0\x9f\x98" };
    for (incomplete) |prefix| try std.testing.expectEqual(Decode.incomplete, decodeOne(prefix, 0));
}

test "malformed UTF-8 reports its offending byte" {
    const cases = [_]struct { bytes: []const u8, bad_offset: usize }{
        .{ .bytes = "\x80", .bad_offset = 0 },
        .{ .bytes = "\xc2A", .bad_offset = 1 },
        .{ .bytes = "\xe0\x80\x80", .bad_offset = 1 },
        .{ .bytes = "\xed\xa0\x80", .bad_offset = 1 },
        .{ .bytes = "\xf0\x80\x80\x80", .bad_offset = 1 },
        .{ .bytes = "\xf4\x90\x80\x80", .bad_offset = 1 },
        .{ .bytes = "\xe2\x82A", .bad_offset = 2 },
    };
    for (cases) |case| {
        switch (decodeOne(case.bytes, 0)) {
            .invalid => |offset| try std.testing.expectEqual(case.bad_offset, offset),
            else => return error.ExpectedInvalidSequence,
        }
    }
}
