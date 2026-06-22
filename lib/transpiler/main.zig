const std = @import("std");
const c_fix = @import("c_fix.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    var in_place = false;
    var cpp_mode = false;
    var file_args: []const []const u8 = &.{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--in-place") or
            std.mem.eql(u8, args[i], "--in_place") or
            std.mem.eql(u8, args[i], "-i"))
        {
            in_place = true;
        } else if (std.mem.eql(u8, args[i], "--cpp") or std.mem.eql(u8, args[i], "--lang=cpp")) {
            cpp_mode = true;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            try usage(init.io, args[0]);
            return;
        } else {
            file_args = args[i..];
            break;
        }
    }

    if (file_args.len == 0) {
        var stdin_buffer: [4096]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
        const source = try stdin_reader.interface.allocRemaining(allocator, .limited(1 << 24));
        var result = try c_fix.fixSourceWithMode(allocator, source, cpp_mode);
        defer result.deinit(allocator);
        const output = try c_fix.applyEdits(allocator, source, result.edits.items);
        defer allocator.free(output);
        try stdout.writeAll(output);
        try stdout.flush();
        return;
    }

    for (file_args) |filepath| {
        const source = try std.Io.Dir.cwd().readFileAlloc(init.io, filepath, allocator, .limited(1 << 24));
        defer allocator.free(source);

        var is_cpp = cpp_mode;
        if (!is_cpp) {
            if (std.mem.endsWith(u8, filepath, ".cc") or
                std.mem.endsWith(u8, filepath, ".cpp") or
                std.mem.endsWith(u8, filepath, ".cxx") or
                std.mem.endsWith(u8, filepath, ".mm"))
            {
                is_cpp = true;
            }
        }

        var result = try c_fix.fixSourceWithMode(allocator, source, is_cpp);
        defer result.deinit(allocator);

        if (in_place) {
            const output = try c_fix.applyEdits(allocator, source, result.edits.items);
            defer allocator.free(output);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = filepath, .data = output });
        } else {
            const output = try c_fix.applyEdits(allocator, source, result.edits.items);
            defer allocator.free(output);
            try stdout.writeAll(output);
        }
    }
    try stdout.flush();
}

fn usage(io: std.Io, exe: []const u8) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try stderr.print(
        \\Usage: {s} [options] [file...]
        \\
        \\Scans C/C++ source for implicit narrowing conversions and inserts explicit casts.
        \\If no file is given, reads from stdin and writes to stdout.
        \\
        \\Options:
        \\  -i, --in-place   Modify files in place
        \\  --cpp            Enable C++ mode (auto-detected from .cc/.cpp/.cxx/.mm)
        \\  -h, --help       Show this help
        \\
    , .{exe});
    try stderr.flush();
}
