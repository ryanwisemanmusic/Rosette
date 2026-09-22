const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");
const types = @import("c_fix_types.zig");
const shared = @import("c_fix_shared.zig");

const Token = c_tokenizer.Token;
const Edit = types.Edit;
const editOverlaps = shared.editOverlaps;
const includePath = shared.includePath;
const nextLine = shared.nextLine;
const trimLine = shared.trimLine;

pub fn appendDepoisonFixes(
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

pub fn appendBracketAttributeFixes(
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

pub fn appendLocalAngleIncludeQuotes(
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

pub fn appendTrivialMacIncludeCollapses(
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
