//! Itanium C++ allocation symbol classification.
//!
//! Mach-O imports carry the leading underscore, so an Itanium `_Znam...`
//! operator is observed here as `__Znam...`.  Keeping the complete family in
//! one table prevents the slow import path and its cached replay path from
//! disagreeing about arguments (most importantly aligned and nothrow array
//! new).

const std = @import("std");

pub const NewForm = struct {
    array: bool,
    nothrow: bool,
    alignment_argument: bool,

    pub fn alignment(self: NewForm, alignment_register: u64) u64 {
        return if (self.alignment_argument) alignment_register else 16;
    }
};

const scalar = NewForm{ .array = false, .nothrow = false, .alignment_argument = false };
const array = NewForm{ .array = true, .nothrow = false, .alignment_argument = false };
const scalar_nothrow = NewForm{ .array = false, .nothrow = true, .alignment_argument = false };
const array_nothrow = NewForm{ .array = true, .nothrow = true, .alignment_argument = false };
const scalar_aligned = NewForm{ .array = false, .nothrow = false, .alignment_argument = true };
const array_aligned = NewForm{ .array = true, .nothrow = false, .alignment_argument = true };
const scalar_aligned_nothrow = NewForm{ .array = false, .nothrow = true, .alignment_argument = true };
const array_aligned_nothrow = NewForm{ .array = true, .nothrow = true, .alignment_argument = true };

pub fn classifyNew(symbol: []const u8) ?NewForm {
    if (std.mem.eql(u8, symbol, "__Znwm")) return scalar;
    if (std.mem.eql(u8, symbol, "__Znam")) return array;
    if (std.mem.eql(u8, symbol, "__ZnwmRKSt9nothrow_t")) return scalar_nothrow;
    if (std.mem.eql(u8, symbol, "__ZnamRKSt9nothrow_t")) return array_nothrow;
    if (std.mem.eql(u8, symbol, "__ZnwmSt11align_val_t")) return scalar_aligned;
    if (std.mem.eql(u8, symbol, "__ZnamSt11align_val_t")) return array_aligned;
    if (std.mem.eql(u8, symbol, "__ZnwmSt11align_val_tRKSt9nothrow_t")) return scalar_aligned_nothrow;
    if (std.mem.eql(u8, symbol, "__ZnamSt11align_val_tRKSt9nothrow_t")) return array_aligned_nothrow;
    return null;
}

pub fn isDelete(symbol: []const u8) bool {
    const delete_symbols = [_][]const u8{
        "__ZdlPv",
        "__ZdaPv",
        "__ZdlPvm",
        "__ZdaPvm",
        "__ZdlPvRKSt9nothrow_t",
        "__ZdaPvRKSt9nothrow_t",
        "__ZdlPvSt11align_val_t",
        "__ZdaPvSt11align_val_t",
        "__ZdlPvmSt11align_val_t",
        "__ZdaPvmSt11align_val_t",
        "__ZdlPvSt11align_val_tRKSt9nothrow_t",
        "__ZdaPvSt11align_val_tRKSt9nothrow_t",
    };
    for (delete_symbols) |candidate| {
        if (std.mem.eql(u8, symbol, candidate)) return true;
    }
    return false;
}

test "classifies the libc++ new family without losing array nothrow" {
    const plain_array = classifyNew("__Znam") orelse return error.TestUnexpectedResult;
    try std.testing.expect(plain_array.array);
    try std.testing.expect(!plain_array.nothrow);
    try std.testing.expectEqual(@as(u64, 16), plain_array.alignment(4096));

    const nothrow_array = classifyNew("__ZnamRKSt9nothrow_t") orelse return error.TestUnexpectedResult;
    try std.testing.expect(nothrow_array.array);
    try std.testing.expect(nothrow_array.nothrow);
    try std.testing.expectEqual(@as(u64, 16), nothrow_array.alignment(4096));

    const aligned_array = classifyNew("__ZnamSt11align_val_tRKSt9nothrow_t") orelse return error.TestUnexpectedResult;
    try std.testing.expect(aligned_array.array);
    try std.testing.expect(aligned_array.nothrow);
    try std.testing.expectEqual(@as(u64, 4096), aligned_array.alignment(4096));
    try std.testing.expect(classifyNew("__Znam_not_an_operator") == null);
}

test "classifies delete variants used by libc++" {
    try std.testing.expect(isDelete("__ZdaPv"));
    try std.testing.expect(isDelete("__ZdlPvRKSt9nothrow_t"));
    try std.testing.expect(isDelete("__ZdaPvSt11align_val_tRKSt9nothrow_t"));
    try std.testing.expect(!isDelete("__Znam"));
}
