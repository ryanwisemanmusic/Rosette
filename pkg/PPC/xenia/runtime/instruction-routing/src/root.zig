//! Static routing facts for the Xenon PPC execution units.
//!
//! The decoder's group is the runtime fallback because it is a property of the
//! decoded opcode record. These name-based exceptions and prefixes are fixed
//! by the instruction table and live here so every dispatcher can share them.

const std = @import("std");

pub const guest_architecture = "ppc32-xenon";
pub const host_architecture = "any";

pub const Hint = enum {
    system,
    branch,
    floating_point,
    vector,
};

const system_names = [_][]const u8{
    "sc",   "sync", "isync", "eieio", "mfspr",  "mtspr",
    "mftb", "mfcr", "mtcrf", "mcrxr", "tw",     "td",
    "twi",  "tdi",  "mfmsr", "mtmsr", "mtmsrd",
};

const branch_names = [_][]const u8{
    "bx",   "bcx",   "bclrx", "bcctrx", "crand", "crandc",
    "cror", "crorc", "crxor", "crnand", "crnor", "creqv",
    "mcrf",
};

const floating_names = [_][]const u8{
    "mcrfs", "mffsx", "mtfsfx", "mtfsb0x", "mtfsb1x", "mtfsfix",
};

const vector_names = [_][]const u8{ "mfvscr", "mtvscr" };

pub fn overrideFor(name: []const u8) ?Hint {
    inline for (system_names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return .system;
    }
    inline for (branch_names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return .branch;
    }
    inline for (floating_names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return .floating_point;
    }
    inline for (vector_names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return .vector;
    }
    return null;
}

pub fn startsWith(name: []const u8, prefix: []const u8) bool {
    return name.len >= prefix.len and std.mem.eql(u8, name[0..prefix.len], prefix);
}

pub fn isVector128(name: []const u8) bool {
    return !std.mem.eql(u8, name, "dcbz128") and
        name.len > 3 and
        std.mem.eql(u8, name[name.len - 3 ..], "128");
}

pub fn isVectorMemory(name: []const u8) bool {
    return startsWith(name, "lv") or startsWith(name, "stv");
}

pub fn isFloatingMemory(name: []const u8) bool {
    return startsWith(name, "lf") or startsWith(name, "stf");
}

pub fn isVector(name: []const u8) bool {
    return name.len != 0 and name[0] == 'v';
}

test "the exception table preserves the Xenon execution-unit ownership" {
    try std.testing.expectEqual(Hint.system, overrideFor("sync").?);
    try std.testing.expectEqual(Hint.branch, overrideFor("cror").?);
    try std.testing.expectEqual(Hint.floating_point, overrideFor("mcrfs").?);
    try std.testing.expectEqual(Hint.vector, overrideFor("mfvscr").?);
    try std.testing.expect(overrideFor("addx") == null);
}

test "prefix facts distinguish VMX128 from ordinary memory" {
    try std.testing.expect(isVector128("lvx128"));
    try std.testing.expect(!isVector128("dcbz128"));
    try std.testing.expect(isVectorMemory("stvewx"));
    try std.testing.expect(isFloatingMemory("lfd"));
    try std.testing.expect(isVector("vaddubm"));
}
