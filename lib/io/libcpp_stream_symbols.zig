const std = @import("std");

/// Synthetic thread-handle window shared with the pthread runtime's handle
/// allocator (see the matching values there): the current-thread sentinel,
/// the base of the 0x10-strided synthetic handles, and the idle-callback
/// range. `displayThreadId` maps raw guest thread ids into small display
/// lanes using exactly these bounds.
pub const CURRENT_THREAD_HANDLE: u64 = 0x7FFF_1000;
pub const SYNTHETIC_THREAD_BASE: u64 = 0x7FFF_2000;
pub const IDLE_CALLBACK_HANDLE_BASE: u64 = 0xFFFF_F900_0000_0000;

pub fn normalizeSymbol(symbol: []const u8) []const u8 {
    if (symbol.len != 0 and symbol[0] == '_') return symbol[1..];
    return symbol;
}

pub fn selectStreambufArgument(state: anytype) u64 {
    // The libc++ C2 base constructor carries a hidden VTT in RSI and moves the
    // declared streambuf argument to RDX. A tiny RSI (the logger showed 0x8)
    // is never a valid object pointer even in test-backed address spaces.
    if (state.regs.rsi >= 0x1000 and state.guestMemoryConst(state.regs.rsi, 8) != null) return state.regs.rsi;
    if (state.regs.rdx != 0 and state.guestMemoryConst(state.regs.rdx, 8) != null) return state.regs.rdx;
    return 0;
}

pub fn isBasicOstreamConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEEC2") != null;
}

pub fn isBasicIstreamConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_istreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_istreamIcNS_11char_traitsIcEEEC2") != null;
}

pub fn isBasicIostreamConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_iostreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_iostreamIcNS_11char_traitsIcEEEC2") != null;
}

pub fn isBasicOstreamDestructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEED1") != null or
        std.mem.indexOf(u8, name, "basic_ostreamIcNS_11char_traitsIcEEED2") != null;
}

pub fn isStringStreamDestructor(name: []const u8) bool {
    const family = std.mem.indexOf(u8, name, "basic_ostringstream") != null or
        std.mem.indexOf(u8, name, "basic_istringstream") != null or
        std.mem.indexOf(u8, name, "basic_stringstream") != null;
    return family and (std.mem.indexOf(u8, name, "D1Ev") != null or std.mem.indexOf(u8, name, "D2Ev") != null);
}

pub fn isStringStreamConstructor(name: []const u8) bool {
    const family = std.mem.indexOf(u8, name, "basic_ostringstream") != null or
        std.mem.indexOf(u8, name, "basic_istringstream") != null or
        std.mem.indexOf(u8, name, "basic_stringstream") != null;
    return family and (std.mem.indexOf(u8, name, "C1") != null or std.mem.indexOf(u8, name, "C2") != null);
}

pub fn isStringStreamTextConstructor(name: []const u8) bool {
    return isStringStreamConstructor(name) and
        std.mem.indexOf(u8, name, "ERKNS_12basic_string") != null;
}

pub fn numericBaseForManipulator(name: []const u8) ?u8 {
    if (std.mem.eql(u8, name, "_ZNSt3__13decB7v160006ERNS_8ios_baseE")) return 10;
    if (std.mem.eql(u8, name, "_ZNSt3__13hexB7v160006ERNS_8ios_baseE")) return 16;
    if (std.mem.eql(u8, name, "_ZNSt3__13octB7v160006ERNS_8ios_baseE")) return 8;
    return null;
}

pub fn isCharacterReferenceExtraction(name: []const u8) bool {
    return std.mem.eql(
        u8,
        name,
        "_ZNSt3__1rsB7v160006IcNS_11char_traitsIcEEEERNS_13basic_istreamIT_T0_EES7_RS4_",
    );
}

pub fn characterArrayCapacity(name: []const u8) ?usize {
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

pub fn isFormattedWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\n' or byte == '\t' or byte == '\r' or byte == '\x0b' or byte == '\x0c';
}

pub fn isDigitForBase(byte: u8, base: u8) bool {
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

pub fn isBasicFilebufConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_filebufIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_filebufIcNS_11char_traitsIcEEEC2") != null;
}

pub fn isBasicStreambufConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEEC2") != null;
}

fn isBasicIosMethod(name: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_iosIcNS_11char_traitsIcEEE") != null and
        std.mem.indexOf(u8, name, marker) != null;
}

pub fn isBasicIosInit(name: []const u8) bool {
    return isBasicIosMethod(name, "4initE");
}

pub fn isBasicIosRdbuf(name: []const u8) bool {
    return isBasicIosMethod(name, "5rdbuf");
}

pub fn isBasicStreambufPubimbue(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEE8pubimbue") != null;
}

pub fn isBasicStreambufImbue(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_streambufIcNS_11char_traitsIcEEE5imbue") != null;
}

pub fn isBasicIosRdstate(name: []const u8) bool {
    return isBasicIosMethod(name, "7rdstate");
}

pub fn isBasicIosClear(name: []const u8) bool {
    return isBasicIosMethod(name, "5clearE");
}

pub fn isBasicIosSetstate(name: []const u8) bool {
    return isBasicIosMethod(name, "8setstateE");
}

pub fn isBasicIosGood(name: []const u8) bool {
    return isBasicIosMethod(name, "4good");
}

pub fn isBasicIosFail(name: []const u8) bool {
    return isBasicIosMethod(name, "4fail");
}

pub fn isBasicIosEof(name: []const u8) bool {
    return isBasicIosMethod(name, "3eof");
}

pub fn isBasicIosBool(name: []const u8) bool {
    return isBasicIosMethod(name, "cvb");
}

pub fn isThreadIdInsertion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostream") != null and
        (std.mem.indexOf(u8, name, "NS_6thread2idE") != null or
            std.mem.indexOf(u8, name, "NS_11__thread_idE") != null or
            (std.mem.indexOf(u8, name, "thread") != null and std.mem.indexOf(u8, name, "idE") != null));
}

pub fn isPointerInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEPKv");
}

pub fn isCStringInsertion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_ostream") != null and
        std.mem.indexOf(u8, name, "PKc") != null and
        std.mem.indexOf(u8, name, "ls") != null;
}

pub fn isIntegerInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEb") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEi") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEj") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEl") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEm") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEx") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEy");
}

pub fn isSignedIntegerInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEi") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEl") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEx");
}

/// basic_ostream::operator<<(double). Imported by the Xenia fork and currently
/// unhandled; render it so a floating-point print cannot fall through to an
/// unresolved import.
pub fn isDoubleInsertion(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEd");
}

/// basic_ostream::operator<<(ostream&(*)(ostream&)) / (ios_base&(*)(ios_base&)).
/// Mangled member forms contain `ls` plus a function-pointer parameter that
/// returns a reference to the stream (`PFRS`) or to ios_base (`PFRNS`).
pub fn isOstreamManipulatorInsertion(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "basic_ostream") == null) return false;
    if (std.mem.indexOf(u8, name, "ls") == null) return false;
    return std.mem.indexOf(u8, name, "PFRS") != null or std.mem.indexOf(u8, name, "PFRNS") != null;
}

/// The std::endl / std::flush / std::ends manipulator functions themselves.
/// Length-prefixed mangling: `_ZNSt3__14endl...`, `_ZNSt3__15flush...`,
/// `_ZNSt3__14ends...` — the digit prefix is the identifier length.
pub fn isStreamManipulator(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "basic_ostream") == null) return false;
    return std.mem.indexOf(u8, name, "4endl") != null or
        std.mem.indexOf(u8, name, "5flush") != null or
        std.mem.indexOf(u8, name, "4ends") != null;
}

/// Classify a manipulator symbol name into a character to append, or null for
/// flush-only manipulators. std::endl appends '\n', std::ends appends the null
/// terminator, std::flush has no model state to flush (writes are unbuffered).
pub fn manipulatorAppend(name: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, name, "4endl") != null) return "\n";
    if (std.mem.indexOf(u8, name, "4ends") != null) return "\x00";
    return null;
}

pub fn manipulatorNumericBase(name: []const u8) ?u8 {
    if (std.mem.indexOf(u8, name, "3dec") != null) return 10;
    if (std.mem.indexOf(u8, name, "3hex") != null) return 16;
    if (std.mem.indexOf(u8, name, "3oct") != null) return 8;
    return null;
}

pub fn isStringbufStr(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv") != null;
}

pub fn isStringStreamStr(name: []const u8) bool {
    const family = std.mem.indexOf(u8, name, "basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEE3str") != null or
        std.mem.indexOf(u8, name, "basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEE3str") != null;
    return family and std.mem.indexOf(u8, name, "Ev") != null;
}

pub fn displayThreadId(raw_id: u64) u64 {
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

pub fn isBaseDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__19basic_iosIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED2Ev") or
        std.mem.eql(u8, name, "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEED1Ev");
}

pub fn isIfstreamDefaultConstructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC2Ev");
}

pub fn isIfstreamCStringConstructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1EPKcj") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC2EPKcj");
}

pub fn isIfstreamFilesystemPathConstructor(name: []const u8) bool {
    return (std.mem.indexOf(u8, name, "basic_ifstreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, name, "basic_ifstreamIcNS_11char_traitsIcEEEC2") != null) and
        std.mem.indexOf(u8, name, "__fs10filesystem4path") != null;
}

pub fn isIfstreamDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED2Ev");
}

pub fn isOfstreamDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, "_ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED1Ev") or
        std.mem.eql(u8, name, "_ZNSt3__114basic_ofstreamIcNS_11char_traitsIcEEED2Ev");
}

pub fn seekDirection(value: u64) std.c.whence_t {
    return switch (value) {
        0 => std.c.SEEK.SET,
        1 => std.c.SEEK.CUR,
        2 => std.c.SEEK.END,
        else => std.c.SEEK.SET,
    };
}
