const std = @import("std");
const path_translation = @import("path_translation.zig");
const fd_management = @import("fd_management.zig");

extern "c" fn shm_open(name: [*:0]const u8, oflag: c_int, mode: std.c.mode_t) c_int;
extern "c" fn shm_unlink(name: [*:0]const u8) c_int;
extern "c" fn socket(domain: c_int, socket_type: c_int, protocol: c_int) c_int;
extern "c" fn setsockopt(fd: c_int, level: c_int, option: c_int, value: ?*const anyopaque, length: u32) c_int;
extern "c" fn connect(fd: c_int, address: *const anyopaque, length: u32) c_int;
extern "c" fn send(fd: c_int, buffer: *const anyopaque, length: usize, flags: c_int) isize;

pub const Forwarder = struct {
    translator: path_translation.Translator,
    fd_manager: fd_management.Manager,
    open_count: u64 = 0,
    read_count: u64 = 0,
    write_count: u64 = 0,
    close_count: u64 = 0,
    mmap_count: u64 = 0,
    shm_open_count: u64 = 0,
    shm_fallback_count: u64 = 0,
    ftruncate_count: u64 = 0,
    stat_count: u64 = 0,
    seek_count: u64 = 0,
    access_count: u64 = 0,
    directory_read_count: u64 = 0,
    errno_updates: u64 = 0,
    last_errno: c_int = 0,

    pub fn init(allocator: std.mem.Allocator) Forwarder {
        return .{
            .translator = path_translation.Translator.init(allocator),
            .fd_manager = fd_management.Manager.init(allocator),
        };
    }

    pub fn deinit(self: *Forwarder) void {
        self.fd_manager.deinit();
        self.translator.deinit();
        self.* = undefined;
    }

    pub fn configurePaths(self: *Forwarder, storage_root: []const u8) void {
        self.translator.configure(storage_root);
        std.debug.print("macho-processor: fs forwarding storage root: {s}\n", .{storage_root});
    }

    pub fn storageRoot(self: *const Forwarder) []const u8 {
        return self.translator.storage_root;
    }

    pub fn resolveHostPath(self: *Forwarder, guest_path: []const u8, temporary: []u8) ?[]const u8 {
        const translation = self.translator.translate(guest_path, temporary) orelse return null;
        if (translation.translated.len == 0) return null;
        return translation.translated;
    }

    pub fn open(self: *Forwarder, state: anytype) u64 {
        self.open_count += 1;
        const path = state.guestCString(state.regs.rdi, 4096) orelse return self.fail(state, .FAULT);
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return self.fail(state, .NOMEM);
        path_buffer.append(self.translator.allocator, 0) catch return self.fail(state, .NOMEM);

        const host_fd = std.c.open(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @bitCast(@as(u32, @truncate(state.regs.rsi))),
            @as(c_int, @intCast(state.regs.rdx & 0xFFFF)),
        );
        if (host_fd < 0) {
            if (isDiagnosticPath(path) or isDiagnosticPath(translated_path)) {
                std.debug.print(
                    "macho-processor: fs open FAILED: guest_path={s} host_path={s} flags=0x{x} mode=0{o} errno={s}\n",
                    .{ path, translated_path, state.regs.rsi, state.regs.rdx & 0xFFFF, @tagName(std.c.errno(host_fd)) },
                );
            }
            return self.failHost(state, host_fd);
        }
        const guest_fd = self.fd_manager.register(host_fd, .file) orelse return self.fail(state, .NOMEM);
        if (shouldTrace(self.open_count) or isDiagnosticPath(path) or isDiagnosticPath(translated_path)) {
            std.debug.print("macho-processor: fs open #{d}: guest_path={s} host_path={s} -> guest_fd={d} host_fd={d}\n", .{ self.open_count, path, translated_path, guest_fd, host_fd });
        }
        return guest_fd;
    }

    pub fn openat(self: *Forwarder, state: anytype) u64 {
        self.open_count += 1;
        const dir_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return self.fail(state, .BADF);
        const path = state.guestCString(state.regs.rsi, 4096) orelse return self.fail(state, .FAULT);
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return self.fail(state, .NOMEM);
        path_buffer.append(self.translator.allocator, 0) catch return self.fail(state, .NOMEM);

        const host_fd = std.c.openat(
            dir_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @bitCast(@as(u32, @truncate(state.regs.rdx))),
            @as(c_int, @intCast(state.regs.rcx & 0xFFFF)),
        );
        if (host_fd < 0) {
            if (isDiagnosticPath(path) or isDiagnosticPath(translated_path)) {
                std.debug.print(
                    "macho-processor: fs openat FAILED: dir_guest_fd={d} guest_path={s} host_path={s} flags=0x{x} errno={s}\n",
                    .{ state.regs.rdi, path, translated_path, state.regs.rdx, @tagName(std.c.errno(host_fd)) },
                );
            }
            return self.failHost(state, host_fd);
        }
        const guest_fd = self.fd_manager.register(host_fd, .file) orelse return self.fail(state, .NOMEM);
        if (shouldTrace(self.open_count) or isDiagnosticPath(path) or isDiagnosticPath(translated_path)) {
            std.debug.print("macho-processor: fs openat #{d}: dir_guest_fd={d} guest_path={s} host_path={s} -> guest_fd={d} host_fd={d}\n", .{ self.open_count, state.regs.rdi, path, translated_path, guest_fd, host_fd });
        }
        return guest_fd;
    }

    pub fn read(self: *Forwarder, state: anytype) i64 {
        self.read_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const bytes = state.guestMemory(state.regs.rsi, state.regs.rdx) orelse return -1;
        while (true) {
            const rc = std.c.read(host_fd, bytes.ptr, bytes.len);
            if (rc >= 0) {
                if (shouldTrace(self.read_count)) {
                    std.debug.print("macho-processor: fs read #{d}: guest_fd={d} requested={d} result={d}\n", .{ self.read_count, state.regs.rdi, bytes.len, rc });
                }
                return @intCast(rc);
            }
            const err = std.c.errno(rc);
            if (err != .INTR and err != .AGAIN) {
                if (shouldTrace(self.read_count)) {
                    std.debug.print("macho-processor: fs read #{d} FAILED: guest_fd={d} errno={s}\n", .{ self.read_count, state.regs.rdi, @tagName(err) });
                }
                return @bitCast(self.fail(state, err));
            }
        }
    }

    pub fn pread(self: *Forwarder, state: anytype) i64 {
        self.read_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const bytes = state.guestMemory(state.regs.rsi, state.regs.rdx) orelse return -1;
        const offset: i64 = @bitCast(state.regs.rcx);
        while (true) {
            const rc = std.c.pread(host_fd, bytes.ptr, bytes.len, offset);
            if (rc >= 0) return @intCast(rc);
            const err = std.c.errno(rc);
            if (err != .INTR and err != .AGAIN) return @bitCast(self.fail(state, err));
        }
    }

    pub fn readv(self: *Forwarder, state: anytype) i64 {
        self.read_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const iov_len: usize = @intCast(state.regs.rdx);
        const table_size = std.math.mul(u64, state.regs.rdx, 16) catch return -1;
        const iov = state.guestMemoryConst(state.regs.rsi, table_size) orelse return -1;
        var total: i64 = 0;
        for (0..iov_len) |index| {
            const entry = iov[index * 16 ..][0..16];
            const address = std.mem.readInt(u64, entry[0..8], .little);
            const length = std.mem.readInt(u64, entry[8..16], .little);
            const destination = state.guestMemory(address, length) orelse return if (total == 0) -1 else total;
            const rc = std.c.read(host_fd, destination.ptr, destination.len);
            if (rc < 0) return if (total == 0) -1 else total;
            total += rc;
            if (rc < destination.len) break;
        }
        return total;
    }

    pub fn writev(self: *Forwarder, state: anytype) i64 {
        self.write_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const iov_len: usize = @intCast(state.regs.rdx);
        const table_size = std.math.mul(u64, state.regs.rdx, 16) catch return -1;
        const iov = state.guestMemoryConst(state.regs.rsi, table_size) orelse return -1;
        var total: i64 = 0;
        for (0..iov_len) |index| {
            const entry = iov[index * 16 ..][0..16];
            const address = std.mem.readInt(u64, entry[0..8], .little);
            const length = std.mem.readInt(u64, entry[8..16], .little);
            const source = state.guestMemoryConst(address, length) orelse return if (total == 0) -1 else total;
            const rc = std.c.write(host_fd, source.ptr, source.len);
            if (rc < 0) return if (total == 0) -1 else total;
            total += rc;
            if (rc < source.len) break;
        }
        return total;
    }

    pub fn write(self: *Forwarder, state: anytype) i64 {
        self.write_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const bytes = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse return -1;
        const rc = std.c.write(host_fd, bytes.ptr, bytes.len);
        if (shouldTrace(self.write_count)) {
            std.debug.print("macho-processor: fs write #{d}: guest_fd={d} requested={d} result={d}\n", .{ self.write_count, state.regs.rdi, bytes.len, rc });
        }
        return if (rc < 0) -1 else @intCast(rc);
    }

    pub fn pwrite(self: *Forwarder, state: anytype) i64 {
        self.write_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const bytes = state.guestMemoryConst(state.regs.rsi, state.regs.rdx) orelse return -1;
        const offset: i64 = @bitCast(state.regs.rcx);
        const rc = std.c.pwrite(host_fd, bytes.ptr, bytes.len, offset);
        return if (rc < 0) -1 else @intCast(rc);
    }

    pub fn close(self: *Forwarder, state: anytype) u64 {
        self.close_count += 1;
        return @intCast(self.fd_manager.close(state.regs.rdi));
    }

    pub fn lseek(self: *Forwarder, state: anytype) i64 {
        self.seek_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return -1;
        const offset: i64 = @bitCast(state.regs.rsi);
        const whence: c_int = @intCast(state.regs.rdx);
        const result = std.c.lseek(host_fd, offset, whence);
        return if (result < 0) -1 else @intCast(result);
    }

    pub fn stat(self: *Forwarder, state: anytype) u64 {
        return self.statAt(state, fd_management.STREAM_FD_COUNT, true);
    }

    pub fn lstat(self: *Forwarder, state: anytype) u64 {
        return self.statAt(state, fd_management.STREAM_FD_COUNT, false);
    }

    pub fn fstat(self: *Forwarder, state: anytype) u64 {
        self.stat_count += 1;
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return self.fail(state, .BADF);
        var host_stat: std.c.Stat = undefined;
        const rc = std.c.fstat(host_fd, &host_stat);
        if (rc != 0) return self.failHost(state, rc);
        const destination = state.guestMemory(state.regs.rsi, @sizeOf(std.c.Stat)) orelse return self.fail(state, .FAULT);
        @memcpy(destination, std.mem.asBytes(&host_stat));
        if (shouldTrace(self.stat_count)) {
            std.debug.print("macho-processor: fs fstat #{d}: guest_fd={d} host_fd={d} mode=0{o}\n", .{ self.stat_count, state.regs.rdi, host_fd, host_stat.mode });
        }
        return 0;
    }

    pub fn fstatat(self: *Forwarder, state: anytype) u64 {
        self.stat_count += 1;
        const dir_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return self.fail(state, .BADF);
        return self.statAtDir(state, dir_fd, state.regs.rsi, state.regs.rdx, state.regs.rcx);
    }

    pub fn access(self: *Forwarder, state: anytype) u64 {
        self.access_count += 1;
        const path = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.access(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @intCast(state.regs.rsi),
        ));
    }

    pub fn faccessat(self: *Forwarder, state: anytype) u64 {
        self.access_count += 1;
        const dir_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const path = state.guestCString(state.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.faccessat(
            dir_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @intCast(state.regs.rdx),
            @intCast(state.regs.rcx),
        ));
    }

    pub fn realpath(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return 0;
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return 0;
        path_buffer.append(self.translator.allocator, 0) catch return 0;

        var resolved: [4096]u8 = undefined;
        const ptr = std.c.realpath(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            &resolved,
        ) orelse return 0;
        const resolved_len = std.mem.len(ptr);
        const allocation = state.guestAlloc(resolved_len + 1, 1) orelse return 0;
        const dest = state.guestMemory(allocation, resolved_len + 1) orelse return 0;
        @memcpy(dest[0..resolved_len], resolved[0..resolved_len]);
        dest[resolved_len] = 0;
        return allocation;
    }

    pub fn getcwd(_: *Forwarder, state: anytype) u64 {
        var buf: [4096]u8 = undefined;
        const ptr = std.c.getcwd(&buf, buf.len) orelse return 0;
        const slice = std.mem.sliceTo(ptr, 0);
        const len = slice.len;
        const allocation = if (state.regs.rdi != 0)
            state.regs.rdi
        else
            (state.guestAlloc(@intCast(len + 1), 1) orelse return 0);
        const dest = state.guestMemory(allocation, @intCast(len + 1)) orelse return 0;
        @memcpy(dest[0..len], buf[0..len]);
        dest[len] = 0;
        return allocation;
    }

    pub fn chdir(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.chdir(@as([*:0]const u8, @ptrCast(path_buffer.items.ptr))));
    }

    pub fn mkdir(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.mkdir(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @intCast(state.regs.rsi & 0o777),
        ));
    }

    pub fn rmdir(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.rmdir(@as([*:0]const u8, @ptrCast(path_buffer.items.ptr))));
    }

    pub fn unlink(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.unlink(@as([*:0]const u8, @ptrCast(path_buffer.items.ptr))));
    }

    pub fn rename(self: *Forwarder, state: anytype) u64 {
        const old = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        const new = state.guestCString(state.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_old: [4096]u8 = undefined;
        var temp_new: [4096]u8 = undefined;
        var translated_old = old;
        var translated_new = new;
        if (self.translator.translate(old, &temp_old)) |t| translated_old = t.translated;
        if (self.translator.translate(new, &temp_new)) |t| translated_new = t.translated;
        var old_buf = std.ArrayList(u8).empty;
        var new_buf = std.ArrayList(u8).empty;
        defer old_buf.deinit(self.translator.allocator);
        defer new_buf.deinit(self.translator.allocator);
        old_buf.appendSlice(self.translator.allocator, translated_old) catch return @bitCast(@as(i64, -1));
        old_buf.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        new_buf.appendSlice(self.translator.allocator, translated_new) catch return @bitCast(@as(i64, -1));
        new_buf.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.rename(
            @as([*:0]const u8, @ptrCast(old_buf.items.ptr)),
            @as([*:0]const u8, @ptrCast(new_buf.items.ptr)),
        ));
    }

    pub fn readlink(self: *Forwarder, state: anytype) i64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return -1;
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return -1;
        path_buffer.append(self.translator.allocator, 0) catch return -1;
        const buf_size = state.regs.rdx;
        const dest = state.guestMemory(state.regs.rsi, buf_size) orelse return -1;
        const rc = std.c.readlink(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @as([*]u8, @ptrCast(dest.ptr)),
            buf_size,
        );
        return if (rc < 0) -1 else @intCast(rc);
    }

    pub fn symlink(self: *Forwarder, state: anytype) u64 {
        const target = state.guestCString(state.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        const link_path = state.guestCString(state.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var temp_target: [4096]u8 = undefined;
        var temp_link: [4096]u8 = undefined;
        var translated_target = target;
        var translated_link = link_path;
        if (self.translator.translate(target, &temp_target)) |t| translated_target = t.translated;
        if (self.translator.translate(link_path, &temp_link)) |t| translated_link = t.translated;
        var target_buf = std.ArrayList(u8).empty;
        var link_buf = std.ArrayList(u8).empty;
        defer target_buf.deinit(self.translator.allocator);
        defer link_buf.deinit(self.translator.allocator);
        target_buf.appendSlice(self.translator.allocator, translated_target) catch return @bitCast(@as(i64, -1));
        target_buf.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        link_buf.appendSlice(self.translator.allocator, translated_link) catch return @bitCast(@as(i64, -1));
        link_buf.append(self.translator.allocator, 0) catch return @bitCast(@as(i64, -1));
        return @intCast(std.c.symlink(
            @as([*:0]const u8, @ptrCast(target_buf.items.ptr)),
            @as([*:0]const u8, @ptrCast(link_buf.items.ptr)),
        ));
    }

    pub fn dup(self: *Forwarder, state: anytype) u64 {
        return self.fd_manager.dup(state.regs.rdi) orelse @bitCast(@as(i64, -1));
    }

    pub fn dup2(self: *Forwarder, state: anytype) u64 {
        return self.fd_manager.dupTo(state.regs.rdi, state.regs.rsi) orelse @bitCast(@as(i64, -1));
    }

    pub fn fcntl(self: *Forwarder, state: anytype) u64 {
        const host_fd = self.fd_manager.hostFd(state.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const cmd: c_int = @intCast(state.regs.rsi);

        if (cmd == std.c.F.GETFD or cmd == std.c.F.GETFL) {
            const result = std.c.fcntl(host_fd, cmd);
            return if (result < 0) @bitCast(@as(i64, -1)) else @intCast(result);
        }
        if (cmd == std.c.F.SETFD) {
            _ = self.fd_manager.setFlags(state.regs.rdi, @truncate(state.regs.rdx));
            return @intCast(std.c.fcntl(host_fd, cmd, @as(c_int, @intCast(state.regs.rdx))));
        }
        if (cmd == std.c.F.SETFL) {
            _ = self.fd_manager.setFlags(state.regs.rdi, @truncate(state.regs.rdx));
            return @intCast(std.c.fcntl(host_fd, cmd, @as(c_int, @intCast(state.regs.rdx))));
        }
        if (cmd == std.c.F.DUPFD) {
            const dup_host_fd = std.c.fcntl(host_fd, std.c.F.DUPFD, @as(c_int, @intCast(state.regs.rdx)));
            if (dup_host_fd < 0) return @bitCast(@as(i64, -1));
            return self.fd_manager.register(dup_host_fd, .file) orelse @bitCast(@as(i64, -1));
        }
        return @intCast(std.c.fcntl(host_fd, cmd, @as(c_int, @intCast(state.regs.rdx))));
    }

    pub fn createSocket(self: *Forwarder, state: anytype) u64 {
        const created = socket(@intCast(state.regs.rdi), @intCast(state.regs.rsi), @intCast(state.regs.rdx));
        return self.fd_manager.register(created, .socket) orelse @bitCast(@as(i64, -1));
    }

    pub fn setSocketOption(self: *Forwarder, state: anytype) u64 {
        const host_fd = self.fd_manager.hostFdWithKind(state.regs.rdi, .socket) orelse return @bitCast(@as(i64, -1));
        const length: u32 = @truncate(state.regs.r8);
        const value = if (length == 0) null else (state.guestMemoryConst(state.regs.rcx, length) orelse return @bitCast(@as(i64, -1))).ptr;
        const result = setsockopt(host_fd, @intCast(state.regs.rsi), @intCast(state.regs.rdx), value, length);
        return @bitCast(@as(i64, result));
    }

    pub fn connectSocket(self: *Forwarder, state: anytype) u64 {
        const host_fd = self.fd_manager.hostFdWithKind(state.regs.rdi, .socket) orelse return @bitCast(@as(i64, -1));
        const length: u32 = @truncate(state.regs.rdx);
        const address = state.guestMemoryConst(state.regs.rsi, length) orelse return @bitCast(@as(i64, -1));
        return @bitCast(@as(i64, connect(host_fd, address.ptr, length)));
    }

    pub fn sendSocket(self: *Forwarder, state: anytype) u64 {
        const host_fd = self.fd_manager.hostFdWithKind(state.regs.rdi, .socket) orelse return @bitCast(@as(i64, -1));
        const length: usize = @intCast(state.regs.rdx);
        if (length == 0) return 0;
        const bytes = state.guestMemoryConst(state.regs.rsi, length) orelse return @bitCast(@as(i64, -1));
        return @bitCast(@as(i64, send(host_fd, bytes.ptr, length, @intCast(state.regs.rcx))));
    }

    pub fn ftruncate(self: *Forwarder, state: anytype) u64 {
        self.ftruncate_count += 1;
        const entry = self.fd_manager.lookup(state.regs.rdi) orelse return self.fail(state, .BADF);
        const host_fd = entry.host_fd;
        const requested_size: i64 = std.math.cast(i64, state.regs.rsi) orelse {
            std.debug.print(
                "macho-processor: fs ftruncate rejected: guest_fd={d} host_fd={d} length=0x{x} reason=size_exceeds_signed_off_t\n",
                .{ state.regs.rdi, host_fd, state.regs.rsi },
            );
            return self.fail(state, .INVAL);
        };
        const rc = std.c.ftruncate(host_fd, requested_size);
        if (rc != 0) {
            const err = std.c.errno(rc);
            // macOS POSIX shared-memory objects can reject the 4.5 GiB
            // backing store used by Xenia even though a sparse regular file
            // supports it. Keep the guest descriptor stable, but replace its
            // host backing before any MAP_SHARED views are established.
            if (entry.kind == .shared_memory and state.regs.rsi >= 1024 * 1024 * 1024) {
                if (self.createTempBackedSharedMemory("large-shm-resize-fallback")) |fallback_fd| {
                    if (std.c.ftruncate(fallback_fd, requested_size) == 0) {
                        entry.host_fd = fallback_fd;
                        _ = std.c.close(host_fd);
                        std.debug.print(
                            "macho-processor: fs ftruncate fallback: guest_fd={d} old_host_fd={d} replacement_host_fd={d} length={d} primary_errno={s}\n",
                            .{ state.regs.rdi, host_fd, fallback_fd, state.regs.rsi, @tagName(err) },
                        );
                        return 0;
                    }
                    const fallback_err = std.c.errno(-1);
                    _ = std.c.close(fallback_fd);
                    std.debug.print(
                        "macho-processor: fs ftruncate fallback FAILED: guest_fd={d} length={d} primary_errno={s} fallback_errno={s}\n",
                        .{ state.regs.rdi, state.regs.rsi, @tagName(err), @tagName(fallback_err) },
                    );
                }
            }
            std.debug.print(
                "macho-processor: fs ftruncate FAILED: guest_fd={d} host_fd={d} length={d} errno={s}\n",
                .{ state.regs.rdi, host_fd, state.regs.rsi, @tagName(err) },
            );
            return self.fail(state, err);
        }
        std.debug.print("macho-processor: fs ftruncate #{d}: guest_fd={d} host_fd={d} length={d}\n", .{ self.ftruncate_count, state.regs.rdi, host_fd, state.regs.rsi });
        return 0;
    }

    pub fn shmOpen(self: *Forwarder, state: anytype) u64 {
        self.shm_open_count += 1;
        const path = state.guestCString(state.regs.rdi, 4096) orelse return self.fail(state, .FAULT);
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, path) catch return self.fail(state, .NOMEM);
        path_buffer.append(self.translator.allocator, 0) catch return self.fail(state, .NOMEM);

        const oflag: c_int = @as(c_int, @bitCast(@as(u32, @truncate(state.regs.rsi))));
        const oflag_bits: std.c.O = @bitCast(@as(u32, @bitCast(oflag)));
        const mode: std.c.mode_t = @as(std.c.mode_t, @intCast(state.regs.rdx & 0xFFFF));
        const c_path = @as([*:0]const u8, @ptrCast(path_buffer.items.ptr));
        var host_fd = shm_open(c_path, oflag, mode);
        if (host_fd < 0) {
            const err = std.c.errno(host_fd);
            std.debug.print(
                "macho-processor: shm_open FAILED #{d}: name={s} oflag=0x{x} mode=0{o} errno={s}\n",
                .{ self.shm_open_count, path, @as(u32, @bitCast(oflag)), mode, @tagName(err) },
            );
            if (oflag_bits.CREAT) {
                _ = shm_unlink(c_path);
                host_fd = shm_open(c_path, oflag, mode);
                if (host_fd >= 0) {
                    std.debug.print(
                        "macho-processor: shm_open recovered after unlink: name={s} -> host_fd={d}\n",
                        .{ path, host_fd },
                    );
                } else {
                    const retry_err = std.c.errno(host_fd);
                    std.debug.print(
                        "macho-processor: shm_open retry FAILED: name={s} errno={s}; trying temp-backed shared memory\n",
                        .{ path, @tagName(retry_err) },
                    );
                    host_fd = self.createTempBackedSharedMemory(path) orelse return self.fail(state, retry_err);
                }
            } else {
                return self.fail(state, err);
            }
        }
        const guest_fd = self.fd_manager.register(host_fd, .shared_memory) orelse {
            _ = std.c.close(host_fd);
            return self.fail(state, .NOMEM);
        };
        std.debug.print(
            "macho-processor: shm_open #{d}: name={s} oflag=0x{x} mode=0{o} -> guest_fd={d} host_fd={d}\n",
            .{ self.shm_open_count, path, @as(u32, @bitCast(oflag)), mode, guest_fd, host_fd },
        );
        return guest_fd;
    }

    fn createTempBackedSharedMemory(self: *Forwarder, guest_name: []const u8) ?c_int {
        self.shm_fallback_count += 1;
        var path_buffer: [256]u8 = undefined;
        const temp_path = std.fmt.bufPrintZ(
            &path_buffer,
            "/private/tmp/rosette-shm-{d}-{d}.tmp",
            .{ std.c.getpid(), self.shm_fallback_count },
        ) catch return null;
        const flags = std.c.O{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
        };
        const host_fd = std.c.open(temp_path, flags, @as(std.c.mode_t, 0o600));
        if (host_fd < 0) {
            std.debug.print(
                "macho-processor: temp-backed shm FAILED: guest_name={s} path={s} errno={s}\n",
                .{ guest_name, temp_path, @tagName(std.c.errno(host_fd)) },
            );
            return null;
        }
        _ = std.c.unlink(temp_path);
        std.debug.print(
            "macho-processor: temp-backed shm #{d}: guest_name={s} path={s} host_fd={d} unlinked=true\n",
            .{ self.shm_fallback_count, guest_name, temp_path, host_fd },
        );
        return host_fd;
    }

    pub fn shmUnlink(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return self.fail(state, .FAULT);
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, path) catch return self.fail(state, .NOMEM);
        path_buffer.append(self.translator.allocator, 0) catch return self.fail(state, .NOMEM);
        const rc = shm_unlink(@as([*:0]const u8, @ptrCast(path_buffer.items.ptr)));
        if (rc != 0) {
            const err = std.c.errno(rc);
            std.debug.print("macho-processor: shm_unlink FAILED: name={s} errno={s}\n", .{ path, @tagName(err) });
            return self.fail(state, err);
        }
        std.debug.print("macho-processor: shm_unlink: name={s}\n", .{path});
        return 0;
    }

    pub fn opendir(self: *Forwarder, state: anytype) u64 {
        const path = state.guestCString(state.regs.rdi, 4096) orelse return self.failNull(state, .FAULT);
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return self.failNull(state, .NOMEM);
        path_buffer.append(self.translator.allocator, 0) catch return self.failNull(state, .NOMEM);
        const directory = std.c.opendir(@as([*:0]const u8, @ptrCast(path_buffer.items.ptr))) orelse return self.failHostNull(state);
        return self.fd_manager.registerDirectory(directory) orelse self.failNull(state, .NOMEM);
    }

    pub fn readdir(self: *Forwarder, state: anytype) u64 {
        self.directory_read_count +|= 1;
        const entry = self.fd_manager.lookup(state.regs.rdi) orelse return 0;
        const directory = entry.directory orelse return 0;
        const host_dirent = while (std.c.readdir(directory)) |candidate| {
            const name = std.mem.sliceTo(&candidate.name, 0);
            if (name.len > 0 and isMacOSMetadataEntry(name)) continue;
            break candidate;
        } else return 0;
        const record_size = @min(@as(usize, host_dirent.reclen), @sizeOf(std.c.dirent));
        if (record_size == 0) return 0;
        if (entry.guest_dirent == 0) {
            entry.guest_dirent = state.guestHeapAllocate(@sizeOf(std.c.dirent), @alignOf(std.c.dirent)) orelse return 0;
        }
        const destination = state.guestMemory(entry.guest_dirent, @sizeOf(std.c.dirent)) orelse return 0;
        @memset(destination, 0);
        @memcpy(destination[0..record_size], std.mem.asBytes(host_dirent)[0..record_size]);
        return entry.guest_dirent;
    }

    pub fn closedir(self: *Forwarder, state: anytype) u64 {
        _ = self.fd_manager.hostFdWithKind(state.regs.rdi, .directory) orelse return self.fail(state, .BADF);
        const rc = self.fd_manager.close(state.regs.rdi);
        return if (rc != 0) self.failHost(state, rc) else 0;
    }

    pub fn dirfd(self: *Forwarder, state: anytype) u64 {
        _ = self.fd_manager.hostFdWithKind(state.regs.rdi, .directory) orelse return self.fail(state, .BADF);
        // Guest code must keep using the virtual descriptor. Returning the host
        // descriptor makes the following openat/fstatat lookup fail or alias.
        return state.regs.rdi;
    }

    pub fn pipe(self: *Forwarder, state: anytype) u64 {
        var host_fds: [2]c_int = undefined;
        if (std.c.pipe(&host_fds) != 0) return @bitCast(@as(i64, -1));
        const read_fd = self.fd_manager.register(host_fds[0], .pipe) orelse {
            _ = std.c.close(host_fds[0]);
            _ = std.c.close(host_fds[1]);
            return @bitCast(@as(i64, -1));
        };
        const write_fd = self.fd_manager.register(host_fds[1], .pipe) orelse {
            _ = self.fd_manager.close(read_fd);
            _ = std.c.close(host_fds[1]);
            return @bitCast(@as(i64, -1));
        };
        const dest = state.guestMemory(state.regs.rdi, 2 * @sizeOf(c_int)) orelse return @bitCast(@as(i64, -1));
        std.mem.writeInt(c_int, dest[0..@sizeOf(c_int)], @intCast(read_fd), .little);
        std.mem.writeInt(c_int, dest[@sizeOf(c_int)..][0..@sizeOf(c_int)], @intCast(write_fd), .little);
        return 0;
    }

    pub fn mmap(self: *Forwarder, state: anytype) u64 {
        self.mmap_count += 1;
        const length = state.regs.rsi;
        const raw_flags: u32 = @truncate(state.regs.rcx);
        const offset: i64 = @bitCast(state.regs.r9);
        if (length == 0) return @bitCast(@as(i64, -1));
        const map_flags: std.c.MAP = @bitCast(raw_flags);
        const backend_trace = if (comptime @hasDecl(@TypeOf(state.*), "backendMemoryDiagnosticsActive"))
            state.backendMemoryDiagnosticsActive()
        else
            false;
        if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapAttempt")) {
            state.noteBackendMmapAttempt("import", state.regs.rdi, length, state.regs.rdx, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS);
        }
        // Xenia's native x64 backend uses this window as an address hint for
        // its code-cache indirection table.  The hint is semantically
        // significant even though it is not MAP_FIXED: the backend rejects a
        // table outside the 32-bit reachability window.  Preserve it in the
        // guest virtual-address model instead of falling through to the
        // unrelated general heap.
        const x64_code_cache_hint = state.regs.rdi >= 0x8000_0000 and state.regs.rdi < 0xA000_0000;
        const trace_mapping = backend_trace or x64_code_cache_hint or length >= 1024 * 1024 * 1024 or (map_flags.FIXED and length >= 64 * 1024 * 1024);
        if (trace_mapping) {
            std.debug.print(
                "macho-processor: large/fixed mmap entry: route=import addr=0x{x} length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} guest_fd=0x{x} offset={d}\n",
                .{ state.regs.rdi, length, state.regs.rdx, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS, state.regs.r8, offset },
            );
        }
        if (comptime @hasDecl(@TypeOf(state.*), "guestMapBackendWithBacking")) {
            const backend_sparse_threshold = 64 * 1024 * 1024;
            if (backend_trace and state.regs.rdi == 0 and map_flags.ANONYMOUS and length >= backend_sparse_threshold) {
                const mapped = state.guestMapBackendWithBacking(length, @truncate(state.regs.rdx), raw_flags, -1, @bitCast(offset)) orelse {
                    std.debug.print(
                        "macho-processor: x64 backend sparse mmap FAILED: route=import address=0x0 length={d} prot=0x{x} flags=0x{x}; bounded guest heap fallback is intentionally disabled for large backend VM regions\n",
                        .{ length, state.regs.rdx, raw_flags },
                    );
                    if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "backend_sparse_anywhere");
                    return @bitCast(@as(i64, -1));
                };
                std.debug.print(
                    "macho-processor: x64 backend sparse mmap succeeded: route=import guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} heap_bypassed=true\n",
                    .{ mapped, length, state.regs.rdx, raw_flags },
                );
                if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(true, mapped, "backend_sparse_anywhere");
                return mapped;
            }
        }
        if (state.regs.rdi != 0 and map_flags.FIXED) {
            // Anonymous mappings deliberately use fd=-1. Do not pass that
            // sentinel through the guest descriptor table: the sparse-memory
            // manager supplies host backing while preserving the requested
            // fixed address in the guest address space.
            const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                -1
            else
                self.fd_manager.hostFd(state.regs.r8) orelse {
                    if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "fixed_fd_translation");
                    return @bitCast(@as(i64, -1));
                };
            if (state.regs.rdi % std.heap.page_size_min != 0) {
                if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "fixed_alignment");
                return @bitCast(@as(i64, -1));
            }
            const mapped = state.guestMapFile(state.regs.rdi, length, @truncate(state.regs.rdx), raw_flags, host_fd, @bitCast(offset));
            if (trace_mapping) {
                const outcome: []const u8 = if (mapped) "succeeded" else "FAILED";
                std.debug.print(
                    "macho-processor: large/fixed mmap {s}: route=import addr=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset={d}\n",
                    .{ outcome, state.regs.rdi, length, state.regs.rdx, raw_flags, host_fd, offset },
                );
            }
            if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(mapped, if (mapped) state.regs.rdi else 0, "fixed_sparse_map");
            return if (mapped) state.regs.rdi else @bitCast(@as(i64, -1));
        }
        if (x64_code_cache_hint) {
            const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                -1
            else
                self.fd_manager.hostFd(state.regs.r8) orelse {
                    std.debug.print(
                        "macho-processor: x64 code-cache hint rejected: reason=guest_fd_translation address=0x{x} length={d} guest_fd=0x{x}\n",
                        .{ state.regs.rdi, length, state.regs.r8 },
                    );
                    return @bitCast(@as(i64, -1));
                };
            if (state.guestMapFile(state.regs.rdi, length, @truncate(state.regs.rdx), raw_flags, host_fd, @bitCast(offset))) {
                std.debug.print(
                    "macho-processor: x64 code-cache hint mapped: guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d}\n",
                    .{ state.regs.rdi, length, state.regs.rdx, raw_flags, host_fd },
                );
                if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(true, state.regs.rdi, "code_cache_hint_sparse_map");
                return state.regs.rdi;
            }
            if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "code_cache_hint_sparse_map");
            std.debug.print(
                "macho-processor: x64 code-cache hint unavailable: guest_base=0x{x} length={d} prot=0x{x} flags=0x{x}; falling back to ordinary mmap placement\n",
                .{ state.regs.rdi, length, state.regs.rdx, raw_flags },
            );
        }
        // Xenia reserves its 32-bit guest address space with a non-fixed,
        // anonymous PROT_NONE mmap.  This is virtual address space, not a 4 GiB
        // physical allocation, and must not be served by the bounded guest heap.
        if (state.regs.rdx == 0 and length >= 1024 * 1024 * 1024) {
            const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                -1
            else
                self.fd_manager.hostFd(state.regs.r8) orelse return @bitCast(@as(i64, -1));
            const reserved = state.guestReserveAddressSpaceWithBacking(length, raw_flags, host_fd, @bitCast(offset)) orelse {
                std.debug.print("macho-processor: large mmap FAILED: route=import stage=sparse_reserve\n", .{});
                if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "sparse_reserve");
                return @bitCast(@as(i64, -1));
            };
            std.debug.print("macho-processor: large mmap succeeded: route=import guest_base=0x{x} length={d}\n", .{ reserved, length });
            if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(true, reserved, "sparse_reserve");
            return reserved;
        }
        const mapped = state.guestHeapAllocate(length, 4096) orelse {
            if (backend_trace) {
                std.debug.print(
                    "macho-processor: x64 backend mmap FAILED: route=import stage=guest_heap_allocate address=0x{x} length={d} heap allocation could not satisfy backend request\n",
                    .{ state.regs.rdi, length },
                );
            }
            if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "guest_heap_allocate");
            return @bitCast(@as(i64, -1));
        };
        const destination = state.guestMemory(mapped, length) orelse {
            state.guestHeapRelease(mapped);
            if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "guest_heap_backing");
            return @bitCast(@as(i64, -1));
        };
        @memset(destination, 0);
        if (!map_flags.ANONYMOUS and state.regs.r8 != std.math.maxInt(u64)) {
            const host_fd = self.fd_manager.hostFd(state.regs.r8) orelse {
                state.guestHeapRelease(mapped);
                if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "file_fd_translation");
                return @bitCast(@as(i64, -1));
            };
            const rc = std.c.pread(host_fd, destination.ptr, destination.len, offset);
            if (rc < 0) {
                state.guestHeapRelease(mapped);
                if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(false, 0, "file_pread");
                return @bitCast(@as(i64, -1));
            }
        }
        if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMmapResult")) state.noteBackendMmapResult(true, mapped, "guest_heap_allocate");
        return mapped;
    }

    pub fn munmap(self: *Forwarder, state: anytype) u64 {
        _ = self;
        if (state.guestUnmapFile(state.regs.rdi, state.regs.rsi)) return 0;
        if (!state.guestHeapContains(state.regs.rdi)) return @bitCast(@as(i64, -1));
        state.guestHeapRelease(state.regs.rdi);
        return 0;
    }

    pub fn mprotect(self: *Forwarder, state: anytype) u64 {
        _ = self;
        const sparse_succeeded = state.guestProtectSparseMemory(state.regs.rdi, state.regs.rsi, @truncate(state.regs.rdx));
        const result: u64 = if (sparse_succeeded)
            0
        else if (state.guestMemory(state.regs.rdi, state.regs.rsi) != null)
            0
        else
            @bitCast(@as(i64, -1));
        if (comptime @hasDecl(@TypeOf(state.*), "noteBackendMprotect")) {
            state.noteBackendMprotect("import", state.regs.rdi, state.regs.rsi, state.regs.rdx, result == 0);
        }
        return result;
    }

    pub fn logSummary(self: *const Forwarder) void {
        std.debug.print(
            "macho-processor: fs io forwarding: open={d} read={d} write={d} close={d} seek={d} stat={d} readdir={d} mmap={d} shm_open={d} shm_fallback={d} ftruncate={d} access={d} errno_updates={d} last_errno={d}\n",
            .{
                self.open_count,
                self.read_count,
                self.write_count,
                self.close_count,
                self.seek_count,
                self.stat_count,
                self.directory_read_count,
                self.mmap_count,
                self.shm_open_count,
                self.shm_fallback_count,
                self.ftruncate_count,
                self.access_count,
                self.errno_updates,
                self.last_errno,
            },
        );
        self.fd_manager.logSummary();
    }

    fn statAt(self: *Forwarder, state: anytype, dir_fd: c_int, follow_symlinks: bool) u64 {
        self.stat_count += 1;
        return self.statAtDir(state, dir_fd, state.regs.rdi, state.regs.rsi, if (follow_symlinks) @as(u64, 0) else @as(u64, std.c.AT.SYMLINK_NOFOLLOW));
    }

    fn statAtDir(self: *Forwarder, state: anytype, dir_fd: c_int, path_guest: u64, stat_guest: u64, flags_guest: u64) u64 {
        const path = state.guestCString(path_guest, 4096) orelse return self.fail(state, .FAULT);
        var temp_buf: [4096]u8 = undefined;
        var translated_path = path;
        if (self.translator.translate(path, &temp_buf)) |t| {
            translated_path = t.translated;
        }
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.translator.allocator);
        path_buffer.appendSlice(self.translator.allocator, translated_path) catch return self.fail(state, .NOMEM);
        path_buffer.append(self.translator.allocator, 0) catch return self.fail(state, .NOMEM);

        var host_stat: std.c.Stat = undefined;
        const effective_dir_fd = if (dir_fd == fd_management.STREAM_FD_COUNT) std.c.AT.FDCWD else dir_fd;
        const rc = std.c.fstatat(
            effective_dir_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            &host_stat,
            @intCast(flags_guest),
        );
        if (rc != 0) return self.failHost(state, rc);
        const destination = state.guestMemory(stat_guest, @sizeOf(std.c.Stat)) orelse return self.fail(state, .FAULT);
        @memcpy(destination, std.mem.asBytes(&host_stat));
        return 0;
    }

    fn fail(self: *Forwarder, state: anytype, err: std.c.E) u64 {
        self.recordErrno(state, err);
        return @bitCast(@as(i64, -1));
    }

    fn failNull(self: *Forwarder, state: anytype, err: std.c.E) u64 {
        self.recordErrno(state, err);
        return 0;
    }

    fn failHost(self: *Forwarder, state: anytype, rc: anytype) u64 {
        return self.fail(state, std.c.errno(rc));
    }

    fn failHostNull(self: *Forwarder, state: anytype) u64 {
        return self.failNull(state, std.c.errno(-1));
    }

    fn recordErrno(self: *Forwarder, state: anytype, err: std.c.E) void {
        const value: c_int = @intCast(@intFromEnum(err));
        self.errno_updates +|= 1;
        self.last_errno = value;
        state.setGuestErrno(value);
    }
};

fn isMacOSMetadataEntry(name: []const u8) bool {
    return std.mem.eql(u8, name, ".DS_Store") or
        std.mem.eql(u8, name, ".localized") or
        std.mem.eql(u8, name, "Icon\r") or
        std.mem.startsWith(u8, name, "._");
}

fn isDiagnosticPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".patch.toml") or
        std.mem.indexOf(u8, path, "User_") != null or
        std.mem.indexOf(u8, path, "Account") != null or
        std.mem.indexOf(u8, path, "/content/") != null;
}

fn shouldTrace(count: u64) bool {
    return count <= 8 or count % 1000 == 0;
}

test "directory descriptors remain virtual and fstatat propagates ENOENT" {
    const TestState = struct {
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        memory: [8192]u8 = [_]u8{0} ** 8192,
        guest_errno: c_int = 0,

        fn guestCString(self: *@This(), address: u64, max_len: usize) ?[]const u8 {
            if (address >= self.memory.len) return null;
            const start: usize = @intCast(address);
            const limit = @min(self.memory.len, start + max_len);
            const end = std.mem.indexOfScalar(u8, self.memory[start..limit], 0) orelse return null;
            return self.memory[start .. start + end];
        }

        fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            const start: usize = std.math.cast(usize, address) orelse return null;
            const len: usize = std.math.cast(usize, length) orelse return null;
            const end = std.math.add(usize, start, len) catch return null;
            if (end > self.memory.len) return null;
            return self.memory[start..end];
        }

        fn setGuestErrno(self: *@This(), value: c_int) void {
            self.guest_errno = value;
        }
    };

    var forwarder = Forwarder.init(std.testing.allocator);
    defer forwarder.deinit();
    var state = TestState{};
    @memcpy(state.memory[64..68], "/tmp");
    state.memory[68] = 0;
    state.regs.rdi = 64;
    const guest_dir = forwarder.opendir(&state);
    try std.testing.expect(guest_dir >= fd_management.STREAM_FD_COUNT);

    state.regs.rdi = guest_dir;
    try std.testing.expectEqual(guest_dir, forwarder.dirfd(&state));

    const missing = "rosette-fstatat-errno-regression-file";
    @memcpy(state.memory[128 .. 128 + missing.len], missing);
    state.memory[128 + missing.len] = 0;
    state.regs.rsi = 128;
    state.regs.rdx = 512;
    state.regs.rcx = std.c.AT.SYMLINK_NOFOLLOW;
    try std.testing.expectEqual(std.math.maxInt(u64), forwarder.fstatat(&state));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(std.c.E.NOENT)), state.guest_errno);
}

test "temp-backed shared memory fallback produces truncatable fd" {
    var forwarder = Forwarder.init(std.testing.allocator);
    defer forwarder.deinit();

    const host_fd = forwarder.createTempBackedSharedMemory("/rosette-test-shm") orelse return error.TestUnexpectedResult;
    defer _ = std.c.close(host_fd);

    try std.testing.expect(host_fd >= fd_management.STREAM_FD_COUNT);
    try std.testing.expectEqual(@as(c_int, 0), std.c.ftruncate(host_fd, 64 * 1024));
}

test "large shared-memory resize replaces constrained backing" {
    const TestState = struct {
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},
        guest_errno: c_int = 0,

        fn setGuestErrno(self: *@This(), value: c_int) void {
            self.guest_errno = value;
        }
    };

    var forwarder = Forwarder.init(std.testing.allocator);
    defer forwarder.deinit();
    const constrained_fd = std.c.open("/private/tmp", std.c.O{ .DIRECTORY = true }, @as(std.c.mode_t, 0));
    if (constrained_fd < 0) return error.TestUnexpectedResult;
    const guest_fd = forwarder.fd_manager.register(constrained_fd, .shared_memory) orelse return error.TestUnexpectedResult;
    var state = TestState{ .regs = .{ .rdi = guest_fd, .rsi = 0x1_2000_0000 } };

    try std.testing.expectEqual(@as(u64, 0), forwarder.ftruncate(&state));
    const replacement_fd = forwarder.fd_manager.hostFd(guest_fd).?;
    try std.testing.expect(replacement_fd != constrained_fd);
    var stat: std.c.Stat = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.fstat(replacement_fd, &stat));
    try std.testing.expectEqual(@as(i64, 0x1_2000_0000), stat.size);
}
