const std = @import("std");

pub const Profile = enum {
    conservative,
    xenia,
    experimental_avx512,

    pub fn label(self: Profile) []const u8 {
        return switch (self) {
            .conservative => "conservative",
            .xenia => "xenia",
            .experimental_avx512 => "experimental-avx512",
        };
    }
};

pub fn parseProfile(value: []const u8) ?Profile {
    if (std.ascii.eqlIgnoreCase(value, "conservative") or
        std.ascii.eqlIgnoreCase(value, "sse42")) return .conservative;
    if (std.ascii.eqlIgnoreCase(value, "xenia") or
        std.ascii.eqlIgnoreCase(value, "avx")) return .xenia;
    if (std.ascii.eqlIgnoreCase(value, "experimental-avx512") or
        std.ascii.eqlIgnoreCase(value, "avx512")) return .experimental_avx512;
    return null;
}

pub const Feature = enum { sse, sse2, sse3, ssse3, sse41, sse42, avx, avx2, avx512f };

pub fn featureLabel(feature: Feature) []const u8 {
    return switch (feature) {
        .sse => "SSE",
        .sse2 => "SSE2",
        .sse3 => "SSE3",
        .ssse3 => "SSSE3",
        .sse41 => "SSE4.1",
        .sse42 => "SSE4.2",
        .avx => "AVX",
        .avx2 => "AVX2",
        .avx512f => "AVX-512F",
    };
}

pub fn supports(profile: Profile, feature: Feature) bool {
    return switch (profile) {
        .conservative => feature != .avx and feature != .avx2 and feature != .avx512f,
        .xenia => feature != .avx2 and feature != .avx512f,
        .experimental_avx512 => true,
    };
}

pub const CpuidResult = struct { eax: u32 = 0, ebx: u32 = 0, ecx: u32 = 0, edx: u32 = 0 };

pub fn cpuid(profile: Profile, leaf: u32, subleaf: u32) CpuidResult {
    return switch (leaf) {
        0 => .{ .eax = 7, .ebx = 0x756E_6547, .edx = 0x4965_6E69, .ecx = 0x6C65_746E },
        1 => .{
            .eax = 0x0003_06C3,
            .ebx = 0x0008_0000,
            .ecx = leaf1Ecx(profile),
            .edx = (@as(u32, 1) << 0) | (@as(u32, 1) << 4) | (@as(u32, 1) << 5) |
                (@as(u32, 1) << 8) | (@as(u32, 1) << 11) | (@as(u32, 1) << 15) |
                (@as(u32, 1) << 19) | (@as(u32, 1) << 23) | (@as(u32, 1) << 24) |
                (@as(u32, 1) << 25) | (@as(u32, 1) << 26),
        },
        7 => if (subleaf == 0) leaf7(profile) else .{},
        0x8000_0000 => .{ .eax = 0x8000_0008 },
        0x8000_0002 => .{ .eax = 0x6573_6F52, .ebx = 0x2065_7474, .ecx = 0x7472_6956, .edx = 0x206C_6175 },
        0x8000_0003 => .{ .eax = 0x2D36_3878, .ebx = 0x4320_3436, .ecx = 0x2020_5550, .edx = 0x2020_2020 },
        0x8000_0004 => .{},
        0x8000_0008 => .{ .eax = 0x0000_3030 },
        else => .{},
    };
}

fn leaf1Ecx(profile: Profile) u32 {
    var value = (@as(u32, 1) << 0) | (@as(u32, 1) << 1) | (@as(u32, 1) << 9) |
        (@as(u32, 1) << 13) | (@as(u32, 1) << 19) | (@as(u32, 1) << 20) |
        (@as(u32, 1) << 22) | (@as(u32, 1) << 23) | (@as(u32, 1) << 25);
    if (profile != .conservative) {
        value |= (@as(u32, 1) << 26) | (@as(u32, 1) << 27) | (@as(u32, 1) << 28);
    }
    return value;
}

fn leaf7(profile: Profile) CpuidResult {
    if (profile == .experimental_avx512) {
        return .{ .ebx = (@as(u32, 1) << 5) | (@as(u32, 1) << 16) |
            (@as(u32, 1) << 17) | (@as(u32, 1) << 28) |
            (@as(u32, 1) << 30) | (@as(u32, 1) << 31) };
    }
    return .{};
}

pub fn xcr0(profile: Profile) u64 {
    return switch (profile) {
        .conservative => 0x3,
        .xenia => 0x7,
        .experimental_avx512 => 0xE7,
    };
}

pub const Encoding = enum { legacy, vex, evex };
pub const Requirement = struct { encoding: Encoding, feature: Feature };

/// Identifies the broad ISA family that blocked decode without pretending to
/// be a second instruction decoder.
pub fn classifyRequirement(bytes: []const u8) ?Requirement {
    if (bytes.len == 0) return null;
    var pos: usize = 0;
    var prefix_66 = false;
    while (pos < bytes.len) : (pos += 1) {
        switch (bytes[pos]) {
            0x66 => prefix_66 = true,
            0x40...0x4F, 0x67, 0xF0, 0xF2, 0xF3 => {},
            else => break,
        }
    }
    if (pos >= bytes.len) return null;
    return switch (bytes[pos]) {
        0x62 => .{ .encoding = .evex, .feature = .avx512f },
        0xC4, 0xC5 => .{ .encoding = .vex, .feature = .avx },
        0x0F => .{ .encoding = .legacy, .feature = if (prefix_66) .sse2 else .sse },
        else => null,
    };
}

test "profiles expose coherent AVX and AVX-512 state" {
    const avx = cpuid(.xenia, 1, 0);
    try std.testing.expect(avx.ecx & (@as(u32, 1) << 27) != 0);
    try std.testing.expect(avx.ecx & (@as(u32, 1) << 28) != 0);
    try std.testing.expectEqual(@as(u64, 0x7), xcr0(.xenia));
    const avx512 = cpuid(.experimental_avx512, 7, 0);
    try std.testing.expect(avx512.ebx & (@as(u32, 1) << 16) != 0);
    try std.testing.expectEqual(@as(u64, 0xE7), xcr0(.experimental_avx512));
}

test "classify VEX and EVEX instruction families" {
    try std.testing.expectEqual(Feature.avx, classifyRequirement(&.{ 0xC5, 0xF8, 0x57, 0xC0 }).?.feature);
    try std.testing.expectEqual(Feature.avx512f, classifyRequirement(&.{ 0x62, 0xF1, 0x7C, 0x48 }).?.feature);
}
