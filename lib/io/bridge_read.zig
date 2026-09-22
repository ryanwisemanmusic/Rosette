const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const cxx_object_model = @import("cxx_abi").cxx_object_model;
const machoCapturePrint = @import("event_log").machoCapturePrint;
const types = @import("bridge_types.zig");
const BASIC_ISTREAM_GCOUNT_OFFSET = types.BASIC_ISTREAM_GCOUNT_OFFSET;
const MAX_REASONABLE_READ_SIZE = types.MAX_REASONABLE_READ_SIZE;
const Stream = types.Stream;
const stream_symbols = @import("libcpp_stream_symbols.zig");
const isDigitForBase = stream_symbols.isDigitForBase;
const isFormattedWhitespace = stream_symbols.isFormattedWhitespace;

pub fn extractUnsignedLong(self: anytype, state: anytype) u64 {
    const istream = state.regs.rdi;
    const dest_ptr = state.regs.rsi;
    const stream = self.findFlexible(istream) orelse return istream;

    var buffer: [64]u8 = undefined;
    var length: usize = 0;
    self.skipFormattedWhitespace(stream);
    while (length < buffer.len) {
        const byte = self.peek(stream.object);
        if (byte < 0 or !isDigitForBase(@intCast(byte), stream.numeric_base)) break;
        buffer[length] = @intCast(self.readByte(stream.object));
        length += 1;
    }
    const text = buffer[0..length];
    const value = std.fmt.parseUnsigned(u64, text, stream.numeric_base) catch {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT);
        return istream;
    };

    if (state.guestMemory(dest_ptr, 8) != null) {
        state.write64(dest_ptr, value);
    }

    return istream;
}

pub fn extractCharacter(self: anytype, state: anytype) u64 {
    const istream = state.regs.rdi;
    const stream = self.findFlexible(istream) orelse return istream;
    self.skipFormattedWhitespace(stream);
    const byte = self.readByte(stream.object);
    if (byte < 0 or state.guestMemory(state.regs.rsi, 1) == null) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.EOFBIT | cxx_object_model.FAILBIT);
        return istream;
    }
    state.write8(state.regs.rsi, @intCast(byte));
    return istream;
}

pub fn extractCharacterArray(self: anytype, state: anytype, capacity: usize) u64 {
    const istream = state.regs.rdi;
    const stream = self.findFlexible(istream) orelse return istream;
    if (capacity < 2 or capacity > 4096) return istream;
    const destination = state.guestMemory(state.regs.rsi, @intCast(capacity)) orelse return istream;
    self.skipFormattedWhitespace(stream);

    var length: usize = 0;
    while (length + 1 < capacity) {
        const byte = self.peek(stream.object);
        if (byte < 0 or isFormattedWhitespace(@intCast(byte))) break;
        destination[length] = @intCast(self.readByte(stream.object));
        length += 1;
    }
    destination[length] = 0;
    if (length == 0) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT);
    }
    return istream;
}

pub fn skipFormattedWhitespace(self: anytype, stream: *Stream) void {
    while (true) {
        const byte = self.peek(stream.object);
        if (byte < 0 or !isFormattedWhitespace(@intCast(byte))) return;
        _ = self.readByte(stream.object);
    }
}

pub fn putBack(self: anytype, object: u64, value: i32) i32 {
    const stream = self.findFlexible(object) orelse return -1;
    if (stream.tracked_pos == 0) return -1;
    stream.tracked_pos -= 1;
    stream.eof = false;
    return if (value < 0) 0 else value & 0xFF;
}

pub fn readLine(self: anytype, state: anytype, object: u64, string_object: u64, delimiter: u8) bool {
    self.reads +|= 1;
    const stream = self.findFlexible(object) orelse {
        self.rejected +|= 1;
        return false;
    };
    if (stream.fd < 0 and !stream.synthetic_proc_maps) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT);
        return false;
    }

    var line: [64 * 1024]u8 = undefined;
    var length: usize = 0;
    if (self.syntheticContent(stream)) |content| {
        while (length < line.len and stream.tracked_pos < content.len) {
            const byte = content[@intCast(stream.tracked_pos)];
            stream.tracked_pos += 1;
            if (byte == delimiter) break;
            line[length] = byte;
            length += 1;
        }
        if (stream.tracked_pos >= content.len) {
            stream.eof = true;
            self.noteState(state, stream, cxx_object_model.EOFBIT);
            if (length == 0) {
                stream.failed = true;
                self.noteState(state, stream, cxx_object_model.FAILBIT);
            }
        }
        return compat_runtime.initLibcppStringFromSlice(state, string_object, line[0..length]);
    }
    while (length < line.len) {
        var byte: [1]u8 = undefined;
        const result = std.c.pread(stream.fd, &byte, 1, @intCast(stream.tracked_pos));
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
        if (byte[0] == delimiter) {
            stream.tracked_pos += 1;
            break;
        }
        line[length] = byte[0];
        length += 1;
        stream.tracked_pos += 1;
    }
    if (length == line.len) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT);
    }
    return compat_runtime.initLibcppStringFromSlice(state, string_object, line[0..length]);
}

pub fn good(self: anytype, object: u64) bool {
    const stream = self.findFlexible(object) orelse return false;
    return !stream.failed;
}

pub fn failed(self: anytype, object: u64) bool {
    const stream = self.findFlexible(object) orelse return true;
    return stream.failed;
}

pub fn eof(self: anytype, object: u64) bool {
    const stream = self.findFlexible(object) orelse return false;
    return stream.eof;
}

pub fn readInto(self: anytype, state: anytype, object: u64, destination: u64, count: u64, set_istream_state: bool) i64 {
    self.reads += 1;
    const stream = self.findFlexible(object) orelse return -1;
    stream.last_read_count = 0;
    if (stream.fd < 0 and !stream.synthetic_proc_maps) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT);
        return -1;
    }
    // Reject wildly oversized reads – they would either OOM the host or
    // corrupt guest heap metadata (toml++'s small buffer_.resize(n) does
    // not guard against a huge n when the string's size field has been
    // corrupted by an adjacent buffer overrun).
    if (count > MAX_REASONABLE_READ_SIZE) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT | cxx_object_model.BADBIT);
        machoCapturePrint("macho-processor: libc++ bridge rejecting unreasonable read: count={d}\n", .{count});
        return -1;
    }
    // Also reject reads that would wrap past the end of guest address space
    if (destination +% count < destination) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.FAILBIT | cxx_object_model.BADBIT);
        return -1;
    }
    const bytes = state.guestMemory(destination, count) orelse {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
        return -1;
    };
    const offset_before = stream.tracked_pos;
    if (self.syntheticContent(stream)) |content| {
        const offset: usize = @min(@as(usize, @intCast(offset_before)), content.len);
        const remaining = content.len - offset;
        const copied = @min(bytes.len, remaining);
        @memcpy(bytes[0..copied], content[offset..][0..copied]);
        stream.last_read_count = @intCast(copied);
        stream.last_read_offset = @intCast(offset_before);
        stream.last_read_size = copied;
        stream.tracked_pos = offset_before +| copied;
        if (copied < count) {
            stream.eof = true;
            if (set_istream_state) stream.failed = true;
            self.noteState(
                state,
                stream,
                cxx_object_model.EOFBIT | if (set_istream_state) cxx_object_model.FAILBIT else 0,
            );
        }
        return @intCast(copied);
    }
    const result = std.c.pread(stream.fd, bytes.ptr, bytes.len, @intCast(offset_before));
    if (result < 0) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
        return -1;
    }
    stream.last_read_count = @intCast(result);
    stream.last_read_offset = @intCast(offset_before);
    stream.last_read_size = @intCast(result);
    stream.tracked_pos = offset_before + @as(u64, @intCast(result));
    self.io_sequence +|= 1;
    stream.last_io_sequence = self.io_sequence;
    // Detect suspicious writes where destination (in_ = buffer_.data()) lands
    // within 1KB of the filebuf/istream object — this indicates buffer_.data()
    // returned a pointer into the ifstream's own memory instead of a heap
    // allocation, which would overwrite string metadata on the next write.
    if (result > 0 and stream.path_length > 0) {
        const prefix = stream.path[0..@min(stream.path_length, @as(usize, 20))];
        if (prefix.len >= 4 and (std.mem.endsWith(u8, prefix, ".patch.toml") or std.mem.endsWith(u8, prefix, ".toml"))) {
            const delta = if (destination > object) destination - object else object - destination;
            if (delta < 1024) {
                machoCapturePrint(
                    "macho-processor: *** SUSPICIOUS write at destination=0x{x} (only {d} bytes from object=0x{x}) " ++ "for stream fd={d} count={d} — buffer_.data() likely corrupted!\n",
                    .{ destination, delta, object, stream.fd, count },
                );
            }
        }
    }
    self.tracePatchRead(stream, "read", @intCast(offset_before), bytes[0..@intCast(result)]);
    // Read ABI details recorded in trace ring buffer via tracePatchRead above.
    // Verbose output suppressed during normal operation.
    if (@as(u64, @intCast(result)) < count) {
        stream.eof = true;
        // toml++ reads fixed-size blocks and uses gcount() to delimit the
        // final block.  Its reader must be allowed to observe a clean EOF
        // and complete the final token; failbit here makes the modeled
        // istream evaluate false before that parser-side EOF handling can
        // run.  Keep standard read() semantics for every other stream.
        const clean_patch_toml_eof = stream.patch_toml and result >= 0;
        if (clean_patch_toml_eof and !stream.patch_toml_eof_logged) {
            stream.patch_toml_eof_logged = true;
            // Print a concise summary instead of the verbose per-read detail.
            machoCapturePrint(
                "macho-processor: patch TOML loaded: {s} bytes={d}\n",
                .{ stream.path[0..stream.path_length], stream.tracked_pos },
            );
        }
        if (set_istream_state and !clean_patch_toml_eof) {
            stream.failed = true;
        }
        self.noteState(
            state,
            stream,
            cxx_object_model.EOFBIT | if (set_istream_state and !clean_patch_toml_eof) cxx_object_model.FAILBIT else 0,
        );
    }
    return @intCast(result);
}

pub fn gcount(self: anytype, object: u64) i64 {
    const stream = self.findFlexible(object) orelse return 0;
    return stream.last_read_count;
}

pub fn mirrorGuestGcount(self: anytype, state: anytype, istream: u64, result: i64) void {
    const stream = self.findFlexible(istream) orelse return;
    const address = istream + BASIC_ISTREAM_GCOUNT_OFFSET;
    if (state.guestMemory(address, 8) == null) {
        stream.failed = true;
        self.rejected +|= 1;
        if (stream.patch_toml) {
            machoCapturePrint(
                "macho-processor: libc++ patch gcount mirror FAILED: istream=0x{x} field=0x{x} generation={d} result={d}\n",
                .{ istream, address, stream.generation, result },
            );
        }
        return;
    }
    _ = state.read64(address); // previous value, consumed by trace only
    const mirrored: u64 = if (result > 0) @intCast(result) else 0;
    state.write64(address, mirrored);
}

pub fn noteState(self: anytype, state: anytype, stream: *const Stream, bits: u32) void {
    if (stream.ios_object != 0) _ = self.object_model.setstate(state, stream.ios_object, bits);
}

pub fn readByte(self: anytype, object: u64) i32 {
    const stream = self.findFlexible(object) orelse return -1;
    if (self.syntheticContent(stream)) |content| {
        if (stream.tracked_pos >= content.len) return -1;
        const byte = content[@intCast(stream.tracked_pos)];
        stream.last_read_offset = @intCast(stream.tracked_pos);
        stream.last_read_size = 1;
        stream.tracked_pos += 1;
        return byte;
    }
    if (stream.fd < 0) return -1;
    var byte: [1]u8 = undefined;
    const offset_before = stream.tracked_pos;
    const result = std.c.pread(stream.fd, &byte, 1, @intCast(offset_before));
    if (result != 1) return -1;
    stream.last_read_offset = @intCast(offset_before);
    stream.last_read_size = 1;
    stream.tracked_pos = offset_before + 1;
    self.tracePatchRead(stream, "read-byte", @intCast(offset_before), byte[0..1]);
    return byte[0];
}

pub fn peek(self: anytype, object: u64) i32 {
    self.peeks += 1;
    const stream = self.findFlexible(object) orelse return -1;
    if (self.syntheticContent(stream)) |content| {
        if (stream.tracked_pos >= content.len) return -1;
        stream.last_read_offset = @intCast(stream.tracked_pos);
        stream.last_read_size = 1;
        return content[@intCast(stream.tracked_pos)];
    }
    if (stream.fd < 0) return -1;
    var byte: [1]u8 = undefined;
    const offset_before = stream.tracked_pos;
    const result = std.c.pread(stream.fd, &byte, 1, @intCast(offset_before));
    if (result != 1) return -1;
    stream.last_read_offset = @intCast(offset_before);
    stream.last_read_size = 1;
    // peek does NOT advance tracked_pos
    self.tracePatchRead(stream, "peek", @intCast(offset_before), byte[0..1]);
    return byte[0];
}

pub fn available(self: anytype, object: u64) i64 {
    const stream = self.findFlexible(object) orelse return -1;
    if (self.syntheticContent(stream)) |content| {
        return if (stream.tracked_pos >= content.len) 0 else @intCast(content.len - @as(usize, @intCast(stream.tracked_pos)));
    }
    if (stream.fd < 0) return -1;
    const end = std.c.lseek(stream.fd, 0, std.c.SEEK.END);
    if (end < 0) return -1;
    const current = stream.tracked_pos;
    return if (@as(u64, @intCast(end)) < current) 0 else @intCast(@as(u64, @intCast(end)) - current);
}
