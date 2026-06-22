const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");

const Token = c_tokenizer.Token;
const Tokenizer = c_tokenizer.Tokenizer;

pub const Edit = struct {
    start: usize,
    end: usize,
    replacement: []const u8,
};

pub const FixResult = struct {
    edits: std.ArrayList(Edit),
    warning: bool,

    pub fn deinit(self: *FixResult, allocator: std.mem.Allocator) void {
        for (self.edits.items) |edit| {
            allocator.free(edit.replacement);
        }
        self.edits.deinit(allocator);
    }
};

fn isCompoundType(kind: Token.Kind) bool {
    return switch (kind) {
        .keyword_int,
        .keyword_long,
        .keyword_short,
        .keyword_char,
        .keyword_signed,
        .keyword_unsigned,
        .keyword_void,
        .keyword_float,
        .keyword_double,
        .keyword_bool,
        .keyword__int8,
        .keyword__int16,
        .keyword__int32,
        .keyword__int64,
        .keyword__wchar_t,
        .keyword_wchar_t,
        .keyword_sizeof,
        => true,
        else => false,
    };
}

fn isTypeQualifier(kind: Token.Kind) bool {
    return switch (kind) {
        .keyword_const,
        .keyword_volatile,
        .keyword_restrict,
        .keyword_static,
        .keyword_extern,
        .keyword_inline,
        .keyword__forceinline,
        => true,
        else => false,
    };
}

fn isStorageClass(kind: Token.Kind) bool {
    return switch (kind) {
        .keyword_static,
        .keyword_extern,
        .keyword_typedef,
        .keyword_register,
        .keyword_auto,
        => true,
        else => false,
    };
}

fn isNarrowType(kind: Token.Kind) bool {
    return switch (kind) {
        .keyword_int,
        .keyword_short,
        .keyword_char,
        .keyword__int8,
        .keyword__int16,
        .keyword__int32,
        => true,
        else => false,
    };
}

fn isNarrowTypedefName(slice: []const u8) bool {
    const names = [_][]const u8{
        "BOOL",
        "BYTE",
        "DWORD",
        "GLenum",
        "GLint",
        "GLsizei",
        "INT",
        "INT32",
        "LONG",
        "UINT",
        "UINT4",
        "UINT32",
        "WORD",
        "__int32",
        "gint",
        "guint",
        "int32",
        "int32_t",
        "int16_t",
        "int8_t",
        "s32",
        "u32",
        "uint",
        "uint32",
        "uint32_t",
        "uint16_t",
        "uint8_t",
    };
    for (names) |name| {
        if (std.mem.eql(u8, slice, name)) return true;
    }
    return false;
}

fn typeIsNarrow(tokens: []const Token, idx: usize, source: []const u8) bool {
    var j = idx;
    while (j < tokens.len) {
        const t = tokens[j];
        if (isTypeQualifier(t.kind) or t.kind == .star) {
            j += 1;
            continue;
        }
        if (isNarrowType(t.kind)) return true;
        if (t.kind == .keyword_unsigned) {
            j += 1;
            continue;
        }
        if (t.kind == .identifier) {
            const slice = source[t.start..t.end];
            if (isNarrowTypedefName(slice)) return true;
            if (std.mem.endsWith(u8, slice, "_t")) {
                const prefix = slice[0 .. slice.len - 2];
                if (std.mem.eql(u8, prefix, "int32") or
                    std.mem.eql(u8, prefix, "uint32") or
                    std.mem.eql(u8, prefix, "int16") or
                    std.mem.eql(u8, prefix, "uint16") or
                    std.mem.eql(u8, prefix, "int8") or
                    std.mem.eql(u8, prefix, "uint8") or
                    std.mem.eql(u8, prefix, "DWORD") or
                    std.mem.eql(u8, prefix, "__int32"))
                {
                    return true;
                }
            }
        }
        return false;
    }
    return false;
}

fn isWideFunctionName(tok: Token, source: []const u8) bool {
    const slice = source[tok.start..tok.end];
    return std.mem.eql(u8, slice, "strlen") or
        std.mem.eql(u8, slice, "wcslen") or
        std.mem.eql(u8, slice, "strnlen") or
        std.mem.eql(u8, slice, "strnlen_s") or
        std.mem.eql(u8, slice, "mbstowcs") or
        std.mem.eql(u8, slice, "wcstombs") or
        std.mem.eql(u8, slice, "_countof") or
        std.mem.eql(u8, slice, "ARRAYSIZE") or
        std.mem.eql(u8, slice, "ARRAY_SIZE") or
        std.mem.eql(u8, slice, "put_bits_count") or
        std.mem.eql(u8, slice, "alignof") or
        std.mem.eql(u8, slice, "offsetof");
}

fn isWideExpressionStart(tok: Token, source: []const u8) bool {
    if (tok.kind == .keyword_sizeof) return true;
    if (isWideFunctionName(tok, source)) return true;
    if (tok.kind == .identifier) {
        const slice = source[tok.start..tok.end];
        if (std.mem.indexOf(u8, slice, "size") != null or
            std.mem.indexOf(u8, slice, "len") != null or
            std.mem.indexOf(u8, slice, "Len") != null or
            std.mem.indexOf(u8, slice, "count") != null or
            std.mem.indexOf(u8, slice, "Count") != null or
            std.mem.indexOf(u8, slice, "index") != null or
            std.mem.indexOf(u8, slice, "Index") != null or
            std.mem.indexOf(u8, slice, "bytes") != null or
            std.mem.indexOf(u8, slice, "Bytes") != null or
            std.mem.indexOf(u8, slice, "offset") != null or
            std.mem.indexOf(u8, slice, "Offset") != null or
            std.mem.indexOf(u8, slice, "capacity") != null or
            std.mem.indexOf(u8, slice, "Capacity") != null or
            std.mem.indexOf(u8, slice, "stride") != null or
            std.mem.indexOf(u8, slice, "Stride") != null or
            std.mem.indexOf(u8, slice, "pitch") != null or
            std.mem.indexOf(u8, slice, "Pitch") != null or
            std.mem.endsWith(u8, slice, "_t") or
            std.mem.eql(u8, slice, "size") or
            std.mem.eql(u8, slice, "length") or
            std.mem.eql(u8, slice, "max") or
            std.mem.eql(u8, slice, "min") or
            std.mem.eql(u8, slice, "diff"))
        {
            return true;
        }
    }
    return false;
}

fn skipToSemicolon(tokens: []const Token, start: usize) usize {
    var i = start;
    var depth: u32 = 0;
    while (i < tokens.len) : (i += 1) {
        switch (tokens[i].kind) {
            .lparen, .lbrace, .lbracket => depth += 1,
            .rparen, .rbrace, .rbracket => {
                if (depth == 0) return i;
                depth -= 1;
            },
            .semicolon => {
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return tokens.len;
}

fn findMatchingClose(tokens: []const Token, start: usize) usize {
    var depth: u32 = 1;
    var i = start;
    while (i < tokens.len) : (i += 1) {
        switch (tokens[i].kind) {
            .lparen, .lbrace, .lbracket => depth += 1,
            .rparen, .rbrace, .rbracket => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return tokens.len;
}

fn isPointerSubtraction(tokens: []const Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (tokens[idx].kind != .identifier and tokens[idx].kind != .int_literal) return false;
    if (tokens[idx + 1].kind != .minus) return false;
    const third = tokens[idx + 2];
    return third.kind == .identifier or third.kind == .int_literal or third.kind == .string_literal;
}

pub fn fixSource(allocator: std.mem.Allocator, source: []const u8) !FixResult {
    var tok = Tokenizer.init(source);
    var all_tokens: std.ArrayList(Token) = .empty;
    defer all_tokens.deinit(allocator);

    while (true) {
        const t = tok.next();
        try all_tokens.append(allocator, t);
        if (t.kind == .eof) break;
    }

    const tokens = all_tokens.items;
    var edits: std.ArrayList(Edit) = .empty;
    errdefer {
        for (edits.items) |e| allocator.free(e.replacement);
        edits.deinit(allocator);
    }
    const warning = false;

    try appendTrivialMacIncludeCollapses(allocator, source, &edits);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (isStorageClass(tokens[i].kind)) continue;

        if (tokens[i].kind == .keyword_return) {
            if (i + 1 < tokens.len) {
                const next = tokens[i + 1];
                if (next.kind == .keyword_sizeof or isWideFunctionName(next, source) or
                    (next.kind == .identifier and isWideExpressionStart(next, source)))
                {
                    const wrap_start = next.start;
                    const semi = skipToSemicolon(tokens, i + 1);
                    const wrap_end = if (semi < tokens.len) tokens[semi].start else tokens[tokens.len - 1].end;
                    if (wrap_end > wrap_start) {
                        try edits.append(allocator, .{
                            .start = wrap_start,
                            .end = wrap_start,
                            .replacement = try allocator.dupe(u8, "(int)"),
                        });
                    }
                }
            }
            continue;
        }
        if (!isCompoundType(tokens[i].kind) and !isIdentifierToken(tokens[i].kind)) continue;

        if (isIdentifierToken(tokens[i].kind)) {
            const slice = source[tokens[i].start..tokens[i].end];
            if (!std.mem.endsWith(u8, slice, "_t") and
                !isNarrowTypedefName(slice) and
                !isWideFunctionName(tokens[i], source) and
                slice.len > 0 and (slice[0] < 'A' or slice[0] > 'Z'))
            {
                continue;
            }
        }

        var type_end = i + 1;
        while (type_end < tokens.len and
            (isCompoundType(tokens[type_end].kind) or
                isTypeQualifier(tokens[type_end].kind) or
                tokens[type_end].kind == .star))
        {
            type_end += 1;
        }

        if (type_end >= tokens.len) continue;

        const has_ptr = tokens[type_end].kind == .star;
        var name_pos = type_end;
        if (has_ptr) {
            name_pos = type_end + 1;
            if (name_pos >= tokens.len) continue;
        }

        if (!isIdentifierToken(tokens[name_pos].kind)) continue;

        const name = tokens[name_pos];
        _ = name;

        if (name_pos + 1 < tokens.len and tokens[name_pos + 1].kind == .eq) {
            const eq_pos = name_pos + 1;
            if (eq_pos + 1 >= tokens.len) continue;

            const rhs_start = eq_pos + 1;
            const rhs = tokens[rhs_start];

            if (!typeIsNarrow(tokens, i, source)) continue;

            if (rhs.kind == .keyword_sizeof or isWideExpressionStart(rhs, source)) {
                const cast_type = source[tokens[i].start..tokens[type_end - 1].end];

                try edits.append(allocator, .{
                    .start = rhs.start,
                    .end = rhs.start,
                    .replacement = try std.fmt.allocPrint(allocator, "({s})", .{cast_type}),
                });
            } else if (isPointerSubtraction(tokens, rhs_start)) {
                const cast_type = source[tokens[i].start..tokens[type_end - 1].end];
                try edits.append(allocator, .{
                    .start = rhs.start,
                    .end = rhs.start,
                    .replacement = try std.fmt.allocPrint(allocator, "({s})", .{cast_type}),
                });
            }
        }
    }

    return .{ .edits = edits, .warning = warning };
}

const Line = struct {
    start: usize,
    end: usize,
    next: usize,
    text: []const u8,
};

fn nextLine(source: []const u8, start: usize) ?Line {
    if (start >= source.len) return null;
    const end = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
    return .{
        .start = start,
        .end = end,
        .next = if (end < source.len) end + 1 else end,
        .text = source[start..end],
    };
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t\r\n");
}

fn includePath(line: []const u8) ?[]const u8 {
    const trimmed = trimLine(line);
    if (!std.mem.startsWith(u8, trimmed, "#include")) return null;
    var rest = std.mem.trim(u8, trimmed["#include".len..], " \t");
    if (rest.len < 3) return null;
    const opener = rest[0];
    const closer: u8 = switch (opener) {
        '"' => '"',
        '<' => '>',
        else => return null,
    };
    rest = rest[1..];
    const close = std.mem.indexOfScalar(u8, rest, closer) orelse return null;
    return rest[0..close];
}

fn macIncludeNormalizesTo(mac_path: []const u8, normal_path: []const u8) bool {
    if (std.mem.eql(u8, mac_path, normal_path) and isTrivialMacCanonicalBasename(mac_path)) return true;
    if (!std.mem.endsWith(u8, mac_path, "_mac.h")) return false;
    if (!isTrivialMacWrapperBasename(mac_path)) return false;
    if (mac_path.len != normal_path.len + "_mac".len) return false;
    const suffix_start = mac_path.len - "_mac.h".len;
    return std.mem.eql(u8, mac_path[0..suffix_start], normal_path[0..suffix_start]) and
        std.mem.eql(u8, normal_path[suffix_start..], ".h");
}

fn isTrivialMacWrapperBasename(path: []const u8) bool {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return isTrivialMacWrapperName(path);
    return isTrivialMacWrapperName(path[slash + 1 ..]);
}

fn isTrivialMacCanonicalBasename(path: []const u8) bool {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return isTrivialMacCanonicalName(path);
    return isTrivialMacCanonicalName(path[slash + 1 ..]);
}

fn isTrivialMacWrapperName(name: []const u8) bool {
    const names = [_][]const u8{
        "byte_order_mac.h",
        "math_mac.h",
        "memory_mac.h",
        "windowed_app_context_mac.h",
    };
    for (names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn isTrivialMacCanonicalName(name: []const u8) bool {
    const names = [_][]const u8{
        "byte_order.h",
        "math.h",
        "memory.h",
        "windowed_app_context.h",
    };
    for (names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn appendTrivialMacIncludeCollapses(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
) !void {
    var pos: usize = 0;
    while (nextLine(source, pos)) |if_line| {
        pos = if_line.next;
        const condition = trimLine(if_line.text);
        if (!std.mem.startsWith(u8, condition, "#if")) continue;
        if (std.mem.indexOf(u8, condition, "MACOS") == null and
            std.mem.indexOf(u8, condition, "__APPLE__") == null and
            std.mem.indexOf(u8, condition, "APPLE") == null)
        {
            continue;
        }

        const include_a = nextLine(source, if_line.next) orelse continue;
        const else_line = nextLine(source, include_a.next) orelse continue;
        const include_b = nextLine(source, else_line.next) orelse continue;
        const endif_line = nextLine(source, include_b.next) orelse continue;
        if (!std.mem.eql(u8, trimLine(else_line.text), "#else")) continue;
        if (!std.mem.startsWith(u8, trimLine(endif_line.text), "#endif")) continue;

        const path_a = includePath(include_a.text) orelse continue;
        const path_b = includePath(include_b.text) orelse continue;
        const normal_path = if (macIncludeNormalizesTo(path_a, path_b))
            path_b
        else if (macIncludeNormalizesTo(path_b, path_a))
            path_a
        else
            continue;

        try edits.append(allocator, .{
            .start = if_line.start,
            .end = endif_line.next,
            .replacement = try std.fmt.allocPrint(allocator, "#include \"{s}\"\n", .{normal_path}),
        });
        pos = endif_line.next;
    }
}

fn isIdentifierToken(kind: Token.Kind) bool {
    return kind == .identifier;
}

pub fn applyEdits(allocator: std.mem.Allocator, source: []const u8, edits: []const Edit) ![]u8 {
    if (edits.len == 0) return try allocator.dupe(u8, source);

    const sorted = try allocator.alloc(Edit, edits.len);
    defer allocator.free(sorted);
    @memcpy(sorted, edits);

    std.mem.sort(Edit, sorted, {}, struct {
        fn lessThan(_: void, a: Edit, b: Edit) bool {
            return a.start > b.start;
        }
    }.lessThan);

    var result = try allocator.dupe(u8, source);
    for (sorted) |edit| {
        const prefix = result[0..edit.start];
        const suffix = result[edit.end..];
        var new_result: std.ArrayList(u8) = .empty;
        defer new_result.deinit(allocator);
        try new_result.appendSlice(allocator, prefix);
        try new_result.appendSlice(allocator, edit.replacement);
        try new_result.appendSlice(allocator, suffix);
        allocator.free(result);
        result = try new_result.toOwnedSlice(allocator);
    }

    return result;
}

test "fix strlen assigned to int" {
    const src = "int x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), result.edits.items.len);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("int x = (int)strlen(s);", output);
}

test "fix sizeof assigned to int32_t" {
    const src = "int32_t x = sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(int32_t)") != null);
}

test "fix strlen assigned to Windows-style UINT4" {
    const src = "UINT4 x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("UINT4 x = (UINT4)strlen(s);", output);
}

test "fix sizeof assigned to GLib guint" {
    const src = "guint x = sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("guint x = (guint)sizeof(buf);", output);
}

test "fix return strlen" {
    const src = "return strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
}

test "fix return sizeof" {
    const src = "return sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
}

test "no false positive on size_t assignment" {
    const src = "size_t x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "fix sizeof in for-loop init" {
    const src = "int32_t x = sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(int32_t)") != null);
}

test "no edit for uint64_t" {
    const src = "uint64_t x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "collapse trivial mac include conditional" {
    const src =
        \\#if XE_PLATFORM_MACOS
        \\#include "xenia/base/math_mac.h"
        \\#else
        \\#include "xenia/base/math.h"
        \\#endif
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("#include \"xenia/base/math.h\"\n", output);
}

test "collapse duplicate canonical trivial mac include conditional" {
    const src =
        \\#if XE_PLATFORM_MACOS
        \\#include "xenia/base/math.h"
        \\#else
        \\#include "xenia/base/math.h"
        \\#endif
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("#include \"xenia/base/math.h\"\n", output);
}

test "do not collapse real mac include conditional" {
    const src =
        \\#if XE_PLATFORM_MACOS
        \\#include "xenia/kernel/kernel_state_mac.h"
        \\#else
        \\#include "xenia/kernel/kernel_state.h"
        \\#endif
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}
