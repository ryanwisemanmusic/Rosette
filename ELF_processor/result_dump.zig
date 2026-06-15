const std = @import("std");
const asm_decls = @import("asm_decls.zig");
const elf_loader = @import("elf_loader.zig");

pub const Options = struct {
    dump_all_results: bool = false,
    source_text: ?[]const u8 = null,
};

pub const DumpSymbol = struct {
    name: []const u8,
    addr: u64,
    size: usize,
    element_size: usize = 0,
    element_count: usize = 1,
    initial: []u8,
};

const ResultExpression = struct {
    name: []const u8,
    text: []const u8,
};

const DumpShape = struct {
    size: usize,
    element_size: usize,
    element_count: usize,
};

const max_result_dump_bytes: usize = 8192;

pub fn collect(allocator: std.mem.Allocator, state: anytype, elf_bytes: []const u8, source_text: ?[]const u8) !std.ArrayList(DumpSymbol) {
    var declarations: std.ArrayList(asm_decls.SymbolDecl) = .empty;
    defer declarations.deinit(allocator);
    if (source_text) |text| {
        declarations = try asm_decls.collect(allocator, text);
    }

    var elf_symbols = try elf_loader.collectSymbols(allocator, elf_bytes);
    defer elf_symbols.deinit(allocator);

    var symbols: std.ArrayList(DumpSymbol) = .empty;
    errdefer deinitSymbols(allocator, &symbols);

    for (elf_symbols.items) |symbol| {
        const declaration = asm_decls.find(declarations.items, symbol.name);
        const shape = resultDumpShape(symbol.name, symbol.size, declaration, source_text != null) orelse continue;
        const mem_offset = state.addrToOffset(symbol.value) orelse continue;
        if (mem_offset + shape.size > state.mem.len) continue;

        const dump_symbol = DumpSymbol{
            .name = symbol.name,
            .addr = symbol.value,
            .size = shape.size,
            .element_size = shape.element_size,
            .element_count = shape.element_count,
            .initial = try allocator.alloc(u8, shape.size),
        };
        copySymbolBytes(state, symbol.value, dump_symbol.initial);
        try appendSorted(allocator, &symbols, dump_symbol);
    }

    return symbols;
}

pub fn dump(allocator: std.mem.Allocator, state: anytype, symbols: []const DumpSymbol, options: Options) !void {
    if (symbols.len == 0) {
        dumpPrint("Rosette ELF results: no result symbols found\n", .{});
        return;
    }

    var expressions: std.ArrayList(ResultExpression) = .empty;
    defer expressions.deinit(allocator);
    if (options.source_text) |source_text| {
        expressions = try collectResultExpressions(allocator, source_text);
    }

    var printed: usize = 0;
    for (symbols) |symbol| {
        if (!options.dump_all_results and !symbolChanged(state, symbol)) continue;
        printed += 1;
    }

    if (printed == 0) {
        dumpPrint("Rosette ELF results: no result values changed\n", .{});
        dumpPrint("  Set ROSETTE_ELF_DUMP_ALL=1 to include unchanged placeholders.\n", .{});
        return;
    }

    if (options.dump_all_results) {
        dumpPrint("Rosette ELF result summary ({d} symbols):\n", .{printed});
    } else {
        dumpPrint("Rosette ELF result summary ({d} changed symbols):\n", .{printed});
    }

    for (symbols) |symbol| {
        if (!options.dump_all_results and !symbolChanged(state, symbol)) continue;
        printSymbol(state, symbol, findResultExpression(expressions.items, symbol.name));
    }
}

pub fn deinitSymbols(allocator: std.mem.Allocator, symbols: *std.ArrayList(DumpSymbol)) void {
    for (symbols.items) |symbol| {
        allocator.free(symbol.initial);
    }
    symbols.deinit(allocator);
}

fn resultDumpShape(name: []const u8, reported_size: u64, declaration: ?asm_decls.SymbolDecl, source_available: bool) ?DumpShape {
    if (declaration) |decl| {
        const declared_size = decl.totalSize();
        if (declared_size == 0 or declared_size > max_result_dump_bytes) return null;
        const reported: usize = if (reported_size > 0 and reported_size <= max_result_dump_bytes) @intCast(reported_size) else 0;
        const size = if (reported != 0 and reported < declared_size) reported else declared_size;
        return .{
            .size = size,
            .element_size = decl.element_size,
            .element_count = @max(@as(usize, 1), size / decl.element_size),
        };
    }

    if (source_available) return null;
    const size = inferResultSymbolSize(name, reported_size);
    if (size == 0 or size > max_result_dump_bytes) return null;
    return .{
        .size = size,
        .element_size = size,
        .element_count = 1,
    };
}

fn inferResultSymbolSize(name: []const u8, reported_size: u64) usize {
    if (reported_size > 0 and reported_size <= max_result_dump_bytes) return @intCast(reported_size);
    if (name.len >= 2 and std.ascii.toLower(name[0]) == 'd' and std.ascii.toLower(name[1]) == 'q') return 16;
    if (name.len == 0) return 0;
    return switch (std.ascii.toLower(name[0])) {
        'b' => 1,
        'w' => 2,
        'd' => 4,
        'q' => 8,
        else => 0,
    };
}

fn copySymbolBytes(state: anytype, addr: u64, out: []u8) void {
    const start = state.addrToOffset(addr) orelse return;
    if (start + out.len > state.mem.len) return;
    @memcpy(out, state.mem[start..][0..out.len]);
}

fn symbolChanged(state: anytype, symbol: DumpSymbol) bool {
    const start = state.addrToOffset(symbol.addr) orelse return false;
    if (start + symbol.size > state.mem.len or symbol.size != symbol.initial.len) return false;
    return !std.mem.eql(u8, state.mem[start..][0..symbol.size], symbol.initial);
}

fn appendSorted(allocator: std.mem.Allocator, symbols: *std.ArrayList(DumpSymbol), symbol: DumpSymbol) !void {
    var insert_at: usize = 0;
    while (insert_at < symbols.items.len and symbols.items[insert_at].addr <= symbol.addr) : (insert_at += 1) {}

    try symbols.append(allocator, symbol);
    var i = symbols.items.len - 1;
    while (i > insert_at) : (i -= 1) {
        symbols.items[i] = symbols.items[i - 1];
    }
    symbols.items[insert_at] = symbol;
}

fn printSymbol(state: anytype, symbol: DumpSymbol, expression: ?[]const u8) void {
    if (symbol.element_count > 1 and symbol.element_size > 0 and symbol.size == symbol.element_size * symbol.element_count) {
        printArray(state, symbol, expression);
        return;
    }

    if (expression) |text| {
        dumpPrint("  {s} -> ", .{text});
    } else {
        dumpPrint("  {s} -> ", .{symbol.name});
    }
    switch (symbol.size) {
        1 => {
            const value = state.read8(symbol.addr);
            const signed: i8 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        2 => {
            const value = state.read16(symbol.addr);
            const signed: i16 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        4 => {
            const value = state.read32(symbol.addr);
            const signed: i32 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        8 => {
            const value = state.read64(symbol.addr);
            const signed: i64 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        16 => {
            const lo = state.read64(symbol.addr);
            const hi = state.read64(symbol.addr + 8);
            const combined = (@as(u128, hi) << 64) | lo;
            dumpPrint("unsigned {d}, hex 0x{x}, high {d}, low {d}", .{ combined, combined, hi, lo });
        },
        else => {
            dumpPrint("bytes=", .{});
            printHexBytes(state, symbol.addr, symbol.size);
        },
    }
    dumpPrint("\n", .{});
}

fn printArray(state: anytype, symbol: DumpSymbol, expression: ?[]const u8) void {
    if (expression) |text| {
        dumpPrint("  {s}[{d}] ({s}) ->", .{ text, symbol.element_count, elementTypeName(symbol.element_size) });
    } else {
        dumpPrint("  {s}[{d}] ({s}) ->", .{ symbol.name, symbol.element_count, elementTypeName(symbol.element_size) });
    }

    var i: usize = 0;
    while (i < symbol.element_count) : (i += 1) {
        if (i % 8 == 0) {
            dumpPrint("\n    [{d}] ", .{i});
        } else {
            dumpPrint(", ", .{});
        }
        printArrayElement(state, symbol.addr + @as(u64, @intCast(i * symbol.element_size)), symbol.element_size);
    }
    dumpPrint("\n", .{});
}

fn printArrayElement(state: anytype, addr: u64, element_size: usize) void {
    switch (element_size) {
        1 => {
            const value = state.read8(addr);
            const signed: i8 = @bitCast(value);
            dumpPrint("{d}", .{signed});
        },
        2 => {
            const value = state.read16(addr);
            const signed: i16 = @bitCast(value);
            dumpPrint("{d}", .{signed});
        },
        4 => {
            const value = state.read32(addr);
            const signed: i32 = @bitCast(value);
            dumpPrint("{d}", .{signed});
        },
        8 => {
            const value = state.read64(addr);
            const signed: i64 = @bitCast(value);
            dumpPrint("{d}", .{signed});
        },
        16 => {
            const lo = state.read64(addr);
            const hi = state.read64(addr + 8);
            const combined = (@as(u128, hi) << 64) | lo;
            dumpPrint("0x{x}", .{combined});
        },
        else => printHexBytes(state, addr, element_size),
    }
}

fn elementTypeName(element_size: usize) []const u8 {
    return switch (element_size) {
        1 => "byte",
        2 => "word",
        4 => "dword",
        8 => "qword",
        16 => "dqword",
        else => "bytes",
    };
}

fn collectResultExpressions(allocator: std.mem.Allocator, source_text: []const u8) !std.ArrayList(ResultExpression) {
    var expressions: std.ArrayList(ResultExpression) = .empty;
    errdefer expressions.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source_text, '\n');
    while (lines.next()) |line| {
        const comment_start = std.mem.indexOfScalar(u8, line, ';') orelse continue;
        const comment = std.mem.trim(u8, line[comment_start + 1 ..], " \t\r\n");
        const eq = std.mem.indexOfScalar(u8, comment, '=') orelse continue;
        const lhs = std.mem.trim(u8, comment[0..eq], " \t\r\n");
        if (lhs.len == 0) continue;
        const rhs = std.mem.trim(u8, comment[eq + 1 ..], " \t\r\n");
        if (rhs.len == 0) continue;
        if (findResultExpression(expressions.items, lhs) != null) continue;
        try expressions.append(allocator, .{
            .name = lhs,
            .text = comment,
        });
    }

    return expressions;
}

fn findResultExpression(expressions: []const ResultExpression, name: []const u8) ?[]const u8 {
    for (expressions) |expression| {
        if (std.mem.eql(u8, expression.name, name)) return expression.text;
    }
    return null;
}

fn printHexBytes(state: anytype, addr: u64, size: usize) void {
    const start = state.addrToOffset(addr) orelse return;
    if (start + size > state.mem.len) return;

    dumpPrint("0x", .{});
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const byte = state.mem[start + i];
        printHexByte(byte);
    }
}

fn printHexByte(byte: u8) void {
    const alphabet = "0123456789abcdef";
    dumpPrint("{c}{c}", .{ alphabet[@as(usize, byte >> 4)], alphabet[@as(usize, byte & 0x0f)] });
}

fn dumpPrint(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, fmt, args) catch return;
    writeHostAll(std.posix.STDOUT_FILENO, text) catch {};
}

fn writeHostAll(fd: std.c.fd_t, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const n = std.c.write(fd, data[written..].ptr, data.len - written);
        if (n <= 0) return error.WriteFailed;
        written += @intCast(n);
    }
}

test "dump shapes follow declared storage size rather than symbol names" {
    const source =
        \\section .data
        \\    alpha dw 0
        \\    beta db 75
        \\    gamma dw -1, 2, 3
        \\section .bss
        \\    delta resq 75
        \\    epsilon resb 500000
    ;

    var declarations = try asm_decls.collect(std.testing.allocator, source);
    defer declarations.deinit(std.testing.allocator);

    const alpha = resultDumpShape("alpha", 0, asm_decls.find(declarations.items, "alpha"), true).?;
    try std.testing.expectEqual(@as(usize, 2), alpha.size);
    try std.testing.expectEqual(@as(usize, 2), alpha.element_size);
    try std.testing.expectEqual(@as(usize, 1), alpha.element_count);

    const gamma = resultDumpShape("gamma", 0, asm_decls.find(declarations.items, "gamma"), true).?;
    try std.testing.expectEqual(@as(usize, 6), gamma.size);
    try std.testing.expectEqual(@as(usize, 2), gamma.element_size);
    try std.testing.expectEqual(@as(usize, 3), gamma.element_count);

    const delta = resultDumpShape("delta", 0, asm_decls.find(declarations.items, "delta"), true).?;
    try std.testing.expectEqual(@as(usize, 600), delta.size);
    try std.testing.expectEqual(@as(usize, 8), delta.element_size);
    try std.testing.expectEqual(@as(usize, 75), delta.element_count);

    try std.testing.expectEqual(null, resultDumpShape("epsilon", 0, asm_decls.find(declarations.items, "epsilon"), true));
}
