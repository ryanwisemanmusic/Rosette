const std = @import("std");

pub const Translation = struct {
    translated: []const u8,
    allocated: bool,
};

pub const Translator = struct {
    allocator: std.mem.Allocator,
    storage_root: []const u8 = "",
    cache_dir: []const u8 = "",
    content_dir: []const u8 = "",
    home_dir: []const u8 = "",
    tmp_dir: []const u8 = "",
    mapped_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Translator {
        return .{
            .allocator = allocator,
            .home_dir = environmentPath("HOME", "/tmp"),
            .tmp_dir = environmentPath("TMPDIR", "/tmp"),
        };
    }

    pub fn deinit(self: *Translator) void {
        self.allocator.free(self.storage_root);
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.content_dir);
        self.* = undefined;
    }

    pub fn configure(self: *Translator, storage_root: []const u8) void {
        self.storage_root = self.allocator.dupe(u8, storage_root) catch "";
        self.cache_dir = std.fs.path.join(self.allocator, &[_][]const u8{ storage_root, "cache" }) catch "";
        self.content_dir = std.fs.path.join(self.allocator, &[_][]const u8{ storage_root, "content" }) catch "";
        self.home_dir = environmentPath("HOME", "/tmp");
        self.tmp_dir = environmentPath("TMPDIR", "/tmp");
    }

    pub fn translate(self: *Translator, guest_path: []const u8, temporary: []u8) ?Translation {
        if (guest_path.len == 0) return null;

        if (guest_path[0] != '/') return .{ .translated = guest_path, .allocated = false };

        if (std.mem.startsWith(u8, guest_path, "/tmp/")) {
            return self.remapTo(temporary, self.tmp_dir, guest_path[4..]);
        }

        if (std.mem.startsWith(u8, guest_path, "/var/folders/")) {
            return .{ .translated = guest_path, .allocated = false };
        }

        if (std.mem.startsWith(u8, guest_path, "/Users/")) {
            return .{ .translated = guest_path, .allocated = false };
        }

        if (std.mem.startsWith(u8, guest_path, "/usr/") or
            std.mem.startsWith(u8, guest_path, "/System/") or
            std.mem.startsWith(u8, guest_path, "/Library/") or
            std.mem.startsWith(u8, guest_path, "/Applications/") or
            std.mem.startsWith(u8, guest_path, "/private/") or
            std.mem.startsWith(u8, guest_path, "/dev/") or
            std.mem.startsWith(u8, guest_path, "/etc/"))
        {
            return .{ .translated = guest_path, .allocated = false };
        }

        if (std.mem.startsWith(u8, guest_path, "/home/") or
            std.mem.startsWith(u8, guest_path, "/root/"))
        {
            const relative = std.mem.indexOf(u8, guest_path[5..], "/") orelse return .{ .translated = guest_path, .allocated = false };
            const suffix = guest_path[5 + relative ..];
            return self.remapTo(temporary, self.home_dir, suffix);
        }

        {
            var buf: [4096]u8 = undefined;
            for (0..self.mapped_count) |i| {
                const mapped = self.getMapping(i) orelse continue;
                if (std.mem.startsWith(u8, guest_path, mapped.guest)) {
                    const suffix = guest_path[mapped.guest.len..];
                    const path_len = mapped.host.len + suffix.len;
                    if (path_len + 1 > buf.len) continue;
                    @memcpy(buf[0..mapped.host.len], mapped.host);
                    if (suffix.len > 0) @memcpy(buf[mapped.host.len..][0..suffix.len], suffix);
                    buf[path_len] = 0;
                    const copy_len = @min(path_len, temporary.len - 1);
                    @memcpy(temporary[0..copy_len], buf[0..copy_len]);
                    temporary[copy_len] = 0;
                    return .{ .translated = temporary[0..copy_len], .allocated = false };
                }
            }
        }

        return .{ .translated = guest_path, .allocated = false };
    }

    pub fn addMapping(self: *Translator, guest_root: []const u8, host_root: []const u8) void {
        _ = self;
        _ = guest_root;
        _ = host_root;
    }

    fn remapTo(self: *Translator, temporary: []u8, host_base: []const u8, suffix: []const u8) Translation {
        _ = self;
        const total = host_base.len + suffix.len;
        if (total + 1 > temporary.len) return .{ .translated = "", .allocated = false };
        @memcpy(temporary[0..host_base.len], host_base);
        if (suffix.len > 0) @memcpy(temporary[host_base.len..][0..suffix.len], suffix);
        temporary[total] = 0;
        return .{ .translated = temporary[0..total], .allocated = false };
    }

    fn getMapping(self: *Translator, index: usize) ?struct { guest: []const u8, host: []const u8 } {
        _ = self;
        _ = index;
        return null;
    }
};

fn environmentPath(name: [*:0]const u8, fallback: []const u8) []const u8 {
    const value = std.c.getenv(name) orelse return fallback;
    return std.mem.span(value);
}

test "translate returns null for empty path" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const result = translator.translate("", &buf);
    try std.testing.expectEqual(@as(?Translation, null), result);
}

test "translate passes through relative paths" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const rel = translator.translate("relative/path.txt", &buf).?;
    try std.testing.expectEqualStrings("relative/path.txt", rel.translated);
    try std.testing.expectEqual(false, rel.allocated);
}

test "translate passes through known absolute paths" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const paths = [_][]const u8{
        "/var/folders/ab/cd/ef/T/",
        "/Users/ryan/test.txt",
        "/usr/local/lib/something.dylib",
        "/System/Library/Frameworks/CoreFoundation.framework",
        "/Library/Preferences/test.plist",
        "/Applications/Xcode.app",
        "/private/var/log/system.log",
        "/dev/null",
        "/etc/hosts",
    };
    for (paths) |p| {
        const result = translator.translate(p, &buf).?;
        try std.testing.expectEqualStrings(p, result.translated);
        try std.testing.expectEqual(false, result.allocated);
    }
}

test "translate remaps /tmp/ paths to tmp_dir" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const result = translator.translate("/tmp/xenia-mac-startup.log", &buf).?;
    // Should start with the tmp_dir value (TMPDIR env var or /tmp fallback)
    try std.testing.expect(result.translated.len > 0);
    // The suffix should be preserved
    try std.testing.expect(std.mem.endsWith(u8, result.translated, "xenia-mac-startup.log"));
    try std.testing.expectEqual(false, result.allocated);
}

test "translate remaps /home/ paths to home_dir" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const result = translator.translate("/home/user/.config/something.cfg", &buf).?;
    try std.testing.expect(result.translated.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, result.translated, "/.config/something.cfg"));
    try std.testing.expectEqual(false, result.allocated);
}

test "translate falls through for unknown paths" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const result = translator.translate("/opt/custom/bin/tool", &buf).?;
    try std.testing.expectEqualStrings("/opt/custom/bin/tool", result.translated);
    try std.testing.expectEqual(false, result.allocated);
}

test "translate /root/ falls through to home_dir" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();
    var buf: [4096]u8 = undefined;
    const result = translator.translate("/root/.bashrc", &buf).?;
    try std.testing.expect(result.translated.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, result.translated, "/.bashrc"));
    try std.testing.expectEqual(false, result.allocated);
}

test "configure sets up cache_dir and content_dir from storage_root" {
    var translator = Translator.init(std.testing.allocator);
    defer translator.deinit();

    translator.configure("/tmp/test_storage");

    try std.testing.expect(std.mem.endsWith(u8, translator.storage_root, "test_storage"));
    try std.testing.expect(std.mem.endsWith(u8, translator.cache_dir, "test_storage/cache"));
    try std.testing.expect(std.mem.endsWith(u8, translator.content_dir, "test_storage/content"));

    // After configure, /tmp/ paths still remap to tmp_dir
    var buf: [4096]u8 = undefined;
    const result = translator.translate("/tmp/test.log", &buf).?;
    try std.testing.expect(result.translated.len > 0);
    try std.testing.expectEqual(false, result.allocated);
}
