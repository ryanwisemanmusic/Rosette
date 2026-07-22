const std = @import("std");

// Header Offsets
const EI_MAG0: u8 = 0; // Offset 0
const EI_MAG1: u8 = 1; // Offset 1
const EI_MAG2: u8 = 2; // Offset 2
const EI_MAG3: u8 = 3; // Offset 3
const EI_CLASS: u8 = 4; // Offset 4
const EI_DATA: u8 = 5; // Offset 5

const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;
const EM_X86_64: u16 = 62;
const ET_EXEC: u16 = 2;

const PT_LOAD: u32 = 1;
const PAGE_SIZE: u64 = 4096;

const SHT_SYMTAB: u32 = 2;
const SHT_STRTAB: u32 = 3;
const SHT_RELA: u32 = 4;
const SHT_DYNSYM: u32 = 11;
pub const SHN_UNDEF: u16 = 0;

pub const Elf64_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const Elf64_Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

pub const Elf64_Shdr = extern struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u64,
    sh_addr: u64,
    sh_offset: u64,
    sh_size: u64,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u64,
    sh_entsize: u64,
};

pub const Elf64_Sym = extern struct {
    st_name: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
    st_value: u64,
    st_size: u64,
};

pub const Elf64_Rela = extern struct {
    r_offset: u64,
    r_info: u64,
    r_addend: i64,
};

pub const Symbol = struct {
    name: []const u8,
    value: u64,
    size: u64,
    section_index: u16,
};

pub const DynamicRelocation = struct {
    name: []const u8,
    offset: u64,
    rel_type: u32,
};

pub const LoadPlan = struct {
    mem_base: u64,
    image_low: u64,
    image_high: u64,
    heap_start: u64,
    entry: u64,
};

pub fn planExecutableLoad(mem_len: usize, elf_bytes: []const u8, stack_reserve: u64) !LoadPlan {
    const ehdr = try header(elf_bytes);
    try validateHeader(&ehdr);

    const phoff = ehdr.e_phoff;
    const phentsize = ehdr.e_phentsize;
    const phnum = ehdr.e_phnum;

    if (phoff == 0 or phentsize < @sizeOf(Elf64_Phdr) or phnum == 0) return error.NoProgramHeaders;
    if (phoff + phnum * phentsize > elf_bytes.len) return error.TruncatedProgramHeaders;

    var min_vaddr: u64 = std.math.maxInt(u64);
    var max_vaddr: u64 = 0;
    var saw_load = false;

    var i: u16 = 0;
    while (i < phnum) : (i += 1) {
        const phdr_off = phoff + i * phentsize;
        if (phdr_off + @sizeOf(Elf64_Phdr) > elf_bytes.len) return error.TruncatedProgramHeaders;
        const phdr = std.mem.bytesToValue(Elf64_Phdr, elf_bytes[phdr_off..][0..@sizeOf(Elf64_Phdr)]);
        if (phdr.p_type != PT_LOAD or phdr.p_memsz == 0) continue;
        if (phdr.p_offset + phdr.p_filesz > elf_bytes.len) return error.TruncatedSegment;

        const segment_high = std.math.add(u64, phdr.p_vaddr, phdr.p_memsz) catch return error.SegmentAddressOverflow;
        min_vaddr = @min(min_vaddr, phdr.p_vaddr);
        max_vaddr = @max(max_vaddr, segment_high);
        saw_load = true;
    }

    if (!saw_load) return error.NoLoadSegments;

    const mem_base = alignDown(min_vaddr, PAGE_SIZE);
    const image_high = alignUp(max_vaddr, PAGE_SIZE) catch return error.SegmentAddressOverflow;
    const required_span = image_high - mem_base;
    const mem_len_u64: u64 = @intCast(mem_len);
    const effective_stack_reserve = @min(stack_reserve, mem_len_u64 / 2);
    if (required_span > mem_len_u64 - effective_stack_reserve) return error.SegmentTooLarge;

    const heap_start = image_high;
    const heap_limit = std.math.add(u64, mem_base, mem_len_u64 - effective_stack_reserve) catch return error.SegmentAddressOverflow;
    if (heap_start > heap_limit) return error.SegmentTooLarge;

    return .{
        .mem_base = mem_base,
        .image_low = min_vaddr,
        .image_high = image_high,
        .heap_start = heap_start,
        .entry = ehdr.e_entry,
    };
}

pub fn loadExecutableSegments(mem_base: u64, mem: []u8, elf_bytes: []const u8) !u64 {
    const ehdr = try header(elf_bytes);
    try validateHeader(&ehdr);

    const phoff = ehdr.e_phoff;
    const phentsize = ehdr.e_phentsize;
    const phnum = ehdr.e_phnum;

    if (phoff == 0 or phentsize < @sizeOf(Elf64_Phdr) or phnum == 0) return error.NoProgramHeaders;
    if (phoff + phnum * phentsize > elf_bytes.len) return error.TruncatedProgramHeaders;

    var i: u16 = 0;
    while (i < phnum) : (i += 1) {
        const phdr_off = phoff + i * phentsize;
        if (phdr_off + @sizeOf(Elf64_Phdr) > elf_bytes.len) return error.TruncatedProgramHeaders;
        const phdr = std.mem.bytesToValue(Elf64_Phdr, elf_bytes[phdr_off..][0..@sizeOf(Elf64_Phdr)]);

        if (phdr.p_type != PT_LOAD) continue;
        if (phdr.p_memsz == 0) continue;

        if (phdr.p_offset + phdr.p_filesz > elf_bytes.len) return error.TruncatedSegment;

        const base_off = addrToOffset(mem_base, mem.len, phdr.p_vaddr) orelse return error.SegmentOutOfRange;
        if (base_off + phdr.p_memsz > mem.len) return error.SegmentTooLarge;

        @memcpy(mem[base_off..][0..@as(usize, @intCast(phdr.p_filesz))], elf_bytes[phdr.p_offset..][0..@as(usize, @intCast(phdr.p_filesz))]);
    }

    return ehdr.e_entry;
}

pub fn collectInitArray(allocator: std.mem.Allocator, elf_bytes: []const u8) !std.ArrayList(u64) {
    const ehdr = try header(elf_bytes);
    try validateHeader(&ehdr);
    if (ehdr.e_shoff == 0 or ehdr.e_shnum == 0) return .empty;
    if (ehdr.e_shentsize < @sizeOf(Elf64_Shdr)) return error.InvalidSectionHeaderSize;

    var functions: std.ArrayList(u64) = .empty;
    errdefer functions.deinit(allocator);

    try collectInitArraySection(allocator, elf_bytes, &ehdr, ".preinit_array", &functions);
    try collectInitArraySection(allocator, elf_bytes, &ehdr, ".init_array", &functions);
    try collectInitArraySection(allocator, elf_bytes, &ehdr, ".ctors", &functions);

    return functions;
}

pub fn collectSymbols(allocator: std.mem.Allocator, elf_bytes: []const u8) !std.ArrayList(Symbol) {
    const ehdr = try header(elf_bytes);
    if (ehdr.e_shoff == 0 or ehdr.e_shnum == 0) return .empty;
    if (ehdr.e_shentsize < @sizeOf(Elf64_Shdr)) return error.InvalidSectionHeaderSize;
    const section_table_size = @as(u64, ehdr.e_shentsize) * @as(u64, ehdr.e_shnum);
    if (ehdr.e_shoff > elf_bytes.len or section_table_size > elf_bytes.len - ehdr.e_shoff) return error.TruncatedSectionHeaders;

    var symbols: std.ArrayList(Symbol) = .empty;
    errdefer symbols.deinit(allocator);

    var section_index: u16 = 0;
    while (section_index < ehdr.e_shnum) : (section_index += 1) {
        const shdr = readSectionHeader(elf_bytes, &ehdr, section_index) orelse return error.TruncatedSectionHeaders;
        if (shdr.sh_type != SHT_SYMTAB) continue;
        if (shdr.sh_entsize < @sizeOf(Elf64_Sym) or shdr.sh_entsize == 0) continue;
        if (shdr.sh_link >= ehdr.e_shnum) continue;

        const strtab_shdr = readSectionHeader(elf_bytes, &ehdr, @intCast(shdr.sh_link)) orelse continue;
        const strtab = sectionBytes(elf_bytes, &strtab_shdr) orelse continue;
        const symtab = sectionBytes(elf_bytes, &shdr) orelse continue;
        const sym_count = shdr.sh_size / shdr.sh_entsize;

        var sym_index: u64 = 0;
        while (sym_index < sym_count) : (sym_index += 1) {
            const sym_offset = sym_index * shdr.sh_entsize;
            if (sym_offset + @sizeOf(Elf64_Sym) > symtab.len) break;
            const sym = std.mem.bytesToValue(Elf64_Sym, symtab[sym_offset..][0..@sizeOf(Elf64_Sym)]);
            if (sym.st_shndx == SHN_UNDEF or sym.st_value == 0) continue;

            const name = elfString(strtab, sym.st_name) orelse continue;
            try symbols.append(allocator, .{
                .name = name,
                .value = sym.st_value,
                .size = sym.st_size,
                .section_index = sym.st_shndx,
            });
        }
    }

    return symbols;
}

pub fn collectDynamicRelocations(allocator: std.mem.Allocator, elf_bytes: []const u8) !std.ArrayList(DynamicRelocation) {
    const ehdr = try header(elf_bytes);
    if (ehdr.e_shoff == 0 or ehdr.e_shnum == 0) return .empty;
    if (ehdr.e_shentsize < @sizeOf(Elf64_Shdr)) return error.InvalidSectionHeaderSize;

    var dynsym_shdr: ?Elf64_Shdr = null;
    var dynstr_shdr: ?Elf64_Shdr = null;
    var relocs: std.ArrayList(DynamicRelocation) = .empty;
    errdefer relocs.deinit(allocator);

    var section_index: u16 = 0;
    while (section_index < ehdr.e_shnum) : (section_index += 1) {
        const shdr = readSectionHeader(elf_bytes, &ehdr, section_index) orelse return error.TruncatedSectionHeaders;
        if (shdr.sh_type == SHT_DYNSYM) dynsym_shdr = shdr;
        if (shdr.sh_type == SHT_STRTAB) {
            if (sectionName(elf_bytes, &ehdr, section_index)) |name| {
                if (std.mem.eql(u8, name, ".dynstr")) dynstr_shdr = shdr;
            }
        }
    }

    const dynsym_header = dynsym_shdr orelse return relocs;
    const dynstr_header = dynstr_shdr orelse return relocs;
    const dynsym = sectionBytes(elf_bytes, &dynsym_header) orelse return relocs;
    const dynstr = sectionBytes(elf_bytes, &dynstr_header) orelse return relocs;

    section_index = 0;
    while (section_index < ehdr.e_shnum) : (section_index += 1) {
        const shdr = readSectionHeader(elf_bytes, &ehdr, section_index) orelse return error.TruncatedSectionHeaders;
        if (shdr.sh_type != SHT_RELA) continue;
        if (shdr.sh_entsize < @sizeOf(Elf64_Rela) or shdr.sh_entsize == 0) continue;
        const rela_bytes = sectionBytes(elf_bytes, &shdr) orelse continue;
        const rela_count = shdr.sh_size / shdr.sh_entsize;

        var rela_index: u64 = 0;
        while (rela_index < rela_count) : (rela_index += 1) {
            const rela_offset = rela_index * shdr.sh_entsize;
            if (rela_offset + @sizeOf(Elf64_Rela) > rela_bytes.len) break;
            const rela = std.mem.bytesToValue(Elf64_Rela, rela_bytes[rela_offset..][0..@sizeOf(Elf64_Rela)]);
            const sym_index = rela.r_info >> 32;
            const rel_type: u32 = @truncate(rela.r_info);
            const sym_offset = sym_index * @sizeOf(Elf64_Sym);
            if (sym_offset + @sizeOf(Elf64_Sym) > dynsym.len) continue;
            const sym = std.mem.bytesToValue(Elf64_Sym, dynsym[sym_offset..][0..@sizeOf(Elf64_Sym)]);
            const name = elfString(dynstr, sym.st_name) orelse continue;
            if (name.len == 0) continue;
            try relocs.append(allocator, .{
                .name = name,
                .offset = rela.r_offset,
                .rel_type = rel_type,
            });
        }
    }

    return relocs;
}

fn collectInitArraySection(
    allocator: std.mem.Allocator,
    elf_bytes: []const u8,
    ehdr: *const Elf64_Ehdr,
    wanted_name: []const u8,
    functions: *std.ArrayList(u64),
) !void {
    var section_index: u16 = 0;
    while (section_index < ehdr.e_shnum) : (section_index += 1) {
        const shdr = readSectionHeader(elf_bytes, ehdr, section_index) orelse return error.TruncatedSectionHeaders;
        const name = sectionName(elf_bytes, ehdr, section_index) orelse continue;
        if (!std.mem.eql(u8, name, wanted_name)) continue;
        if (shdr.sh_entsize != 0 and shdr.sh_entsize < @sizeOf(u64)) return error.InvalidInitArrayEntry;
        if ((shdr.sh_size % @sizeOf(u64)) != 0) return error.InvalidInitArrayEntry;

        const bytes = sectionBytes(elf_bytes, &shdr) orelse return error.TruncatedSection;
        var off: usize = 0;
        while (off + @sizeOf(u64) <= bytes.len) : (off += @sizeOf(u64)) {
            const fn_addr = std.mem.readInt(u64, bytes[off..][0..@sizeOf(u64)], .little);
            if (fn_addr == 0) continue;
            try functions.append(allocator, fn_addr);
        }
    }
}

fn header(elf_bytes: []const u8) !Elf64_Ehdr {
    if (elf_bytes.len < @sizeOf(Elf64_Ehdr)) return error.InvalidElf;
    return std.mem.bytesToValue(Elf64_Ehdr, elf_bytes[0..@sizeOf(Elf64_Ehdr)]);
}

fn validateHeader(ehdr: *const Elf64_Ehdr) !void {
    if (ehdr.e_ident[EI_MAG0] != 0x7f or
        ehdr.e_ident[EI_MAG1] != 'E' or
        ehdr.e_ident[EI_MAG2] != 'L' or
        ehdr.e_ident[EI_MAG3] != 'F') return error.NotElf;
    if (ehdr.e_ident[EI_CLASS] != ELFCLASS64) return error.Not64Bit;
    if (ehdr.e_ident[EI_DATA] != ELFDATA2LSB) return error.NotLittleEndian;
    if (ehdr.e_machine != EM_X86_64) return error.NotX86_64;
    if (ehdr.e_type != ET_EXEC) return error.NotExecutable;
}

fn readSectionHeader(elf_bytes: []const u8, ehdr: *const Elf64_Ehdr, index: u16) ?Elf64_Shdr {
    const offset = ehdr.e_shoff + @as(u64, index) * ehdr.e_shentsize;
    if (offset + @sizeOf(Elf64_Shdr) > elf_bytes.len) return null;
    return std.mem.bytesToValue(Elf64_Shdr, elf_bytes[offset..][0..@sizeOf(Elf64_Shdr)]);
}

fn sectionBytes(elf_bytes: []const u8, shdr: *const Elf64_Shdr) ?[]const u8 {
    if (shdr.sh_offset > elf_bytes.len) return null;
    if (shdr.sh_size > elf_bytes.len - shdr.sh_offset) return null;
    return elf_bytes[shdr.sh_offset..][0..@intCast(shdr.sh_size)];
}

fn sectionName(elf_bytes: []const u8, ehdr: *const Elf64_Ehdr, index: u16) ?[]const u8 {
    if (ehdr.e_shstrndx == SHN_UNDEF or ehdr.e_shstrndx >= ehdr.e_shnum) return null;
    const shdr = readSectionHeader(elf_bytes, ehdr, index) orelse return null;
    const shstr = readSectionHeader(elf_bytes, ehdr, ehdr.e_shstrndx) orelse return null;
    const names = sectionBytes(elf_bytes, &shstr) orelse return null;
    return elfString(names, shdr.sh_name);
}

fn elfString(strtab: []const u8, offset: u32) ?[]const u8 {
    if (offset >= strtab.len) return null;
    const rest = strtab[offset..];
    const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
    return rest[0..len];
}

fn addrToOffset(mem_base: u64, mem_len: usize, vaddr: u64) ?u64 {
    if (vaddr < mem_base) return null;
    const off = vaddr - mem_base;
    if (off >= mem_len) return null;
    return off;
}

fn alignDown(value: u64, alignment: u64) u64 {
    return value & ~(alignment - 1);
}

fn alignUp(value: u64, alignment: u64) !u64 {
    const mask = alignment - 1;
    return (try std.math.add(u64, value, mask)) & ~mask;
}
