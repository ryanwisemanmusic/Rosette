const std = @import("std");
const types = @import("types.zig");

const Value = types.Value;
const Table = types.Table;
const ParseError = types.ParseError;
const MAX_SOURCE_BYTES: usize = 64 * 1024 * 1024;

pub const Diagnostic = struct {
    byte_offset: usize,
    line: usize,
    column: usize,
    context_start: usize,
    context: []const u8,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,
    line: usize,
    line_start: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return .{ .allocator = allocator, .source = source, .pos = 0, .line = 1, .line_start = 0 };
    }

    pub fn parse(root: *Parser) ParseError!Table {
        if (root.source.len > MAX_SOURCE_BYTES) return ParseError.FileTooLarge;
        if (!std.unicode.utf8ValidateSlice(root.source)) {
            root.pos = firstInvalidUtf8Offset(root.source);
            root.recomputeLocation();
            return ParseError.InvalidUtf8;
        }
        if (std.mem.indexOfScalar(u8, root.source, 0)) |offset| {
            root.pos = offset;
            root.recomputeLocation();
            return ParseError.EmbeddedNul;
        }
        // A UTF-8 BOM is not content. Accept it at byte zero only and keep
        // diagnostics byte-accurate for the original file.
        if (root.pos == 0 and std.mem.startsWith(u8, root.source, "\xEF\xBB\xBF")) {
            root.pos = 3;
            root.line_start = 3;
        }
        var table = Table.init();
        errdefer table.deinit(root.allocator);
        var current_table: *Table = &table;

        while (root.pos < root.source.len) {
            root.skipWhitespaceAndNewlines();
            if (root.pos >= root.source.len) break;

            const ch = root.source[root.pos];
            if (ch == '#') {
                root.skipComment();
                continue;
            }

            if (ch == '[') {
                const is_array_table = root.pos + 1 < root.source.len and root.source[root.pos + 1] == '[';
                if (is_array_table) {
                    root.pos += 2;
                    const path = try root.parseTableKey(.array_of_tables);
                    const path_parts = try root.splitPath(path);
                    defer root.allocator.free(path_parts);

                    var target = &table;
                    for (path_parts[0 .. path_parts.len - 1]) |part| {
                        const arr = target.getTableArrayMut(part) orelse blk: {
                            const created = try target.getOrCreateTableArray(root.allocator, part);
                            try created.append(root.allocator, Table.init());
                            break :blk created;
                        };
                        if (arr.items.len == 0) {
                            try arr.append(root.allocator, Table.init());
                        }
                        target = &arr.items[arr.items.len - 1];
                    }

                    const last_key = path_parts[path_parts.len - 1];
                    const arr = try target.getOrCreateTableArray(root.allocator, last_key);
                    const sub_table = Table.init();
                    try arr.append(root.allocator, sub_table);
                    current_table = &arr.items[arr.items.len - 1];
                } else {
                    root.pos += 1;
                    const path = try root.parseTableKey(.table);
                    const path_parts = try root.splitPath(path);
                    defer root.allocator.free(path_parts);

                    current_table = &table;
                    for (path_parts) |part| {
                        const table_arr = current_table.getTableArrayMut(part);
                        const entry = current_table.getPtr(part);
                        if (table_arr) |arr| {
                            if (arr.items.len == 0) return ParseError.InvalidTableHeader;
                            current_table = &arr.items[arr.items.len - 1];
                        } else if (entry) |e| {
                            current_table = &e.table;
                        } else {
                            const sub = Table.init();
                            try current_table.put(root.allocator, part, .{ .table = sub });
                            current_table = &current_table.getPtr(part).?.table;
                        }
                    }
                }
                continue;
            }

            const key = try root.parseKey();
            try root.expect('=');
            root.skipWhitespace();
            const value = try root.parseValue();
            try current_table.put(root.allocator, key, value);

            root.skipWhitespace();
            if (root.pos < root.source.len and root.source[root.pos] == '#') {
                root.skipComment();
            } else if (root.pos < root.source.len and root.source[root.pos] != '\n' and root.source[root.pos] != '\r') {
                return ParseError.UnexpectedToken;
            }
        }

        return table;
    }

    pub fn diagnostic(parser: *const Parser) Diagnostic {
        const start = parser.pos -| 24;
        const end = @min(parser.source.len, parser.pos +| 24);
        return .{
            .byte_offset = parser.pos,
            .line = parser.line,
            .column = parser.pos -| parser.line_start + 1,
            .context_start = start,
            .context = parser.source[start..end],
        };
    }

    fn recomputeLocation(parser: *Parser) void {
        parser.line = 1;
        parser.line_start = 0;
        var index: usize = 0;
        while (index < parser.pos) : (index += 1) {
            if (parser.source[index] == '\n') {
                parser.line += 1;
                parser.line_start = index + 1;
            } else if (parser.source[index] == '\r') {
                if (index + 1 < parser.pos and parser.source[index + 1] == '\n') index += 1;
                parser.line += 1;
                parser.line_start = index + 1;
            }
        }
    }

    fn skipWhitespace(parser: *Parser) void {
        while (parser.pos < parser.source.len and (parser.source[parser.pos] == ' ' or parser.source[parser.pos] == '\t')) {
            parser.pos += 1;
        }
    }

    fn skipWhitespaceAndNewlines(parser: *Parser) void {
        while (parser.pos < parser.source.len) {
            switch (parser.source[parser.pos]) {
                ' ', '\t' => parser.pos += 1,
                '\n' => {
                    parser.pos += 1;
                    parser.line += 1;
                    parser.line_start = parser.pos;
                },
                '\r' => {
                    parser.pos += 1;
                    if (parser.pos < parser.source.len and parser.source[parser.pos] == '\n') parser.pos += 1;
                    parser.line += 1;
                    parser.line_start = parser.pos;
                },
                else => break,
            }
        }
    }

    fn skipComment(parser: *Parser) void {
        while (parser.pos < parser.source.len and parser.source[parser.pos] != '\n') parser.pos += 1;
    }

    fn skipArrayWhitespaceAndComments(parser: *Parser) void {
        while (true) {
            parser.skipWhitespaceAndNewlines();
            if (parser.pos >= parser.source.len or parser.source[parser.pos] != '#') return;
            parser.skipComment();
        }
    }

    fn expect(parser: *Parser, ch: u8) ParseError!void {
        parser.skipWhitespace();
        if (parser.pos >= parser.source.len or parser.source[parser.pos] != ch) return ParseError.UnexpectedToken;
        parser.pos += 1;
    }

    fn parseKey(parser: *Parser) ParseError![]const u8 {
        parser.skipWhitespace();
        const start = parser.pos;
        while (parser.pos < parser.source.len) {
            const ch = parser.source[parser.pos];
            switch (ch) {
                'A'...'Z', 'a'...'z', '0'...'9', '_', '-', '.' => parser.pos += 1,
                else => break,
            }
        }
        if (parser.pos == start) return ParseError.InvalidCharacter;
        return parser.source[start..parser.pos];
    }

    fn parseTableKey(parser: *Parser, comptime kind: enum { table, array_of_tables }) ParseError![]const u8 {
        parser.skipWhitespace();
        const start = parser.pos;
        while (parser.pos < parser.source.len) {
            const ch = parser.source[parser.pos];
            switch (ch) {
                'A'...'Z', 'a'...'z', '0'...'9', '_', '-', '.' => parser.pos += 1,
                ']' => break,
                else => return ParseError.InvalidTableHeader,
            }
        }
        if (parser.pos == start) return ParseError.InvalidTableHeader;
        const end = parser.pos;
        parser.skipWhitespace();
        try parser.expect(']');
        if (kind == .array_of_tables) try parser.expect(']');
        return parser.source[start..end];
    }

    fn parseValue(parser: *Parser) ParseError!Value {
        parser.skipWhitespace();
        if (parser.pos >= parser.source.len) return ParseError.InvalidValue;
        const ch = parser.source[parser.pos];
        switch (ch) {
            '"' => return parser.parseString(),
            't', 'f' => return parser.parseBoolean(),
            '[' => return parser.parseInlineArray(),
            '0' => {
                if (parser.pos + 1 < parser.source.len and parser.source[parser.pos + 1] == 'x') return parser.parseHexInt();
                return parser.parseInteger();
            },
            '+', '-', '1'...'9' => return parser.parseInteger(),
            else => return ParseError.InvalidValue,
        }
    }

    fn parseString(parser: *Parser) ParseError!Value {
        if (parser.pos >= parser.source.len or parser.source[parser.pos] != '"') return ParseError.UnterminatedString;
        parser.pos += 1;
        var result = std.ArrayList(u8).empty;
        errdefer result.deinit(parser.allocator);
        while (parser.pos < parser.source.len) {
            const ch = parser.source[parser.pos];
            switch (ch) {
                '"' => {
                    parser.pos += 1;
                    return .{ .string = try result.toOwnedSlice(parser.allocator) };
                },
                '\\' => {
                    parser.pos += 1;
                    if (parser.pos >= parser.source.len) return ParseError.InvalidEscape;
                    const escaped: u8 = switch (parser.source[parser.pos]) {
                        '"' => '"',
                        '\\' => '\\',
                        'n' => '\n',
                        'r' => '\r',
                        't' => '\t',
                        else => return ParseError.InvalidEscape,
                    };
                    try result.append(parser.allocator, escaped);
                    parser.pos += 1;
                },
                '\n' => return ParseError.UnterminatedString,
                else => {
                    try result.append(parser.allocator, ch);
                    parser.pos += 1;
                },
            }
        }
        return ParseError.UnterminatedString;
    }

    fn parseBoolean(parser: *Parser) ParseError!Value {
        if (parser.pos + 3 < parser.source.len and std.mem.eql(u8, parser.source[parser.pos..][0..4], "true")) {
            parser.pos += 4;
            return .{ .boolean = true };
        }
        if (parser.pos + 4 < parser.source.len and std.mem.eql(u8, parser.source[parser.pos..][0..5], "false")) {
            parser.pos += 5;
            return .{ .boolean = false };
        }
        return ParseError.InvalidValue;
    }

    fn parseInteger(parser: *Parser) ParseError!Value {
        const start = parser.pos;
        if (parser.pos < parser.source.len and (parser.source[parser.pos] == '-' or parser.source[parser.pos] == '+')) parser.pos += 1;
        const digits_start = parser.pos;
        while (parser.pos < parser.source.len) {
            const ch = parser.source[parser.pos];
            switch (ch) {
                '0'...'9', '_' => parser.pos += 1,
                else => break,
            }
        }
        if (parser.pos == digits_start) return ParseError.InvalidValue;
        const slice = parser.source[start..parser.pos];
        const cleaned = try std.mem.replaceOwned(u8, parser.allocator, slice, "_", "");
        defer parser.allocator.free(cleaned);
        const val = std.fmt.parseInt(i64, cleaned, 10) catch return ParseError.IntegerOverflow;
        return .{ .integer = val };
    }

    fn parseHexInt(parser: *Parser) ParseError!Value {
        const start = parser.pos;
        parser.pos += 2;
        while (parser.pos < parser.source.len) {
            const ch = parser.source[parser.pos];
            switch (ch) {
                '0'...'9', 'a'...'f', 'A'...'F', '_' => parser.pos += 1,
                else => break,
            }
        }
        const slice = parser.source[start..parser.pos];
        const cleaned = try std.mem.replaceOwned(u8, parser.allocator, slice, "_", "");
        defer parser.allocator.free(cleaned);
        const val = std.fmt.parseInt(i64, cleaned, 0) catch return ParseError.IntegerOverflow;
        return .{ .integer = val };
    }

    fn parseInlineArray(parser: *Parser) ParseError!Value {
        parser.pos += 1;
        var arr = std.ArrayListUnmanaged(Value).empty;
        errdefer {
            for (arr.items) |*item| item.deinit(parser.allocator);
            arr.deinit(parser.allocator);
        }
        parser.skipArrayWhitespaceAndComments();
        if (parser.pos < parser.source.len and parser.source[parser.pos] == ']') {
            parser.pos += 1;
            return .{ .array = arr };
        }
        while (true) {
            const val = try parser.parseValue();
            try arr.append(parser.allocator, val);
            parser.skipArrayWhitespaceAndComments();
            if (parser.pos >= parser.source.len) return ParseError.UnterminatedArray;
            if (parser.source[parser.pos] == ']') {
                parser.pos += 1;
                return .{ .array = arr };
            }
            if (parser.source[parser.pos] != ',') return ParseError.UnexpectedToken;
            parser.pos += 1;
            parser.skipArrayWhitespaceAndComments();
        }
        return ParseError.UnterminatedArray;
    }

    fn splitPath(parser: *Parser, path: []const u8) ParseError![]const []const u8 {
        var parts = std.ArrayList([]const u8).empty;
        var it = std.mem.splitScalar(u8, path, '.');
        while (it.next()) |part| try parts.append(parser.allocator, part);
        return parts.toOwnedSlice(parser.allocator);
    }
};

fn firstInvalidUtf8Offset(source: []const u8) usize {
    var index: usize = 0;
    while (index < source.len) {
        const sequence_length = std.unicode.utf8ByteSequenceLength(source[index]) catch return index;
        if (index + sequence_length > source.len) return index;
        _ = std.unicode.utf8Decode(source[index..][0..sequence_length]) catch return index;
        index += sequence_length;
    }
    return source.len;
}

test "nested array tables create and select their parent table" {
    const testing = std.testing;
    var parser = Parser.init(
        testing.allocator,
        "[[fruit]]\n" ++
            "name = \"apple\"\n" ++
            "[[fruit.variety]]\n" ++
            "name = \"red delicious\"\n",
    );
    var table = try parser.parse();
    defer table.deinit(testing.allocator);

    const fruit = table.getTableArray("fruit") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(usize, 1), fruit.items.len);
    const varieties = fruit.items[0].getTableArray("variety") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(usize, 1), varieties.items.len);
    try testing.expectEqualStrings("red delicious", varieties.items[0].get("name").?.string);
}

test "signed integers retain their source sign" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, "negative = -42\npositive = +42\n");
    var table = try parser.parse();
    defer table.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, -42), table.get("negative").?.integer);
    try testing.expectEqual(@as(i64, 42), table.get("positive").?.integer);
}

test "inline arrays accept line breaks and comments" {
    const testing = std.testing;
    var parser = Parser.init(
        testing.allocator,
        "hash = [\n" ++
            "    \"A3FF\" # default.xex\n" ++
            "    # \"disabled\"\n" ++
            "]\n",
    );
    var table = try parser.parse();
    defer table.deinit(testing.allocator);

    const hash = &table.get("hash").?.array;
    try testing.expectEqual(@as(usize, 1), hash.items.len);
    try testing.expectEqualStrings("A3FF", hash.items[0].string);
}

test "parser rejects invalid UTF-8 with an exact byte diagnostic" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, "title = \"ok\"\nname = \"\xFF\"\n");
    try testing.expectError(ParseError.InvalidUtf8, parser.parse());
    const diagnostic_info = parser.diagnostic();
    try testing.expectEqual(@as(usize, 21), diagnostic_info.byte_offset);
    try testing.expectEqual(@as(usize, 2), diagnostic_info.line);
    try testing.expectEqual(@as(usize, 9), diagnostic_info.column);
}

test "parser rejects embedded NUL before token parsing" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, "title = \"ok\"\x00\n");
    try testing.expectError(ParseError.EmbeddedNul, parser.parse());
    try testing.expectEqual(@as(usize, 12), parser.diagnostic().byte_offset);
}

test "parser accepts one leading UTF-8 BOM" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, "\xEF\xBB\xBFtitle = \"ok\"\n");
    var table = try parser.parse();
    defer table.deinit(testing.allocator);
    try testing.expectEqualStrings("ok", table.get("title").?.string);
}
