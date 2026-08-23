//! Mach-O object and `ar` archive symbol reading.
//!
//! Only what the audit needs: the symbol table of a relocatable object, and
//! the members of a static archive. Nothing is resolved or relocated, and no
//! section contents are read.

const std = @import("std");
const types = @import("types.zig");

pub const MH_MAGIC_64: u32 = 0xfeedfacf;
pub const MH_CIGAM_64: u32 = 0xcffaedfe;
pub const MH_OBJECT: u32 = 0x1;
pub const LC_SYMTAB: u32 = 0x02;

// nlist_64 n_type bits.
const N_STAB: u8 = 0xe0;
const N_PEXT: u8 = 0x10;
const N_TYPE: u8 = 0x0e;
const N_EXT: u8 = 0x01;
// n_type & N_TYPE values.
const N_UNDF: u8 = 0x0;
const N_ABS: u8 = 0x2;
const N_SECT: u8 = 0xe;
const N_INDR: u8 = 0xa;
// n_desc bits.
const N_WEAK_DEF: u16 = 0x0080;

const nlist_64_size: usize = 16;
const mach_header_64_size: usize = 32;

pub const Symbol = struct {
    name: []const u8,
    linkage: types.Linkage,
};

/// Read the symbol table of one Mach-O relocatable object.
///
/// Returns null when the buffer is not a 64-bit little-endian Mach-O object:
/// a build tree can hold LLVM bitcode (from LTO), fat binaries, and objects
/// for another architecture, and skipping those is more useful than failing
/// the whole audit over one file.
pub fn readObjectSymbols(
    allocator: std.mem.Allocator,
    data: []const u8,
    out: *std.ArrayListUnmanaged(Symbol),
) !bool {
    if (data.len < mach_header_64_size) return false;
    const magic = readU32(data, 0);
    // Byte-swapped Mach-O is a foreign-endian object; this host only produces
    // and consumes little-endian ones.
    if (magic != MH_MAGIC_64) return false;

    const command_count = readU32(data, 16);
    const command_bytes = readU32(data, 20);
    var offset: usize = mach_header_64_size;
    const command_limit = @min(data.len, mach_header_64_size + command_bytes);

    var index: u32 = 0;
    while (index < command_count) : (index += 1) {
        if (offset + 8 > command_limit) break;
        const command = readU32(data, offset);
        const size = readU32(data, offset + 4);
        if (size < 8 or offset + size > command_limit) break;
        if (command == LC_SYMTAB and size >= 24) {
            const symbol_offset = readU32(data, offset + 8);
            const symbol_count = readU32(data, offset + 12);
            const string_offset = readU32(data, offset + 16);
            const string_size = readU32(data, offset + 20);
            try collect(
                allocator,
                data,
                symbol_offset,
                symbol_count,
                string_offset,
                string_size,
                out,
            );
            return true;
        }
        offset += size;
    }
    // An object with no symbol table is still a valid object.
    return true;
}

fn collect(
    allocator: std.mem.Allocator,
    data: []const u8,
    symbol_offset: u32,
    symbol_count: u32,
    string_offset: u32,
    string_size: u32,
    out: *std.ArrayListUnmanaged(Symbol),
) !void {
    const strings_end = @as(usize, string_offset) +| @as(usize, string_size);
    if (strings_end > data.len) return;

    var index: u32 = 0;
    while (index < symbol_count) : (index += 1) {
        const entry = @as(usize, symbol_offset) +| (@as(usize, index) *| nlist_64_size);
        if (entry + nlist_64_size > data.len) return;
        const string_index = readU32(data, entry);
        const n_type = data[entry + 4];
        const n_desc = readU16(data, entry + 6);
        const n_value = readU64(data, entry + 8);

        // Debug-map entries share the symbol table but describe source, not
        // linkage.
        if ((n_type & N_STAB) != 0) continue;
        if (!isExternal(n_type)) {
            // File-local. Cannot collide, so it is not part of the audit.
            continue;
        }
        const name_start = @as(usize, string_offset) +| @as(usize, string_index);
        if (name_start >= strings_end) continue;
        const name = terminated(data[name_start..strings_end]);
        if (name.len == 0) continue;

        const linkage = classify(n_type, n_desc, n_value) orelse continue;
        try out.append(allocator, .{ .name = name, .linkage = linkage });
    }
}

fn isExternal(n_type: u8) bool {
    return (n_type & N_EXT) != 0 or (n_type & N_PEXT) != 0;
}

/// Map one nlist entry onto the linker's view.
///
/// A private external symbol is visible to the linker only within the unit it
/// came from, so it is classified `private` and takes no part in collision
/// detection even though the `N_PEXT` bit makes it look external.
pub fn classify(n_type: u8, n_desc: u16, n_value: u64) ?types.Linkage {
    const kind = n_type & N_TYPE;
    if (kind == N_UNDF) {
        // A common symbol carries a size in n_value and is a tentative
        // definition, not a reference.
        if (n_value != 0) return .weak;
        return .undefined_reference;
    }
    if (kind != N_SECT and kind != N_ABS and kind != N_INDR) return null;
    if ((n_type & N_PEXT) != 0) return .private;
    if ((n_type & N_EXT) == 0) return .private;
    if ((n_desc & N_WEAK_DEF) != 0) return .weak;
    return .strong;
}

// --- `ar` archives --------------------------------------------------------

pub const archive_magic = "!<arch>\n";
const member_header_size: usize = 60;

pub const Member = struct {
    name: []const u8,
    data: []const u8,
};

/// Walk the members of a BSD/macOS `ar` archive.
///
/// macOS stores long member names inline: the header name reads `#1/<length>`
/// and the first `<length>` bytes of the member body are the real name. Almost
/// every object in a CMake build has a name long enough to take that path, so
/// it is the normal case rather than an edge case.
pub const ArchiveIterator = struct {
    data: []const u8,
    offset: usize,

    pub fn init(data: []const u8) ?ArchiveIterator {
        if (data.len < archive_magic.len) return null;
        if (!std.mem.eql(u8, data[0..archive_magic.len], archive_magic)) return null;
        return .{ .data = data, .offset = archive_magic.len };
    }

    pub fn next(self: *ArchiveIterator) ?Member {
        while (true) {
            // Members are two-byte aligned.
            if (self.offset % 2 != 0) self.offset += 1;
            if (self.offset + member_header_size > self.data.len) return null;
            const header = self.data[self.offset..][0..member_header_size];
            const size = parseDecimal(header[48..58]) orelse return null;
            var body_start = self.offset + member_header_size;
            var body_len = size;
            if (body_start +| body_len > self.data.len) return null;

            var name = trimRight(header[0..16]);
            if (std.mem.startsWith(u8, name, "#1/")) {
                const name_len = parseDecimal(name[3..]) orelse return null;
                if (name_len > body_len) return null;
                name = terminated(self.data[body_start..][0..name_len]);
                body_start += name_len;
                body_len -= name_len;
            }
            const member: Member = .{
                .name = name,
                .data = self.data[body_start..][0..body_len],
            };
            self.offset = body_start + body_len;
            // The symbol-table and long-name members are archive bookkeeping,
            // not translation units.
            if (isBookkeeping(member.name)) continue;
            return member;
        }
    }

    fn isBookkeeping(name: []const u8) bool {
        return std.mem.eql(u8, name, "/") or
            std.mem.eql(u8, name, "//") or
            std.mem.eql(u8, name, "__.SYMDEF") or
            std.mem.startsWith(u8, name, "__.SYMDEF");
    }
};

// --- helpers --------------------------------------------------------------

fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn readU32(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

fn readU64(data: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, data[offset..][0..8], .little);
}

fn terminated(data: []const u8) []const u8 {
    for (data, 0..) |character, index| {
        if (character == 0) return data[0..index];
    }
    return data;
}

fn trimRight(data: []const u8) []const u8 {
    var end = data.len;
    while (end > 0 and (data[end - 1] == ' ' or data[end - 1] == '/')) end -= 1;
    return data[0..end];
}

fn parseDecimal(text: []const u8) ?usize {
    var value: usize = 0;
    var digits: usize = 0;
    for (text) |character| {
        if (character == ' ') break;
        if (character < '0' or character > '9') {
            if (digits == 0) continue;
            break;
        }
        value = value *| 10 +| (character - '0');
        digits += 1;
    }
    return if (digits == 0) null else value;
}

test "nlist classification separates the linker's four cases" {
    // Weak definition: vague linkage, duplicates expected.
    try std.testing.expectEqual(types.Linkage.weak, classify(N_SECT | N_EXT, N_WEAK_DEF, 0x1000).?);
    // Plain external definition: a duplicate here is a real collision.
    try std.testing.expectEqual(types.Linkage.strong, classify(N_SECT | N_EXT, 0, 0x1000).?);
    // Private external: linker-visible only inside its own unit.
    try std.testing.expectEqual(types.Linkage.private, classify(N_SECT | N_PEXT, 0, 0x1000).?);
    // Undefined reference.
    try std.testing.expectEqual(types.Linkage.undefined_reference, classify(N_UNDF | N_EXT, 0, 0).?);
    // A common symbol carries its size in n_value and is a tentative
    // definition, so it must not be counted as a reference.
    try std.testing.expectEqual(types.Linkage.weak, classify(N_UNDF | N_EXT, 0, 64).?);
    // Debug-map entries are filtered before classification, and a local
    // symbol is never linker-visible.
    try std.testing.expectEqual(types.Linkage.private, classify(N_SECT, 0, 0x1000).?);
}

test "a non-Mach-O buffer is skipped rather than failing the audit" {
    var symbols: std.ArrayListUnmanaged(Symbol) = .empty;
    defer symbols.deinit(std.testing.allocator);
    // LLVM bitcode, which an LTO build emits in place of objects.
    const bitcode = "BC\xc0\xde" ++ ("\x00" ** 40);
    try std.testing.expect(!try readObjectSymbols(std.testing.allocator, bitcode, &symbols));
    try std.testing.expect(!try readObjectSymbols(std.testing.allocator, "short", &symbols));
    try std.testing.expectEqual(@as(usize, 0), symbols.items.len);
}

test "archive iteration reads macOS long member names" {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(std.testing.allocator);
    const allocator = std.testing.allocator;
    try buffer.appendSlice(allocator, archive_magic);

    // One member whose name goes in the body, the macOS long-name form.
    const long_name = "platform_amd64_mac.cc.o\x00";
    const body = "PAYLOAD!";
    var header: [60]u8 = @splat(' ');
    const prefix = try std.fmt.bufPrint(header[0..16], "#1/{d}", .{long_name.len});
    _ = prefix;
    const size_text = try std.fmt.bufPrint(header[48..58], "{d}", .{long_name.len + body.len});
    _ = size_text;
    // bufPrint leaves the remainder of each field as written above; restore the
    // spaces bufPrint did not overwrite and set the terminator.
    for (header[0..16], 0..) |character, index| {
        if (character == 0) header[index] = ' ';
    }
    for (header[48..58], 0..) |character, index| {
        if (character == 0) header[48 + index] = ' ';
    }
    header[58] = 0x60;
    header[59] = '\n';
    try buffer.appendSlice(allocator, &header);
    try buffer.appendSlice(allocator, long_name);
    try buffer.appendSlice(allocator, body);

    var iterator = ArchiveIterator.init(buffer.items) orelse return error.TestUnexpectedResult;
    const member = iterator.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("platform_amd64_mac.cc.o", member.name);
    try std.testing.expectEqualStrings(body, member.data);
    try std.testing.expect(iterator.next() == null);
}

test "a buffer without the archive magic is not an archive" {
    try std.testing.expect(ArchiveIterator.init("not an archive") == null);
    try std.testing.expect(ArchiveIterator.init("!<") == null);
}
