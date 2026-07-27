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
