//! ARM64-route selection facts for hot Xenia Mach-O primitive imports.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";
pub const guest_pointer_bits: u8 = 32;
pub const host_pointer_bits: u8 = 64;

pub const PrimitiveFamily = enum(u8) {
    strlen,
    memcmp,
    memcpy,
    strcmp,
    cxa_guard_acquire,
    cxa_guard_release,
    cxa_guard_abort,
    string_compare,
    string_rfind,
};

pub fn lookup(symbol_name: []const u8) ?PrimitiveFamily {
    if (std.mem.indexOf(u8, symbol_name, "strlen") != null) return .strlen;
    if (std.mem.indexOf(u8, symbol_name, "memcmp") != null) return .memcmp;
    if (std.mem.indexOf(u8, symbol_name, "memcpy") != null) return .memcpy;
    if (std.mem.indexOf(u8, symbol_name, "strcmp") != null) return .strcmp;
    if (std.mem.indexOf(u8, symbol_name, "__cxa_guard_acquire") != null) return .cxa_guard_acquire;
    if (std.mem.indexOf(u8, symbol_name, "__cxa_guard_release") != null) return .cxa_guard_release;
    if (std.mem.indexOf(u8, symbol_name, "__cxa_guard_abort") != null) return .cxa_guard_abort;
    if (std.mem.indexOf(u8, symbol_name, "compareEmmPKc") != null) return .string_compare;
    if (std.mem.indexOf(u8, symbol_name, "allocatorIcEEE5rfindEcm") != null) return .string_rfind;
    if (std.mem.indexOf(u8, symbol_name, "allocatorIcEEE5rfindB7v160006Ecm") != null) return .string_rfind;
    return null;
}

pub fn contractIsWellFormed() bool {
    return guest_pointer_bits == 32 and host_pointer_bits == 64 and
        host_architecture.len != 0 and host_codegen.len != 0;
}

test "hot primitive names select only existing route families" {
    try std.testing.expectEqual(PrimitiveFamily.strcmp, lookup("_strcmp") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.strlen, lookup("_strlen") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.memcmp, lookup("_memcmp") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.memcpy, lookup("_memcpy") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.cxa_guard_acquire, lookup("___cxa_guard_acquire") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.cxa_guard_release, lookup("___cxa_guard_release") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.string_compare, lookup("__ZNK4Xeno10compareEmmPKc") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(PrimitiveFamily.string_rfind, lookup("__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE5rfindEcm") orelse return error.TestUnexpectedResult);
    try std.testing.expect(lookup("__ZNKSt3__117basic_string_viewIcNSt11char_traitsIcEEE5rfindEcm") == null);
    try std.testing.expect(lookup("_unknown_function") == null);
    try std.testing.expect(contractIsWellFormed());
}

test "package identity is the ARM64 native bridge route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
}
