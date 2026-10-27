const std = @import("std");
const testing = std.testing;
const Executor = @import("../instruction_operations.zig").Executor;
const abi = @import("../abi_handshake.zig");

const cp_acp: u32 = 0;
const cp_windows_1252: u32 = 1252;
const cp_oem_us: u32 = 437;
const cp_utf8: u32 = 65001;

fn getAcp(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(cp_windows_1252);
}

fn getOemCp(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(cp_oem_us);
}

fn getConsoleCp(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 0);
    frame.finish(cp_oem_us);
}

fn isValidCodePage(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 1);
    const codepage = frame.arg(0);
    frame.finish(@intFromBool(codepage == cp_windows_1252 or codepage == cp_oem_us or codepage == cp_utf8));
}

fn getCpInfo(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 2);
    const codepage = frame.arg(0);
    const info_address = frame.arg(1);
    if (info_address == 0) {
        frame.finish(0);
        return;
    }

    const max_char_size: u32 = switch (codepage) {
        cp_windows_1252, cp_oem_us => 1,
        cp_utf8 => 4,
        else => {
            frame.finish(0);
            return;
        },
    };
    ctx.mem.write32(info_address, max_char_size);
    ctx.mem.write8(info_address + 4, '?');
    ctx.mem.write8(info_address + 5, 0);
    // Supported code pages are single-byte except UTF-8. None has lead-byte
    // ranges in CPINFO, so the 12-byte LeadByte field is all zeroes.
    @memset(guestSlice(ctx, info_address + 6, 12) orelse {
        frame.finish(0);
        return;
    }, 0);
    frame.finish(1);
}

fn guestSlice(ctx: *Executor, address: u32, byte_count: usize) ?[]u8 {
    if (address < ctx.mem.base) return null;
    const offset: usize = @intCast(address - ctx.mem.base);
    if (offset > ctx.mem.data.len or byte_count > ctx.mem.data.len - offset) return null;
    return ctx.mem.data[offset .. offset + byte_count];
}

fn wideSource(ctx: *Executor, address: u32, count: u32) ?[]const u8 {
    if (address == 0) return null;
    if (count == std.math.maxInt(u32)) {
        if (address < ctx.mem.base) return null;
        const offset: usize = @intCast(address - ctx.mem.base);
        if (offset >= ctx.mem.data.len) return null;
        var position = offset;
        while (position + 1 < ctx.mem.data.len) : (position += 2) {
            if (ctx.mem.data[position] == 0 and ctx.mem.data[position + 1] == 0) {
                return ctx.mem.data[offset .. position + 2];
            }
        }
        return null;
    }
    if (count == 0 or count & 0x8000_0000 != 0) return null;
    const byte_count = std.math.mul(usize, @as(usize, @intCast(count)), 2) catch return null;
    return guestSlice(ctx, address, byte_count);
}

fn byteSource(ctx: *Executor, address: u32, count: u32) ?[]const u8 {
    if (address == 0) return null;
    if (count == std.math.maxInt(u32)) {
        if (address < ctx.mem.base) return null;
        const offset: usize = @intCast(address - ctx.mem.base);
        if (offset >= ctx.mem.data.len) return null;
        const bytes = ctx.mem.data[offset..];
        const terminator = std.mem.indexOfScalar(u8, bytes, 0) orelse return null;
        return bytes[0 .. terminator + 1];
    }
    if (count == 0 or count & 0x8000_0000 != 0) return null;
    return guestSlice(ctx, address, @intCast(count));
}

fn ctype1Flags(codepoint: u21) u16 {
    const c1_upper: u16 = 0x0001;
    const c1_lower: u16 = 0x0002;
    const c1_digit: u16 = 0x0004;
    const c1_space: u16 = 0x0008;
    const c1_punct: u16 = 0x0010;
    const c1_control: u16 = 0x0020;
    const c1_blank: u16 = 0x0040;
    const c1_hex: u16 = 0x0080;
    const c1_alpha: u16 = 0x0100;
    const c1_defined: u16 = 0x0200;

    var flags: u16 = c1_defined;
    if (codepoint <= 0x7F) {
        const byte: u8 = @intCast(codepoint);
        if (std.ascii.isUpper(byte)) flags |= c1_upper | c1_alpha;
        if (std.ascii.isLower(byte)) flags |= c1_lower | c1_alpha;
        if (std.ascii.isDigit(byte)) flags |= c1_digit;
        if (std.ascii.isHex(byte)) flags |= c1_hex;
        if (std.ascii.isWhitespace(byte)) flags |= c1_space;
        if (byte == ' ' or byte == '\t') flags |= c1_blank;
        if (byte < 0x20 or byte == 0x7F) flags |= c1_control;
        if (byte >= 0x21 and byte <= 0x7E and
            !std.ascii.isAlphanumeric(byte) and !std.ascii.isWhitespace(byte))
        {
            flags |= c1_punct;
        }
    } else if (codepoint <= 0xFF) {
        if ((codepoint >= 0x00C0 and codepoint <= 0x00D6) or (codepoint >= 0x00D8 and codepoint <= 0x00DE)) {
            flags |= c1_upper | c1_alpha;
        } else if ((codepoint >= 0x00DF and codepoint <= 0x00F6) or (codepoint >= 0x00F8 and codepoint <= 0x00FF)) {
            flags |= c1_lower | c1_alpha;
        }
    }
    return flags;
}

fn getStringTypeW(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 4);
    if (frame.arg(0) != 1) {
        frame.finish(0);
        return;
    }
    const source = wideSource(ctx, frame.arg(1), frame.arg(2)) orelse {
        frame.finish(0);
        return;
    };
    const output_address = frame.arg(3);
    const output_length = std.math.mul(usize, source.len / 2, 2) catch {
        frame.finish(0);
        return;
    };
    const output = guestSlice(ctx, output_address, output_length) orelse {
        frame.finish(0);
        return;
    };
    for (0..source.len / 2) |index| {
        const codepoint = std.mem.readInt(u16, source[index * 2 ..][0..2], .little);
        std.mem.writeInt(u16, output[index * 2 ..][0..2], ctype1Flags(codepoint), .little);
    }
    frame.finish(1);
}

fn getStringTypeA(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 4);
    if (frame.arg(0) != 1) {
        frame.finish(0);
        return;
    }
    const source = byteSource(ctx, frame.arg(1), frame.arg(2)) orelse {
        frame.finish(0);
        return;
    };
    const output = guestSlice(ctx, frame.arg(3), source.len * 2) orelse {
        frame.finish(0);
        return;
    };
    for (source, 0..) |byte, index| {
        std.mem.writeInt(u16, output[index * 2 ..][0..2], ctype1Flags(cp1252Codepoint(byte)), .little);
    }
    frame.finish(1);
}

fn mapCase(codepoint: u21, uppercase: bool) u21 {
    if (uppercase) {
        if (codepoint >= 'a' and codepoint <= 'z') return codepoint - 0x20;
        if ((codepoint >= 0x00E0 and codepoint <= 0x00F6) or (codepoint >= 0x00F8 and codepoint <= 0x00FE)) return codepoint - 0x20;
        if (codepoint == 0x00FF) return 0x0178;
    } else {
        if (codepoint >= 'A' and codepoint <= 'Z') return codepoint + 0x20;
        if ((codepoint >= 0x00C0 and codepoint <= 0x00D6) or (codepoint >= 0x00D8 and codepoint <= 0x00DE)) return codepoint + 0x20;
        if (codepoint == 0x0178) return 0x00FF;
    }
    return codepoint;
}

fn caseMapMode(flags: u32) ?bool {
    const case_flags = flags & 0x300;
    if (case_flags != 0x100 and case_flags != 0x200) return null;
    const allowed_flags: u32 = 0x0000_0300 | 0x0100_0000;
    if (flags & ~allowed_flags != 0) return null;
    return case_flags == 0x200;
}

fn lcMapStringW(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 6);
    const uppercase = caseMapMode(frame.arg(1)) orelse {
        frame.finish(0);
        return;
    };
    const source = wideSource(ctx, frame.arg(2), frame.arg(3)) orelse {
        frame.finish(0);
        return;
    };
    const count = source.len / 2;
    const destination = frame.arg(4);
    const capacity = frame.arg(5);
    if (destination == 0) {
        if (capacity != 0) {
            frame.finish(0);
            return;
        }
        frame.finish(@intCast(count));
        return;
    }
    if (capacity < count) {
        frame.finish(0);
        return;
    }
    const output_length = std.math.mul(usize, count, 2) catch {
        frame.finish(0);
        return;
    };
    const output = guestSlice(ctx, destination, output_length) orelse {
        frame.finish(0);
        return;
    };
    for (0..count) |index| {
        const codepoint = std.mem.readInt(u16, source[index * 2 ..][0..2], .little);
        std.mem.writeInt(u16, output[index * 2 ..][0..2], @intCast(mapCase(codepoint, uppercase)), .little);
    }
    frame.finish(@intCast(count));
}

fn lcMapStringA(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 6);
    const uppercase = caseMapMode(frame.arg(1)) orelse {
        frame.finish(0);
        return;
    };
    const source = byteSource(ctx, frame.arg(2), frame.arg(3)) orelse {
        frame.finish(0);
        return;
    };
    const count = source.len;
    const destination = frame.arg(4);
    const capacity = frame.arg(5);
    if (destination == 0) {
        if (capacity != 0) {
            frame.finish(0);
            return;
        }
        frame.finish(@intCast(count));
        return;
    }
    if (capacity < count) {
        frame.finish(0);
        return;
    }
    const output = guestSlice(ctx, destination, count) orelse {
        frame.finish(0);
        return;
    };
    for (source, 0..) |byte, index| {
        const mapped = mapCase(cp1252Codepoint(byte), uppercase);
        output[index] = cp1252Byte(mapped) orelse '?';
    }
    frame.finish(@intCast(count));
}

fn nextWideCodepoint(source: []const u8, index: *usize) u21 {
    const first_offset = index.* * 2;
    const first = std.mem.readInt(u16, source[first_offset..][0..2], .little);
    index.* += 1;
    if (first >= 0xD800 and first <= 0xDBFF and index.* * 2 + 1 < source.len) {
        const next_offset = index.* * 2;
        const second = std.mem.readInt(u16, source[next_offset..][0..2], .little);
        if (second >= 0xDC00 and second <= 0xDFFF) {
            index.* += 1;
            return 0x10000 + (@as(u21, first - 0xD800) << 10) + @as(u21, second - 0xDC00);
        }
    }
    if (first >= 0xD800 and first <= 0xDFFF) return 0xFFFD;
    return first;
}

fn cp1252Byte(codepoint: u21) ?u8 {
    if (codepoint <= 0x7F or (codepoint >= 0xA0 and codepoint <= 0xFF)) return @intCast(codepoint);
    const special = [_]u21{
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    };
    for (special, 0x80..) |candidate, byte| {
        if (candidate == codepoint) return @intCast(byte);
    }
    return null;
}

fn encodeUtf8(codepoint: u21, output: *[4]u8) usize {
    if (codepoint <= 0x7F) {
        output[0] = @intCast(codepoint);
        return 1;
    }
    if (codepoint <= 0x7FF) {
        output[0] = @intCast(0xC0 | (codepoint >> 6));
        output[1] = @intCast(0x80 | (codepoint & 0x3F));
        return 2;
    }
    if (codepoint <= 0xFFFF) {
        output[0] = @intCast(0xE0 | (codepoint >> 12));
        output[1] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        output[2] = @intCast(0x80 | (codepoint & 0x3F));
        return 3;
    }
    output[0] = @intCast(0xF0 | (codepoint >> 18));
    output[1] = @intCast(0x80 | ((codepoint >> 12) & 0x3F));
    output[2] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
    output[3] = @intCast(0x80 | (codepoint & 0x3F));
    return 4;
}

fn appendWideAsBytes(
    source: []const u8,
    codepage: u32,
    fallback: u8,
    output: ?[]u8,
    output_index: *usize,
    used_default: *bool,
) void {
    var source_index: usize = 0;
    const unit_count = source.len / 2;
    while (source_index < unit_count) {
        const codepoint = nextWideCodepoint(source, &source_index);
        if (codepage == cp_utf8) {
            var encoded: [4]u8 = undefined;
            const encoded_count = encodeUtf8(codepoint, &encoded);
            if (output) |buffer| @memcpy(buffer[output_index.*..][0..encoded_count], encoded[0..encoded_count]);
            output_index.* += encoded_count;
        } else if (cp1252Byte(codepoint)) |byte| {
            if (output) |buffer| buffer[output_index.*] = byte;
            output_index.* += 1;
        } else {
            if (output) |buffer| buffer[output_index.*] = fallback;
            output_index.* += 1;
            used_default.* = true;
        }
    }
}

fn wideCharToMultiByte(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 8);
    const codepage = frame.arg(0);
    const source = wideSource(ctx, frame.arg(2), frame.arg(3)) orelse {
        frame.finish(0);
        return;
    };
    if (codepage != cp_acp and codepage != cp_windows_1252 and codepage != cp_utf8) {
        frame.finish(0);
        return;
    }

    const default_address = frame.arg(6);
    const fallback: u8 = if (default_address == 0) '?' else ctx.mem.read8(default_address);
    var required: usize = 0;
    var used_default = false;
    appendWideAsBytes(source, codepage, fallback, null, &required, &used_default);
    const destination = frame.arg(4);
    const capacity = frame.arg(5);
    if (destination == 0) {
        if (capacity != 0) {
            frame.finish(0);
            return;
        }
    } else {
        if (required > capacity) {
            frame.finish(0);
            return;
        }
        const output = guestSlice(ctx, destination, required) orelse {
            frame.finish(0);
            return;
        };
        var output_index: usize = 0;
        var ignored_default = false;
        appendWideAsBytes(source, codepage, fallback, output, &output_index, &ignored_default);
    }
    const used_default_address = frame.arg(7);
    if (used_default_address != 0) ctx.mem.write32(used_default_address, @intFromBool(used_default));
    frame.finish(@intCast(required));
}

fn cp1252Codepoint(byte: u8) u21 {
    if (byte < 0x80 or byte >= 0xA0) return byte;
    const special = [_]u21{
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    };
    return special[byte - 0x80];
}

fn nextUtf8Codepoint(source: []const u8, index: *usize) ?u21 {
    const first = source[index.*];
    const length: usize = if (first < 0x80) 1 else if (first & 0xE0 == 0xC0) 2 else if (first & 0xF0 == 0xE0) 3 else if (first & 0xF8 == 0xF0) 4 else return null;
    if (length > source.len - index.*) return null;
    const value = std.unicode.utf8Decode(source[index.* .. index.* + length]) catch return null;
    index.* += length;
    return value;
}

fn appendCodepointAsWide(codepoint: u21, output: ?[]u8, output_index: *usize) void {
    if (codepoint <= 0xFFFF) {
        if (output) |buffer| std.mem.writeInt(u16, buffer[output_index.*..][0..2], @intCast(codepoint), .little);
        output_index.* += 2;
        return;
    }
    const adjusted = codepoint - 0x10000;
    if (output) |buffer| {
        std.mem.writeInt(u16, buffer[output_index.*..][0..2], @intCast(0xD800 + (adjusted >> 10)), .little);
        std.mem.writeInt(u16, buffer[output_index.* + 2 ..][0..2], @intCast(0xDC00 + (adjusted & 0x3FF)), .little);
    }
    output_index.* += 4;
}

fn appendBytesAsWide(source: []const u8, codepage: u32, output: ?[]u8, output_index: *usize) ?void {
    var index: usize = 0;
    while (index < source.len) {
        const codepoint = if (codepage == cp_utf8)
            (nextUtf8Codepoint(source, &index) orelse return null)
        else blk: {
            const value = cp1252Codepoint(source[index]);
            index += 1;
            break :blk value;
        };
        appendCodepointAsWide(codepoint, output, output_index);
    }
}

fn multiByteToWideChar(ctx: *Executor) void {
    const frame = abi.CallFrame.raw(ctx, 6);
    const codepage = frame.arg(0);
    const source = byteSource(ctx, frame.arg(2), frame.arg(3)) orelse {
        frame.finish(0);
        return;
    };
    if (codepage != cp_acp and codepage != cp_windows_1252 and codepage != cp_utf8) {
        frame.finish(0);
        return;
    }
    var required: usize = 0;
    if (appendBytesAsWide(source, codepage, null, &required) == null) {
        frame.finish(0);
        return;
    }
    const destination = frame.arg(4);
    const capacity: usize = @intCast(frame.arg(5));
    if (destination == 0) {
        if (capacity != 0) {
            frame.finish(0);
            return;
        }
    } else {
        if (capacity > std.math.maxInt(usize) / 2 or required / 2 > capacity) {
            frame.finish(0);
            return;
        }
        const output = guestSlice(ctx, destination, required) orelse {
            frame.finish(0);
            return;
        };
        var output_index: usize = 0;
        if (appendBytesAsWide(source, codepage, output, &output_index) == null) {
            frame.finish(0);
            return;
        }
    }
    frame.finish(@intCast(required / 2));
}

pub fn register(ex: *Executor) void {
    ex.import_table.put("GetACP", getAcp) catch {};
    ex.import_table.put("GetOEMCP", getOemCp) catch {};
    ex.import_table.put("GetConsoleCP", getConsoleCp) catch {};
    ex.import_table.put("GetConsoleOutputCP", getConsoleCp) catch {};
    ex.import_table.put("IsValidCodePage", isValidCodePage) catch {};
    ex.import_table.put("GetCPInfo", getCpInfo) catch {};
    ex.import_table.put("GetStringTypeA", getStringTypeA) catch {};
    ex.import_table.put("GetStringTypeW", getStringTypeW) catch {};
    ex.import_table.put("LCMapStringA", lcMapStringA) catch {};
    ex.import_table.put("LCMapStringW", lcMapStringW) catch {};
    ex.import_table.put("WideCharToMultiByte", wideCharToMultiByte) catch {};
    ex.import_table.put("_WideCharToMultiByte@32", wideCharToMultiByte) catch {};
    ex.import_table.put("MultiByteToWideChar", multiByteToWideChar) catch {};
    ex.import_table.put("_MultiByteToWideChar@24", multiByteToWideChar) catch {};
}

test "Win32 code-page queries report stable Windows defaults and bounded CPINFO" {
    var ex = Executor.init(testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    register(&ex);

    ex.dispatch_import("GetACP");
    try testing.expectEqual(cp_windows_1252, ex.regs.eax);
    ex.dispatch_import("GetOEMCP");
    try testing.expectEqual(cp_oem_us, ex.regs.eax);
    ex.push(cp_utf8);
    ex.dispatch_import("IsValidCodePage");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    ex.push(65000);
    ex.dispatch_import("IsValidCodePage");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);

    ex.push(1024);
    ex.push(cp_utf8);
    ex.dispatch_import("GetCPInfo");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u32, 4), ex.mem.read32(1024));
    try testing.expectEqual(@as(u8, '?'), ex.mem.read8(1028));
    try testing.expectEqual(@as(u8, 0), ex.mem.read8(1029));
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 12), ex.mem.data[1030..1042]);
}

test "GetStringTypeA and GetStringTypeW return CTYPE1 flags for bounded strings" {
    var ex = Executor.init(testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.mem.write16(256, 'A');
    ex.mem.write16(258, 0);
    ex.mem.write8(260, ' ');
    register(&ex);

    ex.push(512); // lpCharType
    ex.push(1); // cchSrc
    ex.push(256); // lpSrcStr
    ex.push(1); // CT_CTYPE1
    ex.dispatch_import("GetStringTypeW");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u16, 0x0301), ex.mem.read16(512)); // C1_UPPER | C1_ALPHA | C1_DEFINED

    ex.push(514);
    ex.push(1);
    ex.push(260);
    ex.push(1);
    ex.dispatch_import("GetStringTypeA");
    try testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try testing.expectEqual(@as(u16, 0x0248), ex.mem.read16(514)); // C1_SPACE | C1_BLANK | C1_DEFINED
}

test "LCMapStringA and LCMapStringW map case and support bounded size queries" {
    var ex = Executor.init(testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.mem.write16(256, 'A');
    ex.mem.write16(258, 0);
    @memcpy(ex.mem.data[260..262], &.{ 'A', 0 });
    register(&ex);

    ex.push(0); // cchDest
    ex.push(0); // lpDestStr
    ex.push(2); // cchSrc
    ex.push(256); // lpSrcStr
    ex.push(0x100); // LCMAP_LOWERCASE
    ex.push(0); // Locale
    ex.dispatch_import("LCMapStringW");
    try testing.expectEqual(@as(u32, 2), ex.regs.eax);

    ex.push(2);
    ex.push(512);
    ex.push(2);
    ex.push(256);
    ex.push(0x100);
    ex.push(0);
    ex.dispatch_import("LCMapStringW");
    try testing.expectEqual(@as(u32, 2), ex.regs.eax);
    try testing.expectEqual(@as(u16, 'a'), ex.mem.read16(512));
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(514));

    ex.push(2);
    ex.push(768);
    ex.push(2);
    ex.push(260);
    ex.push(0x100);
    ex.push(0);
    ex.dispatch_import("LCMapStringA");
    try testing.expectEqual(@as(u32, 2), ex.regs.eax);
    try testing.expectEqualSlices(u8, &.{ 'a', 0 }, ex.mem.data[768..770]);
}

test "WideCharToMultiByte counts and writes UTF-8 including the requested terminator" {
    var ex = Executor.init(testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    ex.mem.write16(256, 0x00E9);
    ex.mem.write16(258, 0);
    register(&ex);

    ex.push(0); // lpUsedDefaultChar
    ex.push(0); // lpDefaultChar
    ex.push(0); // cbMultiByte
    ex.push(0); // lpMultiByteStr
    ex.push(2); // cchWideChar
    ex.push(256); // lpWideCharStr
    ex.push(0); // dwFlags
    ex.push(cp_utf8); // CodePage
    ex.dispatch_import("WideCharToMultiByte");
    try testing.expectEqual(@as(u32, 3), ex.regs.eax);

    ex.push(0); // lpUsedDefaultChar
    ex.push(0); // lpDefaultChar
    ex.push(3); // cbMultiByte
    ex.push(512); // lpMultiByteStr
    ex.push(2); // cchWideChar
    ex.push(256); // lpWideCharStr
    ex.push(0); // dwFlags
    ex.push(cp_utf8); // CodePage
    ex.dispatch_import("WideCharToMultiByte");
    try testing.expectEqual(@as(u32, 3), ex.regs.eax);
    try testing.expectEqualSlices(u8, &.{ 0xC3, 0xA9, 0 }, ex.mem.data[512..515]);
}

test "MultiByteToWideChar converts UTF-8 and rejects incomplete sequences" {
    var ex = Executor.init(testing.allocator, 4096);
    defer ex.deinit();
    ex.regs.esp = 3072;
    @memcpy(ex.mem.data[256..259], &.{ 0xC3, 0xA9, 0 });
    register(&ex);

    ex.push(2); // cchWideChar
    ex.push(512); // lpWideCharStr
    ex.push(3); // cbMultiByte
    ex.push(256); // lpMultiByteStr
    ex.push(0); // dwFlags
    ex.push(cp_utf8); // CodePage
    ex.dispatch_import("MultiByteToWideChar");
    try testing.expectEqual(@as(u32, 2), ex.regs.eax);
    try testing.expectEqual(@as(u16, 0x00E9), ex.mem.read16(512));
    try testing.expectEqual(@as(u16, 0), ex.mem.read16(514));

    ex.mem.data[256] = 0xC3;
    ex.push(2);
    ex.push(512);
    ex.push(1);
    ex.push(256);
    ex.push(0);
    ex.push(cp_utf8);
    ex.dispatch_import("MultiByteToWideChar");
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
}
