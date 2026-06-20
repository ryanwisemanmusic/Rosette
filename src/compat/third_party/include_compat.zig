const std = @import("std");

const candidate_subdirs = [_][]const u8{ "include", "lib", "src" };

pub fn discoverIncludeDirs(io: std.Io, allocator: std.mem.Allocator, project_root: []const u8) !std.ArrayList([]const u8) {
    var dirs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (dirs.items) |dir| allocator.free(dir);
        dirs.deinit(allocator);
    }

    const third_party = try std.fs.path.join(allocator, &.{ project_root, "third_party" });
    defer allocator.free(third_party);

    var root_dir = std.Io.Dir.openDirAbsolute(io, third_party, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir, error.AccessDenied => return dirs,
        else => |e| return e,
    };
    defer root_dir.close(io);

    var it = root_dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const package_root = try std.fs.path.join(allocator, &.{ third_party, entry.name });
        defer allocator.free(package_root);

        for (candidate_subdirs) |subdir| {
            const candidate = try std.fs.path.join(allocator, &.{ package_root, subdir });
            defer allocator.free(candidate);
            if (containsImmediateHeader(io, candidate)) {
                try appendUniqueOwned(allocator, &dirs, candidate);
            }
        }
    }

    return dirs;
}

fn appendUniqueOwned(allocator: std.mem.Allocator, dirs: *std.ArrayList([]const u8), candidate: []const u8) !void {
    for (dirs.items) |existing| {
        if (std.mem.eql(u8, existing, candidate)) return;
    }
    try dirs.append(allocator, try allocator.dupe(u8, candidate));
}

fn containsImmediateHeader(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch return false;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (hasHeaderExtension(entry.name)) return true;
    }
    return false;
}

pub fn hasHeaderExtension(name: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(name, ".h") or
        std.ascii.endsWithIgnoreCase(name, ".hh") or
        std.ascii.endsWithIgnoreCase(name, ".hpp") or
        std.ascii.endsWithIgnoreCase(name, ".hxx");
}

test "header extension detection covers C and C++ headers" {
    try std.testing.expect(hasHeaderExtension("zstd.h"));
    try std.testing.expect(hasHeaderExtension("reader.HPP"));
    try std.testing.expect(!hasHeaderExtension("zstd.c"));
}
