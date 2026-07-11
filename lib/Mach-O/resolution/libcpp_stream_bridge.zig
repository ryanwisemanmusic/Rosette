const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const cxx_object_model = @import("cxx_object_model.zig");

const MAX_STREAMS = 64;
const FILEBUF_OFFSET_IN_IFSTREAM = cxx_object_model.FILEBUF_OFFSET_IN_IFSTREAM;
const BASIC_IOS_OFFSET_IN_IFSTREAM = cxx_object_model.BASIC_IOS_OFFSET_IN_IFSTREAM;

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
    ios_object: u64 = 0,
    fd: std.c.fd_t = -1,
    buffer: u64 = 0,
    buffer_size: u64 = 0,
    last_read_count: i64 = 0,
    eof: bool = false,
    failed: bool = false,
};

pub const Bridge = struct {
    object_model: cxx_object_model.Model = .{},
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
    ifstream_vtable: u64 = 0,
    filebuf_vtable: u64 = 0,
    basic_ios_vtable: u64 = 0,

    pub fn deinit(self: *Bridge) void {
        for (&self.streams) |*stream| closeStream(stream);
        self.object_model.reset();
        self.* = .{};
    }

    pub fn dispatch(self: *Bridge, state: anytype, fs: anytype, symbol: []const u8) ?Outcome {
        const name = normalizeSymbol(symbol);

        if (isBasicOstreamConstructor(name)) {
            const streambuf = selectStreambufArgument(state);
            return if (self.constructOstream(state, state.regs.rdi, streambuf))
                .{ .handled = state.regs.rdi }
            else
                null;
        }
        if (isBasicOstreamDestructor(name) or isBaseDestructor(name)) {
            self.base_destructors +|= 1;
            return .handled_void;
        }
        if (isStringStreamDestructor(name)) {
            // The complete-object destructor normally loads its hidden VTT
            // from dyld ABI data before entering D2. The modeled base stream
            // owns no host resource here, so destruction is intentionally a
            // no-op rather than dereferencing an unavailable VTT.
            self.base_destructors +|= 1;
            return .handled_void;
        }
        if (isBasicIosInit(name)) {
            return if (self.object_model.initializeBasicIos(state, state.regs.rdi, state.regs.rsi))
                .handled_void
            else
                null;
        }
        if (isBasicIosRdbuf(name)) return .{ .handled = self.object_model.rdbuf(state, state.regs.rdi) };
        if (isBasicIosRdstate(name)) return .{ .handled = self.object_model.rdstate(state, state.regs.rdi) };
        if (isBasicIosClear(name)) {
            return if (self.object_model.clear(state, state.regs.rdi, @truncate(state.regs.rsi))) .handled_void else null;
        }
        if (isBasicIosSetstate(name)) {
            return if (self.object_model.setstate(state, state.regs.rdi, @truncate(state.regs.rsi))) .handled_void else null;
        }
        if (isBasicIosGood(name)) return .{ .handled = @intFromBool(self.object_model.good(state, state.regs.rdi)) };
        if (isBasicIosFail(name)) return .{ .handled = @intFromBool(self.object_model.fail(state, state.regs.rdi)) };
        if (isBasicIosEof(name)) return .{ .handled = @intFromBool(self.object_model.eof(state, state.regs.rdi)) };
        if (isBasicIosBool(name)) return .{ .handled = @intFromBool(!self.object_model.fail(state, state.regs.rdi)) };

        if (isIfstreamDefaultConstructor(name)) {
            return if (self.constructIfstream(state, state.regs.rdi))
                .{ .handled = state.regs.rdi }
            else
                null;
        }
        if (isIfstreamCStringConstructor(name)) {
            if (!self.constructIfstream(state, state.regs.rdi)) return null;
            _ = self.openCString(state, fs, state.regs.rdi + FILEBUF_OFFSET_IN_IFSTREAM, state.regs.rsi, state.regs.rdx);
            return .{ .handled = state.regs.rdi };
        }
        if (isIfstreamDestructor(name)) {
            self.destroyIfstream(state, state.regs.rdi);
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
        if (std.mem.eql(u8, name, "_ZNKSt3__113basic_filebufIcNS_11char_traitsIcEEE7is_openEv")) {
            return .{ .handled = @intFromBool(self.isOpen(state.regs.rdi)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4readEPcl")) {
            _ = self.readInto(state, state.regs.rdi, state.regs.rsi, state.regs.rdx);
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNKSt3__113basic_istreamIcNS_11char_traitsIcEEE6gcountEv")) {
            return .{ .handled = @bitCast(self.gcount(state.regs.rdi)) };
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

    pub fn recognizesSymbol(symbol: []const u8) bool {
        const name = normalizeSymbol(symbol);
        return isBasicOstreamConstructor(name) or
            isBasicOstreamDestructor(name) or
            isStringStreamDestructor(name) or
            isBaseDestructor(name) or
            isBasicIosInit(name) or
            isBasicIosRdbuf(name) or
            isBasicIosRdstate(name) or
            isBasicIosClear(name) or
            isBasicIosSetstate(name) or
            isBasicIosGood(name) or
            isBasicIosFail(name) or
            isBasicIosEof(name) or
            isBasicIosBool(name) or
            isIfstreamDefaultConstructor(name) or
            isIfstreamCStringConstructor(name) or
            isIfstreamDestructor(name) or
            std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE4openEPKcj") or
            std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openEPKcj") or
            std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openERKNS_12basic_stringIcS2_NS_9allocatorIcEEEEj") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE5closeEv") or
            std.mem.eql(u8, name, "_ZNKSt3__113basic_filebufIcNS_11char_traitsIcEEE7is_openEv") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4readEPcl") or
            std.mem.eql(u8, name, "_ZNKSt3__113basic_istreamIcNS_11char_traitsIcEEE6gcountEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6xsgetnEPcl") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5tellgEv") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgENS_4fposI11__mbstate_tEE") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgExNS_8ios_base7seekdirE") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4peekEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9underflowEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5uflowEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7snextcEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9showmanycEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE4syncEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6setbufEPcl");
    }

    pub fn handlePubsetbuf(self: *Bridge, object: u64, buffer: u64, size: u64) u64 {
        return self.setBuffer(object, buffer, size);
    }

    pub fn constructIfstream(self: *Bridge, state: anytype, object: u64) bool {
        if (!self.object_model.initializeIfstream(state, object)) {
            self.rejected +|= 1;
            return false;
        }
        self.ifstream_vtable = state.read64(object);
        self.filebuf_vtable = state.read64(object + FILEBUF_OFFSET_IN_IFSTREAM);
        self.basic_ios_vtable = state.read64(object + BASIC_IOS_OFFSET_IN_IFSTREAM);
        const stream = self.ensure(object + FILEBUF_OFFSET_IN_IFSTREAM) orelse {
            self.rejected +|= 1;
            return false;
        };
        stream.ios_object = object + BASIC_IOS_OFFSET_IN_IFSTREAM;
        self.constructors +|= 1;
        return true;
    }

    pub fn constructOstream(self: *Bridge, state: anytype, object: u64, streambuf: u64) bool {
        if (streambuf == 0 or state.guestMemoryConst(streambuf, 8) == null) {
            self.rejected +|= 1;
            return false;
        }
        if (!self.object_model.initializeStream(state, .basic_ostream, object, streambuf)) {
            self.rejected +|= 1;
            return false;
        }
        self.constructors +|= 1;
        return true;
    }

    pub fn destroyIfstream(self: *Bridge, state: anytype, object: u64) void {
        self.destroy(state, object + FILEBUF_OFFSET_IN_IFSTREAM);
    }

    pub fn readLine(self: *Bridge, state: anytype, object: u64, string_object: u64, delimiter: u8) bool {
        self.reads +|= 1;
        const stream = self.findFlexible(object) orelse {
            self.rejected +|= 1;
            return false;
        };
        if (stream.fd < 0) {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.FAILBIT);
            return false;
        }

        var line: [64 * 1024]u8 = undefined;
        var length: usize = 0;
        while (length < line.len) {
            var byte: [1]u8 = undefined;
            const result = std.c.read(stream.fd, &byte, 1);
            if (result < 0) {
                stream.failed = true;
                self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
                return false;
            }
            if (result == 0) {
                stream.eof = true;
                self.noteState(state, stream, cxx_object_model.EOFBIT);
                if (length == 0) {
                    stream.failed = true;
                    self.noteState(state, stream, cxx_object_model.FAILBIT);
                }
                break;
            }
            if (byte[0] == delimiter) break;
            line[length] = byte[0];
            length += 1;
        }
        if (length == line.len) {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.FAILBIT);
        }
        return compat_runtime.initLibcppStringFromSlice(state, string_object, line[0..length]);
    }

    pub fn good(self: *Bridge, object: u64) bool {
        const stream = self.findFlexible(object) orelse return false;
        return !stream.failed;
    }

    pub fn failed(self: *Bridge, object: u64) bool {
        const stream = self.findFlexible(object) orelse return true;
        return stream.failed;
    }

    pub fn eof(self: *Bridge, object: u64) bool {
        const stream = self.findFlexible(object) orelse return false;
        return stream.eof;
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

    fn destroy(self: *Bridge, state: anytype, object: u64) void {
        _ = state;
        const stream = self.find(object) orelse return;
        closeStream(stream);
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
            if (self.find(object)) |stream| stream.failed = true;
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
        stream.eof = false;
        stream.failed = false;
        if (stream.ios_object != 0) _ = self.object_model.clear(state, stream.ios_object, 0);
        if (mode & OPENMODE_ATE != 0) _ = std.c.lseek(fd, 0, std.c.SEEK.END);
        std.debug.print("macho-processor: libc++ filebuf open: {s} mode=0x{x} fd={d}\n", .{ translated, mode, fd });
        return object;
    }

    fn close(self: *Bridge, state: anytype, object: u64) u64 {
        _ = state;
        self.closes += 1;
        const stream = self.findFlexible(object) orelse return 0;
        if (stream.fd < 0) return 0;
        const result = std.c.close(stream.fd);
        stream.fd = -1;
        return if (result == 0) object else 0;
    }

    fn isOpen(self: *Bridge, object: u64) bool {
        const stream = self.findFlexible(object) orelse return false;
        return stream.fd >= 0;
    }

    fn readInto(self: *Bridge, state: anytype, object: u64, destination: u64, count: u64) i64 {
        self.reads += 1;
        const stream = self.findFlexible(object) orelse return -1;
        stream.last_read_count = 0;
        if (stream.fd < 0) {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.FAILBIT);
            return -1;
        }
        const bytes = state.guestMemory(destination, count) orelse {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
            return -1;
        };
        const result = std.c.read(stream.fd, bytes.ptr, bytes.len);
        if (result < 0) {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
            return -1;
        }
        stream.last_read_count = @intCast(result);
        if (result < bytes.len) {
            @memset(bytes[@intCast(result)..], 0);
        }
        if (@as(u64, @intCast(result)) < count) {
            stream.eof = true;
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.EOFBIT | cxx_object_model.FAILBIT);
        }
        return @intCast(result);
    }

    fn gcount(self: *Bridge, object: u64) i64 {
        const stream = self.findFlexible(object) orelse return 0;
        return stream.last_read_count;
    }

    fn noteState(self: *Bridge, state: anytype, stream: *const Stream, bits: u32) void {
        if (stream.ios_object != 0) _ = self.object_model.setstate(state, stream.ios_object, bits);
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
        if (self.find(object)) |stream| return stream;
        if (self.find(object + FILEBUF_OFFSET_IN_IFSTREAM)) |stream| return stream;
        for (&self.streams) |*stream| {
            if (!stream.active or stream.object < FILEBUF_OFFSET_IN_IFSTREAM) continue;
            const ifstream = stream.object - FILEBUF_OFFSET_IN_IFSTREAM;
            if (object == ifstream or object == ifstream + 424) return stream;
        }
        return null;
    }
};

fn closeStream(stream: *Stream) void {
    if (stream.fd >= 0) _ = std.c.close(stream.fd);
    stream.fd = -1;
}

fn normalizeSymbol(symbol: []const u8) []const u8 {
    if (symbol.len != 0 and symbol[0] == '_') return symbol[1..];
    return symbol;
}

fn selectStreambufArgument(state: anytype) u64 {
    // The libc++ C2 base constructor carries a hidden VTT in RSI and moves the
    // declared streambuf argument to RDX. A tiny RSI (the logger showed 0x8)
    // is never a valid object pointer even in test-backed address spaces.
    if (state.regs.rsi >= 0x1000 and state.guestMemoryConst(state.regs.rsi, 8) != null) return state.regs.rsi;
    if (state.regs.rdx != 0 and state.guestMemoryConst(state.regs.rdx, 8) != null) return state.regs.rdx;
    return 0;
}

fn isBasicOstreamConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEEC2") != null;
}

fn isBasicOstreamDestructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEED1") != null or
        std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEED2") != null;
}

fn isStringStreamDestructor(name: []const u8) bool {
    const family = std.mem.indexOf(u8, name, "basic_ostringstream") != null or
        std.mem.indexOf(u8, name, "basic_istringstream") != null or
        std.mem.indexOf(u8, name, "basic_stringstream") != null;
    return family and (std.mem.indexOf(u8, name, "D1Ev") != null or std.mem.indexOf(u8, name, "D2Ev") != null);
}

fn isBasicIosMethod(name: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_iosIcNS_11char_traitsIcEEE") != null and
        std.mem.indexOf(u8, name, marker) != null;
}

fn isBasicIosInit(name: []const u8) bool {
    return isBasicIosMethod(name, "4initE");
}

fn isBasicIosRdbuf(name: []const u8) bool {
    return isBasicIosMethod(name, "5rdbuf");
}

fn isBasicIosRdstate(name: []const u8) bool {
    return isBasicIosMethod(name, "7rdstate");
}

fn isBasicIosClear(name: []const u8) bool {
    return isBasicIosMethod(name, "5clearE");
}

fn isBasicIosSetstate(name: []const u8) bool {
    return isBasicIosMethod(name, "8setstateE");
}

fn isBasicIosGood(name: []const u8) bool {
    return isBasicIosMethod(name, "4good");
}

fn isBasicIosFail(name: []const u8) bool {
    return isBasicIosMethod(name, "4fail");
}

fn isBasicIosEof(name: []const u8) bool {
    return isBasicIosMethod(name, "3eof");
}

fn isBasicIosBool(name: []const u8) bool {
    return isBasicIosMethod(name, "cvb");
}

fn isBaseDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED1Ev");
}

fn isIfstreamDefaultConstructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC2Ev");
}

fn isIfstreamCStringConstructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1EPKcj") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC2EPKcj");
}

fn isIfstreamDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED2Ev");
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
    try std.testing.expect(isBaseDestructor(normalizeSymbol("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED2Ev")));
}

test "stream bridge recognizes constructor and destructor ABI aliases" {
    try std.testing.expect(isIfstreamDefaultConstructor(normalizeSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1Ev")));
    try std.testing.expect(isIfstreamDefaultConstructor(normalizeSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC2Ev")));
    try std.testing.expect(isIfstreamCStringConstructor(normalizeSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1EPKcj")));
    try std.testing.expect(isIfstreamDestructor(normalizeSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED2Ev")));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__119basic_istringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNKSt3__19basic_iosIcNS_11char_traitsIcEEE7rdstateB7v160006Ev"));
}

test "stream bridge forwards guest file operations through typed host calls" {
    const TestState = struct {
        mem: [1024]u8 = [_]u8{0} ** 1024,
        next_alloc: u64 = 768,
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

        pub fn read32(self: *const @This(), address: u64) u32 {
            return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
        }

        pub fn write8(self: *@This(), address: u64, value: u8) void {
            self.mem[@intCast(address)] = value;
        }

        pub fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
        }

        pub fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
        }

        pub fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
            const aligned = std.mem.alignForward(u64, self.next_alloc, alignment);
            if (aligned + size > self.mem.len) return null;
            self.next_alloc = aligned + size;
            return aligned;
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

    @memset(state.mem[object .. object + 160], 0xa5);
    const guest_layout_before = state.mem[object .. object + 160].*;
    state.regs = .{ .rdi = object, .rsi = path_address, .rdx = OPENMODE_IN };
    const opened = bridge.dispatch(&state, &fs, "__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE4openEPKcj").?;
    try std.testing.expectEqual(object, opened.handled);
    try std.testing.expectEqualSlices(u8, &guest_layout_before, state.mem[object .. object + 160]);
    state.regs = .{ .rdi = object };
    try std.testing.expectEqual(@as(u64, 1), bridge.dispatch(&state, &fs, "__ZNKSt3__113basic_filebufIcNS_11char_traitsIcEEE7is_openEv").?.handled);
    try std.testing.expectEqual(@as(i64, 0), bridge.readInto(&state, object, 400, 16));
    try std.testing.expectEqual(@as(i64, 0), bridge.seek(object, 0, std.c.SEEK.SET));
    try std.testing.expectEqual(object, bridge.close(&state, object));
    try std.testing.expectEqualSlices(u8, &guest_layout_before, state.mem[object .. object + 160]);
    try std.testing.expect(!bridge.isOpen(object));

    var ifstream_bridge = Bridge{};
    defer ifstream_bridge.deinit();
    state = .{};
    const ifstream: u64 = 16;
    const ifstream_path_address: u64 = 544;
    const string_object: u64 = 640;
    @memset(state.mem[ifstream .. ifstream + 512], 0x5a);
    try std.testing.expect(ifstream_bridge.constructIfstream(&state, ifstream));
    try std.testing.expectEqual(ifstream_bridge.ifstream_vtable, state.read64(ifstream));
    try std.testing.expectEqual(ifstream_bridge.filebuf_vtable, state.read64(ifstream + FILEBUF_OFFSET_IN_IFSTREAM));
    try std.testing.expectEqual(ifstream_bridge.basic_ios_vtable, state.read64(ifstream + BASIC_IOS_OFFSET_IN_IFSTREAM));
    try std.testing.expectEqual(BASIC_IOS_OFFSET_IN_IFSTREAM, state.read64(ifstream_bridge.ifstream_vtable - 24));
    try std.testing.expectEqual(@as(u8, 0x5a), state.mem[ifstream + 8]);
    try std.testing.expectEqual(@as(u8, 0x5a), state.mem[ifstream + 24]);
    @memcpy(state.mem[ifstream_path_address .. ifstream_path_address + "/dev/null".len], "/dev/null");
    state.regs = .{ .rdi = ifstream, .rsi = ifstream_path_address, .rdx = OPENMODE_IN };
    try std.testing.expect(ifstream_bridge.dispatch(&state, &fs, "__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openEPKcj") != null);
    try std.testing.expect(ifstream_bridge.readLine(&state, ifstream, string_object, '\n'));
    try std.testing.expect(ifstream_bridge.eof(ifstream));
    try std.testing.expect(ifstream_bridge.failed(ifstream));
    try std.testing.expect(!ifstream_bridge.good(ifstream + 424));
    try std.testing.expectEqual(@as(u64, 0), compat_runtime.libcppStringView(&state, string_object).?.length);

    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1EPKcj"));
    try std.testing.expect(!Bridge.recognizesSymbol("__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev"));

    var ostream_bridge = Bridge{};
    defer ostream_bridge.deinit();
    state = .{};
    const ostream: u64 = 32;
    const streambuf: u64 = 256;
    state.regs = .{ .rdi = ostream, .rsi = 8, .rdx = streambuf };
    try std.testing.expect(ostream_bridge.dispatch(&state, &fs, "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE") != null);
    try std.testing.expect(state.read64(ostream) != 0);
    try std.testing.expectEqual(@as(u64, 0), state.read64(state.read64(ostream) - 24));
    try std.testing.expectEqual(streambuf, ostream_bridge.object_model.rdbuf(&state, ostream));
    state.regs = .{ .rdi = ostream, .rsi = cxx_object_model.FAILBIT };
    try std.testing.expect(ostream_bridge.dispatch(&state, &fs, "__ZNSt3__19basic_iosIcNS_11char_traitsIcEEE8setstateEj") != null);
    state.regs = .{ .rdi = ostream };
    try std.testing.expectEqual(@as(u64, 1), ostream_bridge.dispatch(&state, &fs, "__ZNKSt3__19basic_iosIcNS_11char_traitsIcEEE4failB7v160006Ev").?.handled);
}
