const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");
const types = @import("c_fix_types.zig");
const shared = @import("c_fix_shared.zig");

const Token = c_tokenizer.Token;
const Edit = types.Edit;
const editOverlaps = shared.editOverlaps;
const findMatchingClose = shared.findMatchingClose;
const isTypeQualifier = shared.isTypeQualifier;
const rangeContainsPreprocessor = shared.rangeContainsPreprocessor;

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

pub fn appendParenthesesEquality(
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

pub fn appendSwitchDefaultClauses(
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

pub fn appendMissingFieldInitializers(
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

pub fn appendMissingBraces(
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

pub fn appendDeprecatedDeclReplacement(
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

pub fn appendLogicalOpParentheses(
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
