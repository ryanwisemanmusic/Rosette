const std = @import("std");
const cxx_object_model = @import("cxx_abi").cxx_object_model;
const machoCapturePrint = @import("event_log").machoCapturePrint;
const types = @import("bridge_types.zig");
const MAX_REASONABLE_READ_SIZE = types.MAX_REASONABLE_READ_SIZE;
const STRINGSTREAM_TEXT_CAPACITY = types.STRINGSTREAM_TEXT_CAPACITY;
const Stream = types.Stream;
const stream_symbols = @import("libcpp_stream_symbols.zig");
const displayThreadId = stream_symbols.displayThreadId;
const manipulatorAppend = stream_symbols.manipulatorAppend;
const manipulatorNumericBase = stream_symbols.manipulatorNumericBase;

pub fn applyManipulator(self: anytype, state: anytype, ostream: u64, name: []const u8) u64 {
    if (manipulatorAppend(name)) |text| {
        _ = self.appendToOstream(state, ostream, text);
    }
    // flush() is a no-op: modeled writes are unbuffered, so there is no
    // model state to synchronize.
    return ostream;
}

/// operator<<(ostream&, function-pointer) — resolve the manipulator the
/// pointer refers to (import stub or local libc++ copy) and apply it
/// without executing the native body.
pub fn insertManipulatorPointer(self: anytype, state: anytype, ostream: u64, pointer: u64) u64 {
    var resolved: []const u8 = "";
    if (@hasField(@TypeOf(state.*), "metadata")) {
        if (state.metadata.importAtStub(pointer)) |imported| {
            resolved = imported.name;
        } else if (state.metadata.nearestSymbol(pointer)) |symbol| {
            resolved = symbol.name;
        }
    }
    if (manipulatorAppend(resolved)) |text| {
        _ = self.appendToOstream(state, ostream, text);
        return ostream;
    }
    if (manipulatorNumericBase(resolved)) |base| {
        if (self.findOwned(ostream)) |stream| stream.numeric_base = base;
        return ostream;
    }
    // Unknown manipulator: skip the call rather than run native code
    // against the modeled stream.
    return ostream;
}

pub fn insertThreadId(self: anytype, state: anytype, ostream: u64, raw_id: u64) u64 {
    var buffer: [32]u8 = undefined;
    const displayed_id = displayThreadId(raw_id);
    const rendered = std.fmt.bufPrint(&buffer, "{d}", .{displayed_id}) catch return ostream;
    const appended = self.appendToOstream(state, ostream, rendered);
    self.thread_id_insertions +|= 1;
    if (self.thread_id_insertions <= 16 or !appended) {
        machoCapturePrint(
            "scheduler: libc++ thread id insertion #{d}: raw=0x{x} displayed={d} ostream=0x{x} appended={}\n",
            .{ self.thread_id_insertions, raw_id, displayed_id, ostream, appended },
        );
    }
    return ostream;
}

pub fn insertInteger(self: anytype, state: anytype, ostream: u64, value: u64, signed: bool) u64 {
    var buffer: [32]u8 = undefined;
    const rendered = if (signed)
        std.fmt.bufPrint(&buffer, "{d}", .{@as(i64, @bitCast(value))}) catch return ostream
    else
        std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return ostream;
    _ = self.appendToOstream(state, ostream, rendered);
    return ostream;
}

pub fn insertPointer(self: anytype, state: anytype, ostream: u64, value: u64) u64 {
    var buffer: [32]u8 = undefined;
    const rendered = std.fmt.bufPrint(&buffer, "0x{x}", .{value}) catch return ostream;
    _ = self.appendToOstream(state, ostream, rendered);
    return ostream;
}

pub fn insertDouble(self: anytype, state: anytype, ostream: u64, bits: u64) u64 {
    var buffer: [64]u8 = undefined;
    const value: f64 = @bitCast(bits);
    const rendered = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return ostream;
    _ = self.appendToOstream(state, ostream, rendered);
    return ostream;
}

pub fn insertCString(self: anytype, state: anytype, ostream: u64, address: u64) u64 {
    const text = state.guestCString(address, 4096) orelse return ostream;
    _ = self.appendToOstream(state, ostream, text);
    return ostream;
}

pub fn appendToOstream(self: anytype, state: anytype, ostream: u64, text: []const u8) bool {
    const stream = self.streamForOstream(state, ostream) orelse return false;
    return self.writeBytes(state, stream, text) == text.len;
}

pub fn writeFromGuest(self: anytype, state: anytype, object: u64, source: u64, count: u64) i64 {
    if (count == 0) return 0;
    if (count > MAX_REASONABLE_READ_SIZE) {
        self.rejected +|= 1;
        return 0;
    }
    const bytes = state.guestMemoryConst(source, count) orelse {
        self.rejected +|= 1;
        return 0;
    };
    const stream = self.findFlexible(object) orelse {
        self.rejected +|= 1;
        return 0;
    };
    return @intCast(self.writeBytes(state, stream, bytes));
}

pub fn writeBytes(self: anytype, state: anytype, stream: *Stream, bytes: []const u8) usize {
    self.modeled_streambuf_writes +|= 1;
    if (stream.fd >= 0 and stream.is_standard) {
        // Standard streams back pipes, ttys and files, so position-based
        // pwrite() is invalid (ESPIPE). write(2) works everywhere, and the
        // guest log mirror captures the text when the run redirects it.
        const written = self.writeStandardBytes(state, stream, bytes);
        if (written < bytes.len) {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
            self.modeled_streambuf_short_writes +|= 1;
        }
        return written;
    }
    if (stream.fd >= 0) {
        const result = std.c.pwrite(stream.fd, bytes.ptr, bytes.len, @intCast(stream.tracked_pos));
        if (result < 0) {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
            self.modeled_streambuf_short_writes +|= 1;
            return 0;
        }
        const written: usize = @intCast(result);
        stream.tracked_pos +|= @as(u64, @intCast(written));
        if (written < bytes.len) self.modeled_streambuf_short_writes +|= 1;
        return written;
    }

    if (stream.buffer != 0 and stream.tracked_pos < stream.buffer_size) {
        const available_capacity: usize = @intCast(stream.buffer_size - stream.tracked_pos);
        const written = @min(available_capacity, bytes.len);
        const destination = state.guestMemory(
            stream.buffer + stream.tracked_pos,
            @as(u64, @intCast(written)),
        ) orelse {
            stream.failed = true;
            self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
            self.modeled_streambuf_short_writes +|= 1;
            return 0;
        };
        @memcpy(destination, bytes[0..written]);
        stream.tracked_pos +|= @as(u64, @intCast(written));
        if (written < bytes.len) self.modeled_streambuf_short_writes +|= 1;
        return written;
    }

    // A modeled stringstream has a distinct ostream subobject. Filebufs
    // do not, so an unopened filebuf must fail rather than silently
    // becoming an in-memory stream.
    if (stream.stream_object == 0) {
        stream.failed = true;
        self.noteState(state, stream, cxx_object_model.BADBIT | cxx_object_model.FAILBIT);
        self.modeled_streambuf_short_writes +|= 1;
        return 0;
    }
    const remaining_capacity = STRINGSTREAM_TEXT_CAPACITY - stream.string_length;
    const written = @min(remaining_capacity, bytes.len);
    if (written != 0) {
        @memcpy(stream.string_storage[stream.string_length..][0..written], bytes[0..written]);
        stream.string_length += written;
    }
    if (written < bytes.len) {
        stream.string_truncated = true;
        self.modeled_streambuf_short_writes +|= 1;
    }
    return written;
}

pub fn writeStandardBytes(self: anytype, state: anytype, stream: *Stream, bytes: []const u8) usize {
    _ = self;
    var written: usize = 0;
    while (written < bytes.len) {
        const result = std.c.write(stream.fd, bytes.ptr + written, bytes.len - written);
        if (result < 0) break;
        if (result == 0) break;
        written += @intCast(result);
    }
    if (written != 0 and
        @hasField(@TypeOf(state.*), "guest_log_mirror_fd") and
        state.guest_log_mirror_fd >= 0 and
        state.guest_log_mirror_fd != stream.fd)
    {
        _ = std.c.write(state.guest_log_mirror_fd, bytes.ptr, written);
    }
    return written;
}

pub fn writeOne(self: anytype, state: anytype, object: u64, value: i32) i32 {
    // char_traits<char>::eof() is accepted as a successful no-op by
    // overflow; return not_eof(eof), which is zero for this model.
    if (value < 0) return 0;
    const stream = self.findFlexible(object) orelse return -1;
    const byte = [_]u8{@intCast(value & 0xFF)};
    return if (self.writeBytes(state, stream, &byte) == 1) value & 0xFF else -1;
}

pub fn setBuffer(self: anytype, object: u64, buffer: u64, size: u64) u64 {
    const stream = self.ensure(object) orelse {
        self.rejected += 1;
        return 0;
    };
    stream.buffer = buffer;
    stream.buffer_size = size;
    self.buffer_changes += 1;
    return object;
}
