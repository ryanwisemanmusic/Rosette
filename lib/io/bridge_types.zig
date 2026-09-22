const std = @import("std");
const cxx_object_model = @import("cxx_abi").cxx_object_model;

/// Standard C++ streams constructed on demand when the Mach-O bindings for
/// __ZSt4cin/cout/cerr/clog are resolved. Indexed by `StandardStreamKind`.
pub const StandardStreamKind = enum(u8) {
    cin,
    cout,
    cerr,
    clog,
};

/// One contiguous guest allocation per standard stream: basic_ostream at +0,
/// the synthetic basic_filebuf at +64.
pub const STANDARD_STREAM_BLOCK_SIZE: u64 = 128;
pub const STANDARD_STREAM_FILEBUF_OFFSET: u64 = 64;

pub const MAX_STREAMS = 256; // was 64 — raised for IO-5
pub const PATCH_TOML_TRACE_CAPACITY = 128;
pub const MAX_REASONABLE_READ_SIZE: u64 = 64 * 1024 * 1024; // 64MB safety cap (was 1MB — raised for IO-3)
pub const FILEBUF_OFFSET_IN_IFSTREAM = cxx_object_model.FILEBUF_OFFSET_IN_IFSTREAM;
pub const BASIC_IOS_OFFSET_IN_IFSTREAM = cxx_object_model.BASIC_IOS_OFFSET_IN_IFSTREAM;
pub const FILEBUF_OFFSET_IN_OFSTREAM = cxx_object_model.FILEBUF_OFFSET_IN_OFSTREAM;
pub const STRINGSTREAM_OSTREAM_OFFSET: u64 = 16;
pub const STRINGSTREAM_BUFFER_OFFSET: u64 = 24;
pub const STRINGSTREAM_IOS_OFFSET: u64 = 128;
pub const STRINGSTREAM_MIN_SIZE: u64 = STRINGSTREAM_IOS_OFFSET + cxx_object_model.stream_layout.size;
pub const STRINGSTREAM_TEXT_CAPACITY: usize = 512;
pub const PROC_SELF_MAPS_CAPACITY: usize = 256 * 1024;

/// libc++ stream layout version — offsets are validated against libc++ 16 (v160006).
/// Update these when targeting a different libc++ version.
pub const LIBCPP_STREAM_LAYOUT_VERSION: u32 = 16;
pub const LIBCPP_STREAM_LAYOUT_NOTE: []const u8 = "libc++ v160006 specific; adjust for libstdc++ or other versions";
pub const OPENMODE_APP: u64 = 1 << 0;
pub const OPENMODE_ATE: u64 = 1 << 1;
pub const OPENMODE_IN: u64 = 1 << 3;
pub const OPENMODE_OUT: u64 = 1 << 4;
pub const OPENMODE_TRUNC: u64 = 1 << 5;
// libc++ 16 stores basic_istream::__gc_ immediately after the vptr.  Guest
// code may call the locally-linked gcount() body instead of the import stub,
// so modeled read() calls must keep this ABI field synchronized.
pub const BASIC_ISTREAM_GCOUNT_OFFSET = cxx_object_model.BASIC_ISTREAM_GCOUNT_OFFSET;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

pub const Stream = struct {
    active: bool = false,
    /// Canonical basic_streambuf/basic_filebuf subobject used for all I/O.
    object: u64 = 0,
    /// Complete object that owns `object` (for example basic_stringstream).
    owner_object: u64 = 0,
    /// Primary basic_istream/basic_ostream subobject, when distinct.
    stream_object: u64 = 0,
    /// Virtual basic_ios subobject used for state and rdbuf access.
    ios_object: u64 = 0,
    fd: std.c.fd_t = -1,
    buffer: u64 = 0,
    buffer_size: u64 = 0,
    last_read_count: i64 = 0,
    eof: bool = false,
    failed: bool = false,
    last_read_offset: i64 = -1,
    last_read_size: u64 = 0,
    tracked_pos: u64 = 0,
    generation: u64 = 0,
    last_io_sequence: u64 = 0,
    patch_toml: bool = false,
    patch_toml_eof_logged: bool = false,
    patch_toml_schema: PatchTomlSchema = .{},
    patch_toml_trace: [PATCH_TOML_TRACE_CAPACITY]PatchTomlOp = [_]PatchTomlOp{.{}} ** PATCH_TOML_TRACE_CAPACITY,
    patch_toml_trace_next: u16 = 0,
    patch_toml_trace_full: bool = false,
    path_length: u16 = 0,
    path: [512]u8 = [_]u8{0} ** 512,
    string_length: usize = 0,
    string_truncated: bool = false,
    string_storage: [STRINGSTREAM_TEXT_CAPACITY]u8 = [_]u8{0} ** STRINGSTREAM_TEXT_CAPACITY,
    string_backed: bool = false,
    numeric_base: u8 = 10,
    synthetic_proc_maps: bool = false,
    /// Standard streams (std::cin/cout/cerr/clog) map to host fds 0/1/2 and
    /// are never position-tracked or closed by the bridge.
    is_standard: bool = false,
};

pub const PatchTomlOp = struct {
    operation: [12]u8 = [_]u8{0} ** 12,
    op_len: u4 = 0,
    offset: i64 = 0,
    size: u64 = 0,
    content_first: [4]u8 = [_]u8{0} ** 4,
    content_hash: u64 = 0,
    sequence: u64 = 0,
};

pub const PatchTomlSchema = struct {
    bytes: u64 = 0,
    lines: u64 = 0,
    title_name_assignments: u32 = 0,
    title_id_assignments: u32 = 0,
    hash_assignments: u32 = 0,
    patch_array_headers: u32 = 0,
    truncated_lines: u32 = 0,
    complete: bool = false,
};

pub const PatchTomlSchemaScanner = struct {
    schema: PatchTomlSchema = .{},
    prefix: [256]u8 = [_]u8{0} ** 256,
    prefix_length: usize = 0,
    line_truncated: bool = false,

    pub fn feed(self: *PatchTomlSchemaScanner, bytes: []const u8) void {
        self.schema.bytes +|= bytes.len;
        for (bytes) |byte| {
            if (byte == '\n') {
                self.finishLine();
                continue;
            }
            if (self.prefix_length < self.prefix.len) {
                self.prefix[self.prefix_length] = byte;
                self.prefix_length += 1;
            } else {
                self.line_truncated = true;
            }
        }
    }

    pub fn finish(self: *PatchTomlSchemaScanner) PatchTomlSchema {
        if (self.prefix_length != 0 or self.line_truncated) self.finishLine();
        self.schema.complete = true;
        return self.schema;
    }

    fn finishLine(self: *PatchTomlSchemaScanner) void {
        self.schema.lines +|= 1;
        if (self.line_truncated) self.schema.truncated_lines +|= 1;
        const line = std.mem.trim(u8, self.prefix[0..self.prefix_length], " \t\r");
        if (line.len != 0 and line[0] != '#') {
            if (isAssignment(line, "title_name")) self.schema.title_name_assignments +|= 1;
            if (isAssignment(line, "title_id")) self.schema.title_id_assignments +|= 1;
            if (isAssignment(line, "hash")) self.schema.hash_assignments +|= 1;
            if (isExactPatchArrayHeader(line)) self.schema.patch_array_headers +|= 1;
        }
        self.prefix_length = 0;
        self.line_truncated = false;
    }
};

fn isAssignment(line: []const u8, key: []const u8) bool {
    if (!std.mem.startsWith(u8, line, key)) return false;
    const suffix = std.mem.trim(u8, line[key.len..], " \t");
    return suffix.len != 0 and suffix[0] == '=';
}

fn isExactPatchArrayHeader(line: []const u8) bool {
    const marker = "[[patch]]";
    if (!std.mem.startsWith(u8, line, marker)) return false;
    const suffix = std.mem.trim(u8, line[marker.len..], " \t");
    return suffix.len == 0 or suffix[0] == '#';
}

pub const Utf8Invalid = struct {
    offset: u64,
    byte: u8,
    reason: []const u8,
};

pub const Utf8Scanner = struct {
    expected: u3 = 0,
    codepoint: u32 = 0,
    minimum: u32 = 0,
    sequence_start: u64 = 0,

    pub fn feed(self: *Utf8Scanner, byte: u8, offset: u64) ?Utf8Invalid {
        if (self.expected == 0) {
            if (byte < 0x80) return null;
            self.sequence_start = offset;
            if (byte >= 0xC2 and byte <= 0xDF) {
                self.expected = 1;
                self.codepoint = byte & 0x1F;
                self.minimum = 0x80;
                return null;
            }
            if (byte >= 0xE0 and byte <= 0xEF) {
                self.expected = 2;
                self.codepoint = byte & 0x0F;
                self.minimum = 0x800;
                return null;
            }
            if (byte >= 0xF0 and byte <= 0xF4) {
                self.expected = 3;
                self.codepoint = byte & 0x07;
                self.minimum = 0x10000;
                return null;
            }
            return .{ .offset = offset, .byte = byte, .reason = "invalid leading byte" };
        }
        if (byte & 0xC0 != 0x80) {
            self.expected = 0;
            return .{ .offset = offset, .byte = byte, .reason = "expected continuation byte" };
        }
        self.codepoint = (self.codepoint << 6) | (byte & 0x3F);
        self.expected -= 1;
        if (self.expected != 0) return null;
        if (self.codepoint < self.minimum) return .{ .offset = self.sequence_start, .byte = byte, .reason = "overlong sequence" };
        if (self.codepoint >= 0xD800 and self.codepoint <= 0xDFFF) return .{ .offset = self.sequence_start, .byte = byte, .reason = "UTF-16 surrogate" };
        if (self.codepoint > 0x10FFFF) return .{ .offset = self.sequence_start, .byte = byte, .reason = "code point out of range" };
        return null;
    }

    pub fn finish(self: *const Utf8Scanner) ?Utf8Invalid {
        if (self.expected == 0) return null;
        return .{ .offset = self.sequence_start, .byte = 0, .reason = "truncated sequence at end of file" };
    }
};

pub fn closeStream(stream: *Stream) void {
    if (stream.is_standard) {
        // Never close host stdio; also keep the standard flag so a later
        // reuse of the slot cannot be mistaken for a seekable file.
        stream.fd = -1;
        return;
    }
    if (stream.fd >= 0) _ = std.c.close(stream.fd);
    stream.fd = -1;
    stream.synthetic_proc_maps = false;
}
