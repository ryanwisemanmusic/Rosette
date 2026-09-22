const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");
const types = @import("c_fix_types.zig");
const shared = @import("c_fix_shared.zig");

const Token = c_tokenizer.Token;
const Edit = types.Edit;
const editOverlaps = shared.editOverlaps;
const findMatchingClose = shared.findMatchingClose;
const findMatchingCloseGt = shared.findMatchingCloseGt;
const isCompoundType = shared.isCompoundType;
const isIdentifierToken = shared.isIdentifierToken;
const isNarrowTypedefName = shared.isNarrowTypedefName;
const isTypeQualifier = shared.isTypeQualifier;
const skipToSemicolon = shared.skipToSemicolon;

fn primitiveSize(name: []const u8) ?usize {
    const trimmed = std.mem.trim(u8, name, " \t");
    if (std.mem.eql(u8, trimmed, "char") or
        std.mem.eql(u8, trimmed, "signed char") or
        std.mem.eql(u8, trimmed, "unsigned char") or
        std.mem.eql(u8, trimmed, "uint8_t") or
        std.mem.eql(u8, trimmed, "int8_t") or
        std.mem.eql(u8, trimmed, "BYTE"))
    {
        return 1;
    }
    if (std.mem.eql(u8, trimmed, "short") or
        std.mem.eql(u8, trimmed, "short int") or
        std.mem.eql(u8, trimmed, "unsigned short") or
        std.mem.eql(u8, trimmed, "uint16_t") or
        std.mem.eql(u8, trimmed, "int16_t") or
        std.mem.eql(u8, trimmed, "WORD"))
    {
        return 2;
    }
    if (std.mem.eql(u8, trimmed, "int") or
        std.mem.eql(u8, trimmed, "unsigned int") or
        std.mem.eql(u8, trimmed, "unsigned") or
        std.mem.eql(u8, trimmed, "float") or
        std.mem.eql(u8, trimmed, "int32_t") or
        std.mem.eql(u8, trimmed, "uint32_t") or
        std.mem.eql(u8, trimmed, "INT") or
        std.mem.eql(u8, trimmed, "UINT") or
        std.mem.eql(u8, trimmed, "DWORD") or
        std.mem.eql(u8, trimmed, "BOOL"))
    {
        return 4;
    }
    if (std.mem.eql(u8, trimmed, "double") or
        std.mem.eql(u8, trimmed, "long") or
        std.mem.eql(u8, trimmed, "long int") or
        std.mem.eql(u8, trimmed, "unsigned long") or
        std.mem.eql(u8, trimmed, "long long") or
        std.mem.eql(u8, trimmed, "unsigned long long") or
        std.mem.eql(u8, trimmed, "int64_t") or
        std.mem.eql(u8, trimmed, "uint64_t") or
        std.mem.eql(u8, trimmed, "size_t") or
        std.mem.eql(u8, trimmed, "intptr_t") or
        std.mem.eql(u8, trimmed, "uintptr_t") or
        std.mem.eql(u8, trimmed, "LONG") or
        std.mem.eql(u8, trimmed, "INT64"))
    {
        return 8;
    }
    return null;
}

fn findDeclaredSize(tokens: []const Token, var_token: usize, source: []const u8) ?usize {
    const name = source[tokens[var_token].start..tokens[var_token].end];
    var scan = var_token;
    while (scan > 0) {
        scan -= 1;
        if (tokens[scan].kind == .semicolon or tokens[scan].kind == .lbrace) {
            var fwd = scan + 1;
            while (fwd < var_token) {
                if (tokens[fwd].kind == .semicolon) break;
                if (!isCompoundType(tokens[fwd].kind) and !isIdentifierToken(tokens[fwd].kind)) {
                    fwd += 1;
                    continue;
                }
                if (isIdentifierToken(tokens[fwd].kind)) {
                    const slice = source[tokens[fwd].start..tokens[fwd].end];
                    if (std.mem.endsWith(u8, slice, "_t") or isNarrowTypedefName(slice)) {} else if (fwd > 0 and fwd - 1 > scan and tokens[fwd - 1].kind == .star) {} else {
                        fwd += 1;
                        continue;
                    }
                }
                var te = fwd + 1;
                while (te < tokens.len and
                    (isCompoundType(tokens[te].kind) or
                        isTypeQualifier(tokens[te].kind) or
                        tokens[te].kind == .star))
                {
                    te += 1;
                }
                if (te >= var_token) break;
                if (!isIdentifierToken(tokens[te].kind)) {
                    fwd += 1;
                    continue;
                }
                const decl_name = source[tokens[te].start..tokens[te].end];
                if (std.mem.eql(u8, decl_name, name)) {
                    return primitiveSize(source[tokens[fwd].start..tokens[te - 1].end]);
                }
                fwd = te + 1;
            }
        }
    }
    return null;
}

pub fn appendUndefinedReinterpretCast(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .identifier) continue;
        const name = source[tokens[i].start..tokens[i].end];
        if (!std.mem.eql(u8, name, "reinterpret_cast")) continue;

        if (i + 1 >= tokens.len or tokens[i + 1].kind != .lt) continue;

        const gt_pos = findMatchingCloseGt(tokens, i + 1);
        if (gt_pos >= tokens.len) continue;

        if (gt_pos + 1 >= tokens.len or tokens[gt_pos + 1].kind != .lparen) continue;
        const expr_end = findMatchingClose(tokens, gt_pos + 1);
        if (expr_end >= tokens.len) continue;

        if (editOverlaps(edits.items, tokens[i].start, tokens[expr_end].end)) continue;

        const type_start = i + 2;
        const type_end = gt_pos;
        if (type_start >= type_end) continue;

        var has_ref = false;
        var last_type = type_end - 1;
        if (tokens[last_type].kind == .amp) {
            has_ref = true;
            if (last_type == type_start) continue;
            last_type -= 1;
        }

        if (!has_ref) continue;

        const dest_type_src = source[tokens[type_start].start..tokens[last_type].end];
        const dest_size = primitiveSize(dest_type_src) orelse continue;

        const expr_start = gt_pos + 2;
        if (expr_start >= expr_end) continue;

        if (expr_end - expr_start != 1) continue;
        if (tokens[expr_start].kind != .identifier) continue;

        const src_name = source[tokens[expr_start].start..tokens[expr_start].end];
        const src_size = findDeclaredSize(tokens, expr_start, source) orelse continue;

        if (dest_size == src_size) continue;

        const replacement = try std.fmt.allocPrint(allocator, "({s} __r; memcpy(&__r, &{s}, sizeof(__r)), __r)", .{ dest_type_src, src_name });
        try edits.append(allocator, .{
            .start = tokens[i].start,
            .end = tokens[expr_end].end,
            .replacement = replacement,
        });
    }
}

pub fn appendStaticCastVoidUnwrap(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .identifier) continue;
        if (!std.mem.eql(u8, source[tokens[i].start..tokens[i].end], "static_cast")) continue;
        if (tokens[i + 1].kind != .lt) continue;
        if (tokens[i + 2].kind != .keyword_void) continue;
        if (tokens[i + 3].kind != .gt) continue;
        if (tokens[i + 4].kind != .lparen) continue;

        const close = findMatchingClose(tokens, i + 4);
        if (close >= tokens.len or close <= i + 4) continue;
        if (editOverlaps(edits.items, tokens[i].start, tokens[close].end)) continue;

        const inner_start = tokens[i + 4].end;
        const inner_end = tokens[close].start;
        try edits.append(allocator, .{
            .start = tokens[i].start,
            .end = tokens[close].end,
            .replacement = try allocator.dupe(u8, std.mem.trim(u8, source[inner_start..inner_end], " \t\r\n")),
        });
    }

    for (tokens) |token| {
        if (token.kind != .pp_define) continue;
        try appendStaticCastVoidTextUnwrap(allocator, source, token.start, token.end, edits);
    }
}

fn appendStaticCastVoidTextUnwrap(
    allocator: std.mem.Allocator,
    source: []const u8,
    start: usize,
    end: usize,
    edits: *std.ArrayList(Edit),
) !void {
    var pos = start;
    while (std.mem.indexOfPos(u8, source, pos, "static_cast")) |cast_start| {
        if (cast_start >= end) break;
        pos = cast_start + "static_cast".len;
        if (cast_start > start and isIdentByte(source[cast_start - 1])) continue;
        var i = cast_start + "static_cast".len;
        i = skipAsciiSpace(source, i, end);
        if (i >= end or source[i] != '<') continue;
        i += 1;
        i = skipAsciiSpace(source, i, end);
        if (i + "void".len > end or !std.mem.eql(u8, source[i .. i + "void".len], "void")) continue;
        i += "void".len;
        if (i < end and isIdentByte(source[i])) continue;
        i = skipAsciiSpace(source, i, end);
        if (i >= end or source[i] != '>') continue;
        i += 1;
        i = skipAsciiSpace(source, i, end);
        if (i >= end or source[i] != '(') continue;

        const close = findMatchingByteParen(source, i, end) orelse continue;
        if (editOverlaps(edits.items, cast_start, close + 1)) continue;
        const inner = std.mem.trim(u8, source[i + 1 .. close], " \t\r\n");
        try edits.append(allocator, .{
            .start = cast_start,
            .end = close + 1,
            .replacement = try allocator.dupe(u8, inner),
        });
        pos = close + 1;
    }
}

fn skipAsciiSpace(source: []const u8, start: usize, end: usize) usize {
    var i = start;
    while (i < end) : (i += 1) {
        switch (source[i]) {
            ' ', '\t', '\r', '\n' => {},
            else => break,
        }
    }
    return i;
}

fn isIdentByte(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => false,
    };
}

fn findMatchingByteParen(source: []const u8, open: usize, end: usize) ?usize {
    var depth: u32 = 1;
    var i = open + 1;
    while (i < end) : (i += 1) {
        switch (source[i]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            '"' => i = skipQuotedByteString(source, i, end, '"'),
            '\'' => i = skipQuotedByteString(source, i, end, '\''),
            '/' => {
                if (i + 1 < end and source[i + 1] == '/') {
                    i += 2;
                    while (i < end and source[i] != '\n') : (i += 1) {}
                } else if (i + 1 < end and source[i + 1] == '*') {
                    i += 2;
                    while (i + 1 < end and !(source[i] == '*' and source[i + 1] == '/')) : (i += 1) {}
                    if (i + 1 < end) i += 1;
                }
            },
            else => {},
        }
    }
    return null;
}

fn skipQuotedByteString(source: []const u8, quote_start: usize, end: usize, quote: u8) usize {
    var i = quote_start + 1;
    while (i < end) : (i += 1) {
        if (source[i] == '\\') {
            if (i + 1 < end) i += 1;
            continue;
        }
        if (source[i] == quote) return i;
    }
    return end;
}

const StaticCastVoidPointer = struct {
    close: usize,
    expr_open: usize,
    expr_close: usize,
};

fn staticCastVoidPointer(tokens: []const Token, start: usize) ?StaticCastVoidPointer {
    if (start + 5 >= tokens.len) return null;
    if (tokens[start].kind != .identifier) return null;
    if (tokens[start + 1].kind != .lt) return null;

    var i = start + 2;
    var saw_void = false;
    var saw_star = false;
    while (i < tokens.len) : (i += 1) {
        switch (tokens[i].kind) {
            .keyword_const, .keyword_volatile => {},
            .keyword_void => {
                if (saw_void) return null;
                saw_void = true;
            },
            .star => {
                if (saw_star) return null;
                saw_star = true;
            },
            .gt => {
                if (!saw_void or !saw_star) return null;
                if (i + 1 >= tokens.len or tokens[i + 1].kind != .lparen) return null;
                const expr_close = findMatchingClose(tokens, i + 1);
                if (expr_close >= tokens.len) return null;
                return .{
                    .close = expr_close,
                    .expr_open = i + 1,
                    .expr_close = expr_close,
                };
            },
            else => return null,
        }
    }
    return null;
}

fn previousTokenIsCallCallee(source: []const u8, tokens: []const Token, open: usize) bool {
    if (open == 0) return false;
    const prev = tokens[open - 1];
    if (prev.kind == .identifier) {
        const name = source[prev.start..prev.end];
        return !std.mem.eql(u8, name, "if") and
            !std.mem.eql(u8, name, "while") and
            !std.mem.eql(u8, name, "for") and
            !std.mem.eql(u8, name, "switch") and
            !std.mem.eql(u8, name, "return");
    }
    return prev.kind == .rparen or prev.kind == .rbracket or prev.kind == .gt;
}

fn callCalleeName(source: []const u8, tokens: []const Token, open: usize) ?[]const u8 {
    if (open == 0) return null;
    var i = open - 1;
    while (true) {
        if (tokens[i].kind == .identifier) return source[tokens[i].start..tokens[i].end];
        if (i == 0) break;
        i -= 1;
    }
    return null;
}

fn isPrintfStyleCallee(name: []const u8) bool {
    const names = [_][]const u8{
        "printf",
        "fprintf",
        "sprintf",
        "snprintf",
        "vprintf",
        "vfprintf",
        "vsprintf",
        "vsnprintf",
        "XBDM_TRACE",
    };
    for (names) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn findNearestEnclosingParen(tokens: []const Token, before: usize) ?usize {
    if (before == 0) return null;
    var depth: u32 = 0;
    var i = before;
    while (i > 0) {
        i -= 1;
        switch (tokens[i].kind) {
            .rparen, .rbrace, .rbracket => depth += 1,
            .lparen, .lbrace, .lbracket => {
                if (depth == 0) {
                    if (tokens[i].kind == .lparen) return i;
                    return null;
                }
                depth -= 1;
            },
            else => {},
        }
    }
    return null;
}

fn stringTokenContainsFmtPlaceholder(source: []const u8, token: Token) bool {
    if (token.kind != .string_literal) return false;
    const text = source[token.start..token.end];
    return std.mem.indexOfScalar(u8, text, '{') != null;
}

fn callFirstArgumentIsFmtString(source: []const u8, tokens: []const Token, open: usize, cast_index: usize) bool {
    var i = open + 1;
    var depth: u32 = 0;
    var saw_fmt_string = false;
    while (i < tokens.len) : (i += 1) {
        if (i >= cast_index and depth == 0) return false;
        switch (tokens[i].kind) {
            .lparen, .lbrace, .lbracket => depth += 1,
            .rparen, .rbrace, .rbracket => {
                if (depth == 0) return false;
                depth -= 1;
            },
            .comma => {
                if (depth == 0) return saw_fmt_string;
            },
            .string_literal => {
                if (depth == 0 and stringTokenContainsFmtPlaceholder(source, tokens[i])) {
                    saw_fmt_string = true;
                }
            },
            else => {},
        }
    }
    return false;
}

fn isDirectFmtArgument(source: []const u8, tokens: []const Token, cast_index: usize) bool {
    var search = cast_index;
    while (findNearestEnclosingParen(tokens, search)) |open| {
        if (!previousTokenIsCallCallee(source, tokens, open)) {
            search = open;
            continue;
        }
        if (callCalleeName(source, tokens, open)) |name| {
            if (isPrintfStyleCallee(name)) return false;
        }
        return callFirstArgumentIsFmtString(source, tokens, open, cast_index);
    }
    return false;
}

pub fn appendFmtPointerCasts(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, source[tokens[i].start..tokens[i].end], "static_cast")) continue;
        const cast = staticCastVoidPointer(tokens, i) orelse continue;
        if (!isDirectFmtArgument(source, tokens, i)) continue;
        if (editOverlaps(edits.items, tokens[i].start, tokens[cast.close].end)) continue;

        const inner_start = tokens[cast.expr_open].end;
        const inner_end = tokens[cast.expr_close].start;
        const inner = std.mem.trim(u8, source[inner_start..inner_end], " \t\r\n");
        const replacement = try std.fmt.allocPrint(allocator, "fmt::ptr({s})", .{inner});
        try edits.append(allocator, .{
            .start = tokens[i].start,
            .end = tokens[cast.close].end,
            .replacement = replacement,
        });
    }
}

pub fn isFunctionCall(tokens: []const Token, idx: usize) bool {
    if (idx >= tokens.len) return false;
    if (tokens[idx].kind != .identifier) return false;
    if (idx + 1 >= tokens.len) return false;
    return tokens[idx + 1].kind == .lparen;
}

pub fn expressionIsCharPointerUnsigned(tokens: []const Token, idx: usize, source: []const u8) ?bool {
    if (idx >= tokens.len) return null;
    const tok = tokens[idx];
    if (tok.kind == .string_literal) return false;
    if (tok.kind != .identifier) return null;
    const slice = source[tok.start..tok.end];
    const unsigned_patterns = [_][]const u8{ "buf", "Buf", "data", "Data", "bytes", "Bytes", "raw", "Raw", "mem", "Mem" };
    for (unsigned_patterns) |pat| {
        if (std.mem.indexOf(u8, slice, pat) != null) return true;
    }
    const signed_patterns = [_][]const u8{ "str", "Str", "text", "Text", "name", "Name", "label", "Label", "msg", "Msg" };
    for (signed_patterns) |pat| {
        if (std.mem.indexOf(u8, slice, pat) != null) {
            if (std.mem.eql(u8, slice, "stbi__") or std.mem.startsWith(u8, slice, "stbi_")) return true;
            return false;
        }
    }
    return null;
}

pub fn isCharPointerType(tokens: []const Token, idx: usize) ?bool {
    var j = idx;
    while (j < tokens.len and isTypeQualifier(tokens[j].kind)) j += 1;
    if (j >= tokens.len) return null;
    if (tokens[j].kind == .keyword_unsigned) {
        j += 1;
        if (j < tokens.len and tokens[j].kind == .keyword_char) return true;
        return null;
    }
    if (tokens[j].kind == .keyword_char) return false;
    if (tokens[j].kind == .keyword_signed) {
        j += 1;
        if (j < tokens.len and tokens[j].kind == .keyword_char) return false;
        return null;
    }
    return null;
}

fn typeIsUnsigned(tokens: []const Token, idx: usize, source: []const u8) bool {
    var j = idx;
    while (j < tokens.len and isTypeQualifier(tokens[j].kind)) j += 1;
    if (j >= tokens.len) return false;
    if (tokens[j].kind == .keyword_unsigned) return true;
    if (tokens[j].kind == .identifier) {
        const slice = source[tokens[j].start..tokens[j].end];
        return slice.len > 0 and (slice[0] == 'u' or slice[0] == 'U');
    }
    return false;
}

pub fn appendConstantConversionCasts(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    i: usize,
    type_end: usize,
    rhs_start: usize,
    edits: *std.ArrayList(Edit),
) !void {
    if (rhs_start >= tokens.len) return;
    const rhs = tokens[rhs_start];

    const is_negative_literal = rhs.kind == .minus and
        rhs_start + 1 < tokens.len and
        tokens[rhs_start + 1].kind == .int_literal;

    if (is_negative_literal and typeIsUnsigned(tokens, i, source)) {
        const cast_type = source[tokens[i].start..tokens[type_end - 1].end];
        try edits.append(allocator, .{
            .start = rhs.start,
            .end = rhs.start,
            .replacement = try std.fmt.allocPrint(allocator, "({s})", .{cast_type}),
        });
    }
}

pub fn appendStrictAliasingTypePuns(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .star) continue;
        if (i + 1 >= tokens.len or tokens[i + 1].kind != .lparen) continue;

        const cast_start = i + 1;
        const cast_end = findMatchingClose(tokens, cast_start);
        if (cast_end >= tokens.len or cast_end <= cast_start + 2) continue;
        if (tokens[cast_end - 1].kind != .star) continue;

        if (cast_end + 1 >= tokens.len or tokens[cast_end + 1].kind != .amp) continue;
        if (cast_end + 2 >= tokens.len or tokens[cast_end + 2].kind != .identifier) continue;

        const type_name = source[tokens[cast_start + 1].start..tokens[cast_end - 2].end];
        const var_name = source[tokens[cast_end + 2].start..tokens[cast_end + 2].end];
        const deref_start = tokens[i].start;

        if (cast_end + 3 < tokens.len and tokens[cast_end + 3].kind == .eq) {
            const write_expr_start = cast_end + 4;
            const semi = skipToSemicolon(tokens, write_expr_start);
            if (semi < tokens.len) {
                const write_expr = source[tokens[write_expr_start].start..tokens[semi].start];
                try edits.append(allocator, .{
                    .start = deref_start,
                    .end = tokens[semi].end,
                    .replacement = try std.fmt.allocPrint(
                        allocator,
                        "{{ {s} _v = {s}; memcpy(&({s}), &_v, sizeof _v); }}",
                        .{ type_name, write_expr, var_name },
                    ),
                });
            }
        } else {
            const read_replacement = try std.fmt.allocPrint(
                allocator,
                "({{ {s} _r__; memcpy(&_r__, &({s}), sizeof _r__); _r__; }})",
                .{ type_name, var_name },
            );
            try edits.append(allocator, .{
                .start = deref_start,
                .end = tokens[cast_end + 2].end,
                .replacement = read_replacement,
            });
        }
    }
}

pub fn appendOldStyleCastConversion(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .lparen) continue;
        if (i == 0) continue;

        const prev_kind = tokens[i - 1].kind;
        if (prev_kind == .identifier or
            prev_kind == .keyword_sizeof or
            prev_kind == .keyword_if or
            prev_kind == .keyword_while or
            prev_kind == .keyword_switch or
            prev_kind == .keyword_for or
            prev_kind == .keyword_return or
            // A cast's opening parenthesis never follows a closing bracket.
            // `int (*)(DIR*)` is a function-pointer type, not a cast of
            // `DIR*`; rewriting it produced `int (*)reinterpret_cast<DIR*>(>)`
            // and stopped the file compiling. The same guard covers a call
            // through a parenthesized callee, `(*fn)(x)`, and a call through a
            // subscript, `table[i](x)`.
            prev_kind == .rparen or
            prev_kind == .rbracket)
        {
            continue;
        }

        const close = findMatchingClose(tokens, i);
        if (close >= tokens.len or close <= i + 1) continue;

        if (close + 1 >= tokens.len) continue;
        const after_kind = tokens[close + 1].kind;
        if (after_kind == .lbrace or after_kind == .lparen) continue;

        const inner_start = i + 1;
        const inner_end = close;

        var has_type_kw = false;
        var has_ptr = false;
        var has_ref = false;
        var all_valid = true;
        {
            var t = inner_start;
            while (t < inner_end) : (t += 1) {
                const k = tokens[t].kind;
                if (isCompoundType(k) or isTypeQualifier(k) or k == .keyword_signed or k == .keyword_unsigned) {
                    has_type_kw = true;
                } else if (k == .star) {
                    has_ptr = true;
                } else if (k == .amp) {
                    has_ref = true;
                } else if (k == .identifier) {
                    const slice = source[tokens[t].start..tokens[t].end];
                    if (isNarrowTypedefName(slice) or
                        std.mem.endsWith(u8, slice, "_t") or
                        std.mem.eql(u8, slice, "size_t") or
                        std.mem.eql(u8, slice, "intptr_t") or
                        std.mem.eql(u8, slice, "uintptr_t") or
                        std.mem.eql(u8, slice, "ptrdiff_t") or
                        std.mem.eql(u8, slice, "wchar_t") or
                        (slice.len > 0 and slice[0] >= 'A' and slice[0] <= 'Z'))
                    {
                        has_type_kw = true;
                    } else {
                        all_valid = false;
                    }
                } else if (k == .keyword_struct or k == .keyword_union or k == .keyword_enum) {
                    has_type_kw = true;
                } else {
                    all_valid = false;
                }
            }
        }

        if (!all_valid or !has_type_kw) continue;

        if (editOverlaps(edits.items, tokens[i].start, tokens[close].end)) continue;

        const type_text = source[tokens[inner_start].start..tokens[inner_end - 1].end];

        if (editOverlaps(edits.items, tokens[i].start, tokens[close + 1].start)) continue;

        const cast_kind = if (has_ptr or has_ref) "reinterpret_cast" else "static_cast";
        const replacement = try std.fmt.allocPrint(allocator, "{s}<{s}>(", .{ cast_kind, type_text });

        try edits.append(allocator, .{
            .start = tokens[i].start,
            .end = tokens[close].end,
            .replacement = replacement,
        });

        const expr_start = close + 1;
        var expr_end = expr_start;
        var expr_depth: u32 = 0;
        while (expr_end < tokens.len) : (expr_end += 1) {
            const k = tokens[expr_end].kind;
            if (expr_depth == 0) {
                if (k == .semicolon or k == .comma or k == .rparen or k == .rbrace or
                    k == .rbracket or k == .eq or k == .colon or k == .question or
                    k == .amp_amp or k == .pipe_pipe or k == .plus_eq or k == .minus_eq)
                {
                    break;
                }
            }
            switch (k) {
                .lparen, .lbrace, .lbracket => expr_depth += 1,
                .rparen, .rbrace, .rbracket => {
                    if (expr_depth == 0) break;
                    expr_depth -= 1;
                },
                else => {},
            }
        }

        if (!editOverlaps(edits.items, tokens[expr_end - 1].end, tokens[expr_end - 1].end)) {
            try edits.append(allocator, .{
                .start = tokens[expr_end - 1].end,
                .end = tokens[expr_end - 1].end,
                .replacement = try allocator.dupe(u8, ")"),
            });
        }
    }
}
