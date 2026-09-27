//! Output the guest could not have meant to write.
//!
//! The first visible sign of the 2026-09-24 memory-model defect was on disk,
//! seconds into the run: Xenia's log file was created as `0H;C\x01.log` - the
//! low bytes of a heap pointer where `xenia` should have been - and its TOML
//! config was written with 5,011 NUL bytes in place of section names. Nothing
//! in the run log said so; the config was only noticed on the next launch,
//! when the launcher had to repair it.
//!
//! These checks look at what the guest hands the host file layer and name
//! both symptoms as they happen: a file name with control bytes in it, and a
//! text file (by extension) receiving NUL bytes. Either one means the guest
//! formatted a string from memory that did not hold what it expected, which
//! on Rosette is a memory-model or translation defect until proven otherwise.

const std = @import("std");

const text_extensions = [_][]const u8{
    ".toml", ".log", ".txt", ".ini", ".json", ".cfg", ".xml", ".csv", ".md", ".yaml", ".yml",
};

/// Whether `path` names a file whose contents are text by convention.
pub fn isTextPath(path: []const u8) bool {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return false;
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse 0;
    if (dot < slash) return false;
    const extension = path[dot..];
    for (text_extensions) |candidate| {
        if (std.ascii.eqlIgnoreCase(extension, candidate)) return true;
    }
    return false;
}

pub const NulFinding = struct {
    count: usize,
    first: usize,
};

/// NUL bytes in a payload bound for a text file, or null when there are
/// none. A text writer never emits one, so even one is a finding.
pub fn nulBytes(payload: []const u8) ?NulFinding {
    const first = std.mem.indexOfScalar(u8, payload, 0) orelse return null;
    var count: usize = 0;
    for (payload[first..]) |byte| {
        if (byte == 0) count += 1;
    }
    return .{ .count = count, .first = first };
}

/// The first control byte in a path's last component, or null. Path
/// separators are fine; a byte below 0x20 or 0x7F is not something any
/// Windows file name the guest meant to create contains.
pub fn controlByteInName(path: []const u8) ?struct { offset: usize, byte: u8 } {
    const start = if (std.mem.lastIndexOfAny(u8, path, "/\\")) |slash| slash + 1 else 0;
    for (path[start..], start..) |byte, offset| {
        if (byte < 0x20 or byte == 0x7F) return .{ .offset = offset, .byte = byte };
    }
    return null;
}

/// Render `bytes` for a log line: printable ASCII as itself, everything else
/// as `\xNN`. Returns the rendered prefix that fit.
pub fn escape(bytes: []const u8, destination: []u8) []const u8 {
    var used: usize = 0;
    for (bytes) |byte| {
        if (byte >= 0x20 and byte < 0x7F and byte != '\\') {
            if (used + 1 > destination.len) break;
            destination[used] = byte;
            used += 1;
        } else {
            if (used + 4 > destination.len) break;
            _ = std.fmt.bufPrint(destination[used..][0..4], "\\x{x:0>2}", .{byte}) catch break;
            used += 4;
        }
    }
    return destination[0..used];
}

test "text paths are recognised by their extension" {
    try std.testing.expect(isTextPath("/bundle/xenia-canary.config.toml"));
    try std.testing.expect(isTextPath("C:\\xenia\\xenia.LOG"));
    try std.testing.expect(!isTextPath("/bundle/cache/shaders.bin"));
    try std.testing.expect(!isTextPath("/bundle/some.dir/file"));
    try std.testing.expect(!isTextPath("noextension"));
}

test "NUL bytes in a text payload are counted from the first" {
    try std.testing.expect(nulBytes("[APU]\napu = 'any'\n") == null);
    const finding = nulBytes("[\x00\x00\x00]\n").?;
    try std.testing.expectEqual(@as(usize, 3), finding.count);
    try std.testing.expectEqual(@as(usize, 1), finding.first);
}

test "a file name built from a pointer's bytes is caught" {
    // The name Xenia's log file was created with on 2026-09-24.
    const found = controlByteInName("/bundle/0H;C\x01.log").?;
    try std.testing.expectEqual(@as(u8, 0x01), found.byte);
    try std.testing.expect(controlByteInName("/bundle/xenia.log") == null);
    // A control byte in a directory is not the file's name.
    try std.testing.expect(controlByteInName("/odd\x01dir/xenia.log") == null);
}

test "escaped excerpts keep printable text and mark everything else" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("0H;C\\x01.log", escape("0H;C\x01.log", &buffer));
    var small: [5]u8 = undefined;
    try std.testing.expectEqualStrings("ab", escape("ab\x00", &small)[0..2]);
}
