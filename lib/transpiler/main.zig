const std = @import("std");
const c_fix = @import("c_fix.zig");

pub fn main() !void {
    const stderr = std.fs.File.stderr;
    const stdout = std.fs.File.stdout;
    const stdin = std.fs.File.stdin;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit(allocator);

    var in_place = false;
    var file_args: []const []const u8 = &.{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--in_place") or std.mem.eql(u8, args[i], "-i")) {
            in_place = true;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            try usage(stderr, args[0]);
            return;
        } else {
            file_args = args[i..];
            break;
        }
    }

    if (file_args.len == 0) {
        const source = try stdin.readToEndAlloc(allocator, 1 << 24);
        var result = try c_fix.fixSource(allocator, source);
        defer result.deinit(allocator);
        const output = try c_fix.applyEdits(allocator, source, result.edits.items);
        defer allocator.free(output);
        try stdout.writeAll(output);
        return;
    }

    for (file_args) |filepath| {
        const file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();
        const source = try file.readToEndAlloc(allocator, 1 << 24);
        defer allocator.free(source);

        var result = try c_fix.fixSource(allocator, source);
        defer result.deinit(allocator);

        if (in_place) {
            const output = try c_fix.applyEdits(allocator, source, result.edits.items);
            defer allocator.free(output);
            try std.fs.cwd().writeFile(filepath, output);
        } else {
            const output = try c_fix.applyEdits(allocator, source, result.edits.items);
            defer allocator.free(output);
            try stdout.writeAll(output);
        }
    }
}

fn usage(stderr: std.fs.File, exe: []const u8) !void {
    try stderr.writer().print(
        \\Usage: {s} [options] [file...]
        \\
        \\Scans C source for implicit narrowing conversions and inserts explicit casts.
        \\If no file is given, reads from stdin and writes to stdout.
        \\
        \\Options:
        \\  -i, --in-place   Modify files in place
        \\  -h, --help       Show this help
        \\
    , .{exe});
}