const std = @import("std");

pub const SYS_read: u64 = 0;
pub const SYS_write: u64 = 1;
pub const SYS_open: u64 = 2;
pub const SYS_close: u64 = 3;
pub const SYS_creat: u64 = 85;
pub const SYS_exit: u64 = 60;
pub const SYS_gettid: u64 = 186;

pub const Errno = enum(i64) {
    no_entry = -2,
    bad_file_descriptor = -9,
    permission_denied = -13,
    bad_address = -14,
    io = -5,
};

pub fn errnoValue(errno: Errno) u64 {
    return @bitCast(@intFromEnum(errno));
}

pub fn writeHostAll(fd: std.c.fd_t, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const n = std.c.write(fd, data[written..].ptr, data.len - written);
        if (n <= 0) return error.WriteFailed;
        written += @intCast(n);
    }
}
