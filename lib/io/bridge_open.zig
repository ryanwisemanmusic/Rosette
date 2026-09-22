const std = @import("std");
const cxx_object_model = @import("cxx_abi").cxx_object_model;
const machoCapturePrint = @import("event_log").machoCapturePrint;
const types = @import("bridge_types.zig");
const OPENMODE_APP = types.OPENMODE_APP;
const OPENMODE_ATE = types.OPENMODE_ATE;
const OPENMODE_IN = types.OPENMODE_IN;
const OPENMODE_OUT = types.OPENMODE_OUT;
const OPENMODE_TRUNC = types.OPENMODE_TRUNC;
const Stream = types.Stream;
const closeStream = types.closeStream;

pub fn openCString(self: anytype, state: anytype, fs: anytype, object: u64, path_address: u64, mode: u64) u64 {
    const path = state.guestCString(path_address, 4096) orelse {
        self.rejected += 1;
        return 0;
    };
    return self.openBytes(state, fs, object, path, mode);
}

pub fn openPath(self: anytype, state: anytype, fs: anytype, object: u64, address: u64, length: u64, mode: u64) u64 {
    const path = state.guestMemoryConst(address, length) orelse {
        self.rejected += 1;
        return 0;
    };
    return self.openBytes(state, fs, object, path, mode);
}

pub fn openBytes(self: anytype, state: anytype, fs: anytype, object: u64, path: []const u8, mode: u64) u64 {
    self.opens += 1;
    if (std.mem.eql(u8, path, "/proc/self/maps")) {
        return self.openProcSelfMaps(state, object, mode);
    }
    var translated_buffer: [4096]u8 = undefined;
    const translated = fs.resolveHostPath(path, &translated_buffer) orelse path;
    if (translated.len >= translated_buffer.len) {
        self.rejected += 1;
        return 0;
    }
    var path_z_buffer: [4096]u8 = undefined;
    @memcpy(path_z_buffer[0..translated.len], translated);
    path_z_buffer[translated.len] = 0;

    var flags: std.c.O = .{};
    const input = mode & OPENMODE_IN != 0;
    const output = mode & OPENMODE_OUT != 0;
    flags.ACCMODE = if (input and output) .RDWR else if (output) .WRONLY else .RDONLY;
    flags.CREAT = output;
    flags.TRUNC = mode & OPENMODE_TRUNC != 0;
    flags.APPEND = mode & OPENMODE_APP != 0;
    const fd = std.c.open(@ptrCast(&path_z_buffer), flags, @as(std.c.mode_t, 0o666));
    if (fd < 0) {
        self.open_failures +|= 1;
        if (self.find(object)) |stream| stream.failed = true;
        machoCapturePrint(
            "macho-processor: libc++ filebuf open failed: guest_path={s} host_path={s} mode=0x{x} errno={s}\n",
            .{ path, translated, mode, @tagName(std.c.errno(fd)) },
        );
        return 0;
    }

    const stream = self.ensure(object) orelse {
        _ = std.c.close(fd);
        self.rejected += 1;
        return 0;
    };
    closeStream(stream);
    // fd aliasing guard: if a stale stream entry still holds the same fd
    // number (recycled by the OS after a lifecycle bug left a ghost entry),
    // deactivate it without closing the fd (which would close OUR just-
    // opened file).  The stale entry was either already closed or never
    // should have held that fd in the first place.
    // (no &other ≠ stream guard needed: closeStream cleared our fd to -1,
    //  so an other.fd == fd match cannot be our own entry)
    for (&self.streams) |*other| {
        if (other.active and other.fd == fd) {
            other.active = false;
            other.fd = -1;
            machoCapturePrint("macho-processor: libc++ fd aliasing cleanup: deactivated stale ghost entry object=0x{x}\n", .{other.object});
        }
    }
    stream.fd = fd;
    stream.synthetic_proc_maps = false;
    stream.generation = self.next_generation;
    self.next_generation +|= 1;
    stream.eof = false;
    stream.failed = false;
    stream.last_read_offset = -1;
    stream.last_read_size = 0;
    stream.patch_toml = std.mem.endsWith(u8, translated, ".patch.toml");
    stream.patch_toml_eof_logged = false;
    stream.patch_toml_trace_next = 0;
    stream.patch_toml_trace_full = false;
    stream.path_length = @intCast(@min(translated.len, stream.path.len));
    @memcpy(stream.path[0..stream.path_length], translated[0..stream.path_length]);
    if (stream.ios_object != 0) _ = self.object_model.clear(state, stream.ios_object, 0);
    if (mode & OPENMODE_ATE != 0) _ = std.c.lseek(fd, 0, std.c.SEEK.END);
    machoCapturePrint(
        "macho-processor: libc++ filebuf open: {s} mode=0x{x} fd={d} object=0x{x} generation={d}\n",
        .{ translated, mode, fd, object, stream.generation },
    );
    if (stream.patch_toml) self.tracePatchTomlOpen(stream, translated);
    stream.tracked_pos = 0;
    return object;
}

pub fn openProcSelfMaps(self: anytype, state: anytype, object: u64, mode: u64) u64 {
    if (mode & OPENMODE_IN == 0 or mode & OPENMODE_OUT != 0) {
        self.open_failures +|= 1;
        return 0;
    }
    const State = @TypeOf(state.*);
    if (comptime !@hasDecl(State, "renderProcSelfMaps")) {
        self.open_failures +|= 1;
        return 0;
    }
    const stream = self.ensure(object) orelse {
        self.rejected +|= 1;
        return 0;
    };
    closeStream(stream);
    const snapshot = state.renderProcSelfMaps(self.proc_maps_storage[0..]);
    self.proc_maps_length = snapshot.len;
    stream.synthetic_proc_maps = true;
    stream.generation = self.next_generation;
    self.next_generation +|= 1;
    stream.eof = false;
    stream.failed = false;
    stream.last_read_count = 0;
    stream.last_read_offset = -1;
    stream.last_read_size = 0;
    stream.tracked_pos = if (mode & OPENMODE_ATE != 0) snapshot.len else 0;
    stream.patch_toml = false;
    const path = "/proc/self/maps";
    stream.path_length = path.len;
    @memcpy(stream.path[0..path.len], path);
    if (stream.ios_object != 0) _ = self.object_model.clear(state, stream.ios_object, 0);
    machoCapturePrint(
        "macho-processor: libc++ virtual file open: path=/proc/self/maps bytes={d} object=0x{x} generation={d} source=rosette_guest_mappings\n",
        .{ snapshot.len, object, stream.generation },
    );
    return object;
}

pub fn close(self: anytype, state: anytype, object: u64) u64 {
    _ = state;
    self.closes += 1;
    const stream = self.findFlexible(object) orelse return 0;
    if (stream.synthetic_proc_maps) {
        stream.synthetic_proc_maps = false;
        return object;
    }
    if (stream.fd < 0) return 0;
    const result = std.c.close(stream.fd);
    stream.fd = -1;
    return if (result == 0) object else 0;
}

pub fn isOpen(self: anytype, object: u64) bool {
    const stream = self.findFlexible(object) orelse return false;
    return stream.fd >= 0 or stream.synthetic_proc_maps;
}

pub fn seek(self: anytype, object: u64, offset: i64, direction: std.c.whence_t) i64 {
    self.seeks += 1;
    const stream = self.findFlexible(object) orelse return -1;
    if (stream.fd < 0 and !stream.synthetic_proc_maps) return -1;
    const new_pos: i64 = switch (direction) {
        std.c.SEEK.SET => offset,
        std.c.SEEK.CUR => @as(i64, @intCast(stream.tracked_pos)) + offset,
        std.c.SEEK.END => blk: {
            if (stream.synthetic_proc_maps) break :blk @as(i64, @intCast(self.proc_maps_length)) + offset;
            const fsize = std.c.lseek(stream.fd, 0, std.c.SEEK.END);
            if (fsize < 0) break :blk -1;
            break :blk fsize + offset;
        },
        else => -1,
    };
    if (new_pos < 0) return -1;
    stream.tracked_pos = @intCast(new_pos);
    stream.eof = false;
    stream.failed = false;
    const ret: i64 = new_pos;
    self.tracePatchSeek(stream, "seek", offset, direction, ret);
    return ret;
}

pub fn clearEofBitAfterSeek(self: anytype, state: anytype, object: u64, seek_result: i64) void {
    if (seek_result < 0) return;
    const stream = self.findFlexible(object) orelse return;
    if (stream.ios_object != 0) {
        const current = self.object_model.rdstate(state, stream.ios_object);
        _ = self.object_model.clear(state, stream.ios_object, current & ~cxx_object_model.EOFBIT);
    }
}

pub fn syntheticContent(self: anytype, stream: *const Stream) ?[]const u8 {
    if (stream.synthetic_proc_maps) return self.proc_maps_storage[0..self.proc_maps_length];
    if (stream.string_backed) return stream.string_storage[0..stream.string_length];
    return null;
}
