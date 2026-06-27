const std = @import("std");
const macho = @import("macho.zig");

const LC_DYLD_INFO_ONLY: u32 = 0x22 | 0x8000_0000;
const LC_LOAD_WEAK_DYLIB: u32 = 0x18 | 0x8000_0000;
const LC_LAZY_LOAD_DYLIB: u32 = 0x20;

const INDIRECT_SYMBOL_LOCAL: u32 = 0x8000_0000;
const INDIRECT_SYMBOL_ABS: u32 = 0x4000_0000;
const N_STAB: u8 = 0xe0;
const N_TYPE: u8 = 0x0e;
const N_SECT: u8 = 0x0e;

const MACH_HEADER_64_SIZE: usize = 32;
const SEGMENT_COMMAND_64_SIZE: usize = 72;
const SECTION_64_SIZE: usize = 80;
const NLIST_64_SIZE: usize = 16;

pub const Section = struct {
    name: []const u8,
    segment_name: []const u8,
    address: u64,
    size: u64,
    file_offset: u32,
    flags: u32,
    indirect_symbol_start: u32,
    stub_size: u32,
};

pub const ImportedSymbol = struct {
    name: []const u8,
    dylib: []const u8,
    stub_address: u64,
    lazy_pointer_address: u64,
    symbol_index: u32,
};

pub const SymbolMatch = struct {
    name: []const u8,
    address: u64,
    offset: u64,
};

const Symtab = struct {
    symbol_offset: u32,
    symbol_count: u32,
    string_offset: u32,
    string_size: u32,
};

const Dysymtab = struct {
    indirect_symbol_offset: u32,
    indirect_symbol_count: u32,
};

pub const Metadata = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    sections: []Section,
    dylibs: [][]const u8,
    imports: []ImportedSymbol,
    initializer_count: usize,
    symtab: ?Symtab,
    dysymtab: ?Dysymtab,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !Metadata {
        if (data.len < MACH_HEADER_64_SIZE) return error.TruncatedMachO;
        if (readU32(data, 0) != macho.MH_MAGIC_64) return error.UnsupportedMachOEndian;

        var sections: std.ArrayList(Section) = .empty;
        errdefer sections.deinit(allocator);
        var dylibs: std.ArrayList([]const u8) = .empty;
        errdefer dylibs.deinit(allocator);

        var symtab: ?Symtab = null;
        var dysymtab: ?Dysymtab = null;
        var initializer_count: usize = 0;
        const command_count = readU32(data, 16);
        const command_bytes = readU32(data, 20);
        const command_end = @min(data.len, MACH_HEADER_64_SIZE + @as(usize, command_bytes));
        var command_offset: usize = MACH_HEADER_64_SIZE;

        var command_index: u32 = 0;
        while (command_index < command_count and command_offset + 8 <= command_end) : (command_index += 1) {
            const command = readU32(data, command_offset);
            const command_size = readU32(data, command_offset + 4);
            if (command_size < 8 or command_offset + command_size > command_end) break;

            switch (command) {
                macho.LC_SEGMENT_64 => {
                    if (command_size >= SEGMENT_COMMAND_64_SIZE) {
                        const section_count = readU32(data, command_offset + 64);
                        var section_offset = command_offset + SEGMENT_COMMAND_64_SIZE;
                        var section_index: u32 = 0;
                        while (section_index < section_count and section_offset + SECTION_64_SIZE <= command_offset + command_size) : (section_index += 1) {
                            const section = Section{
                                .name = fixedName(data[section_offset..][0..16]),
                                .segment_name = fixedName(data[section_offset + 16 ..][0..16]),
                                .address = readU64(data, section_offset + 32),
                                .size = readU64(data, section_offset + 40),
                                .file_offset = readU32(data, section_offset + 48),
                                .flags = readU32(data, section_offset + 64),
                                .indirect_symbol_start = readU32(data, section_offset + 68),
                                .stub_size = readU32(data, section_offset + 72),
                            };
                            if (std.mem.eql(u8, section.name, "__mod_init_func")) {
                                initializer_count += @intCast(section.size / @sizeOf(u64));
                            }
                            try sections.append(allocator, section);
                            section_offset += SECTION_64_SIZE;
                        }
                    }
                },
                macho.LC_SYMTAB => {
                    if (command_size >= 24) {
                        symtab = .{
                            .symbol_offset = readU32(data, command_offset + 8),
                            .symbol_count = readU32(data, command_offset + 12),
                            .string_offset = readU32(data, command_offset + 16),
                            .string_size = readU32(data, command_offset + 20),
                        };
                    }
                },
                macho.LC_DYSYMTAB => {
                    if (command_size >= 64) {
                        dysymtab = .{
                            .indirect_symbol_offset = readU32(data, command_offset + 56),
                            .indirect_symbol_count = readU32(data, command_offset + 60),
                        };
                    }
                },
                macho.LC_LOAD_DYLIB,
                macho.LC_LOAD_UPWARD_DYLIB,
                macho.LC_REEXPORT_DYLIB,
                LC_LOAD_WEAK_DYLIB,
                LC_LAZY_LOAD_DYLIB,
                => {
                    if (command_size >= 24) {
                        const name_offset = readU32(data, command_offset + 8);
                        if (name_offset < command_size) {
                            try dylibs.append(allocator, terminatedString(data, command_offset + name_offset, command_offset + command_size));
                        }
                    }
                },
                LC_DYLD_INFO_ONLY => {},
                else => {},
            }
            command_offset += command_size;
        }

        var metadata = Metadata{
            .allocator = allocator,
            .data = data,
            .sections = try sections.toOwnedSlice(allocator),
            .dylibs = try dylibs.toOwnedSlice(allocator),
            .imports = &.{},
            .initializer_count = initializer_count,
            .symtab = symtab,
            .dysymtab = dysymtab,
        };
        errdefer metadata.deinit();
        metadata.imports = try metadata.collectImports();
        return metadata;
    }

    pub fn deinit(self: *Metadata) void {
        self.allocator.free(self.sections);
        self.allocator.free(self.dylibs);
        if (self.imports.len != 0) self.allocator.free(self.imports);
        self.* = undefined;
    }

    pub fn importAtStub(self: *const Metadata, address: u64) ?ImportedSymbol {
        for (self.imports) |imported| {
            if (imported.stub_address == address) return imported;
        }
        return null;
    }

    pub fn nearestSymbol(self: *const Metadata, address: u64) ?SymbolMatch {
        const table = self.symtab orelse return null;
        var best_name: []const u8 = "";
        var best_address: u64 = 0;
        var index: u32 = 0;
        while (index < table.symbol_count) : (index += 1) {
            const entry_offset = @as(usize, table.symbol_offset) + @as(usize, index) * NLIST_64_SIZE;
            if (entry_offset + NLIST_64_SIZE > self.data.len) break;
            const symbol_type = self.data[entry_offset + 4];
            if ((symbol_type & N_STAB) != 0 or (symbol_type & N_TYPE) != N_SECT) continue;
            const value = readU64(self.data, entry_offset + 8);
            if (value == 0 or value > address or value < best_address) continue;
            const name = self.symbolName(table, readU32(self.data, entry_offset)) orelse continue;
            if (name.len == 0) continue;
            best_name = name;
            best_address = value;
            if (value == address) break;
        }
        if (best_name.len == 0) return null;
        return .{
            .name = best_name,
            .address = best_address,
            .offset = address - best_address,
        };
    }

    fn collectImports(self: *const Metadata) ![]ImportedSymbol {
        const table = self.symtab orelse return &.{};
        const dynamic = self.dysymtab orelse return &.{};
        var imports: std.ArrayList(ImportedSymbol) = .empty;
        errdefer imports.deinit(self.allocator);

        for (self.sections) |section| {
            if (!std.mem.eql(u8, section.name, "__stubs") or section.stub_size == 0) continue;
            const stub_count = section.size / section.stub_size;
            var stub_index: u64 = 0;
            while (stub_index < stub_count) : (stub_index += 1) {
                const indirect_index = @as(u64, section.indirect_symbol_start) + stub_index;
                if (indirect_index >= dynamic.indirect_symbol_count) break;
                const indirect_offset = @as(u64, dynamic.indirect_symbol_offset) + indirect_index * @sizeOf(u32);
                if (indirect_offset + @sizeOf(u32) > self.data.len) break;
                const symbol_index = readU32(self.data, @intCast(indirect_offset));
                if ((symbol_index & (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) != 0) continue;
                if (symbol_index >= table.symbol_count) continue;
                const symbol_offset = @as(usize, table.symbol_offset) + @as(usize, symbol_index) * NLIST_64_SIZE;
                if (symbol_offset + NLIST_64_SIZE > self.data.len) continue;
                const name = self.symbolName(table, readU32(self.data, symbol_offset)) orelse continue;
                const description = readU16(self.data, symbol_offset + 6);
                const ordinal: u8 = @intCast(description >> 8);
                try imports.append(self.allocator, .{
                    .name = name,
                    .dylib = self.dylibForOrdinal(ordinal),
                    .stub_address = section.address + stub_index * section.stub_size,
                    .lazy_pointer_address = 0,
                    .symbol_index = symbol_index,
                });
            }
        }
        return imports.toOwnedSlice(self.allocator);
    }

    fn symbolName(self: *const Metadata, table: Symtab, string_index: u32) ?[]const u8 {
        if (string_index >= table.string_size) return null;
        const start = @as(usize, table.string_offset) + string_index;
        const end = @min(self.data.len, @as(usize, table.string_offset) + table.string_size);
        if (start >= end) return null;
        return terminatedString(self.data, start, end);
    }

    fn dylibForOrdinal(self: *const Metadata, ordinal: u8) []const u8 {
        if (ordinal >= 1 and ordinal <= self.dylibs.len) return self.dylibs[ordinal - 1];
        return switch (ordinal) {
            0 => "self",
            0xfd => "flat-namespace",
            0xfe => "main-executable",
            0xff => "weak-lookup",
            else => "unknown-dylib",
        };
    }
};

fn fixedName(bytes: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    return bytes[0..end];
}

fn terminatedString(data: []const u8, start: usize, limit: usize) []const u8 {
    if (start >= data.len or start >= limit) return "";
    const bounded_end = @min(data.len, limit);
    const bytes = data[start..bounded_end];
    const length = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    return bytes[0..length];
}

fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn readU32(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

fn readU64(data: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, data[offset..][0..8], .little);
}

test "metadata maps indirect stubs to imported symbols" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** 512;
    std.mem.writeInt(u32, data[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, data[16..20], 3, .little);
    std.mem.writeInt(u32, data[20..24], 72 + 80 + 24 + 80, .little);

    var offset: usize = MACH_HEADER_64_SIZE;
    std.mem.writeInt(u32, data[offset..][0..4], macho.LC_SEGMENT_64, .little);
    std.mem.writeInt(u32, data[offset + 4 ..][0..4], 72 + 80, .little);
    std.mem.writeInt(u32, data[offset + 64 ..][0..4], 1, .little);
    offset += 72;
    @memcpy(data[offset..][0..7], "__stubs");
    std.mem.writeInt(u64, data[offset + 32 ..][0..8], 0x1000, .little);
    std.mem.writeInt(u64, data[offset + 40 ..][0..8], 6, .little);
    std.mem.writeInt(u32, data[offset + 68 ..][0..4], 0, .little);
    std.mem.writeInt(u32, data[offset + 72 ..][0..4], 6, .little);

    offset = MACH_HEADER_64_SIZE + 72 + 80;
    std.mem.writeInt(u32, data[offset..][0..4], macho.LC_SYMTAB, .little);
    std.mem.writeInt(u32, data[offset + 4 ..][0..4], 24, .little);
    std.mem.writeInt(u32, data[offset + 8 ..][0..4], 320, .little);
    std.mem.writeInt(u32, data[offset + 12 ..][0..4], 1, .little);
    std.mem.writeInt(u32, data[offset + 16 ..][0..4], 352, .little);
    std.mem.writeInt(u32, data[offset + 20 ..][0..4], 32, .little);

    offset += 24;
    std.mem.writeInt(u32, data[offset..][0..4], macho.LC_DYSYMTAB, .little);
    std.mem.writeInt(u32, data[offset + 4 ..][0..4], 80, .little);
    std.mem.writeInt(u32, data[offset + 56 ..][0..4], 384, .little);
    std.mem.writeInt(u32, data[offset + 60 ..][0..4], 1, .little);

    std.mem.writeInt(u32, data[320..324], 1, .little);
    data[326] = 0;
    data[327] = 0;
    @memcpy(data[353..][0..11], "_test_call\x00");
    std.mem.writeInt(u32, data[384..388], 0, .little);

    var metadata = try Metadata.init(allocator, &data);
    defer metadata.deinit();
    try std.testing.expectEqual(@as(usize, 1), metadata.imports.len);
    try std.testing.expectEqualStrings("_test_call", metadata.imports[0].name);
    try std.testing.expectEqual(@as(u64, 0x1000), metadata.imports[0].stub_address);
}
