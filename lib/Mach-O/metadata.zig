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
const N_WEAK_REF: u16 = 0x0040;

const MACH_HEADER_64_SIZE: usize = 32;
const SEGMENT_COMMAND_64_SIZE: usize = 72;
const SECTION_64_SIZE: usize = 80;
const NLIST_64_SIZE: usize = 16;
const POINTER_SIZE: u64 = @sizeOf(u64);

const BIND_OPCODE_MASK: u8 = 0xF0;
const BIND_IMMEDIATE_MASK: u8 = 0x0F;
const BIND_TYPE_POINTER: u8 = 1;

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
    weak: bool = false,
};

pub const DataBinding = struct {
    address: u64,
    name: []const u8,
    dylib: []const u8,
    addend: i64,
};

pub const SymbolMatch = struct {
    name: []const u8,
    address: u64,
    offset: u64,
};

const AddressedSymbol = struct {
    name: []const u8,
    address: u64,
    original_index: u32,
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

const DyldInfo = struct {
    bind_offset: u32,
    bind_size: u32,
    weak_bind_offset: u32,
    weak_bind_size: u32,
    lazy_bind_offset: u32,
    lazy_bind_size: u32,
};

pub const Metadata = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    sections: []Section,
    segment_addresses: []u64,
    dylibs: [][]const u8,
    imports: []ImportedSymbol,
    bindings: []DataBinding,
    initializer_count: usize,
    initializer_addresses: []u64,
    addressed_symbols: []AddressedSymbol,
    symtab: ?Symtab,
    dysymtab: ?Dysymtab,
    dyld_info: ?DyldInfo,
    defined_symbols: std.StringHashMap(u64),

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !Metadata {
        if (data.len < MACH_HEADER_64_SIZE) return error.TruncatedMachO;
        if (readU32(data, 0) != macho.MH_MAGIC_64) return error.UnsupportedMachOEndian;

        var sections: std.ArrayList(Section) = .empty;
        errdefer sections.deinit(allocator);
        var dylibs: std.ArrayList([]const u8) = .empty;
        errdefer dylibs.deinit(allocator);
        var segment_addresses: std.ArrayList(u64) = .empty;
        errdefer segment_addresses.deinit(allocator);

        var symtab: ?Symtab = null;
        var dysymtab: ?Dysymtab = null;
        var dyld_info: ?DyldInfo = null;
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
                        try segment_addresses.append(allocator, readU64(data, command_offset + 24));
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
                LC_DYLD_INFO_ONLY => {
                    if (command_size >= 48) {
                        dyld_info = .{
                            .bind_offset = readU32(data, command_offset + 16),
                            .bind_size = readU32(data, command_offset + 20),
                            .weak_bind_offset = readU32(data, command_offset + 24),
                            .weak_bind_size = readU32(data, command_offset + 28),
                            .lazy_bind_offset = readU32(data, command_offset + 32),
                            .lazy_bind_size = readU32(data, command_offset + 36),
                        };
                    }
                },
                else => {},
            }
            command_offset += command_size;
        }

        var metadata = Metadata{
            .allocator = allocator,
            .data = data,
            .sections = try sections.toOwnedSlice(allocator),
            .segment_addresses = try segment_addresses.toOwnedSlice(allocator),
            .dylibs = try dylibs.toOwnedSlice(allocator),
            .imports = &.{},
            .bindings = &.{},
            .initializer_count = initializer_count,
            .initializer_addresses = &.{},
            .addressed_symbols = &.{},
            .symtab = symtab,
            .dysymtab = dysymtab,
            .dyld_info = dyld_info,
            .defined_symbols = std.StringHashMap(u64).init(allocator),
        };
        errdefer metadata.deinit();
        try metadata.indexDefinedSymbols();
        metadata.imports = try metadata.collectImports();
        metadata.bindings = try metadata.collectBindings();
        metadata.initializer_addresses = try metadata.collectInitializers();
        return metadata;
    }

    pub fn deinit(self: *Metadata) void {
        self.allocator.free(self.sections);
        self.allocator.free(self.segment_addresses);
        self.allocator.free(self.dylibs);
        if (self.imports.len != 0) self.allocator.free(self.imports);
        if (self.bindings.len != 0) self.allocator.free(self.bindings);
        if (self.initializer_addresses.len != 0) self.allocator.free(self.initializer_addresses);
        if (self.addressed_symbols.len != 0) self.allocator.free(self.addressed_symbols);
        self.defined_symbols.deinit();
        self.* = undefined;
    }

    pub fn importAtStub(self: *const Metadata, address: u64) ?ImportedSymbol {
        var low: usize = 0;
        var high: usize = self.imports.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const imported = self.imports[middle];
            if (address < imported.stub_address) {
                high = middle;
            } else if (address > imported.stub_address) {
                low = middle + 1;
            } else {
                return imported;
            }
        }
        return null;
    }

    pub fn sectionAtAddress(self: *const Metadata, address: u64) ?Section {
        for (self.sections) |section| {
            if (address >= section.address and address - section.address < section.size) {
                return section;
            }
        }
        return null;
    }

    pub fn nearestSymbol(self: *const Metadata, address: u64) ?SymbolMatch {
        var low: usize = 0;
        var high: usize = self.addressed_symbols.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.addressed_symbols[middle].address <= address) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if (low == 0) return null;
        var best_index = low - 1;
        const best_address = self.addressed_symbols[best_index].address;
        // Preserve the old symbol-table behavior for aliases at the same
        // address by selecting the first original symbol-table entry.
        while (best_index != 0 and self.addressed_symbols[best_index - 1].address == best_address) {
            best_index -= 1;
        }
        const best = self.addressed_symbols[best_index];
        return .{
            .name = best.name,
            .address = best.address,
            .offset = address - best.address,
        };
    }

    pub fn symbolAddressWithPrefix(self: *const Metadata, prefix: []const u8) ?u64 {
        const table = self.symtab orelse return null;
        var index: u32 = 0;
        while (index < table.symbol_count) : (index += 1) {
            const entry_offset = @as(usize, table.symbol_offset) + @as(usize, index) * NLIST_64_SIZE;
            if (entry_offset + NLIST_64_SIZE > self.data.len) break;
            const symbol_type = self.data[entry_offset + 4];
            if ((symbol_type & N_STAB) != 0 or (symbol_type & N_TYPE) != N_SECT) continue;
            const name = self.symbolName(table, readU32(self.data, entry_offset)) orelse continue;
            if (!std.mem.startsWith(u8, name, prefix)) continue;
            const address = readU64(self.data, entry_offset + 8);
            if (address != 0) return address;
        }
        return null;
    }

    pub fn definedSymbolAddress(self: *const Metadata, expected_name: []const u8) ?u64 {
        return self.defined_symbols.get(expected_name);
    }

    pub fn definedSymbolIterator(self: *const Metadata) std.StringHashMap(u64).Iterator {
        return self.defined_symbols.iterator();
    }

    fn indexDefinedSymbols(self: *Metadata) !void {
        const table = self.symtab orelse return;
        var addressed: std.ArrayList(AddressedSymbol) = .empty;
        errdefer addressed.deinit(self.allocator);
        var index: u32 = 0;
        while (index < table.symbol_count) : (index += 1) {
            const entry_offset = @as(usize, table.symbol_offset) + @as(usize, index) * NLIST_64_SIZE;
            if (entry_offset + NLIST_64_SIZE > self.data.len) break;
            const symbol_type = self.data[entry_offset + 4];
            if ((symbol_type & N_STAB) != 0 or (symbol_type & N_TYPE) != N_SECT) continue;
            const name = self.symbolName(table, readU32(self.data, entry_offset)) orelse continue;
            const address = readU64(self.data, entry_offset + 8);
            if (address != 0) {
                try self.defined_symbols.put(name, address);
                try addressed.append(self.allocator, .{
                    .name = name,
                    .address = address,
                    .original_index = index,
                });
            }
        }
        self.addressed_symbols = try addressed.toOwnedSlice(self.allocator);
        std.mem.sort(AddressedSymbol, self.addressed_symbols, {}, struct {
            fn lessThan(_: void, lhs: AddressedSymbol, rhs: AddressedSymbol) bool {
                if (lhs.address != rhs.address) return lhs.address < rhs.address;
                return lhs.original_index < rhs.original_index;
            }
        }.lessThan);
    }

    pub fn symbolAddressesMatching(
        self: *const Metadata,
        prefix: []const u8,
        fragment: []const u8,
        output: []u64,
    ) usize {
        const table = self.symtab orelse return 0;
        var found: usize = 0;
        var index: u32 = 0;
        while (index < table.symbol_count and found < output.len) : (index += 1) {
            const entry_offset = @as(usize, table.symbol_offset) + @as(usize, index) * NLIST_64_SIZE;
            if (entry_offset + NLIST_64_SIZE > self.data.len) break;
            const symbol_type = self.data[entry_offset + 4];
            if ((symbol_type & N_STAB) != 0 or (symbol_type & N_TYPE) != N_SECT) continue;
            const name = self.symbolName(table, readU32(self.data, entry_offset)) orelse continue;
            if (!std.mem.startsWith(u8, name, prefix) or std.mem.indexOf(u8, name, fragment) == null) continue;
            const address = readU64(self.data, entry_offset + 8);
            if (address == 0) continue;
            output[found] = address;
            found += 1;
        }
        return found;
    }

    pub fn sectionNamed(self: *const Metadata, segment_name: []const u8, section_name: []const u8) ?Section {
        for (self.sections) |section| {
            if (std.mem.eql(u8, section.segment_name, segment_name) and
                std.mem.eql(u8, section.name, section_name)) return section;
        }
        return null;
    }

    pub fn sectionBytes(self: *const Metadata, section: Section) ?[]const u8 {
        const start: usize = @intCast(section.file_offset);
        const size: usize = @intCast(section.size);
        if (start > self.data.len or size > self.data.len - start) return null;
        return self.data[start .. start + size];
    }

    pub fn imageBase(self: *const Metadata) u64 {
        var base: u64 = std.math.maxInt(u64);
        for (self.segment_addresses) |address| base = @min(base, address);
        return if (base == std.math.maxInt(u64)) 0 else base;
    }

    fn collectImports(self: *const Metadata) ![]ImportedSymbol {
        const table = self.symtab orelse return &.{};
        const dynamic = self.dysymtab orelse return &.{};
        var imports: std.ArrayList(ImportedSymbol) = .empty;
        errdefer imports.deinit(self.allocator);

        // Find __la_symbol_ptr section for lazy pointer address resolution
        const la_sym_ptr = for (self.sections) |s| {
            if (std.mem.eql(u8, s.name, "__la_symbol_ptr")) break &s;
        } else null;

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

                // Resolve lazy pointer address from __la_symbol_ptr section if available
                const lazy_ptr_addr = if (la_sym_ptr) |lap| blk: {
                    const ptr_index = indirect_index -| lap.indirect_symbol_start;
                    if (ptr_index < lap.size / 8) break :blk lap.address + ptr_index * 8;
                    break :blk 0;
                } else 0;

                try imports.append(self.allocator, .{
                    .name = name,
                    .dylib = self.dylibForOrdinal(ordinal),
                    .stub_address = section.address + stub_index * section.stub_size,
                    .lazy_pointer_address = lazy_ptr_addr,
                    .symbol_index = symbol_index,
                    .weak = isWeakReference(description),
                });
            }
        }
        const result = try imports.toOwnedSlice(self.allocator);
        std.mem.sort(ImportedSymbol, result, {}, struct {
            fn lessThan(_: void, lhs: ImportedSymbol, rhs: ImportedSymbol) bool {
                return lhs.stub_address < rhs.stub_address;
            }
        }.lessThan);
        return result;
    }

    fn collectBindings(self: *const Metadata) ![]DataBinding {
        const info = self.dyld_info orelse return &.{};
        var bindings: std.ArrayList(DataBinding) = .empty;
        errdefer bindings.deinit(self.allocator);

        try self.collectBindingStream(&bindings, info.bind_offset, info.bind_size, false, 0);
        try self.collectBindingStream(&bindings, info.weak_bind_offset, info.weak_bind_size, false, 0xFF);
        return bindings.toOwnedSlice(self.allocator);
    }

    fn collectInitializers(self: *const Metadata) ![]u64 {
        var initializers: std.ArrayList(u64) = .empty;
        errdefer initializers.deinit(self.allocator);

        for (self.sections) |section| {
            if (!std.mem.eql(u8, section.name, "__mod_init_func")) continue;
            const count = section.size / POINTER_SIZE;
            var index: u64 = 0;
            while (index < count) : (index += 1) {
                const file_offset = @as(u64, section.file_offset) + index * POINTER_SIZE;
                if (file_offset > self.data.len) break;
                const offset: usize = @intCast(file_offset);
                if (self.data.len - offset < @sizeOf(u64)) break;
                const address = readU64(self.data, offset);
                if (address != 0) try initializers.append(self.allocator, address);
            }
        }
        return initializers.toOwnedSlice(self.allocator);
    }

    fn collectBindingStream(
        self: *const Metadata,
        bindings: *std.ArrayList(DataBinding),
        stream_offset: u32,
        stream_size: u32,
        lazy: bool,
        default_ordinal: u8,
    ) !void {
        if (stream_size == 0) return;
        const start: usize = stream_offset;
        const size: usize = stream_size;
        if (start > self.data.len or size > self.data.len - start) return;
        const stream = self.data[start .. start + size];

        var position: usize = 0;
        var segment_index: usize = 0;
        var address: u64 = 0;
        var symbol: []const u8 = "";
        var ordinal = default_ordinal;
        var bind_type: u8 = BIND_TYPE_POINTER;
        var addend: i64 = 0;

        while (position < stream.len) {
            const byte = stream[position];
            position += 1;
            const opcode = byte & BIND_OPCODE_MASK;
            const immediate = byte & BIND_IMMEDIATE_MASK;

            switch (opcode) {
                0x00 => {
                    if (!lazy) break;
                    segment_index = 0;
                    address = 0;
                    symbol = "";
                    ordinal = default_ordinal;
                    bind_type = BIND_TYPE_POINTER;
                    addend = 0;
                },
                0x10 => ordinal = immediate,
                0x20 => ordinal = @truncate(readUleb(stream, &position) orelse return),
                0x30 => ordinal = if (immediate == 0) 0 else immediate | 0xF0,
                0x40 => {
                    const symbol_start = position;
                    const symbol_length = std.mem.indexOfScalar(u8, stream[symbol_start..], 0) orelse return;
                    symbol = stream[symbol_start .. symbol_start + symbol_length];
                    position = symbol_start + symbol_length + 1;
                },
                0x50 => bind_type = immediate,
                0x60 => addend = readSleb(stream, &position) orelse return,
                0x70 => {
                    segment_index = immediate;
                    const offset = readUleb(stream, &position) orelse return;
                    if (segment_index >= self.segment_addresses.len) return;
                    address = self.segment_addresses[segment_index] +% offset;
                },
                0x80 => address +%= readUleb(stream, &position) orelse return,
                0x90 => {
                    try self.appendBinding(bindings, address, symbol, ordinal, bind_type, addend);
                    address +%= POINTER_SIZE;
                },
                0xA0 => {
                    try self.appendBinding(bindings, address, symbol, ordinal, bind_type, addend);
                    address +%= POINTER_SIZE +% (readUleb(stream, &position) orelse return);
                },
                0xB0 => {
                    try self.appendBinding(bindings, address, symbol, ordinal, bind_type, addend);
                    address +%= POINTER_SIZE +% @as(u64, immediate) * POINTER_SIZE;
                },
                0xC0 => {
                    const count = readUleb(stream, &position) orelse return;
                    const skip = readUleb(stream, &position) orelse return;
                    var index: u64 = 0;
                    while (index < count) : (index += 1) {
                        try self.appendBinding(bindings, address, symbol, ordinal, bind_type, addend);
                        address +%= POINTER_SIZE +% skip;
                    }
                },
                else => return,
            }
        }
    }

    fn appendBinding(
        self: *const Metadata,
        bindings: *std.ArrayList(DataBinding),
        address: u64,
        symbol: []const u8,
        ordinal: u8,
        bind_type: u8,
        addend: i64,
    ) !void {
        if (bind_type != BIND_TYPE_POINTER or symbol.len == 0 or address == 0) return;
        try bindings.append(self.allocator, .{
            .address = address,
            .name = symbol,
            .dylib = self.dylibForOrdinal(ordinal),
            .addend = addend,
        });
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

fn isWeakReference(description: u16) bool {
    return description & N_WEAK_REF != 0;
}

test "Mach-O weak references use the n_desc N_WEAK_REF bit" {
    try std.testing.expect(isWeakReference(0x0040));
    try std.testing.expect(isWeakReference(0x0240));
    try std.testing.expect(!isWeakReference(0x0200));
}

fn readU32(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

fn readU64(data: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, data[offset..][0..8], .little);
}

fn readUleb(data: []const u8, position: *usize) ?u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    while (position.* < data.len) {
        const byte = data[position.*];
        position.* += 1;
        const payload = byte & 0x7F;
        if (shift >= 63 and payload > 1) return null;
        result |= @as(u64, payload) << shift;
        if (byte & 0x80 == 0) return result;
        if (shift > 56) return null;
        shift += 7;
    }
    return null;
}

fn readSleb(data: []const u8, position: *usize) ?i64 {
    var result: u64 = 0;
    var shift: u7 = 0;
    var byte: u8 = 0;
    while (position.* < data.len) {
        byte = data[position.*];
        position.* += 1;
        const payload = byte & 0x7F;
        if (shift >= 63 and payload != 0 and payload != 0x7F) return null;
        result |= @as(u64, payload) << @intCast(shift);
        shift += 7;
        if (byte & 0x80 == 0) break;
        if (shift >= 64) return null;
    } else return null;

    if (shift < 64 and byte & 0x40 != 0) {
        result |= ~@as(u64, 0) << @intCast(shift);
    }
    return @bitCast(result);
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
    std.mem.writeInt(u32, data[offset + 12 ..][0..4], 2, .little);
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
    std.mem.writeInt(u32, data[336..340], 1, .little);
    data[340] = N_SECT;
    data[341] = 1;
    std.mem.writeInt(u64, data[344..352], 0x2000, .little);
    @memcpy(data[353..][0..11], "_test_call\x00");
    std.mem.writeInt(u32, data[384..388], 0, .little);

    var metadata = try Metadata.init(allocator, &data);
    defer metadata.deinit();
    try std.testing.expectEqual(@as(usize, 1), metadata.imports.len);
    try std.testing.expectEqualStrings("_test_call", metadata.imports[0].name);
    try std.testing.expectEqual(@as(u64, 0x1000), metadata.imports[0].stub_address);
    try std.testing.expectEqual(@as(u64, 0x2000), metadata.definedSymbolAddress("_test_call").?);
    try std.testing.expect(metadata.definedSymbolAddress("_missing") == null);
}

test "metadata decodes classic dyld data bindings" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** 256;
    std.mem.writeInt(u32, data[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, data[16..20], 2, .little);
    std.mem.writeInt(u32, data[20..24], 72 + 48, .little);

    var offset: usize = MACH_HEADER_64_SIZE;
    std.mem.writeInt(u32, data[offset..][0..4], macho.LC_SEGMENT_64, .little);
    std.mem.writeInt(u32, data[offset + 4 ..][0..4], 72, .little);
    std.mem.writeInt(u64, data[offset + 24 ..][0..8], 0x1000, .little);

    offset += 72;
    std.mem.writeInt(u32, data[offset..][0..4], LC_DYLD_INFO_ONLY, .little);
    std.mem.writeInt(u32, data[offset + 4 ..][0..4], 48, .little);
    std.mem.writeInt(u32, data[offset + 16 ..][0..4], 200, .little);
    std.mem.writeInt(u32, data[offset + 20 ..][0..4], 14, .little);

    const bind_stream = [_]u8{ 0x11, 0x40, '_', 'v', 'i', 'r', 't', 'u', 'a', 'l', 0, 0x51, 0x70, 0x30, 0x90, 0x00 };
    @memcpy(data[200..][0..bind_stream.len], &bind_stream);
    std.mem.writeInt(u32, data[offset + 20 ..][0..4], bind_stream.len, .little);

    var metadata = try Metadata.init(allocator, &data);
    defer metadata.deinit();
    try std.testing.expectEqual(@as(usize, 1), metadata.bindings.len);
    try std.testing.expectEqualStrings("_virtual", metadata.bindings[0].name);
    try std.testing.expectEqual(@as(u64, 0x1030), metadata.bindings[0].address);
    try std.testing.expectEqual(@as(i64, 0), metadata.bindings[0].addend);
}

test "metadata collects mod init function addresses" {
    const allocator = std.testing.allocator;
    var data = [_]u8{0} ** 256;
    std.mem.writeInt(u32, data[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, data[16..20], 1, .little);
    std.mem.writeInt(u32, data[20..24], SEGMENT_COMMAND_64_SIZE + SECTION_64_SIZE, .little);

    const command_offset = MACH_HEADER_64_SIZE;
    std.mem.writeInt(u32, data[command_offset..][0..4], macho.LC_SEGMENT_64, .little);
    std.mem.writeInt(u32, data[command_offset + 4 ..][0..4], SEGMENT_COMMAND_64_SIZE + SECTION_64_SIZE, .little);
    std.mem.writeInt(u64, data[command_offset + 24 ..][0..8], 0x1000, .little);
    std.mem.writeInt(u32, data[command_offset + 64 ..][0..4], 1, .little);

    const section_offset = command_offset + SEGMENT_COMMAND_64_SIZE;
    @memcpy(data[section_offset..][0..15], "__mod_init_func");
    @memcpy(data[section_offset + 16 ..][0..12], "__DATA_CONST");
    std.mem.writeInt(u64, data[section_offset + 32 ..][0..8], 0x2000, .little);
    std.mem.writeInt(u64, data[section_offset + 40 ..][0..8], @sizeOf(u64), .little);
    std.mem.writeInt(u32, data[section_offset + 48 ..][0..4], 224, .little);
    std.mem.writeInt(u64, data[224..232], 0x1234_5678, .little);

    var metadata = try Metadata.init(allocator, &data);
    defer metadata.deinit();
    try std.testing.expectEqual(@as(usize, 1), metadata.initializer_count);
    try std.testing.expectEqualSlices(u64, &.{0x1234_5678}, metadata.initializer_addresses);
}
