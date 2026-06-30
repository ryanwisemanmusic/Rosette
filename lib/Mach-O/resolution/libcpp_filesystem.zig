const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");

const FILE_TYPE_NONE: i8 = 0;
const FILE_TYPE_NOT_FOUND: i8 = -1;
const FILE_TYPE_REGULAR: i8 = 1;
const FILE_TYPE_DIRECTORY: i8 = 2;
const FILE_TYPE_SYMLINK: i8 = 3;
const FILE_TYPE_BLOCK: i8 = 4;
const FILE_TYPE_CHARACTER: i8 = 5;
const FILE_TYPE_FIFO: i8 = 6;
const FILE_TYPE_SOCKET: i8 = 7;
const FILE_TYPE_UNKNOWN: i8 = 8;
const PERMS_UNKNOWN: u32 = 0xFFFF;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

pub const Bridge = struct {
    system_category: u64 = 0,
    generic_category: u64 = 0,
    status_calls: u64 = 0,
    path_calls: u64 = 0,
    mutation_calls: u64 = 0,
    errors_written: u64 = 0,

    pub fn dispatch(self: *Bridge, state: anytype, fs: anytype, name: []const u8) ?Outcome {
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem8__statusERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.status(state, fs, true) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem16__symlink_statusERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.status(state, fs, false) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem10__absoluteERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.absolute(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem11__canonicalERKNS1_4pathEPNS_10error_codeE") or
            std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem18__weakly_canonicalERKNS1_4pathEPNS_10error_codeE"))
        {
            return .{ .handled = self.canonical(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem11__file_sizeERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.fileSize(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem18__create_directoryERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.createDirectory(state, fs, false) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem20__create_directoriesERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.createDirectory(state, fs, true) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem8__removeERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.remove(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem8__renameERKNS1_4pathES4_PNS_10error_codeE")) {
            return .{ .handled = self.rename(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__115system_categoryEv")) {
            return .{ .handled = self.category(state, false) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__116generic_categoryEv")) {
            return .{ .handled = self.category(state, true) };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__110error_code7messageEv")) {
            return .{ .handled = self.errorMessage(state) };
        }
        return null;
    }

    pub fn logSummary(self: *const Bridge) void {
        if (self.status_calls == 0 and self.path_calls == 0 and self.mutation_calls == 0) return;
        std.debug.print(
            "macho-processor: libc++ filesystem: status={d} paths={d} mutations={d} errors={d}\n",
            .{ self.status_calls, self.path_calls, self.mutation_calls, self.errors_written },
        );
    }

    fn status(self: *Bridge, state: anytype, fs: anytype, follow_symlinks: bool) u64 {
        self.status_calls +|= 1;
        const output = state.regs.rdi;
        const path = pathView(state, state.regs.rsi) orelse return output;
        var buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &buffer) orelse return output;
        var path_z: [4096:0]u8 = undefined;
        const c_path = terminate(&path_z, translated) orelse return output;
        var host_status: std.c.Stat = undefined;
        const rc = if (follow_symlinks) std.c.stat(c_path, &host_status) else std.c.lstat(c_path, &host_status);
        if (rc == 0) {
            writeFileStatus(state, output, fileType(host_status.mode), @as(u32, @intCast(host_status.mode)) & 0o7777);
            self.writeErrorCode(state, state.regs.rdx, 0, false);
        } else {
            const error_value: i32 = @intCast(@intFromEnum(std.c.errno(rc)));
            if (error_value == @intFromEnum(std.c.E.NOENT) or error_value == @intFromEnum(std.c.E.NOTDIR)) {
                writeFileStatus(state, output, FILE_TYPE_NOT_FOUND, PERMS_UNKNOWN);
                self.writeErrorCode(state, state.regs.rdx, 0, false);
            } else {
                writeFileStatus(state, output, FILE_TYPE_NONE, PERMS_UNKNOWN);
                self.writeErrorCode(state, state.regs.rdx, error_value, false);
            }
        }
        std.debug.print("macho-processor: libc++ filesystem status: {s} -> type={d}\n", .{ translated, @as(i8, @bitCast(state.read8(output))) });
        return output;
    }

    fn absolute(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.path_calls +|= 1;
        const output = state.regs.rdi;
        const path = pathView(state, state.regs.rsi) orelse return output;
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return output;
        if (std.fs.path.isAbsolute(translated)) {
            _ = compat_runtime.initLibcppStringFromSlice(state, output, translated);
            self.writeErrorCode(state, state.regs.rdx, 0, false);
            return output;
        }
        var cwd_buffer: [4096]u8 = undefined;
        const cwd_ptr = std.c.getcwd(&cwd_buffer, cwd_buffer.len) orelse return output;
        const cwd = std.mem.sliceTo(cwd_ptr, 0);
        var result: [4096]u8 = undefined;
        const joined = joinPath(&result, cwd, translated) orelse return output;
        _ = compat_runtime.initLibcppStringFromSlice(state, output, joined);
        self.writeErrorCode(state, state.regs.rdx, 0, false);
        return output;
    }

    fn canonical(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.path_calls +|= 1;
        const output = state.regs.rdi;
        const path = pathView(state, state.regs.rsi) orelse return output;
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return output;
        var path_z: [4096:0]u8 = undefined;
        const c_path = terminate(&path_z, translated) orelse return output;
        var resolved: [4096]u8 = undefined;
        const resolved_ptr = std.c.realpath(c_path, &resolved) orelse {
            self.writeErrorCode(state, state.regs.rdx, @intCast(@intFromEnum(std.c.errno(-1))), false);
            _ = compat_runtime.initLibcppStringFromSlice(state, output, "");
            return output;
        };
        const result = std.mem.sliceTo(resolved_ptr, 0);
        _ = compat_runtime.initLibcppStringFromSlice(state, output, result);
        self.writeErrorCode(state, state.regs.rdx, 0, false);
        return output;
    }

    fn fileSize(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.status_calls +|= 1;
        const path = pathView(state, state.regs.rdi) orelse return std.math.maxInt(u64);
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return std.math.maxInt(u64);
        var path_z: [4096:0]u8 = undefined;
        const c_path = terminate(&path_z, translated) orelse return std.math.maxInt(u64);
        var host_status: std.c.Stat = undefined;
        const rc = std.c.stat(c_path, &host_status);
        if (rc != 0) {
            self.writeErrorCode(state, state.regs.rsi, @intCast(@intFromEnum(std.c.errno(rc))), false);
            return std.math.maxInt(u64);
        }
        self.writeErrorCode(state, state.regs.rsi, 0, false);
        return @bitCast(@as(i64, host_status.size));
    }

    fn createDirectory(self: *Bridge, state: anytype, fs: anytype, recursive: bool) u64 {
        self.mutation_calls +|= 1;
        const path = pathView(state, state.regs.rdi) orelse return 0;
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return 0;
        const result = if (recursive) makePath(translated) else makeOneDirectory(translated);
        if (result.error_value != 0) self.errors_written +|= 1;
        self.writeErrorCode(state, state.regs.rsi, result.error_value, false);
        return @intFromBool(result.created);
    }

    fn remove(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.mutation_calls +|= 1;
        const path = pathView(state, state.regs.rdi) orelse return 0;
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return 0;
        var path_z: [4096:0]u8 = undefined;
        const c_path = terminate(&path_z, translated) orelse return 0;
        var rc = std.c.unlink(c_path);
        if (rc != 0 and std.c.errno(rc) == .ISDIR) rc = std.c.rmdir(c_path);
        if (rc != 0 and std.c.errno(rc) == .NOENT) {
            self.writeErrorCode(state, state.regs.rsi, 0, false);
            return 0;
        }
        self.writeErrorCode(state, state.regs.rsi, if (rc == 0) 0 else @intCast(@intFromEnum(std.c.errno(rc))), false);
        return @intFromBool(rc == 0);
    }

    fn rename(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.mutation_calls +|= 1;
        const old_path = pathView(state, state.regs.rdi) orelse return 0;
        const new_path = pathView(state, state.regs.rsi) orelse return 0;
        var old_buffer: [4096]u8 = undefined;
        var new_buffer: [4096]u8 = undefined;
        const old_translated = fs.resolveHostPath(old_path, &old_buffer) orelse return 0;
        const new_translated = fs.resolveHostPath(new_path, &new_buffer) orelse return 0;
        var old_z: [4096:0]u8 = undefined;
        var new_z: [4096:0]u8 = undefined;
        const rc = std.c.rename(terminate(&old_z, old_translated) orelse return 0, terminate(&new_z, new_translated) orelse return 0);
        self.writeErrorCode(state, state.regs.rdx, if (rc == 0) 0 else @intCast(@intFromEnum(std.c.errno(rc))), false);
        return 0;
    }

    fn errorMessage(self: *Bridge, state: anytype) u64 {
        const output = state.regs.rdi;
        const value: i32 = @bitCast(state.read32(state.regs.rsi));
        const message_ptr = std.c.strerror(value) orelse return output;
        _ = compat_runtime.initLibcppStringFromSlice(state, output, std.mem.span(message_ptr));
        return output;
    }

    fn writeErrorCode(self: *Bridge, state: anytype, address: u64, value: i32, generic: bool) void {
        if (address == 0 or state.guestMemory(address, 16) == null) return;
        state.write32(address, @bitCast(value));
        state.write64(address + 8, self.category(state, generic));
        if (value != 0) self.errors_written +|= 1;
    }

    fn category(self: *Bridge, state: anytype, generic: bool) u64 {
        const slot = if (generic) &self.generic_category else &self.system_category;
        if (slot.* == 0) {
            slot.* = state.guestAlloc(16, 8) orelse return 0;
            state.write64(slot.*, if (generic) 0x4745_4E45_5249_4300 else 0x5359_5354_454D_0000);
        }
        return slot.*;
    }
};

const CreateResult = struct {
    created: bool,
    error_value: i32,
};

fn pathView(state: anytype, object: u64) ?[]const u8 {
    const view = compat_runtime.libcppStringView(state, object) orelse return null;
    return state.guestMemoryConst(view.address, view.length);
}

fn writeFileStatus(state: anytype, output: u64, file_type: i8, permissions: u32) void {
    const bytes = state.guestMemory(output, 8) orelse return;
    @memset(bytes, 0);
    bytes[0] = @bitCast(file_type);
    std.mem.writeInt(u32, bytes[4..8], permissions, .little);
}

fn fileType(mode: std.c.mode_t) i8 {
    if (std.c.S.ISREG(mode)) return FILE_TYPE_REGULAR;
    if (std.c.S.ISDIR(mode)) return FILE_TYPE_DIRECTORY;
    if (std.c.S.ISLNK(mode)) return FILE_TYPE_SYMLINK;
    if (std.c.S.ISBLK(mode)) return FILE_TYPE_BLOCK;
    if (std.c.S.ISCHR(mode)) return FILE_TYPE_CHARACTER;
    if (std.c.S.ISFIFO(mode)) return FILE_TYPE_FIFO;
    if (std.c.S.ISSOCK(mode)) return FILE_TYPE_SOCKET;
    return FILE_TYPE_UNKNOWN;
}

fn terminate(buffer: *[4096:0]u8, value: []const u8) ?[*:0]const u8 {
    if (value.len >= buffer.len) return null;
    @memcpy(buffer[0..value.len], value);
    buffer[value.len] = 0;
    return @ptrCast(buffer);
}

fn joinPath(buffer: []u8, base: []const u8, child: []const u8) ?[]const u8 {
    const separator: usize = @intFromBool(base.len != 0 and base[base.len - 1] != '/');
    const total = base.len + separator + child.len;
    if (total > buffer.len) return null;
    @memcpy(buffer[0..base.len], base);
    if (separator != 0) buffer[base.len] = '/';
    @memcpy(buffer[base.len + separator .. total], child);
    return buffer[0..total];
}

fn makeOneDirectory(path: []const u8) CreateResult {
    var path_z: [4096:0]u8 = undefined;
    const c_path = terminate(&path_z, path) orelse return .{ .created = false, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
    const rc = std.c.mkdir(c_path, 0o755);
    if (rc == 0) return .{ .created = true, .error_value = 0 };
    const err = std.c.errno(rc);
    if (err == .EXIST) return .{ .created = false, .error_value = 0 };
    return .{ .created = false, .error_value = @intCast(@intFromEnum(err)) };
}

fn makePath(path: []const u8) CreateResult {
    if (path.len == 0) return .{ .created = false, .error_value = @intFromEnum(std.c.E.NOENT) };
    var scratch: [4096]u8 = undefined;
    if (path.len >= scratch.len) return .{ .created = false, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
    @memcpy(scratch[0..path.len], path);
    var created = false;
    var index: usize = if (path[0] == '/') 1 else 0;
    while (index <= path.len) : (index += 1) {
        if (index != path.len and scratch[index] != '/') continue;
        if (index == 0) continue;
        const result = makeOneDirectory(scratch[0..index]);
        if (result.error_value != 0) return .{ .created = created, .error_value = result.error_value };
        created = created or result.created;
    }
    return .{ .created = created, .error_value = 0 };
}

test "file status layout matches libc++ ABI v160006" {
    const TestState = struct {
        mem: [16]u8 = [_]u8{0} ** 16,
        fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }
    };
    var state = TestState{};
    writeFileStatus(&state, 0, FILE_TYPE_DIRECTORY, 0o755);
    try std.testing.expectEqual(@as(u8, 2), state.mem[0]);
    try std.testing.expectEqual(@as(u32, 0o755), std.mem.readInt(u32, state.mem[4..8], .little));
}

test "recursive path creation helper accepts an existing temp directory" {
    const result = makePath("/tmp");
    try std.testing.expectEqual(@as(i32, 0), result.error_value);
}
