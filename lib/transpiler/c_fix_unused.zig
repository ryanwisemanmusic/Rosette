const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");
const types = @import("c_fix_types.zig");
const shared = @import("c_fix_shared.zig");

const Token = c_tokenizer.Token;
const Edit = types.Edit;
const editOverlaps = shared.editOverlaps;
const hasMaybeUnusedPrefix = shared.hasMaybeUnusedPrefix;
const identifierAppearsAfter = shared.identifierAppearsAfter;
const isCompoundType = shared.isCompoundType;
const isIdentChar = shared.isIdentChar;
const isIdentifierToken = shared.isIdentifierToken;
const isNarrowTypedefName = shared.isNarrowTypedefName;
const isTypeQualifier = shared.isTypeQualifier;
const nextLine = shared.nextLine;
const skipInitializerToDelim = shared.skipInitializerToDelim;
const trimLine = shared.trimLine;

pub fn appendUnusedVarDeclarations(
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

    if (std.mem.indexOfScalar(u8, lhs[0..start], '[') != null) return null;

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

pub fn appendUnusedLocalAnnotations(
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

pub fn appendVoidSuppressorElisions(
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

pub fn appendUnusedSetLocalAnnotations(
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

pub fn appendUnusedConstAnnotations(
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
