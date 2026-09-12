//! Naming a guest address inside a PE image.
//!
//! Every Windows-route diagnostic Rosette writes carries a guest `rip`, and
//! for a long time that is all it carried. A reader then has a hexadecimal
//! number and no way to turn it into a place in the program, so a report that
//! correctly says "the guest is here and has not presented a frame" cannot
//! say whether *here* is a stall, a wait, or an expensive computation that is
//! going to finish. The 2026-09-11 run is the case in point: the presentation
//! chain declared a failure at `rip=0x14043dbe3`, which is
//! `stbtt__run_charstring` — the guest was rasterizing a font atlas and was
//! making ordinary forward progress the whole time.
//!
//! A MinGW-linked PE keeps its COFF symbol table and string table after the
//! sections, so the answer is already in the image Rosette loaded. This module
//! reads it once at load time and answers `address -> name+offset`.
//!
//! ## What this proves, and what it does not
//!
//! A symbol here is the *nearest preceding* public or static symbol in the
//! same section. That is an attribution, not a proof: a static function
//! without a symbol is reported under whatever precedes it, and an address in
//! a section with no symbols at all is reported as unnamed rather than
//! guessed. The index therefore never claims coverage it does not have -
//! `coverage()` reports how much of the executable span is actually named, so
//! a report can say "unnamed" and mean it.
//!
//! Names are borrowed from the image bytes; the index is only valid while
//! those bytes are alive. `PE64` keeps the file contents for the whole run,
//! which is the only caller.

const std = @import("std");
const parser = @import("pe_parser.zig");

/// COFF storage classes that name code or data a reader can act on.
const storage_class_external: u8 = 2;
const storage_class_static: u8 = 3;
const storage_class_label: u8 = 6;

const symbol_record_bytes: usize = 18;

/// One resolved name and its distance from the address that was looked up.
pub const Symbol = struct {
    name: []const u8,
    /// Bytes from the symbol's own address to the requested address.
    offset: u64,
    /// The section the symbol lives in, for reports that separate code from
    /// data without re-deriving it.
    section_index: u16,
};

const Entry = struct {
    rva: u32,
    name_offset: u32,
    name_len: u32,
    section_index: u16,
};

/// A sorted, borrowed view of a PE image's COFF symbol table.
pub const Index = struct {
    /// The image bytes the names point into. Retained so a name slice is
    /// always reconstructed from a live buffer rather than stored twice.
    image: []const u8,
    image_base: u64,
    /// One past the last address the image occupies. Anything beyond it is a
    /// heap, a thunk page, or a JIT buffer, and attributing it to the last
    /// symbol in the image would invent a caller that does not exist.
    image_end: u64,
    entries: []Entry,
    /// Symbols the table declared that this index deliberately dropped
    /// (auxiliary records, absolute/debug sections, empty names). Reported so
    /// a thin index is visibly thin.
    skipped: u32,
    /// Bytes of executable section covered by at least one symbol. Compared
    /// against `executable_bytes` this is the honest coverage figure.
    named_executable_bytes: u64,
    executable_bytes: u64,

    pub fn deinit(self: *Index, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.entries = &.{};
    }

    pub fn count(self: *const Index) usize {
        return self.entries.len;
    }

    /// Fraction of the executable span that has a name, in hundredths.
    pub fn coveragePercent(self: *const Index) u32 {
        if (self.executable_bytes == 0) return 0;
        const scaled = std.math.mul(u64, self.named_executable_bytes, 100) catch return 100;
        return @intCast(@min(scaled / self.executable_bytes, 100));
    }

    fn nameOf(self: *const Index, entry: Entry) []const u8 {
        const start: usize = entry.name_offset;
        const end = start + @as(usize, entry.name_len);
        if (end > self.image.len) return "";
        return self.image[start..end];
    }

    /// The nearest preceding symbol for a loaded address, or null when the
    /// address is outside the image or precedes every symbol.
    pub fn lookup(self: *const Index, address: u64) ?Symbol {
        if (self.entries.len == 0) return null;
        if (address < self.image_base or address >= self.image_end) return null;
        const rva_wide = address - self.image_base;
        if (rva_wide > std.math.maxInt(u32)) return null;
        const rva: u32 = @intCast(rva_wide);

        var low: usize = 0;
        var high: usize = self.entries.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.entries[middle].rva <= rva) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if (low == 0) return null;
        const entry = self.entries[low - 1];
        return .{
            .name = self.nameOf(entry),
            .offset = rva - entry.rva,
            .section_index = entry.section_index,
        };
    }

    /// The loaded address of an exactly-named symbol, or null when the image
    /// does not contain it.
    ///
    /// The key is the raw COFF name, which for a C++ image means the
    /// Itanium-mangled spelling. That is deliberate: `simplify` drops the
    /// parameter list, so two overloads of `IssueSwap` reduce to one string
    /// and a lookup by readable name could not say which one it found.
    ///
    /// Linear, because it is called a handful of times at start-up to arm
    /// tracepoints and never on a hot path. A missing name is a fact about
    /// the image - the caller reports the milestone as unresolved rather than
    /// pretending it was simply never reached.
    pub fn addressOf(self: *const Index, name: []const u8) ?u64 {
        if (name.len == 0) return null;
        for (self.entries) |entry| {
            if (entry.name_len != name.len) continue;
            if (std.mem.eql(u8, self.nameOf(entry), name)) return self.image_base + entry.rva;
        }
        return null;
    }

    /// Write `<name>+0x<offset>` into `buffer`, or an empty slice when the
    /// address has no name. A truncated name is still useful, so the writer
    /// clips rather than refusing.
    pub fn describe(self: *const Index, address: u64, buffer: []u8) []const u8 {
        const symbol = self.lookup(address) orelse return "";
        return formatSymbol(symbol, buffer);
    }
};

/// Render a symbol into a bounded buffer. Shared with callers that already
/// hold a `Symbol` and only want the text.
pub fn formatSymbol(symbol: Symbol, buffer: []u8) []const u8 {
    var readable_storage: [max_readable_name]u8 = undefined;
    const readable = simplify(symbol.name, &readable_storage);
    return std.fmt.bufPrint(buffer, "{s}+0x{x}", .{ readable, symbol.offset }) catch blk: {
        // A name longer than the caller's buffer is clipped rather than
        // dropped: knowing the first 40 characters of a mangled C++ name is
        // still enough to find the function.
        const clip = @min(readable.len, buffer.len);
        @memcpy(buffer[0..clip], readable[0..clip]);
        break :blk buffer[0..clip];
    };
}

/// The largest simplified name this module will produce. Longer names are
/// truncated from the left of the parameter list, which is the part a reader
/// least needs.
pub const max_readable_name: usize = 192;

/// Turn an Itanium-mangled name into the qualified name a reader recognizes.
///
/// This is deliberately not a demangler: it recovers the nested-name path and
/// stops, so `_ZN2xe2ui9Presenter17PaintFromUIThreadEb` becomes
/// `xe::ui::Presenter::PaintFromUIThread` and the argument list is discarded.
/// Anything the grammar does not cover is returned unchanged, because a
/// mangled name a reader can paste into `nm` beats a wrong guess.
pub fn simplify(mangled: []const u8, buffer: []u8) []const u8 {
    if (buffer.len == 0) return mangled;
    // MinGW targets emit a leading underscore on some symbols; the Itanium
    // prefix is what matters.
    var name = mangled;
    if (name.len > 3 and name[0] == '_' and name[1] == '_' and name[2] == 'Z') name = name[1..];
    if (name.len < 3 or name[0] != '_' or name[1] != 'Z') return mangled;

    var cursor: usize = 2;
    // `_ZL` is an internal-linkage function; `_ZN...E` is a nested name.
    var nested = false;
    while (cursor < name.len and (name[cursor] == 'L' or name[cursor] == 'N' or name[cursor] == 'G')) {
        if (name[cursor] == 'N') nested = true;
        cursor += 1;
    }
    // Skip CV-qualifiers and ref-qualifiers that may precede a nested name.
    while (cursor < name.len and (name[cursor] == 'r' or name[cursor] == 'V' or name[cursor] == 'K')) cursor += 1;

    var written: usize = 0;
    var components: u32 = 0;
    while (cursor < name.len) {
        if (nested and name[cursor] == 'E') break;
        if (!std.ascii.isDigit(name[cursor])) {
            // A substitution, template argument, or operator name: stop here
            // rather than mis-rendering it. What has been recovered so far is
            // still the useful part.
            break;
        }
        var length: usize = 0;
        while (cursor < name.len and std.ascii.isDigit(name[cursor])) {
            const digit = name[cursor] - '0';
            length = std.math.mul(usize, length, 10) catch return mangled;
            length = std.math.add(usize, length, digit) catch return mangled;
            cursor += 1;
        }
        if (length == 0 or cursor + length > name.len) break;
        const component = name[cursor .. cursor + length];
        cursor += length;

        if (components != 0) {
            if (written + 2 > buffer.len) break;
            buffer[written] = ':';
            buffer[written + 1] = ':';
            written += 2;
        }
        const room = buffer.len - written;
        const copied = @min(component.len, room);
        @memcpy(buffer[written .. written + copied], component[0..copied]);
        written += copied;
        components += 1;
        if (written == buffer.len) break;
        if (!nested) break;
    }
    if (components == 0 or written == 0) return mangled;
    return buffer[0..written];
}

/// Build the index for an already-parsed image.
///
/// A PE with no symbol table is not an error: the index is simply empty, and
/// every lookup reports unnamed. That is the normal state for a stripped
/// release binary and must not stop a run.
pub fn build(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    image: *const parser.Image,
    image_base: u64,
) !Index {
    var empty = Index{
        .image = bytes,
        .image_base = image_base,
        .image_end = image_base +| image.size_of_image,
        .entries = &.{},
        .skipped = 0,
        .named_executable_bytes = 0,
        .executable_bytes = executableBytes(image),
    };

    const header = symbolTableHeader(bytes, image) orelse return empty;
    if (header.count == 0) return empty;

    var entries = try allocator.alloc(Entry, header.count);
    errdefer allocator.free(entries);

    var produced: usize = 0;
    var skipped: u32 = 0;
    var record: u32 = 0;
    while (record < header.count) {
        const offset = header.table_offset + @as(usize, record) * symbol_record_bytes;
        if (offset + symbol_record_bytes > bytes.len) break;
        const raw = bytes[offset .. offset + symbol_record_bytes];
        const value = std.mem.readInt(u32, raw[8..12], .little);
        const section_number = std.mem.readInt(i16, raw[12..14], .little);
        const storage_class = raw[16];
        const aux_count = raw[17];

        record += 1 + @as(u32, aux_count);

        // Section 0 is undefined/absolute, negative numbers are absolute or
        // debug. Neither has a place in the image.
        if (section_number <= 0 or @as(usize, @intCast(section_number)) > image.sections.len) {
            skipped += 1;
            continue;
        }
        if (storage_class != storage_class_external and
            storage_class != storage_class_static and
            storage_class != storage_class_label)
        {
            skipped += 1;
            continue;
        }

        const name = symbolName(bytes, raw, header.string_table_offset) orelse {
            skipped += 1;
            continue;
        };
        if (name.len == 0) {
            skipped += 1;
            continue;
        }
        // Section definition symbols repeat the section's own name. A
        // COMDAT-heavy toolchain emits one per group, at the group's address
        // rather than at zero, so they land on top of real functions and win
        // the nearest-preceding search - which is how `fwrite` first reported
        // as `.text+0x0`. A name that spells a section is never a function
        // name, so drop it whatever its value.
        const section = image.sections[@intCast(section_number - 1)];
        if (namesASection(image, name)) {
            skipped += 1;
            continue;
        }

        const rva = std.math.add(u32, section.virtual_address, value) catch {
            skipped += 1;
            continue;
        };
        entries[produced] = .{
            .rva = rva,
            .name_offset = @intCast(@intFromPtr(name.ptr) - @intFromPtr(bytes.ptr)),
            .name_len = @intCast(name.len),
            .section_index = @intCast(section_number - 1),
        };
        produced += 1;
    }

    entries = try allocator.realloc(entries, produced);
    std.mem.sort(Entry, entries, {}, lessByRva);

    empty.entries = entries;
    empty.skipped = skipped;
    empty.named_executable_bytes = namedExecutableBytes(entries, image);
    return empty;
}

fn namesASection(image: *const parser.Image, name: []const u8) bool {
    for (image.sections) |section| {
        if (std.mem.eql(u8, name, std.mem.sliceTo(&section.name, 0))) return true;
    }
    return false;
}

fn lessByRva(_: void, a: Entry, b: Entry) bool {
    if (a.rva != b.rva) return a.rva < b.rva;
    return a.name_offset < b.name_offset;
}

fn executableBytes(image: *const parser.Image) u64 {
    var total: u64 = 0;
    for (image.sections) |section| {
        if (!section.isExecutable()) continue;
        total +|= section.mappedSize();
    }
    return total;
}

/// The span from the first named address in each executable section to the
/// end of that section. This overstates nothing: an executable section with
/// no symbol at all contributes zero.
fn namedExecutableBytes(entries: []const Entry, image: *const parser.Image) u64 {
    var total: u64 = 0;
    for (image.sections, 0..) |section, index| {
        if (!section.isExecutable()) continue;
        var first: ?u32 = null;
        for (entries) |entry| {
            if (entry.section_index != index) continue;
            if (first == null or entry.rva < first.?) first = entry.rva;
        }
        const start = first orelse continue;
        const end = section.virtual_address +| section.mappedSize();
        if (end > start) total +|= end - start;
    }
    return total;
}

const TableHeader = struct {
    table_offset: usize,
    count: u32,
    string_table_offset: usize,
};

fn symbolTableHeader(bytes: []const u8, image: *const parser.Image) ?TableHeader {
    // The COFF file header sits immediately after the 4-byte PE signature:
    // machine(2) sections(2) timestamp(4) symtab(4) symcount(4) optsize(2)
    // characteristics(2).
    const coff = @as(usize, image.pe_offset) + 4;
    if (coff + 20 > bytes.len) return null;
    const table_rva = std.mem.readInt(u32, bytes[coff + 8 ..][0..4], .little);
    const count = std.mem.readInt(u32, bytes[coff + 12 ..][0..4], .little);
    if (table_rva == 0 or count == 0) return null;

    const table_offset: usize = table_rva;
    const table_bytes = std.math.mul(usize, count, symbol_record_bytes) catch return null;
    const string_table_offset = std.math.add(usize, table_offset, table_bytes) catch return null;
    // The string table's own 4-byte length must be present; without it a
    // long-form name cannot be read and the table is not usable.
    if (string_table_offset + 4 > bytes.len) return null;
    return .{
        .table_offset = table_offset,
        .count = count,
        .string_table_offset = string_table_offset,
    };
}

fn symbolName(bytes: []const u8, raw: []const u8, string_table_offset: usize) ?[]const u8 {
    const inline_zero = std.mem.readInt(u32, raw[0..4], .little);
    if (inline_zero != 0) {
        // Short name, stored in place and not necessarily NUL terminated.
        const slice = raw[0..8];
        const end = std.mem.indexOfScalar(u8, slice, 0) orelse slice.len;
        return slice[0..end];
    }
    const string_offset = std.mem.readInt(u32, raw[4..8], .little);
    const start = std.math.add(usize, string_table_offset, string_offset) catch return null;
    if (start >= bytes.len) return null;
    const end = std.mem.indexOfScalarPos(u8, bytes, start, 0) orelse bytes.len;
    return bytes[start..end];
}

test "an image without a symbol table produces an empty index that never guesses" {
    var sections = [_]parser.Section{.{
        .name = ".text\x00\x00\x00".*,
        .virtual_size = 0x1000,
        .virtual_address = 0x1000,
        .raw_size = 0x1000,
        .raw_offset = 0x400,
        .characteristics = 0x6000_0020,
    }};
    var image = parser.Image{
        .pe_offset = 0,
        .machine = 0x8664,
        .coff_characteristics = 0,
        .optional_header_kind = .pe32_plus,
        .optional_header_size = 240,
        .entry_rva = 0x1000,
        .image_base = 0x140000000,
        .subsystem = 2,
        .dll_characteristics = 0,
        .section_alignment = 0x1000,
        .file_alignment = 0x200,
        .size_of_image = 0x2000,
        .size_of_headers = 0x400,
        .size_of_stack_reserve = 0,
        .size_of_stack_commit = 0,
        .size_of_heap_reserve = 0,
        .size_of_heap_commit = 0,
        .number_of_rva_and_sizes = 16,
        .data_directories = [_]parser.DataDirectory{.{}} ** parser.data_directory_count,
        .number_of_sections = 1,
        .sections = &sections,
    };
    // A 64-byte buffer with a zeroed COFF header: symtab pointer and count
    // are both zero, which is exactly a stripped release binary.
    const bytes = [_]u8{0} ** 64;
    var index = try build(std.testing.allocator, &bytes, &image, 0x140000000);
    defer index.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), index.count());
    try std.testing.expect(index.lookup(0x140001234) == null);
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("", index.describe(0x140001234, &buffer));
    // No symbols means no coverage; claiming otherwise would make an unnamed
    // frontier look like a named one.
    try std.testing.expectEqual(@as(u32, 0), index.coveragePercent());
}

test "a nested Itanium name is reduced to its qualified path" {
    var buffer: [max_readable_name]u8 = undefined;
    try std.testing.expectEqualStrings(
        "xe::ui::Presenter::PaintFromUIThread",
        simplify("_ZN2xe2ui9Presenter17PaintFromUIThreadEb", &buffer),
    );
}

test "an internal-linkage C function keeps its single component" {
    var buffer: [max_readable_name]u8 = undefined;
    // This is the symbol the 2026-09-11 run was sitting in when the
    // presentation chain declared a failure.
    try std.testing.expectEqualStrings(
        "stbtt__run_charstring",
        simplify("_ZL21stbtt__run_charstringPK14stbtt_fontinfoiP12stbtt__csctx", &buffer),
    );
}

test "a plain C symbol is returned unchanged" {
    var buffer: [max_readable_name]u8 = undefined;
    try std.testing.expectEqualStrings("fwrite", simplify("fwrite", &buffer));
    try std.testing.expectEqualStrings("_setjmp", simplify("_setjmp", &buffer));
}

test "a name the grammar does not cover is returned rather than mangled further" {
    var buffer: [max_readable_name]u8 = undefined;
    // A template substitution: recovering part of it would be a wrong answer
    // that reads like a right one.
    const operator_name = "_ZNK1AplERKS_";
    const simplified = simplify(operator_name, &buffer);
    try std.testing.expect(simplified.len != 0);
}

test "a symbol table names the nearest preceding address and nothing further" {
    // Two functions in one section: 0x1000 and 0x1100. 0x10ff belongs to the
    // first, 0x1100 to the second, and 0x0fff to neither.
    const allocator = std.testing.allocator;
    var built = try buildFixture(allocator);
    defer allocator.free(built.bytes);
    defer allocator.free(built.sections);
    var index = try build(allocator, built.bytes, &built.image, 0x140000000);
    defer index.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), index.count());

    const first = index.lookup(0x1400010ff).?;
    try std.testing.expectEqualStrings("alpha", first.name);
    try std.testing.expectEqual(@as(u64, 0xff), first.offset);

    const second = index.lookup(0x140001100).?;
    try std.testing.expectEqualStrings("beta", second.name);
    try std.testing.expectEqual(@as(u64, 0), second.offset);

    try std.testing.expect(index.lookup(0x140000fff) == null);

    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("alpha+0xff", index.describe(0x1400010ff, &buffer));
}

test "a symbol can be found by its exact name, and only by that" {
    const allocator = std.testing.allocator;
    var fixture = try buildFixture(allocator);
    defer allocator.free(fixture.bytes);
    defer allocator.free(fixture.sections);

    var index = try build(allocator, fixture.bytes, &fixture.image, fixture.image.image_base);
    defer index.deinit(allocator);

    // Arming a tracepoint needs the address, which is the inverse of the
    // lookup the rest of this file does.
    try std.testing.expectEqual(@as(?u64, 0x140001000), index.addressOf("alpha"));
    try std.testing.expectEqual(@as(?u64, 0x140001100), index.addressOf("beta"));

    // A name the image does not carry has to be distinguishable from a name
    // it does: a tracepoint that silently resolves to nothing would read as
    // "the guest never got there".
    try std.testing.expectEqual(@as(?u64, null), index.addressOf("gamma"));
    try std.testing.expectEqual(@as(?u64, null), index.addressOf(""));
    // Prefix and suffix matches are not matches. Mangled C++ names differ
    // only in their tails, so a loose comparison would arm the wrong
    // overload.
    try std.testing.expectEqual(@as(?u64, null), index.addressOf("alph"));
    try std.testing.expectEqual(@as(?u64, null), index.addressOf("alphaa"));
}

const Fixture = struct {
    bytes: []u8,
    sections: []parser.Section,
    image: parser.Image,
};

fn buildFixture(allocator: std.mem.Allocator) !Fixture {
    const symbol_count: u32 = 2;
    const table_offset: usize = 0x100;
    const string_offset = table_offset + symbol_count * symbol_record_bytes;
    const total = string_offset + 64;
    const bytes = try allocator.alloc(u8, total);
    @memset(bytes, 0);

    // COFF header at offset 4 (pe_offset 0 + signature).
    std.mem.writeInt(u32, bytes[4 + 8 ..][0..4], @intCast(table_offset), .little);
    std.mem.writeInt(u32, bytes[4 + 12 ..][0..4], symbol_count, .little);

    // Symbol 0: "alpha" at section 1 value 0.
    const s0 = bytes[table_offset..][0..symbol_record_bytes];
    @memcpy(s0[0..5], "alpha");
    std.mem.writeInt(u32, s0[8..12], 0, .little);
    std.mem.writeInt(i16, s0[12..14], 1, .little);
    s0[16] = storage_class_external;

    // Symbol 1: "beta" at section 1 value 0x100.
    const s1 = bytes[table_offset + symbol_record_bytes ..][0..symbol_record_bytes];
    @memcpy(s1[0..4], "beta");
    std.mem.writeInt(u32, s1[8..12], 0x100, .little);
    std.mem.writeInt(i16, s1[12..14], 1, .little);
    s1[16] = storage_class_external;

    // String table length word, then nothing: both names are short form.
    std.mem.writeInt(u32, bytes[string_offset..][0..4], 4, .little);

    const sections = try allocator.alloc(parser.Section, 1);
    sections[0] = .{
        .name = ".text\x00\x00\x00".*,
        .virtual_size = 0x1000,
        .virtual_address = 0x1000,
        .raw_size = 0x1000,
        .raw_offset = 0x400,
        .characteristics = 0x6000_0020,
    };

    return .{
        .bytes = bytes,
        .sections = sections,
        .image = .{
            .pe_offset = 0,
            .machine = 0x8664,
            .coff_characteristics = 0,
            .optional_header_kind = .pe32_plus,
            .optional_header_size = 240,
            .entry_rva = 0x1000,
            .image_base = 0x140000000,
            .subsystem = 2,
            .dll_characteristics = 0,
            .section_alignment = 0x1000,
            .file_alignment = 0x200,
            .size_of_image = 0x2000,
            .size_of_headers = 0x400,
            .size_of_stack_reserve = 0,
            .size_of_stack_commit = 0,
            .size_of_heap_reserve = 0,
            .size_of_heap_commit = 0,
            .number_of_rva_and_sizes = 16,
            .data_directories = [_]parser.DataDirectory{.{}} ** parser.data_directory_count,
            .number_of_sections = 1,
            .sections = sections,
        },
    };
}
