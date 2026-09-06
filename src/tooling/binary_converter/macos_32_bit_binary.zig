const std = @import("std");
const macho = @import("../app_parser/macho_parser.zig");
const fat = @import("../app_parser/fat_binary.zig");

pub const ConvertError = error{
    Not32BitMachO,
    UnsupportedCPUType,
    ConversionFailed,
};

pub fn isConvertible32BitMachO(image: macho.MachImage) bool {
    if (image.is_64) return false;
    if (image.header.cputype != macho.CPU_TYPE_I386) return false;
    return true;
}

pub fn convertMachOToARM64(allocator: std.mem.Allocator, image: macho.MachImage, data: []const u8) ![]u8 {
    _ = image;
    _ = allocator;
    _ = data;
    return error.ConversionFailed;
}

pub fn extract32BitSlice(allocator: std.mem.Allocator, ub: fat.UniversalBinary) ![]const u8 {
    const slice = ub.getSlice(macho.CPU_TYPE_I386) orelse return error.Not32BitMachO;
    return try allocator.dupe(u8, slice.data);
}

pub fn strip32BitSlice(allocator: std.mem.Allocator, ub: fat.UniversalBinary) ![]u8 {
    _ = ub;
    _ = allocator;
    return error.ConversionFailed;
}

test "isConvertible detects 32-bit Mach-O" {
    const hdr = macho.MachHeader32{
        .magic = macho.MH_MAGIC,
        .cputype = macho.CPU_TYPE_I386,
        .cpusubtype = 3,
        .filetype = macho.MH_EXECUTE,
        .ncmds = 0,
        .sizeofcmds = 0,
        .flags = 0,
    };
    const image = macho.MachImage{
        .is_64 = false,
        .is_32_bit = true,
        .header = hdr,
        .cputype = macho.CPU_TYPE_I386,
        .cpusubtype = 3,
        .filetype = macho.MH_EXECUTE,
        .segments = &.{},
        .dylibs = &.{},
        .uuid = null,
        .entry_point = 0,
        .code_signature_offset = 0,
        .code_signature_size = 0,
        .allocator = std.testing.allocator,
    };
    try std.testing.expect(isConvertible32BitMachO(image));
}

test "extract 32-bit slice from fat binary" {
    var arch = fat.FatArch{
        .cputype = macho.CPU_TYPE_I386,
        .cpusubtype = 3,
        .offset = 8 + @sizeOf(fat.FatArch),
        .size = 4,
        .alignment = 0,
    };
    var fat_hdr = fat.FatHeader{
        .magic = fat.FAT_MAGIC,
        .narchives = 1,
    };
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    buf.appendSlice(std.testing.allocator, std.mem.asBytes(&fat_hdr)) catch unreachable;
    buf.appendSlice(std.testing.allocator, std.mem.asBytes(&arch)) catch unreachable;
    buf.appendSlice(std.testing.allocator, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }) catch unreachable;

    var ub = try fat.parseFatBinary(std.testing.allocator, buf.items);
    defer ub.deinit();
    const slice = try extract32BitSlice(std.testing.allocator, ub);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 4), slice.len);
}
