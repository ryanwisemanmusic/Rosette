const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const cxx_object_model = @import("cxx_abi").cxx_object_model;
const machoCapturePrint = @import("event_log").machoCapturePrint;
const stream_symbols = @import("libcpp_stream_symbols.zig");
const types = @import("bridge_types.zig");
const bridge_core = @import("bridge_core.zig");
const bridge_read = @import("bridge_read.zig");
const bridge_write = @import("bridge_write.zig");
const bridge_open = @import("bridge_open.zig");
const bridge_patch = @import("bridge_patch.zig");

const characterArrayCapacity = stream_symbols.characterArrayCapacity;
const displayThreadId = stream_symbols.displayThreadId;
const isBaseDestructor = stream_symbols.isBaseDestructor;
const isBasicFilebufConstructor = stream_symbols.isBasicFilebufConstructor;
const isBasicIosBool = stream_symbols.isBasicIosBool;
const isBasicIosClear = stream_symbols.isBasicIosClear;
const isBasicIosEof = stream_symbols.isBasicIosEof;
const isBasicIosFail = stream_symbols.isBasicIosFail;
const isBasicIosGood = stream_symbols.isBasicIosGood;
const isBasicIosInit = stream_symbols.isBasicIosInit;
const isBasicIosRdbuf = stream_symbols.isBasicIosRdbuf;
const isBasicIosRdstate = stream_symbols.isBasicIosRdstate;
const isBasicIosSetstate = stream_symbols.isBasicIosSetstate;
const isBasicIostreamConstructor = stream_symbols.isBasicIostreamConstructor;
const isBasicIstreamConstructor = stream_symbols.isBasicIstreamConstructor;
const isBasicOstreamConstructor = stream_symbols.isBasicOstreamConstructor;
const isBasicOstreamDestructor = stream_symbols.isBasicOstreamDestructor;
const isBasicStreambufConstructor = stream_symbols.isBasicStreambufConstructor;
const isBasicStreambufImbue = stream_symbols.isBasicStreambufImbue;
const isBasicStreambufPubimbue = stream_symbols.isBasicStreambufPubimbue;
const isCStringInsertion = stream_symbols.isCStringInsertion;
const isCharacterReferenceExtraction = stream_symbols.isCharacterReferenceExtraction;
const isDigitForBase = stream_symbols.isDigitForBase;
const isDoubleInsertion = stream_symbols.isDoubleInsertion;
const isFormattedWhitespace = stream_symbols.isFormattedWhitespace;
const isIfstreamCStringConstructor = stream_symbols.isIfstreamCStringConstructor;
const isIfstreamDefaultConstructor = stream_symbols.isIfstreamDefaultConstructor;
const isIfstreamDestructor = stream_symbols.isIfstreamDestructor;
const isIfstreamFilesystemPathConstructor = stream_symbols.isIfstreamFilesystemPathConstructor;
const isIntegerInsertion = stream_symbols.isIntegerInsertion;
const isOfstreamDestructor = stream_symbols.isOfstreamDestructor;
const isOstreamManipulatorInsertion = stream_symbols.isOstreamManipulatorInsertion;
const isPointerInsertion = stream_symbols.isPointerInsertion;
const isSignedIntegerInsertion = stream_symbols.isSignedIntegerInsertion;
const isStreamManipulator = stream_symbols.isStreamManipulator;
const isStringStreamConstructor = stream_symbols.isStringStreamConstructor;
const isStringStreamDestructor = stream_symbols.isStringStreamDestructor;
const isStringStreamStr = stream_symbols.isStringStreamStr;
const isStringStreamTextConstructor = stream_symbols.isStringStreamTextConstructor;
const isStringbufStr = stream_symbols.isStringbufStr;
const isThreadIdInsertion = stream_symbols.isThreadIdInsertion;
const manipulatorAppend = stream_symbols.manipulatorAppend;
const manipulatorNumericBase = stream_symbols.manipulatorNumericBase;
const normalizeSymbol = stream_symbols.normalizeSymbol;
const numericBaseForManipulator = stream_symbols.numericBaseForManipulator;
const seekDirection = stream_symbols.seekDirection;
const selectStreambufArgument = stream_symbols.selectStreambufArgument;

/// Standard C++ streams constructed on demand when the Mach-O bindings for
/// __ZSt4cin/cout/cerr/clog are resolved. Indexed by `StandardStreamKind`.
const SYNTHETIC_THREAD_BASE = stream_symbols.SYNTHETIC_THREAD_BASE;

const BASIC_IOS_OFFSET_IN_IFSTREAM = types.BASIC_IOS_OFFSET_IN_IFSTREAM;
const BASIC_ISTREAM_GCOUNT_OFFSET = types.BASIC_ISTREAM_GCOUNT_OFFSET;
const FILEBUF_OFFSET_IN_IFSTREAM = types.FILEBUF_OFFSET_IN_IFSTREAM;
const FILEBUF_OFFSET_IN_OFSTREAM = types.FILEBUF_OFFSET_IN_OFSTREAM;
const MAX_STREAMS = types.MAX_STREAMS;
const OPENMODE_IN = types.OPENMODE_IN;
pub const Outcome = types.Outcome;
const PROC_SELF_MAPS_CAPACITY = types.PROC_SELF_MAPS_CAPACITY;
const PatchTomlSchema = types.PatchTomlSchema;
const PatchTomlSchemaScanner = types.PatchTomlSchemaScanner;
const STRINGSTREAM_BUFFER_OFFSET = types.STRINGSTREAM_BUFFER_OFFSET;
const STRINGSTREAM_IOS_OFFSET = types.STRINGSTREAM_IOS_OFFSET;
const STRINGSTREAM_OSTREAM_OFFSET = types.STRINGSTREAM_OSTREAM_OFFSET;
pub const StandardStreamKind = types.StandardStreamKind;
const Stream = types.Stream;

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
        return bridge_core.deinit(self);
    }
    pub fn dispatch(self: *Bridge, state: anytype, fs: anytype, symbol: []const u8) ?Outcome {
        return bridge_core.dispatch(self, state, fs, symbol);
    }
    pub fn recognizesSymbol(symbol: []const u8) bool {
        return bridge_core.recognizesSymbol(symbol);
    }
    pub fn handlePubsetbuf(self: *Bridge, object: u64, buffer: u64, size: u64) u64 {
        return bridge_core.handlePubsetbuf(self, object, buffer, size);
    }
    pub fn dispatchStreambufVirtual(
        self: *Bridge,
        state: anytype,
        thunk: compat_runtime.SyntheticThunk,
        object: u64,
        argument_1: u64,
        argument_2: u64,
    ) u64 {
        return bridge_core.dispatchStreambufVirtual(self, state, thunk, object, argument_1, argument_2);
    }
    pub fn constructIfstream(self: *Bridge, state: anytype, object: u64) bool {
        return bridge_core.constructIfstream(self, state, object);
    }
    pub fn constructOstream(self: *Bridge, state: anytype, object: u64, streambuf: u64) bool {
        return bridge_core.constructOstream(self, state, object, streambuf);
    }
    pub fn ensureStandardStream(self: *Bridge, state: anytype, kind: StandardStreamKind) ?u64 {
        return bridge_core.ensureStandardStream(self, state, kind);
    }
    pub fn constructStandardStream(self: *Bridge, state: anytype, fd: i32) ?u64 {
        return bridge_core.constructStandardStream(self, state, fd);
    }
    pub fn applyManipulator(self: *Bridge, state: anytype, ostream: u64, name: []const u8) u64 {
        return bridge_write.applyManipulator(self, state, ostream, name);
    }
    pub fn insertManipulatorPointer(self: *Bridge, state: anytype, ostream: u64, pointer: u64) u64 {
        return bridge_write.insertManipulatorPointer(self, state, ostream, pointer);
    }
    pub fn constructFilebuf(self: *Bridge, state: anytype, object: u64) bool {
        return bridge_core.constructFilebuf(self, state, object);
    }
    pub fn stringbufToString(self: *Bridge, state: anytype, stringbuf: u64, output: u64) bool {
        return bridge_core.stringbufToString(self, state, stringbuf, output);
    }
    pub fn streamObjectToString(self: *Bridge, state: anytype, object: u64, output: u64) bool {
        return bridge_core.streamObjectToString(self, state, object, output);
    }
    pub fn insertThreadId(self: *Bridge, state: anytype, ostream: u64, raw_id: u64) u64 {
        return bridge_write.insertThreadId(self, state, ostream, raw_id);
    }
    pub fn insertInteger(self: *Bridge, state: anytype, ostream: u64, value: u64, signed: bool) u64 {
        return bridge_write.insertInteger(self, state, ostream, value, signed);
    }
    pub fn insertPointer(self: *Bridge, state: anytype, ostream: u64, value: u64) u64 {
        return bridge_write.insertPointer(self, state, ostream, value);
    }
    pub fn insertDouble(self: *Bridge, state: anytype, ostream: u64, bits: u64) u64 {
        return bridge_write.insertDouble(self, state, ostream, bits);
    }
    pub fn insertCString(self: *Bridge, state: anytype, ostream: u64, address: u64) u64 {
        return bridge_write.insertCString(self, state, ostream, address);
    }
    pub fn extractUnsignedLong(self: *Bridge, state: anytype) u64 {
        return bridge_read.extractUnsignedLong(self, state);
    }
    pub fn extractCharacter(self: *Bridge, state: anytype) u64 {
        return bridge_read.extractCharacter(self, state);
    }
    pub fn extractCharacterArray(self: *Bridge, state: anytype, capacity: usize) u64 {
        return bridge_read.extractCharacterArray(self, state, capacity);
    }
    pub fn skipFormattedWhitespace(self: *Bridge, stream: *Stream) void {
        return bridge_read.skipFormattedWhitespace(self, stream);
    }
    pub fn appendToOstream(self: *Bridge, state: anytype, ostream: u64, text: []const u8) bool {
        return bridge_write.appendToOstream(self, state, ostream, text);
    }
    pub fn writeFromGuest(self: *Bridge, state: anytype, object: u64, source: u64, count: u64) i64 {
        return bridge_write.writeFromGuest(self, state, object, source, count);
    }
    pub fn writeBytes(self: *Bridge, state: anytype, stream: *Stream, bytes: []const u8) usize {
        return bridge_write.writeBytes(self, state, stream, bytes);
    }
    pub fn writeStandardBytes(self: *Bridge, state: anytype, stream: *Stream, bytes: []const u8) usize {
        return bridge_write.writeStandardBytes(self, state, stream, bytes);
    }
    pub fn writeOne(self: *Bridge, state: anytype, object: u64, value: i32) i32 {
        return bridge_write.writeOne(self, state, object, value);
    }
    pub fn putBack(self: *Bridge, object: u64, value: i32) i32 {
        return bridge_read.putBack(self, object, value);
    }
    pub fn streamForOstream(self: *Bridge, state: anytype, object: u64) ?*Stream {
        return bridge_core.streamForOstream(self, state, object);
    }
    pub fn resetStringBuffer(self: *Bridge, stream: *Stream) void {
        return bridge_core.resetStringBuffer(self, stream);
    }
    pub fn constructBaseStream(self: *Bridge, state: anytype, kind: cxx_object_model.Kind, object: u64, streambuf: u64) bool {
        return bridge_core.constructBaseStream(self, state, kind, object, streambuf);
    }
    pub fn constructStringStream(self: *Bridge, state: anytype, object: u64) bool {
        return bridge_core.constructStringStream(self, state, object);
    }
    pub fn seedStringStream(self: *Bridge, object: u64, text: []const u8) void {
        return bridge_core.seedStringStream(self, object, text);
    }
    pub fn installStreambufVirtuals(self: *Bridge, state: anytype, kind: cxx_object_model.Kind) bool {
        return bridge_core.installStreambufVirtuals(self, state, kind);
    }
    pub fn destroyIfstream(self: *Bridge, state: anytype, object: u64) void {
        return bridge_core.destroyIfstream(self, state, object);
    }
    pub fn destroyOfstream(self: *Bridge, state: anytype, object: u64) void {
        return bridge_core.destroyOfstream(self, state, object);
    }
    pub fn registerStackVtable(state: anytype, address: u64) void {
        return bridge_core.registerStackVtable(state, address);
    }
    pub fn forgetStackVtable(state: anytype, address: u64) void {
        return bridge_core.forgetStackVtable(state, address);
    }
    pub fn readLine(self: *Bridge, state: anytype, object: u64, string_object: u64, delimiter: u8) bool {
        return bridge_read.readLine(self, state, object, string_object, delimiter);
    }
    pub fn good(self: *Bridge, object: u64) bool {
        return bridge_read.good(self, object);
    }
    pub fn failed(self: *Bridge, object: u64) bool {
        return bridge_read.failed(self, object);
    }
    pub fn eof(self: *Bridge, object: u64) bool {
        return bridge_read.eof(self, object);
    }
    pub fn logSummary(self: *const Bridge) void {
        return bridge_core.logSummary(self);
    }
    pub fn destroy(self: *Bridge, state: anytype, object: u64) void {
        return bridge_core.destroy(self, state, object);
    }
    pub fn openCString(self: *Bridge, state: anytype, fs: anytype, object: u64, path_address: u64, mode: u64) u64 {
        return bridge_open.openCString(self, state, fs, object, path_address, mode);
    }
    pub fn openPath(self: *Bridge, state: anytype, fs: anytype, object: u64, address: u64, length: u64, mode: u64) u64 {
        return bridge_open.openPath(self, state, fs, object, address, length, mode);
    }
    pub fn openBytes(self: *Bridge, state: anytype, fs: anytype, object: u64, path: []const u8, mode: u64) u64 {
        return bridge_open.openBytes(self, state, fs, object, path, mode);
    }
    pub fn openProcSelfMaps(self: *Bridge, state: anytype, object: u64, mode: u64) u64 {
        return bridge_open.openProcSelfMaps(self, state, object, mode);
    }
    pub fn close(self: *Bridge, state: anytype, object: u64) u64 {
        return bridge_open.close(self, state, object);
    }
    pub fn isOpen(self: *Bridge, object: u64) bool {
        return bridge_open.isOpen(self, object);
    }
    pub fn readInto(self: *Bridge, state: anytype, object: u64, destination: u64, count: u64, set_istream_state: bool) i64 {
        return bridge_read.readInto(self, state, object, destination, count, set_istream_state);
    }
    pub fn gcount(self: *Bridge, object: u64) i64 {
        return bridge_read.gcount(self, object);
    }
    pub fn mirrorGuestGcount(self: *Bridge, state: anytype, istream: u64, result: i64) void {
        return bridge_read.mirrorGuestGcount(self, state, istream, result);
    }
    pub fn noteState(self: *Bridge, state: anytype, stream: *const Stream, bits: u32) void {
        return bridge_read.noteState(self, state, stream, bits);
    }
    pub fn seek(self: *Bridge, object: u64, offset: i64, direction: std.c.whence_t) i64 {
        return bridge_open.seek(self, object, offset, direction);
    }
    pub fn clearEofBitAfterSeek(self: *Bridge, state: anytype, object: u64, seek_result: i64) void {
        return bridge_open.clearEofBitAfterSeek(self, state, object, seek_result);
    }
    pub fn readByte(self: *Bridge, object: u64) i32 {
        return bridge_read.readByte(self, object);
    }
    pub fn peek(self: *Bridge, object: u64) i32 {
        return bridge_read.peek(self, object);
    }
    pub fn recordPatchTomlOp(self: *Bridge, stream: *Stream, operation: []const u8, offset: i64, bytes: []const u8) void {
        return bridge_patch.recordPatchTomlOp(self, stream, operation, offset, bytes);
    }
    pub fn tracePatchRead(self: *Bridge, stream: *Stream, operation: []const u8, offset: i64, bytes: []const u8) void {
        return bridge_patch.tracePatchRead(self, stream, operation, offset, bytes);
    }
    pub fn tracePatchSeek(self: *Bridge, stream: *Stream, operation: []const u8, offset: i64, direction: std.c.whence_t, result: i64) void {
        return bridge_patch.tracePatchSeek(self, stream, operation, offset, direction, result);
    }
    pub fn tracePatchTell(self: *Bridge, stream: *Stream, result: i64) void {
        return bridge_patch.tracePatchTell(self, stream, result);
    }
    pub fn findPatchTomlByteCount(self: *Bridge) ?u64 {
        return bridge_patch.findPatchTomlByteCount(self);
    }
    pub fn isActivePatchTomlIstream(self: *Bridge, object: u64) bool {
        return bridge_patch.isActivePatchTomlIstream(self, object);
    }
    pub fn dumpPatchTomlDiagnostics(self: *Bridge, reason: []const u8) void {
        return bridge_patch.dumpPatchTomlDiagnostics(self, reason);
    }
    pub fn dumpPatchPostParseDiagnosis(self: *Bridge, reason: []const u8) void {
        return bridge_patch.dumpPatchPostParseDiagnosis(self, reason);
    }
    pub fn logPatchSchema(self: *Bridge, stream: *const Stream, label: []const u8) void {
        return bridge_patch.logPatchSchema(self, stream, label);
    }
    pub fn logPatchSchemaValues(self: *Bridge, path: []const u8, schema: PatchTomlSchema, label: []const u8) void {
        return bridge_patch.logPatchSchemaValues(self, path, schema, label);
    }
    pub fn rememberPatchSchema(self: *Bridge, stream: *const Stream) void {
        return bridge_patch.rememberPatchSchema(self, stream);
    }
    pub fn latestPatchSchemaHasEmptyPatchSet(self: *const Bridge) bool {
        return bridge_patch.latestPatchSchemaHasEmptyPatchSet(self);
    }
    pub fn logEmptyPatchCompatibility(self: *const Bridge, action: []const u8) void {
        return bridge_patch.logEmptyPatchCompatibility(self, action);
    }
    pub fn logPatchSchemaValuesStatic(path: []const u8, schema: PatchTomlSchema, label: []const u8) void {
        return bridge_patch.logPatchSchemaValuesStatic(path, schema, label);
    }
    pub fn tracePatchTomlOpen(self: *Bridge, stream: *Stream, path: []const u8) void {
        return bridge_patch.tracePatchTomlOpen(self, stream, path);
    }
    pub fn tracePatchContext(self: *Bridge, fd: std.c.fd_t, path: []const u8, center: u64, label: []const u8) void {
        return bridge_patch.tracePatchContext(self, fd, path, center, label);
    }
    pub fn available(self: *Bridge, object: u64) i64 {
        return bridge_read.available(self, object);
    }
    pub fn setBuffer(self: *Bridge, object: u64, buffer: u64, size: u64) u64 {
        return bridge_write.setBuffer(self, object, buffer, size);
    }
    pub fn syntheticContent(self: *const Bridge, stream: *const Stream) ?[]const u8 {
        return bridge_open.syntheticContent(self, stream);
    }
    pub fn modeledStreamObjectForAddress(self: *Bridge, address: u64) ?u64 {
        return bridge_core.modeledStreamObjectForAddress(self, address);
    }
    pub fn ensure(self: *Bridge, object: u64) ?*Stream {
        return bridge_core.ensure(self, object);
    }
    pub fn setOwnership(self: *Bridge, stream: *Stream, owner_object: u64, stream_object: u64, ios_object: u64) void {
        return bridge_core.setOwnership(self, stream, owner_object, stream_object, ios_object);
    }
    pub fn ownsAddress(stream: *const Stream, address: u64) bool {
        return bridge_core.ownsAddress(stream, address);
    }
    pub fn findOwned(self: *Bridge, address: u64) ?*Stream {
        return bridge_core.findOwned(self, address);
    }
    pub fn resolveRdbuf(self: *Bridge, state: anytype, object: u64) u64 {
        return bridge_core.resolveRdbuf(self, state, object);
    }
    pub fn find(self: *Bridge, object: u64) ?*Stream {
        return bridge_core.find(self, object);
    }
    pub fn findFlexible(self: *Bridge, object: u64) ?*Stream {
        return bridge_core.findFlexible(self, object);
    }
    pub fn findAny(self: *Bridge, object: u64) ?*Stream {
        return bridge_core.findAny(self, object);
    }
};

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
