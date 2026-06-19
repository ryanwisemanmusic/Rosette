const std = @import("std");

pub const MH_MAGIC: u32 = 0xFEEDFACE;
pub const MH_CIGAM: u32 = 0xCEFAEDFE;
pub const MH_MAGIC_64: u32 = 0xFEEDFACF;
pub const MH_CIGAM_64: u32 = 0xCFFAEDFE;

pub const CPU_TYPE_I386: u32 = 7;
pub const CPU_TYPE_X86_64: u32 = 7 | 0x01000000;
pub const CPU_TYPE_ARM64: u32 = 12 | 0x01000000;

pub const MH_EXECUTE: u32 = 2;
pub const MH_DYLIB: u32 = 6;
pub const MH_BUNDLE: u32 = 8;

pub const LC_SEGMENT: u32 = 0x01;
pub const LC_SEGMENT_64: u32 = 0x19;
pub const LC_SYMTAB: u32 = 0x02;
pub const LC_DYSYMTAB: u32 = 0x0B;
pub const LC_LOAD_DYLIB: u32 = 0x0C;
pub const LC_UUID: u32 = 0x1B;
pub const LC_CODE_SIGNATURE: u32 = 0x1D;
pub const LC_MAIN: u32 = 0x28 | 0x80000000;
pub const LC_VERSION_MIN_MACOSX: u32 = 0x24;
pub const LC_SOURCE_VERSION: u32 = 0x2A;
pub const LC_FUNCTION_STARTS: u32 = 0x26;
pub const LC_DATA_IN_CODE: u32 = 0x29;
pub const LC_ENCRYPTION_INFO_64: u32 = 0x2C;
pub const LC_BUILD_VERSION: u32 = 0x32;
pub const LC_RPATH: u32 = 0x1C | 0x80000000;
pub const LC_LOAD_UPWARD_DYLIB: u32 = 0x23 | 0x80000000;
pub const LC_REEXPORT_DYLIB: u32 = 0x1F | 0x80000000;

pub const MachHeader64 = packed struct {
    magic: u32,
    cputype: u32,
    cpusubtype: u32,
    filetype: u32,
    ncmds: u32,
    sizeofcmds: u32,
    flags: u32,
    reserved: u32,
};

pub const LoadCommand = packed struct {
    cmd: u32,
    cmdsize: u32,
};

pub const SegmentCommand64 = extern struct {
    cmd: u32,
    cmdsize: u32,
    segname: [16]u8,
    vmaddr: u64,
    vmsize: u64,
    fileoff: u64,
    filesize: u64,
    maxprot: u32,
    initprot: u32,
    nsects: u32,
    flags: u32,
};

pub const Section64 = extern struct {
    sectname: [16]u8,
    segname: [16]u8,
    addr: u64,
    size: u64,
    offset: u32,
    alignment: u32,
    reloff: u32,
    nreloc: u32,
    flags: u32,
    reserved1: u32,
    reserved2: u32,
    reserved3: u32,
};

pub const EntryPoint = packed struct {
    cmd: u32,
    cmdsize: u32,
    entryoff: u64,
    stacksize: u64,
};

pub const MachSegment = struct {
    name: []const u8,
    vmaddr: u64,
    vmsize: u64,
    fileoff: u64,
    filesize: u64,
    initprot: u32,
};

pub const MachOState = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    header: MachHeader64,
    entry_point: u64,
    stack_size: u64,
    segments: []const MachSegment,
    terminated: bool = false,
    exit_code: u64 = 0,

    pub fn deinit(self: *MachOState) void {
        for (self.segments) |seg| self.allocator.free(seg.name);
        self.allocator.free(self.segments);
    }
};

pub fn load(allocator: std.mem.Allocator, data: []const u8) !MachOState {
    if (data.len < @sizeOf(MachHeader64)) return error.TruncatedMachO;
    const magic = std.mem.readInt(u32, data[0..4], .little);
    if (magic != MH_MAGIC_64 and magic != MH_CIGAM_64) return error.Not64BitMachO;

    const endian: std.builtin.Endian = if (magic == MH_MAGIC_64) .little else .big;
    const header = std.mem.bytesToValue(MachHeader64, data[0..@sizeOf(MachHeader64)]);
    if (header.filetype != MH_EXECUTE) return error.NotExecutable;

    var segments: std.ArrayList(MachSegment) = .empty;
    errdefer {
        for (segments.items) |s| allocator.free(s.name);
        segments.deinit(allocator);
    }

    var entry_point: u64 = 0;
    var stack_size: u64 = 0;
    var pos: usize = @sizeOf(MachHeader64);
    const cmds_end = pos + header.sizeofcmds;

    for (0..header.ncmds) |_| {
        if (pos + 8 > data.len) break;
        const cmd = std.mem.readInt(u32, data[pos..][0..4], endian);
        const cmdsize = std.mem.readInt(u32, data[pos + 4 ..][0..4], endian);
        if (cmdsize < 8 or pos + cmdsize > data.len) break;

        switch (cmd) {
            LC_SEGMENT_64 => {
                const seg = std.mem.bytesToValue(SegmentCommand64, data[pos..][0..@sizeOf(SegmentCommand64)]);
                const name_end = std.mem.indexOfScalar(u8, &seg.segname, 0) orelse 16;
                const name = try allocator.dupe(u8, seg.segname[0..name_end]);
                try segments.append(allocator, .{
                    .name = name,
                    .vmaddr = seg.vmaddr,
                    .vmsize = seg.vmsize,
                    .fileoff = seg.fileoff,
                    .filesize = seg.filesize,
                    .initprot = seg.initprot,
                });
            },
            LC_MAIN => {
                const ep = std.mem.bytesToValue(EntryPoint, data[pos..][0..@sizeOf(EntryPoint)]);
                entry_point = ep.entryoff;
                stack_size = ep.stacksize;
            },
            else => {},
        }

        pos += cmdsize;
        if (pos >= cmds_end) break;
    }

    return MachOState{
        .allocator = allocator,
        .data = data,
        .header = header,
        .entry_point = entry_point,
        .stack_size = stack_size,
        .segments = try segments.toOwnedSlice(allocator),
    };
}
