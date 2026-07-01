const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");

const MAX_STREAMS = 64;
const FILEBUF_OFFSET_IN_IFSTREAM: u64 = 16;
const FILEBUF_OPEN_HANDLE_OFFSET: u64 = 0x78;

const OPENMODE_APP: u64 = 1 << 0;
const OPENMODE_ATE: u64 = 1 << 1;
const OPENMODE_IN: u64 = 1 << 3;
const OPENMODE_OUT: u64 = 1 << 4;
const OPENMODE_TRUNC: u64 = 1 << 5;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

const Stream = struct {
    active: bool = false,
    object: u64 = 0,
    fd: std.c.fd_t = -1,
    buffer: u64 = 0,
    buffer_size: u64 = 0,
};

pub const Bridge = struct {
    streams: [MAX_STREAMS]Stream = [_]Stream{.{}} ** MAX_STREAMS,
    constructors: u64 = 0,
    opens: u64 = 0,
    open_failures: u64 = 0,
    closes: u64 = 0,
    reads: u64 = 0,
    seeks: u64 = 0,
    peeks: u64 = 0,
    buffer_changes: u64 = 0,
    base_destructors: u64 = 0,
    rejected: u64 = 0,

    pub fn deinit(self: *Bridge) void {
        for (&self.streams) |*stream| closeStream(stream);
        self.* = .{};
    }

    pub fn dispatch(self: *Bridge, state: anytype, fs: anytype, symbol: []const u8) ?Outcome {
        const name = normalizeSymbol(symbol);

        if (std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEEC2Ev"))
        {
            return if (self.construct(state, state.regs.rdi)) .handled_void else null;
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1EOS3_")) {
            return if (self.moveConstruct(state, state.regs.rdi, state.regs.rsi)) .handled_void else null;
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE4swapERS3_")) {
            self.swap(state, state.regs.rdi, state.regs.rsi);
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEED1Ev") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED2Ev"))
        {
            self.destroy(state, state.regs.rdi);
            return .handled_void;
        }
        if (isBaseDestructor(name)) {
            self.base_destructors +|= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE4openEPKcj")) {
            return .{ .handled = self.openCString(state, fs, state.regs.rdi, state.regs.rsi, state.regs.rdx) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openEPKcj")) {
            _ = self.openCString(state, fs, state.regs.rdi + FILEBUF_OFFSET_IN_IFSTREAM, state.regs.rsi, state.regs.rdx);
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openERKNS_12basic_stringIcS2_NS_9allocatorIcEEEEj")) {
            const view = compat_runtime.libcppStringView(state, state.regs.rsi) orelse return null;
            return if (self.openPath(state, fs, state.regs.rdi + FILEBUF_OFFSET_IN_IFSTREAM, view.address, view.length, state.regs.rdx) != 0)
                .handled_void
            else
                .handled_void;
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE5closeEv")) {
            return .{ .handled = self.close(state, state.regs.rdi) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4readEPcl")) {
            _ = self.readInto(state, state.regs.rdi, state.regs.rsi, state.regs.rdx);
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6xsgetnEPcl")) {
            return .{ .handled = @bitCast(self.readInto(state, state.regs.rdi, state.regs.rsi, state.regs.rdx)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5tellgEv")) {
            return .{ .handled = @bitCast(self.seek(state.regs.rdi, 0, std.c.SEEK.CUR)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgENS_4fposI11__mbstate_tEE")) {
            _ = self.seek(state.regs.rdi, @bitCast(state.regs.rsi), std.c.SEEK.SET);
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgExNS_8ios_base7seekdirE")) {
            _ = self.seek(state.regs.rdi, @bitCast(state.regs.rsi), seekDirection(state.regs.rdx));
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj")) {
            return .{ .handled = @bitCast(self.seek(state.regs.rdi, @bitCast(state.regs.rsi), seekDirection(state.regs.rdx))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj")) {
            return .{ .handled = @bitCast(self.seek(state.regs.rdi, @bitCast(state.regs.rsi), std.c.SEEK.SET)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4peekEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9underflowEv"))
        {
            return .{ .handled = @bitCast(@as(i64, self.peek(state.regs.rdi))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5uflowEv")) {
            return .{ .handled = @bitCast(@as(i64, self.readByte(state.regs.rdi))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7snextcEv")) {
            const byte = self.readByte(state.regs.rdi);
            if (byte < 0) return .{ .handled = @bitCast(@as(i64, -1)) };
            return .{ .handled = @bitCast(@as(i64, self.peek(state.regs.rdi))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9showmanycEv")) {
            return .{ .handled = @bitCast(self.available(state.regs.rdi)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE4syncEv")) {
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6setbufEPcl")) {
            return .{ .handled = self.setBuffer(state.regs.rdi, state.regs.rsi, state.regs.rdx) };
        }
        return null;
    }

    pub fn handlePubsetbuf(self: *Bridge, object: u64, buffer: u64, size: u64) u64 {
        return self.setBuffer(object, buffer, size);
    }

    pub fn logSummary(self: *const Bridge) void {
        var live: usize = 0;
        for (self.streams) |stream| {
            if (stream.active and stream.fd >= 0) live += 1;
        }
        std.debug.print(
            "macho-processor: libc++ stream bridge: constructors={d} open={d} open_failed={d} close={d} read={d} seek={d} peek={d} buffers={d} base_dtors={d} live={d} rejected={d}\n",
            .{ self.constructors, self.opens, self.open_failures, self.closes, self.reads, self.seeks, self.peeks, self.buffer_changes, self.base_destructors, live, self.rejected },
        );
    }

    fn construct(self: *Bridge, state: anytype, object: u64) bool {
        const bytes = state.guestMemory(object, 128) orelse {
            self.rejected += 1;
            return false;
        };
        @memset(bytes, 0);
        _ = self.ensure(object) orelse {
            self.rejected += 1;
            return false;
        };
        self.constructors += 1;
        return true;
    }

    fn moveConstruct(self: *Bridge, state: anytype, destination: u64, source: u64) bool {
        const source_stream = self.find(source) orelse return false;
        const fd = source_stream.fd;
        const buffer = source_stream.buffer;
        const buffer_size = source_stream.buffer_size;
        source_stream.fd = -1;
        const destination_stream = self.ensure(destination) orelse return false;
        closeStream(destination_stream);
        destination_stream.fd = fd;
        destination_stream.buffer = buffer;
        destination_stream.buffer_size = buffer_size;
        setOpenMarker(state, source, false);
        setOpenMarker(state, destination, fd >= 0);
        self.constructors += 1;
        return true;
    }

    fn swap(self: *Bridge, state: anytype, lhs: u64, rhs: u64) void {
        const left = self.ensure(lhs) orelse return;
        const right = self.ensure(rhs) orelse return;
        std.mem.swap(std.c.fd_t, &left.fd, &right.fd);
        std.mem.swap(u64, &left.buffer, &right.buffer);
        std.mem.swap(u64, &left.buffer_size, &right.buffer_size);
        setOpenMarker(state, lhs, left.fd >= 0);
        setOpenMarker(state, rhs, right.fd >= 0);
    }

    fn destroy(self: *Bridge, state: anytype, object: u64) void {
        const stream = self.find(object) orelse return;
        closeStream(stream);
        setOpenMarker(state, stream.object, false);
        stream.* = .{};
    }

    fn openCString(self: *Bridge, state: anytype, fs: anytype, object: u64, path_address: u64, mode: u64) u64 {
        const path = state.guestCString(path_address, 4096) orelse {
            self.rejected += 1;
            return 0;
        };
        return self.openBytes(state, fs, object, path, mode);
    }

    fn openPath(self: *Bridge, state: anytype, fs: anytype, object: u64, address: u64, length: u64, mode: u64) u64 {
        const path = state.guestMemoryConst(address, length) orelse {
            self.rejected += 1;
            return 0;
        };
        return self.openBytes(state, fs, object, path, mode);
    }

    fn openBytes(self: *Bridge, state: anytype, fs: anytype, object: u64, path: []const u8, mode: u64) u64 {
        self.opens += 1;
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
            setOpenMarker(state, object, false);
            std.debug.print("macho-processor: libc++ filebuf open failed: {s} mode=0x{x}\n", .{ translated, mode });
            return 0;
        }

        const stream = self.ensure(object) orelse {
            _ = std.c.close(fd);
            self.rejected += 1;
            return 0;
        };
        closeStream(stream);
        stream.fd = fd;
        setOpenMarker(state, object, true);
        if (mode & OPENMODE_ATE != 0) _ = std.c.lseek(fd, 0, std.c.SEEK.END);
        std.debug.print("macho-processor: libc++ filebuf open: {s} mode=0x{x} fd={d}\n", .{ translated, mode, fd });
        return object;
    }

    fn close(self: *Bridge, state: anytype, object: u64) u64 {
        self.closes += 1;
        const stream = self.findFlexible(object) orelse return 0;
        if (stream.fd < 0) return 0;
        const result = std.c.close(stream.fd);
        stream.fd = -1;
        setOpenMarker(state, stream.object, false);
        return if (result == 0) object else 0;
    }

    fn readInto(self: *Bridge, state: anytype, object: u64, destination: u64, count: u64) i64 {
        self.reads += 1;
        const stream = self.findFlexible(object) orelse return -1;
        if (stream.fd < 0) return -1;
        const bytes = state.guestMemory(destination, count) orelse return -1;
        const result = std.c.read(stream.fd, bytes.ptr, bytes.len);
        return if (result < 0) -1 else @intCast(result);
    }

    fn seek(self: *Bridge, object: u64, offset: i64, direction: std.c.whence_t) i64 {
        self.seeks += 1;
        const stream = self.findFlexible(object) orelse return -1;
        if (stream.fd < 0) return -1;
        const result = std.c.lseek(stream.fd, offset, direction);
        return if (result < 0) -1 else @intCast(result);
    }

    fn readByte(self: *Bridge, object: u64) i32 {
        const stream = self.findFlexible(object) orelse return -1;
        if (stream.fd < 0) return -1;
        var byte: [1]u8 = undefined;
        const result = std.c.read(stream.fd, &byte, 1);
        if (result != 1) return -1;
        return byte[0];
    }

    fn peek(self: *Bridge, object: u64) i32 {
        self.peeks += 1;
        const stream = self.findFlexible(object) orelse return -1;
        if (stream.fd < 0) return -1;
        var byte: [1]u8 = undefined;
        const result = std.c.read(stream.fd, &byte, 1);
        if (result != 1) return -1;
        if (std.c.lseek(stream.fd, -1, std.c.SEEK.CUR) < 0) return -1;
        return byte[0];
    }

    fn available(self: *Bridge, object: u64) i64 {
        const stream = self.findFlexible(object) orelse return -1;
        if (stream.fd < 0) return -1;
        const current = std.c.lseek(stream.fd, 0, std.c.SEEK.CUR);
        if (current < 0) return -1;
        const end = std.c.lseek(stream.fd, 0, std.c.SEEK.END);
        _ = std.c.lseek(stream.fd, current, std.c.SEEK.SET);
        return if (end < current) 0 else @intCast(end - current);
    }

    fn setBuffer(self: *Bridge, object: u64, buffer: u64, size: u64) u64 {
        const stream = self.ensure(object) orelse {
            self.rejected += 1;
            return 0;
        };
        stream.buffer = buffer;
        stream.buffer_size = size;
        self.buffer_changes += 1;
        return object;
    }

    fn ensure(self: *Bridge, object: u64) ?*Stream {
        if (self.find(object)) |stream| return stream;
        for (&self.streams) |*stream| {
            if (stream.active) continue;
            stream.* = .{ .active = true, .object = object };
            return stream;
        }
        return null;
    }

    fn find(self: *Bridge, object: u64) ?*Stream {
        for (&self.streams) |*stream| {
            if (stream.active and stream.object == object) return stream;
        }
        return null;
    }

    fn findFlexible(self: *Bridge, object: u64) ?*Stream {
        return self.find(object) orelse self.find(object + FILEBUF_OFFSET_IN_IFSTREAM);
    }
};

fn closeStream(stream: *Stream) void {
    if (stream.fd >= 0) _ = std.c.close(stream.fd);
    stream.fd = -1;
}

fn setOpenMarker(state: anytype, object: u64, is_open: bool) void {
    state.write64(object + FILEBUF_OPEN_HANDLE_OFFSET, if (is_open) object else 0);
}

fn normalizeSymbol(symbol: []const u8) []const u8 {
    if (symbol.len != 0 and symbol[0] == '_') return symbol[1..];
    return symbol;
}

fn isBaseDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED1Ev");
}

fn seekDirection(value: u64) std.c.whence_t {
    return switch (value) {
        0 => std.c.SEEK.SET,
        1 => std.c.SEEK.CUR,
        2 => std.c.SEEK.END,
        else => std.c.SEEK.SET,
    };
}

test "stream bridge tracks guest filebuf state without host C++ objects" {
    var bridge = Bridge{};
    defer bridge.deinit();
    const object: u64 = 0x1000;
    try std.testing.expectEqual(object, bridge.handlePubsetbuf(object, 0x2000, 8192));
    try std.testing.expectEqual(@as(u64, 1), bridge.buffer_changes);
    try std.testing.expectEqual(@as(u64, 0x2000), bridge.find(object).?.buffer);
    try std.testing.expectEqual(@as(u64, 8192), bridge.find(object).?.buffer_size);
}

test "stream bridge resolves ifstream base objects to their filebuf" {
    var bridge = Bridge{};
    defer bridge.deinit();
    const ifstream: u64 = 0x3000;
    _ = bridge.ensure(ifstream + FILEBUF_OFFSET_IN_IFSTREAM);
    try std.testing.expect(bridge.findFlexible(ifstream) != null);
}

test "stream bridge handles libc++ base destructor chain" {
    try std.testing.expect(isBaseDestructor(normalizeSymbol("__ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED2Ev")));
    try std.testing.expect(isBaseDestructor(normalizeSymbol("__ZNSt3__19basic_iosIcNS_11char_traitsIcEEED2Ev")));
    try std.testing.expect(!isBaseDestructor(normalizeSymbol("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED2Ev")));
}

test "stream bridge forwards guest file operations through typed host calls" {
    const TestState = struct {
        mem: [512]u8 = [_]u8{0} ** 512,
        regs: struct {
            rdi: u64 = 0,
            rsi: u64 = 0,
            rdx: u64 = 0,
        } = .{},

        pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }

        pub fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }

        pub fn guestCString(self: *const @This(), address: u64, maximum: usize) ?[]const u8 {
            if (address >= self.mem.len) return null;
            const begin: usize = @intCast(address);
            const limit = @min(self.mem.len, begin + maximum);
            const end = std.mem.indexOfScalar(u8, self.mem[begin..limit], 0) orelse return null;
            return self.mem[begin .. begin + end];
        }

        pub fn read64(self: *const @This(), address: u64) u64 {
            return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
        }

        pub fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
        }
    };
    const IdentityFs = struct {
        fn resolveHostPath(_: *@This(), path: []const u8, _: []u8) ?[]const u8 {
            return path;
        }
    };

    var bridge = Bridge{};
    defer bridge.deinit();
    var state = TestState{};
    var fs = IdentityFs{};
    const object: u64 = 32;
    const path_address: u64 = 256;
    @memcpy(state.mem[path_address .. path_address + "/dev/null".len], "/dev/null");

    state.regs.rdi = object;
    try std.testing.expect(bridge.dispatch(&state, &fs, "__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev") != null);
    state.regs = .{ .rdi = object, .rsi = path_address, .rdx = OPENMODE_IN };
    const opened = bridge.dispatch(&state, &fs, "__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE4openEPKcj").?;
    try std.testing.expectEqual(object, opened.handled);
    try std.testing.expectEqual(object, state.read64(object + FILEBUF_OPEN_HANDLE_OFFSET));
    try std.testing.expectEqual(@as(i64, 0), bridge.readInto(&state, object, 400, 16));
    try std.testing.expectEqual(@as(i64, 0), bridge.seek(object, 0, std.c.SEEK.SET));
    try std.testing.expectEqual(object, bridge.close(&state, object));
    try std.testing.expectEqual(@as(u64, 0), state.read64(object + FILEBUF_OPEN_HANDLE_OFFSET));
}
