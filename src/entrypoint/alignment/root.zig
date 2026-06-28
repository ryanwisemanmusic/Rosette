const std = @import("std");

pub const FieldSpec = struct {
    name: []const u8,
    size: usize,
    alignment: usize,
};

pub const FieldLayout = struct {
    name: []const u8 = "",
    offset: usize = 0,
    size: usize = 0,
    alignment: usize = 1,
};

pub const RecordLayout = struct {
    size: usize,
    alignment: usize,
};

pub const PointerWarning = struct {
    symbol: []const u8 = "",
    offset: usize = 0,
    source: []const u8 = "",
};

pub const WarningAnalysis = struct {
    warning_count: usize = 0,
    malformed_count: usize = 0,
    required_alignment: usize,
    residue_mask: u64 = 0,
    examples: [8]PointerWarning = [_]PointerWarning{PointerWarning{}} ** 8,
    example_count: usize = 0,

    pub fn hasIssues(self: WarningAnalysis) bool {
        return self.warning_count != 0;
    }

    pub fn commonResidue(self: WarningAnalysis) ?usize {
        if (self.residue_mask == 0 or @popCount(self.residue_mask) != 1) return null;
        return @ctz(self.residue_mask);
    }
};

pub fn alignForward(value: usize, alignment: usize) !usize {
    if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.InvalidAlignment;
    const remainder = value & (alignment - 1);
    if (remainder == 0) return value;
    return std.math.add(usize, value, alignment - remainder);
}

pub fn planRecordLayout(fields: []const FieldSpec, output: []FieldLayout) !RecordLayout {
    if (output.len < fields.len) return error.OutputTooSmall;
    var cursor: usize = 0;
    var record_alignment: usize = 1;
    for (fields, 0..) |field, index| {
        if (field.alignment == 0 or !std.math.isPowerOfTwo(field.alignment)) return error.InvalidAlignment;
        cursor = try alignForward(cursor, field.alignment);
        output[index] = .{
            .name = field.name,
            .offset = cursor,
            .size = field.size,
            .alignment = field.alignment,
        };
        cursor = try std.math.add(usize, cursor, field.size);
        record_alignment = @max(record_alignment, field.alignment);
    }
    return .{
        .size = try alignForward(cursor, record_alignment),
        .alignment = record_alignment,
    };
}

pub fn parsePointerWarning(line: []const u8) ?PointerWarning {
    const marker = "pointer not aligned at ";
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    const location_start = marker_index + marker.len;
    const source_marker = " from ";
    const source_index = std.mem.indexOfPos(u8, line, location_start, source_marker) orelse line.len;
    const location = std.mem.trim(u8, line[location_start..source_index], " \t\r\n");
    const offset_marker = "+0x";
    const offset_index = std.mem.lastIndexOf(u8, location, offset_marker) orelse return null;
    const symbol = std.mem.trim(u8, location[0..offset_index], " \t");
    const offset_text = location[offset_index + offset_marker.len ..];
    if (symbol.len == 0 or offset_text.len == 0) return null;
    const offset = std.fmt.parseUnsigned(usize, offset_text, 16) catch return null;
    const source = if (source_index < line.len)
        std.mem.trim(u8, line[source_index + source_marker.len ..], " \t\r\n")
    else
        "";
    return .{ .symbol = symbol, .offset = offset, .source = source };
}

pub fn analyzeWarnings(text: []const u8, required_alignment: usize) !WarningAnalysis {
    if (required_alignment == 0 or !std.math.isPowerOfTwo(required_alignment) or required_alignment > 64) {
        return error.InvalidAlignment;
    }
    var analysis = WarningAnalysis{ .required_alignment = required_alignment };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "pointer not aligned") == null) continue;
        const warning = parsePointerWarning(line) orelse {
            analysis.malformed_count += 1;
            continue;
        };
        analysis.warning_count += 1;
        analysis.residue_mask |= @as(u64, 1) << @intCast(warning.offset & (required_alignment - 1));
        if (analysis.example_count < analysis.examples.len and !containsSymbol(analysis.examples[0..analysis.example_count], warning.symbol)) {
            analysis.examples[analysis.example_count] = warning;
            analysis.example_count += 1;
        }
    }
    return analysis;
}

pub fn diagnoseFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, required_alignment: usize, strict: bool) !u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(text);
    const analysis = try analyzeWarnings(text, required_alignment);

    if (!analysis.hasIssues()) {
        std.debug.print("rosette-alignment: no unaligned pointer relocation warnings found in {s}\n", .{path});
        return 0;
    }

    std.debug.print("rosette-alignment: {d} unaligned pointer relocation warning(s)\n", .{analysis.warning_count});
    std.debug.print("  required pointer alignment: {d} byte(s)\n", .{analysis.required_alignment});
    if (analysis.commonResidue()) |residue| {
        std.debug.print("  common offset remainder:    {d} modulo {d}\n", .{ residue, analysis.required_alignment });
    } else {
        std.debug.print("  offset remainders:          mixed\n", .{});
    }
    for (analysis.examples[0..analysis.example_count]) |example| {
        std.debug.print("  symbol: {s}+0x{x}\n", .{ example.symbol, example.offset });
        if (example.source.len != 0) std.debug.print("    source: {s}\n", .{example.source});
    }
    if (analysis.malformed_count != 0) {
        std.debug.print("  note: {d} related warning line(s) could not be parsed\n", .{analysis.malformed_count});
    }
    std.debug.print(
        "  correction: restore natural alignment for pointer-bearing fields or use an explicitly planned layout; do not round relocation addresses after linking.\n",
        .{},
    );
    return if (strict) 2 else 0;
}

fn containsSymbol(examples: []const PointerWarning, symbol: []const u8) bool {
    for (examples) |example| {
        if (std.mem.eql(u8, example.symbol, symbol)) return true;
    }
    return false;
}

test "parses ld pointer alignment warning" {
    const line = "ld: warning: pointer not aligned at table+0x1C from object.o";
    const warning = parsePointerWarning(line).?;
    try std.testing.expectEqualStrings("table", warning.symbol);
    try std.testing.expectEqual(@as(usize, 0x1c), warning.offset);
    try std.testing.expectEqualStrings("object.o", warning.source);
}

test "plans naturally aligned pointer-bearing record" {
    const fields = [_]FieldSpec{
        .{ .name = "group", .size = 4, .alignment = 4 },
        .{ .name = "format", .size = 4, .alignment = 4 },
        .{ .name = "opcode", .size = 4, .alignment = 4 },
        .{ .name = "name", .size = 8, .alignment = 8 },
        .{ .name = "description", .size = 8, .alignment = 8 },
        .{ .name = "disasm", .size = 8, .alignment = 8 },
    };
    var output: [fields.len]FieldLayout = undefined;
    const layout = try planRecordLayout(&fields, &output);
    try std.testing.expectEqual(@as(usize, 16), output[3].offset);
    try std.testing.expectEqual(@as(usize, 24), output[4].offset);
    try std.testing.expectEqual(@as(usize, 32), output[5].offset);
    try std.testing.expectEqual(@as(usize, 40), layout.size);
    try std.testing.expectEqual(@as(usize, 8), layout.alignment);
}

test "summarizes repeated warning residue" {
    const text =
        \\ld: warning: pointer not aligned at table+0xC from object.o
        \\ld: warning: pointer not aligned at table+0x14 from object.o
        \\ld: warning: pointer not aligned at table+0x54 from object.o
    ;
    const analysis = try analyzeWarnings(text, 8);
    try std.testing.expectEqual(@as(usize, 3), analysis.warning_count);
    try std.testing.expectEqual(@as(?usize, 4), analysis.commonResidue());
}
