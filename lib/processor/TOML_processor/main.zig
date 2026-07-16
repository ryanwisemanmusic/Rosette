const std = @import("std");
const toml = @import("root.zig");
const types = toml.types;
const Value = types.Value;
const Table = types.Table;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        std.debug.print("Usage: toml_processor <toml-file>\n", .{});
        std.process.exit(1);
    }

    const file_path = args[1];
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, file_path, allocator, .unlimited);

    const file_name = std.fs.path.basename(file_path);
    var ascii = true;
    var nul_count: usize = 0;
    var newline_count: usize = 0;
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (source) |byte| {
        if (byte >= 0x80) ascii = false;
        if (byte == 0) nul_count += 1;
        if (byte == '\n') newline_count += 1;
        hash = (hash ^ byte) *% 0x100_0000_01b3;
    }
    std.debug.print(
        "TOML preflight: path={s} bytes={d} ascii={} utf8={} embedded_nul={d} newlines={d} fnv1a64=0x{x}\n",
        .{ file_path, source.len, ascii, std.unicode.utf8ValidateSlice(source), nul_count, newline_count, hash },
    );
    std.debug.print("\n=== {s} : TOML FILE READOUT ===\n", .{file_name});
    const displayed = @min(source.len, 64 * 1024);
    std.debug.print("{s}", .{source[0..displayed]});
    if (displayed < source.len) std.debug.print("\n... truncated {d} bytes ...\n", .{source.len - displayed});
    std.debug.print("=== END TOML FILE READOUT ===\n", .{});

    var parser = toml.parser.Parser.init(allocator, source);
    var table = parser.parse() catch |err| {
        const diagnostic_info = parser.diagnostic();
        var context_hex: [96]u8 = undefined;
        const shown = @min(diagnostic_info.context.len, context_hex.len / 2);
        const alphabet = "0123456789abcdef";
        for (diagnostic_info.context[0..shown], 0..) |byte, index| {
            context_hex[index * 2] = alphabet[byte >> 4];
            context_hex[index * 2 + 1] = alphabet[byte & 0x0f];
        }
        std.debug.print(
            "TOML parse failure: error={} byte_offset={d} line={d} column={d} context_start={d} context_hex={s}\n",
            .{ err, diagnostic_info.byte_offset, diagnostic_info.line, diagnostic_info.column, diagnostic_info.context_start, context_hex[0 .. shown * 2] },
        );
        std.process.exit(1);
    };
    defer table.deinit(allocator);

    std.debug.print("\n=== TOML Parse Results ===\n", .{});
    printTable(&table, allocator, 0);
}

fn printTable(table: *const Table, allocator: std.mem.Allocator, depth: usize) void {
    const indent = "    ";
    for (table.keys()) |key| {
        const val = table.get(key).?;
        for (0..depth) |_| std.debug.print("{s}", .{indent});
        switch (val.*) {
            .string => |s| std.debug.print("{s} = \"{s}\"\n", .{ key, s }),
            .integer => |i| std.debug.print("{s} = {d} (0x{x})\n", .{ key, i, @as(u64, @bitCast(i)) }),
            .boolean => |b| std.debug.print("{s} = {}\n", .{ key, b }),
            .array => |*arr| {
                std.debug.print("{s} = [", .{key});
                for (arr.items, 0..) |*item, idx| {
                    if (idx > 0) std.debug.print(", ", .{});
                    printValue(item);
                }
                std.debug.print("]\n", .{});
            },
            .table => |*t| {
                std.debug.print("[{s}]\n", .{key});
                printTable(t, allocator, depth + 1);
            },
            else => std.debug.print("{s} = <other>\n", .{key}),
        }
    }

    for (table.getTableArrayKeys()) |key| {
        const arr = table.getTableArray(key).?;
        for (0..depth) |_| std.debug.print("{s}", .{indent});
        std.debug.print("[[{s}]] ({d} entries)\n", .{ key, arr.items.len });
        for (arr.items, 0..) |*t, idx| {
            for (0..depth + 1) |_| std.debug.print("{s}", .{indent});
            std.debug.print("[{d}]\n", .{idx});
            printTable(t, allocator, depth + 2);
        }
    }
}

fn printValue(val: *const Value) void {
    switch (val.*) {
        .string => |s| std.debug.print("\"{s}\"", .{s}),
        .integer => |i| std.debug.print("{d}", .{i}),
        .boolean => |b| std.debug.print("{}", .{b}),
        else => std.debug.print("<complex>", .{}),
    }
}
