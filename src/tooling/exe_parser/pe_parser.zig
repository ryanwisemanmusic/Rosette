const std = @import("std");
const fmt = @import("pe_format.zig");

pub const Section = struct {
    name: [8]u8,
    virtual_size: u32,
    virtual_address: u32,
    raw_size: u32,
    raw_offset: u32,
    characteristics: u32,

    pub fn isExecutable(self: Section) bool {
        return (self.characteristics & 0x2000_0000) != 0;
    }

    pub fn isReadable(self: Section) bool {
        return (self.characteristics & 0x4000_0000) != 0;
    }

    pub fn isWritable(self: Section) bool {
        return (self.characteristics & 0x8000_0000) != 0;
    }

    /// The bytes occupied by this section after the loader has zero-filled its
    /// virtual tail.  PE permits a zero VirtualSize, in which case RawSize is
    /// the only useful extent.
    pub fn mappedSize(self: Section) u32 {
        return @max(self.virtual_size, self.raw_size);
    }
};

pub const OptionalHeaderKind = enum(u8) {
    pe32,
    pe32_plus,
};

pub const DataDirectory = struct {
    virtual_address: u32 = 0,
    size: u32 = 0,

    pub fn present(self: DataDirectory) bool {
        return self.virtual_address != 0 and self.size != 0;
    }

    pub fn end(self: DataDirectory) ?u32 {
        return std.math.add(u32, self.virtual_address, self.size) catch null;
    }
};

pub const data_directory_count: usize = 16;

pub const Image = struct {
    pe_offset: u32,
    machine: u16,
    coff_characteristics: u16,
    optional_header_kind: OptionalHeaderKind,
    optional_header_size: u16,
    entry_rva: u32,
    image_base: u64,
    subsystem: u16,
    dll_characteristics: u16,
    section_alignment: u32,
    file_alignment: u32,
    size_of_image: u32,
    size_of_headers: u32,
    size_of_stack_reserve: u64,
    size_of_stack_commit: u64,
    size_of_heap_reserve: u64,
    size_of_heap_commit: u64,
    number_of_rva_and_sizes: u32,
    data_directories: [data_directory_count]DataDirectory,
    number_of_sections: u16,
    sections: []Section,

    pub fn isPe32Plus(self: *const Image) bool {
        return self.optional_header_kind == .pe32_plus;
    }

    pub fn entryAddress(self: *const Image, load_base: u64) ?u64 {
        return std.math.add(u64, load_base, self.entry_rva) catch null;
    }

    pub fn dataDirectory(self: *const Image, index: usize) ?DataDirectory {
        if (index >= data_directory_count or @as(u64, index) >= self.number_of_rva_and_sizes) return null;
        const directory = self.data_directories[index];
        return if (directory.present()) directory else null;
    }

    pub fn sectionForRva(self: *const Image, rva: u32) ?*const Section {
        for (self.sections) |*section| {
            const end = std.math.add(u32, section.virtual_address, section.mappedSize()) catch continue;
            if (rva >= section.virtual_address and rva < end) return section;
        }
        return null;
    }

    pub fn rvaInImage(self: *const Image, rva: u32, size: u32) bool {
        const end = std.math.add(u32, rva, size) catch return false;
        return rva < self.size_of_image and end <= self.size_of_image;
    }
};

pub const ParseError = error{
    FileTooSmall,
    InvalidDosSignature,
    InvalidPeSignature,
    UnsupportedOptionalHeader,
    OptionalHeaderTruncated,
    MachineFormatMismatch,
    TruncatedSectionTable,
    TruncatedSectionData,
    InvalidImageLayout,
    OutOfMemory,
};

fn readU16(bytes: []const u8, offset: usize) ParseError!u16 {
    if (offset > bytes.len or bytes.len - offset < 2) return error.FileTooSmall;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32(bytes: []const u8, offset: usize) ParseError!u32 {
    if (offset > bytes.len or bytes.len - offset < 4) return error.FileTooSmall;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn readU64(bytes: []const u8, offset: usize) ParseError!u64 {
    if (offset > bytes.len or bytes.len - offset < 8) return error.FileTooSmall;
    return @as(u64, try readU32(bytes, offset)) |
        (@as(u64, try readU32(bytes, offset + 4)) << 32);
}

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Image {
    if (bytes.len < 0x40) return error.FileTooSmall;
    if (try readU16(bytes, 0) != fmt.dos.signature) return error.InvalidDosSignature;

    const pe_offset = try readU32(bytes, 0x3C);
    const pe_offset_usize: usize = @intCast(pe_offset);
    if (pe_offset_usize > bytes.len or bytes.len - pe_offset_usize < 24) return error.FileTooSmall;
    if (try readU32(bytes, pe_offset_usize) != fmt.coff.signature) return error.InvalidPeSignature;

    const coff_offset = pe_offset_usize + 4;
    const machine = try readU16(bytes, coff_offset + 0);
    const number_of_sections = try readU16(bytes, coff_offset + 2);
    const size_of_optional_header = try readU16(bytes, coff_offset + 16);
    const optional_offset = coff_offset + 20;
    if (size_of_optional_header < 2 or optional_offset > bytes.len or
        bytes.len - optional_offset < size_of_optional_header)
    {
        return error.OptionalHeaderTruncated;
    }
    const optional_magic = try readU16(bytes, optional_offset);

    var image_base: u64 = 0;
    var entry_rva: u32 = 0;
    var subsystem: u16 = 0;
    var section_alignment: u32 = 0;
    var file_alignment: u32 = 0;
    var size_of_image: u32 = 0;
    var size_of_headers: u32 = 0;
    var dll_characteristics: u16 = 0;
    var size_of_stack_reserve: u64 = 0;
    var size_of_stack_commit: u64 = 0;
    var size_of_heap_reserve: u64 = 0;
    var size_of_heap_commit: u64 = 0;
    var number_of_rva_and_sizes: u32 = 0;
    var optional_header_kind: OptionalHeaderKind = undefined;

    var data_directories = [_]DataDirectory{.{}} ** data_directory_count;

    switch (optional_magic) {
        fmt.coff.optional_magic_pe32 => {
            if (size_of_optional_header < fmt.opt32.minimum_size) return error.OptionalHeaderTruncated;
            optional_header_kind = .pe32;
            entry_rva = try readU32(bytes, optional_offset + 16);
            image_base = try readU32(bytes, optional_offset + 28);
            section_alignment = try readU32(bytes, optional_offset + 32);
            file_alignment = try readU32(bytes, optional_offset + 36);
            size_of_image = try readU32(bytes, optional_offset + 56);
            size_of_headers = try readU32(bytes, optional_offset + 60);
            subsystem = try readU16(bytes, optional_offset + 68);
            dll_characteristics = try readU16(bytes, optional_offset + 70);
            size_of_stack_reserve = try readU32(bytes, optional_offset + 72);
            size_of_stack_commit = try readU32(bytes, optional_offset + 76);
            size_of_heap_reserve = try readU32(bytes, optional_offset + 80);
            size_of_heap_commit = try readU32(bytes, optional_offset + 84);
            number_of_rva_and_sizes = try readU32(bytes, optional_offset + fmt.opt32.number_of_rva_and_sizes_off);
        },
        fmt.coff.optional_magic_pe32_plus => {
            if (size_of_optional_header < fmt.opt64.minimum_size) return error.OptionalHeaderTruncated;
            optional_header_kind = .pe32_plus;
            entry_rva = try readU32(bytes, optional_offset + 16);
            image_base = try readU64(bytes, optional_offset + 24);
            section_alignment = try readU32(bytes, optional_offset + 32);
            file_alignment = try readU32(bytes, optional_offset + 36);
            size_of_image = try readU32(bytes, optional_offset + 56);
            size_of_headers = try readU32(bytes, optional_offset + 60);
            subsystem = try readU16(bytes, optional_offset + 68);
            dll_characteristics = try readU16(bytes, optional_offset + 70);
            size_of_stack_reserve = try readU64(bytes, optional_offset + 72);
            size_of_stack_commit = try readU64(bytes, optional_offset + 80);
            size_of_heap_reserve = try readU64(bytes, optional_offset + 88);
            size_of_heap_commit = try readU64(bytes, optional_offset + 96);
            number_of_rva_and_sizes = try readU32(bytes, optional_offset + fmt.opt64.number_of_rva_and_sizes_off);
        },
        else => return error.UnsupportedOptionalHeader,
    }

    if ((machine == fmt.coff.machine_i386 and optional_header_kind != .pe32) or
        (machine == fmt.coff.machine_amd64 and optional_header_kind != .pe32_plus))
    {
        return error.MachineFormatMismatch;
    }
    if (size_of_image == 0 or size_of_headers == 0 or section_alignment == 0 or file_alignment == 0 or
        @as(u64, size_of_headers) > bytes.len or size_of_headers > size_of_image)
    {
        return error.InvalidImageLayout;
    }

    const data_dir_offset: usize = if (optional_header_kind == .pe32)
        optional_offset + fmt.opt32.data_dir_off
    else
        optional_offset + fmt.opt64.data_dir_off;
    const directory_count: usize = @intCast(@min(number_of_rva_and_sizes, @as(u32, data_directory_count)));
    const directory_bytes = std.math.mul(usize, directory_count, 8) catch return error.OptionalHeaderTruncated;
    const optional_end = optional_offset + @as(usize, size_of_optional_header);
    if (data_dir_offset > optional_end or directory_bytes > optional_end - data_dir_offset) {
        return error.OptionalHeaderTruncated;
    }
    for (0..directory_count) |index| {
        const off = data_dir_offset + index * 8;
        data_directories[index] = .{
            .virtual_address = try readU32(bytes, off),
            .size = try readU32(bytes, off + 4),
        };
    }

    const section_table = optional_offset + @as(usize, size_of_optional_header);
    const section_table_bytes = std.math.mul(usize, @as(usize, number_of_sections), 40) catch return error.TruncatedSectionTable;
    if (section_table > bytes.len or section_table_bytes > bytes.len - section_table) {
        return error.TruncatedSectionTable;
    }

    const sections = try allocator.alloc(Section, number_of_sections);
    errdefer allocator.free(sections);

    for (sections, 0..) |*section, i| {
        const off = section_table + i * 40;
        @memcpy(section.name[0..8], bytes[off .. off + 8]);
        section.virtual_size = try readU32(bytes, off + 8);
        section.virtual_address = try readU32(bytes, off + 12);
        section.raw_size = try readU32(bytes, off + 16);
        section.raw_offset = try readU32(bytes, off + 20);
        section.characteristics = try readU32(bytes, off + 36);

        const mapped_size = section.mappedSize();
        const section_end = std.math.add(u32, section.virtual_address, mapped_size) catch return error.InvalidImageLayout;
        if (section.virtual_address >= size_of_image or section_end > size_of_image) {
            return error.InvalidImageLayout;
        }
        if (section.raw_size != 0) {
            const raw_offset: usize = @intCast(section.raw_offset);
            const raw_size: usize = @intCast(section.raw_size);
            if (raw_offset > bytes.len or raw_size > bytes.len - raw_offset) {
                return error.TruncatedSectionData;
            }
        }
    }

    return .{
        .pe_offset = pe_offset,
        .machine = machine,
        .coff_characteristics = try readU16(bytes, coff_offset + 18),
        .optional_header_kind = optional_header_kind,
        .optional_header_size = size_of_optional_header,
        .entry_rva = entry_rva,
        .image_base = image_base,
        .subsystem = subsystem,
        .dll_characteristics = dll_characteristics,
        .section_alignment = section_alignment,
        .file_alignment = file_alignment,
        .size_of_image = size_of_image,
        .size_of_headers = size_of_headers,
        .size_of_stack_reserve = size_of_stack_reserve,
        .size_of_stack_commit = size_of_stack_commit,
        .size_of_heap_reserve = size_of_heap_reserve,
        .size_of_heap_commit = size_of_heap_commit,
        .number_of_rva_and_sizes = number_of_rva_and_sizes,
        .data_directories = data_directories,
        .number_of_sections = number_of_sections,
        .sections = sections,
    };
}

test "parse minimal PE32 header" {
    var bytes = [_]u8{0} ** 0x600;
    std.mem.writeInt(u16, bytes[0x00..0x02], fmt.dos.signature, .little);
    std.mem.writeInt(u32, bytes[0x3C..0x40], 0x80, .little);
    std.mem.writeInt(u32, bytes[0x80..0x84], fmt.coff.signature, .little);
    std.mem.writeInt(u16, bytes[0x84..0x86], fmt.coff.machine_i386, .little);
    std.mem.writeInt(u16, bytes[0x86..0x88], 1, .little);
    std.mem.writeInt(u16, bytes[0x94..0x96], 0xE0, .little);
    std.mem.writeInt(u16, bytes[0x98..0x9A], fmt.coff.optional_magic_pe32, .little);
    std.mem.writeInt(u32, bytes[0xA8..0xAC], 0x1234, .little);
    std.mem.writeInt(u32, bytes[0xB4..0xB8], 0x400000, .little);
    std.mem.writeInt(u32, bytes[0xB8..0xBC], 0x1000, .little);
    std.mem.writeInt(u32, bytes[0xBC..0xC0], 0x200, .little);
    std.mem.writeInt(u32, bytes[0xD0..0xD4], 0x5000, .little);
    std.mem.writeInt(u32, bytes[0xD4..0xD8], 0x400, .little);
    std.mem.writeInt(u16, bytes[0xDC..0xDE], fmt.coff.subsystem_windows_gui, .little);
    @memcpy(bytes[0x178..0x180], &[_]u8{ '.', 't', 'e', 'x', 't', 0, 0, 0 });
    std.mem.writeInt(u32, bytes[0x180..0x184], 0x1000, .little);
    std.mem.writeInt(u32, bytes[0x184..0x188], 0x1000, .little);
    std.mem.writeInt(u32, bytes[0x188..0x18C], 0x200, .little);
    std.mem.writeInt(u32, bytes[0x18C..0x190], 0x400, .little);
    std.mem.writeInt(u32, bytes[0x19C..0x1A0], 0x60000020, .little);

    const image = try parse(std.testing.allocator, &bytes);
    defer std.testing.allocator.free(image.sections);

    try std.testing.expectEqual(@as(u16, fmt.coff.machine_i386), image.machine);
    try std.testing.expectEqual(@as(u32, 0x1234), image.entry_rva);
    try std.testing.expectEqual(@as(u16, fmt.coff.subsystem_windows_gui), image.subsystem);
    try std.testing.expectEqual(@as(u16, 1), image.number_of_sections);
}
