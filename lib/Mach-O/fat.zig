const std = @import("std");
const macho = @import("macho_core").macho;

pub const FAT_MAGIC: u32 = 0xCAFEBABE;
pub const FAT_CIGAM: u32 = 0xBEBAFECA;
pub const FAT_MAGIC_64: u32 = 0xCAFEBABF;
pub const FAT_CIGAM_64: u32 = 0xBFBAFECA;

pub const FatArch = packed struct {
    cputype: u32,
    cpusubtype: u32,
    offset: u32,
    size: u32,
    alignment: u32,
};

pub const FatArch64 = packed struct {
    cputype: u32,
    cpusubtype: u32,
    offset: u64,
    size: u64,
    alignment: u32,
    reserved: u32,
};

pub fn extractX8664Slice(_: std.mem.Allocator, data: []const u8) ![]const u8 {
    if (data.len < 8) return error.TruncatedFatBinary;
    const magic = std.mem.readInt(u32, data[0..4], .big);
    const is_64 = magic == FAT_MAGIC_64 or magic == FAT_CIGAM_64;
    const is_fat = magic == FAT_MAGIC or magic == FAT_CIGAM or is_64;
    if (!is_fat) {
        if (data.len >= 4) {
            const mh_magic = std.mem.readInt(u32, data[0..4], .little);
            if (mh_magic == macho.MH_MAGIC_64 or mh_magic == macho.MH_CIGAM_64) {
                return data;
            }
        }
        return error.NotMachO;
    }

    const endian: std.builtin.Endian = if (magic == FAT_MAGIC or magic == FAT_MAGIC_64) .big else .little;
    const narchives = std.mem.readInt(u32, data[4..8], endian);
    if (narchives > 128) return error.TooManyArchitectures;

    var pos: usize = 8;
    for (0..narchives) |_| {
        if (is_64) {
            if (pos + @sizeOf(FatArch64) > data.len) break;
            const cpu = std.mem.readInt(u32, data[pos..][0..4], endian);
            const offset = std.mem.readInt(u64, data[pos + 8 ..][0..8], endian);
            const size = std.mem.readInt(u64, data[pos + 16 ..][0..8], endian);
            if (cpu == macho.CPU_TYPE_X86_64 and offset + size <= data.len) {
                return data[offset .. offset + size];
            }
            pos += @sizeOf(FatArch64);
        } else {
            if (pos + @sizeOf(FatArch) > data.len) break;
            const cpu = std.mem.readInt(u32, data[pos..][0..4], endian);
            const offset = std.mem.readInt(u32, data[pos + 8 ..][0..4], endian);
            const size = std.mem.readInt(u32, data[pos + 12 ..][0..4], endian);
            if (cpu == macho.CPU_TYPE_X86_64 and offset + size <= data.len) {
                return data[offset .. offset + size];
            }
            pos += @sizeOf(FatArch);
        }
    }

    return error.NoX86_64Slice;
}
