//! Guest file I/O operations extracted from MachOState (process.zig).
//! Handles fopen/fwrite/fread/fseek/fprintf/snprintf and related
//! guest-level file operations by delegating to host POSIX APIs.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports
//! with process.zig. The type is inferred at the call site as
//! `*MachOState`.

const std = @import("std");
const types = @import("macho_core").types;
const constants = @import("macho_core").constants;
const utils = @import("macho_core").utils;
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;

const GuestFile = types.GuestFile;
const GuestFileKind = types.GuestFileKind;
const GUEST_FILE_BASE = constants.GUEST_FILE_BASE;
const GUEST_FILE_MAX = constants.GUEST_FILE_MAX;
const parseFopenFlags = utils.parseFopenFlags;

fn registerGuestFd(self: anytype, host_fd: c_int) ?u64 {
    var guest_fd: usize = @intCast(@max(self.next_guest_fd, 3));
    while (guest_fd < self.guest_fds.len and self.guest_fds[guest_fd] >= 0) : (guest_fd += 1) {}
    if (guest_fd >= self.guest_fds.len) {
        _ = std.c.close(host_fd);
        return null;
    }
    self.guest_fds[guest_fd] = host_fd;
    self.next_guest_fd = guest_fd + 1;
    return guest_fd;
}

pub fn hostFd(self: anytype, guest_or_host_fd: u64) ?c_int {
    if (guest_or_host_fd < self.guest_fds.len) {
        const guest_fd: usize = @intCast(guest_or_host_fd);
        if (self.guest_fds[guest_fd] >= 0) return self.guest_fds[guest_fd];
    }
    if (guest_or_host_fd > std.math.maxInt(c_int)) return null;
    return @intCast(guest_or_host_fd);
}

fn hostWriteFdAll(fd: c_int, bytes: []const u8) bool {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = std.c.write(fd, bytes.ptr + written, bytes.len - written);
        if (rc < 0) return false;
        if (rc == 0) break;
        written += @intCast(rc);
    }
    return written == bytes.len;
}

pub fn hostWriteAll(self: anytype, file: *GuestFile, bytes: []const u8) bool {
    if (file.fd < 0) return false;
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = std.c.write(file.fd, bytes.ptr + written, bytes.len - written);
        if (rc < 0) {
            self.setGuestErrno(@intCast(@intFromEnum(std.c.errno(rc))));
            file.error_flag = true;
            return false;
        }
        if (rc == 0) break;
        written += @intCast(rc);
    }
    if (file.kind == .regular) file.position += @intCast(written);
    const completed = written == bytes.len;
    if (completed and file.kind != .regular) {
        self.guest_stdio_write_count +|= 1;
        switch (file.kind) {
            .stdout => self.guest_stdout_byte_count +|= written,
            .stderr => self.guest_stderr_byte_count +|= written,
            .regular => unreachable,
        }
        if (self.guest_log_mirror_fd >= 0 and
            self.guest_log_mirror_fd != file.fd and
            !hostWriteFdAll(self.guest_log_mirror_fd, bytes))
        {
            self.guest_stdio_mirror_failures +|= 1;
        }
        if (self.guest_stdio_write_count == 1) {
            machoCapturePrint(
                "macho-processor: guest stdio capture active: first_stream={s} log_mirror_active={}\n",
                .{ @tagName(file.kind), self.guest_log_mirror_fd >= 0 },
            );
        }
    }
    return completed;
}

pub fn setGuestErrno(self: anytype, value: c_int) void {
    if (self.guest_errno_address == 0) {
        self.guest_errno_address = self.guestAlloc(@sizeOf(c_int), @alignOf(c_int)) orelse return;
    }
    const storage = self.guestMemory(self.guest_errno_address, @sizeOf(c_int)) orelse return;
    std.mem.writeInt(c_int, storage[0..@sizeOf(c_int)], value, .little);
}

pub fn handleOpen(self: anytype) u64 {
    const path = self.guestCString(self.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
    var path_buffer = std.ArrayList(u8).empty;
    defer path_buffer.deinit(self.allocator);
    path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
    path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));

    const host_fd = std.c.open(
        @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
        @bitCast(@as(u32, @truncate(self.regs.rsi))),
        @as(c_int, @intCast(self.regs.rdx & 0xFFFF)),
    );
    if (host_fd < 0) return @bitCast(@as(i64, -1));
    return registerGuestFd(self, host_fd) orelse @bitCast(@as(i64, -1));
}

pub fn handleFstatat(self: anytype) u64 {
    const directory_fd = hostFd(self, self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    const path = self.guestCString(self.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
    var path_buffer = std.ArrayList(u8).empty;
    defer path_buffer.deinit(self.allocator);
    path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
    path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));
    var host_stat: std.c.Stat = undefined;
    const result = std.c.fstatat(
        directory_fd,
        @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
        &host_stat,
        @truncate(self.regs.rcx),
    );
    if (result != 0) {
        self.setGuestErrno(2);
        return @bitCast(@as(i64, -1));
    }
    const destination = self.guestMemory(self.regs.rdx, @sizeOf(std.c.Stat)) orelse return @bitCast(@as(i64, -1));
    @memcpy(destination, std.mem.asBytes(&host_stat));
    return 0;
}

pub fn handleOpenat(self: anytype) u64 {
    const directory_fd = hostFd(self, self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    const path = self.guestCString(self.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
    var path_buffer = std.ArrayList(u8).empty;
    defer path_buffer.deinit(self.allocator);
    path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
    path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));
    const host_fd = std.c.openat(
        directory_fd,
        @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
        @bitCast(@as(u32, @truncate(self.regs.rdx))),
        @as(c_int, @intCast(self.regs.rcx & 0xFFFF)),
    );
    if (host_fd < 0) {
        self.setGuestErrno(2);
        return @bitCast(@as(i64, -1));
    }
    return registerGuestFd(self, host_fd) orelse @bitCast(@as(i64, -1));
}

pub fn handleFstat(self: anytype) u64 {
    const fd = hostFd(self, self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    var host_stat: std.c.Stat = undefined;
    if (std.c.fstat(fd, &host_stat) != 0) {
        self.setGuestErrno(2);
        return @bitCast(@as(i64, -1));
    }
    const destination = self.guestMemory(self.regs.rsi, @sizeOf(std.c.Stat)) orelse return @bitCast(@as(i64, -1));
    @memcpy(destination, std.mem.asBytes(&host_stat));
    return 0;
}

pub fn handleFtruncate(self: anytype) u64 {
    const fd = hostFd(self, self.regs.rdi) orelse {
        self.setGuestErrno(9);
        return @bitCast(@as(i64, -1));
    };
    const result = std.c.ftruncate(fd, @bitCast(self.regs.rsi));
    if (result != 0) self.setGuestErrno(22);
    return @bitCast(@as(i64, result));
}

pub fn handleOpendir(self: anytype) ?u64 {
    const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
    var path_buffer = std.ArrayList(u8).empty;
    defer path_buffer.deinit(self.allocator);
    path_buffer.appendSlice(self.allocator, path) catch return null;
    path_buffer.append(self.allocator, 0) catch return null;
    const host_fd = std.c.open(
        @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
        std.c.O{ .DIRECTORY = true },
        @as(c_int, 0),
    );
    if (host_fd < 0) return null;
    return self.allocGuestFile(host_fd, .regular) orelse {
        _ = std.c.close(host_fd);
        return null;
    };
}

pub fn handleClosedir(self: anytype) u64 {
    const directory = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    if (directory.fd >= 0 and std.c.close(directory.fd) != 0) return @bitCast(@as(i64, -1));
    directory.* = .{};
    return 0;
}

pub fn handleWrite(self: anytype) u64 {
    const guest_fd: usize = @intCast(self.regs.rdi);
    if (guest_fd >= self.guest_fds.len or self.guest_fds[guest_fd] < 0) return @bitCast(@as(i64, -1));
    const bytes = self.guestMemoryConst(self.regs.rsi, self.regs.rdx) orelse return @bitCast(@as(i64, -1));
    const written = std.c.write(self.guest_fds[guest_fd], bytes.ptr, bytes.len);
    return if (written < 0) @bitCast(@as(i64, -1)) else @intCast(written);
}

pub fn handleClose(self: anytype) u64 {
    const guest_fd: usize = @intCast(self.regs.rdi);
    if (guest_fd >= self.guest_fds.len or self.guest_fds[guest_fd] < 0) return @bitCast(@as(i64, -1));
    const result = std.c.close(self.guest_fds[guest_fd]);
    self.guest_fds[guest_fd] = -1;
    if (guest_fd < self.next_guest_fd) self.next_guest_fd = @max(guest_fd, 3);
    return if (result == 0) 0 else @bitCast(@as(i64, -1));
}

pub fn handleFopen(self: anytype) ?u64 {
    const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
    const mode = self.guestCString(self.regs.rsi, 32) orelse return null;
    const flags = parseFopenFlags(mode) orelse return null;
    var temp_buf: [4096]u8 = undefined;
    var translated_path: []const u8 = path;
    if (self.fs_forwarder.resolveHostPath(path, &temp_buf)) |t| {
        translated_path = t;
    }
    var path_buf = std.ArrayList(u8).empty;
    defer path_buf.deinit(self.allocator);
    path_buf.appendSlice(self.allocator, translated_path) catch return null;
    path_buf.append(self.allocator, 0) catch return null;
    const zpath: [*:0]const u8 = @ptrCast(path_buf.items.ptr);
    const oflags: std.c.O = @bitCast(@as(u32, @intCast(flags)));
    var fd = std.c.open(zpath, oflags, @as(c_int, 0o666));
    if (fd < 0) {
        const err = std.c.errno(fd);
        if (self.fs_forwarder.tryOpenFallback(translated_path, oflags, 0o666, err)) |fallback_fd| {
            fd = fallback_fd;
        } else {
            return null;
        }
    }
    return self.allocGuestFile(fd, .regular);
}

pub fn handleFdopen(self: anytype) ?u64 {
    const mode = self.guestCString(self.regs.rsi, 32) orelse {
        self.setGuestErrno(@intFromEnum(std.c.E.FAULT));
        machoCapturePrint("macho-processor: fdopen rejected: unreadable mode pointer=0x{x}\n", .{self.regs.rsi});
        return null;
    };
    const guest_fd = self.regs.rdi;
    const borrowed = self.fs_forwarder.fd_manager.borrowForStream(guest_fd) orelse {
        self.setGuestErrno(@intFromEnum(std.c.E.BADF));
        machoCapturePrint("macho-processor: fdopen rejected: invalid guest_fd={d} mode={s}\n", .{ guest_fd, mode });
        return null;
    };
    const handle = self.allocGuestFile(borrowed.host_fd, .regular) orelse {
        // A failed fdopen leaves the caller's descriptor open.
        self.setGuestErrno(@intFromEnum(std.c.E.NOMEM));
        return null;
    };
    const file = self.guestFileFromHandle(handle).?;
    file.descriptor_alias = guest_fd;
    file.descriptor_generation = borrowed.generation;
    file.descriptor_alias_is_primary = true;
    machoCapturePrint(
        "macho-processor: fdopen: guest_fd={d} host_fd={d} generation={d} mode={s} -> FILE=0x{x}\n",
        .{ guest_fd, borrowed.host_fd, borrowed.generation, mode, handle },
    );
    return handle;
}

pub fn handleFileno(self: anytype) u64 {
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    if (file.descriptor_alias != std.math.maxInt(u64) and
        self.fs_forwarder.fd_manager.generationMatches(file.descriptor_alias, file.descriptor_generation))
    {
        return file.descriptor_alias;
    }
    if (file.descriptor_alias != std.math.maxInt(u64)) {
        self.setGuestErrno(@intFromEnum(std.c.E.BADF));
        return @bitCast(@as(i64, -1));
    }
    const duplicate = std.c.dup(file.fd);
    if (duplicate < 0) return @bitCast(@as(i64, -1));
    const guest_fd = self.fs_forwarder.fd_manager.register(duplicate, .file) orelse return @bitCast(@as(i64, -1));
    const borrowed = self.fs_forwarder.fd_manager.borrowForStream(guest_fd).?;
    file.descriptor_alias = guest_fd;
    file.descriptor_generation = borrowed.generation;
    return guest_fd;
}

pub fn handleFclose(self: anytype) u64 {
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    if (file.descriptor_alias != std.math.maxInt(u64)) {
        const alias_is_primary = file.descriptor_alias_is_primary;
        const close_result = self.fs_forwarder.fd_manager.closeGeneration(
            file.descriptor_alias,
            file.descriptor_generation,
        );
        file.descriptor_alias = std.math.maxInt(u64);
        if (alias_is_primary) file.fd = -1;
        if (close_result != 0) {
            if (!alias_is_primary and file.kind == .regular and file.fd >= 0) {
                _ = std.c.close(file.fd);
            }
            self.setGuestErrno(@intFromEnum(std.c.E.BADF));
            file.* = .{};
            return @bitCast(@as(i64, -1));
        }
    }
    if (file.kind == .regular and file.fd >= 0) {
        if (std.c.close(file.fd) != 0) {
            file.error_flag = true;
            return @bitCast(@as(i64, -1));
        }
    }
    file.* = .{};
    return 0;
}

pub fn handleFputs(self: anytype) u64 {
    const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return @bitCast(@as(i64, -1));
    const file = self.guestFileFromHandle(self.regs.rsi) orelse return @bitCast(@as(i64, -1));
    if (!hostWriteAll(self, file, text)) return @bitCast(@as(i64, -1));
    return @intCast(text.len);
}

pub fn handleFwrite(self: anytype) u64 {
    const element_size = self.regs.rsi;
    const element_count = self.regs.rdx;
    if (element_size == 0 or element_count == 0) return 0;
    const byte_count = std.math.mul(u64, element_size, element_count) catch {
        self.setGuestErrno(@intFromEnum(std.c.E.OVERFLOW));
        return 0;
    };
    const bytes = self.guestMemoryConst(self.regs.rdi, byte_count) orelse {
        self.setGuestErrno(@intFromEnum(std.c.E.FAULT));
        machoCapturePrint("macho-processor: fwrite rejected: source=0x{x} bytes={d}\n", .{ self.regs.rdi, byte_count });
        return 0;
    };
    const file = self.guestFileFromHandle(self.regs.rcx) orelse {
        self.setGuestErrno(@intFromEnum(std.c.E.BADF));
        machoCapturePrint("macho-processor: fwrite rejected: FILE=0x{x} bytes={d}\n", .{ self.regs.rcx, byte_count });
        return 0;
    };
    if (!hostWriteAll(self, file, bytes)) {
        machoCapturePrint("macho-processor: fwrite failed: FILE=0x{x} host_fd={d} requested={d}\n", .{ self.regs.rcx, file.fd, byte_count });
        return 0;
    }
    machoCapturePrint("macho-processor: fwrite: FILE=0x{x} host_fd={d} bytes={d} elements={d}\n", .{ self.regs.rcx, file.fd, byte_count, element_count });
    return element_count;
}

pub fn handleFread(self: anytype) u64 {
    const element_size = self.regs.rsi;
    const element_count = self.regs.rdx;
    if (element_size == 0 or element_count == 0) return 0;
    const byte_count = std.math.mul(u64, element_size, element_count) catch {
        self.setGuestErrno(@intFromEnum(std.c.E.OVERFLOW));
        self.guest_stdio_failures +|= 1;
        return 0;
    };
    const destination = self.guestMemory(self.regs.rdi, byte_count) orelse {
        self.setGuestErrno(@intFromEnum(std.c.E.FAULT));
        self.guest_stdio_failures +|= 1;
        machoCapturePrint("macho-processor: fread rejected: destination=0x{x} bytes={d}\n", .{ self.regs.rdi, byte_count });
        return 0;
    };
    const file = self.guestFileFromHandle(self.regs.rcx) orelse {
        self.setGuestErrno(@intFromEnum(std.c.E.BADF));
        self.guest_stdio_failures +|= 1;
        machoCapturePrint("macho-processor: fread rejected: FILE=0x{x} bytes={d}\n", .{ self.regs.rcx, byte_count });
        return 0;
    };
    if (file.fd < 0) {
        self.setGuestErrno(@intFromEnum(std.c.E.BADF));
        file.error_flag = true;
        self.guest_stdio_failures +|= 1;
        return 0;
    }

    const initial_position = file.position;
    var bytes_read: usize = 0;
    while (bytes_read < destination.len) {
        const result = std.c.read(file.fd, destination.ptr + bytes_read, destination.len - bytes_read);
        if (result < 0) {
            self.setGuestErrno(@intCast(@intFromEnum(std.c.errno(result))));
            file.error_flag = true;
            self.guest_stdio_failures +|= 1;
            break;
        }
        if (result == 0) break;
        bytes_read += @intCast(result);
    }
    file.position += @intCast(bytes_read);
    self.guest_stdio_read_count +|= 1;
    self.guest_stdio_read_bytes +|= bytes_read;
    const complete_elements = bytes_read / @as(usize, @intCast(element_size));
    if (self.guest_stdio_read_count <= 8 or self.guest_stdio_read_count % 1000 == 0) {
        machoCapturePrint(
            "macho-processor: fread #{d}: FILE=0x{x} host_fd={d} position={d}->{d} requested={d} read={d} elements={d}/{d}\n",
            .{ self.guest_stdio_read_count, self.regs.rcx, file.fd, initial_position, file.position, byte_count, bytes_read, complete_elements, element_count },
        );
    }
    return complete_elements;
}

pub fn handleFflush(self: anytype) u64 {
    if (self.regs.rdi == 0) return 0;
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    if (std.c.fsync(file.fd) != 0 and file.kind == .regular) {
        file.error_flag = true;
        return @bitCast(@as(i64, -1));
    }
    return 0;
}

pub fn handleFtell(self: anytype) u64 {
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    return @bitCast(file.position);
}

pub fn handleFseek(self: anytype) u64 {
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    const offset: i64 = @bitCast(self.regs.rsi);
    const whence: i32 = @intCast(self.regs.rdx);
    self.guest_stdio_seek_count +|= 1;
    if (file.fd < 0) {
        self.setGuestErrno(@intFromEnum(std.c.E.BADF));
        self.guest_stdio_failures +|= 1;
        return @bitCast(@as(i64, -1));
    }
    const initial_position = file.position;
    const pos = std.c.lseek(file.fd, offset, whence);
    if (pos < 0) {
        self.setGuestErrno(@intCast(@intFromEnum(std.c.errno(pos))));
        file.error_flag = true;
        self.guest_stdio_failures +|= 1;
        return @bitCast(@as(i64, -1));
    }
    file.position = pos;
    if (self.guest_stdio_seek_count <= 8 or self.guest_stdio_seek_count % 1000 == 0) {
        machoCapturePrint(
            "macho-processor: fseek #{d}: FILE=0x{x} host_fd={d} position={d}->{d} offset={d} whence={d}\n",
            .{ self.guest_stdio_seek_count, self.regs.rdi, file.fd, initial_position, pos, offset, whence },
        );
    }
    return 0;
}

pub fn handleFerror(self: anytype) u64 {
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return 1;
    return if (file.error_flag) 1 else 0;
}

pub fn handleFprintf(self: anytype) u64 {
    const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
    const arguments = [_]u64{ self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
    return handlePrintfLike(self, file, self.regs.rsi, &arguments);
}

pub fn handleSnprintf(self: anytype) u64 {
    const destination = self.regs.rdi;
    const capacity: usize = @intCast(self.regs.rsi);
    const format = self.guestCString(self.regs.rdx, 1 << 20) orelse return @bitCast(@as(i64, -1));
    var output = std.ArrayList(u8).empty;
    defer output.deinit(self.allocator);
    const arguments = [_]u64{ self.regs.rcx, self.regs.r8, self.regs.r9 };
    var argument_index: usize = 0;
    var stack_argument = self.regs.rsp + 8;
    var index: usize = 0;
    while (index < format.len) : (index += 1) {
        if (format[index] != '%') {
            output.append(self.allocator, format[index]) catch return @bitCast(@as(i64, -1));
            continue;
        }
        index += 1;
        if (index >= format.len) break;
        if (format[index] == '%') {
            output.append(self.allocator, '%') catch return @bitCast(@as(i64, -1));
            continue;
        }
        while (index < format.len and (format[index] == '-' or format[index] == '+' or format[index] == ' ' or format[index] == '#' or format[index] == '0')) : (index += 1) {}
        while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {}
        if (index < format.len and format[index] == '.') {
            index += 1;
            while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {}
        }
        while (index < format.len and (format[index] == 'l' or format[index] == 'h' or format[index] == 'z' or format[index] == 't' or format[index] == 'j')) : (index += 1) {}
        if (index >= format.len) break;
        const argument = self.nextVarArg(&arguments, &argument_index, &stack_argument);
        switch (format[index]) {
            's' => output.appendSlice(self.allocator, self.guestCString(argument, 1 << 20) orelse "(null)") catch return @bitCast(@as(i64, -1)),
            'c' => output.append(self.allocator, @truncate(argument)) catch return @bitCast(@as(i64, -1)),
            'd', 'i' => {
                const rendered = std.fmt.allocPrint(self.allocator, "{d}", .{@as(i64, @bitCast(argument))}) catch return @bitCast(@as(i64, -1));
                defer self.allocator.free(rendered);
                output.appendSlice(self.allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'u' => {
                const rendered = std.fmt.allocPrint(self.allocator, "{d}", .{argument}) catch return @bitCast(@as(i64, -1));
                defer self.allocator.free(rendered);
                output.appendSlice(self.allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'x', 'X', 'p' => {
                const rendered = std.fmt.allocPrint(self.allocator, "{x}", .{argument}) catch return @bitCast(@as(i64, -1));
                defer self.allocator.free(rendered);
                if (format[index] == 'p') output.appendSlice(self.allocator, "0x") catch return @bitCast(@as(i64, -1));
                output.appendSlice(self.allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'f', 'F', 'e', 'E', 'g', 'G', 'a', 'A' => output.append(self.allocator, '0') catch return @bitCast(@as(i64, -1)),
            else => {
                output.append(self.allocator, '%') catch return @bitCast(@as(i64, -1));
                output.append(self.allocator, format[index]) catch return @bitCast(@as(i64, -1));
            },
        }
    }
    if (capacity != 0) {
        const target = self.guestMemory(destination, capacity) orelse return @bitCast(@as(i64, -1));
        const written = @min(output.items.len, capacity - 1);
        @memcpy(target[0..written], output.items[0..written]);
        target[written] = 0;
    }
    return output.items.len;
}

pub fn handlePrintfLike(self: anytype, file_opt: ?*GuestFile, format_address: u64, arguments: []const u64) u64 {
    const format = self.guestCString(format_address, 1 << 20) orelse return @bitCast(@as(i64, -1));
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);

    var gp_index: usize = 0;
    var stack_arg_addr = self.regs.rsp + 8;
    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        if (format[i] != '%') {
            output.append(allocator, format[i]) catch return @bitCast(@as(i64, -1));
            continue;
        }
        i += 1;
        if (i >= format.len) break;
        if (format[i] == '%') {
            output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
            continue;
        }

        while (i < format.len and (format[i] == '-' or format[i] == '+' or format[i] == ' ' or format[i] == '#' or format[i] == '0')) : (i += 1) {}
        while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
        if (i < format.len and format[i] == '.') {
            i += 1;
            while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
        }
        while (i < format.len and
            (format[i] == 'l' or format[i] == 'h' or format[i] == 'z' or
                format[i] == 't' or format[i] == 'j' or format[i] == 'L')) : (i += 1)
        {}
        if (i >= format.len) break;

        const spec = format[i];
        const arg = self.nextVarArg(arguments, &gp_index, &stack_arg_addr);
        switch (spec) {
            's' => {
                const text = self.guestCString(arg, 1 << 20) orelse "(null)";
                output.appendSlice(allocator, text) catch return @bitCast(@as(i64, -1));
            },
            'd', 'i' => {
                const val: i64 = @bitCast(arg);
                const rendered = std.fmt.allocPrint(allocator, "{}", .{val}) catch return @bitCast(@as(i64, -1));
                output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'u' => {
                const rendered = std.fmt.allocPrint(allocator, "{}", .{arg}) catch return @bitCast(@as(i64, -1));
                output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'x' => {
                const rendered = std.fmt.allocPrint(allocator, "{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'X' => {
                const rendered = std.fmt.allocPrint(allocator, "{X}", .{arg}) catch return @bitCast(@as(i64, -1));
                output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'p' => {
                const rendered = std.fmt.allocPrint(allocator, "0x{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
            },
            'c' => {
                output.append(allocator, @intCast(arg & 0xFF)) catch return @bitCast(@as(i64, -1));
            },
            else => {
                output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                output.append(allocator, spec) catch return @bitCast(@as(i64, -1));
            },
        }
    }

    const sink = file_opt orelse self.guestFileFromHandle(GUEST_FILE_BASE + 1).?;
    if (!hostWriteAll(self, sink, output.items)) return @bitCast(@as(i64, -1));
    return output.items.len;
}

pub fn handlePutchar(self: anytype) u64 {
    const ch: u8 = @intCast(self.regs.rdi & 0xFF);
    const sink = self.guestFileFromHandle(GUEST_FILE_BASE + 1) orelse return @bitCast(@as(i64, -1));
    if (!hostWriteAll(self, sink, &[_]u8{ch})) return @bitCast(@as(i64, -1));
    return ch;
}

pub fn handleGtkInitCheck(self: anytype) u64 {
    const argc_ptr = self.regs.rdi;
    const argv_ptr = self.regs.rsi;
    _ = argc_ptr;
    _ = argv_ptr;
    machoCapturePrint("    [import] _gtk_init_check compatibility shim → success\n", .{});
    return 1;
}
