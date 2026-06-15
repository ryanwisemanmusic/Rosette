const std = @import("std");

pub const Section = enum { other, data, bss };

pub const SymbolDecl = struct {
    name: []const u8,
    section: Section,
    element_size: usize,
    element_count: usize,
    zero_initialized: bool,

    pub fn totalSize(self: SymbolDecl) usize {
        return self.element_size * self.element_count;
    }
};

const DataDirective = struct {
    element_size: usize,
    reserved: bool,
};

pub fn collect(allocator: std.mem.Allocator, source_text: []const u8) !std.ArrayList(SymbolDecl) {
    var declarations: std.ArrayList(SymbolDecl) = .empty;
    errdefer declarations.deinit(allocator);

    var section: Section = .other;
    var lines = std.mem.splitScalar(u8, source_text, '\n');
    while (lines.next()) |raw_line| {
        const line_without_comment = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, ';') orelse raw_line.len];
        const line = std.mem.trim(u8, line_without_comment, " \t\r\n");
        if (line.len == 0) continue;

        var pos: usize = 0;
        const first_raw = nextToken(line, &pos) orelse continue;
        if (std.ascii.eqlIgnoreCase(first_raw, "section")) {
            const section_name = nextToken(line, &pos) orelse "";
            section = parseSection(section_name);
            continue;
        }
        if (section == .other) continue;

        const name = stripTrailingColon(first_raw);
        if (name.len == 0) continue;
        if (parseDataDirective(name) != null) continue;

        const directive_token = nextToken(line, &pos) orelse continue;
        const directive = parseDataDirective(directive_token) orelse continue;
        const rest = std.mem.trim(u8, line[pos..], " \t\r\n");
        const element_count = if (directive.reserved)
            parseCount(rest)
        else
            countInitializers(rest);

        try declarations.append(allocator, .{
            .name = name,
            .section = section,
            .element_size = directive.element_size,
            .element_count = element_count,
            .zero_initialized = directive.reserved or initializersAllZero(rest),
        });
    }

    return declarations;
}

pub fn find(declarations: []const SymbolDecl, name: []const u8) ?SymbolDecl {
    for (declarations) |declaration| {
        if (std.mem.eql(u8, declaration.name, name)) return declaration;
    }
    return null;
}

fn parseDataDirective(token: []const u8) ?DataDirective {
    if (std.ascii.eqlIgnoreCase(token, "db")) return .{ .element_size = 1, .reserved = false };
    if (std.ascii.eqlIgnoreCase(token, "dw")) return .{ .element_size = 2, .reserved = false };
    if (std.ascii.eqlIgnoreCase(token, "dd")) return .{ .element_size = 4, .reserved = false };
    if (std.ascii.eqlIgnoreCase(token, "dq")) return .{ .element_size = 8, .reserved = false };
    if (std.ascii.eqlIgnoreCase(token, "ddq")) return .{ .element_size = 16, .reserved = false };
    if (std.ascii.eqlIgnoreCase(token, "resb")) return .{ .element_size = 1, .reserved = true };
    if (std.ascii.eqlIgnoreCase(token, "resw")) return .{ .element_size = 2, .reserved = true };
    if (std.ascii.eqlIgnoreCase(token, "resd")) return .{ .element_size = 4, .reserved = true };
    if (std.ascii.eqlIgnoreCase(token, "resq")) return .{ .element_size = 8, .reserved = true };
    if (std.ascii.eqlIgnoreCase(token, "resdq")) return .{ .element_size = 16, .reserved = true };
    return null;
}

fn parseSection(token: []const u8) Section {
    if (std.ascii.eqlIgnoreCase(token, ".data") or std.ascii.eqlIgnoreCase(token, "data")) return .data;
    if (std.ascii.eqlIgnoreCase(token, ".bss") or std.ascii.eqlIgnoreCase(token, "bss")) return .bss;
    return .other;
}

fn nextToken(line: []const u8, pos: *usize) ?[]const u8 {
    while (pos.* < line.len and std.ascii.isWhitespace(line[pos.*])) : (pos.* += 1) {}
    if (pos.* >= line.len) return null;
    const start = pos.*;
    while (pos.* < line.len and !std.ascii.isWhitespace(line[pos.*])) : (pos.* += 1) {}
    return line[start..pos.*];
}

fn stripTrailingColon(token: []const u8) []const u8 {
    if (token.len > 0 and token[token.len - 1] == ':') return token[0 .. token.len - 1];
    return token;
}

fn parseCount(rest: []const u8) usize {
    const trimmed = std.mem.trim(u8, rest, " \t\r\n");
    if (trimmed.len == 0) return 1;
    var end: usize = 0;
    while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) : (end += 1) {}
    if (end == 0) return 1;
    return std.fmt.parseInt(usize, trimmed[0..end], 10) catch 1;
}

fn countInitializers(rest: []const u8) usize {
    if (std.mem.trim(u8, rest, " \t\r\n").len == 0) return 1;
    var count: usize = 0;
    var values = std.mem.splitScalar(u8, rest, ',');
    while (values.next()) |value| {
        if (std.mem.trim(u8, value, " \t\r\n").len != 0) count += 1;
    }
    return @max(count, @as(usize, 1));
}

fn initializersAllZero(rest: []const u8) bool {
    var saw_value = false;
    var values = std.mem.splitScalar(u8, rest, ',');
    while (values.next()) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len == 0) continue;
        saw_value = true;
        if (!initializerIsZero(trimmed)) return false;
    }
    return saw_value;
}

fn initializerIsZero(value: []const u8) bool {
    var token_end: usize = 0;
    while (token_end < value.len and !std.ascii.isWhitespace(value[token_end])) : (token_end += 1) {}
    var token = value[0..token_end];
    if (token.len > 0 and token[0] == '+') token = token[1..];
    if (token.len == 0) return false;
    if (std.mem.eql(u8, token, "0")) return true;
    if (std.mem.startsWith(u8, token, "0x") or std.mem.startsWith(u8, token, "0X")) {
        for (token[2..]) |ch| {
            if (ch != '0') return false;
        }
        return token.len > 2;
    }
    for (token) |ch| {
        if (ch != '0') return false;
    }
    return true;
}

test "parses data and bss declarations without name-specific assumptions" {
    const source =
        \\section .data
        \\    scalar_word dw 0
        \\    scalar_byte db 75
        \\    mixed_words dw -1, 2, 3
        \\section .bss
        \\    qword_results resq 75
        \\    scratch resb 500000
    ;

    var declarations = try collect(std.testing.allocator, source);
    defer declarations.deinit(std.testing.allocator);

    const scalar_word = find(declarations.items, "scalar_word").?;
    try std.testing.expect(scalar_word.zero_initialized);
    try std.testing.expectEqual(@as(usize, 2), scalar_word.element_size);
    try std.testing.expectEqual(@as(usize, 1), scalar_word.element_count);

    const mixed_words = find(declarations.items, "mixed_words").?;
    try std.testing.expect(!mixed_words.zero_initialized);
    try std.testing.expectEqual(@as(usize, 2), mixed_words.element_size);
    try std.testing.expectEqual(@as(usize, 3), mixed_words.element_count);

    const qword_results = find(declarations.items, "qword_results").?;
    try std.testing.expectEqual(Section.bss, qword_results.section);
    try std.testing.expectEqual(@as(usize, 8), qword_results.element_size);
    try std.testing.expectEqual(@as(usize, 75), qword_results.element_count);

    const scratch = find(declarations.items, "scratch").?;
    try std.testing.expectEqual(@as(usize, 500000), scratch.totalSize());
}
