const std = @import("std");
const c_fix = @import("c_fix.zig");
const windows_xenia_cpp = @import("windows_xenia_cpp.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    // Deliberately separate from --in-place and the heuristic C passes.
    // Both modes only emit Rosette-owned outputs; the input tree is read-only.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--windows-xenia-overlay")) {
        if (args.len != 4) return error.ExpectedSourceRootAndOutputDirectory;
        const overlay = try generateWindowsOverlay(allocator, init.io, args[2], args[3]);
        try stdout.print("{s}\n", .{overlay});
        try stdout.flush();
        return;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--windows-xenia-file")) {
        if (args.len != 4) return error.ExpectedProfilePathAndInputFile;
        const source = try std.Io.Dir.cwd().readFileAlloc(init.io, args[3], allocator, .limited(1 << 26));
        var result = try windows_xenia_cpp.fix(allocator, args[2], source);
        defer result.deinit(allocator);
        const output = try c_fix.applyEdits(allocator, source, result.edits.items);
        try stdout.writeAll(output);
        try stdout.flush();
        return;
    }

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

fn generateWindowsOverlay(allocator: std.mem.Allocator, io: std.Io, source_root: []const u8, output_dir: []const u8) ![]const u8 {
    if (!std.fs.path.isAbsolute(source_root) or !std.fs.path.isAbsolute(output_dir)) return error.OverlayPathsMustBeAbsolute;
    // Resolve symlinks before admitting an output directory. A path spelling
    // outside Xenia must not resolve back into its checkout or source mirror.
    const cwd = std.Io.Dir.cwd();
    const source_real = try cwd.realPathFileAlloc(io, source_root, allocator);
    const output_real = try cwd.realPathFileAlloc(io, output_dir, allocator);
    if (std.mem.eql(u8, output_real, source_real) or
        (std.mem.startsWith(u8, output_real, source_real) and output_real.len > source_real.len and output_real[source_real.len] == '/'))
        return error.OverlayOutputMustBeOutsideSourceTree;

    const Entry = struct {
        type: []const u8 = "file",
        name: []const u8,
        @"external-contents": []const u8,
    };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);
    for (windows_xenia_cpp.files, 0..) |relative, index| {
        const input = try std.fs.path.join(allocator, &.{ source_real, relative });
        const source = try cwd.readFileAlloc(io, input, allocator, .limited(1 << 26));
        var result = try windows_xenia_cpp.fix(allocator, relative, source);
        defer result.deinit(allocator);
        const output = try c_fix.applyEdits(allocator, source, result.edits.items);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(output, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        const filename = try std.fmt.allocPrint(allocator, "translated-{d}-{s}{s}", .{ index, hex, std.fs.path.extension(relative) });
        const external = try std.fs.path.join(allocator, &.{ output_real, filename });
        try cwd.writeFile(io, .{ .sub_path = external, .data = output });
        try entries.append(allocator, .{ .name = input, .@"external-contents" = external });
    }
    const json = try std.json.Stringify.valueAlloc(allocator, .{
        .version = @as(u32, 0),
        .@"use-external-names" = false,
        .roots = entries.items,
    }, .{});
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(json, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    // A content-addressed compiler argument invalidates Ninja's command key
    // even when unchanged virtual include paths retain their original mtimes.
    const name = try std.fmt.allocPrint(allocator, "windows-cpp-{s}.json", .{hex});
    const path = try std.fs.path.join(allocator, &.{ output_real, name });
    try cwd.writeFile(io, .{ .sub_path = path, .data = json });
    return path;
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
        \\  --windows-xenia-file PROFILE_PATH INPUT_FILE
        \\                   Emit only the opt-in Clang/MinGW Xenia profile
        \\  --windows-xenia-overlay ABS_SOURCE_ROOT ABS_OUTPUT_DIR
        \\                   Emit translated inputs + Clang VFS in existing output dir
        \\  -h, --help       Show this help
        \\
    , .{exe});
    try stderr.flush();
}
