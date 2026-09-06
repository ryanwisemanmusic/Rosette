//! Source-architecture detection and library-selection policy.
//!
//! Rosette has two different architecture questions:
//! * what the host process is compiled for; and
//! * what architecture the source image actually contains.
//!
//! The second one owns dependency selection. An ARM64 Rosette process may
//! still be executing an x86-64 PE, ELF, or Mach-O slice, in which case the
//! x86 provider is required for the translated build/runtime boundary. A
//! native ARM64 source image selects native libraries instead. Universal
//! Mach-O images select x86 when they contain an x86-64 slice, because that is
//! the slice Rosette must be able to translate.

const std = @import("std");

pub const Architecture = enum(u8) {
    x86_64,
    arm64,
    mixed,
    unknown,

    pub fn label(self: Architecture) []const u8 {
        return switch (self) {
            .x86_64 => "x86_64",
            .arm64 => "arm64",
            .mixed => "mixed",
            .unknown => "unknown",
        };
    }
};

pub const Container = enum(u8) {
    macho,
    pe,
    elf,
    unknown,

    pub fn label(self: Container) []const u8 {
        return switch (self) {
            .macho => "Mach-O",
            .pe => "PE",
            .elf => "ELF",
            .unknown => "unknown",
        };
    }
};

pub const Detection = struct {
    architecture: Architecture = .unknown,
    container: Container = .unknown,
    x86_present: bool = false,
    arm64_present: bool = false,

    /// The provider that must be selected for this source. Unknown formats
    /// deliberately choose ARM64: native code is the safe default, while an
    /// x86 source is selected only after a concrete container/header proof.
    pub fn libraryArchitecture(self: Detection) Architecture {
        return if (self.x86_present) .x86_64 else .arm64;
    }

    pub fn usesX86Libraries(self: Detection) bool {
        return self.libraryArchitecture() == .x86_64;
    }

    pub fn usesNativeArm64Libraries(self: Detection) bool {
        return !self.usesX86Libraries();
    }
};

const Endian = enum { little, big };

const FAT_MAGIC: u32 = 0xCAFE_BABE;
const FAT_MAGIC_64: u32 = 0xCAFE_BABF;
const MH_MAGIC: u32 = 0xFEED_FACE;
const MH_MAGIC_64: u32 = 0xFEED_FACF;

const CPU_TYPE_X86_64: u32 = 0x0100_0007;
const CPU_TYPE_ARM64: u32 = 0x0100_000C;

const PE_MACHINE_X86_64: u16 = 0x8664;
const PE_MACHINE_ARM64: u16 = 0xAA64;

const ELF_MACHINE_X86_64: u16 = 62;
const ELF_MACHINE_ARM64: u16 = 183;

fn readU16(bytes: []const u8, offset: usize, endian: Endian) ?u16 {
    if (offset > bytes.len or bytes.len - offset < 2) return null;
    return std.mem.readInt(u16, bytes[offset..][0..2], if (endian == .little) .little else .big);
}

fn readU32(bytes: []const u8, offset: usize, endian: Endian) ?u32 {
    if (offset > bytes.len or bytes.len - offset < 4) return null;
    return std.mem.readInt(u32, bytes[offset..][0..4], if (endian == .little) .little else .big);
}

fn detection(container: Container, x86: bool, arm64: bool) Detection {
    return .{
        .architecture = if (x86 and arm64)
            .mixed
        else if (x86)
            .x86_64
        else if (arm64)
            .arm64
        else
            .unknown,
        .container = container,
        .x86_present = x86,
        .arm64_present = arm64,
    };
}

fn noteCpu(cputype: u32, x86: *bool, arm64: *bool) void {
    if (cputype == CPU_TYPE_X86_64) x86.* = true;
    if (cputype == CPU_TYPE_ARM64) arm64.* = true;
}

fn detectMachO(bytes: []const u8) ?Detection {
    if (bytes.len < 8) return null;
    const magic_little = readU32(bytes, 0, .little) orelse return null;
    const magic_big = readU32(bytes, 0, .big) orelse return null;

    const thin_endian: ?Endian = if (magic_little == MH_MAGIC or magic_little == MH_MAGIC_64)
        .little
    else if (magic_big == MH_MAGIC or magic_big == MH_MAGIC_64)
        .big
    else
        null;
    if (thin_endian) |endian| {
        var x86 = false;
        var arm64 = false;
        noteCpu(readU32(bytes, 4, endian) orelse return null, &x86, &arm64);
        return detection(.macho, x86, arm64);
    }

    const fat_endian: ?Endian = if (magic_big == FAT_MAGIC or magic_big == FAT_MAGIC_64)
        .big
    else if (magic_little == FAT_MAGIC or magic_little == FAT_MAGIC_64)
        .little
    else
        null;
    const endian = fat_endian orelse return null;
    const is_fat64 = (if (endian == .big) magic_big else magic_little) == FAT_MAGIC_64;
    const count = readU32(bytes, 4, endian) orelse return null;
    // A header with an absurd architecture count is not a reason to scan
    // unbounded guest memory. It is simply an unrecognised/unsafe container.
    if (count > 256) return detection(.macho, false, false);

    var x86 = false;
    var arm64 = false;
    const entry_size: usize = if (is_fat64) 32 else 20;
    const count_usize: usize = @intCast(count);
    if (count_usize > (bytes.len -| 8) / entry_size) return detection(.macho, false, false);
    for (0..count_usize) |index| {
        const entry = 8 + index * entry_size;
        noteCpu(readU32(bytes, entry, endian) orelse continue, &x86, &arm64);
        // Reading the offsets/sizes is not needed for architecture choice.
        // The header itself is sufficient to prove that an x86 slice exists.
    }
    return detection(.macho, x86, arm64);
}

fn detectPe(bytes: []const u8) ?Detection {
    if (bytes.len < 2 or bytes[0] != 'M' or bytes[1] != 'Z') return null;
    const pe_offset = readU32(bytes, 0x3C, .little) orelse return detection(.pe, false, false);
    const offset: usize = @intCast(pe_offset);
    if (offset > bytes.len or bytes.len - offset < 6) return detection(.pe, false, false);
    if (!std.mem.eql(u8, bytes[offset..][0..4], "PE\x00\x00")) return detection(.pe, false, false);
    const machine = readU16(bytes, offset + 4, .little) orelse return detection(.pe, false, false);
    return detection(.pe, machine == PE_MACHINE_X86_64, machine == PE_MACHINE_ARM64);
}

fn detectElf(bytes: []const u8) ?Detection {
    if (bytes.len < 20 or !std.mem.eql(u8, bytes[0..4], "\x7F" ++ "ELF")) return null;
    const data = bytes[5];
    const endian: Endian = switch (data) {
        1 => .little,
        2 => .big,
        else => return detection(.elf, false, false),
    };
    const machine = readU16(bytes, 18, endian) orelse return detection(.elf, false, false);
    return detection(.elf, machine == ELF_MACHINE_X86_64, machine == ELF_MACHINE_ARM64);
}

pub fn detect(bytes: []const u8) Detection {
    if (detectMachO(bytes)) |result| return result;
    if (detectPe(bytes)) |result| return result;
    if (detectElf(bytes)) |result| return result;
    return .{};
}

test "thin Mach-O source selects x86 provider" {
    var bytes = [_]u8{0} ** 32;
    std.mem.writeInt(u32, bytes[0..4], MH_MAGIC_64, .little);
    std.mem.writeInt(u32, bytes[4..8], CPU_TYPE_X86_64, .little);
    const result = detect(&bytes);
    try std.testing.expectEqual(Container.macho, result.container);
    try std.testing.expectEqual(Architecture.x86_64, result.architecture);
    try std.testing.expect(result.usesX86Libraries());
}

test "universal Mach-O containing x86 and ARM selects x86 provider" {
    var bytes = [_]u8{0} ** 48;
    std.mem.writeInt(u32, bytes[0..4], FAT_MAGIC, .big);
    std.mem.writeInt(u32, bytes[4..8], 2, .big);
    std.mem.writeInt(u32, bytes[8..12], CPU_TYPE_X86_64, .big);
    std.mem.writeInt(u32, bytes[28..32], CPU_TYPE_ARM64, .big);
    const result = detect(&bytes);
    try std.testing.expectEqual(Architecture.mixed, result.architecture);
    try std.testing.expect(result.x86_present);
    try std.testing.expect(result.arm64_present);
    try std.testing.expectEqual(Architecture.x86_64, result.libraryArchitecture());
}

test "x86-64 PE source selects x86 provider" {
    var bytes = [_]u8{0} ** 128;
    bytes[0] = 'M';
    bytes[1] = 'Z';
    std.mem.writeInt(u32, bytes[0x3C..][0..4], 0x40, .little);
    @memcpy(bytes[0x40..0x44], "PE\x00\x00");
    std.mem.writeInt(u16, bytes[0x44..][0..2], PE_MACHINE_X86_64, .little);
    const result = detect(&bytes);
    try std.testing.expectEqual(Container.pe, result.container);
    try std.testing.expectEqual(Architecture.x86_64, result.architecture);
    try std.testing.expect(result.usesX86Libraries());
}

test "ARM64 ELF source selects native provider" {
    var bytes = [_]u8{0} ** 64;
    @memcpy(bytes[0..4], "\x7F" ++ "ELF");
    bytes[4] = 2;
    bytes[5] = 1;
    std.mem.writeInt(u16, bytes[18..][0..2], ELF_MACHINE_ARM64, .little);
    const result = detect(&bytes);
    try std.testing.expectEqual(Container.elf, result.container);
    try std.testing.expectEqual(Architecture.arm64, result.architecture);
    try std.testing.expect(result.usesNativeArm64Libraries());
}

test "unknown source defaults to native libraries" {
    const result = detect("not an executable");
    try std.testing.expectEqual(Architecture.unknown, result.architecture);
    try std.testing.expectEqual(Architecture.arm64, result.libraryArchitecture());
}
