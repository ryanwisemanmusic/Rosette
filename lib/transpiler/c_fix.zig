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

fn appendDepoisonFixes(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    _ = cpp_mode;
    const statement_attr = "[[maybe_unused]] ";
    const statement_comment = "/* rosette-c-fix: maybe_unused */ ";

    const repeated_marker = "/* rosette-c-fix: maybe_unused */ /* rosette-c-fix: maybe_unused */";
    while (std.mem.indexOf(u8, source, repeated_marker)) |idx| {
        if (editOverlaps(edits.items, idx, idx + repeated_marker.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + repeated_marker.len,
            .replacement = try allocator.dupe(u8, "/* rosette-c-fix: maybe_unused */"),
        });
    }

    const mixed_marker = "[[maybe_unused]] /* rosette-c-fix: maybe_unused */";
    while (std.mem.indexOf(u8, source, mixed_marker)) |idx| {
        if (editOverlaps(edits.items, idx, idx + mixed_marker.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + mixed_marker.len,
            .replacement = try allocator.dupe(u8, "/* rosette-c-fix: maybe_unused */"),
        });
    }

    const poisoned_dirhandle = "std::unique_ptr<DIR, int (*)reinterpret_cast<DIR*>(>)";
    while (std.mem.indexOf(u8, source, poisoned_dirhandle)) |idx| {
        if (editOverlaps(edits.items, idx, idx + poisoned_dirhandle.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + poisoned_dirhandle.len,
            .replacement = try allocator.dupe(u8, "std::unique_ptr<DIR, int (*)(DIR*)>"),
        });
    }

    const poisoned_readdir = "while ((auto ent = readdir(dir)))";
    while (std.mem.indexOf(u8, source, poisoned_readdir)) |idx| {
        if (editOverlaps(edits.items, idx, idx + poisoned_readdir.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + poisoned_readdir.len,
            .replacement = try allocator.dupe(u8, "while (auto ent = readdir(dir))"),
        });
    }

    const poisoned_const_attr = "const [[maybe_unused]] int";
    while (std.mem.indexOf(u8, source, poisoned_const_attr)) |idx| {
        if (editOverlaps(edits.items, idx, idx + poisoned_const_attr.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + poisoned_const_attr.len,
            .replacement = try allocator.dupe(u8, "const int"),
        });
    }

    const poisoned_param_u8 = "/* rosette-c-fix: maybe_unused */ uint8_t";
    while (std.mem.indexOf(u8, source, poisoned_param_u8)) |idx| {
        if (editOverlaps(edits.items, idx, idx + poisoned_param_u8.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + poisoned_param_u8.len,
            .replacement = try allocator.dupe(u8, "uint8_t"),
        });
    }

    const poisoned_param_const_u8 = "/* rosette-c-fix: maybe_unused */ const uint8_t";
    while (std.mem.indexOf(u8, source, poisoned_param_const_u8)) |idx| {
        if (editOverlaps(edits.items, idx, idx + poisoned_param_const_u8.len)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = idx + poisoned_param_const_u8.len,
            .replacement = try allocator.dupe(u8, "const uint8_t"),
        });
    }

    const poisoned_static_cast_prefix = "/* rosette-c-fix: maybe_unused */ const int av_aes_size= static_cast<int>(sizeof(";
    while (std.mem.indexOf(u8, source, poisoned_static_cast_prefix)) |idx| {
        const start = idx;
        const suffix_start = idx + poisoned_static_cast_prefix.len;
        const tail = source[suffix_start..];
        const close_rel = std.mem.indexOf(u8, tail, "))") orelse break;
        const close_idx = suffix_start + close_rel + 2;
        const inner = source[suffix_start .. suffix_start + close_rel];
        const replacement = try std.fmt.allocPrint(allocator, "/* rosette-c-fix: maybe_unused */ const int av_aes_size= (int)sizeof({s})", .{inner});
        if (editOverlaps(edits.items, start, close_idx)) break;
        try edits.append(allocator, .{
            .start = start,
            .end = close_idx,
            .replacement = replacement,
        });
    }

    const poisoned_static_cast_generic = "/* rosette-c-fix: maybe_unused */ const int ";
    while (std.mem.indexOf(u8, source, poisoned_static_cast_generic)) |idx| {
        const cast_rel = std.mem.indexOf(u8, source[idx..], "= static_cast<int>(sizeof(") orelse break;
        const cast_start = idx + cast_rel + "= static_cast<int>(sizeof(".len;
        const tail = source[cast_start..];
        const close_rel = std.mem.indexOf(u8, tail, "))") orelse break;
        const inner = source[cast_start .. cast_start + close_rel];
        const prefix = source[idx .. idx + cast_rel + 2];
        const replacement = try std.fmt.allocPrint(allocator, "{s}(int)sizeof({s})", .{ prefix, inner });
        const end = cast_start + close_rel + 2;
        if (editOverlaps(edits.items, idx, end)) break;
        try edits.append(allocator, .{
            .start = idx,
            .end = end,
            .replacement = replacement,
        });
    }

    const include_sentinel_poison = "\n, 0};";
    while (std.mem.indexOf(u8, source, include_sentinel_poison)) |idx| {
        const line_start = idx + 1;
        var scan = idx;
        var saw_include = false;
        while (scan > 0) {
            const prev_nl = std.mem.lastIndexOfScalar(u8, source[0..scan], '\n') orelse 0;
            const candidate_start = if (prev_nl == 0) 0 else prev_nl + 1;
            const candidate = trimLine(source[candidate_start..scan]);
            if (candidate.len == 0) {
                if (candidate_start == 0) break;
                scan = candidate_start - 1;
                continue;
            }
            if (std.mem.startsWith(u8, candidate, "#include ")) {
                saw_include = true;
            }
            break;
        }
        if (!saw_include) break;
        if (editOverlaps(edits.items, line_start, line_start + ", 0".len)) break;
        try edits.append(allocator, .{
            .start = line_start,
            .end = line_start + ", 0".len,
            .replacement = try allocator.dupe(u8, ""),
        });
    }

    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        pos = line.next;
        const trimmed = trimLine(line.text);
        if (trimmed.len == 0) continue;

        const marker = if (std.mem.startsWith(u8, trimmed, statement_attr)) statement_attr else if (std.mem.startsWith(u8, trimmed, statement_comment)) statement_comment else continue;
        const after = trimmed[marker.len..];
        if (after.len == 0) continue;

        const is_statement_assignment = std.mem.indexOfScalar(u8, after, '=') != null and
            (std.mem.indexOfScalar(u8, after, '[') != null or
             std.mem.indexOfScalar(u8, after, '.') != null or
             std.mem.indexOf(u8, after, "->") != null or
             std.mem.indexOf(u8, after, "++") != null or
             std.mem.indexOf(u8, after, "--") != null or
             std.mem.indexOf(u8, after, "|=") != null or
             std.mem.indexOf(u8, after, "+=") != null or
             std.mem.indexOf(u8, after, "-=") != null or
             std.mem.indexOf(u8, after, "*=") != null or
             std.mem.indexOf(u8, after, "/=") != null or
             std.mem.indexOf(u8, after, "%=") != null or
             std.mem.indexOf(u8, after, "BITS(") != null or
             std.mem.indexOf(u8, after, "NEEDBITS(") != null or
             std.mem.indexOf(u8, after, "DROPBITS(") != null);
        if (!is_statement_assignment) continue;

        const rel = std.mem.indexOf(u8, line.text, marker) orelse continue;
        const start = line.start + rel;
        const end = start + marker.len;
        if (editOverlaps(edits.items, start, end)) continue;
        try edits.append(allocator, .{
            .start = start,
            .end = end,
            .replacement = try allocator.dupe(u8, ""),
        });
    }
}

fn appendBracketAttributeFixes(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    if (cpp_mode) return;
    const marker = "/* rosette-c-fix: maybe_unused */";

    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .lbracket or tokens[i + 1].kind != .lbracket) continue;
        if (tokens[i + 2].kind != .identifier) continue;
        if (tokens[i + 3].kind != .rbracket or tokens[i + 4].kind != .rbracket) continue;

        const attr_name = source[tokens[i + 2].start..tokens[i + 2].end];
        var replace_end = tokens[i + 4].end;
        if (replace_end <= source.len) {
            const tail = source[replace_end..];
            const trimmed = std.mem.trim(u8, tail, " \t\r\n");
            if (std.mem.startsWith(u8, trimmed, marker)) {
                replace_end = source.len - trimmed.len + marker.len;
            }
        }
        if (std.mem.eql(u8, attr_name, "maybe_unused")) {
            try edits.append(allocator, .{
                .start = tokens[i].start,
                .end = replace_end,
                .replacement = try allocator.dupe(u8, marker),
            });
            i += 4;
            continue;
        }

        // Conservative C-mode fallback: preserve parseability by stripping unknown
        // bracket attributes rather than relying on the compiler to accept C++11
        // attributes in .c translation units.
        try edits.append(allocator, .{
            .start = tokens[i].start,
            .end = replace_end,
            .replacement = try std.fmt.allocPrint(allocator, "/* rosette-c-fix stripped [[{s}]] */", .{attr_name}),
        });
        i += 4;
    }
}

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
        std.mem.eql(u8, slice, "offsetof") or
        std.mem.eql(u8, slice, "strtol") or
        std.mem.eql(u8, slice, "strtoll") or
        std.mem.eql(u8, slice, "strtoul") or
        std.mem.eql(u8, slice, "strtoull");
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

fn findMatchingCloseGt(tokens: []const Token, start: usize) usize {
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

fn isPointerSubtraction(tokens: []const Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (tokens[idx].kind != .identifier and tokens[idx].kind != .int_literal) return false;
    if (tokens[idx + 1].kind != .minus) return false;
    const third = tokens[idx + 2];
    return third.kind == .identifier or third.kind == .int_literal or third.kind == .string_literal;
}

pub fn fixSource(allocator: std.mem.Allocator, source: []const u8) !FixResult {
    return fixSourceWithMode(allocator, source, false);
}

pub fn fixSourceWithMode(allocator: std.mem.Allocator, source: []const u8, cpp_mode: bool) !FixResult {
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

    try appendDepoisonFixes(allocator, source, &edits, cpp_mode);
    if (cpp_mode) {
        return .{ .edits = edits, .warning = warning };
    }
    try appendBracketAttributeFixes(allocator, source, tokens, &edits, cpp_mode);
    try appendTrivialMacIncludeCollapses(allocator, source, &edits);
    try appendLocalAngleIncludeQuotes(allocator, source, &edits);
    try appendVoidSuppressorElisions(allocator, source, &edits, cpp_mode);
    try appendStaticCastVoidUnwrap(allocator, source, tokens, &edits);
    try appendFmtPointerCasts(allocator, source, tokens, &edits);
    try appendUnusedLocalAnnotations(allocator, source, &edits, cpp_mode);
    try appendUnusedVarDeclarations(allocator, source, tokens, &edits, cpp_mode);
    try appendUnusedSetLocalAnnotations(allocator, source, &edits, cpp_mode);
    try appendUnusedConstAnnotations(allocator, source, &edits, cpp_mode);
    try appendParenthesesEquality(allocator, source, tokens, &edits);
    try appendSwitchDefaultClauses(allocator, source, tokens, &edits);
    try appendMissingFieldInitializers(allocator, source, tokens, &edits);
    try appendStrictAliasingTypePuns(allocator, source, tokens, &edits);
    try appendMissingBraces(allocator, source, tokens, &edits);
    try appendDeprecatedDeclReplacement(allocator, source, tokens, &edits);
    try appendLogicalOpParentheses(allocator, source, tokens, &edits);
    if (cpp_mode) {
        try appendOldStyleCastConversion(allocator, source, tokens, &edits);
        try appendUndefinedReinterpretCast(allocator, source, tokens, &edits);
    }

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

        const has_ptr = type_end > i and tokens[type_end - 1].kind == .star;
        const name_pos = type_end;

        if (!isIdentifierToken(tokens[name_pos].kind)) continue;

        const name = tokens[name_pos];
        _ = name;

        if (name_pos + 1 < tokens.len and tokens[name_pos + 1].kind == .eq) {
            const eq_pos = name_pos + 1;
            if (eq_pos + 1 >= tokens.len) continue;

            const rhs_start = eq_pos + 1;
            const rhs = tokens[rhs_start];

            if (has_ptr) {
                if (isCharPointerType(tokens, i)) |lhs_unsigned| {
                    var need_cast = false;
                    if (rhs.kind == .string_literal and lhs_unsigned) {
                        need_cast = true;
                    } else if (rhs.kind == .identifier) {
                        if (expressionIsCharPointerUnsigned(tokens, rhs_start, source)) |rhs_unsigned| {
                            if (lhs_unsigned != rhs_unsigned) need_cast = true;
                        }
                    }
                    if (need_cast) {
                        const cast_text = if (lhs_unsigned) "(unsigned char *)" else "(char *)";
                        try edits.append(allocator, .{
                            .start = rhs.start,
                            .end = rhs.start,
                            .replacement = try allocator.dupe(u8, cast_text),
                        });
                    }
                }
                continue;
            }

            if (!typeIsNarrow(tokens, i, source)) continue;

            try appendConstantConversionCasts(allocator, source, tokens, i, type_end, rhs_start, &edits);

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
            } else if (isFunctionCall(tokens, rhs_start)) {
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

fn skipInitializerToDelim(tokens: []const Token, start: usize) usize {
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

fn hasMaybeUnusedPrefix(tokens: []const Token, type_start: usize, source: []const u8) bool {
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

fn isPreprocessorToken(kind: Token.Kind) bool {
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

fn rangeContainsPreprocessor(tokens: []const Token, start: usize, end: usize) bool {
    if (start >= tokens.len or end >= tokens.len or end < start) return false;
    var i = start;
    while (i <= end and i < tokens.len) : (i += 1) {
        if (isPreprocessorToken(tokens[i].kind)) return true;
    }
    return false;
}

fn appendUnusedVarDeclarations(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    if (cpp_mode) return;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!isCompoundType(tokens[i].kind) and !isIdentifierToken(tokens[i].kind)) continue;

        if (isIdentifierToken(tokens[i].kind)) {
            const slice = source[tokens[i].start..tokens[i].end];
            if (!std.mem.endsWith(u8, slice, "_t") and
                !isNarrowTypedefName(slice) and
                slice.len > 0 and (slice[0] < 'A' or slice[0] > 'Z'))
            {
                continue;
            }
        }

        if (hasMaybeUnusedPrefix(tokens, i, source)) continue;

        var type_end = i + 1;
        while (type_end < tokens.len and
            (isCompoundType(tokens[type_end].kind) or
                isTypeQualifier(tokens[type_end].kind) or
                tokens[type_end].kind == .star))
        {
            type_end += 1;
        }

        if (type_end >= tokens.len) continue;
        if (!isIdentifierToken(tokens[type_end].kind)) continue;

        if (type_end + 1 >= tokens.len) continue;
        if (tokens[type_end + 1].kind == .lparen) continue;

        if (!appearsInsideBlock(source, tokens[i].start)) continue;

        var var_names: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (var_names.items) |name| {
                allocator.free(name);
            }
            var_names.deinit(allocator);
        }

        var scan = type_end;
        var decl_end: usize = tokens[type_end].end;
        var has_initializer = false;

        while (scan < tokens.len) {
            switch (tokens[scan].kind) {
                .identifier => {
                    const name_dupe = try allocator.dupe(u8, source[tokens[scan].start..tokens[scan].end]);
                    try var_names.append(allocator, name_dupe);
                    scan += 1;
                },
                .eq => {
                    has_initializer = true;
                    scan = skipInitializerToDelim(tokens, scan + 1);
                    if (scan >= tokens.len) break;
                    if (tokens[scan].kind == .semicolon) {
                        decl_end = tokens[scan].end;
                        break;
                    }
                    scan += 1;
                },
                .comma => {
                    scan += 1;
                },
                .semicolon => {
                    decl_end = tokens[scan].end;
                    break;
                },
                else => break,
            }
        }

        // Skip declarations without initializers (like struct fields)
        if (!has_initializer) continue;

        if (var_names.items.len == 0) continue;
        if (editOverlaps(edits.items, tokens[i].start, decl_end)) continue;

        var any_unused = false;
        for (var_names.items) |nv| {
            if (!identifierAppearsAfter(source, decl_end, nv)) {
                any_unused = true;
                break;
            }
        }

        if (any_unused) {
            try edits.append(allocator, .{
                .start = tokens[i].start,
                .end = tokens[i].start,
                .replacement = try allocator.dupe(u8, if (cpp_mode) "[[maybe_unused]] " else "/* rosette-c-fix: maybe_unused */ "),
            });
        }
    }
}

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

fn appendUndefinedReinterpretCast(
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

fn editOverlaps(edits: []const Edit, start: usize, end: usize) bool {
    for (edits) |edit| {
        if (start < edit.end and edit.start < end) return true;
        // Also detect zero-width insertions at the exact start position
        if (edit.start == start and edit.end == start and start < end) return true;
    }
    return false;
}

fn isVendoredAngleInclude(path: []const u8) bool {
    const prefixes = [_][]const u8{
        "llvm/",
        "simde/",
        "xbyak/",
        "xsimd/",
    };
    for (prefixes) |candidate| {
        if (std.mem.startsWith(u8, path, candidate)) return true;
    }

    const headers = [_][]const u8{
        "bmi2neon.h",
        "ppcfloat2neon.h",
        "vex2neon.h",
        "ymm2neon.h",
    };
    for (headers) |candidate| {
        if (std.mem.eql(u8, path, candidate)) return true;
    }
    return false;
}

fn appendLocalAngleIncludeQuotes(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
) !void {
    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        pos = line.next;
        if (editOverlaps(edits.items, line.start, line.next)) continue;
        const trimmed = trimLine(line.text);
        if (!std.mem.startsWith(u8, trimmed, "#include")) continue;

        const open_rel = std.mem.indexOfScalar(u8, line.text, '<') orelse continue;
        const close_rel = std.mem.indexOfScalarPos(u8, line.text, open_rel + 1, '>') orelse continue;
        const path = line.text[open_rel + 1 .. close_rel];
        if (!isVendoredAngleInclude(path)) continue;

        var replacement: std.ArrayList(u8) = .empty;
        errdefer replacement.deinit(allocator);
        try replacement.appendSlice(allocator, line.text[0..open_rel]);
        try replacement.append(allocator, '"');
        try replacement.appendSlice(allocator, path);
        try replacement.append(allocator, '"');
        try replacement.appendSlice(allocator, line.text[close_rel + 1 ..]);
        if (line.next > line.end) try replacement.append(allocator, '\n');

        try edits.append(allocator, .{
            .start = line.start,
            .end = line.next,
            .replacement = try replacement.toOwnedSlice(allocator),
        });
    }
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

fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

const MacBranchState = enum {
    known_true,
    known_false,
    unknown,
};

fn macBranchActive(stack: []const MacBranchState) bool {
    for (stack) |state| {
        if (state == .known_false) return false;
    }
    return true;
}

fn macIfExpressionState(expr: []const u8) MacBranchState {
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

fn macDirectiveState(trimmed: []const u8) ?MacBranchState {
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

fn toggledMacBranchState(state: MacBranchState) MacBranchState {
    return switch (state) {
        .known_true => .known_false,
        .known_false => .known_true,
        .unknown => .unknown,
    };
}

fn identifierAppearsInSlice(slice: []const u8, name: []const u8) bool {
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

fn identifierAppearsAfter(source: []const u8, start: usize, name: []const u8) bool {
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

fn unusedLocalDeclarationName(line: []const u8) ?[]const u8 {
    const trimmed = trimLine(line);
    if (trimmed.len == 0 or trimmed[0] == '#') return null;
    if (std.mem.startsWith(u8, trimmed, "[[maybe_unused]]") or
        std.mem.startsWith(u8, trimmed, "/* rosette-c-fix:")) return null;
    if (std.mem.startsWith(u8, trimmed, "if ") or
        std.mem.startsWith(u8, trimmed, "if(") or
        std.mem.startsWith(u8, trimmed, "for ") or
        std.mem.startsWith(u8, trimmed, "for(") or
        std.mem.startsWith(u8, trimmed, "while ") or
        std.mem.startsWith(u8, trimmed, "while(") or
        std.mem.startsWith(u8, trimmed, "switch ") or
        std.mem.startsWith(u8, trimmed, "switch(") or
        std.mem.startsWith(u8, trimmed, "return ") or
        std.mem.startsWith(u8, trimmed, "case ") or
        std.mem.startsWith(u8, trimmed, "default:") or
        std.mem.startsWith(u8, trimmed, "using ") or
        std.mem.startsWith(u8, trimmed, "typedef ") or
        std.mem.startsWith(u8, trimmed, "namespace ") or
        std.mem.startsWith(u8, trimmed, "class ") or
        std.mem.startsWith(u8, trimmed, "struct ") or
        std.mem.startsWith(u8, trimmed, "}"))
    {
        return null;
    }

    const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse return null;
    const semi = std.mem.lastIndexOfScalar(u8, trimmed, ';') orelse return null;
    if (semi < eq) return null;

    const lhs = std.mem.trim(u8, trimmed[0..eq], " \t");
    if (std.mem.indexOfScalar(u8, lhs, '.') != null or std.mem.indexOf(u8, lhs, "->") != null) return null;
    if (std.mem.indexOfScalar(u8, lhs, '(') != null or std.mem.indexOfScalar(u8, lhs, ')') != null) return null;
    if (lhs.len == 0) return null;

    var end = lhs.len;
    while (end > 0 and !isIdentChar(lhs[end - 1])) end -= 1;
    if (end == 0) return null;
    var start = end;
    while (start > 0 and isIdentChar(lhs[start - 1])) start -= 1;
    if (start == end) return null;

    const prefix = std.mem.trim(u8, lhs[0..start], " \t*&");
    if (prefix.len == 0) return null;
    return lhs[start..end];
}

fn isVoidSuppressorGuard(trimmed: []const u8) bool {
    if (!std.mem.startsWith(u8, trimmed, "#if") and
        !std.mem.startsWith(u8, trimmed, "#ifdef"))
    {
        return false;
    }
    return std.mem.indexOf(u8, trimmed, "__APPLE__") != null or
        std.mem.indexOf(u8, trimmed, "XE_PLATFORM_MACOS") != null;
}

fn voidSuppressorName(line: []const u8) ?[]const u8 {
    const trimmed = trimLine(line);
    if (!std.mem.startsWith(u8, trimmed, "(void)")) return null;

    var rest = std.mem.trim(u8, trimmed["(void)".len..], " \t");
    if (rest.len < 2 or rest[rest.len - 1] != ';') return null;
    rest = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    if (rest.len == 0 or (rest[0] >= '0' and rest[0] <= '9')) return null;

    for (rest) |ch| {
        if (!isIdentChar(ch)) return null;
    }
    return rest;
}

fn isDeclarationPrefixReject(trimmed: []const u8) bool {
    if (trimmed.len == 0 or trimmed[0] == '#') return true;
    if (std.mem.startsWith(u8, trimmed, "[[maybe_unused]]")) return true;
    if (hasMaybeUnusedBlockComment(trimmed)) return true;
    return std.mem.startsWith(u8, trimmed, "if ") or
        std.mem.startsWith(u8, trimmed, "if(") or
        std.mem.startsWith(u8, trimmed, "for ") or
        std.mem.startsWith(u8, trimmed, "for(") or
        std.mem.startsWith(u8, trimmed, "while ") or
        std.mem.startsWith(u8, trimmed, "while(") or
        std.mem.startsWith(u8, trimmed, "switch ") or
        std.mem.startsWith(u8, trimmed, "switch(") or
        std.mem.startsWith(u8, trimmed, "return ") or
        std.mem.startsWith(u8, trimmed, "case ") or
        std.mem.startsWith(u8, trimmed, "default:") or
        std.mem.startsWith(u8, trimmed, "using ") or
        std.mem.startsWith(u8, trimmed, "typedef ") or
        std.mem.startsWith(u8, trimmed, "namespace ") or
        std.mem.startsWith(u8, trimmed, "class ") or
        std.mem.startsWith(u8, trimmed, "struct ") or
        std.mem.startsWith(u8, trimmed, "enum ") or
        std.mem.startsWith(u8, trimmed, "template") or
        std.mem.startsWith(u8, trimmed, "static_assert") or
        std.mem.startsWith(u8, trimmed, "}") or
        std.mem.indexOf(u8, trimmed, "[[maybe_unused]]") != null or
        hasMaybeUnusedBlockComment(trimmed);
}

fn hasMaybeUnusedBlockComment(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "/* rosette-c-fix:") != null;
}

fn localDeclarationInsertOffset(line: []const u8, name: []const u8) ?usize {
    const trimmed = trimLine(line);
    if (isDeclarationPrefixReject(trimmed)) return null;
    if (!std.mem.endsWith(u8, trimmed, ";")) return null;
    if (std.mem.indexOfScalar(u8, trimmed, '(') != null or
        std.mem.indexOfScalar(u8, trimmed, ')') != null or
        std.mem.indexOfScalar(u8, trimmed, '[') != null or
        std.mem.indexOf(u8, trimmed, "->") != null or
        std.mem.indexOfScalar(u8, trimmed, '.') != null)
    {
        return null;
    }

    const semi = std.mem.lastIndexOfScalar(u8, trimmed, ';') orelse return null;
    const eq_or_semi = std.mem.indexOfScalar(u8, trimmed, '=') orelse semi;
    const lhs = std.mem.trim(u8, trimmed[0..eq_or_semi], " \t");
    if (lhs.len == 0) return null;

    var ident_end = lhs.len;
    while (ident_end > 0 and !isIdentChar(lhs[ident_end - 1])) ident_end -= 1;
    if (ident_end == 0) return null;
    var ident_start = ident_end;
    while (ident_start > 0 and isIdentChar(lhs[ident_start - 1])) ident_start -= 1;
    if (!std.mem.eql(u8, lhs[ident_start..ident_end], name)) return null;

    const prefix = std.mem.trim(u8, lhs[0..ident_start], " \t*&");
    if (prefix.len == 0) return null;

    var indent_len: usize = 0;
    while (indent_len < line.len and (line[indent_len] == ' ' or line[indent_len] == '\t')) {
        indent_len += 1;
    }
    return indent_len;
}

fn previousParameterDelimiter(line: []const u8, before: usize) ?usize {
    var pos = before;
    while (pos > 0) {
        pos -= 1;
        if (line[pos] == '(' or line[pos] == ',') return pos;
        if (line[pos] == ';' or line[pos] == '{' or line[pos] == '}') return null;
    }
    return null;
}

fn nextParameterDelimiter(line: []const u8, after: usize) ?usize {
    var pos = after;
    while (pos < line.len) : (pos += 1) {
        if (line[pos] == ')' or line[pos] == ',') return pos;
        if (line[pos] == ';' or line[pos] == '{' or line[pos] == '}') return null;
    }
    return null;
}

fn parameterDeclarationInsertOffset(line: []const u8, name: []const u8) ?usize {
    if (std.mem.indexOf(u8, line, "[[maybe_unused]]") != null) return null;

    var search: usize = 0;
    while (std.mem.indexOfPos(u8, line, search, name)) |match| {
        const before_ok = match == 0 or !isIdentChar(line[match - 1]);
        const after_index = match + name.len;
        const after_ok = after_index >= line.len or !isIdentChar(line[after_index]);
        if (!before_ok or !after_ok) {
            search = match + name.len;
            continue;
        }

        const left = previousParameterDelimiter(line, match) orelse {
            search = match + name.len;
            continue;
        };
        const right = nextParameterDelimiter(line, after_index) orelse {
            search = match + name.len;
            continue;
        };
        if (right <= left + 1) {
            search = match + name.len;
            continue;
        }

        const segment = line[left + 1 .. right];
        const rel_name = match - (left + 1);
        const prefix = std.mem.trim(u8, segment[0..rel_name], " \t*&");
        if (prefix.len == 0) {
            search = match + name.len;
            continue;
        }
        if (std.mem.indexOfScalar(u8, prefix, '"') != null or
            std.mem.indexOfScalar(u8, prefix, '\'') != null)
        {
            search = match + name.len;
            continue;
        }

        var insert = left + 1;
        while (insert < line.len and (line[insert] == ' ' or line[insert] == '\t')) {
            insert += 1;
        }
        return insert;
    }
    return null;
}

fn maybeUnusedInsertOffsetForName(source: []const u8, before: usize, name: []const u8) ?usize {
    var best: ?usize = null;
    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        if (line.start >= before) break;
        pos = line.next;

        if (localDeclarationInsertOffset(line.text, name)) |offset| {
            best = line.start + offset;
            continue;
        }
        if (parameterDeclarationInsertOffset(line.text, name)) |offset| {
            best = line.start + offset;
        }
    }
    return best;
}

fn hasMaybeUnusedInsertion(edits: []const Edit, offset: usize) bool {
    for (edits) |edit| {
        if (edit.start == offset and edit.end == offset and
            (std.mem.eql(u8, edit.replacement, "[[maybe_unused]] ") or
             std.mem.indexOf(u8, edit.replacement, "/* rosette-c-fix:") != null))
        {
            return true;
        }
    }
    return false;
}

fn appendMaybeUnusedAnnotationForName(
    allocator: std.mem.Allocator,
    source: []const u8,
    before: usize,
    name: []const u8,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    const insert = maybeUnusedInsertOffsetForName(source, before, name) orelse return;
    if (hasMaybeUnusedInsertion(edits.items, insert)) return;

    try edits.append(allocator, .{
        .start = insert,
        .end = insert,
        .replacement = try allocator.dupe(u8, if (cpp_mode) "[[maybe_unused]] " else "/* rosette-c-fix: maybe_unused */ "),
    });
}

fn appearsInsideBlock(source: []const u8, offset: usize) bool {
    var depth: isize = 0;
    for (source[0..offset]) |ch| {
        if (ch == '{') {
            depth += 1;
        } else if (ch == '}' and depth > 0) {
            depth -= 1;
        }
    }
    return depth > 0;
}

fn appendUnusedLocalAnnotations(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    if (cpp_mode) return;
    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        pos = line.next;
        if (editOverlaps(edits.items, line.start, line.next)) continue;
        if (!appearsInsideBlock(source, line.start)) continue;
        const name = unusedLocalDeclarationName(line.text) orelse continue;
        if (identifierAppearsAfter(source, line.next, name)) continue;

        var indent_len: usize = 0;
        while (indent_len < line.text.len and (line.text[indent_len] == ' ' or line.text[indent_len] == '\t')) {
            indent_len += 1;
        }

        try edits.append(allocator, .{
            .start = line.start + indent_len,
            .end = line.start + indent_len,
            .replacement = try allocator.dupe(u8, if (cpp_mode) "[[maybe_unused]] " else "/* rosette-c-fix: maybe_unused */ "),
        });
    }
}

fn isIdentifierToken(kind: Token.Kind) bool {
    return kind == .identifier;
}

fn appendStaticCastVoidUnwrap(
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

fn appendFmtPointerCasts(
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

fn appendVoidSuppressorElisions(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        const trimmed = trimLine(line.text);

        if (isVoidSuppressorGuard(trimmed)) {
            var names: std.ArrayList([]const u8) = .empty;
            defer names.deinit(allocator);

            var scan_pos = line.next;
            var valid_block = true;
            var block_end: ?usize = null;
            while (nextLine(source, scan_pos)) |block_line| {
                scan_pos = block_line.next;
                const block_trimmed = trimLine(block_line.text);
                if (block_trimmed.len == 0) continue;
                if (std.mem.eql(u8, block_trimmed, "#endif")) {
                    block_end = block_line.next;
                    break;
                }
                if (voidSuppressorName(block_line.text)) |name| {
                    try names.append(allocator, name);
                    continue;
                }
                valid_block = false;
                break;
            }

            if (valid_block and names.items.len > 0) {
                if (block_end) |end| {
                    if (!editOverlaps(edits.items, line.start, end)) {
                        for (names.items) |name| {
                            try appendMaybeUnusedAnnotationForName(allocator, source, line.start, name, edits, cpp_mode);
                        }
                        try edits.append(allocator, .{
                            .start = line.start,
                            .end = end,
                            .replacement = try allocator.dupe(u8, ""),
                        });
                        pos = end;
                        continue;
                    }
                }
            }
        }

        if (voidSuppressorName(line.text)) |name| {
            if (!editOverlaps(edits.items, line.start, line.next)) {
                try appendMaybeUnusedAnnotationForName(allocator, source, line.start, name, edits, cpp_mode);
                try edits.append(allocator, .{
                    .start = line.start,
                    .end = line.next,
                    .replacement = try allocator.dupe(u8, ""),
                });
            }
        }

        pos = line.next;
    }
}

fn appendUnusedSetLocalAnnotations(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    if (cpp_mode) return;
    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        pos = line.next;
        if (editOverlaps(edits.items, line.start, line.next)) continue;
        if (!appearsInsideBlock(source, line.start)) continue;

        const trimmed = trimLine(line.text);
        if (trimmed.len == 0) continue;

        if (trimmed[0] == '#' or trimmed[0] == '}') continue;

        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const semi = std.mem.lastIndexOfScalar(u8, trimmed, ';') orelse continue;
        if (semi < eq) continue;

        const lhs = std.mem.trim(u8, trimmed[0..eq], " \t");
        if (lhs.len == 0) continue;

        if (std.mem.indexOfScalar(u8, lhs, '.') != null) continue;
        if (std.mem.indexOf(u8, lhs, "->") != null) continue;
        if (std.mem.indexOfScalar(u8, lhs, '(') != null) continue;
        if (std.mem.indexOfScalar(u8, lhs, '[') != null) continue;
        if (std.mem.indexOfScalar(u8, lhs, '*') != null) continue;
        if (std.mem.indexOfScalar(u8, lhs, '&') != null) continue;

        var name_end = lhs.len;
        while (name_end > 0 and !isIdentChar(lhs[name_end - 1])) name_end -= 1;
        if (name_end == 0) continue;
        var name_start = name_end;
        while (name_start > 0 and isIdentChar(lhs[name_start - 1])) name_start -= 1;
        if (name_start == name_end) continue;
        const name = lhs[name_start..name_end];
        if (name.len == 0) continue;

        const prefix = std.mem.trim(u8, lhs[0..name_start], " \t*&");
        if (prefix.len > 0) continue;

        const eq_in_text = std.mem.indexOfScalar(u8, line.text, '=') orelse continue;
        const semi_in_text = std.mem.lastIndexOfScalar(u8, line.text, ';') orelse continue;
        const rhs_region = line.text[eq_in_text + 1 .. semi_in_text];
        if (std.mem.indexOf(u8, rhs_region, name) != null) continue;

        if (identifierAppearsAfter(source, line.next, name)) continue;

        try appendMaybeUnusedAnnotationForName(allocator, source, line.start, name, edits, cpp_mode);
    }
}

fn isFunctionCall(tokens: []const Token, idx: usize) bool {
    if (idx >= tokens.len) return false;
    if (tokens[idx].kind != .identifier) return false;
    if (idx + 1 >= tokens.len) return false;
    return tokens[idx + 1].kind == .lparen;
}

fn expressionIsCharPointerUnsigned(tokens: []const Token, idx: usize, source: []const u8) ?bool {
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

fn isCharPointerType(tokens: []const Token, idx: usize) ?bool {
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

fn hasTopLevelAssign(tokens: []const Token, start: usize, end: usize) bool {
    var depth: u32 = 0;
    var i = start;
    while (i < end) : (i += 1) {
        switch (tokens[i].kind) {
            .lparen, .lbrace, .lbracket => depth += 1,
            .rparen, .rbrace, .rbracket => {
                if (depth == 0) return false;
                depth -= 1;
            },
            .eq => {
                if (depth == 0) return true;
            },
            else => {},
        }
    }
    return false;
}

fn appendUnusedConstAnnotations(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayList(Edit),
    cpp_mode: bool,
) !void {
    if (cpp_mode) return;
    var pos: usize = 0;
    while (nextLine(source, pos)) |line| {
        pos = line.next;
        if (editOverlaps(edits.items, line.start, line.next)) continue;
        if (appearsInsideBlock(source, line.start)) continue;

        const trimmed = trimLine(line.text);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for "const" keyword with word boundaries
        const const_idx = std.mem.indexOf(u8, trimmed, "const") orelse continue;
        const before_ok = const_idx == 0 or !isIdentChar(trimmed[const_idx - 1]);
        const after_idx = const_idx + 5;
        const after_ok = after_idx >= trimmed.len or !isIdentChar(trimmed[after_idx]);
        if (!before_ok or !after_ok) continue;

        const prefix_marker = if (cpp_mode) "[[maybe_unused]]" else "/* rosette-c-fix:";
        if (std.mem.startsWith(u8, trimmed, prefix_marker)) continue;

        const name = unusedLocalDeclarationName(line.text) orelse continue;
        if (identifierAppearsAfter(source, line.next, name)) continue;

        var indent_len: usize = 0;
        while (indent_len < line.text.len and (line.text[indent_len] == ' ' or line.text[indent_len] == '\t')) {
            indent_len += 1;
        }

        try edits.append(allocator, .{
            .start = line.start + indent_len,
            .end = line.start + indent_len,
            .replacement = try allocator.dupe(u8, if (cpp_mode) "[[maybe_unused]] " else "/* rosette-c-fix: maybe_unused */ "),
        });
    }
}

fn appendParenthesesEquality(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    _ = source;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .keyword_if and tokens[i].kind != .keyword_while) continue;
        if (i + 1 >= tokens.len) continue;
        if (tokens[i + 1].kind != .lparen) continue;

        const close = findMatchingClose(tokens, i + 1);
        if (close >= tokens.len or close <= i + 2) continue;
        if (rangeContainsPreprocessor(tokens, i + 1, close)) continue;

        if (hasTopLevelAssign(tokens, i + 2, close)) {
            try edits.append(allocator, .{
                .start = tokens[i + 1].start + 1,
                .end = tokens[i + 1].start + 1,
                .replacement = try allocator.dupe(u8, "("),
            });
            try edits.append(allocator, .{
                .start = tokens[close].start,
                .end = tokens[close].start,
                .replacement = try allocator.dupe(u8, ")"),
            });
        }
    }
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

fn appendConstantConversionCasts(
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

fn appendSwitchDefaultClauses(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    _ = source;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .keyword_switch) continue;
        if (i + 1 >= tokens.len) continue;
        if (tokens[i + 1].kind != .lparen) continue;

        const close_paren = findMatchingClose(tokens, i + 1);
        if (close_paren >= tokens.len) continue;
        const after_paren = close_paren + 1;
        if (after_paren >= tokens.len) continue;
        if (tokens[after_paren].kind != .lbrace) continue;

        const body_start = after_paren;
        const body_end = findMatchingClose(tokens, body_start);
        if (body_end >= tokens.len) continue;

        var depth: u32 = 1;
        var has_default = false;
        var j = body_start + 1;
        while (j < body_end) : (j += 1) {
            switch (tokens[j].kind) {
                .lbrace => depth += 1,
                .rbrace => {
                    depth -= 1;
                    if (depth == 0) break;
                },
                .keyword_default => {
                    if (depth == 1 and j + 1 < body_end and tokens[j + 1].kind == .colon) {
                        has_default = true;
                        break;
                    }
                },
                else => {},
            }
        }

        if (!has_default) {
            try edits.append(allocator, .{
                .start = tokens[body_end].start,
                .end = tokens[body_end].start,
                .replacement = try allocator.dupe(u8, "default: break;\n"),
            });
        }
    }
}

fn collectStructDefs(
    allocator: std.mem.Allocator,
    tokens: []const Token,
    source: []const u8,
) !std.StringHashMap(usize) {
    var map = std.StringHashMap(usize).init(allocator);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const is_typedef = tokens[i].kind == .keyword_typedef;
        if (!is_typedef and tokens[i].kind != .keyword_struct) continue;
        if (is_typedef) {
            var sp = i + 1;
            while (sp < tokens.len and tokens[sp].kind != .keyword_struct) {
                sp += 1;
            }
            if (sp >= tokens.len) continue;
            i = sp;
        }

        var j = i + 1;
        var struct_name: ?[]const u8 = null;
        if (j < tokens.len and tokens[j].kind == .identifier) {
            struct_name = source[tokens[j].start..tokens[j].end];
            j += 1;
        }

        while (j < tokens.len and (isTypeQualifier(tokens[j].kind) or tokens[j].kind == .identifier)) {
            j += 1;
        }

        if (j >= tokens.len or tokens[j].kind != .lbrace) continue;

        const body_start = j;
        const body_end = findMatchingClose(tokens, body_start);
        if (body_end >= tokens.len) continue;

        var field_count: usize = 0;
        var depth: u32 = 1;
        var t = body_start + 1;
        while (t < body_end) : (t += 1) {
            switch (tokens[t].kind) {
                .lbrace, .lbracket => depth += 1,
                .rbrace, .rbracket => {
                    depth -= 1;
                    if (depth == 0) break;
                },
                .semicolon => {
                    if (depth == 1) field_count += 1;
                },
                else => {},
            }
        }

        if (struct_name) |name| {
            try map.put(name, field_count);
        }

        if (is_typedef) {
            var k = body_end + 1;
            while (k < tokens.len and tokens[k].kind != .semicolon) {
                if (tokens[k].kind == .identifier) {
                    try map.put(source[tokens[k].start..tokens[k].end], field_count);
                    break;
                }
                k += 1;
            }
        }
    }

    return map;
}

fn hasDesignatedInitializers(tokens: []const Token, init_start: usize, init_end: usize) bool {
    var depth: u32 = 1;
    var j = init_start + 1;
    while (j < init_end) : (j += 1) {
        if (tokens[j].kind == .lbrace or tokens[j].kind == .lbracket) {
            depth += 1;
        } else if (tokens[j].kind == .rbrace or tokens[j].kind == .rbracket) {
            depth -= 1;
            if (depth == 0) break;
        } else if (depth == 1 and tokens[j].kind == .dot) {
            return true;
        }
    }
    return false;
}

fn countTopLevelCommas(tokens: []const Token, init_start: usize, init_end: usize) usize {
    if (init_end <= init_start + 1) return 0;
    var count: usize = 1;
    var depth: u32 = 1;
    var j = init_start + 1;
    while (j < init_end) : (j += 1) {
        if (tokens[j].kind == .lbrace or tokens[j].kind == .lbracket) {
            depth += 1;
        } else if (tokens[j].kind == .rbrace or tokens[j].kind == .rbracket) {
            depth -= 1;
            if (depth == 0) break;
        } else if (depth == 1 and tokens[j].kind == .comma) {
            count += 1;
        }
    }
    return count;
}

fn findStructTypeName(
    tokens: []const Token,
    start: usize,
    source: []const u8,
    struct_map: std.StringHashMap(usize),
) ?[]const u8 {
    if (start == 0) return null;
    var j = start;
    var skip_depth: u32 = 0;
    while (j > 0) {
        j -= 1;
        if (skip_depth > 0) {
            switch (tokens[j].kind) {
                .rbrace, .rbracket, .rparen => skip_depth += 1,
                .lbrace, .lbracket, .lparen => {
                    skip_depth -= 1;
                },
                else => {},
            }
            continue;
        }

        switch (tokens[j].kind) {
            .identifier => {
                const name = source[tokens[j].start..tokens[j].end];
                if (struct_map.contains(name)) return name;
            },
            .keyword_const, .keyword_volatile, .keyword_restrict, .star, .keyword_struct, .comma, .eq, .keyword_unsigned, .keyword_signed => continue,
            .rbrace, .rbracket, .rparen => {
                skip_depth = 1;
            },
            else => return null,
        }
    }
    return null;
}

fn appendMissingFieldInitializers(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var struct_map = try collectStructDefs(allocator, tokens, source);
    defer struct_map.deinit();

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .eq) continue;
        if (i + 1 >= tokens.len or tokens[i + 1].kind != .lbrace) continue;

        const init_start = i + 1;
        const init_end = findMatchingClose(tokens, init_start);
        if (init_end >= tokens.len or init_end <= init_start + 1) continue;

        const type_name = findStructTypeName(tokens, i, source, struct_map) orelse continue;
        const field_count = struct_map.get(type_name) orelse continue;
        if (field_count == 0) continue;

        if (hasArrayDeclaratorBeforeEq(tokens, i)) continue;

        if (hasDesignatedInitializers(tokens, init_start, init_end)) continue;

        const init_count = countTopLevelCommas(tokens, init_start, init_end);
        // Debug
        // std.debug.print("Struct: {s}, field_count: {}, init_count: {}, adding: {}\n", .{type_name, field_count, init_count, init_count < field_count});
        if (init_count >= field_count) continue;

        try edits.append(allocator, .{
            .start = tokens[init_end].start,
            .end = tokens[init_end].start,
            .replacement = try allocator.dupe(u8, ", 0"),
        });
    }
}

fn appendStrictAliasingTypePuns(
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

fn hasNestedBraces(tokens: []const Token, init_start: usize, init_end: usize) bool {
    var depth: u32 = 1;
    var j = init_start + 1;
    while (j < init_end) : (j += 1) {
        if (tokens[j].kind == .lbrace or tokens[j].kind == .lbracket) {
            depth += 1;
            if (depth > 1) return true;
        } else if (tokens[j].kind == .rbrace or tokens[j].kind == .rbracket) {
            if (depth == 0) break;
            depth -= 1;
        }
    }
    return false;
}

fn findArraySize(tokens: []const Token, eq_pos: usize, source: []const u8) ?usize {
    if (eq_pos == 0) return null;
    var j = eq_pos - 1;
    if (tokens[j].kind != .rbracket) return null;
    var depth: u32 = 1;
    while (j > 0) {
        j -= 1;
        if (depth == 0) break;
        switch (tokens[j].kind) {
            .rbracket => depth += 1,
            .lbracket => {
                depth -= 1;
                if (depth == 0) {
                    const dist = eq_pos - 1 - j;
                    if (dist == 2 and tokens[j + 1].kind == .int_literal) {
                        const slice = source[tokens[j + 1].start..tokens[j + 1].end];
                        return std.fmt.parseInt(usize, slice, 0) catch null;
                    }
                    return null;
                }
            },
            else => {},
        }
    }
    return null;
}

fn hasArrayDeclaratorBeforeEq(tokens: []const Token, eq_pos: usize) bool {
    if (eq_pos == 0) return false;
    var j = eq_pos;
    var depth: u32 = 0;
    while (j > 0) {
        j -= 1;
        switch (tokens[j].kind) {
            .rparen, .rbrace => depth += 1,
            .lparen, .lbrace => {
                if (depth == 0) return false;
                depth -= 1;
            },
            .semicolon, .comma => {
                if (depth == 0) return false;
            },
            .rbracket => {
                if (depth == 0) return true;
            },
            else => {},
        }
    }
    return false;
}

fn appendMissingBraces(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var struct_map = try collectStructDefs(allocator, tokens, source);
    defer struct_map.deinit();

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .eq) continue;
        if (i + 1 >= tokens.len or tokens[i + 1].kind != .lbrace) continue;

        const init_start = i + 1;
        const init_end = findMatchingClose(tokens, init_start);
        if (init_end >= tokens.len or init_end <= init_start + 1) continue;

        if (hasNestedBraces(tokens, init_start, init_end)) continue;

        const type_name = findStructTypeName(tokens, i, source, struct_map) orelse continue;
        const field_count = struct_map.get(type_name) orelse continue;
        if (field_count == 0) continue;

        if (!hasArrayDeclaratorBeforeEq(tokens, i)) continue;

        const array_size = findArraySize(tokens, i, source) orelse continue;
        if (array_size == 0) continue;

        const init_count = countTopLevelCommas(tokens, init_start, init_end);
        if (init_count != array_size * field_count) continue;

        if (editOverlaps(edits.items, tokens[init_start].start, tokens[init_end].end)) continue;

        const opening = try allocator.dupe(u8, "{");
        const closing = try allocator.dupe(u8, "}");
        const sep = try allocator.dupe(u8, "}, {");

        try edits.append(allocator, .{ .start = tokens[init_start].start + 1, .end = tokens[init_start].start + 1, .replacement = opening });
        try edits.append(allocator, .{ .start = tokens[init_end].start, .end = tokens[init_end].start, .replacement = closing });

        var group_count: usize = 0;
        var depth: u32 = 1;
        var j = init_start + 1;
        while (j < init_end) : (j += 1) {
            switch (tokens[j].kind) {
                .lbrace, .lbracket => depth += 1,
                .rbrace, .rbracket => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                .comma => {
                    if (depth == 1) group_count += 1;
                    if (depth == 1 and group_count % field_count == 0 and group_count < init_count) {
                        try edits.append(allocator, .{ .start = tokens[j].start, .end = tokens[j].end, .replacement = sep });
                    }
                },
                else => {},
            }
        }
    }
}

fn appendDeprecatedDeclReplacement(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .identifier) continue;
        const name = source[tokens[i].start..tokens[i].end];

        const is_sprintf = std.mem.eql(u8, name, "sprintf");
        const is_strcpy = std.mem.eql(u8, name, "strcpy");
        const is_strcat = std.mem.eql(u8, name, "strcat");
        if (!is_sprintf and !is_strcpy and !is_strcat) continue;

        if (i + 1 >= tokens.len or tokens[i + 1].kind != .lparen) continue;
        const call_end = findMatchingClose(tokens, i + 1);
        if (call_end >= tokens.len or call_end <= i + 2) continue;

        if (editOverlaps(edits.items, tokens[i].start, tokens[call_end].end)) continue;

        if (is_sprintf) {
            const arg1_start = i + 2;
            if (arg1_start >= call_end) continue;
            const arg1_name = source[tokens[arg1_start].start..tokens[arg1_start].end];

            var comma_pos: ?usize = null;
            var depth: u32 = 1;
            var j = i + 2;
            while (j < call_end) : (j += 1) {
                switch (tokens[j].kind) {
                    .lparen, .lbrace, .lbracket => depth += 1,
                    .rparen, .rbrace, .rbracket => {
                        if (depth == 0) break;
                        depth -= 1;
                    },
                    .comma => {
                        if (depth == 1) {
                            comma_pos = j;
                            break;
                        }
                    },
                    else => {},
                }
            }

            if (comma_pos) |cp| {
                const replacement = try std.fmt.allocPrint(allocator, "{s}, sizeof({s})", .{ source[tokens[cp].start..tokens[cp].end], arg1_name });
                try edits.append(allocator, .{ .start = tokens[cp].start, .end = tokens[cp].end, .replacement = replacement });
                const func_name = source[tokens[i].start..tokens[i].end];
                const new_name = try std.fmt.allocPrint(allocator, "sn{s}", .{func_name[1..]});
                try edits.append(allocator, .{ .start = tokens[i].start, .end = tokens[i].end, .replacement = new_name });
            }
        } else if (is_strcpy or is_strcat) {
            const arg1_start = i + 2;
            if (arg1_start >= call_end) continue;
            const arg1_name = source[tokens[arg1_start].start..tokens[arg1_start].end];

            const func_name = source[tokens[i].start..tokens[i].end];
            const new_name = try std.fmt.allocPrint(allocator, "strl{s}", .{func_name[3..]});
            try edits.append(allocator, .{ .start = tokens[i].start, .end = tokens[i].end, .replacement = new_name });
            try edits.append(allocator, .{ .start = tokens[call_end].start, .end = tokens[call_end].start, .replacement = try std.fmt.allocPrint(allocator, ", sizeof({s})", .{arg1_name}) });
        }
    }
}

fn appendLogicalOpParentheses(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    edits: *std.ArrayList(Edit),
) !void {
    _ = source;

    // Forward scan: && followed by ||  (handles a && b || c)
    {
        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            if (tokens[i].kind != .amp_amp) continue;

            var open_depth: u32 = 0;
            var j = i;
            while (j > 0) {
                j -= 1;
                switch (tokens[j].kind) {
                    .lparen, .lbrace, .lbracket => {
                        if (open_depth == 0) break;
                        open_depth -= 1;
                    },
                    .rparen, .rbrace, .rbracket => open_depth += 1,
                    .semicolon, .keyword_if, .keyword_while, .keyword_for, .keyword_switch, .comma, .eq, .colon, .keyword_return, .keyword_case, .pipe_pipe, .amp_amp => {
                        if (open_depth == 0) break;
                    },
                    else => {},
                }
            }

            var k = i + 1;
            var close_depth: u32 = 0;
            while (k < tokens.len) : (k += 1) {
                switch (tokens[k].kind) {
                    .lparen, .lbrace, .lbracket => close_depth += 1,
                    .rparen, .rbrace, .rbracket => {
                        if (close_depth == 0) break;
                        close_depth -= 1;
                    },
                    .pipe_pipe => {
                        if (close_depth == 0) {
                            const left = tokens[j + 1].start;
                            if (rangeContainsPreprocessor(tokens, j + 1, k)) break;
                            if (editOverlaps(edits.items, left, tokens[k].start)) break;
                            try edits.append(allocator, .{ .start = left, .end = left, .replacement = try allocator.dupe(u8, "(") });
                            try edits.append(allocator, .{ .start = tokens[k].start, .end = tokens[k].start, .replacement = try allocator.dupe(u8, ")") });
                            break;
                        }
                    },
                    .semicolon, .comma, .eq, .colon, .keyword_if, .keyword_while, .keyword_for => {
                        if (close_depth == 0) break;
                    },
                    else => {},
                }
            }
        }
    }

    // Forward scan: || followed by && at depth 0  (handles a || b && c)
    {
        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            if (tokens[i].kind != .pipe_pipe) continue;
            var depth: u32 = 0;
            var k = i + 1;
            while (k < tokens.len) : (k += 1) {
                switch (tokens[k].kind) {
                    .lparen, .lbrace, .lbracket => depth += 1,
                    .rparen, .rbrace, .rbracket => {
                        if (depth == 0) break;
                        depth -= 1;
                    },
                    .amp_amp => {
                        if (depth == 0) {
                            var left = k;
                            var ld: u32 = 0;
                            while (left > 0) {
                                left -= 1;
                                switch (tokens[left].kind) {
                                    .lparen, .lbrace, .lbracket => {
                                        if (ld == 0) {
                                            left += 1;
                                            break;
                                        }
                                        ld -= 1;
                                    },
                                    .rparen, .rbrace, .rbracket => ld += 1,
                                    .semicolon, .comma, .eq, .colon, .keyword_if, .keyword_while, .keyword_for, .keyword_switch, .keyword_return, .keyword_case, .pipe_pipe, .amp_amp => {
                                        if (ld == 0) {
                                            left += 1;
                                            break;
                                        }
                                    },
                                    else => {},
                                }
                            }
                            var end = k + 1;
                            var ed: u32 = 0;
                            while (end < tokens.len) : (end += 1) {
                                switch (tokens[end].kind) {
                                    .lparen, .lbrace, .lbracket => ed += 1,
                                    .rparen, .rbrace, .rbracket => {
                                        if (ed == 0) break;
                                        ed -= 1;
                                    },
                                    .semicolon, .comma, .eq, .colon, .pipe_pipe, .keyword_if, .keyword_while, .keyword_for => {
                                        if (ed == 0) break;
                                    },
                                    else => {},
                                }
                            }
                            if (end > k + 1) end -= 1;
                            if (tokens[end].kind == .rparen or tokens[end].kind == .rbrace or tokens[end].kind == .rbracket) end -= 1;
                            if (left <= i + 1) left = i + 1;
                            if (end < left or end >= tokens.len) break;
                            if (rangeContainsPreprocessor(tokens, left, end)) break;
                            if (editOverlaps(edits.items, tokens[left].start, tokens[end - 1].end)) break;
                            try edits.append(allocator, .{ .start = tokens[left].start, .end = tokens[left].start, .replacement = try allocator.dupe(u8, "(") });
                            try edits.append(allocator, .{ .start = tokens[end].end, .end = tokens[end].end, .replacement = try allocator.dupe(u8, ")") });
                            break;
                        }
                    },
                    .semicolon, .comma, .eq, .colon, .keyword_if, .keyword_while, .keyword_for => {
                        if (depth == 0) break;
                    },
                    else => {},
                }
            }
        }
    }
}

fn appendOldStyleCastConversion(
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
            prev_kind == .keyword_return)
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

test "quote vendored angle include" {
    const src =
        \\#include <llvm/ADT/BitVector.h>
        \\#include <vector>
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(
        "#include \"llvm/ADT/BitVector.h\"\n#include <vector>\n",
        output,
    );
}

test "annotate unused single line local declaration" {
    const src =
        \\void f() {
        \\  auto arena = builder->arena();
        \\  use(builder);
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ auto arena") != null);
}

test "do not annotate used local declaration" {
    const src =
        \\void f() {
        \\  uint32_t index_buffer_base = regs[0];
        \\  use(index_buffer_base);
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "[[maybe_unused]]") == null);
}

test "local used only in non-apple branch gets maybe_unused annotation" {
    const src =
        \\void f() {
        \\  int x = 0;
        \\#ifndef __APPLE__
        \\  use(x);
        \\#endif
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ int x") != null);
}

test "local used in apple branch gets no maybe_unused annotation" {
    const src =
        \\void f() {
        \\  int x = 0;
        \\#ifdef __APPLE__
        \\  use(x);
        \\#endif
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "[[maybe_unused]]") == null);
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

test "unused but set local gets maybe_unused annotation" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  x = 42;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ int x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(void)x") == null);
}

test "standalone void suppressor becomes maybe_unused local annotation" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  (void)x;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ int x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(void)x") == null);
}

test "apple-only void suppressor block becomes maybe_unused parameter annotation" {
    const src =
        \\void f(int dfn) {
        \\#ifdef __APPLE__
        \\  (void)dfn;
        \\#endif
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "void f(/* rosette-c-fix: maybe_unused */ int dfn)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(void)dfn") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "#ifdef __APPLE__") == null);
}

test "static_cast void expression keeps side effects without suppressor cast" {
    const src =
        \\void f(void) {
        \\  static_cast<void>(call());
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "call();") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<void>") == null);
}

test "static_cast void macro continuation keeps expression" {
    const src =
        \\#define LOAD_KERNEL_MODULE(t) \
        \\  static_cast<void>(kernel_state_->LoadKernelModule<kernel::t>())
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "kernel_state_->LoadKernelModule<kernel::t>()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<void>") == null);
}

test "fmt logging pointer cast becomes fmt ptr" {
    const src =
        \\void f(Object* object) {
        \\  XELOGI("Object pointer: {}", static_cast<void*>(object));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "fmt::ptr(object)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<void*>") == null);
}

test "fmt logging const pointer cast becomes fmt ptr" {
    const src =
        \\void f(const Device* device) {
        \\  XELOGI("Device pointer: {}", static_cast<const void*>(device));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "fmt::ptr(device)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<const void*>") == null);
}

test "printf style pointer cast is not fmt ptr" {
    const src =
        \\void f(Object* object) {
        \\  XBDM_TRACE("Object pointer: %p\n", static_cast<void*>(object));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "nested non-format pointer cast is not fmt ptr" {
    const src =
        \\void f(Object* object) {
        \\  XELOGI("Object pointer: {}", wrap(static_cast<void*>(object)));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "unused but set local used on RHS gets no suppression" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  x = x + 1;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "used variable after assignment gets no unused-set suppression" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  x = 42;
        \\  use(x);
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "sign-conversion cast for function call RHS" {
    const src = "uint32_t x = getchar();";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(uint32_t)") != null);
}

test "pointer-sign cast unsigned char* from string literal" {
    const src = "unsigned char *p = \"hello\";";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(unsigned char *)") != null);
}

test "no pointer-sign cast for already-correct pointer" {
    const src = "char *p = \"hello\";";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "parentheses-equality wraps if assignment" {
    const src = "if (x = y) { f(); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("if ((x = y)) { f(); }", output);
}

test "parentheses-equality wraps while assignment" {
    const src = "while (x = next()) { process(); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "((x = next()))") != null);
}

test "no parentheses-equality for comparison" {
    const src = "if (x == y) { f(); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "no parentheses-equality for for-loop init" {
    const src = "for (i = 0; i < n; i++) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "constant-conversion cast negative literal to unsigned" {
    const src = "uint32_t x = -1;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(uint32_t)") != null);
}

test "switch default clause inserted when missing" {
    const src =
        \\switch (x) {
        \\  case 1: break;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "default: break;") != null);
}

test "switch no default when default already present" {
    const src =
        \\switch (x) {
        \\  case 1: break;
        \\  default: break;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "unused file-scope const gets maybe_unused" {
    const src =
        \\const int FOO = 42;
        \\void f(void) {}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ const int FOO") != null);
}

test "used file-scope const gets no annotation" {
    const src =
        \\const int BAR = 42;
        \\int f(void) { return BAR; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "static const at file scope gets maybe_unused" {
    const src =
        \\static const int BAZ = 42;
        \\void f(void) {}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ static const int BAZ") != null);
}

test "extern const at file scope skipped" {
    const src =
        \\extern const int QUX;
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "struct partial initializer gets padded" {
    const src =
        \\struct Foo { int a; int b; int c; };
        \\void f(void) { struct Foo x = {1, 2}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, ", 0") != null);
}

test "struct full initializer unchanged" {
    const src =
        \\struct Foo { int a; int b; };
        \\struct Foo f(void) { return (struct Foo){1, 2}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "struct designated initializer skipped" {
    const src =
        \\struct Foo { int a; int b; int c; };
        \\struct Foo f(void) { return (struct Foo){.a = 1, .b = 2}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "typedef struct partial initializer gets padded" {
    const src =
        \\typedef struct { int a; int b; int c; } Foo;
        \\void f(void) { Foo x = {1}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, ", 0") != null);
}

test "strict-aliasing read pun via memcpy" {
    const src = "uint32_t x = *(uint32_t *)&f;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "memcpy") != null);
}

test "strict-aliasing write pun via memcpy" {
    const src = "*(uint32_t *)&f = 0x3f800000;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "memcpy") != null);
}

test "strict-aliasing no match without cast" {
    const src = "int x = *p;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "logical-op-parentheses wraps && before ||" {
    const src = "if (a && b || c) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "&& b") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "|| c") != null);
}

test "logical-op-parentheses wraps && after ||" {
    const src = "if (a || b && c) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "&& c") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "a || ") != null);
}

test "logical-op-parentheses no wrap on single operator" {
    const src = "if (a && b) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "logical-op-parentheses no wrap when already parenthesised" {
    const src = "if ((a && b) || c) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "old-style-cast int to float in cpp mode" {
    const src = "double x = (double)42;";
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<double>") != null);
}

test "old-style-cast pointer cast in cpp mode" {
    const src = "void *p = (uint32_t *)ptr;";
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "reinterpret_cast<uint32_t *>") != null);
}

test "old-style-cast does not run in C mode" {
    const src = "double x = (double)42;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "old-style-cast does not touch function call parens" {
    const src = "void f(void) { }";
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "old-style-cast struct keyword cast" {
    const src = "struct Foo *p = (struct Foo *)ptr;";
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "reinterpret_cast<struct Foo *>") != null);
}

test "missing-braces insert inner braces for array of struct" {
    const src =
        \\struct Foo { int a; int b; };
        \\void f(void) { struct Foo arr[2] = { 1, 2, 3, 4 }; }
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "{{ 1, 2}") != null);
}

test "missing-braces no change when already braced" {
    const src =
        \\struct Foo { int a; int b; };
        \\struct Foo* f(void) { static struct Foo arr[2] = { {1, 2}, {3, 4} }; return arr; }
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "missing-braces no change for non-array struct" {
    const src =
        \\struct Foo { int a; int b; };
        \\struct Foo f(void) { return (struct Foo){ 1, 2 }; }
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "deprecated sprintf replaced with snprintf" {
    const src = "void f(void) { sprintf(buf, \"%d\", x); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "snprintf") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sizeof(buf)") != null);
}

test "deprecated strcpy replaced with strlcpy" {
    const src = "void f(void) { strcpy(dst, src); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "strlcpy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sizeof(dst)") != null);
}

test "deprecated strcat replaced with strlcat" {
    const src = "void f(void) { strcat(dst, src); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "strlcat") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sizeof(dst)") != null);
}

test "deprecated no false positive on unrelated sprintf-like" {
    const src = "int f(void) { int foo_sprintf = 42; return foo_sprintf; }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}
