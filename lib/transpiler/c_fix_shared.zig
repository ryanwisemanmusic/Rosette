const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");
const types = @import("c_fix_types.zig");

const Token = c_tokenizer.Token;
const Edit = types.Edit;
const Line = types.Line;

pub fn isCompoundType(kind: Token.Kind) bool {
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

pub fn isTypeQualifier(kind: Token.Kind) bool {
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

pub fn isStorageClass(kind: Token.Kind) bool {
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

pub fn isNarrowType(kind: Token.Kind) bool {
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

pub fn isNarrowTypedefName(slice: []const u8) bool {
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

pub fn typeIsNarrow(tokens: []const Token, idx: usize, source: []const u8) bool {
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

pub fn isWideFunctionName(tok: Token, source: []const u8) bool {
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
        std.mem.eql(u8, slice, "offsetof") or
        std.mem.eql(u8, slice, "strtol") or
        std.mem.eql(u8, slice, "strtoll") or
        std.mem.eql(u8, slice, "strtoul") or
        std.mem.eql(u8, slice, "strtoull");
}

pub fn isWideExpressionStart(tok: Token, source: []const u8) bool {
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

pub fn isLikelyPointerReturningFunction(tok: Token, source: []const u8) bool {
    if (tok.kind != .identifier) return false;
    const slice = source[tok.start..tok.end];
    const allocation_markers = [_][]const u8{
        "alloc",
        "calloc",
        "malloc",
        "realloc",
    };
    for (allocation_markers) |marker| {
        if (std.mem.indexOf(u8, slice, marker) != null) return true;
    }
    return false;
}

pub fn skipToSemicolon(tokens: []const Token, start: usize) usize {
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

pub fn findMatchingClose(tokens: []const Token, start: usize) usize {
    var depth: u32 = 1;
    var i = start + 1;
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

pub fn findMatchingCloseGt(tokens: []const Token, start: usize) usize {
    var depth: u32 = 1;
    var i = start + 1;
    while (i < tokens.len) : (i += 1) {
        switch (tokens[i].kind) {
            .lt => depth += 1,
            .gt => {
                depth -= 1;
                if (depth == 0) return i;
            },
            .lparen, .lbrace, .lbracket => {
                const close = findMatchingClose(tokens, i);
                if (close >= tokens.len) return tokens.len;
                i = close;
            },
            else => {},
        }
    }
    return tokens.len;
}

pub fn isPointerSubtraction(tokens: []const Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (tokens[idx].kind != .identifier and tokens[idx].kind != .int_literal) return false;
    if (tokens[idx + 1].kind != .minus) return false;
    const third = tokens[idx + 2];
    return third.kind == .identifier or third.kind == .int_literal or third.kind == .string_literal;
}

pub fn isIdentifierToken(kind: Token.Kind) bool {
    return kind == .identifier;
}

pub fn isPreprocessorToken(kind: Token.Kind) bool {
    return switch (kind) {
        .hash,
        .pp_if,
        .pp_ifdef,
        .pp_ifndef,
        .pp_elif,
        .pp_else,
        .pp_endif,
        .pp_define,
        .pp_undef,
        .pp_include,
        => true,
        else => false,
    };
}

pub fn rangeContainsPreprocessor(tokens: []const Token, start: usize, end: usize) bool {
    if (start >= tokens.len or end >= tokens.len or end < start) return false;
    var i = start;
    while (i <= end and i < tokens.len) : (i += 1) {
        if (isPreprocessorToken(tokens[i].kind)) return true;
    }
    return false;
}

pub fn skipInitializerToDelim(tokens: []const Token, start: usize) usize {
    var depth: u32 = 0;
    var i = start;
    while (i < tokens.len) : (i += 1) {
        switch (tokens[i].kind) {
            .lparen, .lbrace, .lbracket => depth += 1,
            .rparen, .rbrace, .rbracket => {
                if (depth == 0) return i;
                depth -= 1;
            },
            .comma, .semicolon => {
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return tokens.len;
}

pub fn hasMaybeUnusedPrefix(tokens: []const Token, type_start: usize, source: []const u8) bool {
    const marker = "/* rosette-c-fix: maybe_unused */";
    if (type_start >= 5 and
        tokens[type_start - 5].kind == .lbracket and
        tokens[type_start - 4].kind == .lbracket and
        tokens[type_start - 3].kind == .identifier and
        std.mem.eql(u8, source[tokens[type_start - 3].start..tokens[type_start - 3].end], "maybe_unused") and
        tokens[type_start - 2].kind == .rbracket and
        tokens[type_start - 1].kind == .rbracket)
    {
        return true;
    }

    const type_start_byte = tokens[type_start].start;
    if (type_start_byte <= source.len) {
        const prefix = source[0..type_start_byte];
        const trimmed = std.mem.trim(u8, prefix, " \t\r\n");
        return std.mem.endsWith(u8, trimmed, marker);
    }
    return false;
}

pub fn nextLine(source: []const u8, start: usize) ?Line {
    if (start >= source.len) return null;
    const end = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
    return .{
        .start = start,
        .end = end,
        .next = if (end < source.len) end + 1 else end,
        .text = source[start..end],
    };
}

pub fn trimLine(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t\r\n");
}

pub fn includePath(line: []const u8) ?[]const u8 {
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

pub fn editOverlaps(edits: []const Edit, start: usize, end: usize) bool {
    for (edits) |edit| {
        if (start < edit.end and edit.start < end) return true;
        // Also detect zero-width insertions at the exact start position
        if (edit.start == start and edit.end == start and start < end) return true;
    }
    return false;
}

pub fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

pub fn identifierAppearsInSlice(slice: []const u8, name: []const u8) bool {
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, slice, pos, name)) |match| {
        const before_ok = match == 0 or !isIdentChar(slice[match - 1]);
        const after_index = match + name.len;
        const after_ok = after_index >= slice.len or !isIdentChar(slice[after_index]);
        if (before_ok and after_ok) return true;
        pos = match + name.len;
    }
    return false;
}

pub fn identifierAppearsAfter(source: []const u8, start: usize, name: []const u8) bool {
    var stack: [64]MacBranchState = undefined;
    var depth: usize = 0;

    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        pos = line.next;

        const trimmed = trimLine(line.text);
        if (macDirectiveState(trimmed)) |state| {
            if (depth < stack.len) {
                stack[depth] = state;
                depth += 1;
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "#else")) {
            if (depth > 0) {
                stack[depth - 1] = toggledMacBranchState(stack[depth - 1]);
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "#endif")) {
            if (depth > 0) depth -= 1;
            continue;
        }

        if (line.end <= start or !macBranchActive(stack[0..depth])) continue;
        const line_search_start = if (start > line.start) start - line.start else 0;
        if (line_search_start >= line.text.len) continue;
        if (identifierAppearsInSlice(line.text[line_search_start..], name)) return true;
    }
    return false;
}

const MacBranchState = enum {
    known_true,
    known_false,
    unknown,
};

pub fn macBranchActive(stack: []const MacBranchState) bool {
    for (stack) |state| {
        if (state == .known_false) return false;
    }
    return true;
}

pub fn macIfExpressionState(expr: []const u8) MacBranchState {
    const trimmed = std.mem.trim(u8, expr, " \t()");
    if (std.mem.indexOf(u8, trimmed, "__APPLE__") == null and
        std.mem.indexOf(u8, trimmed, "XE_PLATFORM_MACOS") == null)
    {
        return .unknown;
    }

    if (std.mem.indexOf(u8, trimmed, "!defined(__APPLE__)") != null or
        std.mem.indexOf(u8, trimmed, "! defined(__APPLE__)") != null or
        std.mem.indexOf(u8, trimmed, "!__APPLE__") != null or
        std.mem.indexOf(u8, trimmed, "!XE_PLATFORM_MACOS") != null or
        std.mem.indexOf(u8, trimmed, "XE_PLATFORM_MACOS == 0") != null or
        std.mem.indexOf(u8, trimmed, "XE_PLATFORM_MACOS != 1") != null)
    {
        return .known_false;
    }

    return .known_true;
}

pub fn macDirectiveState(trimmed: []const u8) ?MacBranchState {
    if (std.mem.startsWith(u8, trimmed, "#ifdef")) {
        const symbol = std.mem.trim(u8, trimmed["#ifdef".len..], " \t");
        if (std.mem.eql(u8, symbol, "__APPLE__") or
            std.mem.eql(u8, symbol, "XE_PLATFORM_MACOS"))
        {
            return .known_true;
        }
        return .unknown;
    }
    if (std.mem.startsWith(u8, trimmed, "#ifndef")) {
        const symbol = std.mem.trim(u8, trimmed["#ifndef".len..], " \t");
        if (std.mem.eql(u8, symbol, "__APPLE__") or
            std.mem.eql(u8, symbol, "XE_PLATFORM_MACOS"))
        {
            return .known_false;
        }
        return .unknown;
    }
    if (std.mem.startsWith(u8, trimmed, "#if")) {
        return macIfExpressionState(trimmed["#if".len..]);
    }
    return null;
}

pub fn toggledMacBranchState(state: MacBranchState) MacBranchState {
    return switch (state) {
        .known_true => .known_false,
        .known_false => .known_true,
        .unknown => .unknown,
    };
}
