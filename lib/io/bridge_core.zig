const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const cxx_object_model = @import("cxx_abi").cxx_object_model;
const machoCapturePrint = @import("event_log").machoCapturePrint;
const types = @import("bridge_types.zig");
const BASIC_IOS_OFFSET_IN_IFSTREAM = types.BASIC_IOS_OFFSET_IN_IFSTREAM;
const FILEBUF_OFFSET_IN_IFSTREAM = types.FILEBUF_OFFSET_IN_IFSTREAM;
const FILEBUF_OFFSET_IN_OFSTREAM = types.FILEBUF_OFFSET_IN_OFSTREAM;
const Outcome = types.Outcome;
const STANDARD_STREAM_BLOCK_SIZE = types.STANDARD_STREAM_BLOCK_SIZE;
const STANDARD_STREAM_FILEBUF_OFFSET = types.STANDARD_STREAM_FILEBUF_OFFSET;
const STRINGSTREAM_BUFFER_OFFSET = types.STRINGSTREAM_BUFFER_OFFSET;
const STRINGSTREAM_IOS_OFFSET = types.STRINGSTREAM_IOS_OFFSET;
const STRINGSTREAM_MIN_SIZE = types.STRINGSTREAM_MIN_SIZE;
const STRINGSTREAM_OSTREAM_OFFSET = types.STRINGSTREAM_OSTREAM_OFFSET;
const STRINGSTREAM_TEXT_CAPACITY = types.STRINGSTREAM_TEXT_CAPACITY;
const StandardStreamKind = types.StandardStreamKind;
const Stream = types.Stream;
const closeStream = types.closeStream;
const stream_symbols = @import("libcpp_stream_symbols.zig");
const characterArrayCapacity = stream_symbols.characterArrayCapacity;
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
const isDoubleInsertion = stream_symbols.isDoubleInsertion;
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
const normalizeSymbol = stream_symbols.normalizeSymbol;
const numericBaseForManipulator = stream_symbols.numericBaseForManipulator;
const seekDirection = stream_symbols.seekDirection;
const selectStreambufArgument = stream_symbols.selectStreambufArgument;

pub fn deinit(self: anytype) void {
    for (&self.streams) |*stream| closeStream(stream);
    self.object_model.reset();
    self.* = .{};
}

pub fn dispatch(self: anytype, state: anytype, fs: anytype, symbol: []const u8) ?Outcome {
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
        // `compat` is a *field* of the process state, so the presence test
        // has to be `@hasField`. Written as `@hasDecl` it compiled, always
        // evaluated false, and every locale initialisation in this file —
        // all six of them — was silently skipped for the whole life of the
        // code, leaving each constructed stream's locale slot zero.
        if (@hasField(@TypeOf(state.*), "compat")) {
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
        if (@hasField(@TypeOf(state.*), "compat")) {
            _ = state.compat.initLocale(state, state.regs.rdi + BASIC_IOS_OFFSET_IN_IFSTREAM + cxx_object_model.stream_layout.locale_offset, null);
        }
        return .{ .handled = state.regs.rdi };
    }
    if (isIfstreamCStringConstructor(name)) {
        if (!self.constructIfstream(state, state.regs.rdi)) return null;
        if (@hasField(@TypeOf(state.*), "compat")) {
            _ = state.compat.initLocale(state, state.regs.rdi + BASIC_IOS_OFFSET_IN_IFSTREAM + cxx_object_model.stream_layout.locale_offset, null);
        }
        _ = self.openCString(state, fs, state.regs.rdi + FILEBUF_OFFSET_IN_IFSTREAM, state.regs.rsi, state.regs.rdx);
        return .{ .handled = state.regs.rdi };
    }
    if (isIfstreamFilesystemPathConstructor(name)) {
        if (!self.constructIfstream(state, state.regs.rdi)) return null;
        if (@hasField(@TypeOf(state.*), "compat")) {
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

pub fn handlePubsetbuf(self: anytype, object: u64, buffer: u64, size: u64) u64 {
    return self.setBuffer(object, buffer, size);
}

/// Executes a typed virtual from Rosette's synthetic basic_streambuf
/// vtable. The vtable owns only addresses; all stream state and I/O remain
/// centralized here so direct imports and virtual calls cannot diverge.
pub fn dispatchStreambufVirtual(
    self: anytype,
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

pub fn constructIfstream(self: anytype, state: anytype, object: u64) bool {
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

pub fn constructOstream(self: anytype, state: anytype, object: u64, streambuf: u64) bool {
    if (streambuf == 0 or state.guestMemoryConst(streambuf, 8) == null) {
        self.rejected +|= 1;
        return false;
    }
    if (!self.object_model.initializeStream(state, .basic_ostream, object, streambuf)) {
        self.rejected +|= 1;
        return false;
    }
    if (@hasField(@TypeOf(state.*), "compat")) {
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
pub fn ensureStandardStream(self: anytype, state: anytype, kind: StandardStreamKind) ?u64 {
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

pub fn constructStandardStream(self: anytype, state: anytype, fd: i32) ?u64 {
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
pub fn constructFilebuf(self: anytype, state: anytype, object: u64) bool {
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

pub fn stringbufToString(self: anytype, state: anytype, stringbuf: u64, output: u64) bool {
    const stream = self.findFlexible(stringbuf) orelse return false;
    return compat_runtime.initLibcppStringFromSlice(state, output, stream.string_storage[0..stream.string_length]);
}

pub fn streamObjectToString(self: anytype, state: anytype, object: u64, output: u64) bool {
    const stream = self.streamForOstream(state, object) orelse return false;
    return compat_runtime.initLibcppStringFromSlice(state, output, stream.string_storage[0..stream.string_length]);
}

pub fn streamForOstream(self: anytype, state: anytype, object: u64) ?*Stream {
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

pub fn resetStringBuffer(_: anytype, stream: *Stream) void {
    stream.string_length = 0;
    stream.string_truncated = false;
    @memset(&stream.string_storage, 0);
}

pub fn constructBaseStream(self: anytype, state: anytype, kind: cxx_object_model.Kind, object: u64, streambuf: u64) bool {
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

pub fn constructStringStream(self: anytype, state: anytype, object: u64) bool {
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
    if (@hasField(@TypeOf(state.*), "compat")) {
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

pub fn seedStringStream(self: anytype, object: u64, text: []const u8) void {
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

pub fn installStreambufVirtuals(self: anytype, state: anytype, kind: cxx_object_model.Kind) bool {
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

pub fn destroyIfstream(self: anytype, state: anytype, object: u64) void {
    self.destroy(state, object + FILEBUF_OFFSET_IN_IFSTREAM);
}

pub fn destroyOfstream(self: anytype, state: anytype, object: u64) void {
    self.destroy(state, object + FILEBUF_OFFSET_IN_OFSTREAM);
}

/// Register a streambuf's vtable with the stack vtable registry so that
/// corruption (e.g. heap reuse overwriting the vptr) can be recovered.
/// Uses an anonymous struct literal for provenance to avoid importing
/// vtable types (io module doesn't include vtable in its dep tree).
pub fn registerStackVtable(state: anytype, address: u64) void {
    if (comptime !@hasField(@TypeOf(state.*), "vtable_stack_registry")) return;
    const vptr = state.read64(address);
    state.vtable_stack_registry.register(address, vptr, .{
        .writer_rip = if (@hasField(@TypeOf(state.*), "regs")) state.regs.rip else 0,
        .writer_step = if (@hasField(@TypeOf(state.*), "regs")) state.executed_steps else 0,
        .writer_thread = if (@hasField(@TypeOf(state.*), "regs")) state.active_guest_thread else 0,
    });
}

/// Forget a streambuf's vtable entry when the stream is destroyed.
pub fn forgetStackVtable(state: anytype, address: u64) void {
    if (comptime !@hasField(@TypeOf(state.*), "vtable_stack_registry")) return;
    state.vtable_stack_registry.forget(address);
}

pub fn logSummary(self: anytype) void {
    var live: usize = 0;
    for (self.streams) |stream| {
        if (stream.active and (stream.fd >= 0 or stream.synthetic_proc_maps)) live += 1;
    }
    machoCapturePrint(
        "macho-processor: libc++ stream bridge: constructors={d} open={d} open_failed={d} close={d} read={d} seek={d} peek={d} buffers={d} base_dtors={d} ofstream_dtors={d} rdbuf_aliases={d} modeled_imbues={d} virtual_calls={d} writes={d} short_writes={d} live={d} rejected={d}\n",
        .{ self.constructors, self.opens, self.open_failures, self.closes, self.reads, self.seeks, self.peeks, self.buffer_changes, self.base_destructors, self.ofstream_destructors, self.rdbuf_alias_resolutions, self.modeled_streambuf_imbues, self.modeled_streambuf_virtual_calls, self.modeled_streambuf_writes, self.modeled_streambuf_short_writes, live, self.rejected },
    );
}

pub fn destroy(self: anytype, state: anytype, object: u64) void {
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

pub fn modeledStreamObjectForAddress(self: anytype, address: u64) ?u64 {
    const stream = self.findOwned(address) orelse return null;
    return stream.object;
}

pub fn ensure(self: anytype, object: u64) ?*Stream {
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

pub fn setOwnership(self: anytype, stream: *Stream, owner_object: u64, stream_object: u64, ios_object: u64) void {
    _ = self;
    stream.owner_object = owner_object;
    stream.stream_object = stream_object;
    stream.ios_object = ios_object;
}

pub fn ownsAddress(stream: *const Stream, address: u64) bool {
    if (!stream.active or address == 0) return false;
    return address == stream.object or
        (stream.owner_object != 0 and address == stream.owner_object) or
        (stream.stream_object != 0 and address == stream.stream_object) or
        (stream.ios_object != 0 and address == stream.ios_object);
}

pub fn findOwned(self: anytype, address: u64) ?*Stream {
    for (&self.streams) |*stream| {
        if (ownsAddress(stream, address)) return stream;
    }
    return null;
}

pub fn resolveRdbuf(self: anytype, state: anytype, object: u64) u64 {
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

pub fn find(self: anytype, object: u64) ?*Stream {
    for (&self.streams) |*stream| {
        if (stream.active and stream.object == object) return stream;
    }
    return null;
}

pub fn findFlexible(self: anytype, object: u64) ?*Stream {
    if (self.findOwned(object)) |stream| return stream;
    if (self.find(object + FILEBUF_OFFSET_IN_IFSTREAM)) |stream| return stream;
    for (&self.streams) |*stream| {
        if (!stream.active or stream.object < FILEBUF_OFFSET_IN_IFSTREAM) continue;
        const ifstream = stream.object - FILEBUF_OFFSET_IN_IFSTREAM;
        if (object == ifstream or object == ifstream + 424) return stream;
    }
    return null;
}

pub fn findAny(self: anytype, object: u64) ?*Stream {
    for (&self.streams) |*stream| {
        if (stream.object == object or
            stream.owner_object == object or
            stream.stream_object == object or
            stream.ios_object == object) return stream;
    }
    return null;
}
