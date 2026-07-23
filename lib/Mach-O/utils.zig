const std = @import("std");
const builtin = @import("builtin");
const x64_decoder = @import("x64_decoder");
const types = @import("types.zig");
const constants = @import("constants.zig");
const decoder = @import("decoder.zig");
const machoCapturePrint = @import("event_log.zig").machoCapturePrint;

const Regs = x64_decoder.Regs;
const DecodedInsn = x64_decoder.DecodedInsn;
const Size = x64_decoder.OperandSize;
const Op = x64_decoder.Op;
const bitScan = x64_decoder.bitScan;
const crc32cAccumulator = x64_decoder.crc32cAccumulator;

const BulkConstructionRange = types.BulkConstructionRange;
const GuestSignalFrame = types.GuestSignalFrame;
const GuestSignalAction = types.GuestSignalAction;
const ProfileAccountStage = types.ProfileAccountStage;
const TomlCodepointRepair = types.TomlCodepointRepair;
const IMPORT_ROUTE_CACHE_SIZE = constants.IMPORT_ROUTE_CACHE_SIZE;
const DARWIN_SIGINFO_SIZE = constants.DARWIN_SIGINFO_SIZE;
const DARWIN_UCONTEXT_SIZE = constants.DARWIN_UCONTEXT_SIZE;
const DARWIN_MCONTEXT_SIZE = constants.DARWIN_MCONTEXT_SIZE;
const DARWIN_SIGACTION_SIZE = constants.DARWIN_SIGACTION_SIZE;
const GUEST_SIGNAL_ACTION_COUNT = constants.GUEST_SIGNAL_ACTION_COUNT;
const TOML_CODEPOINT_STRIDE = constants.TOML_CODEPOINT_STRIDE;
const GUEST_SIGILL = constants.GUEST_SIGILL;
const PROFILE_ENCRYPTED_ACCOUNT_BYTES = constants.PROFILE_ENCRYPTED_ACCOUNT_BYTES;
const SA_SIGINFO = constants.SA_SIGINFO;

const decodeInsn = decoder.decodeInsn;

pub fn nextPrime(n: u64) u64 {
    if (n <= 2) return 2;
    var candidate = n;
    if (candidate % 2 == 0) candidate += 1;
    while (true) {
        var is_prime = true;
        var i: u64 = 3;
        while (i <= candidate / i) {
            if (candidate % i == 0) {
                is_prime = false;
                break;
            }
            i += 2;
        }
        if (is_prime) return candidate;
        candidate += 2;
    }
}

pub fn alignDown(value: u64, alignment: u64) u64 {
    return value & ~(alignment - 1);
}

pub fn importRouteCacheIndex(stub_address: u64) usize {
    const mixed = stub_address ^ (stub_address >> 17) ^ (stub_address >> 37);
    return @intCast(mixed & (IMPORT_ROUTE_CACHE_SIZE - 1));
}

pub fn calculateBulkConstructionRange(begin: u64, end: u64, capacity_end: u64, count: u64, element_size: u64) ?BulkConstructionRange {
    if (begin == 0 or end < begin or capacity_end < end or element_size == 0) return null;
    const byte_count = std.math.mul(u64, count, element_size) catch return null;
    const new_end = std.math.add(u64, end, byte_count) catch return null;
    if (new_end > capacity_end) return null;
    return .{ .byte_count = byte_count, .new_end = new_end };
}

test "bulk construction range validates capacity and overflow" {
    const range = calculateBulkConstructionRange(0x1000, 0x1800, 0x3000, 128, 16).?;
    try std.testing.expectEqual(@as(u64, 2048), range.byte_count);
    try std.testing.expectEqual(@as(u64, 0x2000), range.new_end);
    try std.testing.expectEqual(@as(?BulkConstructionRange, null), calculateBulkConstructionRange(0x1000, 0x1800, 0x1FFF, 128, 16));
    try std.testing.expectEqual(@as(?BulkConstructionRange, null), calculateBulkConstructionRange(0x1000, std.math.maxInt(u64) - 7, std.math.maxInt(u64), 1, 16));
}

test "import route cache index is stable and bounded" {
    const index = importRouteCacheIndex(0x133_147E);
    try std.testing.expect(index < IMPORT_ROUTE_CACHE_SIZE);
    try std.testing.expectEqual(index, importRouteCacheIndex(0x133_147E));
}

pub fn mappedOffset(mem_base: u64, mem_size: u64, mapped_min: u64, address: u64) ?u64 {
    // Check for near-null or negative addresses (high bit set in 64-bit, or very small positive addresses)
    const near_null = (address & 0x8000_0000_0000_0000) != 0 or address < 0x1000;
    if (near_null or address < mapped_min or address < mem_base) return null;
    const offset = address - mem_base;
    return if (offset < mem_size) offset else null;
}

pub fn applyBindingAddend(address: u64, addend: i64) ?u64 {
    const adjusted = @as(i128, address) + @as(i128, addend);
    if (adjusted < 0 or adjusted > std.math.maxInt(u64)) return null;
    return @intCast(adjusted);
}

test "dyld binding addends are checked instead of wrapping" {
    try std.testing.expectEqual(@as(?u64, 0x1020), applyBindingAddend(0x1000, 0x20));
    try std.testing.expectEqual(@as(?u64, 0x0ff0), applyBindingAddend(0x1000, -0x10));
    try std.testing.expectEqual(@as(?u64, null), applyBindingAddend(0, -1));
    try std.testing.expectEqual(@as(?u64, null), applyBindingAddend(std.math.maxInt(u64), 1));
}

pub fn parseFopenFlags(mode: []const u8) ?i32 {
    if (mode.len == 0) return null;
    var flags: i32 = 0;
    switch (mode[0]) {
        'r' => flags = 0x0000,
        'w' => flags = 0x0001 | 0x0200 | 0x0400,
        'a' => flags = 0x0001 | 0x0200 | 0x0008,
        else => return null,
    }
    if (std.mem.indexOfScalar(u8, mode, '+') != null) {
        flags &= ~@as(i32, 0x0003);
        flags |= 0x0002;
    }
    return flags;
}

pub fn guestSignalIndex(raw_signal: u64) ?usize {
    if (raw_signal == 0 or raw_signal >= GUEST_SIGNAL_ACTION_COUNT) return null;
    return @intCast(raw_signal);
}

pub fn signalFailureResult() u64 {
    return @bitCast(@as(i64, -1));
}

pub fn signalHandlerMadeProgress(frame: GuestSignalFrame, resume_rip: u64, fault_bytes: []const u8) bool {
    if (resume_rip != frame.fault_rip) return true;
    if (frame.signal != GUEST_SIGILL) return false;
    if (fault_bytes.len < 2) return false;
    return fault_bytes[0] != 0x0F or fault_bytes[1] != 0x0B;
}

pub fn isAsciiBytes(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte & 0x80 != 0) return false;
    }
    return true;
}

pub fn profileIdFromUserDevice(message: []const u8) ?[]const u8 {
    const marker = "User_";
    const marker_index = std.mem.indexOf(u8, message, marker) orelse return null;
    const start = marker_index + marker.len;
    const relative_end = std.mem.indexOfScalar(u8, message[start..], ':') orelse return null;
    const profile_id = message[start .. start + relative_end];
    if (profile_id.len != 16) return null;
    for (profile_id) |character| {
        if (!std.ascii.isHex(character)) return null;
    }
    return profile_id;
}

pub fn classifyProfileDismountCaller(symbol_name: []const u8, offset: u64) ?ProfileAccountStage {
    if (std.mem.indexOf(u8, symbol_name, "ProfileManager11LoadAccount") == null) return null;
    // Current Xenia has three DismountProfile call sites in LoadAccount:
    // open validation, short-read validation, and post-decryption cleanup.
    if (offset >= 0x700) return .decrypted;
    if (offset >= 0x600) return .short_read;
    return .open_failed;
}

test "profile device diagnostic extracts only a valid 16 digit XUID" {
    try std.testing.expectEqualStrings(
        "E0300000728022C4",
        profileIdFromUserDevice("HostPathDevice::ResolvePath(User_E0300000728022C4:)").?,
    );
    try std.testing.expect(profileIdFromUserDevice("HostPathDevice::ResolvePath(User_short:)") == null);
    try std.testing.expect(profileIdFromUserDevice("HostPathDevice::ResolvePath(User_E0300000728022CZ:)") == null);
}

test "profile dismount classifier distinguishes cleanup from load failures" {
    const load_symbol = "__ZN2xe6kernel3xam14ProfileManager11LoadAccountEy";
    try std.testing.expectEqual(@as(?ProfileAccountStage, .open_failed), classifyProfileDismountCaller(load_symbol, 0x483));
    try std.testing.expectEqual(@as(?ProfileAccountStage, .short_read), classifyProfileDismountCaller(load_symbol, 0x646));
    try std.testing.expectEqual(@as(?ProfileAccountStage, .decrypted), classifyProfileDismountCaller(load_symbol, 0x762));
    try std.testing.expect(classifyProfileDismountCaller("OtherFunction", 0x762) == null);
    try std.testing.expectEqual(@as(u64, 404), PROFILE_ENCRYPTED_ACCOUNT_BYTES);
}

pub fn repairAsciiCodepointBlock(storage: []u8, expected: []const u8) TomlCodepointRepair {
    var report = TomlCodepointRepair{};
    const available = @min(expected.len, storage.len / TOML_CODEPOINT_STRIDE);
    for (expected[0..available], 0..) |byte, index| {
        const start = index * TOML_CODEPOINT_STRIDE;
        const scalar = std.mem.readInt(u32, storage[start..][0..4], .little);
        const raw = storage[start + 4];
        if (scalar != byte or raw != byte) {
            if (report.first_bad_index == null) {
                report.first_bad_index = @intCast(index);
                report.first_bad_scalar = scalar;
                report.first_bad_raw = raw;
                report.first_expected = byte;
            }
            if (scalar != byte) {
                std.mem.writeInt(u32, storage[start..][0..4], byte, .little);
                report.scalar_repairs +|= 1;
            }
            if (raw != byte) {
                storage[start + 4] = byte;
                report.raw_repairs +|= 1;
            }
        }
    }
    return report;
}

pub fn isPatchDbNullIsArraySequence(bytes: []const u8) bool {
    const expected = [_]u8{
        0x48, 0x8B, 0x07, // mov rax, [rdi]
        0xFF, 0x50, 0x38, // call [rax+0x38] (node::is_array)
        0xA8, 0x01, // test al, 1
        0x0F, 0x85, 0x18, 0x00, 0x00, 0x00, // jne array path
    };
    return std.mem.eql(u8, bytes, &expected);
}

test "PatchDB empty-patch compatibility recognizes only the null virtual-call sequence" {
    const sequence = [_]u8{ 0x48, 0x8B, 0x07, 0xFF, 0x50, 0x38, 0xA8, 0x01, 0x0F, 0x85, 0x18, 0x00, 0x00, 0x00 };
    try std.testing.expect(isPatchDbNullIsArraySequence(&sequence));
    var changed = sequence;
    changed[5] = 0x40;
    try std.testing.expect(!isPatchDbNullIsArraySequence(&changed));
}

pub fn threeOperandImulResult(regs: *const Regs, instruction: DecodedInsn, size: Size) u64 {
    return x64_decoder.regVal(regs, instruction.src_reg, size) *% instruction.imm;
}

test "three-operand IMUL uses the source register rather than the old destination" {
    var regs = Regs{};
    x64_decoder.setReg(&regs, .al_ax_eax_rax, .bits64, 99);
    x64_decoder.setReg(&regs, .cl_cx_ecx_rcx, .bits64, 3);

    const instruction = DecodedInsn{
        .op = .imul_reg64_reg64_imm8,
        .dst_reg = .al_ax_eax_rax,
        .src_reg = .cl_cx_ecx_rcx,
        .imm = 24,
    };

    try std.testing.expectEqual(@as(u64, 72), threeOperandImulResult(&regs, instruction, .bits64));
}

test "TOML ASCII codepoint integrity repair restores scalar and raw bytes" {
    const expected = "A\n\"";
    var storage = [_]u8{0} ** (expected.len * TOML_CODEPOINT_STRIDE);
    for (expected, 0..) |byte, index| {
        const start = index * TOML_CODEPOINT_STRIDE;
        std.mem.writeInt(u32, storage[start..][0..4], byte, .little);
        storage[start + 4] = byte;
    }
    std.mem.writeInt(u32, storage[TOML_CODEPOINT_STRIDE..][0..4], 0, .little);
    storage[TOML_CODEPOINT_STRIDE + 4] = 0xff;

    const report = repairAsciiCodepointBlock(&storage, expected);
    try std.testing.expectEqual(@as(u8, 1), report.scalar_repairs);
    try std.testing.expectEqual(@as(u8, 1), report.raw_repairs);
    try std.testing.expectEqual(@as(?u8, 1), report.first_bad_index);
    try std.testing.expectEqual(@as(u32, '\n'), std.mem.readInt(u32, storage[TOML_CODEPOINT_STRIDE..][0..4], .little));
    try std.testing.expectEqual(@as(u8, '\n'), storage[TOML_CODEPOINT_STRIDE + 4]);
}

/// A guest handler can observe a SIGILL/UD2 assertion and return without
/// editing the saved machine context.  Re-entering the same UD2 would only
/// redeliver the signal, so treat that acknowledged assertion as resolved.
pub fn resolveGuestSignalReturn(frame: GuestSignalFrame, resume_rip: u64, fault_bytes: []const u8) ?u64 {
    if (signalHandlerMadeProgress(frame, resume_rip, fault_bytes)) return resume_rip;
    if (frame.signal != GUEST_SIGILL or fault_bytes.len < 2) return null;
    if (fault_bytes[0] != 0x0F or fault_bytes[1] != 0x0B) return null;
    return frame.fault_rip +% frame.instruction_len;
}

pub fn readDarwinSigaction(bytes: []const u8) ?GuestSignalAction {
    if (bytes.len < DARWIN_SIGACTION_SIZE) return null;
    return .{
        .handler = std.mem.readInt(u64, bytes[0..8], .little),
        .mask = std.mem.readInt(u32, bytes[8..12], .little),
        .flags = std.mem.readInt(u32, bytes[12..16], .little),
    };
}

pub fn writeDarwinSigaction(bytes: []u8, action: GuestSignalAction) void {
    if (bytes.len < DARWIN_SIGACTION_SIZE) return;
    std.mem.writeInt(u64, bytes[0..8], action.handler, .little);
    std.mem.writeInt(u32, bytes[8..12], action.mask, .little);
    std.mem.writeInt(u32, bytes[12..16], action.flags, .little);
}

pub fn writeDarwinSiginfo(bytes: []u8, signal: u8, signal_code: i32, fault_address: u64) void {
    if (bytes.len < DARWIN_SIGINFO_SIZE) return;
    @memset(bytes[0..DARWIN_SIGINFO_SIZE], 0);
    std.mem.writeInt(i32, bytes[0..4], signal, .little);
    std.mem.writeInt(i32, bytes[8..12], signal_code, .little);
    std.mem.writeInt(u64, bytes[24..32], fault_address, .little); // si_addr
}

pub fn writeDarwinUcontext(bytes: []u8, mcontext: u64) void {
    if (bytes.len < DARWIN_UCONTEXT_SIZE) return;
    @memset(bytes[0..DARWIN_UCONTEXT_SIZE], 0);
    std.mem.writeInt(u64, bytes[40..48], DARWIN_MCONTEXT_SIZE, .little); // uc_mcsize
    std.mem.writeInt(u64, bytes[48..56], mcontext, .little); // uc_mcontext
}

pub fn writeDarwinMcontext(bytes: []u8, regs: Regs, trap_number: u16, error_code: u32, fault_address: u64) void {
    if (bytes.len < DARWIN_MCONTEXT_SIZE) return;
    @memset(bytes[0..DARWIN_MCONTEXT_SIZE], 0);
    std.mem.writeInt(u16, bytes[0..2], trap_number, .little);
    std.mem.writeInt(u32, bytes[4..8], error_code, .little);
    std.mem.writeInt(u64, bytes[8..16], fault_address, .little); // exception state faultvaddr
    const values = [_]u64{
        regs.rax, regs.rbx, regs.rcx, regs.rdx,    regs.rdi,                  regs.rsi,                  regs.rbp,
        regs.rsp, regs.r8,  regs.r9,  regs.r10,    regs.r11,                  regs.r12,                  regs.r13,
        regs.r14, regs.r15, regs.rip, regs.rflags, regs.segments.cs.selector, regs.segments.fs.selector, regs.segments.gs.selector,
    };
    for (values, 0..) |value, index| {
        const offset = 16 + index * @sizeOf(u64);
        std.mem.writeInt(u64, bytes[offset..][0..8], value, .little);
    }
}

pub fn readDarwinMcontext(bytes: []const u8, regs: *Regs) bool {
    if (bytes.len < DARWIN_MCONTEXT_SIZE) return false;
    const thread = bytes[16..][0 .. 21 * @sizeOf(u64)];
    regs.rax = std.mem.readInt(u64, thread[0..8], .little);
    regs.rbx = std.mem.readInt(u64, thread[8..16], .little);
    regs.rcx = std.mem.readInt(u64, thread[16..24], .little);
    regs.rdx = std.mem.readInt(u64, thread[24..32], .little);
    regs.rdi = std.mem.readInt(u64, thread[32..40], .little);
    regs.rsi = std.mem.readInt(u64, thread[40..48], .little);
    regs.rbp = std.mem.readInt(u64, thread[48..56], .little);
    regs.rsp = std.mem.readInt(u64, thread[56..64], .little);
    regs.r8 = std.mem.readInt(u64, thread[64..72], .little);
    regs.r9 = std.mem.readInt(u64, thread[72..80], .little);
    regs.r10 = std.mem.readInt(u64, thread[80..88], .little);
    regs.r11 = std.mem.readInt(u64, thread[88..96], .little);
    regs.r12 = std.mem.readInt(u64, thread[96..104], .little);
    regs.r13 = std.mem.readInt(u64, thread[104..112], .little);
    regs.r14 = std.mem.readInt(u64, thread[112..120], .little);
    regs.r15 = std.mem.readInt(u64, thread[120..128], .little);
    regs.rip = std.mem.readInt(u64, thread[128..136], .little);
    regs.rflags = @truncate(std.mem.readInt(u64, thread[136..144], .little));
    regs.segments.cs.selector = @truncate(std.mem.readInt(u64, thread[144..152], .little));
    regs.segments.fs.selector = @truncate(std.mem.readInt(u64, thread[152..160], .little));
    regs.segments.gs.selector = @truncate(std.mem.readInt(u64, thread[160..168], .little));
    return true;
}

test "Darwin sigaction and x86_64 mcontext preserve guest signal state" {
    var action_bytes = [_]u8{0} ** DARWIN_SIGACTION_SIZE;
    const expected_action = GuestSignalAction{ .handler = 0x1234, .mask = 0xA5, .flags = SA_SIGINFO };
    writeDarwinSigaction(&action_bytes, expected_action);
    const decoded_action = readDarwinSigaction(&action_bytes).?;
    try std.testing.expectEqual(expected_action.handler, decoded_action.handler);
    try std.testing.expectEqual(expected_action.mask, decoded_action.mask);
    try std.testing.expectEqual(expected_action.flags, decoded_action.flags);

    var original = Regs{ .rax = 1, .rbx = 2, .rcx = 3, .rdx = 4, .rdi = 5, .rsi = 6, .rbp = 7, .rsp = 8, .r8 = 9, .r9 = 10, .r10 = 11, .r11 = 12, .r12 = 13, .r13 = 14, .r14 = 15, .r15 = 16, .rip = 0xBEEF, .rflags = 0x202 };
    original.segments.cs.selector = 0x2B;
    original.segments.fs.selector = 0x53;
    original.segments.gs.selector = 0x5B;
    var mcontext = [_]u8{0} ** DARWIN_MCONTEXT_SIZE;
    writeDarwinMcontext(&mcontext, original, 6, 0, original.rip);
    var restored = Regs{};
    try std.testing.expect(readDarwinMcontext(&mcontext, &restored));
    try std.testing.expectEqual(original.rax, restored.rax);
    try std.testing.expectEqual(original.r15, restored.r15);
    try std.testing.expectEqual(original.rip, restored.rip);
    try std.testing.expectEqual(original.rflags, restored.rflags);
    try std.testing.expectEqual(original.segments.gs.selector, restored.segments.gs.selector);
}

test "Darwin SIGSEGV state exposes access violation address and write bit" {
    var siginfo = [_]u8{0} ** DARWIN_SIGINFO_SIZE;
    writeDarwinSiginfo(&siginfo, 11, 2, 0x7FC8_0700);
    try std.testing.expectEqual(@as(i32, 11), std.mem.readInt(i32, siginfo[0..4], .little));
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, siginfo[8..12], .little));
    try std.testing.expectEqual(@as(u64, 0x7FC8_0700), std.mem.readInt(u64, siginfo[24..32], .little));

    var mcontext = [_]u8{0} ** DARWIN_MCONTEXT_SIZE;
    const regs = Regs{ .rip = 0x1234 };
    writeDarwinMcontext(&mcontext, regs, 14, 3, 0x7FC8_0700);
    try std.testing.expectEqual(@as(u16, 14), std.mem.readInt(u16, mcontext[0..2], .little));
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, mcontext[4..8], .little));
    try std.testing.expectEqual(@as(u64, 0x7FC8_0700), std.mem.readInt(u64, mcontext[8..16], .little));
}

test "guest SIGILL return requires a changed RIP or patched UD2 bytes" {
    const frame = GuestSignalFrame{ .signal = GUEST_SIGILL, .instruction_len = 2, .fault_rip = 0x4000 };
    try std.testing.expect(signalHandlerMadeProgress(frame, 0x4002, &.{ 0x0F, 0x0B }));
    try std.testing.expect(signalHandlerMadeProgress(frame, 0x4000, &.{ 0x90, 0x90 }));
    try std.testing.expect(!signalHandlerMadeProgress(frame, 0x4000, &.{ 0x0F, 0x0B }));
}

test "toml++ ASCII fast path predicate accepts ASCII and rejects UTF-8 multibyte bytes" {
    try std.testing.expect(isAsciiBytes("title_name = \"Halo 3\""));
    try std.testing.expect(!isAsciiBytes(&.{ 0x74, 0xC3, 0xA9 }));
}

test "guest SIGILL handler return resolves an unchanged UD2 by advancing" {
    const ud2_frame = GuestSignalFrame{ .signal = GUEST_SIGILL, .instruction_len = 2, .fault_rip = 0x4000 };
    try std.testing.expectEqual(@as(?u64, 0x4002), resolveGuestSignalReturn(ud2_frame, 0x4000, &.{ 0x0F, 0x0B }));

    const other_signal = GuestSignalFrame{ .signal = 11, .instruction_len = 2, .fault_rip = 0x4000 };
    try std.testing.expectEqual(@as(?u64, null), resolveGuestSignalReturn(other_signal, 0x4000, &.{ 0x0F, 0x0B }));
}

pub fn alignUp(value: u64, alignment: u64) !u64 {
    const mask = alignment - 1;
    return (try std.math.add(u64, value, mask)) & ~mask;
}

pub const MachORunOptions = struct {
    path: []const u8,
    args: []const []const u8 = &.{},
    trace: bool = false,
};

pub fn selectedCpuProfile() x64_decoder.capabilities.Profile {
    const raw = std.c.getenv("ROSETTE_X64_CPU_PROFILE") orelse return .xenia;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return x64_decoder.capabilities.parseProfile(value) orelse {
        machoCapturePrint(
            "macho-processor: unknown ROSETTE_X64_CPU_PROFILE={s}; using xenia\n",
            .{value},
        );
        return .xenia;
    };
}

pub fn environmentFlag(name: [*:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes");
}

pub fn environmentUnsigned(name: [*:0]const u8, fallback: u64) u64 {
    const raw = std.c.getenv(name) orelse return fallback;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return std.fmt.parseUnsigned(u64, value, 10) catch fallback;
}

pub fn stepBudgetAllows(max_steps: u64, completed_steps: u64) bool {
    return max_steps == 0 or completed_steps < max_steps;
}

pub const VexDecoderAudit = struct {
    passed: usize,
    total: usize,
    first_failed_case: ?usize = null,
    expected_op: Op = .invalid,
    actual_op: Op = .invalid,
    expected_len: usize = 0,
    actual_len: usize = 0,
    expected_vector_256: bool = false,
    actual_vector_256: bool = false,

    pub fn ready(self: VexDecoderAudit) bool {
        return self.passed == self.total;
    }
};

/// AVX CPUID exposure is a promise that the foundational VEX encodings used
/// by compilers and JITs are executable. Audit both VEX2/VEX3, 128/256-bit,
/// extended-base, scalar-move, arithmetic and zero-upper forms before launch.
pub fn auditVexDecoder() VexDecoderAudit {
    const AuditCase = struct {
        bytes: []const u8,
        op: Op,
        vector_256: bool = false,
    };
    const cases = [_]AuditCase{
        .{ .bytes = &.{ 0xC5, 0xFA, 0x7E, 0x40, 0x48 }, .op = .vmovq_xmm_mem64 }, // vmovq xmm0, [rax+0x48]
        .{ .bytes = &.{ 0xC5, 0xFA, 0x6F, 0x00 }, .op = .vmovdqu_xmm_mem }, // vmovdqu xmm0, [rax]
        .{ .bytes = &.{ 0xC4, 0xC1, 0x7A, 0x7F, 0x01 }, .op = .vmovdqu_mem_xmm }, // vmovdqu [r9], xmm0
        .{ .bytes = &.{ 0xC5, 0xFC, 0x10, 0x00 }, .op = .vmovups_ymm_mem, .vector_256 = true }, // vmovups ymm0, [rax]
        .{ .bytes = &.{ 0xC5, 0xFC, 0x11, 0x00 }, .op = .vmovups_mem_ymm, .vector_256 = true }, // vmovups [rax], ymm0
        .{ .bytes = &.{ 0xC5, 0xF8, 0x58, 0xC1 }, .op = .vaddps }, // vaddps xmm0, xmm0, xmm1
        .{ .bytes = &.{ 0xC5, 0xF8, 0x57, 0xC0 }, .op = .vxorps }, // vxorps xmm0, xmm0, xmm0
        .{ .bytes = &.{ 0xC5, 0xF9, 0xF4, 0xC1 }, .op = .vpmuludq }, // vpmuludq xmm0, xmm0, xmm1
        .{ .bytes = &.{ 0xC4, 0x41, 0x31, 0xF4, 0xC2 }, .op = .vpmuludq }, // vpmuludq xmm8, xmm9, xmm10
        .{ .bytes = &.{ 0xC5, 0xFD, 0xF4, 0xC1 }, .op = .vpmuludq, .vector_256 = true }, // vpmuludq ymm0, ymm0, ymm1
        .{ .bytes = &.{ 0xC5, 0xF9, 0xD4, 0x45, 0xE0 }, .op = .vpaddq }, // vpaddq xmm0, xmm0, [rbp-0x20]
        .{ .bytes = &.{ 0xC5, 0xF9, 0xD3, 0xC1 }, .op = .vpsrlq }, // vpsrlq xmm0, xmm0, xmm1
        .{ .bytes = &.{ 0xC5, 0xF9, 0xF3, 0xC2 }, .op = .vpsllq }, // vpsllq xmm0, xmm0, xmm2
        .{ .bytes = &.{ 0xC4, 0xE3, 0x79, 0x0E, 0xDA, 0xCC }, .op = .vpblendw }, // vpblendw xmm3, xmm0, xmm2, 0xcc
        .{ .bytes = &.{ 0xC5, 0xF9, 0x6C, 0xC1 }, .op = .vpunpcklqdq }, // vpunpcklqdq xmm0, xmm0, xmm1
        .{ .bytes = &.{ 0xC5, 0xF8, 0x77 }, .op = .vzeroupper }, // vzeroupper
    };
    var passed: usize = 0;
    var result = VexDecoderAudit{ .passed = 0, .total = cases.len };
    for (cases, 0..) |case, index| {
        const decoded = decodeInsn(case.bytes);
        if (decoded.op == case.op and decoded.len == case.bytes.len and decoded.vector_256 == case.vector_256) {
            passed += 1;
        } else if (result.first_failed_case == null) {
            result.first_failed_case = index;
            result.expected_op = case.op;
            result.actual_op = decoded.op;
            result.expected_len = case.bytes.len;
            result.actual_len = decoded.len;
            result.expected_vector_256 = case.vector_256;
            result.actual_vector_256 = decoded.vector_256;
        }
    }
    result.passed = passed;
    return result;
}

test "Mach-O execution is unlimited unless an explicit step budget is set" {
    try std.testing.expect(stepBudgetAllows(0, 0));
    try std.testing.expect(stepBudgetAllows(0, std.math.maxInt(u64)));
    try std.testing.expect(stepBudgetAllows(100, 99));
    try std.testing.expect(!stepBudgetAllows(100, 100));
}

test "advertised AVX profile passes baseline VEX decoder audit" {
    const audit = auditVexDecoder();
    if (!audit.ready()) {
        machoCapturePrint(
            "VEX audit failure: case={?} expected={s}/len={d}/ymm={} actual={s}/len={d}/ymm={}\n",
            .{ audit.first_failed_case, @tagName(audit.expected_op), audit.expected_len, audit.expected_vector_256, @tagName(audit.actual_op), audit.actual_len, audit.actual_vector_256 },
        );
    }
    try std.testing.expect(audit.ready());
}
