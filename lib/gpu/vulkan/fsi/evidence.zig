//! Bounded exact shader evidence beside the run log, before and after adaptation.
//! The normal launcher enables it; ROSETTE_FSI_EVIDENCE=0 opts out.
const std = @import("std");
const tracker = @import("tracker.zig");
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fwrite(data: [*]const u8, size: usize, count: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn mkdir(path: [*:0]const u8, mode: std.c.mode_t) c_int;
extern "c" fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
extern "c" fn fread(data: [*]u8, size: usize, count: usize, stream: *anyopaque) usize;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn rmdir(path: [*:0]const u8) c_int;

pub const maximum_module_bytes: usize = 32 * 1024 * 1024;
pub const maximum_run_bytes: usize = 256 * 1024 * 1024;
pub const Result = enum { saved, invalid, limited, failed };
pub const Version = enum { guest, native };

pub fn filename(storage: []u8, guest: u64, hash: u64, version: Version) ![]const u8 {
    return std.fmt.bufPrint(storage, "module-{x}-{x}.{s}.spv", .{ guest, hash, @tagName(version) });
}

pub const Writer = struct {
    bytes_saved: usize = 0,
    modules_saved: u64 = 0,
    failures: u64 = 0,
    limits: u64 = 0,

    pub fn save(self: *Writer, run_directory: []const u8, guest: u64, words: []const u32, version: Version) Result {
        const bytes = std.mem.sliceAsBytes(words);
        if (words.len < 5 or words[0] != 0x0723_0203 or bytes.len > maximum_module_bytes) return .invalid;
        if (bytes.len > maximum_run_bytes - self.bytes_saved) {
            self.limits +|= 1;
            return .limited;
        }
        var folder_buffer: [4096]u8 = undefined;
        const folder = std.fmt.bufPrintZ(&folder_buffer, "{s}/vulkan-shaders", .{run_directory}) catch return self.fail();
        _ = mkdir(folder, 0o700);
        var name_buffer: [96]u8 = undefined;
        const name = filename(&name_buffer, guest, tracker.spirvFingerprint(words), version) catch return self.fail();
        var path_buffer: [4096]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buffer, "{s}/{s}", .{ folder, name }) catch return self.fail();
        const file = fopen(path, "wb") orelse return self.fail();
        const written = fwrite(bytes.ptr, 1, bytes.len, file);
        const closed = fclose(file);
        if (written != bytes.len or closed != 0) return self.fail();
        self.bytes_saved += bytes.len;
        self.modules_saved +|= 1;
        return .saved;
    }

    fn fail(self: *Writer) Result {
        self.failures +|= 1;
        return .failed;
    }
};

test "FSI shader evidence names original and native modules separately" {
    var buffer: [96]u8 = undefined;
    try std.testing.expectEqualStrings("module-ab-1234.guest.spv", try filename(&buffer, 0xAB, 0x1234, .guest));
    try std.testing.expectEqualStrings("module-ab-1234.native.spv", try filename(&buffer, 0xAB, 0x1234, .native));
    var writer = Writer{ .bytes_saved = maximum_run_bytes };
    try std.testing.expectEqual(Result.invalid, writer.save("/unused", 1, &.{}, .native));
    try std.testing.expectEqual(Result.limited, writer.save("/unused", 1, &.{ 0x0723_0203, 0x10000, 0, 1, 0 }, .native));
}

test "FSI shader evidence preserves driver words on disk and reports IO failure" {
    var temporary = "/tmp/rosette-fsi-evidence-XXXXXX".*;
    const folder = mkdtemp(&temporary) orelse return error.TestUnexpectedResult;
    defer _ = rmdir(folder);
    const words = [_]u32{ 0x0723_0203, 0x0001_0000, 0, 1, 0, 0x0001_0000 };
    var writer = Writer{};
    var child_buffer: [4096]u8 = undefined;
    const child = try std.fmt.bufPrintZ(&child_buffer, "{s}/vulkan-shaders", .{folder});
    defer _ = rmdir(child);
    for ([_]Version{ .guest, .native }) |version| {
        try std.testing.expectEqual(Result.saved, writer.save(std.mem.span(folder), 0xAB, &words, version));
        var name_buffer: [96]u8 = undefined;
        const name = try filename(&name_buffer, 0xAB, tracker.spirvFingerprint(&words), version);
        var path_buffer: [4096]u8 = undefined;
        const path = try std.fmt.bufPrintZ(&path_buffer, "{s}/{s}", .{ child, name });
        defer _ = unlink(path);
        const file = fopen(path, "rb") orelse return error.TestUnexpectedResult;
        defer _ = fclose(file);
        var actual: [@sizeOf(@TypeOf(words)) + 1]u8 = undefined;
        const count = fread(&actual, 1, actual.len, file);
        try std.testing.expectEqual(@sizeOf(@TypeOf(words)), count);
        try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(&words), actual[0..count]);
    }
    try std.testing.expectEqual(@as(usize, @sizeOf(@TypeOf(words)) * 2), writer.bytes_saved);
    try std.testing.expectEqual(@as(u64, 2), writer.modules_saved);
    // A file cannot be used as a parent directory. This exercises failure
    // without relying on host permissions or leaving files behind.
    var occupied_buffer: [4096]u8 = undefined;
    const occupied = try std.fmt.bufPrintZ(&occupied_buffer, "{s}/occupied", .{folder});
    const file = fopen(occupied, "wb") orelse return error.TestUnexpectedResult;
    _ = fclose(file);
    defer _ = unlink(occupied);
    try std.testing.expectEqual(Result.failed, writer.save(occupied, 0xAB, &words, .native));
    try std.testing.expectEqual(@as(u64, 1), writer.failures);
}
