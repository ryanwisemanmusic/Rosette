const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const cxx_object_model = @import("cxx_abi").cxx_object_model;
const machoCapturePrint = @import("event_log").machoCapturePrint;

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
const STANDARD_STREAM_FILEBUF_OFFSET: u64 = 64;

const MAX_STREAMS = 256; // was 64 — raised for IO-5
const PATCH_TOML_TRACE_CAPACITY = 128;
const MAX_REASONABLE_READ_SIZE: u64 = 64 * 1024 * 1024; // 64MB safety cap (was 1MB — raised for IO-3)
const FILEBUF_OFFSET_IN_IFSTREAM = cxx_object_model.FILEBUF_OFFSET_IN_IFSTREAM;
const BASIC_IOS_OFFSET_IN_IFSTREAM = cxx_object_model.BASIC_IOS_OFFSET_IN_IFSTREAM;
const FILEBUF_OFFSET_IN_OFSTREAM = cxx_object_model.FILEBUF_OFFSET_IN_OFSTREAM;
const STRINGSTREAM_OSTREAM_OFFSET: u64 = 16;
const STRINGSTREAM_BUFFER_OFFSET: u64 = 24;
const STRINGSTREAM_IOS_OFFSET: u64 = 128;
const STRINGSTREAM_MIN_SIZE: u64 = STRINGSTREAM_IOS_OFFSET + cxx_object_model.stream_layout.size;
const STRINGSTREAM_TEXT_CAPACITY: usize = 512;
const PROC_SELF_MAPS_CAPACITY: usize = 256 * 1024;

/// libc++ stream layout version — offsets are validated against libc++ 16 (v160006).
/// Update these when targeting a different libc++ version.
const LIBCPP_STREAM_LAYOUT_VERSION: u32 = 16;
const LIBCPP_STREAM_LAYOUT_NOTE: []const u8 = "libc++ v160006 specific; adjust for libstdc++ or other versions";
const CURRENT_THREAD_HANDLE: u64 = 0x7FFF_1000;
const SYNTHETIC_THREAD_BASE: u64 = 0x7FFF_2000;
const IDLE_CALLBACK_HANDLE_BASE: u64 = 0xFFFF_F900_0000_0000;

const OPENMODE_APP: u64 = 1 << 0;
const OPENMODE_ATE: u64 = 1 << 1;
const OPENMODE_IN: u64 = 1 << 3;
const OPENMODE_OUT: u64 = 1 << 4;
const OPENMODE_TRUNC: u64 = 1 << 5;
// libc++ 16 stores basic_istream::__gc_ immediately after the vptr.  Guest
// code may call the locally-linked gcount() body instead of the import stub,
// so modeled read() calls must keep this ABI field synchronized.
const BASIC_ISTREAM_GCOUNT_OFFSET = cxx_object_model.BASIC_ISTREAM_GCOUNT_OFFSET;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

const Stream = struct {
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

const PatchTomlOp = struct {
    operation: [12]u8 = [_]u8{0} ** 12,
    op_len: u4 = 0,
    offset: i64 = 0,
    size: u64 = 0,
    content_first: [4]u8 = [_]u8{0} ** 4,
    content_hash: u64 = 0,
    sequence: u64 = 0,
};

const PatchTomlSchema = struct {
    bytes: u64 = 0,
    lines: u64 = 0,
    title_name_assignments: u32 = 0,
    title_id_assignments: u32 = 0,
    hash_assignments: u32 = 0,
    patch_array_headers: u32 = 0,
    truncated_lines: u32 = 0,
    complete: bool = false,
};

const PatchTomlSchemaScanner = struct {
    schema: PatchTomlSchema = .{},
    prefix: [256]u8 = [_]u8{0} ** 256,
    prefix_length: usize = 0,
    line_truncated: bool = false,

    fn feed(self: *PatchTomlSchemaScanner, bytes: []const u8) void {
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

    fn finish(self: *PatchTomlSchemaScanner) PatchTomlSchema {
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

test "patch TOML schema scanner distinguishes absent patch arrays from nested data arrays" {
    var empty_patch_scanner = PatchTomlSchemaScanner{};
    empty_patch_scanner.feed(
        "title_name = \"Geometry Wars: Evolved\"\n" ++
            "title_id = \"584108FF\"\n" ++
            "hash = []\n",
    );
    const empty_patch = empty_patch_scanner.finish();
    try std.testing.expectEqual(@as(u32, 1), empty_patch.title_name_assignments);
    try std.testing.expectEqual(@as(u32, 1), empty_patch.title_id_assignments);
    try std.testing.expectEqual(@as(u32, 1), empty_patch.hash_assignments);
    try std.testing.expectEqual(@as(u32, 0), empty_patch.patch_array_headers);

    var populated_scanner = PatchTomlSchemaScanner{};
    populated_scanner.feed("[[patch]] # primary\n[[patch.be32]]\n[[patch]]\n");
    const populated = populated_scanner.finish();
    try std.testing.expectEqual(@as(u32, 2), populated.patch_array_headers);

    var bridge = Bridge{};
    var stream = Stream{
        .active = true,
        .patch_toml = true,
        .generation = 7,
        .patch_toml_schema = empty_patch,
    };
    const path = "patches/584108FF.patch.toml";
    stream.path_length = @intCast(path.len);
    @memcpy(stream.path[0..path.len], path);
    bridge.rememberPatchSchema(&stream);
    stream.active = false;
    try std.testing.expect(bridge.latestPatchSchemaHasEmptyPatchSet());
    try std.testing.expectEqual(@as(u64, 7), bridge.last_patch_schema_generation);
    try std.testing.expectEqualStrings(path, bridge.last_patch_path[0..bridge.last_patch_path_length]);
}

const Utf8Invalid = struct {
    offset: u64,
    byte: u8,
    reason: []const u8,
};

const Utf8Scanner = struct {
    expected: u3 = 0,
    codepoint: u32 = 0,
    minimum: u32 = 0,
    sequence_start: u64 = 0,

    fn feed(self: *Utf8Scanner, byte: u8, offset: u64) ?Utf8Invalid {
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

    fn finish(self: *const Utf8Scanner) ?Utf8Invalid {
        if (self.expected == 0) return null;
        return .{ .offset = self.sequence_start, .byte = 0, .reason = "truncated sequence at end of file" };
    }
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
    ofstream_destructors: u64 = 0,
    thread_id_insertions: u64 = 0,
    rdbuf_alias_resolutions: u64 = 0,
    modeled_streambuf_imbues: u64 = 0,
    modeled_streambuf_virtual_calls: u64 = 0,
    modeled_streambuf_writes: u64 = 0,
    modeled_streambuf_short_writes: u64 = 0,
    rejected: u64 = 0,
    next_generation: u64 = 1,
    io_sequence: u64 = 0,
    ifstream_vtable: u64 = 0,
    filebuf_vtable: u64 = 0,
    basic_ios_vtable: u64 = 0,
    last_patch_schema_valid: bool = false,
    last_patch_schema_generation: u64 = 0,
    last_patch_schema: PatchTomlSchema = .{},
    last_patch_path_length: u16 = 0,
    last_patch_path: [512]u8 = [_]u8{0} ** 512,
    proc_maps_length: usize = 0,
    proc_maps_storage: [PROC_SELF_MAPS_CAPACITY]u8 = [_]u8{0} ** PROC_SELF_MAPS_CAPACITY,
    last_logged_stringstream_object: u64 = 0,
    /// Guest addresses of the modeled std::cin/cout/cerr/clog ostream objects,
    /// populated once per kind on first binding and reused by every slot that
    /// references the same stream.
    standard_ostreams: [std.enums.values(StandardStreamKind).len]u64 = [_]u64{0} ** std.enums.values(StandardStreamKind).len,
    standard_stream_bindings: u64 = 0,

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
        if (isBasicIstreamConstructor(name)) {
            const streambuf = selectStreambufArgument(state);
            return if (self.constructBaseStream(state, .basic_istream, state.regs.rdi, streambuf))
                .{ .handled = state.regs.rdi }
            else
                null;
        }
        if (isBasicIostreamConstructor(name)) {
            const streambuf = selectStreambufArgument(state);
            return if (self.constructBaseStream(state, .basic_iostream, state.regs.rdi, streambuf))
                .{ .handled = state.regs.rdi }
            else
                null;
        }
        if (isStringStreamConstructor(name)) {
            var initial_storage: [STRINGSTREAM_TEXT_CAPACITY]u8 = undefined;
            const initial_text = if (isStringStreamTextConstructor(name)) blk: {
                const view = compat_runtime.libcppStringView(state, state.regs.rsi) orelse return null;
                const source = state.guestMemoryConst(view.address, view.length) orelse return null;
                const length = @min(source.len, initial_storage.len);
                @memcpy(initial_storage[0..length], source[0..length]);
                break :blk initial_storage[0..length];
            } else null;
            if (!self.constructStringStream(state, state.regs.rdi)) return null;
            if (initial_text) |text| self.seedStringStream(state.regs.rdi, text);
            return .{ .handled = state.regs.rdi };
        }
        if (isBasicFilebufConstructor(name) or isBasicStreambufConstructor(name)) {
            return if (self.constructFilebuf(state, state.regs.rdi))
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
            // owns no native C++ resource, but its registry entries must still
            // be retired before this stack storage is reused by another
            // object. Otherwise the stack-vtable guard may restore a stale
            // streambuf vptr into the new occupant.
            self.destroy(state, state.regs.rdi);
            self.base_destructors +|= 1;
            return .handled_void;
        }
        if (isBasicIosInit(name)) {
            const ios = state.regs.rdi;
            if (!self.object_model.initializeBasicIos(state, ios, state.regs.rsi)) return null;
            if (@hasDecl(@TypeOf(state.*), "compat")) {
                _ = state.compat.initLocale(state, ios + cxx_object_model.stream_layout.locale_offset, null);
            }
            return .handled_void;
        }
        if (isBasicIosRdbuf(name)) return .{ .handled = self.resolveRdbuf(state, state.regs.rdi) };
        if (isBasicStreambufPubimbue(name) or isBasicStreambufImbue(name)) {
            const stream = self.findOwned(state.regs.rdi) orelse return null;
            // These are only safe to model for the canonical synthetic
            // streambuf. Do not hide a bad `this` alias or intercept native
            // stream buffers that Rosette does not own.
            if (state.regs.rdi != stream.object) return null;
            self.modeled_streambuf_imbues +|= 1;
            return .handled_void;
        }
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
        if (numericBaseForManipulator(name)) |base| {
            const stream = self.findOwned(state.regs.rdi) orelse return null;
            stream.numeric_base = base;
            return .{ .handled = state.regs.rdi };
        }
        if (isThreadIdInsertion(name)) return .{ .handled = self.insertThreadId(state, state.regs.rdi, state.regs.rsi) };
        if (isPointerInsertion(name)) return .{ .handled = self.insertPointer(state, state.regs.rdi, state.regs.rsi) };
        if (isCStringInsertion(name)) return .{ .handled = self.insertCString(state, state.regs.rdi, state.regs.rsi) };
        if (isIntegerInsertion(name)) return .{ .handled = self.insertInteger(state, state.regs.rdi, state.regs.rsi, isSignedIntegerInsertion(name)) };
        if (isDoubleInsertion(name)) return .{ .handled = self.insertDouble(state, state.regs.rdi, state.regs.rsi) };
        if (isOstreamManipulatorInsertion(name)) {
            // operator<<(ostream&, ostream&(*)(ostream&)) and the ios_base
            // variant. The native libc++ bodies tail-call the manipulator with
            // `this` = the ostream; running them natively against a synthetic
            // (or near-null) stream is the near-null casualty vector seen in
            // Xbyak's undefined-label print. Resolve the pointer and apply the
            // effect here instead.
            return .{ .handled = self.insertManipulatorPointer(state, state.regs.rdi, state.regs.rsi) };
        }
        if (isStreamManipulator(name)) {
            // Direct calls to std::endl / std::flush / std::ends.
            return .{ .handled = self.applyManipulator(state, state.regs.rdi, name) };
        }
        if (isStringbufStr(name)) return if (self.stringbufToString(state, state.regs.rsi, state.regs.rdi)) .{ .handled = state.regs.rdi } else null;
        if (isStringStreamStr(name)) return if (self.streamObjectToString(state, state.regs.rsi, state.regs.rdi)) .{ .handled = state.regs.rdi } else null;

        if (isIfstreamDefaultConstructor(name)) {
            if (!self.constructIfstream(state, state.regs.rdi)) return null;
            if (@hasDecl(@TypeOf(state.*), "compat")) {
                _ = state.compat.initLocale(state, state.regs.rdi + BASIC_IOS_OFFSET_IN_IFSTREAM + cxx_object_model.stream_layout.locale_offset, null);
            }
            return .{ .handled = state.regs.rdi };
        }
        if (isIfstreamCStringConstructor(name)) {
            if (!self.constructIfstream(state, state.regs.rdi)) return null;
            if (@hasDecl(@TypeOf(state.*), "compat")) {
                _ = state.compat.initLocale(state, state.regs.rdi + BASIC_IOS_OFFSET_IN_IFSTREAM + cxx_object_model.stream_layout.locale_offset, null);
            }
            _ = self.openCString(state, fs, state.regs.rdi + FILEBUF_OFFSET_IN_IFSTREAM, state.regs.rsi, state.regs.rdx);
            return .{ .handled = state.regs.rdi };
        }
        if (isIfstreamFilesystemPathConstructor(name)) {
            if (!self.constructIfstream(state, state.regs.rdi)) return null;
            if (@hasDecl(@TypeOf(state.*), "compat")) {
                _ = state.compat.initLocale(state, state.regs.rdi + BASIC_IOS_OFFSET_IN_IFSTREAM + cxx_object_model.stream_layout.locale_offset, null);
            }
            const view = compat_runtime.libcppStringView(state, state.regs.rsi) orelse return null;
            _ = self.openPath(state, fs, state.regs.rdi + FILEBUF_OFFSET_IN_IFSTREAM, view.address, view.length, state.regs.rdx);
            return .{ .handled = state.regs.rdi };
        }
        if (isIfstreamDestructor(name)) {
            self.destroyIfstream(state, state.regs.rdi);
            return .handled_void;
        }
        if (isOfstreamDestructor(name)) {
            // ofstream constructors may execute their locally linked libc++
            // body while basic_filebuf operations are modeled here. Its D2
            // body expects a real compiler-emitted VTT and otherwise replaces
            // the synthetic vptr with zero before reading vtable[-3]. Retire
            // the modeled filebuf directly instead.
            const object = state.regs.rdi;
            const filebuf = object + FILEBUF_OFFSET_IN_OFSTREAM;
            const tracked = self.findAny(filebuf) != null;
            self.destroyOfstream(state, object);
            self.ofstream_destructors +|= 1;
            if (self.ofstream_destructors <= 4) {
                machoCapturePrint(
                    "macho-processor: libc++ ofstream destructor modeled: object=0x{x} filebuf=0x{x} tracked={}\n",
                    .{ object, filebuf, tracked },
                );
            }
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
        if (std.mem.eql(u8, name, "_ZNKSt3__113basic_filebufIcNS_11char_traitsIcEEE7is_openEv")) {
            return .{ .handled = @intFromBool(self.isOpen(state.regs.rdi)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4readEPcl")) {
            const istream = state.regs.rdi;
            const result = self.readInto(state, istream, state.regs.rsi, state.regs.rdx, true);
            self.mirrorGuestGcount(state, istream, result);
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNKSt3__113basic_istreamIcNS_11char_traitsIcEEE6gcountEv")) {
            const result = self.gcount(state.regs.rdi);
            // gcount import recorded in trace ring buffer.
            // Verbose output suppressed during normal operation.
            return .{ .handled = @bitCast(result) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6xsgetnEPcl")) {
            // xsgetn is the low-level stream-buffer primitive.  A short read
            // is its normal EOF signal; only basic_istream::read is allowed
            // to translate that result into failbit.
            return .{ .handled = @bitCast(self.readInto(state, state.regs.rdi, state.regs.rsi, state.regs.rdx, false)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6xsputnEPKcl")) {
            return .{ .handled = @bitCast(self.writeFromGuest(state, state.regs.rdi, state.regs.rsi, state.regs.rdx)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5tellgEv")) {
            return .{ .handled = @bitCast(self.seek(state.regs.rdi, 0, std.c.SEEK.CUR)) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgENS_4fposI11__mbstate_tEE")) {
            const seek_result = self.seek(state.regs.rdi, @bitCast(state.regs.rsi), std.c.SEEK.SET);
            self.clearEofBitAfterSeek(state, state.regs.rdi, seek_result);
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgExNS_8ios_base7seekdirE")) {
            const seek_result = self.seek(state.regs.rdi, @bitCast(state.regs.rsi), seekDirection(state.regs.rdx));
            self.clearEofBitAfterSeek(state, state.regs.rdi, seek_result);
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj")) {
            const seek_result = self.seek(state.regs.rdi, @bitCast(state.regs.rsi), seekDirection(state.regs.rdx));
            self.clearEofBitAfterSeek(state, state.regs.rdi, seek_result);
            return .{ .handled = @bitCast(seek_result) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj")) {
            const seek_result = self.seek(state.regs.rdi, @bitCast(state.regs.rsi), std.c.SEEK.SET);
            self.clearEofBitAfterSeek(state, state.regs.rdi, seek_result);
            return .{ .handled = @bitCast(seek_result) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4peekEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9underflowEv"))
        {
            return .{ .handled = @bitCast(@as(i64, self.peek(state.regs.rdi))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5uflowEv")) {
            return .{ .handled = @bitCast(@as(i64, self.readByte(state.regs.rdi))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9pbackfailEi")) {
            const value: i32 = @bitCast(@as(u32, @truncate(state.regs.rsi)));
            return .{ .handled = @bitCast(@as(i64, self.putBack(state.regs.rdi, value))) };
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
        if (std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE8overflowEi")) {
            const value: i32 = @bitCast(@as(u32, @truncate(state.regs.rsi)));
            return .{ .handled = @bitCast(@as(i64, self.writeOne(state, state.regs.rdi, value))) };
        }
        if (std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEErsERm")) {
            return .{ .handled = self.extractUnsignedLong(state) };
        }
        if (isCharacterReferenceExtraction(name)) {
            return .{ .handled = self.extractCharacter(state) };
        }
        if (characterArrayCapacity(name)) |capacity| {
            return .{ .handled = self.extractCharacterArray(state, capacity) };
        }
        return null;
    }

    pub fn recognizesSymbol(symbol: []const u8) bool {
        const name = normalizeSymbol(symbol);
        return isBasicOstreamConstructor(name) or
            isBasicIstreamConstructor(name) or
            isBasicIostreamConstructor(name) or
            isStringStreamConstructor(name) or
            isBasicFilebufConstructor(name) or
            isBasicStreambufConstructor(name) or
            isBasicOstreamDestructor(name) or
            isStringStreamDestructor(name) or
            isBaseDestructor(name) or
            isBasicIosInit(name) or
            isBasicIosRdbuf(name) or
            isBasicStreambufPubimbue(name) or
            isBasicStreambufImbue(name) or
            isBasicIosRdstate(name) or
            isBasicIosClear(name) or
            isBasicIosSetstate(name) or
            isBasicIosGood(name) or
            isBasicIosFail(name) or
            isBasicIosEof(name) or
            isBasicIosBool(name) or
            numericBaseForManipulator(name) != null or
            isThreadIdInsertion(name) or
            isPointerInsertion(name) or
            isCStringInsertion(name) or
            isIntegerInsertion(name) or
            isDoubleInsertion(name) or
            isOstreamManipulatorInsertion(name) or
            isStreamManipulator(name) or
            isStringbufStr(name) or
            isStringStreamStr(name) or
            isIfstreamDefaultConstructor(name) or
            isIfstreamCStringConstructor(name) or
            isIfstreamFilesystemPathConstructor(name) or
            isIfstreamDestructor(name) or
            isOfstreamDestructor(name) or
            std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE4openEPKcj") or
            std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openEPKcj") or
            std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEE4openERKNS_12basic_stringIcS2_NS_9allocatorIcEEEEj") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEE5closeEv") or
            std.mem.eql(u8, name, "_ZNKSt3__113basic_filebufIcNS_11char_traitsIcEEE7is_openEv") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4readEPcl") or
            std.mem.eql(u8, name, "_ZNKSt3__113basic_istreamIcNS_11char_traitsIcEEE6gcountEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6xsgetnEPcl") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6xsputnEPKcl") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5tellgEv") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgENS_4fposI11__mbstate_tEE") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE5seekgExNS_8ios_base7seekdirE") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekoffExNS_8ios_base7seekdirEj") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7seekposENS_4fposI11__mbstate_tEEj") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE4peekEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9underflowEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5uflowEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9pbackfailEi") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE7snextcEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9showmanycEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE4syncEv") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE6setbufEPcl") or
            std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE8overflowEi") or
            std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEErsERm") or
            isCharacterReferenceExtraction(name) or
            characterArrayCapacity(name) != null;
    }

    pub fn handlePubsetbuf(self: *Bridge, object: u64, buffer: u64, size: u64) u64 {
        return self.setBuffer(object, buffer, size);
    }

    /// Executes a typed virtual from Rosette's synthetic basic_streambuf
    /// vtable. The vtable owns only addresses; all stream state and I/O remain
    /// centralized here so direct imports and virtual calls cannot diverge.
    pub fn dispatchStreambufVirtual(
        self: *Bridge,
        state: anytype,
        thunk: compat_runtime.SyntheticThunk,
        object: u64,
        argument_1: u64,
        argument_2: u64,
    ) u64 {
        self.modeled_streambuf_virtual_calls +|= 1;
        return switch (thunk) {
            .streambuf_setbuf => self.setBuffer(object, argument_1, argument_2),
            .streambuf_seekoff => blk: {
                const result = self.seek(object, @bitCast(argument_1), seekDirection(argument_2));
                self.clearEofBitAfterSeek(state, object, result);
                break :blk @bitCast(result);
            },
            .streambuf_seekpos => blk: {
                const result = self.seek(object, @bitCast(argument_1), std.c.SEEK.SET);
                self.clearEofBitAfterSeek(state, object, result);
                break :blk @bitCast(result);
            },
            .streambuf_sync => 0,
            .streambuf_showmanyc => @bitCast(self.available(object)),
            .streambuf_xsgetn => @bitCast(self.readInto(state, object, argument_1, argument_2, false)),
            .streambuf_underflow => @bitCast(@as(i64, self.peek(object))),
            .streambuf_uflow => @bitCast(@as(i64, self.readByte(object))),
            .streambuf_pbackfail => blk: {
                const value: i32 = @bitCast(@as(u32, @truncate(argument_1)));
                break :blk @bitCast(@as(i64, self.putBack(object, value)));
            },
            .streambuf_xsputn => @bitCast(self.writeFromGuest(state, object, argument_1, argument_2)),
            .streambuf_overflow => blk: {
                const value: i32 = @bitCast(@as(u32, @truncate(argument_1)));
                break :blk @bitCast(@as(i64, self.writeOne(state, object, value)));
            },
            else => 0,
        };
    }

    pub fn constructIfstream(self: *Bridge, state: anytype, object: u64) bool {
        if (!self.object_model.initializeIfstream(state, object)) {
            self.rejected +|= 1;
            return false;
        }
        if (!self.installStreambufVirtuals(state, .basic_filebuf)) {
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
        self.setOwnership(stream, object, object, object + BASIC_IOS_OFFSET_IN_IFSTREAM);
        stream.ios_object = object + BASIC_IOS_OFFSET_IN_IFSTREAM;
        registerStackVtable(state, object + FILEBUF_OFFSET_IN_IFSTREAM);
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
        if (@hasDecl(@TypeOf(state.*), "compat")) {
            _ = state.compat.initLocale(state, object + cxx_object_model.stream_layout.locale_offset, null);
        }
        self.constructors +|= 1;
        return true;
    }

    /// Return the guest ostream address for a standard C++ stream, constructing
    /// it once per kind. The object is fully modeled (ostream vptr, rdbuf,
    /// locale, synthetic streambuf virtuals) so both dispatch routes are safe:
    /// imports intercepted by the bridge, and native libc++ template copies
    /// that run against the object (e.g. std::endl calling widen()/put()/flush()
    /// through the synthetic locale and streambuf vtables).
    pub fn ensureStandardStream(self: *Bridge, state: anytype, kind: StandardStreamKind) ?u64 {
        const index = @intFromEnum(kind);
        if (self.standard_ostreams[index] != 0) return self.standard_ostreams[index];
        const fd: i32 = switch (kind) {
            .cin => 0,
            .cout => 1,
            .cerr, .clog => 2,
        };
        const ostream = self.constructStandardStream(state, fd) orelse return null;
        self.standard_ostreams[index] = ostream;
        if (self.standard_stream_bindings < 4) {
            machoCapturePrint(
                "macho-processor: modeled standard C++ stream kind={s} fd={d} ostream=0x{x} filebuf=0x{x}\n",
                .{ @tagName(kind), fd, ostream, ostream + STANDARD_STREAM_FILEBUF_OFFSET },
            );
        }
        return ostream;
    }

    fn constructStandardStream(self: *Bridge, state: anytype, fd: i32) ?u64 {
        if (fd < 0 or fd > 2) return null;
        const block = state.guestAlloc(STANDARD_STREAM_BLOCK_SIZE, 16) orelse return null;
        const filebuf = block + STANDARD_STREAM_FILEBUF_OFFSET;
        if (!self.constructFilebuf(state, filebuf)) return null;
        if (!self.constructOstream(state, block, filebuf)) return null;
        const stream = self.ensure(filebuf) orelse return null;
        self.setOwnership(stream, block, 0, 0);
        stream.fd = fd;
        stream.is_standard = true;
        stream.tracked_pos = 0;
        return block;
    }

    /// Direct std::endl / std::flush / std::ends import.
    pub fn applyManipulator(self: *Bridge, state: anytype, ostream: u64, name: []const u8) u64 {
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
    pub fn insertManipulatorPointer(self: *Bridge, state: anytype, ostream: u64, pointer: u64) u64 {
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

    pub fn constructFilebuf(self: *Bridge, state: anytype, object: u64) bool {
        if (!self.object_model.initializeStreambufBase(state, object)) {
            self.rejected +|= 1;
            return false;
        }
        if (!self.installStreambufVirtuals(state, .basic_streambuf)) {
            self.rejected +|= 1;
            return false;
        }
        const stream = self.ensure(object) orelse {
            self.rejected +|= 1;
            return false;
        };
        self.setOwnership(stream, object, 0, 0);
        closeStream(stream);
        stream.fd = -1;
        stream.buffer = 0;
        stream.buffer_size = 0;
        stream.last_read_count = 0;
        stream.eof = false;
        stream.failed = false;
        stream.string_backed = false;
        stream.numeric_base = 10;
        stream.patch_toml_trace_next = 0;
        stream.patch_toml_trace_full = false;
        self.resetStringBuffer(stream);
        registerStackVtable(state, object);
        self.constructors +|= 1;
        return true;
    }

    pub fn stringbufToString(self: *Bridge, state: anytype, stringbuf: u64, output: u64) bool {
        const stream = self.findFlexible(stringbuf) orelse return false;
        return compat_runtime.initLibcppStringFromSlice(state, output, stream.string_storage[0..stream.string_length]);
    }

    pub fn streamObjectToString(self: *Bridge, state: anytype, object: u64, output: u64) bool {
        const stream = self.streamForOstream(state, object) orelse return false;
        return compat_runtime.initLibcppStringFromSlice(state, output, stream.string_storage[0..stream.string_length]);
    }

    fn insertThreadId(self: *Bridge, state: anytype, ostream: u64, raw_id: u64) u64 {
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

    fn insertInteger(self: *Bridge, state: anytype, ostream: u64, value: u64, signed: bool) u64 {
        var buffer: [32]u8 = undefined;
        const rendered = if (signed)
            std.fmt.bufPrint(&buffer, "{d}", .{@as(i64, @bitCast(value))}) catch return ostream
        else
            std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return ostream;
        _ = self.appendToOstream(state, ostream, rendered);
        return ostream;
    }

    fn insertPointer(self: *Bridge, state: anytype, ostream: u64, value: u64) u64 {
        var buffer: [32]u8 = undefined;
        const rendered = std.fmt.bufPrint(&buffer, "0x{x}", .{value}) catch return ostream;
        _ = self.appendToOstream(state, ostream, rendered);
        return ostream;
    }

    fn insertDouble(self: *Bridge, state: anytype, ostream: u64, bits: u64) u64 {
        var buffer: [64]u8 = undefined;
        const value: f64 = @bitCast(bits);
        const rendered = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return ostream;
        _ = self.appendToOstream(state, ostream, rendered);
        return ostream;
    }

    fn insertCString(self: *Bridge, state: anytype, ostream: u64, address: u64) u64 {
        const text = state.guestCString(address, 4096) orelse return ostream;
        _ = self.appendToOstream(state, ostream, text);
        return ostream;
    }

    fn extractUnsignedLong(self: *Bridge, state: anytype) u64 {
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

    fn extractCharacter(self: *Bridge, state: anytype) u64 {
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

    fn extractCharacterArray(self: *Bridge, state: anytype, capacity: usize) u64 {
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

    fn skipFormattedWhitespace(self: *Bridge, stream: *Stream) void {
        while (true) {
            const byte = self.peek(stream.object);
            if (byte < 0 or !isFormattedWhitespace(@intCast(byte))) return;
            _ = self.readByte(stream.object);
        }
    }

    fn appendToOstream(self: *Bridge, state: anytype, ostream: u64, text: []const u8) bool {
        const stream = self.streamForOstream(state, ostream) orelse return false;
        return self.writeBytes(state, stream, text) == text.len;
    }

    fn writeFromGuest(self: *Bridge, state: anytype, object: u64, source: u64, count: u64) i64 {
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

    fn writeBytes(self: *Bridge, state: anytype, stream: *Stream, bytes: []const u8) usize {
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

    fn writeStandardBytes(self: *Bridge, state: anytype, stream: *Stream, bytes: []const u8) usize {
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

    fn writeOne(self: *Bridge, state: anytype, object: u64, value: i32) i32 {
        // char_traits<char>::eof() is accepted as a successful no-op by
        // overflow; return not_eof(eof), which is zero for this model.
        if (value < 0) return 0;
        const stream = self.findFlexible(object) orelse return -1;
        const byte = [_]u8{@intCast(value & 0xFF)};
        return if (self.writeBytes(state, stream, &byte) == 1) value & 0xFF else -1;
    }

    fn putBack(self: *Bridge, object: u64, value: i32) i32 {
        const stream = self.findFlexible(object) orelse return -1;
        if (stream.tracked_pos == 0) return -1;
        stream.tracked_pos -= 1;
        stream.eof = false;
        return if (value < 0) 0 else value & 0xFF;
    }

    fn streamForOstream(self: *Bridge, state: anytype, object: u64) ?*Stream {
        if (self.findOwned(object)) |stream| return stream;
        if (state.guestMemoryConst(object + cxx_object_model.stream_layout.rdbuf_offset, 8) != null) {
            const streambuf = self.resolveRdbuf(state, object);
            if (streambuf != 0) {
                if (self.findFlexible(streambuf)) |stream| return stream;
            }
        }
        if (object >= STRINGSTREAM_OSTREAM_OFFSET) {
            const container = object - STRINGSTREAM_OSTREAM_OFFSET;
            if (self.find(container + STRINGSTREAM_BUFFER_OFFSET)) |stream| return stream;
        }
        if (self.find(object + STRINGSTREAM_BUFFER_OFFSET)) |stream| return stream;
        return self.findFlexible(object);
    }

    fn resetStringBuffer(_: *Bridge, stream: *Stream) void {
        stream.string_length = 0;
        stream.string_truncated = false;
        @memset(&stream.string_storage, 0);
    }

    fn constructBaseStream(self: *Bridge, state: anytype, kind: cxx_object_model.Kind, object: u64, streambuf: u64) bool {
        if (streambuf == 0 or state.guestMemoryConst(streambuf, 8) == null) {
            self.rejected +|= 1;
            return false;
        }
        if (!self.object_model.initializeStreamBase(state, kind, object)) {
            self.rejected +|= 1;
            return false;
        }
        self.constructors +|= 1;
        return true;
    }

    fn constructStringStream(self: *Bridge, state: anytype, object: u64) bool {
        if (state.guestMemory(object, STRINGSTREAM_MIN_SIZE) == null) {
            self.rejected +|= 1;
            return false;
        }
        const streambuf = object + STRINGSTREAM_BUFFER_OFFSET;
        if (!self.object_model.initializeStreambufBase(state, streambuf) or
            !self.object_model.initializeStreamBase(state, .basic_iostream, object) or
            !self.object_model.initializeStreamBase(state, .basic_ostream, object + STRINGSTREAM_OSTREAM_OFFSET) or
            !self.object_model.initializeBasicIos(state, object + STRINGSTREAM_IOS_OFFSET, streambuf))
        {
            self.rejected +|= 1;
            return false;
        }
        if (!self.installStreambufVirtuals(state, .basic_streambuf)) {
            self.rejected +|= 1;
            return false;
        }
        if (@hasDecl(@TypeOf(state.*), "compat")) {
            _ = state.compat.initLocale(state, object + STRINGSTREAM_IOS_OFFSET + cxx_object_model.stream_layout.locale_offset, null);
        }
        const stream = self.ensure(streambuf) orelse {
            self.rejected +|= 1;
            return false;
        };
        self.setOwnership(
            stream,
            object,
            object + STRINGSTREAM_OSTREAM_OFFSET,
            object + STRINGSTREAM_IOS_OFFSET,
        );
        self.resetStringBuffer(stream);
        stream.string_backed = true;
        stream.numeric_base = 10;
        stream.tracked_pos = 0;
        registerStackVtable(state, streambuf);
        if (object != self.last_logged_stringstream_object) {
            self.last_logged_stringstream_object = object;
            self.constructors +|= 1;
            machoCapturePrint(
                "macho-processor: modeled libc++ stringstream object=0x{x} ostream=0x{x} streambuf=0x{x} ios=0x{x}\n",
                .{ object, object + STRINGSTREAM_OSTREAM_OFFSET, streambuf, object + STRINGSTREAM_IOS_OFFSET },
            );
        }
        return true;
    }

    fn seedStringStream(self: *Bridge, object: u64, text: []const u8) void {
        const stream = self.find(object + STRINGSTREAM_BUFFER_OFFSET) orelse return;
        self.resetStringBuffer(stream);
        stream.string_backed = true;
        const copy_length = @min(text.len, stream.string_storage.len);
        @memcpy(stream.string_storage[0..copy_length], text[0..copy_length]);
        stream.string_length = copy_length;
        stream.string_truncated = text.len > copy_length;
        stream.tracked_pos = 0;
        stream.eof = false;
        stream.failed = false;
    }

    fn installStreambufVirtuals(self: *Bridge, state: anytype, kind: cxx_object_model.Kind) bool {
        // libc++ v160006 basic_streambuf virtual surface. Slots 0 and 1 are
        // destructor variants, which remain on the bridge's typed direct
        // destructor path. Every operational slot is populated up front so a
        // locally linked wrapper (sputn, pubseekoff, sgetc, and friends)
        // cannot branch through a null synthetic vtable entry.
        const slots = [_]struct {
            index: usize,
            thunk: compat_runtime.SyntheticThunk,
        }{
            .{ .index = 2, .thunk = .streambuf_imbue },
            .{ .index = 3, .thunk = .streambuf_setbuf },
            .{ .index = 4, .thunk = .streambuf_seekoff },
            .{ .index = 5, .thunk = .streambuf_seekpos },
            .{ .index = 6, .thunk = .streambuf_sync },
            .{ .index = 7, .thunk = .streambuf_showmanyc },
            .{ .index = 8, .thunk = .streambuf_xsgetn },
            .{ .index = 9, .thunk = .streambuf_underflow },
            .{ .index = 10, .thunk = .streambuf_uflow },
            .{ .index = 11, .thunk = .streambuf_pbackfail },
            .{ .index = 12, .thunk = .streambuf_xsputn },
            .{ .index = 13, .thunk = .streambuf_overflow },
        };
        for (slots) |slot| {
            if (!self.object_model.setVirtualSlot(
                state,
                kind,
                slot.index,
                compat_runtime.thunkAddress(slot.thunk),
            )) return false;
        }
        return true;
    }

    pub fn destroyIfstream(self: *Bridge, state: anytype, object: u64) void {
        self.destroy(state, object + FILEBUF_OFFSET_IN_IFSTREAM);
    }

    pub fn destroyOfstream(self: *Bridge, state: anytype, object: u64) void {
        self.destroy(state, object + FILEBUF_OFFSET_IN_OFSTREAM);
    }

    /// Register a streambuf's vtable with the stack vtable registry so that
    /// corruption (e.g. heap reuse overwriting the vptr) can be recovered.
    /// Uses an anonymous struct literal for provenance to avoid importing
    /// vtable types (io module doesn't include vtable in its dep tree).
    fn registerStackVtable(state: anytype, address: u64) void {
        if (comptime !@hasField(@TypeOf(state.*), "vtable_stack_registry")) return;
        const vptr = state.read64(address);
        state.vtable_stack_registry.register(address, vptr, .{
            .writer_rip = if (@hasField(@TypeOf(state.*), "regs")) state.regs.rip else 0,
            .writer_step = if (@hasField(@TypeOf(state.*), "regs")) state.executed_steps else 0,
            .writer_thread = if (@hasField(@TypeOf(state.*), "regs")) state.active_guest_thread else 0,
        });
    }

    /// Forget a streambuf's vtable entry when the stream is destroyed.
    fn forgetStackVtable(state: anytype, address: u64) void {
        if (comptime !@hasField(@TypeOf(state.*), "vtable_stack_registry")) return;
        state.vtable_stack_registry.forget(address);
    }

    pub fn readLine(self: *Bridge, state: anytype, object: u64, string_object: u64, delimiter: u8) bool {
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
            if (stream.active and (stream.fd >= 0 or stream.synthetic_proc_maps)) live += 1;
        }
        machoCapturePrint(
            "macho-processor: libc++ stream bridge: constructors={d} open={d} open_failed={d} close={d} read={d} seek={d} peek={d} buffers={d} base_dtors={d} ofstream_dtors={d} rdbuf_aliases={d} modeled_imbues={d} virtual_calls={d} writes={d} short_writes={d} live={d} rejected={d}\n",
            .{ self.constructors, self.opens, self.open_failures, self.closes, self.reads, self.seeks, self.peeks, self.buffer_changes, self.base_destructors, self.ofstream_destructors, self.rdbuf_alias_resolutions, self.modeled_streambuf_imbues, self.modeled_streambuf_virtual_calls, self.modeled_streambuf_writes, self.modeled_streambuf_short_writes, live, self.rejected },
        );
    }

    fn destroy(self: *Bridge, state: anytype, object: u64) void {
        const stream = self.findAny(object) orelse {
            // Preserve support for callers that already pass the canonical
            // streambuf address even if its Bridge entry was retired first.
            forgetStackVtable(state, object);
            return;
        };
        // `object` may be the complete stringstream, ostream, or basic_ios
        // alias. The stack-vtable registry is keyed by the canonical
        // streambuf subobject.
        forgetStackVtable(state, stream.object);
        closeStream(stream);
        stream.active = false;
        stream.fd = -1;
        stream.owner_object = 0;
        stream.stream_object = 0;
        stream.ios_object = 0;
        stream.buffer = 0;
        stream.buffer_size = 0;
        stream.last_read_count = 0;
        stream.eof = false;
        stream.failed = false;
        stream.last_read_offset = -1;
        stream.last_read_size = 0;
        stream.tracked_pos = 0;
        stream.patch_toml = false;
        stream.patch_toml_trace_next = 0;
        stream.patch_toml_trace_full = false;
        stream.path_length = 0;
        stream.string_length = 0;
        stream.string_truncated = false;
        @memset(&stream.path, 0);
        @memset(&stream.string_storage, 0);
        // note: stream.object is deliberately preserved so that ensure()
        // can reactivate this slot when the same guest address is reused.
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

    fn openProcSelfMaps(self: *Bridge, state: anytype, object: u64, mode: u64) u64 {
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

    fn close(self: *Bridge, state: anytype, object: u64) u64 {
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

    fn isOpen(self: *Bridge, object: u64) bool {
        const stream = self.findFlexible(object) orelse return false;
        return stream.fd >= 0 or stream.synthetic_proc_maps;
    }

    fn readInto(self: *Bridge, state: anytype, object: u64, destination: u64, count: u64, set_istream_state: bool) i64 {
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

    fn gcount(self: *Bridge, object: u64) i64 {
        const stream = self.findFlexible(object) orelse return 0;
        return stream.last_read_count;
    }

    fn mirrorGuestGcount(self: *Bridge, state: anytype, istream: u64, result: i64) void {
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

    fn noteState(self: *Bridge, state: anytype, stream: *const Stream, bits: u32) void {
        if (stream.ios_object != 0) _ = self.object_model.setstate(state, stream.ios_object, bits);
    }

    fn seek(self: *Bridge, object: u64, offset: i64, direction: std.c.whence_t) i64 {
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

    fn clearEofBitAfterSeek(self: *Bridge, state: anytype, object: u64, seek_result: i64) void {
        if (seek_result < 0) return;
        const stream = self.findFlexible(object) orelse return;
        if (stream.ios_object != 0) {
            const current = self.object_model.rdstate(state, stream.ios_object);
            _ = self.object_model.clear(state, stream.ios_object, current & ~cxx_object_model.EOFBIT);
        }
    }

    fn readByte(self: *Bridge, object: u64) i32 {
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

    fn peek(self: *Bridge, object: u64) i32 {
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

    fn recordPatchTomlOp(self: *Bridge, stream: *Stream, operation: []const u8, offset: i64, bytes: []const u8) void {
        self.io_sequence +|= 1;
        stream.last_io_sequence = self.io_sequence;
        const op_idx = stream.patch_toml_trace_next;
        const op = &stream.patch_toml_trace[op_idx];
        const op_len = @min(operation.len, op.operation.len);
        @memset(&op.operation, 0);
        @memcpy(op.operation[0..op_len], operation[0..op_len]);
        op.op_len = @intCast(op_len);
        op.offset = offset;
        op.size = bytes.len;
        op.sequence = self.io_sequence;
        if (bytes.len > 0) {
            const copy_len = @min(bytes.len, 4);
            @memcpy(op.content_first[0..copy_len], bytes[0..copy_len]);
            var hash: u64 = 0;
            for (bytes[0..@min(bytes.len, 64)]) |b| hash = hash ^ @as(u64, b);
            op.content_hash = hash;
        }
        stream.patch_toml_trace_next = (stream.patch_toml_trace_next + 1) % PATCH_TOML_TRACE_CAPACITY;
        if (stream.patch_toml_trace_next == 0) stream.patch_toml_trace_full = true;
    }

    fn tracePatchRead(self: *Bridge, stream: *Stream, operation: []const u8, offset: i64, bytes: []const u8) void {
        if (!stream.patch_toml or bytes.len == 0) return;

        self.recordPatchTomlOp(stream, operation, offset, bytes);

        var scanner = Utf8Scanner{};
        for (bytes, 0..) |byte, index| {
            if (scanner.feed(byte, @as(u64, @intCast(@max(offset, 0))) + index)) |issue| {
                machoCapturePrint(
                    "macho-processor: libc++ patch stream invalid UTF-8 chunk: path={s} operation={s} byte_offset={d} reason={s} byte=0x{x:0>2}\n",
                    .{ stream.path[0..stream.path_length], operation, issue.offset, issue.reason, issue.byte },
                );
                self.tracePatchContext(stream.fd, stream.path[0..stream.path_length], issue.offset, "chunk-invalid");
                break;
            }
        }
        if (scanner.finish()) |issue| {
            machoCapturePrint(
                "macho-processor: libc++ patch stream truncated UTF-8 chunk: path={s} operation={s} byte_offset={d} reason={s}\n",
                .{ stream.path[0..stream.path_length], operation, issue.offset, issue.reason },
            );
        }

        // Stream operation is recorded in the trace ring buffer above.
        // The verbose machoCapturePrint for each read/peek is intentionally
        // suppressed during normal operation; dumpPatchTomlDiagnostics
        // emits the full trace on fault.
    }

    fn tracePatchSeek(self: *Bridge, stream: *Stream, operation: []const u8, offset: i64, direction: std.c.whence_t, result: i64) void {
        if (!stream.patch_toml) return;
        _ = direction; // recorded in trace ring buffer below
        _ = result;
        const empty: [0]u8 = undefined;
        self.recordPatchTomlOp(stream, operation, offset, &empty);
    }

    fn tracePatchTell(self: *Bridge, stream: *Stream, result: i64) void {
        if (!stream.patch_toml) return;
        _ = result; // recorded in trace ring buffer
        const empty: [0]u8 = undefined;
        self.recordPatchTomlOp(stream, "tellg", 0, &empty);
    }

    /// Returns the most recent block size read by an active patch stream.
    /// tracked_pos is cumulative and must never be used as a block length.
    pub fn findPatchTomlByteCount(self: *Bridge) ?u64 {
        var newest_sequence: u64 = 0;
        var count: ?u64 = null;
        for (&self.streams) |*stream| {
            if (!stream.active) continue;
            if (stream.fd < 0) continue;
            const path = stream.path[0..stream.path_length];
            if (std.mem.endsWith(u8, path, ".patch.toml")) {
                if (stream.last_io_sequence >= newest_sequence and stream.last_read_count >= 0) {
                    newest_sequence = stream.last_io_sequence;
                    count = @intCast(stream.last_read_count);
                }
            }
        }
        return count;
    }

    pub fn isActivePatchTomlIstream(self: *Bridge, object: u64) bool {
        const stream = self.findFlexible(object) orelse return false;
        return stream.active and stream.fd >= 0 and stream.patch_toml;
    }

    pub fn dumpPatchTomlDiagnostics(self: *Bridge, reason: []const u8) void {
        var found = false;
        for (&self.streams) |*stream| {
            if (!stream.active or !stream.patch_toml) continue;
            found = true;
            const path = stream.path[0..stream.path_length];
            const current: i64 = @intCast(stream.tracked_pos);
            machoCapturePrint(
                "macho-processor: TOML diagnostics ({s}): path={s} object=0x{x} fd={d} generation={d} io_sequence={d} current_offset={d} last_read_offset={d} last_read_size={d} last_gcount={d} eof={} failed={}\n",
                .{ reason, path, stream.object, stream.fd, stream.generation, stream.last_io_sequence, current, stream.last_read_offset, stream.last_read_size, stream.last_read_count, stream.eof, stream.failed },
            );
            self.logPatchSchema(stream, "active-stream");

            const trace_count = if (stream.patch_toml_trace_full) PATCH_TOML_TRACE_CAPACITY else stream.patch_toml_trace_next;
            if (trace_count > 0) {
                machoCapturePrint("macho-processor: libc++ patch I/O trace (last {d} operations):\n", .{trace_count});
                if (stream.patch_toml_trace_full) {
                    const start = stream.patch_toml_trace_next;
                    for (0..PATCH_TOML_TRACE_CAPACITY) |i| {
                        const idx = (start + i) % PATCH_TOML_TRACE_CAPACITY;
                        const op = &stream.patch_toml_trace[idx];
                        if (op.op_len == 0) continue;
                        const op_str = op.operation[0..op.op_len];
                        if (std.mem.eql(u8, op_str, "tellg")) continue;
                        const hex_byte = &[_]u8{
                            "0123456789abcdef"[op.content_first[0] >> 4],
                            "0123456789abcdef"[op.content_first[0] & 0x0f],
                            "0123456789abcdef"[op.content_first[1] >> 4],
                            "0123456789abcdef"[op.content_first[1] & 0x0f],
                            "0123456789abcdef"[op.content_first[2] >> 4],
                            "0123456789abcdef"[op.content_first[2] & 0x0f],
                            "0123456789abcdef"[op.content_first[3] >> 4],
                            "0123456789abcdef"[op.content_first[3] & 0x0f],
                        };
                        machoCapturePrint("  seq={d} {s} offset={d} size={d} first={s} hash=0x{x}\n", .{ op.sequence, op_str, op.offset, op.size, hex_byte[0..8], op.content_hash });
                    }
                } else {
                    for (0..stream.patch_toml_trace_next) |i| {
                        const op = &stream.patch_toml_trace[i];
                        if (op.op_len == 0) continue;
                        const op_str = op.operation[0..op.op_len];
                        if (std.mem.eql(u8, op_str, "tellg")) continue;
                        const hex_byte = &[_]u8{
                            "0123456789abcdef"[op.content_first[0] >> 4],
                            "0123456789abcdef"[op.content_first[0] & 0x0f],
                            "0123456789abcdef"[op.content_first[1] >> 4],
                            "0123456789abcdef"[op.content_first[1] & 0x0f],
                            "0123456789abcdef"[op.content_first[2] >> 4],
                            "0123456789abcdef"[op.content_first[2] & 0x0f],
                            "0123456789abcdef"[op.content_first[3] >> 4],
                            "0123456789abcdef"[op.content_first[3] & 0x0f],
                        };
                        machoCapturePrint("  seq={d} {s} offset={d} size={d} first={s} hash=0x{x}\n", .{ op.sequence, op_str, op.offset, op.size, hex_byte[0..8], op.content_hash });
                    }
                }
            }

            // Detect offset regression: check if offset went backwards
            // (peek operations do NOT advance the position and are excluded)
            var last_offset: i64 = -1;
            var regression_found = false;
            const iteration_count = if (stream.patch_toml_trace_full) PATCH_TOML_TRACE_CAPACITY else stream.patch_toml_trace_next;
            const trace_start = if (stream.patch_toml_trace_full) stream.patch_toml_trace_next else @as(u16, 0);
            for (0..iteration_count) |i| {
                const idx = (trace_start +% @as(u16, @intCast(i))) % PATCH_TOML_TRACE_CAPACITY;
                const op = &stream.patch_toml_trace[idx];
                const op_str = op.operation[0..op.op_len];
                if (op.op_len == 0) continue;
                if (std.mem.eql(u8, op_str, "tellg")) continue;
                // seek sets an absolute offset; track it without regression check
                if (std.mem.eql(u8, op_str, "seek")) {
                    last_offset = op.offset;
                    // peek does NOT advance the file position – skip it
                } else if (std.mem.eql(u8, op_str, "peek")) {
                    continue;
                } else if (op.size > 0) {
                    if (last_offset >= 0 and op.offset < last_offset) {
                        machoCapturePrint("macho-processor: *** OFFSET REGRESSION DETECTED: was offset={d}, now offset={d} (went backwards! fd may have been reopened/reset!)\n", .{ last_offset, op.offset });
                        regression_found = true;
                    }
                    if (op.offset >= 0) last_offset = op.offset + @as(i64, @intCast(op.size));
                }
            }
            if (!regression_found and last_offset >= 0) {
                machoCapturePrint("macho-processor: I/O trace monotonic: no offset regression detected (last tracked end offset = {d})\n", .{last_offset});
            }

            if (stream.fd >= 0) {
                self.tracePatchTomlOpen(stream, path);
                const center: u64 = if (stream.last_read_offset >= 0)
                    @intCast(stream.last_read_offset)
                else if (current >= 0)
                    @intCast(current)
                else
                    0;
                self.tracePatchContext(stream.fd, path, center, "active-stream");

                // Expected vs actual content check at current offset
                if (current >= 0) {
                    var expected: [64]u8 = undefined;
                    const eread = std.c.pread(stream.fd, &expected, expected.len, @intCast(current));
                    if (eread > 0) {
                        const ebytes = expected[0..@intCast(eread)];
                        var ehex: [128]u8 = undefined;
                        for (ebytes, 0..) |b, j| {
                            ehex[j * 2] = "0123456789abcdef"[b >> 4];
                            ehex[j * 2 + 1] = "0123456789abcdef"[b & 0x0f];
                        }
                        machoCapturePrint(
                            "macho-processor: pread at current_offset={d} ({d} bytes): first={s}\n",
                            .{ current, ebytes.len, ehex[0..@min(ebytes.len * 2, 64)] },
                        );
                    }
                }

                // fd integrity check: verify file size via lseek to end
                if (stream.fd >= 0) {
                    const saved = std.c.lseek(stream.fd, 0, std.c.SEEK.CUR);
                    const fsize = std.c.lseek(stream.fd, 0, std.c.SEEK.END);
                    if (saved >= 0 and fsize >= 0) {
                        _ = std.c.lseek(stream.fd, saved, std.c.SEEK.SET);
                        machoCapturePrint(
                            "macho-processor: fd integrity: fd={d} file_size={d}\n",
                            .{ stream.fd, fsize },
                        );
                    }
                }

                // Check for other streams sharing the same fd
                var shared_fd_count: u32 = 0;
                for (&self.streams) |other| {
                    if (other.active and other.fd == stream.fd and other.object != stream.object) shared_fd_count += 1;
                }
                if (shared_fd_count > 0) {
                    machoCapturePrint("macho-processor: *** WARNING: {d} other stream(s) share fd={d}! Possible fd aliasing\n", .{ shared_fd_count, stream.fd });
                    machoCapturePrint("macho-processor: fd aliasing detail: primary object=0x{x} tracked_pos={d} path={s}\n", .{ stream.object, stream.tracked_pos, path });
                    for (&self.streams) |other| {
                        if (other.active and other.fd == stream.fd and other.object != stream.object) {
                            const other_path = other.path[0..other.path_length];
                            machoCapturePrint("macho-processor: fd aliasing detail: aliased object=0x{x} tracked_pos={d} path={s}\n", .{ other.object, other.tracked_pos, other_path });
                        }
                    }
                }
            }
        }
        if (!found) {
            machoCapturePrint("macho-processor: TOML diagnostics ({s}): no active .patch.toml stream tracked by libc++ bridge\n", .{reason});
            if (self.last_patch_schema_valid) {
                self.logPatchSchemaValues(
                    self.last_patch_path[0..self.last_patch_path_length],
                    self.last_patch_schema,
                    "archived-after-stream-destruction",
                );
            }
        }
    }

    pub fn dumpPatchPostParseDiagnosis(self: *Bridge, reason: []const u8) void {
        var newest: ?*Stream = null;
        for (&self.streams) |*stream| {
            if (!stream.active or !stream.patch_toml) continue;
            if (newest == null or stream.generation > newest.?.generation) newest = stream;
        }
        var schema: PatchTomlSchema = undefined;
        var path: []const u8 = undefined;
        if (newest) |stream| {
            schema = stream.patch_toml_schema;
            path = stream.path[0..stream.path_length];
        } else if (self.last_patch_schema_valid) {
            schema = self.last_patch_schema;
            path = self.last_patch_path[0..self.last_patch_path_length];
        } else {
            machoCapturePrint("macho-processor: PatchDB post-parse diagnosis ({s}): no active or archived patch TOML schema is available\n", .{reason});
            return;
        }
        self.logPatchSchemaValues(path, schema, reason);
        if (schema.patch_array_headers == 0) {
            machoCapturePrint(
                "macho-processor: PatchDB null-dereference correlation: the parsed file contains zero [[patch]] arrays; Xenia PatchDB::ReadPatchFile obtains patch_toml_fields.get(\"patch\") and calls patch_array->is_array() without first checking patch_array for null\n",
                .{},
            );
            machoCapturePrint(
                "macho-processor: PatchDB null-dereference verdict: normal EOF and successful TOML parsing are compatible with this crash; the missing optional patch node is the immediate null source, not fd reuse or stream corruption\n",
                .{},
            );
        }
    }

    fn logPatchSchema(_: *Bridge, stream: *const Stream, label: []const u8) void {
        logPatchSchemaValuesStatic(stream.path[0..stream.path_length], stream.patch_toml_schema, label);
    }

    fn logPatchSchemaValues(_: *Bridge, path: []const u8, schema: PatchTomlSchema, label: []const u8) void {
        logPatchSchemaValuesStatic(path, schema, label);
    }

    fn rememberPatchSchema(self: *Bridge, stream: *const Stream) void {
        self.last_patch_schema_valid = stream.patch_toml_schema.complete;
        self.last_patch_schema_generation = stream.generation;
        self.last_patch_schema = stream.patch_toml_schema;
        self.last_patch_path_length = stream.path_length;
        @memcpy(self.last_patch_path[0..self.last_patch_path_length], stream.path[0..stream.path_length]);
    }

    pub fn latestPatchSchemaHasEmptyPatchSet(self: *const Bridge) bool {
        if (!self.last_patch_schema_valid) return false;
        const schema = self.last_patch_schema;
        return schema.complete and
            schema.title_name_assignments != 0 and
            schema.title_id_assignments != 0 and
            schema.hash_assignments != 0 and
            schema.patch_array_headers == 0;
    }

    pub fn logEmptyPatchCompatibility(self: *const Bridge, action: []const u8) void {
        if (!self.last_patch_schema_valid) return;
        logPatchSchemaValuesStatic(
            self.last_patch_path[0..self.last_patch_path_length],
            self.last_patch_schema,
            action,
        );
    }

    fn logPatchSchemaValuesStatic(path: []const u8, schema: PatchTomlSchema, label: []const u8) void {
        machoCapturePrint(
            "macho-processor: patch TOML schema[{s}]: path={s} bytes={d} lines={d} assignments(title_name/title_id/hash)={d}/{d}/{d} patch_array_headers={d} truncated_lines={d} complete={}\n",
            .{ label, path, schema.bytes, schema.lines, schema.title_name_assignments, schema.title_id_assignments, schema.hash_assignments, schema.patch_array_headers, schema.truncated_lines, schema.complete },
        );
    }

    fn tracePatchTomlOpen(self: *Bridge, stream: *Stream, path: []const u8) void {
        const fd = stream.fd;
        const original = std.c.lseek(fd, 0, std.c.SEEK.CUR);
        if (original < 0) return;
        _ = std.c.lseek(fd, 0, std.c.SEEK.SET);
        var buffer: [4096]u8 = undefined;
        var scanner = Utf8Scanner{};
        var schema_scanner = PatchTomlSchemaScanner{};
        var total: u64 = 0;
        var ascii = true;
        var invalid: ?Utf8Invalid = null;
        while (true) {
            const result = std.c.read(fd, &buffer, buffer.len);
            if (result < 0) {
                machoCapturePrint("macho-processor: libc++ patch TOML preflight failed: {s} errno={s}\n", .{ path, @tagName(std.c.errno(result)) });
                _ = std.c.lseek(fd, original, std.c.SEEK.SET);
                return;
            }
            if (result == 0) break;
            const bytes = buffer[0..@intCast(result)];
            schema_scanner.feed(bytes);
            for (bytes, 0..) |byte, index| {
                if (byte >= 0x80) ascii = false;
                if (invalid == null) invalid = scanner.feed(byte, total + index);
            }
            total += bytes.len;
        }
        _ = std.c.lseek(fd, original, std.c.SEEK.SET);
        stream.patch_toml_schema = schema_scanner.finish();
        self.rememberPatchSchema(stream);
        if (invalid == null) invalid = scanner.finish();
        machoCapturePrint(
            "macho-processor: libc++ patch TOML preflight: path={s} bytes={d} ascii={} utf8={} full_scan=true\n",
            .{ path, total, ascii, invalid == null },
        );
        self.logPatchSchema(stream, "preflight");
        if (invalid) |issue| {
            const context_start: u64 = issue.offset -| 8;
            var context: [24]u8 = undefined;
            const context_read = std.c.pread(fd, &context, context.len, @intCast(context_start));
            const context_len: usize = if (context_read > 0) @intCast(context_read) else 0;
            var hex: [48]u8 = undefined;
            const alphabet = "0123456789abcdef";
            for (context[0..context_len], 0..) |byte, index| {
                hex[index * 2] = alphabet[byte >> 4];
                hex[index * 2 + 1] = alphabet[byte & 0x0f];
            }
            machoCapturePrint(
                "macho-processor: libc++ patch TOML invalid UTF-8: path={s} byte_offset={d} reason={s} byte=0x{x:0>2} context_start={d} context_hex={s}\n",
                .{ path, issue.offset, issue.reason, issue.byte, context_start, hex[0 .. context_len * 2] },
            );
        } else {
            // Host bytes validated; detailed UTF-8 diagnostics are suppressed
            // during normal operation. dumpPatchTomlDiagnostics shows full
            // I/O trace and schema information on fault.
        }
    }

    fn tracePatchContext(_: *Bridge, fd: std.c.fd_t, path: []const u8, center: u64, label: []const u8) void {
        if (fd < 0) return;
        const start = center -| 32;
        var context: [96]u8 = undefined;
        const context_read = std.c.pread(fd, &context, context.len, @intCast(start));
        if (context_read <= 0) return;
        const context_len: usize = @intCast(context_read);
        var hex: [192]u8 = undefined;
        var ascii: [96]u8 = undefined;
        const alphabet = "0123456789abcdef";
        for (context[0..context_len], 0..) |byte, index| {
            hex[index * 2] = alphabet[byte >> 4];
            hex[index * 2 + 1] = alphabet[byte & 0x0f];
            ascii[index] = if (byte >= 0x20 and byte < 0x7f) byte else '.';
        }
        machoCapturePrint(
            "macho-processor: libc++ patch TOML context[{s}]: path={s} center={d} start={d} bytes={d} hex={s} ascii='{s}'\n",
            .{ label, path, center, start, context_len, hex[0 .. context_len * 2], ascii[0..context_len] },
        );
    }

    fn available(self: *Bridge, object: u64) i64 {
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

    fn syntheticContent(self: *const Bridge, stream: *const Stream) ?[]const u8 {
        if (stream.synthetic_proc_maps) return self.proc_maps_storage[0..self.proc_maps_length];
        if (stream.string_backed) return stream.string_storage[0..stream.string_length];
        return null;
    }

    pub fn modeledStreamObjectForAddress(self: *Bridge, address: u64) ?u64 {
        const stream = self.findOwned(address) orelse return null;
        return stream.object;
    }

    fn ensure(self: *Bridge, object: u64) ?*Stream {
        if (self.find(object)) |stream| return stream;
        // before activating a slot, deactivate any OTHER entry with the same object
        // (catches stale duplicates left by lifecycle edge cases)
        for (&self.streams) |*stream| {
            if (!stream.active) continue;
            if (stream.object == object) return stream;
        }
        var stale_object: ?*Stream = null;
        for (&self.streams) |*stream| {
            if (stream.active) continue;
            if (stream.object == object) {
                stale_object = stream;
                break;
            }
        }
        if (stale_object) |s| {
            s.* = .{ .active = true, .object = object };
            return s;
        }
        for (&self.streams) |*stream| {
            if (stream.active) continue;
            stream.* = .{ .active = true, .object = object };
            return stream;
        }
        return null;
    }

    fn setOwnership(self: *Bridge, stream: *Stream, owner_object: u64, stream_object: u64, ios_object: u64) void {
        _ = self;
        stream.owner_object = owner_object;
        stream.stream_object = stream_object;
        stream.ios_object = ios_object;
    }

    fn ownsAddress(stream: *const Stream, address: u64) bool {
        if (!stream.active or address == 0) return false;
        return address == stream.object or
            (stream.owner_object != 0 and address == stream.owner_object) or
            (stream.stream_object != 0 and address == stream.stream_object) or
            (stream.ios_object != 0 and address == stream.ios_object);
    }

    fn findOwned(self: *Bridge, address: u64) ?*Stream {
        for (&self.streams) |*stream| {
            if (ownsAddress(stream, address)) return stream;
        }
        return null;
    }

    fn resolveRdbuf(self: *Bridge, state: anytype, object: u64) u64 {
        if (self.findOwned(object)) |stream| {
            self.rdbuf_alias_resolutions +|= 1;
            return stream.object;
        }

        const candidate = self.object_model.rdbuf(state, object);
        if (self.findOwned(candidate)) |stream| {
            self.rdbuf_alias_resolutions +|= 1;
            return stream.object;
        }
        return candidate;
    }

    fn find(self: *Bridge, object: u64) ?*Stream {
        for (&self.streams) |*stream| {
            if (stream.active and stream.object == object) return stream;
        }
        return null;
    }

    fn findFlexible(self: *Bridge, object: u64) ?*Stream {
        if (self.findOwned(object)) |stream| return stream;
        if (self.find(object + FILEBUF_OFFSET_IN_IFSTREAM)) |stream| return stream;
        for (&self.streams) |*stream| {
            if (!stream.active or stream.object < FILEBUF_OFFSET_IN_IFSTREAM) continue;
            const ifstream = stream.object - FILEBUF_OFFSET_IN_IFSTREAM;
            if (object == ifstream or object == ifstream + 424) return stream;
        }
        return null;
    }

    fn findAny(self: *Bridge, object: u64) ?*Stream {
        for (&self.streams) |*stream| {
            if (stream.object == object or
                stream.owner_object == object or
                stream.stream_object == object or
                stream.ios_object == object) return stream;
        }
        return null;
    }
};

fn closeStream(stream: *Stream) void {
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

fn isBasicIstreamConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_istreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_istreamIcNS_11char_traitsIcEEEC2") != null;
}

fn isBasicIostreamConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_iostreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_iostreamIcNS_11char_traitsIcEEEC2") != null;
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

fn isStringStreamConstructor(name: []const u8) bool {
    const family = std.mem.indexOf(u8, name, "basic_ostringstream") != null or
        std.mem.indexOf(u8, name, "basic_istringstream") != null or
        std.mem.indexOf(u8, name, "basic_stringstream") != null;
    return family and (std.mem.indexOf(u8, name, "C1") != null or std.mem.indexOf(u8, name, "C2") != null);
}

fn isStringStreamTextConstructor(name: []const u8) bool {
    return isStringStreamConstructor(name) and
        std.mem.indexOf(u8, name, "ERKNS_12basic_string") != null;
}

fn numericBaseForManipulator(name: []const u8) ?u8 {
    if (std.mem.eql(u8, name, "_ZNSt3__13decB7v160006ERNS_8ios_baseE")) return 10;
    if (std.mem.eql(u8, name, "_ZNSt3__13hexB7v160006ERNS_8ios_baseE")) return 16;
    if (std.mem.eql(u8, name, "_ZNSt3__13octB7v160006ERNS_8ios_baseE")) return 8;
    return null;
}

fn isCharacterReferenceExtraction(name: []const u8) bool {
    return std.mem.eql(
        u8,
        name,
        "_ZNSt3__1rsB7v160006IcNS_11char_traitsIcEEEERNS_13basic_istreamIT_T0_EES7_RS4_",
    );
}

fn characterArrayCapacity(name: []const u8) ?usize {
    const marker = "_ZNSt3__1rsB7v160006IcNS_11char_traitsIcEELm";
    if (!std.mem.startsWith(u8, name, marker) or
        std.mem.indexOf(u8, name, "RNS_13basic_istream") == null or
        std.mem.indexOf(u8, name, "RAT1__S4_") == null)
    {
        return null;
    }
    const suffix = name[marker.len..];
    const end = std.mem.indexOfScalar(u8, suffix, 'E') orelse return null;
    const capacity = std.fmt.parseUnsigned(usize, suffix[0..end], 10) catch return null;
    return if (capacity >= 2 and capacity <= 4096) capacity else null;
}

fn isFormattedWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\n' or byte == '\t' or byte == '\r' or byte == '\x0b' or byte == '\x0c';
}

fn isDigitForBase(byte: u8, base: u8) bool {
    const digit: u8 = if (byte >= '0' and byte <= '9')
        byte - '0'
    else if (byte >= 'a' and byte <= 'f')
        byte - 'a' + 10
    else if (byte >= 'A' and byte <= 'F')
        byte - 'A' + 10
    else
        return false;
    return digit < base;
}

fn isBasicFilebufConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_filebufIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_filebufIcNS_11char_traitsIcEEEC2") != null;
}

fn isBasicStreambufConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEEC2") != null;
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

fn isBasicStreambufPubimbue(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEE8pubimbue") != null;
}

fn isBasicStreambufImbue(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEE5imbue") != null;
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

fn isThreadIdInsertion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostream") != null and
        (std.mem.indexOf(u8, name, "NS_6thread2idE") != null or
            std.mem.indexOf(u8, name, "NS_11__thread_idE") != null or
            (std.mem.indexOf(u8, name, "thread") != null and std.mem.indexOf(u8, name, "idE") != null));
}

fn isPointerInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEPKv");
}

fn isCStringInsertion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostream") != null and
        std.mem.indexOf(u8, name, "PKc") != null and
        std.mem.indexOf(u8, name, "ls") != null;
}

fn isIntegerInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEb") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEi") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEj") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEl") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEm") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEx") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEy");
}

fn isSignedIntegerInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEi") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEl") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEx");
}

/// basic_ostream::operator<<(double). Imported by the Xenia fork and currently
/// unhandled; render it so a floating-point print cannot fall through to an
/// unresolved import.
fn isDoubleInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEd");
}

/// basic_ostream::operator<<(ostream&(*)(ostream&)) / (ios_base&(*)(ios_base&)).
/// Mangled member forms contain `ls` plus a function-pointer parameter that
/// returns a reference to the stream (`PFRS`) or to ios_base (`PFRNS`).
fn isOstreamManipulatorInsertion(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "basic_ostream") == null) return false;
    if (std.mem.indexOf(u8, name, "ls") == null) return false;
    return std.mem.indexOf(u8, name, "PFRS") != null or std.mem.indexOf(u8, name, "PFRNS") != null;
}

/// The std::endl / std::flush / std::ends manipulator functions themselves.
/// Length-prefixed mangling: `_ZNSt3__14endl...`, `_ZNSt3__15flush...`,
/// `_ZNSt3__14ends...` — the digit prefix is the identifier length.
fn isStreamManipulator(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "basic_ostream") == null) return false;
    return std.mem.indexOf(u8, name, "4endl") != null or
        std.mem.indexOf(u8, name, "5flush") != null or
        std.mem.indexOf(u8, name, "4ends") != null;
}

/// Classify a manipulator symbol name into a character to append, or null for
/// flush-only manipulators. std::endl appends '\n', std::ends appends the null
/// terminator, std::flush has no model state to flush (writes are unbuffered).
fn manipulatorAppend(name: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, name, "4endl") != null) return "\n";
    if (std.mem.indexOf(u8, name, "4ends") != null) return "\x00";
    return null;
}

fn manipulatorNumericBase(name: []const u8) ?u8 {
    if (std.mem.indexOf(u8, name, "3dec") != null) return 10;
    if (std.mem.indexOf(u8, name, "3hex") != null) return 16;
    if (std.mem.indexOf(u8, name, "3oct") != null) return 8;
    return null;
}

fn isStringbufStr(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv") != null;
}

fn isStringStreamStr(name: []const u8) bool {
    const family = std.mem.indexOf(u8, name, "basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEE3str") != null or
        std.mem.indexOf(u8, name, "basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEE3str") != null;
    return family and std.mem.indexOf(u8, name, "Ev") != null;
}

fn displayThreadId(raw_id: u64) u64 {
    if (raw_id == 0 or raw_id == CURRENT_THREAD_HANDLE) return 1;
    if (raw_id >= IDLE_CALLBACK_HANDLE_BASE) return 1;
    if (raw_id >= SYNTHETIC_THREAD_BASE and raw_id < SYNTHETIC_THREAD_BASE + 0x10000) {
        return 2 + ((raw_id - SYNTHETIC_THREAD_BASE) / 0x10);
    }
    return raw_id;
}

fn isUnsignedIntegerInsertion(name: []const u8) bool {
    return isIntegerInsertion(name) and !isSignedIntegerInsertion(name);
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

fn isIfstreamFilesystemPathConstructor(name: []const u8) bool {
    return (std.mem.indexOf(u8, name, "basic_ifstreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_ifstreamIcNS_11char_traitsIcEEEC2") != null) and
        std.mem.indexOf(u8, name, "__fs10filesystem4path") != null;
}

fn isIfstreamDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED2Ev");
}

fn isOfstreamDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED2Ev");
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

test "modeled istream read mirrors libc++ gcount ABI field" {
    const TestState = struct {
        mem: [128]u8 = [_]u8{0} ** 128,

        fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }

        fn read64(self: *const @This(), address: u64) u64 {
            return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
        }

        fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
        }
    };

    var bridge = Bridge{};
    defer bridge.deinit();
    var state = TestState{};
    const istream: u64 = 32;
    const stream = bridge.ensure(istream + FILEBUF_OFFSET_IN_IFSTREAM).?;
    stream.ios_object = istream;
    state.write64(istream + BASIC_ISTREAM_GCOUNT_OFFSET, 0x4d7ab70);

    bridge.mirrorGuestGcount(&state, istream, 32);
    try std.testing.expectEqual(@as(u64, 32), state.read64(istream + BASIC_ISTREAM_GCOUNT_OFFSET));
    try std.testing.expectEqual(@as(i64, 0), stream.last_read_count);
}

test "virtual proc maps file supports libc++ reads and seeks without a host fd" {
    const TestState = struct {
        mem: [256]u8 = [_]u8{0} ** 256,

        pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }

        pub fn read32(self: *const @This(), address: u64) u32 {
            return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
        }

        pub fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
        }

        pub fn read64(self: *const @This(), address: u64) u64 {
            return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
        }

        pub fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
        }

        pub fn renderProcSelfMaps(_: *const @This(), output: []u8) []const u8 {
            const content = "1000-2000 rw-p 00000000 00:00 0 [rosette-mapping]\n";
            @memcpy(output[0..content.len], content);
            return output[0..content.len];
        }
    };

    var bridge = Bridge{};
    defer bridge.deinit();
    var state = TestState{};
    const object: u64 = 32;
    try std.testing.expectEqual(object, bridge.openProcSelfMaps(&state, object, OPENMODE_IN));
    try std.testing.expect(bridge.isOpen(object));
    try std.testing.expectEqual(@as(i64, 8), bridge.readInto(&state, object, 128, 8, false));
    try std.testing.expectEqualStrings("1000-200", state.mem[128..136]);
    try std.testing.expectEqual(@as(i64, 0), bridge.seek(object, 0, std.c.SEEK.SET));
    try std.testing.expectEqual(@as(i32, '1'), bridge.peek(object));
    try std.testing.expectEqual(@as(i32, '1'), bridge.readByte(object));
    try std.testing.expectEqual(object, bridge.close(&state, object));
    try std.testing.expect(!bridge.isOpen(object));
}

test "patch byte count reports latest block not cumulative cursor" {
    var bridge = Bridge{};
    defer bridge.deinit();
    const older = bridge.ensure(0x1000).?;
    older.fd = 3;
    older.patch_toml = true;
    older.path_length = "older.patch.toml".len;
    @memcpy(older.path[0..older.path_length], "older.patch.toml");
    older.tracked_pos = 4096;
    older.last_read_count = 32;
    older.last_io_sequence = 4;

    const newer = bridge.ensure(0x2000).?;
    newer.fd = 4;
    newer.patch_toml = true;
    newer.path_length = "newer.patch.toml".len;
    @memcpy(newer.path[0..newer.path_length], "newer.patch.toml");
    newer.tracked_pos = 8192;
    newer.last_read_count = 17;
    newer.last_io_sequence = 5;

    try std.testing.expectEqual(@as(?u64, 17), bridge.findPatchTomlByteCount());
    // Prevent the unit test from closing arbitrary process fds.
    older.fd = -1;
    newer.fd = -1;
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
    try std.testing.expect(isOfstreamDestructor(normalizeSymbol("__ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED1Ev")));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED2Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__113basic_istreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__114basic_iostreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__118basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEC1B7v160006Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__1lsB7v160006IcNS_11char_traitsIcEEERNS_13basic_ostreamIT_T0_EES7_NS_6thread2idE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__1lsB7v160006IcNS_11char_traitsIcEEERNS_13basic_ostreamIT_T0_EES7_NS_11__thread_idE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNKSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEE3strB7v160006Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEEC2Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1B7v160006ERKNS_4__fs10filesystem4pathEj"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__119basic_istringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNKSt3__19basic_iosIcNS_11char_traitsIcEEE7rdstateB7v160006Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE8pubimbueB7v160006ERKNS_6localeE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5imbueERKNS_6localeE"));
}

test "stream bridge recognizes std manipulators and function-pointer insertions" {
    const endl = normalizeSymbol("__ZNSt3__14endlB7v160006IcNS_11char_traitsIcEEEERNS_13basic_ostreamIT_T0_EES7_");
    const flush = normalizeSymbol("__ZNSt3__15flushB7v160006IcNS_11char_traitsIcEEEERNS_13basic_ostreamIT_T0_EES7_");
    const ends = normalizeSymbol("__ZNSt3__14endsB7v160006IcNS_11char_traitsIcEEEERNS_13basic_ostreamIT_T0_EES7_");
    const pf_insert = normalizeSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsB7v160006EPFRS3_S4_E");
    const ios_pf_insert = normalizeSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsB7v160006EPFRNS_8ios_baseES5_E");
    const int_insert = normalizeSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEi");

    try std.testing.expect(isStreamManipulator(endl));
    try std.testing.expect(isStreamManipulator(flush));
    try std.testing.expect(isStreamManipulator(ends));
    try std.testing.expect(!isStreamManipulator(int_insert));
    try std.testing.expect(isOstreamManipulatorInsertion(pf_insert));
    try std.testing.expect(isOstreamManipulatorInsertion(ios_pf_insert));
    try std.testing.expect(!isOstreamManipulatorInsertion(int_insert));
    try std.testing.expectEqualStrings("\n", manipulatorAppend(endl).?);
    try std.testing.expect(manipulatorAppend(flush) == null);
    try std.testing.expectEqual(@as(?u8, 16), manipulatorNumericBase("__ZNSt3__13hexB7v160006ERNS_8ios_baseE"));
    try std.testing.expectEqual(@as(?u8, 8), manipulatorNumericBase("__ZNSt3__13octB7v160006ERNS_8ios_baseE"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__14endlB7v160006IcNS_11char_traitsIcEEEERNS_13basic_ostreamIT_T0_EES7_"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsB7v160006EPFRS3_S4_E"));
}

test "standard stream construction models cerr over a tracked fd-2 filebuf" {
    const TestState = struct {
        alloc_next: u64 = 0x1_0000,
        mem: [256 * 1024]u8 = [_]u8{0} ** (256 * 1024),

        pub fn guestAlloc(self: *@This(), length: u64, alignment: u64) ?u64 {
            _ = alignment;
            const address = self.alloc_next;
            self.alloc_next += length;
            if (address + length > self.mem.len) return null;
            return address;
        }

        pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }

        pub fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            if (address + length > self.mem.len) return null;
            return self.mem[@intCast(address)..@intCast(address + length)];
        }

        pub fn read64(self: *const @This(), address: u64) u64 {
            return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
        }

        pub fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
        }

        pub fn write8(self: *@This(), address: u64, value: u8) void {
            self.mem[@intCast(address)] = value;
        }

        pub fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
        }
    };

    var bridge = Bridge{};
    defer bridge.deinit();
    var state = TestState{};
    const ostream = bridge.ensureStandardStream(&state, .cerr).?;
    try std.testing.expectEqual(ostream, bridge.ensureStandardStream(&state, .cerr).?);
    try std.testing.expectEqual(@as(u64, 0), bridge.standard_ostreams[@intFromEnum(StandardStreamKind.cin)]);
    const filebuf = state.read64(ostream + cxx_object_model.stream_layout.rdbuf_offset);
    try std.testing.expect(filebuf != 0);
    try std.testing.expect(bridge.findOwned(ostream) != null);
    const stream = bridge.find(filebuf).?;
    try std.testing.expect(stream.is_standard);
    try std.testing.expectEqual(@as(i32, 2), stream.fd);
}

test "stream bridge forwards guest file operations through typed host calls" {
    const TestStackVtableRegistry = struct {
        address: u64 = 0,
        vptr: u64 = 0,

        pub fn register(self: *@This(), address: u64, vptr: u64, provenance: anytype) void {
            _ = provenance;
            self.address = address;
            self.vptr = vptr;
        }

        pub fn forget(self: *@This(), address: u64) void {
            if (self.address != address) return;
            self.address = 0;
            self.vptr = 0;
        }

        pub fn contains(self: *const @This(), address: u64) bool {
            return self.address == address and self.vptr != 0;
        }
    };
    const TestState = struct {
        mem: [4096]u8 = [_]u8{0} ** 4096,
        next_alloc: u64 = 2048,
        executed_steps: u64 = 0,
        active_guest_thread: u64 = 0,
        vtable_stack_registry: TestStackVtableRegistry = .{},
        regs: struct {
            rdi: u64 = 0,
            rsi: u64 = 0,
            rdx: u64 = 0,
            rip: u64 = 0,
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
    try std.testing.expectEqual(@as(i64, 0), bridge.readInto(&state, object, 400, 16, false));
    try std.testing.expect(bridge.eof(object));
    try std.testing.expect(!bridge.failed(object));
    try std.testing.expectEqual(@as(i64, 0), bridge.seek(object, 0, std.c.SEEK.SET));
    const patch_stream = bridge.find(object).?;
    patch_stream.patch_toml = true;
    patch_stream.eof = false;
    patch_stream.failed = false;
    try std.testing.expectEqual(@as(i64, 0), bridge.readInto(&state, object, 400, 16, true));
    try std.testing.expect(bridge.eof(object));
    try std.testing.expect(!bridge.failed(object));
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
    try std.testing.expectEqual(@as(u64, 0), state.read64(ifstream + BASIC_ISTREAM_GCOUNT_OFFSET));
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
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev"));
    try std.testing.expect(Bridge.recognizesSymbol("__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1B7v160006ERKNS_4__fs10filesystem4pathEj"));

    var stringstream_bridge = Bridge{};
    defer stringstream_bridge.deinit();
    const stringstream: u64 = 512;
    const streambuf_for_stringstream = stringstream + STRINGSTREAM_BUFFER_OFFSET;
    const output_string: u64 = 768;
    state.regs = .{ .rdi = stringstream };
    try std.testing.expect(stringstream_bridge.dispatch(&state, &fs, "__ZNSt3__118basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEC1B7v160006Ev") != null);
    const modeled_stringstream = stringstream_bridge.find(streambuf_for_stringstream).?;
    try std.testing.expectEqual(stringstream, modeled_stringstream.owner_object);
    try std.testing.expectEqual(stringstream + STRINGSTREAM_OSTREAM_OFFSET, modeled_stringstream.stream_object);
    try std.testing.expectEqual(stringstream + STRINGSTREAM_IOS_OFFSET, modeled_stringstream.ios_object);
    const streambuf_vptr = state.read64(streambuf_for_stringstream);
    try std.testing.expectEqual(
        compat_runtime.thunkAddress(.streambuf_imbue),
        state.read64(streambuf_vptr + 2 * @sizeOf(u64)),
    );
    const expected_streambuf_thunks = [_]compat_runtime.SyntheticThunk{
        .streambuf_imbue,
        .streambuf_setbuf,
        .streambuf_seekoff,
        .streambuf_seekpos,
        .streambuf_sync,
        .streambuf_showmanyc,
        .streambuf_xsgetn,
        .streambuf_underflow,
        .streambuf_uflow,
        .streambuf_pbackfail,
        .streambuf_xsputn,
        .streambuf_overflow,
    };
    for (expected_streambuf_thunks, 2..) |thunk, slot| {
        const target = state.read64(streambuf_vptr + slot * @sizeOf(u64));
        try std.testing.expectEqual(compat_runtime.thunkAddress(thunk), target);
        try std.testing.expectEqual(thunk, compat_runtime.syntheticThunk(target).?);
    }
    const virtual_text_address: u64 = 1792;
    const virtual_text = "GPU-ready ";
    @memcpy(
        state.mem[virtual_text_address .. virtual_text_address + virtual_text.len],
        virtual_text,
    );
    try std.testing.expectEqual(
        @as(u64, virtual_text.len),
        stringstream_bridge.dispatchStreambufVirtual(
            &state,
            .streambuf_xsputn,
            streambuf_for_stringstream,
            virtual_text_address,
            virtual_text.len,
        ),
    );
    for ([_]u64{
        stringstream,
        stringstream + STRINGSTREAM_OSTREAM_OFFSET,
        stringstream + STRINGSTREAM_IOS_OFFSET,
    }) |alias| {
        state.regs = .{ .rdi = alias };
        const rdbuf_result = stringstream_bridge.dispatch(
            &state,
            &fs,
            "__ZNKSt3__19basic_iosIcNS_11char_traitsIcEEE5rdbufB7v160006Ev",
        ).?;
        try std.testing.expectEqual(streambuf_for_stringstream, rdbuf_result.handled);
    }
    state.regs = .{ .rdi = streambuf_for_stringstream, .rsi = 0x40 };
    const pubimbue_result = stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE8pubimbueB7v160006ERKNS_6localeE",
    ).?;
    switch (pubimbue_result) {
        .handled_void => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(u64, 3), stringstream_bridge.rdbuf_alias_resolutions);
    try std.testing.expectEqual(@as(u64, 1), stringstream_bridge.modeled_streambuf_imbues);
    state.regs = .{ .rdi = stringstream + STRINGSTREAM_OSTREAM_OFFSET, .rsi = SYNTHETIC_THREAD_BASE + 0x10 };
    try std.testing.expect(stringstream_bridge.dispatch(&state, &fs, "__ZNSt3__1lsB7v160006IcNS_11char_traitsIcEEERNS_13basic_ostreamIT_T0_EES7_NS_6thread2idE") != null);
    state.regs = .{ .rdi = output_string, .rsi = streambuf_for_stringstream };
    try std.testing.expect(stringstream_bridge.dispatch(&state, &fs, "__ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv") != null);
    const thread_id_text = compat_runtime.libcppStringView(&state, output_string).?;
    const thread_id_bytes = state.guestMemoryConst(thread_id_text.address, thread_id_text.length).?;
    try std.testing.expectEqualStrings("GPU-ready 3", thread_id_bytes);
    try std.testing.expectEqual(@as(u64, 1), stringstream_bridge.modeled_streambuf_virtual_calls);
    try std.testing.expectEqual(@as(u64, 2), stringstream_bridge.modeled_streambuf_writes);
    try std.testing.expect(state.vtable_stack_registry.contains(streambuf_for_stringstream));
    state.regs = .{ .rdi = stringstream };
    const stringstream_destructor = stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__118basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev",
    ).?;
    switch (stringstream_destructor) {
        .handled_void => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(!state.vtable_stack_registry.contains(streambuf_for_stringstream));
    try std.testing.expect(stringstream_bridge.find(streambuf_for_stringstream) == null);

    // Xenia's POSIX QueryProtect parses Rosette's virtual /proc/self/maps with
    // `stringstream(line) >> std::hex >> begin >> '-' >> end >> protection`.
    // All of these locally-linked libc++ helpers must stay on the modeled
    // stream path; allowing even the char extractor to enter native sbumpc()
    // reads zero get-area pointers from the synthetic streambuf layout.
    const maps_line_object: u64 = 1400;
    const maps_stream: u64 = 1536;
    const maps_begin: u64 = 1800;
    const maps_separator: u64 = 1816;
    const maps_end: u64 = 1824;
    const maps_protection: u64 = 1840;
    const maps_line = "3cd450000-3cd460000 rw-p 00000000 00:00 0 [rosette-mapping]";
    try std.testing.expect(compat_runtime.initLibcppStringFromSlice(&state, maps_line_object, maps_line));
    state.regs = .{ .rdi = maps_stream, .rsi = maps_line_object, .rdx = OPENMODE_IN };
    try std.testing.expect(stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__118basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEC1B7v160006ERKNS_12basic_stringIcS2_S4_EEj",
    ) != null);
    state.regs = .{ .rdi = maps_stream + STRINGSTREAM_IOS_OFFSET };
    try std.testing.expect(stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__13hexB7v160006ERNS_8ios_baseE",
    ) != null);
    state.regs = .{ .rdi = maps_stream, .rsi = maps_begin };
    try std.testing.expect(stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__113basic_istreamIcNS_11char_traitsIcEEErsERm",
    ) != null);
    state.regs = .{ .rdi = maps_stream, .rsi = maps_separator };
    try std.testing.expect(stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__1rsB7v160006IcNS_11char_traitsIcEEEERNS_13basic_istreamIT_T0_EES7_RS4_",
    ) != null);
    state.regs = .{ .rdi = maps_stream, .rsi = maps_end };
    try std.testing.expect(stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__113basic_istreamIcNS_11char_traitsIcEEErsERm",
    ) != null);
    state.regs = .{ .rdi = maps_stream, .rsi = maps_protection };
    try std.testing.expect(stringstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__1rsB7v160006IcNS_11char_traitsIcEELm4EEERNS_13basic_istreamIT_T0_EES7_RAT1__S4_",
    ) != null);
    try std.testing.expectEqual(@as(u64, 0x3cd450000), state.read64(maps_begin));
    try std.testing.expectEqual(@as(u8, '-'), state.mem[maps_separator]);
    try std.testing.expectEqual(@as(u64, 0x3cd460000), state.read64(maps_end));
    try std.testing.expectEqualStrings("rw-", state.mem[maps_protection .. maps_protection + 3]);

    var ostringstream_bridge = Bridge{};
    defer ostringstream_bridge.deinit();
    const ostringstream: u64 = 1024;
    const ostringstream_output: u64 = 1280;
    state.regs = .{ .rdi = ostringstream };
    try std.testing.expect(ostringstream_bridge.dispatch(&state, &fs, "__ZNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEC1B7v160006Ev") != null);
    state.regs = .{ .rdi = ostringstream, .rsi = SYNTHETIC_THREAD_BASE + 0x20 };
    try std.testing.expect(ostringstream_bridge.dispatch(&state, &fs, "__ZNSt3__1lsB7v160006IcNS_11char_traitsIcEEERNS_13basic_ostreamIT_T0_EES7_NS_11__thread_idE") != null);
    state.regs = .{ .rdi = ostringstream_output, .rsi = ostringstream };
    try std.testing.expect(ostringstream_bridge.dispatch(&state, &fs, "__ZNKSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEE3strB7v160006Ev") != null);
    const ostringstream_text = compat_runtime.libcppStringView(&state, ostringstream_output).?;
    const ostringstream_bytes = state.guestMemoryConst(ostringstream_text.address, ostringstream_text.length).?;
    try std.testing.expectEqualStrings("4", ostringstream_bytes);

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

    var ofstream_bridge = Bridge{};
    defer ofstream_bridge.deinit();
    state = .{};
    const ofstream: u64 = 64;
    const ofstream_filebuf = ofstream + FILEBUF_OFFSET_IN_OFSTREAM;
    const modeled_ofstream = ofstream_bridge.ensure(ofstream_filebuf).?;
    ofstream_bridge.setOwnership(modeled_ofstream, ofstream, ofstream, 0);
    state.vtable_stack_registry.register(ofstream_filebuf, 0xAA55, .{});
    state.regs = .{ .rdi = ofstream };
    const ofstream_destructor = ofstream_bridge.dispatch(
        &state,
        &fs,
        "__ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED2Ev",
    ).?;
    switch (ofstream_destructor) {
        .handled_void => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(u64, 1), ofstream_bridge.ofstream_destructors);
    try std.testing.expect(ofstream_bridge.find(ofstream_filebuf) == null);
    try std.testing.expect(!state.vtable_stack_registry.contains(ofstream_filebuf));
}
