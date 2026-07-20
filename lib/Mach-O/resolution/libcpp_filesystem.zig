const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");

extern "c" fn strerror(error_value: c_int) ?[*:0]const u8;
extern "c" fn statvfs(path: [*:0]const u8, result: *StatVfs) c_int;

const StatVfs = extern struct {
    block_size: c_ulong,
    fragment_size: c_ulong,
    blocks: c_uint,
    blocks_free: c_uint,
    blocks_available: c_uint,
    files: c_uint,
    files_free: c_uint,
    files_available: c_uint,
    filesystem_id: c_ulong,
    flags: c_ulong,
    name_max: c_ulong,
};

const COPY_SKIP_EXISTING: u16 = 1;
const COPY_OVERWRITE_EXISTING: u16 = 2;
const COPY_UPDATE_EXISTING: u16 = 4;
const COPY_RECURSIVE: u16 = 8;
const COPY_SYMLINKS: u16 = 16;
const COPY_SKIP_SYMLINKS: u16 = 32;
const COPY_DIRECTORIES_ONLY: u16 = 64;
const COPY_CREATE_SYMLINKS: u16 = 128;
const COPY_CREATE_HARD_LINKS: u16 = 256;

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
    capacity_calls: u64 = 0,
    copy_calls: u64 = 0,
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
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem7__spaceERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.space(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem13__fs_is_emptyERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.isEmpty(state, fs) };
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
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem12__remove_allERKNS1_4pathEPNS_10error_codeE")) {
            return .{ .handled = self.removeAll(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem8__renameERKNS1_4pathES4_PNS_10error_codeE")) {
            return .{ .handled = self.rename(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem11__copy_fileERKNS1_4pathES4_NS1_12copy_optionsEPNS_10error_codeE")) {
            return .{ .handled = self.copyFile(state, fs) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem6__copyERKNS1_4pathES4_NS1_12copy_optionsEPNS_10error_codeE")) {
            self.copy(state, fs);
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt3__14__fs10filesystem4path17replace_extensionERKS2_")) {
            return .{ .handled = self.replaceExtension(state) };
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
        if (self.status_calls == 0 and self.path_calls == 0 and self.mutation_calls == 0 and self.capacity_calls == 0 and self.copy_calls == 0) return;
        std.debug.print(
            "macho-processor: libc++ filesystem: status={d} paths={d} capacity={d} mutations={d} copies={d} errors={d}\n",
            .{ self.status_calls, self.path_calls, self.capacity_calls, self.mutation_calls, self.copy_calls, self.errors_written },
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
        const flags: u32 = if (follow_symlinks) 0 else std.c.AT.SYMLINK_NOFOLLOW;
        const rc = std.c.fstatat(std.c.AT.FDCWD, c_path, &host_status, flags);
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
        if (shouldTrace(self.status_calls) or isDiagnosticPath(path) or isDiagnosticPath(translated)) {
            std.debug.print(
                "macho-processor: libc++ filesystem status #{d}: guest_path={s} host_path={s} follow_symlinks={} -> type={d}\n",
                .{ self.status_calls, path, translated, follow_symlinks, @as(i8, @bitCast(state.read8(output))) },
            );
        }
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
        const rc = std.c.fstatat(std.c.AT.FDCWD, c_path, &host_status, 0);
        if (rc != 0) {
            self.writeErrorCode(state, state.regs.rsi, @intCast(@intFromEnum(std.c.errno(rc))), false);
            return std.math.maxInt(u64);
        }
        self.writeErrorCode(state, state.regs.rsi, 0, false);
        return @bitCast(@as(i64, host_status.size));
    }

    fn space(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.capacity_calls +|= 1;
        const output = state.regs.rdi;
        const path = pathView(state, state.regs.rsi) orelse return output;
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return output;
        var path_z: [4096:0]u8 = undefined;
        const c_path = terminate(&path_z, translated) orelse return output;
        var host_space: StatVfs = undefined;
        const rc = statvfs(c_path, &host_space);
        if (rc != 0) {
            writeSpaceInfo(state, output, std.math.maxInt(u64), std.math.maxInt(u64), std.math.maxInt(u64));
            self.writeErrorCode(state, state.regs.rdx, errnoValue(rc), false);
            return output;
        }
        const unit: u64 = if (host_space.fragment_size != 0) host_space.fragment_size else host_space.block_size;
        writeSpaceInfo(
            state,
            output,
            saturatingMultiply(unit, host_space.blocks),
            saturatingMultiply(unit, host_space.blocks_free),
            saturatingMultiply(unit, host_space.blocks_available),
        );
        self.writeErrorCode(state, state.regs.rdx, 0, false);
        return output;
    }

    fn isEmpty(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.status_calls +|= 1;
        const path = pathView(state, state.regs.rdi) orelse return 0;
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return 0;
        const result = hostIsEmpty(translated);
        self.writeErrorCode(state, state.regs.rsi, result.error_value, false);
        return @intFromBool(result.empty and result.error_value == 0);
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
        var host_status: std.c.Stat = undefined;
        const stat_rc = std.c.fstatat(std.c.AT.FDCWD, c_path, &host_status, std.c.AT.SYMLINK_NOFOLLOW);
        if (stat_rc != 0 and (std.c.errno(stat_rc) == .NOENT or std.c.errno(stat_rc) == .NOTDIR)) {
            self.writeErrorCode(state, state.regs.rsi, 0, false);
            return 0;
        }
        const rc = if (stat_rc == 0 and std.c.S.ISDIR(host_status.mode)) std.c.rmdir(c_path) else std.c.unlink(c_path);
        if (rc != 0 and std.c.errno(rc) == .NOENT) {
            self.writeErrorCode(state, state.regs.rsi, 0, false);
            return 0;
        }
        self.writeErrorCode(state, state.regs.rsi, if (rc == 0) 0 else @intCast(@intFromEnum(std.c.errno(rc))), false);
        return @intFromBool(rc == 0);
    }

    fn removeAll(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.mutation_calls +|= 1;
        const path = pathView(state, state.regs.rdi) orelse return std.math.maxInt(u64);
        var translated_buffer: [4096]u8 = undefined;
        const translated = fs.resolveHostPath(path, &translated_buffer) orelse return std.math.maxInt(u64);
        const result = removeTree(translated);
        self.writeErrorCode(state, state.regs.rsi, result.error_value, false);
        return if (result.error_value == 0) result.count else std.math.maxInt(u64);
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

    fn copyFile(self: *Bridge, state: anytype, fs: anytype) u64 {
        self.copy_calls +|= 1;
        const source = pathView(state, state.regs.rdi) orelse return 0;
        const destination = pathView(state, state.regs.rsi) orelse return 0;
        var source_buffer: [4096]u8 = undefined;
        var destination_buffer: [4096]u8 = undefined;
        const host_source = fs.resolveHostPath(source, &source_buffer) orelse return 0;
        const host_destination = fs.resolveHostPath(destination, &destination_buffer) orelse return 0;
        const result = copyOneFile(host_source, host_destination, @truncate(state.regs.rdx));
        self.writeErrorCode(state, state.regs.rcx, result.error_value, false);
        return @intFromBool(result.copied and result.error_value == 0);
    }

    fn copy(self: *Bridge, state: anytype, fs: anytype) void {
        self.copy_calls +|= 1;
        const source = pathView(state, state.regs.rdi) orelse return;
        const destination = pathView(state, state.regs.rsi) orelse return;
        var source_buffer: [4096]u8 = undefined;
        var destination_buffer: [4096]u8 = undefined;
        const host_source = fs.resolveHostPath(source, &source_buffer) orelse return;
        const host_destination = fs.resolveHostPath(destination, &destination_buffer) orelse return;
        const result = copyTree(host_source, host_destination, @truncate(state.regs.rdx));
        self.writeErrorCode(state, state.regs.rcx, result.error_value, false);
    }

    fn replaceExtension(self: *Bridge, state: anytype) u64 {
        self.path_calls +|= 1;
        const object = state.regs.rdi;
        const original = pathView(state, object) orelse return object;
        const replacement = pathView(state, state.regs.rsi) orelse return object;
        var result_buffer: [4096]u8 = undefined;
        const prefix_length = extensionStart(original) orelse original.len;
        const dot_length: usize = @intFromBool(replacement.len != 0 and replacement[0] != '.');
        const result_length = prefix_length + dot_length + replacement.len;
        if (result_length > result_buffer.len) return object;
        @memcpy(result_buffer[0..prefix_length], original[0..prefix_length]);
        if (dot_length != 0) result_buffer[prefix_length] = '.';
        @memcpy(result_buffer[prefix_length + dot_length .. result_length], replacement);
        _ = compat_runtime.initLibcppStringFromSlice(state, object, result_buffer[0..result_length]);
        return object;
    }

    fn errorMessage(self: *Bridge, state: anytype) u64 {
        _ = self;
        const output = state.regs.rdi;
        const value: i32 = @bitCast(state.read32(state.regs.rsi));
        const message_ptr = strerror(value) orelse return output;
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

const EmptyResult = struct {
    empty: bool,
    error_value: i32,
};

const RemoveTreeResult = struct {
    count: u64,
    error_value: i32,
};

const CopyResult = struct {
    copied: bool,
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

fn writeSpaceInfo(state: anytype, output: u64, capacity: u64, free: u64, available: u64) void {
    const bytes = state.guestMemory(output, 24) orelse return;
    std.mem.writeInt(u64, bytes[0..8], capacity, .little);
    std.mem.writeInt(u64, bytes[8..16], free, .little);
    std.mem.writeInt(u64, bytes[16..24], available, .little);
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

fn hostIsEmpty(path: []const u8) EmptyResult {
    var path_z: [4096:0]u8 = undefined;
    const c_path = terminate(&path_z, path) orelse return .{ .empty = false, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
    var host_status: std.c.Stat = undefined;
    const stat_rc = std.c.fstatat(std.c.AT.FDCWD, c_path, &host_status, 0);
    if (stat_rc != 0) return .{ .empty = false, .error_value = errnoValue(stat_rc) };
    if (!std.c.S.ISDIR(host_status.mode)) return .{ .empty = host_status.size == 0, .error_value = 0 };

    const directory = std.c.opendir(c_path) orelse return .{ .empty = false, .error_value = errnoValue(-1) };
    defer _ = std.c.closedir(directory);
    while (std.c.readdir(directory)) |entry| {
        const name = entry.name[0..entry.namlen];
        if (isDotEntry(name)) continue;
        return .{ .empty = false, .error_value = 0 };
    }
    return .{ .empty = true, .error_value = 0 };
}

fn removeTree(path: []const u8) RemoveTreeResult {
    var path_z: [4096:0]u8 = undefined;
    const c_path = terminate(&path_z, path) orelse return .{ .count = 0, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
    var host_status: std.c.Stat = undefined;
    const stat_rc = std.c.fstatat(std.c.AT.FDCWD, c_path, &host_status, std.c.AT.SYMLINK_NOFOLLOW);
    if (stat_rc != 0) {
        const error_value = errnoValue(stat_rc);
        if (error_value == @intFromEnum(std.c.E.NOENT) or error_value == @intFromEnum(std.c.E.NOTDIR)) {
            return .{ .count = 0, .error_value = 0 };
        }
        return .{ .count = 0, .error_value = error_value };
    }
    if (!std.c.S.ISDIR(host_status.mode)) {
        const rc = std.c.unlink(c_path);
        return .{ .count = @intFromBool(rc == 0), .error_value = if (rc == 0) 0 else errnoValue(rc) };
    }

    const directory = std.c.opendir(c_path) orelse return .{ .count = 0, .error_value = errnoValue(-1) };
    var count: u64 = 0;
    while (std.c.readdir(directory)) |entry| {
        const name = entry.name[0..entry.namlen];
        if (isDotEntry(name)) continue;
        var child_buffer: [4096]u8 = undefined;
        const child = joinPath(&child_buffer, path, name) orelse {
            _ = std.c.closedir(directory);
            return .{ .count = count, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
        };
        const child_result = removeTree(child);
        count +|= child_result.count;
        if (child_result.error_value != 0) {
            _ = std.c.closedir(directory);
            return .{ .count = count, .error_value = child_result.error_value };
        }
    }
    _ = std.c.closedir(directory);
    const rc = std.c.rmdir(c_path);
    if (rc != 0) return .{ .count = count, .error_value = errnoValue(rc) };
    return .{ .count = count +| 1, .error_value = 0 };
}

fn copyOneFile(source: []const u8, destination: []const u8, options: u16) CopyResult {
    if ((options & (COPY_SYMLINKS | COPY_SKIP_SYMLINKS | COPY_DIRECTORIES_ONLY | COPY_CREATE_SYMLINKS | COPY_CREATE_HARD_LINKS)) != 0) {
        return .{ .copied = false, .error_value = @intFromEnum(std.c.E.OPNOTSUPP) };
    }
    var source_z: [4096:0]u8 = undefined;
    var destination_z: [4096:0]u8 = undefined;
    const c_source = terminate(&source_z, source) orelse return .{ .copied = false, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
    const c_destination = terminate(&destination_z, destination) orelse return .{ .copied = false, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };

    var source_status: std.c.Stat = undefined;
    const source_stat_rc = std.c.fstatat(std.c.AT.FDCWD, c_source, &source_status, 0);
    if (source_stat_rc != 0) return .{ .copied = false, .error_value = errnoValue(source_stat_rc) };
    if (!std.c.S.ISREG(source_status.mode)) return .{ .copied = false, .error_value = @intFromEnum(std.c.E.INVAL) };

    var destination_status: std.c.Stat = undefined;
    const destination_exists = std.c.fstatat(std.c.AT.FDCWD, c_destination, &destination_status, 0) == 0;
    if (destination_exists) {
        if ((options & COPY_SKIP_EXISTING) != 0) return .{ .copied = false, .error_value = 0 };
        if ((options & COPY_UPDATE_EXISTING) != 0 and !isNewer(source_status.mtimespec, destination_status.mtimespec)) {
            return .{ .copied = false, .error_value = 0 };
        }
        if ((options & (COPY_OVERWRITE_EXISTING | COPY_UPDATE_EXISTING)) == 0) {
            return .{ .copied = false, .error_value = @intFromEnum(std.c.E.EXIST) };
        }
    }

    const source_fd = std.c.open(c_source, @bitCast(@as(u32, 0)), @as(c_int, 0));
    if (source_fd < 0) return .{ .copied = false, .error_value = errnoValue(source_fd) };
    defer _ = std.c.close(source_fd);
    const destination_flags: u32 = 0x0001 | 0x0200 | 0x0400 | (if (destination_exists) @as(u32, 0) else 0x0800);
    const destination_fd = std.c.open(c_destination, @bitCast(destination_flags), @as(c_int, @intCast(source_status.mode & 0o777)));
    if (destination_fd < 0) return .{ .copied = false, .error_value = errnoValue(destination_fd) };
    defer _ = std.c.close(destination_fd);

    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const read_count = std.c.read(source_fd, &buffer, buffer.len);
        if (read_count < 0) return .{ .copied = false, .error_value = errnoValue(read_count) };
        if (read_count == 0) break;
        var written: usize = 0;
        const bytes_read: usize = @intCast(read_count);
        while (written < bytes_read) {
            const write_count = std.c.write(destination_fd, buffer[written..bytes_read].ptr, bytes_read - written);
            if (write_count < 0) return .{ .copied = false, .error_value = errnoValue(write_count) };
            if (write_count == 0) return .{ .copied = false, .error_value = @intFromEnum(std.c.E.IO) };
            written += @intCast(write_count);
        }
    }
    return .{ .copied = true, .error_value = 0 };
}

fn copyTree(source: []const u8, destination: []const u8, options: u16) CopyResult {
    var source_z: [4096:0]u8 = undefined;
    const c_source = terminate(&source_z, source) orelse return .{ .copied = false, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
    var source_status: std.c.Stat = undefined;
    const stat_rc = std.c.fstatat(std.c.AT.FDCWD, c_source, &source_status, std.c.AT.SYMLINK_NOFOLLOW);
    if (stat_rc != 0) return .{ .copied = false, .error_value = errnoValue(stat_rc) };
    if (std.c.S.ISLNK(source_status.mode)) {
        if ((options & COPY_SKIP_SYMLINKS) != 0) return .{ .copied = false, .error_value = 0 };
        return .{ .copied = false, .error_value = @intFromEnum(std.c.E.OPNOTSUPP) };
    }
    if (!std.c.S.ISDIR(source_status.mode)) {
        if ((options & COPY_DIRECTORIES_ONLY) != 0) return .{ .copied = false, .error_value = 0 };
        return copyOneFile(source, destination, options & ~(COPY_RECURSIVE | COPY_DIRECTORIES_ONLY));
    }

    const created = makeOneDirectory(destination);
    if (created.error_value != 0) return .{ .copied = false, .error_value = created.error_value };
    if ((options & COPY_RECURSIVE) == 0) return .{ .copied = created.created, .error_value = 0 };
    const directory = std.c.opendir(c_source) orelse return .{ .copied = false, .error_value = errnoValue(-1) };
    var copied = created.created;
    while (std.c.readdir(directory)) |entry| {
        const name = entry.name[0..entry.namlen];
        if (isDotEntry(name)) continue;
        var source_child_buffer: [4096]u8 = undefined;
        var destination_child_buffer: [4096]u8 = undefined;
        const source_child = joinPath(&source_child_buffer, source, name) orelse {
            _ = std.c.closedir(directory);
            return .{ .copied = copied, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
        };
        const destination_child = joinPath(&destination_child_buffer, destination, name) orelse {
            _ = std.c.closedir(directory);
            return .{ .copied = copied, .error_value = @intFromEnum(std.c.E.NAMETOOLONG) };
        };
        const child_result = copyTree(source_child, destination_child, options);
        copied = copied or child_result.copied;
        if (child_result.error_value != 0) {
            _ = std.c.closedir(directory);
            return .{ .copied = copied, .error_value = child_result.error_value };
        }
    }
    _ = std.c.closedir(directory);
    return .{ .copied = copied, .error_value = 0 };
}

fn isDotEntry(name: []const u8) bool {
    return std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..");
}

fn extensionStart(path: []const u8) ?usize {
    const filename_start = if (std.mem.lastIndexOfScalar(u8, path, '/')) |separator| separator + 1 else 0;
    const filename = path[filename_start..];
    if (filename.len == 0 or std.mem.eql(u8, filename, ".") or std.mem.eql(u8, filename, "..")) return null;
    const dot = std.mem.lastIndexOfScalar(u8, filename, '.') orelse return null;
    if (dot == 0) return null;
    return filename_start + dot;
}

fn isNewer(source: std.c.timespec, destination: std.c.timespec) bool {
    return source.sec > destination.sec or (source.sec == destination.sec and source.nsec > destination.nsec);
}

fn errnoValue(rc: anytype) i32 {
    return @intCast(@intFromEnum(std.c.errno(rc)));
}

fn saturatingMultiply(left: anytype, right: anytype) u64 {
    return std.math.mul(u64, @intCast(left), @intCast(right)) catch std.math.maxInt(u64);
}

fn shouldTrace(count: u64) bool {
    return count <= 8 or count % 1000 == 0;
}

fn isDiagnosticPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".patch.toml") or
        std.mem.indexOf(u8, path, "User_") != null or
        std.mem.indexOf(u8, path, "Account") != null or
        std.mem.indexOf(u8, path, "/content/") != null;
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

test "host filesystem lifecycle supports copy and recursive removal" {
    var root_buffer: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buffer, "/tmp/rosette-libcpp-fs-{d}", .{std.c.getpid()});
    _ = removeTree(root);
    defer _ = removeTree(root);

    const created = makePath(root);
    try std.testing.expectEqual(@as(i32, 0), created.error_value);
    try std.testing.expect((hostIsEmpty(root)).empty);

    var source_buffer: [512]u8 = undefined;
    var destination_buffer: [512]u8 = undefined;
    const source = joinPath(&source_buffer, root, "source.bin").?;
    const destination = joinPath(&destination_buffer, root, "destination.bin").?;
    var source_z: [4096:0]u8 = undefined;
    const source_fd = std.c.open(
        terminate(&source_z, source).?,
        @bitCast(@as(u32, 0x0001 | 0x0200 | 0x0400 | 0x0800)),
        @as(c_int, 0o600),
    );
    try std.testing.expect(source_fd >= 0);
    const payload = "rosette-filesystem-bridge";
    try std.testing.expectEqual(@as(isize, payload.len), std.c.write(source_fd, payload.ptr, payload.len));
    try std.testing.expectEqual(@as(c_int, 0), std.c.close(source_fd));
    try std.testing.expect(!(hostIsEmpty(root)).empty);

    const copied = copyOneFile(source, destination, 0);
    try std.testing.expect(copied.copied);
    try std.testing.expectEqual(@as(i32, 0), copied.error_value);
    const skipped = copyOneFile(source, destination, COPY_SKIP_EXISTING);
    try std.testing.expect(!skipped.copied);
    try std.testing.expectEqual(@as(i32, 0), skipped.error_value);

    const removed = removeTree(root);
    try std.testing.expectEqual(@as(i32, 0), removed.error_value);
    try std.testing.expect(removed.count >= 3);
}

test "extension replacement preserves path and hidden-file rules" {
    try std.testing.expectEqual(@as(?usize, 8), extensionStart("dir/name.txt"));
    try std.testing.expectEqual(@as(?usize, null), extensionStart("dir/.config"));
    try std.testing.expectEqual(@as(?usize, null), extensionStart("dir/.."));
}
