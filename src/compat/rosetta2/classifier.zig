const std = @import("std");
const types = @import("types.zig");

const FAT_MAGIC: u32 = 0xCAFEBABE;
const FAT_CIGAM: u32 = 0xBEBAFECA;
const FAT_MAGIC_64: u32 = 0xCAFEBABF;
const FAT_CIGAM_64: u32 = 0xBFBAFECA;

const MH_MAGIC: u32 = 0xFEEDFACE;
const MH_CIGAM: u32 = 0xCEFAEDFE;
const MH_MAGIC_64: u32 = 0xFEEDFACF;
const MH_CIGAM_64: u32 = 0xCFFAEDFE;

const CPU_TYPE_I386: u32 = 7;
const CPU_TYPE_X86_64: u32 = 7 | 0x01000000;
const CPU_TYPE_ARM64: u32 = 12 | 0x01000000;

const PE_MACHINE_I386: u16 = 0x014c;
const PE_MACHINE_AMD64: u16 = 0x8664;
const ELF_MACHINE_X86_64: u16 = 62;

pub const Classification = types.Classification;

pub fn classifyPath(io: std.Io, allocator: std.mem.Allocator, raw_path: []const u8) !Classification {
    const requested = try absolutePath(allocator, trimTrailingSlashes(raw_path));
    if (std.ascii.endsWithIgnoreCase(requested, ".app")) {
        const executable = try resolveBundleExecutable(io, allocator, requested);
        var class = try classifyExecutableBytes(io, allocator, executable);
        class.target_kind = .app_bundle;
        class.requested_path = requested;
        class.executable_path = executable;
        return class;
    }

    var class = try classifyExecutableBytes(io, allocator, requested);
    class.target_kind = .file;
    class.requested_path = requested;
    class.executable_path = requested;
    return class;
}

pub fn classifyExecutableBytes(io: std.Io, allocator: std.mem.Allocator, executable_path: []const u8) !Classification {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, executable_path, allocator, .limited(1024 * 1024)) catch |err| {
        return .{
            .target_kind = .file,
            .format = .unknown,
            .arch = .unknown,
            .requested_path = executable_path,
            .executable_path = executable_path,
            .note = try std.fmt.allocPrint(allocator, "read_error={s}", .{@errorName(err)}),
        };
    };

    if (bytes.len >= 4 and std.mem.eql(u8, bytes[0..4], "\x7fELF")) {
        return classifyElf(allocator, executable_path, bytes);
    }
    if (bytes.len >= 2 and std.mem.eql(u8, bytes[0..2], "MZ")) {
        return classifyPe(allocator, executable_path, bytes);
    }
    if (bytes.len >= 8 and looksLikeMachO(bytes)) {
        return classifyMachO(allocator, executable_path, bytes);
    }

    return .{
        .target_kind = .file,
        .format = .unknown,
        .arch = .unknown,
        .requested_path = executable_path,
        .executable_path = executable_path,
        .note = "unrecognized_binary_magic",
    };
}

fn classifyElf(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !Classification {
    _ = allocator;
    if (bytes.len < 20) {
        return .{
            .target_kind = .file,
            .format = .elf,
            .arch = .unknown,
            .requested_path = path,
            .executable_path = path,
            .note = "truncated_elf_header",
        };
    }

    const is_64 = bytes[4] == 2;
    const is_little = bytes[5] == 1;
    const machine = if (is_little) std.mem.readInt(u16, bytes[18..][0..2], .little) else std.mem.readInt(u16, bytes[18..][0..2], .big);
    const is_x86_64 = is_64 and machine == ELF_MACHINE_X86_64;
    return .{
        .target_kind = .file,
        .format = .elf,
        .arch = if (is_x86_64) .x86_64 else .unknown,
        .requested_path = path,
        .executable_path = path,
        .has_x86_64 = is_x86_64,
        .note = if (is_x86_64) "linux_x86_64_elf" else "unsupported_elf_machine",
    };
}

fn classifyPe(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !Classification {
    _ = allocator;
    if (bytes.len < 0x40) {
        return .{
            .target_kind = .file,
            .format = .pe,
            .arch = .unknown,
            .requested_path = path,
            .executable_path = path,
            .note = "truncated_pe_dos_header",
        };
    }

    const pe_off = std.mem.readInt(u32, bytes[0x3c..][0..4], .little);
    if (pe_off > std.math.maxInt(usize)) return peUnknown(path, "pe_header_offset_out_of_range");
    const pe: usize = @intCast(pe_off);
    if (pe + 6 > bytes.len or !std.mem.eql(u8, bytes[pe .. pe + 4], "PE\x00\x00")) {
        return peUnknown(path, "missing_pe_signature");
    }

    const machine = std.mem.readInt(u16, bytes[pe + 4 ..][0..2], .little);
    return .{
        .target_kind = .file,
        .format = .pe,
        .arch = switch (machine) {
            PE_MACHINE_I386 => .x86,
            PE_MACHINE_AMD64 => .x86_64,
            else => .unknown,
        },
        .requested_path = path,
        .executable_path = path,
        .has_x86_64 = machine == PE_MACHINE_AMD64,
        .has_i386 = machine == PE_MACHINE_I386,
        .note = "windows_pe",
    };
}

fn peUnknown(path: []const u8, note: []const u8) Classification {
    return .{
        .target_kind = .file,
        .format = .pe,
        .arch = .unknown,
        .requested_path = path,
        .executable_path = path,
        .note = note,
    };
}

fn looksLikeMachO(bytes: []const u8) bool {
    const magic_le = std.mem.readInt(u32, bytes[0..4], .little);
    const magic_be = std.mem.readInt(u32, bytes[0..4], .big);
    return magic_le == MH_MAGIC or magic_le == MH_CIGAM or
        magic_le == MH_MAGIC_64 or magic_le == MH_CIGAM_64 or
        magic_be == FAT_MAGIC or magic_be == FAT_CIGAM or
        magic_be == FAT_MAGIC_64 or magic_be == FAT_CIGAM_64;
}

fn classifyMachO(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !Classification {
    _ = allocator;
    const magic_be = std.mem.readInt(u32, bytes[0..4], .big);
    if (magic_be == FAT_MAGIC or magic_be == FAT_CIGAM or
        magic_be == FAT_MAGIC_64 or magic_be == FAT_CIGAM_64)
    {
        return classifyFatMachO(path, bytes, magic_be);
    }

    const magic_le = std.mem.readInt(u32, bytes[0..4], .little);
    const cputype = if (magic_le == MH_CIGAM or magic_le == MH_CIGAM_64)
        std.mem.readInt(u32, bytes[4..8], .big)
    else
        std.mem.readInt(u32, bytes[4..8], .little);

    return .{
        .target_kind = .file,
        .format = .mach_o,
        .arch = archFromCpuType(cputype),
        .requested_path = path,
        .executable_path = path,
        .has_arm64 = cputype == CPU_TYPE_ARM64,
        .has_x86_64 = cputype == CPU_TYPE_X86_64,
        .has_i386 = cputype == CPU_TYPE_I386,
        .note = "thin_mach_o",
    };
}

fn classifyFatMachO(path: []const u8, bytes: []const u8, magic: u32) Classification {
    const is_64 = magic == FAT_MAGIC_64 or magic == FAT_CIGAM_64;
    const endian: std.builtin.Endian = if (magic == FAT_MAGIC or magic == FAT_MAGIC_64) .big else .little;
    if (bytes.len < 8) return machUnknown(path, "truncated_fat_header");

    const arch_count = std.mem.readInt(u32, bytes[4..8], endian);
    const arch_size: usize = if (is_64) 32 else 20;
    var pos: usize = 8;
    var seen: usize = 0;
    var has_arm64 = false;
    var has_x86_64 = false;
    var has_i386 = false;

    while (seen < arch_count and pos + arch_size <= bytes.len) : ({
        seen += 1;
        pos += arch_size;
    }) {
        const cputype = std.mem.readInt(u32, bytes[pos..][0..4], endian);
        has_arm64 = has_arm64 or cputype == CPU_TYPE_ARM64;
        has_x86_64 = has_x86_64 or cputype == CPU_TYPE_X86_64;
        has_i386 = has_i386 or cputype == CPU_TYPE_I386;
    }

    const arch: types.GuestArch = if ((has_arm64 and has_x86_64) or (has_arm64 and has_i386) or (has_x86_64 and has_i386))
        .universal
    else if (has_arm64)
        .arm64
    else if (has_x86_64)
        .x86_64
    else if (has_i386)
        .i386
    else
        .unknown;

    return .{
        .target_kind = .file,
        .format = .mach_o,
        .arch = arch,
        .requested_path = path,
        .executable_path = path,
        .has_arm64 = has_arm64,
        .has_x86_64 = has_x86_64,
        .has_i386 = has_i386,
        .note = "universal_mach_o",
    };
}

fn machUnknown(path: []const u8, note: []const u8) Classification {
    return .{
        .target_kind = .file,
        .format = .mach_o,
        .arch = .unknown,
        .requested_path = path,
        .executable_path = path,
        .note = note,
    };
}

fn archFromCpuType(cputype: u32) types.GuestArch {
    return switch (cputype) {
        CPU_TYPE_ARM64 => .arm64,
        CPU_TYPE_X86_64 => .x86_64,
        CPU_TYPE_I386 => .i386,
        else => .unknown,
    };
}

fn resolveBundleExecutable(io: std.Io, allocator: std.mem.Allocator, app_path: []const u8) ![]const u8 {
    const plist_path = try std.fs.path.join(allocator, &.{ app_path, "Contents", "Info.plist" });
    if (readCFBundleExecutable(io, allocator, plist_path)) |exe_name| {
        return std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", exe_name });
    } else |_| {}

    const app_name = std.fs.path.basename(app_path);
    const fallback_name = if (std.ascii.endsWithIgnoreCase(app_name, ".app"))
        app_name[0 .. app_name.len - 4]
    else
        app_name;
    return std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", fallback_name });
}

fn readCFBundleExecutable(io: std.Io, allocator: std.mem.Allocator, plist_path: []const u8) ![]const u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, plist_path, allocator, .limited(1024 * 1024));
    const key = "<key>CFBundleExecutable</key>";
    const key_pos = std.mem.indexOf(u8, data, key) orelse return error.BundleExecutableMissing;
    const tail = data[key_pos + key.len ..];
    const open_tag = "<string>";
    const close_tag = "</string>";
    const open_pos = std.mem.indexOf(u8, tail, open_tag) orelse return error.BundleExecutableMissing;
    const value_start = open_pos + open_tag.len;
    const value_tail = tail[value_start..];
    const close_pos = std.mem.indexOf(u8, value_tail, close_tag) orelse return error.BundleExecutableMissing;
    return allocator.dupe(u8, std.mem.trim(u8, value_tail[0..close_pos], " \t\r\n"));
}

fn trimTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

fn absolutePath(allocator: std.mem.Allocator, raw_path: []const u8) ![]const u8 {
    return std.fs.path.resolve(allocator, &.{raw_path});
}

test "classifies thin x86_64 Mach-O" {
    const hdr = [_]u8{
        0xcf, 0xfa, 0xed, 0xfe,
        0x07, 0x00, 0x00, 0x01,
        0x03, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };
    const class = try classifyMachO(std.testing.allocator, "Xenia", &hdr);
    try std.testing.expectEqual(types.BinaryFormat.mach_o, class.format);
    try std.testing.expectEqual(types.GuestArch.x86_64, class.arch);
    try std.testing.expect(class.has_x86_64);
}

test "classifies x86_64 ELF" {
    var hdr: [64]u8 = [_]u8{0} ** 64;
    @memcpy(hdr[0..4], "\x7fELF");
    hdr[4] = 2;
    hdr[5] = 1;
    std.mem.writeInt(u16, hdr[18..20], ELF_MACHINE_X86_64, .little);
    const class = try classifyElf(std.testing.allocator, "ast01", &hdr);
    try std.testing.expectEqual(types.BinaryFormat.elf, class.format);
    try std.testing.expectEqual(types.GuestArch.x86_64, class.arch);
}
