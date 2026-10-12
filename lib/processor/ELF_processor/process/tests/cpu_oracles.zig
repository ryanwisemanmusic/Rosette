const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const BLOCK_JIT_WAYS = __ProcessInternals._BLOCK_JIT_WAYS;
const DecodeCacheMissCause = __ProcessInternals._DecodeCacheMissCause;
const DecodedInsn = process.DecodedInsn;
const ElfRegs = process.ElfRegs;
const GpuRingWindow = __ProcessInternals._GpuRingWindow;
const GuestFrameCost = __ProcessInternals._GuestFrameCost;
const GuestFrontBuffer = __ProcessInternals._GuestFrontBuffer;
const GuestXmaRegisterCensus = __ProcessInternals._GuestXmaRegisterCensus;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const Op = process.Op;
const PE_DECODE_CACHE_SETS = __ProcessInternals._PE_DECODE_CACHE_SETS;
const PE_DECODE_CACHE_WAYS = __ProcessInternals._PE_DECODE_CACHE_WAYS;
const RFL_CF = __ProcessInternals._RFL_CF;
const RegId = process.RegId;
const Size = process.Size;
const WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND = process.WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
const WINDOWS_GUEST_SPIN_MAX_BACKOFF = __ProcessInternals._WINDOWS_GUEST_SPIN_MAX_BACKOFF;
const WINDOWS_TIMED_WAIT_SITE_CAPACITY = __ProcessInternals._WINDOWS_TIMED_WAIT_SITE_CAPACITY;
const WindowsFileFailureClass = __ProcessInternals._WindowsFileFailureClass;
const WindowsFileFailureLedger = __ProcessInternals._WindowsFileFailureLedger;
const WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const WindowsTimedWaitClassification = __ProcessInternals._WindowsTimedWaitClassification;
const WindowsTimedWaitSite = __ProcessInternals._WindowsTimedWaitSite;
const block_jit = __ProcessInternals._block_jit;
const classifyWindowsFileFailure = __ProcessInternals._classifyWindowsFileFailure;
const classifyWindowsTimedWaitSite = __ProcessInternals._classifyWindowsTimedWaitSite;
const decode_cache_set_lock_count = __ProcessInternals._decode_cache_set_lock_count;
const evex = __ProcessInternals._evex;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const freeTranslatedBlock = __ProcessInternals._freeTranslatedBlock;
const guest_clock = __ProcessInternals._guest_clock;
const host_fp_control = __ProcessInternals._host_fp_control;
const kuser_shared = __ProcessInternals._kuser_shared;
const log = __ProcessInternals._log;
const mapped_ranges = __ProcessInternals._mapped_ranges;
const monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const peDecodeCacheIndex = __ProcessInternals._peDecodeCacheIndex;
const peDecodeCacheSetIndex = __ProcessInternals._peDecodeCacheSetIndex;
const std = __ProcessInternals._std;
const testing = std.testing;
const windowsTimedWaitPercent = __ProcessInternals._windowsTimedWaitPercent;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const ElfState = process.ElfState;
const decodeInsn = __ProcessInternals._decodeInsn;
const envPresentAndFalse = __ProcessInternals._envPresentAndFalse;
const BlockJitState = __ProcessInternals._BlockJitState;
const RFL_ZF = __ProcessInternals._RFL_ZF;
const WindowsGuestThreadContext = __ProcessInternals._WindowsGuestThreadContext;
const WindowsMappedCodeSlice = __ProcessInternals._WindowsMappedCodeSlice;
const heap_guard = __ProcessInternals._heap_guard;
const tso_memory = __ProcessInternals._tso_memory;
const tso_memory_policy = __ProcessInternals._tso_memory_policy;
const windows_guest_execution_binding = __ProcessInternals._windows_guest_execution_binding;
const main = process.main;

/// The general register an AT&T operand names, as a `RegId` number, or null.
fn corpusGprIndex(operand: []const u8) ?u4 {
    if (operand.len < 2 or operand[0] != '%') return null;
    const name = operand[1..];
    const legacy = [_]struct { names: []const []const u8, index: u4 }{
        .{ .names = &.{ "rax", "eax", "ax", "al", "ah" }, .index = 0 },
        .{ .names = &.{ "rcx", "ecx", "cx", "cl", "ch" }, .index = 1 },
        .{ .names = &.{ "rdx", "edx", "dx", "dl", "dh" }, .index = 2 },
        .{ .names = &.{ "rbx", "ebx", "bx", "bl", "bh" }, .index = 3 },
        .{ .names = &.{ "rsp", "esp", "sp", "spl" }, .index = 4 },
        .{ .names = &.{ "rbp", "ebp", "bp", "bpl" }, .index = 5 },
        .{ .names = &.{ "rsi", "esi", "si", "sil" }, .index = 6 },
        .{ .names = &.{ "rdi", "edi", "di", "dil" }, .index = 7 },
    };
    for (legacy) |entry| {
        for (entry.names) |candidate| if (std.mem.eql(u8, name, candidate)) return entry.index;
    }
    if (name.len >= 2 and name[0] == 'r' and std.ascii.isDigit(name[1])) {
        var end: usize = 1;
        while (end < name.len and std.ascii.isDigit(name[end])) end += 1;
        const number = std.fmt.parseInt(u8, name[1..end], 10) catch return null;
        if (number >= 8 and number <= 15) return @intCast(number);
    }
    return null;
}

/// The operands of an AT&T line, split at top-level commas.
fn corpusOperands(text: []const u8, out: *[4][]const u8) usize {
    const space = std.mem.indexOfScalar(u8, text, ' ') orelse return 0;
    const operands = std.mem.trim(u8, text[space..], " ");
    var count: usize = 0;
    var depth: usize = 0;
    var start: usize = 0;
    for (operands, 0..) |c, i| {
        switch (c) {
            '(' => depth += 1,
            ')' => depth -|= 1,
            ',' => if (depth == 0) {
                if (count < out.len) out[count] = std.mem.trim(u8, operands[start..i], " ");
                count += 1;
                start = i + 1;
            },
            else => {},
        }
    }
    if (count < out.len and start < operands.len) {
        out[count] = std.mem.trim(u8, operands[start..], " ");
        count += 1;
    }
    return @min(count, out.len);
}

test "every Xenia JIT form writes only the general registers its assembler text names" {
    // The decodes-and-executes corpus test above cannot see a form that
    // runs cleanly into the wrong register. On 2026-09-21 VEX `vpextrw
    // r32, xmm, imm` (0F C5, ModRM.reg is the destination) was decoded with
    // the roles of the 0F3A 15 form; `vpextrw eax, xmm4, n` zeroed rsp and
    // retired Halo 3's RENDER thread mid campaign load. Here every register
    // starts distinct, and after one step only the registers the
    // assembler's own disassembly names as written - plus each mnemonic's
    // architectural implicit writes - may have changed. rsp in particular
    // moves only for the stack instructions.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    var state = ElfState.init(testing.allocator);
    state.block_jit_enabled = false;
    defer state.deinit();
    const code = MEM_BASE + 0x1000;
    const data = MEM_BASE + 0x40000;
    var failures: usize = 0;
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        const mnemonic = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        var bytes = [_]u8{0x90} ** 16;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (count == bytes.len) break;
            bytes[count] = try std.fmt.parseInt(u8, token, 16);
            count += 1;
        }
        const decoded = decodeInsn(bytes[0..count]);
        if (decoded.op == .invalid or decoded.len != count) continue;
        for (bytes, 0..) |byte, offset| state.write8(code + offset, byte);
        const segments = state.regs.segments;
        state.regs = .{};
        state.regs.segments = segments;
        // Distinct values, each still an address inside readable memory, and
        // CL still a shift count of one.
        for (0..16) |index| {
            const id: RegId = @enumFromInt(index);
            state.setReg(id, .bits64, data + index * 0x200 + (if (index == 1) @as(u64, 1) else 0));
        }
        state.regs.rsp = MEM_BASE + 0x80000;
        state.regs.rip = code;
        var before: [16]u64 = undefined;
        for (0..16) |index| before[index] = state.regVal(@enumFromInt(index), .bits64);
        state.terminated = false;
        state.faulted = false;
        state.termination_reason = .unknown;
        _ = state.step();
        if (state.terminated or state.faulted) continue;
        checked += 1;

        var allowed = [_]bool{false} ** 16;
        var operands: [4][]const u8 = undefined;
        const operand_count = corpusOperands(text, &operands);
        if (operand_count != 0) {
            if (corpusGprIndex(operands[operand_count - 1])) |index| allowed[index] = true;
        }
        const implicit = struct {
            fn any(m: []const u8, names: []const []const u8) bool {
                for (names) |name| if (std.mem.startsWith(u8, m, name)) return true;
                return false;
            }
        };
        if (implicit.any(mnemonic, &.{ "xchg", "xadd" }) and operand_count != 0) {
            if (corpusGprIndex(operands[0])) |index| allowed[index] = true;
        }
        if (implicit.any(mnemonic, &.{ "push", "pop", "call", "ret", "enter", "leave" })) {
            allowed[4] = true;
            allowed[5] = true;
        }
        if (implicit.any(mnemonic, &.{ "cmpxchg", "cqo", "cdq", "cwd", "cbw", "cwde", "cdqe", "cltq", "cltd", "cqto", "cwtl", "cwtd", "cbtw", "lahf", "rdtsc", "cpuid" })) {
            allowed[0] = true;
            allowed[2] = true;
            if (implicit.any(mnemonic, &.{ "cpuid", "rdtsc" })) {
                allowed[1] = true;
                allowed[3] = true;
            }
        }
        if ((implicit.any(mnemonic, &.{ "mul", "div", "idiv" }) or
            (std.mem.startsWith(u8, mnemonic, "imul") and operand_count == 1)))
        {
            allowed[0] = true;
            allowed[2] = true;
        }
        // The string instructions (none are in Xenia's JIT today) move rsi,
        // rdi and rcx and read or write rax.
        if (implicit.any(mnemonic, &.{ "stos", "lods", "cmps", "scas", "rep", "loop" }) or
            std.mem.eql(u8, mnemonic, "movsb") or std.mem.eql(u8, mnemonic, "movsw") or std.mem.eql(u8, mnemonic, "movsq"))
        {
            allowed[0] = true;
            allowed[1] = true;
            allowed[6] = true;
            allowed[7] = true;
        }
        for (0..16) |index| {
            const after = state.regVal(@enumFromInt(index), .bits64);
            if (after == before[index] or allowed[index]) continue;
            if (failures < 8) std.debug.print("register {d} changed 0x{x} -> 0x{x} by {s}\n", .{ index, before[index], after, line });
            failures += 1;
            break;
        }
    }
    try testing.expect(checked > 1000);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "an eight-bit DIV and IDIV leave the remainder in AH and raise #DE on overflow" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xFFFF_0000_0000_0107; // AX = 263
    state.regs.rdx = 0x55;
    state.regs.r10 = 10;
    state.execute(decodeInsn(&[_]u8{ 0x41, 0xF6, 0xF2 })); // div r10b
    try testing.expect(!state.terminated);
    try testing.expectEqual(@as(u64, 0x031A), state.regs.rax & 0xFFFF); // AH=3 AL=26
    try testing.expectEqual(@as(u64, 0x55), state.regs.rdx);
    state.regs.rax = 0xFFF9; // AX = -7
    state.regs.r10 = 2;
    state.execute(decodeInsn(&[_]u8{ 0x41, 0xF6, 0xFA })); // idiv r10b
    try testing.expectEqual(@as(u64, 0xFFFD), state.regs.rax & 0xFFFF); // AH=-1 AL=-3
    state.regs.rax = 0x1000;
    state.regs.r10 = 2;
    state.execute(decodeInsn(&[_]u8{ 0x41, 0xF6, 0xF2 }));
    try testing.expectEqual(exit_diagnostics.TerminationReason.divide_by_zero, state.termination_reason);
}

test "VMOVSS xmm1, xmm2, xmm3 merges the low element of one source with the lane of VEX.vvvv" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // vmovss %xmm3, %xmm2, %xmm1: low element from xmm3, the rest from xmm2.
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xEA, 0x10, 0xCB });
    try testing.expectEqual(Op.vmovss_xmm_xmm_xmm, decoded.op);
    for (0..16) |index| {
        state.xmm[2][index] = @intCast(0x20 + index);
        state.xmm[3][index] = @intCast(0x30 + index);
    }
    state.ymm_hi[1] = [_]u8{0xAA} ** 16;
    state.execute(decoded);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x30, 0x31, 0x32, 0x33 }, state.xmm[1][0..4]);
    try testing.expectEqualSlices(u8, state.xmm[2][4..16], state.xmm[1][4..16]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[1]);
}

test "CloseHandle keeps a mapping's backing while a view of it is mapped, as Windows does" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x980;

    const mapping: u64 = 0xFFFF_F000_0000_0E01;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    const index = state.windowsMappingIndex(mapping).?;
    state.windows_memory_views[0] = .{ .guest_base = 0x5_0000_0000, .length = 0x10000, .mapping_index = index, .backing_offset = 0 };
    state.windows_memory_view_count = 1;

    state.regs.rcx = mapping;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CloseHandle", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    // Closed, and still backed: the view is what Xenia's guest memory is.
    try testing.expect(state.windows_file_mappings[index].backing != null);
    try testing.expect(state.unmapWindowsMemoryView(0x5_0000_0000));
    try testing.expect(state.windows_file_mappings[index].backing == null);

    // An event closes through the same call and gives back its slot.
    const event: u64 = 0xFFFF_F000_0000_0E02;
    state.registerWindowsEvent(event, false, false);
    state.regs.rcx = event;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CloseHandle", return_rip));
    try testing.expectEqual(@as(?bool, null), state.windowsWaitObjectReady(event));
}

test "indexed Windows mappings preserve scalar SIMD CRT and offset-alias byte identity through close and reuse" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mapping: u64 = 0xFFFF_F000_0000_0F01;
    const base: u64 = 0x6000_0000;
    const alias: u64 = 0x7000_0000;
    const offset_alias: u64 = 0x7100_0000;
    const page: u64 = std.heap.page_size_min;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    try testing.expectEqual(base, state.mapWindowsMemoryView(mapping, base, 0x10000, 0).?);
    try testing.expectEqual(alias, state.mapWindowsMemoryView(mapping, alias, 0x10000, 0).?);
    try testing.expectEqual(offset_alias, state.mapWindowsMemoryView(mapping, offset_alias, page, page).?);
    try testing.expectEqual(@as(usize, 3), state.windows_mapped_ranges.count);
    state.write32(base + 0x20, 0x04030201);
    try testing.expectEqual(@as(u32, 0x04030201), state.read32(alias + 0x20));
    try testing.expectEqual(@intFromPtr(state.guestMemoryConst(base, 1).?.ptr), @intFromPtr(state.guestMemoryConst(alias, 1).?.ptr));
    const vector: [16]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    state.writeMem128(alias + 0x50, vector);
    try testing.expectEqualSlices(u8, &vector, &state.readMem128(base + 0x50));
    state.write64(base + page, 0x1122334455667788);
    try testing.expectEqual(@as(u64, 0x1122334455667788), state.read64(offset_alias));
    state.writeMem128(state.mem_base + 0x2000, vector);
    state.regs.rcx = alias + 0x90;
    state.regs.rdx = state.mem_base + 0x2000;
    state.regs.r8 = vector.len;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memcpy", state.mem_base + 0x1000));
    try testing.expectEqualSlices(u8, &vector, &state.readMem128(base + 0x90));
    try testing.expect(state.guestMemoryConst(base + 0xffff, 2) == null);
    try testing.expect(state.guestMemory(base + 0xffff, 2) == null);
    try testing.expect(state.guestMemoryConst(offset_alias + page, 1) == null);
    const slot = state.windowsMappingIndex(mapping).?;
    try testing.expect(state.closeWindowsMemoryMapping(mapping));
    try testing.expectEqual(@as(u32, 0x04030201), state.read32(alias + 0x20));
    try testing.expect(state.unmapWindowsMemoryView(base));
    try testing.expect(state.guestMemoryConst(base, 1) == null);
    try testing.expect(state.windows_file_mappings[slot].backing != null);
    try testing.expect(state.unmapWindowsMemoryView(alias));
    try testing.expect(state.unmapWindowsMemoryView(offset_alias));
    try testing.expect(state.windows_file_mappings[slot].backing == null);
    try testing.expectEqual(@as(usize, 0), state.windows_mapped_ranges.count);
    try testing.expect(state.createWindowsMemoryMapping(mapping + 1, 0x10000, std.math.maxInt(u64)));
    try testing.expectEqual(slot, state.windowsMappingIndex(mapping + 1).?);
    try testing.expectEqual(base, state.mapWindowsMemoryView(mapping + 1, base, 0x10000, 0).?);
    try testing.expectEqual(@as(u32, 0), state.read32(base + 0x20));
    try testing.expect(state.unmapWindowsMemoryView(base));
    try testing.expect(state.closeWindowsMemoryMapping(mapping + 1));
    try testing.expect(state.createWindowsVirtualAllocation(base, 0x1000));
    try testing.expectEqual(mapped_ranges.Kind.virtual_allocation, state.windows_mapped_ranges.find(base, 1).?.kind);
    try testing.expect(state.releaseWindowsVirtualAllocation(base, 0, 0x8000));
    try testing.expectEqual(@as(usize, 0), state.windows_mapped_ranges.count);
    try testing.expect(state.guestMemoryConst(base, 1) == null);
}

test "decode cache observes alias stores bulk writes rollover and mapping-kind lifetime replacement" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    // This test deliberately exercises source-byte refills. Production PE
    // runs keep the default fatal policy, while the unit test opts into the
    // diagnostic/continue mode so it can inspect the post-refill value.
    state.windows_fatal_point_terminate = false;
    const mapping: u64 = 0xFFFF_F000_0000_0F10;
    const base: u64 = 0x6000_0000;
    const alias: u64 = 0x7000_0000;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, base, 0x10000, 0).?;
    _ = state.mapWindowsMemoryView(mapping, alias, 0x10000, 0).?;
    state.write8(base, 0xb8); // MOV EAX, imm32.
    state.write32(base + 1, 1);
    state.regs.rip = base;
    try testing.expectEqual(@as(u64, 1), state.decodeAt().?.imm);
    _ = state.decodeAt().?;
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().hits);
    state.write32(alias + 1, 2);
    try testing.expectEqual(@as(u64, 2), state.decodeAt().?.imm);
    state.write8(alias + 0x100, 0x90); // Unrelated emission only re-arms.
    try testing.expectEqual(@as(u64, 2), state.decodeAt().?.imm);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().rearms);
    const mutable_bytes = state.guestMemory(alias + 1, 4).?;
    std.mem.writeInt(u32, mutable_bytes[0..4], 3, .little);
    try testing.expectEqual(@as(u64, 3), state.decodeAt().?.imm);
    state.write32(state.mem_base + 0x2000, 4);
    state.regs.rcx = alias + 1;
    state.regs.rdx = state.mem_base + 0x2000;
    state.regs.r8 = 4;
    state.windows_runtime_enabled = true;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memcpy", state.mem_base + 0x1000));
    state.regs.rip = base;
    try testing.expectEqual(@as(u64, 4), state.decodeAt().?.imm);
    const slot = state.windowsMappingIndex(mapping).?;
    state.windows_file_mappings[slot].code_generation = std.math.maxInt(u64);
    _ = state.decodeAt().?;
    state.write32(alias + 1, 5);
    try testing.expectEqual(@as(u64, 1), state.windows_file_mappings[slot].code_generation);
    try testing.expectEqual(@as(u64, 5), state.decodeAt().?.imm);
    try testing.expect(state.unmapWindowsMemoryView(base));
    try testing.expect(state.unmapWindowsMemoryView(alias));
    try testing.expect(state.closeWindowsMemoryMapping(mapping));
    try testing.expect(!state.decode_cache[peDecodeCacheIndex(base)].valid);
    try testing.expect(state.createWindowsVirtualAllocation(base, 0x10000));
    const replacement = state.guestMemory(base, 5).?;
    replacement[0] = 0xb8;
    std.mem.writeInt(u32, replacement[1..5], 6, .little);
    state.regs.rip = base;
    try testing.expectEqual(@as(u64, 6), state.decodeAt().?.imm);
    try testing.expectEqual(mapped_ranges.Kind.virtual_allocation, state.decode_cache[peDecodeCacheIndex(base)].source_kind);
    try testing.expect(state.releaseWindowsVirtualAllocation(base, 0, 0x8000));
    try testing.expect(!state.decode_cache[peDecodeCacheIndex(base)].valid);
}

test "decode cache keeps aligned JIT page addresses spread across sets" {
    var seen: [PE_DECODE_CACHE_SETS]bool = @splat(false);
    var distinct: usize = 0;
    for (0..128) |page| {
        const index = peDecodeCacheIndex(0xa000_0000 + @as(u64, @intCast(page)) * 0x10000);
        const set = index / PE_DECODE_CACHE_WAYS;
        if (!seen[set]) distinct += 1;
        seen[set] = true;
    }
    try testing.expectEqual(@as(usize, 128), distinct);
    // Two addresses sharing a set now occupy separate ways instead of
    // evicting each other. This is the ordinary collision that used to make
    // the direct-mapped cache look like it was continually missing.
    var state = ElfState.initWithMemory(testing.allocator, 0x400000);
    defer state.deinit();
    // The test also drives executable-byte changes to prove the stale-byte
    // recovery path. Strict PE runs leave this on; this unit test needs to
    // continue after recording the diagnosed condition.
    state.windows_fatal_point_terminate = false;
    const first = state.mem_base + 0x100;
    var second = first + 16;
    while (second < state.mem_base + state.mem.len - 16 and peDecodeCacheIndex(second) != peDecodeCacheIndex(first)) : (second += 1) {}
    try testing.expect(second < state.mem_base + state.mem.len - 16);
    state.write8(first, 0xb8);
    state.write32(first + 1, 11);
    state.write8(second, 0xb8);
    state.write32(second + 1, 22);
    state.regs.rip = first;
    try testing.expectEqual(@as(u64, 11), state.decodeAt().?.imm);
    state.regs.rip = second;
    try testing.expectEqual(@as(u64, 22), state.decodeAt().?.imm);
    state.regs.rip = first;
    try testing.expectEqual(@as(u64, 11), state.decodeAt().?.imm);
    try testing.expectEqual(@as(u64, 0), state.decodeCacheCounts().collisions);
    // The image generation fast path has the same bulk/SIMD obligations.
    state.windows_runtime_enabled = true;
    state.configureWindowsExecutableRanges(&.{.{ .guest_base = first, .length = 0x100 }});
    _ = state.decodeAt().?;
    const image_output = state.guestMemory(first + 1, 4).?;
    std.mem.writeInt(u32, image_output[0..4], 33, .little);
    try testing.expectEqual(@as(u64, 33), state.decodeAt().?.imm);
    var image_vector: [16]u8 = @splat(0x90);
    image_vector[0] = 0xb8;
    std.mem.writeInt(u32, image_vector[1..5], 44, .little);
    state.writeMem128(first, image_vector);
    try testing.expectEqual(@as(u64, 44), state.decodeAt().?.imm);
    state.write32(state.mem_base + 0x2000, 55);
    state.regs.rcx = first + 1;
    state.regs.rdx = state.mem_base + 0x2000;
    state.regs.r8 = 4;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memcpy", state.mem_base + 0x1000));
    state.regs.rip = first;
    try testing.expectEqual(@as(u64, 55), state.decodeAt().?.imm);
}

test "decode cache makes a full set an explicit fatal point" {
    var state = ElfState.initWithMemory(testing.allocator, 0x400000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_fatal_point_terminate = true;

    const first = state.mem_base + 0x100;
    const target_set = peDecodeCacheSetIndex(first);
    var addresses: [PE_DECODE_CACHE_WAYS + 1]u64 = undefined;
    var found: usize = 0;
    var candidate = first;
    while (candidate < state.mem_base + state.mem.len - 16 and found < addresses.len) : (candidate += 1) {
        if (peDecodeCacheSetIndex(candidate) != target_set) continue;
        var separated = true;
        for (addresses[0..found]) |previous| {
            const distance = if (candidate >= previous) candidate - previous else previous - candidate;
            if (distance < 16) {
                separated = false;
                break;
            }
        }
        if (!separated) continue;
        addresses[found] = candidate;
        found += 1;
    }
    try testing.expectEqual(addresses.len, found);

    for (addresses, 0..) |address, index| {
        state.write8(address, 0xb8);
        state.write32(address + 1, @intCast(index + 1));
        state.regs.rip = address;
        if (index + 1 == addresses.len) {
            try testing.expect(state.decodeAt() == null);
        } else {
            try testing.expectEqual(@as(u64, @intCast(index + 1)), state.decodeAt().?.imm);
        }
    }
    try testing.expect(state.terminated);
    try testing.expect(state.faulted);
    try testing.expectEqual(exit_diagnostics.TerminationReason.runtime_invariant_failure, state.termination_reason);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().collisions);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().conflict_fills);
    // The conflict is the one listed site; the sixteen fills before it are
    // counted only.
    try testing.expectEqual(@as(usize, 1), state.decode_cache_miss_site_count);
    try testing.expectEqual(DecodeCacheMissCause.capacity_conflict, state.decode_cache_miss_sites[0].cause);
    try testing.expectEqual(@as(u64, PE_DECODE_CACHE_WAYS), state.decode_cache_miss_reports[@intFromEnum(DecodeCacheMissCause.vacant_fill)]);
}

test "decode-cache miss reports count across shards and list no compulsory fill" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    // Misses in different sets land in different shards. A per-shard count
    // called each of them the first, which is how 4096 shards each reported
    // their own first fills on 2026-09-30.
    var shards: [4]usize = undefined;
    var address = state.mem_base + 0x100;
    for (&shards) |*shard| {
        state.write8(address, 0x90);
        state.regs.rip = address;
        _ = state.decodeAt() orelse return error.ExpectedInstruction;
        shard.* = peDecodeCacheSetIndex(address) % decode_cache_set_lock_count;
        address += 0x40;
    }
    try testing.expect(shards[0] != shards[1] or shards[1] != shards[2] or shards[2] != shards[3]);
    try testing.expectEqual(@as(u64, 4), state.decode_cache_miss_reports[@intFromEnum(DecodeCacheMissCause.vacant_fill)]);
    try testing.expectEqual(@as(usize, 0), state.decode_cache_miss_site_count);
    try testing.expectEqual(@as(u64, 0), state.decode_cache_miss_site_overflow);
}

test "decode cache victim bank recovers a recently displaced instruction" {
    var state = ElfState.initWithMemory(testing.allocator, 0x400000);
    defer state.deinit();
    state.windows_fatal_point_terminate = false;

    const first = state.mem_base + 0x100;
    const target_set = peDecodeCacheSetIndex(first);
    var addresses: [PE_DECODE_CACHE_WAYS + 1]u64 = undefined;
    var found: usize = 0;
    var candidate = first;
    while (candidate < state.mem_base + state.mem.len - 16 and found < addresses.len) : (candidate += 1) {
        if (peDecodeCacheSetIndex(candidate) != target_set) continue;
        var separated = true;
        for (addresses[0..found]) |previous| {
            if (@abs(@as(i64, @intCast(candidate)) - @as(i64, @intCast(previous))) < 16) {
                separated = false;
                break;
            }
        }
        if (!separated) continue;
        addresses[found] = candidate;
        found += 1;
    }
    try testing.expectEqual(addresses.len, found);

    for (addresses, 0..) |address, index| {
        state.write8(address, 0xb8);
        state.write32(address + 1, @intCast(index + 1));
        state.regs.rip = address;
        try testing.expectEqual(@as(u64, @intCast(index + 1)), state.decodeAt().?.imm);
    }
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().collisions);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().victim_fills);

    state.regs.rip = addresses[0];
    try testing.expectEqual(@as(u64, 1), state.decodeAt().?.imm);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheCounts().victim_hits);
    try testing.expectEqual(@as(u64, addresses.len), state.decodeCacheCounts().misses);
}

test "a file failure is classified by what it means, and only an actionable one warns" {
    try testing.expectEqual(WindowsFileFailureClass.named_pipe_without_server, classifyWindowsFileFailure("CreateFileW", 2, "\\\\?\\pipe\\discord-ipc-0"));
    try testing.expectEqual(WindowsFileFailureClass.end_of_enumeration, classifyWindowsFileFailure("FindNextFileW", 18, ""));
    try testing.expectEqual(WindowsFileFailureClass.optional_path_probe, classifyWindowsFileFailure("_wstat64", 2, "C:\\xenia\\portable.txt"));
    try testing.expectEqual(WindowsFileFailureClass.missing_path_open, classifyWindowsFileFailure("_wfopen", 2, "C:\\xenia\\cache.bin"));
    try testing.expectEqual(WindowsFileFailureClass.io_failure, classifyWindowsFileFailure("fread", 5, "/tmp/shaders.xsf"));
    try testing.expect(WindowsFileFailureClass.named_pipe_without_server.expected());
    try testing.expect(!WindowsFileFailureClass.io_failure.expected());

    var ledger = WindowsFileFailureLedger{};
    ledger.note("CreateFileW", 2, "\\\\?\\pipe\\discord-ipc-0", 0x140001000);
    ledger.note("CreateFileW", 2, "\\\\?\\pipe\\discord-ipc-1", 0x140001000);
    ledger.note("CreateFileW", 2, "C:\\xenia\\missing.bin", 0x140002000);
    try testing.expectEqual(@as(usize, 2), ledger.count);
    try testing.expectEqual(@as(u64, 2), ledger.entries[0].count);
    try testing.expectEqualStrings("\\\\?\\pipe\\discord-ipc-0", ledger.entries[0].subject());
    try testing.expectEqual(WindowsFileFailureClass.missing_path_open, ledger.entries[1].class);
}

test "timed condition waits are counted by the site that makes them" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const site = state.noteWindowsTimedWaitSite(0x140a4d000, 3, 500);
    try testing.expectEqual(@as(u8, 1), site);
    try testing.expectEqual(@as(u8, 1), state.noteWindowsTimedWaitSite(0x140a4d000, 3, 500));
    state.countWindowsTimedWaitOutcome(site, .timeout);
    state.countWindowsTimedWaitOutcome(site, .signalled);
    try testing.expectEqual(@as(u64, 2), state.windows_timed_wait_sites[0].waits);
    try testing.expectEqual(@as(u64, 1), state.windows_timed_wait_sites[0].timeouts);
    try testing.expectEqual(@as(u64, 1), state.windows_timed_wait_sites[0].signalled);
    for (1..WINDOWS_TIMED_WAIT_SITE_CAPACITY) |offset| _ = state.noteWindowsTimedWaitSite(0x140b00000 + offset, 1, 30);
    try testing.expectEqual(@as(u8, 0), state.noteWindowsTimedWaitSite(0x140c00000, 1, 30));
    try testing.expectEqual(@as(u64, 1), state.windows_timed_wait_site_overflow);
}

test "timed condition site classification separates polling from lost wakeups" {
    var site = WindowsTimedWaitSite{
        .waits = 100,
        .timeouts = 99,
        .signalled = 1,
        .last_milliseconds = 500,
    };
    try testing.expectEqual(WindowsTimedWaitClassification.short_periodic_poll_candidate, classifyWindowsTimedWaitSite(site));
    try testing.expectEqual(@as(u8, 99), windowsTimedWaitPercent(site.timeouts, site.waits));

    site.last_milliseconds = 5_000;
    site.signalled = 0;
    try testing.expectEqual(WindowsTimedWaitClassification.possible_lost_wakeup, classifyWindowsTimedWaitSite(site));
}

test "every instruction form in xenia_canary.exe decodes to a real operation" {
    // xenia_image_corpus.txt is tools/gen_xenia_image_corpus.py's output: one
    // exemplar per (mnemonic, operand shape, encoding family) across the
    // executable's 3.9 million instructions. The JIT corpus covers what Xenia
    // generates; this covers Xenia itself, where the 2026-09-14 run died on
    // `vmovntps %ymm0, mem` in its two-byte VEX spelling.
    const corpus = @embedFile("../../xenia_image_corpus.txt");
    // Forms that stay undecoded, each for a reason. A form that fails and is
    // not named here is a new gap.
    const known_gaps = [_]struct { form: []const u8, reason: []const u8 }{
        .{ .form = "shrx", .reason = "BMI2: the xenia CPUID profile does not advertise it, and zstd picks its _bmi2 functions by CPUID" },
        .{ .form = "rdrand", .reason = "not advertised; libstdc++'s random_device asks CPUID before using it" },
        .{ .form = "rdseed", .reason = "not advertised; libstdc++'s random_device asks CPUID before using it" },
        .{ .form = "vhaddp", .reason = "no executor arm; only SDL's SSE3 stereo-to-mono converter" },
        .{ .form = "vaddsubp", .reason = "no ISA contract or executor; only SDL_RenderCopyEx and FFmpeg's RDFT, neither on Xenia's path" },
        .{ .form = "pushfq", .reason = "decodes as NOP; only SDL's CPUID-bit probe uses it, and that sequence stays stack-balanced" },
        .{ .form = "popfq", .reason = "decodes as NOP; see pushfq" },
        // llvm-objdump prints a LOCK prefix it could not attach as a line of
        // its own; the instruction it belongs to is its own exemplar.
        .{ .form = "lock ", .reason = "a disassembler artefact, not an instruction" },
    };
    const not_operations = [_][]const u8{ "nop", "prefetch", "endbr", "pause", "fnop" };
    var failures: usize = 0;
    var first_failure: []const u8 = "";
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        const form = fields.next() orelse continue;
        const family = fields.next() orelse continue;
        // AVX-512 is not advertised; CPUID dispatch keeps those forms cold.
        if (std.mem.startsWith(u8, family, "evex.")) continue;
        const known = for (known_gaps) |gap| {
            if (std.mem.startsWith(u8, form, gap.form)) break true;
        } else false;
        if (known) continue;
        var bytes: [15]u8 = undefined;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (count == bytes.len) break;
            bytes[count] = try std.fmt.parseInt(u8, token, 16);
            count += 1;
        }
        const decoded = decodeInsn(bytes[0..count]);
        // A form that decodes to NOP and is not one skips its own effect,
        // which is worse than refusing: legacy PSHUFD did that.
        const silent = decoded.op == .nop and for (not_operations) |name| {
            if (std.mem.startsWith(u8, form, name)) break false;
        } else true;
        // A VEX form that decodes to a different valid operation is worse
        // still: nothing refuses it. VPINSRQ decoded as VPINSRD passed every
        // check above, and Xenia's deque erase crashed the campaign launch.
        const disagrees = std.mem.startsWith(u8, family, "vex") and decoded.op != .invalid and !corpusMnemonicAgrees(form, decoded);
        if (disagrees) std.debug.print("xenia_canary.exe form decodes to another operation: {s} -> {s} ({s})\n", .{ line, @tagName(decoded.op), @tagName(decoded.size) });
        // The legacy spelling of the same defect is a width: FE decoded
        // `incb` as a 32-bit INC and 66 0F AF `imulw` as a 32-bit IMUL.
        const wrong_width = std.mem.startsWith(u8, family, "legacy") and decoded.op != .invalid and !corpusLegacyWidthAgrees(form, decoded);
        if (wrong_width) std.debug.print("xenia_canary.exe form decodes at another width: {s} -> {s} ({s})\n", .{ line, @tagName(decoded.op), @tagName(decoded.size) });
        if (decoded.op == .invalid or decoded.len != count or silent or disagrees or wrong_width) {
            if (failures == 0) first_failure = line;
            failures += 1;
        }
    }
    if (failures != 0) std.debug.print("{d} xenia_canary.exe form(s) fail; the first is {s}\n", .{ failures, first_failure });
    try testing.expectEqual(@as(usize, 0), failures);
}

/// Whether the corpus mnemonic of `form` (llvm-objdump's AT&T spelling) names
/// the operation `decoded` carries. Op tags spell VEX operations as the Intel
/// mnemonic plus an optional operand-shape suffix (`vmovdqu_xmm_mem`), so the
/// test is a prefix match after the AT&T-only spellings are undone:
///  - an operand-size suffix on a VEX GPR or int-to-float form (`shlxq`,
///    `vcvtsi2sdl`), which must also agree with the decoded width;
///  - a comparison predicate folded into the mnemonic (`vcmpltps` is
///    `vcmpps` with an immediate);
///  - a destination-width suffix (`vcvttpd2dqx`);
///  - documented equivalents that share one operation.
fn corpusMnemonicAgrees(form: []const u8, decoded: DecodedInsn) bool {
    const mnemonic = form[0 .. std.mem.indexOfScalar(u8, form, ' ') orelse form.len];
    const name = @tagName(decoded.op);
    const sized_families = [_][]const u8{ "vcvtsi2ss", "vcvtsi2sd", "shlx", "shrx", "sarx", "rorx", "bzhi", "andn", "mulx", "pdep", "pext", "bextr", "blsr", "blsi", "blsmsk" };
    for (sized_families) |stem| {
        if (mnemonic.len == stem.len + 1 and std.mem.startsWith(u8, mnemonic, stem)) {
            const width: Size = switch (mnemonic[stem.len]) {
                'l' => .bits32,
                'q' => .bits64,
                else => return false,
            };
            return std.mem.startsWith(u8, name, stem) and decoded.size == width;
        }
    }
    if (std.mem.startsWith(u8, mnemonic, "vcmp") and mnemonic.len > 6) {
        const kind = mnemonic[mnemonic.len - 2 ..];
        return std.mem.startsWith(u8, name, "vcmp") and std.mem.endsWith(u8, name, kind);
    }
    const equivalents = [_]struct { mnemonic: []const u8, op: []const u8 }{
        .{ .mnemonic = "vlddqu", .op = "vmovdqu" },
        .{ .mnemonic = "vextracti128", .op = "vextractf128" },
        .{ .mnemonic = "vinserti128", .op = "vinsertf128" },
        .{ .mnemonic = "vldmxcsr", .op = "ldmxcsr" },
        .{ .mnemonic = "vstmxcsr", .op = "stmxcsr" },
        // The ordered compares differ only in raising invalid-operation on a
        // quiet NaN, which Rosette does not model; the flags are the same
        // (ISA/decoding/vex.zig decodes 0F 2F as 2E on purpose).
        .{ .mnemonic = "vcomiss", .op = "vucomiss" },
        .{ .mnemonic = "vcomisd", .op = "vucomisd" },
    };
    for (equivalents) |pair| {
        if (std.mem.eql(u8, mnemonic, pair.mnemonic)) return std.mem.startsWith(u8, name, mnemonic) or std.mem.startsWith(u8, name, pair.op);
    }
    const stem = if (mnemonic.len > 1 and (std.mem.endsWith(u8, mnemonic, "x") or std.mem.endsWith(u8, mnemonic, "y")) and
        std.mem.indexOf(u8, mnemonic, "2") != null)
        mnemonic[0 .. mnemonic.len - 1]
    else
        mnemonic;
    return std.mem.startsWith(u8, name, stem);
}

/// The width a decoded operation acts at: the first `reg<N>`/`mem<N>`
/// component of its tag, else `size`. An `imm8` component names the
/// immediate, not the operation (`shld_reg_imm8` is 32 or 64 bits wide).
fn corpusDecodedWidth(decoded: DecodedInsn) Size {
    var parts = std.mem.splitScalar(u8, @tagName(decoded.op), '_');
    while (parts.next()) |part| {
        const digits = if (std.mem.startsWith(u8, part, "reg") or std.mem.startsWith(u8, part, "mem")) part[3..] else continue;
        if (std.mem.eql(u8, digits, "8")) return .bits8;
        if (std.mem.eql(u8, digits, "16")) return .bits16;
        if (std.mem.eql(u8, digits, "32")) return .bits32;
        if (std.mem.eql(u8, digits, "64")) return .bits64;
    }
    return decoded.size;
}

/// Whether a legacy image form's AT&T size suffix (b/w/l/q) is the width the
/// decoder chose, for the integer families where the suffix is the operand
/// width. Other mnemonics (movz/movs, cvt*, string ops) are not judged.
fn corpusLegacyWidthAgrees(form: []const u8, decoded: DecodedInsn) bool {
    const mnemonic = form[0 .. std.mem.indexOfScalar(u8, form, ' ') orelse form.len];
    if (mnemonic.len < 2) return true;
    const want: Size = switch (mnemonic[mnemonic.len - 1]) {
        'b' => .bits8,
        'w' => .bits16,
        'l' => .bits32,
        'q' => .bits64,
        else => return true,
    };
    const stem = mnemonic[0 .. mnemonic.len - 1];
    const stems = [_][]const u8{
        "mov",  "cmp", "add",  "sub", "and", "or",   "xor",    "adc",   "sbb",   "test",
        "imul", "mul", "idiv", "div", "inc", "dec",  "neg",    "not",   "lea",   "shl",
        "shr",  "sal", "sar",  "rol", "ror", "shld", "shrd",   "xchg",  "xadd",  "cmpxchg",
        "bsr",  "bsf", "bt",   "bts", "btr", "btc",  "popcnt", "tzcnt", "lzcnt", "bswap",
    };
    const known = for (stems) |candidate| {
        if (std.mem.eql(u8, stem, candidate)) break true;
    } else std.mem.startsWith(u8, stem, "cmov") and stem.len > 4;
    if (!known) return true;
    return corpusDecodedWidth(decoded) == want;
}

test "the legacy width check names a byte INC decoded at 32 bits" {
    try testing.expect(corpusLegacyWidthAgrees("incb m[b]", .{ .op = .inc_mem8, .size = .bits8 }));
    try testing.expect(!corpusLegacyWidthAgrees("incb m[b]", .{ .op = .inc_mem32, .size = .bits32 }));
    try testing.expect(!corpusLegacyWidthAgrees("imulw m[b],r16", .{ .op = .imul_reg32_mem32, .size = .bits32 }));
    try testing.expect(corpusLegacyWidthAgrees("imulw m[b],r16", .{ .op = .imul_reg16_mem16, .size = .bits16 }));
    try testing.expect(corpusLegacyWidthAgrees("shldq imm,r64,r64", .{ .op = .shld_reg_imm8, .size = .bits64 }));
    try testing.expect(corpusLegacyWidthAgrees("movzbl m[b],r32", .{ .op = .movzx_reg32_mem8, .size = .bits32 }));
}

test "the corpus agreement check names VPINSRQ decoded as VPINSRD" {
    const pinsrq = DecodedInsn{ .op = .vpinsrq, .size = .bits64 };
    const pinsrd = DecodedInsn{ .op = .vpinsrd, .size = .bits32 };
    try testing.expect(corpusMnemonicAgrees("vpinsrq imm,r64,xmm,xmm", pinsrq));
    try testing.expect(!corpusMnemonicAgrees("vpinsrq imm,r64,xmm,xmm", pinsrd));
    try testing.expect(corpusMnemonicAgrees("shlxq r64,r64,r64", .{ .op = .shlx, .size = .bits64 }));
    try testing.expect(!corpusMnemonicAgrees("shlxq r64,r64,r64", .{ .op = .shlx, .size = .bits32 }));
    try testing.expect(corpusMnemonicAgrees("vcmpltps xmm,xmm,xmm", .{ .op = .vcmpps }));
    try testing.expect(!corpusMnemonicAgrees("vcmpltps xmm,xmm,xmm", .{ .op = .vcmppd }));
    try testing.expect(corpusMnemonicAgrees("vcvttpd2dqx m[b,d32],xmm", .{ .op = .vcvttpd2dq }));
    try testing.expect(corpusMnemonicAgrees("vlddqu m[b],ymm", .{ .op = .vmovdqu_ymm_mem }));
}

/// The width an AT&T general-register operand states: 64 or 32 bits, or null
/// for a narrower register or anything that is not a general register.
fn corpusGprWidth(operand: []const u8) ?Size {
    if (corpusGprIndex(operand) == null) return null;
    const name = operand[1..];
    for ([_][]const u8{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi" }) |wide| {
        if (std.mem.eql(u8, name, wide)) return .bits64;
    }
    if (name[0] == 'r' and std.ascii.isDigit(name[name.len - 1])) return .bits64;
    if (name[0] == 'e' or name[name.len - 1] == 'd') return .bits32;
    return null;
}

/// Mnemonics whose operand width is VEX.W's choice, so a general-register
/// operand of 64 bits must decode as a 64-bit operation and one of 32 as 32.
fn corpusWidthFollowsGpr(mnemonic: []const u8) bool {
    const stems = [_][]const u8{
        "vmovd",      "vmovq",   "vcvtsi2ss", "vcvtsi2sd", "vcvtss2si", "vcvtsd2si", "vcvttss2si",
        "vcvttsd2si", "vpextrd", "vpextrq",   "vpinsrd",   "vpinsrq",   "andn",      "bextr",
        "bzhi",       "shlx",    "shrx",      "sarx",      "rorx",      "mulx",      "pdep",
        "pext",       "blsi",    "blsr",      "blsmsk",
    };
    for (stems) |stem| {
        if (!std.mem.startsWith(u8, mnemonic, stem)) continue;
        // The stem itself or an AT&T l/q suffix: `vmovd` but not `vmovdqa`.
        if (mnemonic.len == stem.len) return true;
        if (mnemonic.len == stem.len + 1 and (mnemonic[stem.len] == 'l' or mnemonic[stem.len] == 'q')) return true;
    }
    return false;
}

test "every Xenia JIT VEX form decodes to the operation and width its assembler text names" {
    // The decodes-and-executes corpus test accepts any valid operation of
    // the right length, which is how the image's `vpinsrq` (VEX.66.0F3A.W1
    // 22) ran for months as VPINSRD and corrupted Xenia's deques. The JIT
    // corpus is the code Halo 3 itself runs through, so it gets the image's
    // agreement check plus the width VEX.W selects wherever a general
    // register operand states it.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    var failures: usize = 0;
    var checked: usize = 0;
    var width_checked: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        if (!std.mem.startsWith(u8, hex, "c4") and !std.mem.startsWith(u8, hex, "c5")) continue;
        var bytes = [_]u8{0x90} ** 16;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (count == bytes.len) break;
            bytes[count] = try std.fmt.parseInt(u8, token, 16);
            count += 1;
        }
        const decoded = decodeInsn(bytes[0..count]);
        // An invalid decode is the decodes-and-executes test's finding.
        if (decoded.op == .invalid) continue;
        checked += 1;
        var operands: [4][]const u8 = undefined;
        const operand_count = corpusOperands(text, &operands);
        var gpr_width: ?Size = null;
        for (operands[0..operand_count]) |operand| {
            if (corpusGprWidth(operand)) |width| gpr_width = width;
        }
        const mnemonic = text[0 .. std.mem.indexOfScalar(u8, text, ' ') orelse text.len];
        // Xbyak, and so the corpus, spells the 64-bit GPR move `vmovd` too.
        const agrees = if (std.mem.eql(u8, mnemonic, "vmovd") and gpr_width == .bits64)
            std.mem.startsWith(u8, @tagName(decoded.op), "vmovq")
        else
            corpusMnemonicAgrees(text, decoded);
        var width_agrees = true;
        if (gpr_width) |width| {
            if (corpusWidthFollowsGpr(mnemonic)) {
                width_checked += 1;
                width_agrees = decoded.size == width;
            }
        }
        if (!agrees or !width_agrees) {
            std.debug.print("Xenia JIT form decodes to another operation or width: {s} -> {s} {s}\n", .{ line, @tagName(decoded.op), @tagName(decoded.size) });
            failures += 1;
        }
    }
    // A corpus that lost its VEX forms, or its width-bearing ones, would
    // pass vacuously.
    try testing.expect(checked > 600);
    try testing.expect(width_checked > 30);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "the JIT corpus width check reads AT&T register widths" {
    try testing.expectEqual(@as(?Size, .bits64), corpusGprWidth("%rax"));
    try testing.expectEqual(@as(?Size, .bits64), corpusGprWidth("%r10"));
    try testing.expectEqual(@as(?Size, .bits32), corpusGprWidth("%r10d"));
    try testing.expectEqual(@as(?Size, .bits32), corpusGprWidth("%edi"));
    try testing.expectEqual(@as(?Size, null), corpusGprWidth("%r10w"));
    try testing.expectEqual(@as(?Size, null), corpusGprWidth("%xmm9"));
    try testing.expectEqual(@as(?Size, null), corpusGprWidth("8(%r12,%r13,2)"));
    try testing.expect(corpusWidthFollowsGpr("vcvtsi2sdq"));
    try testing.expect(corpusWidthFollowsGpr("vmovd"));
    try testing.expect(!corpusWidthFollowsGpr("vmovdqa"));
    try testing.expect(!corpusWidthFollowsGpr("vpextrw"));
}

fn testStepBytes(state: *ElfState, bytes: []const u8) void {
    const code = MEM_BASE + 0x1000;
    for (bytes, 0..) |byte, offset| state.write8(code + offset, byte);
    state.regs.rip = code;
    state.terminated = false;
    _ = state.step();
}

fn testSetLanes(state: *ElfState, register: usize, lanes: [4]u64) void {
    std.mem.writeInt(u64, state.xmm[register][0..8], lanes[0], .little);
    std.mem.writeInt(u64, state.xmm[register][8..16], lanes[1], .little);
    std.mem.writeInt(u64, state.ymm_hi[register][0..8], lanes[2], .little);
    std.mem.writeInt(u64, state.ymm_hi[register][8..16], lanes[3], .little);
}

fn testGetLanes(state: *const ElfState, register: usize) [4]u64 {
    return .{
        std.mem.readInt(u64, state.xmm[register][0..8], .little),
        std.mem.readInt(u64, state.xmm[register][8..16], .little),
        std.mem.readInt(u64, state.ymm_hi[register][0..8], .little),
        std.mem.readInt(u64, state.ymm_hi[register][8..16], .little),
    };
}

test "a two-byte VEX spelling decodes wherever its three-byte spelling does" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const data = MEM_BASE + 0x40000;
    // vmovntps %ymm0, -0x3020(%rcx,%rax), from xe::memory::vastcpy_impl_avx.
    const two_byte = [_]u8{ 0xC5, 0xFC, 0x2B, 0x84, 0x01, 0xE0, 0xCF, 0xFF, 0xFF };
    const decoded = decodeInsn(&two_byte);
    try testing.expectEqual(Op.vmovntps, decoded.op);
    try testing.expectEqual(@as(u8, 9), decoded.len);
    try testing.expect(decoded.vector_256);
    const three_byte = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7C, 0x2B, 0x84, 0x01, 0xE0, 0xCF, 0xFF, 0xFF });
    try testing.expectEqual(Op.vmovntps, three_byte.op);
    try testing.expectEqual(@as(u8, 10), three_byte.len);

    testSetLanes(&state, 0, .{ 0x1111, 0x2222, 0x3333, 0x4444 });
    state.regs.rcx = data + 0x3020;
    state.regs.rax = 0;
    testStepBytes(&state, &two_byte);
    try testing.expect(!state.terminated);
    try testing.expectEqual(@as(u64, 0x1111), state.read64(data));
    try testing.expectEqual(@as(u64, 0x4444), state.read64(data + 24));
    try testing.expectEqual(MEM_BASE + 0x1000 + 9, state.regs.rip);
}

test "SHUFPD's control bits pick an element within each source, never the source" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // vshufpd $5, %ymm5, %ymm4, %ymm4, from libstdc++'s mt19937_64 twist:
    // ymm4 = ymm4[1], ymm5[0], ymm4[3], ymm5[2].
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xDD, 0xC6, 0xE5, 0x05 });
    try testing.expectEqual(Op.vshufpd, decoded.op);
    testSetLanes(&state, 4, .{ 1, 2, 3, 4 });
    testSetLanes(&state, 5, .{ 5, 6, 7, 8 });
    state.execute(decoded);
    try testing.expectEqual([4]u64{ 2, 5, 4, 7 }, testGetLanes(&state, 4));
}

test "libstdc++'s unsigned-to-double idiom converts an mt19937_64 draw exactly" {
    // generate_canonical turns each engine draw into a double with this
    // sequence. Under the old SHUFPD it produced twice the low half, every
    // uniform_real_distribution was wrong, and discord-rpc's reconnect
    // backoff never grew past 500 ms (14,123 CreateFileW probes in one run).
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const draw: u64 = 0xE4CE_7F57_A02C_DA67;
    const sequence = [_][]const u8{
        &.{ 0xC4, 0xE1, 0xF9, 0x6E, 0xC0 }, // vmovq %rax, %xmm0
        &.{ 0xC5, 0xF9, 0x62, 0xC7 }, // vpunpckldq %xmm7, %xmm0, %xmm0
        &.{ 0xC4, 0xC1, 0x79, 0x5C, 0xC0 }, // vsubpd %xmm8, %xmm0, %xmm0
        &.{ 0xC5, 0xF9, 0xC6, 0xC8, 0x01 }, // vshufpd $1, %xmm0, %xmm0, %xmm1
        &.{ 0xC5, 0xF3, 0x58, 0xC0 }, // vaddsd %xmm0, %xmm1, %xmm0
    };
    state.regs.rax = draw;
    testSetLanes(&state, 7, .{ 0x4530_0000_4330_0000, 0, 0, 0 });
    testSetLanes(&state, 8, .{ 0x4330_0000_0000_0000, 0x4530_0000_0000_0000, 0, 0 });
    for (sequence) |bytes| {
        testStepBytes(&state, bytes);
        try testing.expect(!state.terminated);
    }
    const expected: f64 = @floatFromInt(draw);
    try testing.expectEqual(@as(u64, @bitCast(expected)), testGetLanes(&state, 0)[0]);
}

test "x87 memory arithmetic reads the operand at its displacement" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const data = MEM_BASE + 0x40000;
    state.regs.rbx = data;
    state.write32(data, @bitCast(@as(f32, 7.0))); // what a lost displacement reads
    state.write32(data + 0x10, @bitCast(@as(f32, 3.0)));
    testStepBytes(&state, &.{ 0xD9, 0xE8 }); // fld1
    testStepBytes(&state, &.{ 0xD8, 0x4B, 0x10 }); // fmul 0x10(%rbx)
    testStepBytes(&state, &.{ 0xDD, 0x5B, 0x20 }); // fstpl 0x20(%rbx)
    try testing.expectEqual(@as(f64, 3.0), @as(f64, @bitCast(state.read64(data + 0x20))));

    // fisttpl truncates into a 32-bit integer.
    state.write64(data + 0x18, @bitCast(@as(f64, 2.75)));
    testStepBytes(&state, &.{ 0xDD, 0x43, 0x18 }); // fldl 0x18(%rbx)
    testStepBytes(&state, &.{ 0xDB, 0x0B }); // fisttpl (%rbx)
    try testing.expectEqual(@as(u32, 2), state.read32(data));

    // fnstenv/fldenv round-trip the control word, and FNSTENV masks every
    // exception afterwards, as MinGW's feclearexcept expects.
    state.x87_control = 0x037A;
    testStepBytes(&state, &.{ 0xD9, 0x73, 0x30 }); // fnstenv 0x30(%rbx)
    try testing.expectEqual(@as(u16, 0x037A), @as(u16, @truncate(state.read32(data + 0x30))));
    try testing.expectEqual(@as(u16, 0x037F), state.x87_control);
    testStepBytes(&state, &.{ 0xD9, 0x63, 0x30 }); // fldenv 0x30(%rbx)
    try testing.expectEqual(@as(u16, 0x037A), state.x87_control);
}

test "translated x87 memory arithmetic uses the focused helper and matches the interpreter" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;

    const program = [_]u8{ 0xD8, 0x03, 0xF4 }; // faddl (%rbx); hlt
    const code = MEM_BASE + 0x1000;
    const data = MEM_BASE + 0x20000;

    var interpreted = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer interpreted.deinit();
    @memcpy(interpreted.mem[0x1000..][0..program.len], &program);
    interpreted.regs.rip = code;
    interpreted.regs.rbx = data;
    interpreted.write32(data, @bitCast(@as(f32, 3.0)));
    _ = interpreted.x87PushRaw(ElfState.x87RawFromFloat(1.0));
    interpreted.runWithLimit(32);

    var translated = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer translated.deinit();
    @memcpy(translated.mem[0x1000..][0..program.len], &program);
    translated.regs.rip = code;
    translated.regs.rbx = data;
    translated.write32(data, @bitCast(@as(f32, 3.0)));
    _ = translated.x87PushRaw(ElfState.x87RawFromFloat(1.0));
    translated.block_jit_enabled = true;
    translated.block_jit_hot_threshold = 1;
    translated.runWithLimit(32);

    try testing.expect(interpreted.terminated and translated.terminated);
    const interpreted_raw = interpreted.x87GetRaw(0) orelse return error.TestUnexpectedResult;
    const translated_raw = translated.x87GetRaw(0) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(ElfState.readExtendedFloat80(&interpreted_raw), ElfState.readExtendedFloat80(&translated_raw));
    try testing.expectEqual(@as(f64, 4.0), ElfState.readExtendedFloat80(&translated_raw));
    const jit = translated.block_jit orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u64, 1), jit.x87_memory_helpers);
    try testing.expectEqual(@as(u64, 0), jit.fallback_calls);
    try testing.expect(jit.compiled > 0);
}

test "SBB with a memory operand decodes and borrows in both directions" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const data = MEM_BASE + 0x40000;
    state.regs.rbx = data;
    state.write64(data + 8, 3);
    state.regs.rax = 10;
    state.regs.rflags |= RFL_CF;
    testStepBytes(&state, &.{ 0x48, 0x1B, 0x43, 0x08 }); // sbb 0x8(%rbx), %rax
    try testing.expectEqual(@as(u64, 6), state.regs.rax);
    state.write64(data + 8, 20);
    state.regs.rflags |= RFL_CF;
    testStepBytes(&state, &.{ 0x48, 0x19, 0x43, 0x08 }); // sbb %rax, 0x8(%rbx)
    try testing.expectEqual(@as(u64, 13), state.read64(data + 8));
}

test "legacy PSHUFD, PCMPEQD and PSUBQ execute instead of decoding as NOP or nothing" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // pshufd $0xe5, %xmm0, %xmm0 from libstdc++'s basic_filebuf move
    // constructor: dwords 1, 1, 2, 3. It used to be a five-byte NOP that
    // claimed six bytes.
    const pshufd = decodeInsn(&[_]u8{ 0x66, 0x0F, 0x70, 0xC0, 0xE5 });
    try testing.expectEqual(Op.vpshufd, pshufd.op);
    try testing.expectEqual(@as(u8, 5), pshufd.len);
    for (0..4) |index| std.mem.writeInt(u32, state.xmm[0][index * 4 ..][0..4], @intCast(0x10 + index), .little);
    state.ymm_hi[0] = [_]u8{0xAB} ** 16;
    state.execute(pshufd);
    try testing.expectEqual(@as(u32, 0x11), std.mem.readInt(u32, state.xmm[0][0..4], .little));
    try testing.expectEqual(@as(u32, 0x11), std.mem.readInt(u32, state.xmm[0][4..8], .little));
    try testing.expectEqual(@as(u32, 0x12), std.mem.readInt(u32, state.xmm[0][8..12], .little));
    try testing.expectEqual(@as(u32, 0x13), std.mem.readInt(u32, state.xmm[0][12..16], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xAB} ** 16), &state.ymm_hi[0]);

    const pcmpeqd = decodeInsn(&[_]u8{ 0x66, 0x0F, 0x76, 0xC0 }); // pcmpeqd %xmm0, %xmm0
    try testing.expectEqual(Op.vpcmpeqd, pcmpeqd.op);
    state.execute(pcmpeqd);
    try testing.expectEqualSlices(u8, &([_]u8{0xFF} ** 16), &state.xmm[0]);

    const psubq = decodeInsn(&[_]u8{ 0x66, 0x0F, 0xFB, 0xCB }); // psubq %xmm3, %xmm1
    try testing.expectEqual(Op.vpsubq, psubq.op);
    testSetLanes(&state, 1, .{ 100, 7, 0, 0 });
    testSetLanes(&state, 3, .{ 1, 9, 0, 0 });
    state.execute(psubq);
    try testing.expectEqual(@as(u64, 99), testGetLanes(&state, 1)[0]);
    try testing.expectEqual(@as(u64, 7) -% 9, testGetLanes(&state, 1)[1]);

    // vpsadbw %xmm4, %xmm3, %xmm4 from zlib-ng's adler32.
    const vpsadbw = decodeInsn(&[_]u8{ 0xC5, 0xE1, 0xF6, 0xE4 });
    try testing.expectEqual(Op.vpsadbw, vpsadbw.op);
    state.xmm[3] = [_]u8{10} ** 16;
    state.xmm[4] = [_]u8{3} ** 16;
    state.execute(vpsadbw);
    try testing.expectEqual([4]u64{ 56, 56, 0, 0 }, testGetLanes(&state, 4));
}

test "a waitable timer signals at its due tick, re-arms when periodic, and a synchronization timer is consumed" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const tick = WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    const handle: u64 = 0xFFFF_F000_0000_0F01;
    state.registerWindowsTimer(handle, false);
    try testing.expect(state.windowsWaitObjectKnown(handle));
    try testing.expectEqual(false, state.windowsWaitObjectReady(handle).?);

    // Relative 5 ms (negative, in 100 ns), repeating every 3 ms.
    state.guest_clock.ticks = 10_000;
    try testing.expect(state.setWindowsTimer(handle, -50_000, 3, 0, 0));
    const index = state.windowsWaitObjectIndex(handle).?;
    const due = state.windows_wait_objects[index].due_ticks;
    try testing.expect(due >= 10_000 + 5 * tick);

    // A worker blocked on it with an infinite timeout.
    state.windows_guest_threads[0] = .{ .status = .blocked, .handle = 0xFFFF_F000_0000_0F02, .blocked_wait_handle = handle };
    try testing.expectEqual(@as(u64, 0), state.fireDueWindowsTimers(due - 1));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[0].status);
    try testing.expectEqual(@as(u64, 1), state.fireDueWindowsTimers(due));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);
    try testing.expectEqual(handle, state.windows_guest_threads[0].wait_resume_handle);
    // The waiter took the synchronization timer's signal with it, and the
    // period moved the next due tick on.
    try testing.expectEqual(false, state.windows_wait_objects[index].signaled);
    try testing.expectEqual(due + 3 * tick, state.windows_wait_objects[index].due_ticks);

    try testing.expect(state.cancelWindowsTimer(handle));
    try testing.expectEqual(@as(u32, 0), state.windows_armed_timers);

    // An absolute FILETIME two milliseconds past "now", on a notification
    // timer, stays signalled after a wait is satisfied by it.
    const notification: u64 = 0xFFFF_F000_0000_0F03;
    state.registerWindowsTimer(notification, true);
    try testing.expect(state.setWindowsTimer(notification, 1_000 + 20_000, 0, 1_000, 0));
    state.guest_clock.ticks = state.windows_wait_objects[state.windowsWaitObjectIndex(notification).?].due_ticks;
    try testing.expect(state.windowsWaitObjectReady(notification).?);
    state.consumeWindowsWaitObject(notification);
    try testing.expect(state.windowsWaitObjectReady(notification).?);
    try testing.expectEqual(@as(u32, 0), state.windows_armed_timers);
    try testing.expect(!state.setWindowsTimer(0xFFFF_F000_0000_0F04, -1, 0, 0, 0));
}

test "a worker slice that repeats its exact state without a kernel call backs off, and any other slice resets it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_guest_threads[0] = .{ .status = .runnable, .handle = 0xFFFF_F000_0000_0A01, .kernel_calls = 5 };
    state.noteWindowsGuestSliceShape(0, true, 5);
    try testing.expectEqual(@as(u8, 1), state.windows_guest_threads[0].spin_skip_remaining);
    state.noteWindowsGuestSliceShape(0, true, 5);
    state.noteWindowsGuestSliceShape(0, true, 5);
    state.noteWindowsGuestSliceShape(0, true, 5);
    state.noteWindowsGuestSliceShape(0, true, 5);
    try testing.expectEqual(WINDOWS_GUEST_SPIN_MAX_BACKOFF, state.windows_guest_threads[0].spin_backoff);
    // A kernel call during the slice is not a spin.
    state.windows_guest_threads[0].kernel_calls = 6;
    state.noteWindowsGuestSliceShape(0, true, 5);
    try testing.expectEqual(@as(u8, 0), state.windows_guest_threads[0].spin_backoff);
    try testing.expectEqual(@as(u64, 5), state.windows_spin_slices);
}

test "the XMA register census names kicks, locks and clears from the faults that deliver them" {
    var census = GuestXmaRegisterCensus{};
    // The title stores big-endian: 0x80000000 to Context5Clear arrives as the
    // little-endian dword 0x00000080, and the decoder byte-swaps it back.
    census.note(GuestXmaRegisterCensus.clear_first + 5, true, 0x0000_0080, 10);
    try testing.expectEqual(@as(u64, 1), census.clears);
    try testing.expectEqual(@as(u64, 0), census.kicks);
    try testing.expectEqual(@as(u32, 0x8000_0000), census.entries[0].last_value);
    census.note(GuestXmaRegisterCensus.kick_first, true, 0x0100_0000, 11);
    census.note(GuestXmaRegisterCensus.kick_first, true, 0x0300_0000, 12);
    // A zero kick asks for nothing.
    census.note(GuestXmaRegisterCensus.kick_first + 1, true, 0, 13);
    try testing.expectEqual(@as(u64, 2), census.kicks);
    try testing.expectEqual(@as(u32, 2), census.kicked_contexts);
    census.note(GuestXmaRegisterCensus.current_context_index, false, 0, 14);
    try testing.expectEqual(@as(u64, 5), census.faults);
    try testing.expectEqual(@as(usize, 4), census.count);
    try testing.expectEqualStrings("Kick", GuestXmaRegisterCensus.registerName(0x0653));
    try testing.expectEqualStrings("Clear", GuestXmaRegisterCensus.registerName(0x06A9));
    try testing.expectEqualStrings("ContextArrayAddress", GuestXmaRegisterCensus.registerName(0x0600));
}

test "frame cost keeps a bounded window of swap intervals and per-thread shares" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_guest_threads[0] = .{ .status = .runnable, .handle = 0xA01, .executed_steps = 1000 };
    state.windows_guest_threads[1] = .{ .status = .runnable, .handle = 0xA02, .executed_steps = 500 };
    _ = state.spin_watch.arm(MEM_BASE + 0x2000, 4, 0);
    try testing.expect(state.traceWithholdsWriteTlb(MEM_BASE + 0x2000));
    state.noteFrameCostSwap(10_000);
    try testing.expect(!state.spin_watch.armed());
    try testing.expect(!state.traceWithholdsWriteTlb(MEM_BASE + 0x2000));
    state.windows_guest_threads[0].executed_steps = 7000;
    state.windows_guest_threads[1].executed_steps = 1500;
    state.noteFrameCostSwap(17_000);
    try testing.expectEqual(@as(u64, 2), state.frame_cost.swaps);
    try testing.expectEqual(@as(u64, 7000), state.frame_cost.meanRecentInterval());
    try testing.expectEqual(@as(u64, 6000), state.frame_cost.threads[0].since_first_swap);
    try testing.expectEqual(@as(u64, 1000), state.frame_cost.threads[1].since_first_swap);
    // A slot reused by another thread starts from its own zero rather than
    // inheriting the previous thread's snapshot.
    state.windows_guest_threads[1] = .{ .status = .runnable, .handle = 0xA03, .executed_steps = 90 };
    state.noteFrameCostSwap(20_000);
    try testing.expectEqual(@as(u64, 0), state.frame_cost.threads[1].since_first_swap);
    try testing.expectEqual(@as(u64, 0xA03), state.frame_cost.threads[1].handle);
    try testing.expectEqual(@as(u64, 5000), state.frame_cost.meanRecentInterval());
    try testing.expectEqual(@as(u64, 3000), state.frame_cost.min_interval);
    try testing.expectEqual(@as(u64, 7000), state.frame_cost.max_interval);
    try testing.expectEqual(@as(u64, 10_000), state.frame_cost.totalSinceFirstSwap());
    var cost = GuestFrameCost{};
    for (0..GuestFrameCost.window + 4) |i| cost.noteInterval(@intCast(i + 1));
    try testing.expectEqual(GuestFrameCost.window, cost.recent_count);
    // The oldest four intervals fell out: the mean of 5..36 is 20.5.
    try testing.expectEqual(@as(u64, 20), cost.meanRecentInterval());
}

test "the front buffer record decodes the fetch constant VdSwap places before XE_SWAP" {
    var window = GpuRingWindow{};
    // dword_0: tiled, pitch 20 (in 32-pixel units); dword_1: format 54
    // (k_2_10_10_10_AS_16_16_16_16), endianness 1, base 0x1FC00000 >> 12;
    // dword_2: 1280x720 as (width - 1, height - 1).
    window.swap_fetch = .{ (1 << 31) | (20 << 22), 54 | (1 << 6) | ((0x1FC0_0000 >> 12) << 12), 1279 | (719 << 13), 0, 0, 0 };
    window.swap_fetch_seen = true;
    window.swap_packets = 1;
    window.swap_frontbuffer = 0x1FC0_0000;
    window.swap_width = 1280;
    window.swap_height = 720;
    window.dc_lut_type0_writes = 3;
    var front = GuestFrontBuffer{};
    front.note(&window);
    try testing.expectEqual(@as(u64, 1), front.swaps);
    try testing.expectEqual(@as(u6, 54), front.format());
    try testing.expectEqualStrings("k_2_10_10_10_AS_16_16_16_16", GuestFrontBuffer.formatName(front.format()));
    try testing.expect(GuestFrontBuffer.usesPwlRamp(front.format()));
    try testing.expect(!GuestFrontBuffer.usesPwlRamp(6));
    try testing.expectEqual(@as(u2, 1), front.endianness());
    try testing.expect(front.tiled());
    try testing.expectEqual(@as(u32, 20), front.pitch());
    try testing.expectEqual(@as(u32, 0x1FC0_0000), front.baseAddress());
    try testing.expectEqual(@as(u32, 1280), front.fetchWidth());
    try testing.expectEqual(@as(u32, 720), front.fetchHeight());
    try testing.expectEqual(@as(u32, 1280), front.width);
    try testing.expectEqual(@as(u64, 3), front.dc_lut_type0_writes);
    try testing.expectEqual(@as(u64, 1) << 54, front.formats_seen);
    // A window without the fetch constant still contributes its DC_LUT count
    // and nothing else.
    var bare = GpuRingWindow{ .dc_lut_type0_writes = 2 };
    front.note(&bare);
    try testing.expectEqual(@as(u64, 1), front.swaps);
    try testing.expectEqual(@as(u64, 5), front.dc_lut_type0_writes);
}

test "the ring decoder captures the swap fetch constant and the XE_SWAP payload" {
    // A ring holding VdSwap's output: a type-0 write of six dwords to 0x4800,
    // then XE_SWAP with its four payload dwords, then type-2 filler.
    const Source = struct {
        dwords: []const u32,
        pub fn readDword(self: @This(), ring_index: u64) ?u32 {
            return if (ring_index < self.dwords.len) self.dwords[ring_index] else null;
        }
        pub fn aliasCheck(self: @This(), ring_index: u64, physical_value: u32) struct { checked: u16, mismatched: u16 } {
            _ = self;
            _ = ring_index;
            _ = physical_value;
            return .{ .checked = 0, .mismatched = 0 };
        }
    };
    const dwords = [_]u32{
        (5 << 16) | 0x4800,                    0x8000_0000, 54 | (0x1FC00 << 12), 1279 | (719 << 13), 0,   0,                  0,
        0xC000_0000 | (3 << 16) | (0x64 << 8), 0x5357_4150, 0x1FC0_0000,          1280,               720, (1 << 16) | 0x1925, 0x3FFF_FFFF,
        0x3FBF_EFFB,                           0x8000_0000,
    };
    var window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(Source{ .dwords = &dwords }, &window, 0, dwords.len, dwords.len);
    try testing.expect(window.swap_fetch_seen);
    try testing.expectEqual(@as(u32, 54 | (0x1FC00 << 12)), window.swap_fetch[1]);
    try testing.expectEqual(@as(u32, 1), window.swap_packets);
    try testing.expectEqual(@as(u32, 0x1FC0_0000), window.swap_frontbuffer);
    try testing.expectEqual(@as(u32, 1280), window.swap_width);
    try testing.expectEqual(@as(u32, 720), window.swap_height);
    // The two-dword DC_LUT_30_COLOR write counts once as a ramp write.
    try testing.expectEqual(@as(u32, 1), window.dc_lut_type0_writes);
    try testing.expectEqual(@as(u32, 2), window.type0);
}

test "the ring decoder does not let a later texture fetch masquerade as the front buffer" {
    const ArraySource = struct {
        dwords: []const u32,

        pub fn readDword(self: @This(), index: u64) ?u32 {
            return if (index < self.dwords.len) self.dwords[@intCast(index)] else null;
        }

        pub fn aliasCheck(self: @This(), index: u64, value: u32) struct { checked: u16, mismatched: u16 } {
            _ = self;
            _ = index;
            _ = value;
            return .{ .checked = 0, .mismatched = 0 };
        }
    };

    const front = [6]u32{ (1 << 31) | (36 << 22), 54 | (1 << 6), 1151 | (639 << 13), 0, 0, 0 };
    const later_texture = [6]u32{ (1 << 31) | (8 << 22), 53 | (1 << 6), 255 | (255 << 13), 0, 0, 0 };
    var ring: [27]u32 = undefined;
    @memset(&ring, 0);
    ring[0] = (5 << 16) | 0x4800;
    @memcpy(ring[1..7], &front);
    ring[7] = 0xC000_0000 | (3 << 16) | (0x64 << 8);
    ring[8] = 0x5357_4150;
    ring[9] = 0x4E20_0000;
    ring[10] = 1152;
    ring[11] = 640;
    ring[12] = (5 << 16) | 0x4800;
    @memcpy(ring[13..19], &later_texture);

    var window = GpuRingWindow{};
    ElfState.decodeGpuRingWindow(ArraySource{ .dwords = &ring }, &window, 0, ring.len, ring.len);
    try testing.expectEqual(@as(u32, 1), window.swap_packets);
    try testing.expect(window.swap_fetch_seen);
    try testing.expectEqual(@as(u32, 54), window.swap_fetch[1] & 0x3F);
    try testing.expectEqual(@as(u32, 1152), window.swap_width);
    try testing.expectEqual(@as(u32, 640), window.swap_height);
}

// ─── Block translation: interpreter-versus-translation differential ───

/// A small x86-64 assembler for the differential tests below: enough of the
/// integer core to build random straight-line bodies whose every instruction
/// the block translator has a template for, plus the loop and halt around
/// them. Registers are numbered 0..15 as the hardware does.
const DifferentialAssembler = struct {
    bytes: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,

    fn deinit(self: *DifferentialAssembler) void {
        self.bytes.deinit(self.allocator);
    }

    fn put(self: *DifferentialAssembler, slice: []const u8) void {
        self.bytes.appendSlice(self.allocator, slice) catch unreachable;
    }

    fn rexW(reg: u8, rm: u8) u8 {
        return 0x48 | (if (reg >= 8) @as(u8, 4) else 0) | (if (rm >= 8) @as(u8, 1) else 0);
    }

    fn modrmReg(reg: u8, rm: u8) u8 {
        return 0xC0 | ((reg & 7) << 3) | (rm & 7);
    }

    fn imm32(self: *DifferentialAssembler, value: u32) void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, value, .little);
        self.put(&buffer);
    }

    /// mov r64, simm32
    fn movImm(self: *DifferentialAssembler, dst: u8, value: i32) void {
        self.put(&.{ rexW(0, dst), 0xC7, modrmReg(0, dst) });
        self.imm32(@bitCast(value));
    }

    /// add/sub/and/or/xor/cmp/test r64, r64 by primary opcode.
    fn aluRegReg(self: *DifferentialAssembler, opcode: u8, dst: u8, src: u8) void {
        self.put(&.{ rexW(src, dst), opcode, modrmReg(src, dst) });
    }

    /// Group 1 with an imm8: opcode 0x83 /ext.
    fn aluImm8(self: *DifferentialAssembler, ext: u8, dst: u8, value: i8) void {
        self.put(&.{ rexW(0, dst), 0x83, modrmReg(ext, dst), @bitCast(value) });
    }

    /// Group 1 with an imm32: opcode 0x81 /ext.
    fn aluImm32(self: *DifferentialAssembler, ext: u8, dst: u8, value: i32) void {
        self.put(&.{ rexW(0, dst), 0x81, modrmReg(ext, dst) });
        self.imm32(@bitCast(value));
    }

    fn imulRegReg(self: *DifferentialAssembler, dst: u8, src: u8) void {
        self.put(&.{ rexW(dst, src), 0x0F, 0xAF, modrmReg(dst, src) });
    }

    fn imulImm8(self: *DifferentialAssembler, dst: u8, src: u8, value: i8) void {
        self.put(&.{ rexW(dst, src), 0x6B, modrmReg(dst, src), @bitCast(value) });
    }

    /// shl (4), shr (5), sar (7) r64, imm8
    fn shiftImm(self: *DifferentialAssembler, ext: u8, dst: u8, count: u8) void {
        self.put(&.{ rexW(0, dst), 0xC1, modrmReg(ext, dst), count });
    }

    /// inc (0) / dec (1) r64
    fn incDec(self: *DifferentialAssembler, ext: u8, dst: u8) void {
        self.put(&.{ rexW(0, dst), 0xFF, modrmReg(ext, dst) });
    }

    /// not (2) / neg (3) r64
    fn notNeg(self: *DifferentialAssembler, ext: u8, dst: u8) void {
        self.put(&.{ rexW(0, dst), 0xF7, modrmReg(ext, dst) });
    }

    /// lea r64, [base + disp32]; base must not be rsp/r12.
    fn lea(self: *DifferentialAssembler, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x8D, 0x80 | ((dst & 7) << 3) | (base & 7) });
        self.imm32(@bitCast(disp));
    }

    /// mov r64, [base + disp32]
    fn load(self: *DifferentialAssembler, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x8B, 0x80 | ((dst & 7) << 3) | (base & 7) });
        self.imm32(@bitCast(disp));
    }

    /// mov [base + disp32], r64
    fn store(self: *DifferentialAssembler, src: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(src, base), 0x89, 0x80 | ((src & 7) << 3) | (base & 7) });
        self.imm32(@bitCast(disp));
    }

    /// movzx r64, byte [base + disp32]
    fn movzxByte(self: *DifferentialAssembler, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x0F, 0xB6, 0x80 | ((dst & 7) << 3) | (base & 7) });
        self.imm32(@bitCast(disp));
    }

    /// movsxd r64, dword [base + disp32]
    fn movsxd(self: *DifferentialAssembler, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x63, 0x80 | ((dst & 7) << 3) | (base & 7) });
        self.imm32(@bitCast(disp));
    }

    fn cmov(self: *DifferentialAssembler, cond: u8, dst: u8, src: u8) void {
        self.put(&.{ rexW(dst, src), 0x0F, 0x40 | cond, modrmReg(dst, src) });
    }

    fn setcc(self: *DifferentialAssembler, cond: u8, dst: u8) void {
        self.put(&.{ 0x40 | (if (dst >= 8) @as(u8, 1) else 0), 0x0F, 0x90 | cond, modrmReg(0, dst) });
    }

    fn push(self: *DifferentialAssembler, reg: u8) void {
        if (reg >= 8) self.put(&.{0x41});
        self.put(&.{0x50 | (reg & 7)});
    }

    fn pop(self: *DifferentialAssembler, reg: u8) void {
        if (reg >= 8) self.put(&.{0x41});
        self.put(&.{0x58 | (reg & 7)});
    }

    /// jcc rel8 forward over `skip` bytes.
    fn jccOver(self: *DifferentialAssembler, cond: u8, skip: u8) void {
        self.put(&.{ 0x70 | cond, skip });
    }

    /// jnz rel32 backwards to `target` (an offset into `bytes`).
    fn jnzBack(self: *DifferentialAssembler, target: usize) void {
        const next: i64 = @intCast(self.bytes.items.len + 6);
        const rel: i32 = @intCast(@as(i64, @intCast(target)) - next);
        self.put(&.{ 0x0F, 0x85 });
        self.imm32(@bitCast(rel));
    }

    fn hlt(self: *DifferentialAssembler) void {
        self.put(&.{0xF4});
    }

    /// A `[base + disp32]` ModRM (mod = 10) for a register field.
    fn memOperand(self: *DifferentialAssembler, reg: u8, base: u8, disp: i32) void {
        self.put(&.{0x80 | ((reg & 7) << 3) | (base & 7)});
        self.imm32(@bitCast(disp));
    }

    /// Group 1 `op [base + disp32], r64` (opcodes 01/29/21/09/31/39, and 85 for test).
    fn aluMemReg(self: *DifferentialAssembler, opcode: u8, reg: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(reg, base), opcode });
        self.memOperand(reg, base, disp);
    }

    /// Group 1 `op r64, [base + disp32]` (opcodes 03/2B/23/0B/33/3B, 13 adc, 1B sbb).
    fn aluRegMem(self: *DifferentialAssembler, opcode: u8, reg: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(reg, base), opcode });
        self.memOperand(reg, base, disp);
    }

    /// Group 1 `op qword [base + disp32], imm8` (0x83 /ext).
    fn aluMemImm8(self: *DifferentialAssembler, ext: u8, base: u8, disp: i32, value: i8) void {
        self.put(&.{ rexW(0, base), 0x83 });
        self.memOperand(ext, base, disp);
        self.put(&.{@bitCast(value)});
    }

    /// inc (0) / dec (1) qword [base + disp32]
    fn incDecMem(self: *DifferentialAssembler, ext: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(0, base), 0xFF });
        self.memOperand(ext, base, disp);
    }

    /// not (2) / neg (3) qword [base + disp32]
    fn notNegMem(self: *DifferentialAssembler, ext: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(0, base), 0xF7 });
        self.memOperand(ext, base, disp);
    }

    fn imulRegMem(self: *DifferentialAssembler, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x0F, 0xAF });
        self.memOperand(dst, base, disp);
    }

    /// Group-1 `op r, r` at 8, 16 or 32 bits; `opcode` is the 64-bit form's
    /// (01 add, 29 sub, 21 and, 09 or, 31 xor, 39 cmp, 85 test). A REX is
    /// always emitted, so registers 4-7 are spl/bpl/sil/dil at 8 bits.
    fn aluRegRegSized(self: *DifferentialAssembler, opcode: u8, dst: u8, src: u8, bits_wide: u8) void {
        const rex: u8 = 0x40 | (if (src >= 8) @as(u8, 4) else 0) | (if (dst >= 8) @as(u8, 1) else 0);
        switch (bits_wide) {
            8 => self.put(&.{ rex, opcode - 1, modrmReg(src, dst) }),
            16 => self.put(&.{ 0x66, rex, opcode, modrmReg(src, dst) }),
            else => self.put(&.{ rex, opcode, modrmReg(src, dst) }),
        }
    }

    /// Group-1 `op r, imm8` at 8, 16 or 32 bits (80 /ext ib, or 83 /ext ib).
    fn aluImm8Sized(self: *DifferentialAssembler, ext: u8, dst: u8, value: i8, bits_wide: u8) void {
        const rex: u8 = 0x40 | (if (dst >= 8) @as(u8, 1) else 0);
        switch (bits_wide) {
            8 => self.put(&.{ rex, 0x80, modrmReg(ext, dst), @bitCast(value) }),
            16 => self.put(&.{ 0x66, rex, 0x83, modrmReg(ext, dst), @bitCast(value) }),
            else => self.put(&.{ rex, 0x83, modrmReg(ext, dst), @bitCast(value) }),
        }
    }

    /// inc (0) / dec (1) at 8, 16 or 32 bits.
    fn incDecSized(self: *DifferentialAssembler, ext: u8, dst: u8, bits_wide: u8) void {
        const rex: u8 = 0x40 | (if (dst >= 8) @as(u8, 1) else 0);
        switch (bits_wide) {
            8 => self.put(&.{ rex, 0xFE, modrmReg(ext, dst) }),
            16 => self.put(&.{ 0x66, rex, 0xFF, modrmReg(ext, dst) }),
            else => self.put(&.{ rex, 0xFF, modrmReg(ext, dst) }),
        }
    }

    /// setcc byte [base + disp32]
    fn setccMem(self: *DifferentialAssembler, cond: u8, base: u8, disp: i32) void {
        self.put(&.{ 0x40 | (if (base >= 8) @as(u8, 1) else 0), 0x0F, 0x90 | cond });
        self.memOperand(0, base, disp);
    }

    fn cmovMem(self: *DifferentialAssembler, cond: u8, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x0F, 0x40 | cond });
        self.memOperand(dst, base, disp);
    }

    /// movbe r64, [base + disp32]
    fn movbeLoad(self: *DifferentialAssembler, dst: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(dst, base), 0x0F, 0x38, 0xF0 });
        self.memOperand(dst, base, disp);
    }

    /// movbe [base + disp32], r64
    fn movbeStore(self: *DifferentialAssembler, src: u8, base: u8, disp: i32) void {
        self.put(&.{ rexW(src, base), 0x0F, 0x38, 0xF1 });
        self.memOperand(src, base, disp);
    }

    /// rol (0), ror (1), shl (4), shr (5), sar (7) r64, cl
    fn shiftCl(self: *DifferentialAssembler, ext: u8, dst: u8) void {
        self.put(&.{ rexW(0, dst), 0xD3, modrmReg(ext, dst) });
    }

    /// rol (0) / ror (1) r64, imm8
    fn rotateImm(self: *DifferentialAssembler, ext: u8, dst: u8, count: u8) void {
        self.put(&.{ rexW(0, dst), 0xC1, modrmReg(ext, dst), count });
    }

    /// bt (A3) / bts (AB) / btr (B3) r64, r64: the bit index is the reg field.
    fn bitTestRegReg(self: *DifferentialAssembler, opcode: u8, dst: u8, index: u8) void {
        self.put(&.{ rexW(index, dst), 0x0F, opcode, modrmReg(index, dst) });
    }

    /// bt (4) / bts (5) / btr (6) r64, imm8
    fn bitTestRegImm(self: *DifferentialAssembler, ext: u8, dst: u8, bit: u8) void {
        self.put(&.{ rexW(0, dst), 0x0F, 0xBA, modrmReg(ext, dst), bit });
    }

    /// bsf (BC) / bsr (BD) r64, r64, or tzcnt/lzcnt with the F3 prefix.
    fn bitScan(self: *DifferentialAssembler, opcode: u8, dst: u8, src: u8, count_zeros: bool) void {
        if (count_zeros) self.put(&.{0xF3});
        self.put(&.{ rexW(dst, src), 0x0F, opcode, modrmReg(dst, src) });
    }

    /// xchg r64, r64 (0x87 /r)
    fn xchgRegReg(self: *DifferentialAssembler, dst: u8, src: u8) void {
        self.put(&.{ rexW(src, dst), 0x87, modrmReg(src, dst) });
    }

    /// mul (4) / imul (5) / div (6) / idiv (7) r64
    fn mulDiv(self: *DifferentialAssembler, ext: u8, src: u8) void {
        self.put(&.{ rexW(0, src), 0xF7, modrmReg(ext, src) });
    }

    fn cqo(self: *DifferentialAssembler) void {
        self.put(&.{ 0x48, 0x99 });
    }

    /// call rel32 to `target` (an offset into `bytes`).
    fn callRel32(self: *DifferentialAssembler, target: usize) void {
        const next: i64 = @intCast(self.bytes.items.len + 5);
        const rel: i32 = @intCast(@as(i64, @intCast(target)) - next);
        self.put(&.{0xE8});
        self.imm32(@bitCast(rel));
    }

    fn ret(self: *DifferentialAssembler) void {
        self.put(&.{0xC3});
    }

    /// jmp rel8 forward over `skip` bytes.
    fn jmpOver(self: *DifferentialAssembler, skip: u8) void {
        self.put(&.{ 0xEB, skip });
    }

    /// A three-byte VEX prefix. `map` 1/2/3 = 0F/0F38/0F3A, `pp` 0/1/2/3 =
    /// none/66/F3/F2; `reg` is the ModRM.reg register, `vvvv` the extra
    /// source (0 when the form has none), `rm` the ModRM.rm register or base.
    fn vex(self: *DifferentialAssembler, map: u8, pp: u8, w: bool, reg: u8, vvvv: u8, rm: u8) void {
        const r_bar: u8 = if (reg >= 8) 0 else 0x80;
        const b_bar: u8 = if (rm >= 8) 0 else 0x20;
        self.put(&.{ 0xC4, r_bar | 0x40 | b_bar | map, (if (w) @as(u8, 0x80) else 0) | ((~vvvv & 0xF) << 3) | pp });
    }

    /// VEX op with three register operands (reg = dst, vvvv = src1, rm = src2).
    fn vexRR(self: *DifferentialAssembler, map: u8, pp: u8, w: bool, opcode: u8, reg: u8, vvvv: u8, rm: u8) void {
        self.vex(map, pp, w, reg, vvvv, rm);
        self.put(&.{ opcode, modrmReg(reg, rm) });
    }

    fn vexRRI(self: *DifferentialAssembler, map: u8, pp: u8, w: bool, opcode: u8, reg: u8, vvvv: u8, rm: u8, imm: u8) void {
        self.vexRR(map, pp, w, opcode, reg, vvvv, rm);
        self.put(&.{imm});
    }

    /// VEX op with a `[rbx + disp32]` memory operand in rm.
    fn vexRM(self: *DifferentialAssembler, map: u8, pp: u8, w: bool, opcode: u8, reg: u8, vvvv: u8, disp: i32) void {
        self.vex(map, pp, w, reg, vvvv, 3);
        self.put(&.{opcode});
        self.memOperand(reg, 3, disp);
    }

    fn vexRMI(self: *DifferentialAssembler, map: u8, pp: u8, w: bool, opcode: u8, reg: u8, vvvv: u8, disp: i32, imm: u8) void {
        self.vexRM(map, pp, w, opcode, reg, vvvv, disp);
        self.put(&.{imm});
    }

    fn vzeroupper(self: *DifferentialAssembler) void {
        self.put(&.{ 0xC5, 0xF8, 0x77 });
    }

    /// A VEX.256 (L=1) register or `[rbx + disp32]` form.
    fn vex256(self: *DifferentialAssembler, map: u8, pp: u8, opcode: u8, reg: u8, vvvv: u8, rm: ?u8, disp: i32) void {
        const r_bar: u8 = if (reg >= 8) 0 else 0x80;
        const b_bar: u8 = if ((rm orelse 3) >= 8) 0 else 0x20;
        self.put(&.{ 0xC4, r_bar | 0x40 | b_bar | map, ((~vvvv & 0xF) << 3) | 0x04 | pp, opcode });
        if (rm) |register| self.put(&.{modrmReg(reg, register)}) else self.memOperand(reg, 3, disp);
    }

    /// vldmxcsr / vstmxcsr `[rbx + disp32]` (VEX.LZ.0F AE /2, /3).
    fn vmxcsr(self: *DifferentialAssembler, is_store: bool, disp: i32) void {
        self.put(&.{ 0xC5, 0xF8, 0xAE });
        self.memOperand(if (is_store) 3 else 2, 3, disp);
    }

    /// `lock xadd|cmpxchg|xchg [rbx + disp32], reg` at 16, 32 or 64 bits.
    fn lockedMemReg(self: *DifferentialAssembler, kind: u8, size: u8, reg: u8, disp: i32) void {
        if (size == 16) self.put(&.{0x66});
        if (kind != 2) self.put(&.{0xF0});
        const rex: u8 = (if (size == 64) @as(u8, 0x48) else 0x40) | (if (reg >= 8) @as(u8, 4) else 0);
        if (rex != 0x40) self.put(&.{rex});
        switch (kind) {
            0 => self.put(&.{ 0x0F, 0xC1 }), // xadd
            1 => self.put(&.{ 0x0F, 0xB1 }), // cmpxchg
            else => self.put(&.{0x87}), // xchg
        }
        self.memOperand(reg, 3, disp);
    }

    /// add|sub rbx, imm8 - moves the data base the hoist planner picks.
    fn moveBase(self: *DifferentialAssembler, subtract: bool, amount: i8) void {
        self.put(&.{ 0x48, 0x83, if (subtract) @as(u8, 0xEB) else 0xC3, @bitCast(amount) });
    }
};

/// One random AVX-128 instruction over xmm0-xmm7, `[rbx + disp]` and the
/// general registers the integer body leaves free: the forms the vector
/// templates compile, in the encodings Xenia's emitter and MinGW produce.
fn buildVectorBody(asm_: *DifferentialAssembler, random: std.Random, count: usize) void {
    const gprs = [_]u8{ 0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 13, 14 };
    var emitted: usize = 0;
    while (emitted < count) : (emitted += 1) {
        const dst = random.uintLessThan(u8, 8);
        const src1 = random.uintLessThan(u8, 8);
        const src2 = random.uintLessThan(u8, 8);
        const gpr = gprs[random.uintLessThan(usize, gprs.len)];
        const disp: i32 = @intCast(random.uintLessThan(u32, 0xFF) * 16);
        const imm = random.int(u8);
        switch (random.uintLessThan(u8, 44)) {
            // moves
            0 => asm_.vexRR(1, 0, false, 0x28, dst, 0, src2), // vmovaps x, x
            1 => asm_.vexRM(1, 0, false, 0x28, dst, 0, disp), // vmovaps x, [m]
            2 => asm_.vexRM(1, 0, false, 0x29, src1, 0, disp), // vmovaps [m], x
            3 => asm_.vexRM(1, 2, false, 0x6F, dst, 0, disp), // vmovdqu x, [m]
            4 => asm_.vexRM(1, 2, false, 0x7F, src1, 0, disp), // vmovdqu [m], x
            5 => asm_.vexRR(1, 1, false, 0x6E, dst, 0, gpr), // vmovd x, r32
            6 => asm_.vexRR(1, 1, true, 0x6E, dst, 0, gpr), // vmovq x, r64
            7 => asm_.vexRR(1, 1, false, 0x7E, src1, 0, gpr), // vmovd r32, x
            8 => asm_.vexRR(1, 1, true, 0x7E, src1, 0, gpr), // vmovq r64, x
            9 => asm_.vexRR(1, 2, false, 0x7E, dst, 0, src2), // vmovq x, x
            10 => asm_.vexRM(1, 2, false, 0x10, dst, 0, disp), // vmovss x, [m]
            11 => asm_.vexRM(1, 3, false, 0x11, src1, 0, disp), // vmovsd [m], x
            12 => asm_.vexRR(1, 2, false, 0x10, dst, src1, src2), // vmovss x, x, x
            // bitwise and integer
            13 => asm_.vexRR(1, 0, false, ([_]u8{ 0x54, 0x55, 0x56, 0x57 })[random.uintLessThan(usize, 4)], dst, src1, src2), // vandps/vandnps/vorps/vxorps
            14 => asm_.vexRM(1, 1, false, ([_]u8{ 0xDB, 0xDF, 0xEB, 0xEF })[random.uintLessThan(usize, 4)], dst, src1, disp), // vpand/vpandn/vpor/vpxor [m]
            15 => asm_.vexRR(1, 1, false, ([_]u8{ 0xFC, 0xFD, 0xFE, 0xD4, 0xF8, 0xF9, 0xFA, 0xFB })[random.uintLessThan(usize, 8)], dst, src1, src2), // vpadd/vpsub b w d q
            16 => asm_.vexRR(1, 1, false, ([_]u8{ 0x74, 0x75, 0x76, 0x64, 0x65, 0x66 })[random.uintLessThan(usize, 6)], dst, src1, src2), // vpcmpeq/gt b w d
            17 => asm_.vexRR(1, 1, false, ([_]u8{ 0xDA, 0xDE, 0xEA, 0xEE, 0xDC, 0xDD, 0xD8, 0xD9, 0xEC, 0xED, 0xE8, 0xE9, 0xE0, 0xE3, 0xD5 })[random.uintLessThan(usize, 15)], dst, src1, src2), // min/max ub/sw, addus/subus, adds/subs, avg, mullw
            18 => asm_.vexRR(2, 1, false, ([_]u8{ 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F })[random.uintLessThan(usize, 8)], dst, src1, src2), // vpmin/max sb sd uw ud
            19 => asm_.vexRR(1, 1, false, ([_]u8{ 0x60, 0x61, 0x62, 0x6C, 0x68, 0x69, 0x6A, 0x6D })[random.uintLessThan(usize, 8)], dst, src1, src2), // vpunpck l/h bw wd dq qdq
            20 => asm_.vexRR(1, 0, false, if (random.boolean()) 0x14 else 0x15, dst, src1, src2), // vunpckl/hps
            21 => asm_.vexRRI(1, 1, false, 0x72, ([_]u8{ 6, 2, 4 })[random.uintLessThan(usize, 3)], dst, src2, random.uintLessThan(u8, 40)), // vpslld/vpsrld/vpsrad x, x, imm
            22 => asm_.vexRRI(1, 1, false, 0x73, ([_]u8{ 6, 2, 7, 3 })[random.uintLessThan(usize, 4)], dst, src2, random.uintLessThan(u8, 20)), // vpsllq/vpsrlq/vpslldq/vpsrldq
            23 => asm_.vexRRI(1, 1, false, 0x71, ([_]u8{ 6, 2, 4 })[random.uintLessThan(usize, 3)], dst, src2, random.uintLessThan(u8, 20)), // vpsllw/vpsrlw/vpsraw
            24 => asm_.vexRR(2, 1, false, 0x00, dst, src1, src2), // vpshufb
            25 => asm_.vexRRI(1, 1, false, 0x70, dst, 0, src2, imm), // vpshufd
            26 => asm_.vexRRI(1, 0, false, 0xC6, dst, src1, src2, imm), // vshufps
            27 => asm_.vexRR(1, 1, false, ([_]u8{ 0x63, 0x67, 0x6B })[random.uintLessThan(usize, 3)], dst, src1, src2), // vpacksswb/vpackuswb/vpackssdw
            28 => asm_.vexRR(2, 1, false, ([_]u8{ 0x30, 0x31, 0x33, 0x20, 0x23, 0x25 })[random.uintLessThan(usize, 6)], dst, 0, src2), // vpmovzx/sx bw bd wd
            29 => asm_.vexRRI(3, 1, false, 0x4C, dst, src1, src2, @as(u8, random.uintLessThan(u8, 8)) << 4), // vpblendvb with mask xmm
            30 => asm_.vexRRI(3, 1, false, 0x16, src1, 0, gpr, imm), // vpextrd r32, x, imm
            31 => asm_.vexRRI(3, 1, false, 0x22, dst, src1, gpr, imm), // vpinsrd x, x, r32, imm
            // float
            32 => asm_.vexRR(1, 0, false, ([_]u8{ 0x58, 0x59, 0x5C, 0x5E, 0x5D, 0x5F })[random.uintLessThan(usize, 6)], dst, src1, src2), // vadd/mul/sub/div/min/maxps
            33 => asm_.vexRM(1, 1, false, ([_]u8{ 0x58, 0x59, 0x5C, 0x5E, 0x5D, 0x5F })[random.uintLessThan(usize, 6)], dst, src1, disp), // ...pd [m]
            34 => asm_.vexRR(1, 2, false, ([_]u8{ 0x58, 0x59, 0x5C, 0x5E, 0x5D, 0x5F, 0x51 })[random.uintLessThan(usize, 7)], dst, src1, src2), // ...ss, vsqrtss
            35 => asm_.vexRR(1, 3, false, ([_]u8{ 0x58, 0x59, 0x5C, 0x5E, 0x5D, 0x5F, 0x51 })[random.uintLessThan(usize, 7)], dst, src1, src2), // ...sd, vsqrtsd
            36 => asm_.vexRR(1, 0, false, 0x51, dst, 0, src2), // vsqrtps
            37 => asm_.vexRR(1, if (random.boolean()) 0 else 2, false, 0x5B, dst, 0, src2), // vcvtdq2ps / vcvttps2dq
            38 => {
                // vcvtps2pd / vcvtpd2ps are two-operand (VEX.vvvv must be
                // 1111); vcvtss2sd / vcvtsd2ss merge into a first source.
                const pp = random.uintLessThan(u8, 4);
                asm_.vexRR(1, pp, false, 0x5A, dst, if (pp >= 2) src1 else 0, src2);
            },
            39 => asm_.vexRR(1, if (random.boolean()) 2 else 3, random.boolean(), 0x2A, dst, src1, gpr), // vcvtsi2ss/sd x, x, r32/r64
            40 => asm_.vexRR(1, if (random.boolean()) 2 else 3, random.boolean(), if (random.boolean()) 0x2C else 0x2D, gpr, 0, src2), // vcvt(t)ss2si / sd2si
            41 => asm_.vexRR(1, if (random.boolean()) 0 else 1, false, 0x2E, src1, 0, src2), // vucomiss / vucomisd
            42 => asm_.vexRRI(1, 0, false, 0xC2, dst, src1, src2, random.uintLessThan(u8, 8)), // vcmpps imm
            else => asm_.vexRRI(3, 1, false, 0x08, dst, 0, src2, random.uintLessThan(u8, 8)), // vroundps imm
        }
    }
}

/// Build one random loop body: instructions the translator compiles, over
/// registers that leave the loop counter (r15), the data base (rbx) and the
/// stack (rsp) alone. Memory operands stay inside the data region.
fn buildDifferentialBody(asm_: *DifferentialAssembler, random: std.Random, count: usize, subroutine: ?usize) void {
    const usable = [_]u8{ 0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 13, 14 };
    var emitted: usize = 0;
    while (emitted < count) : (emitted += 1) {
        const dst = usable[random.uintLessThan(usize, usable.len)];
        const src = usable[random.uintLessThan(usize, usable.len)];
        // A divisor register other than rax/rdx, which the divide reads.
        const divisor: u8 = if (src == 0 or src == 2) 5 else src;
        const disp: i32 = @intCast(random.uintLessThan(u32, 0x200) * 8);
        switch (random.uintLessThan(u8, 38)) {
            0 => asm_.movImm(dst, random.int(i32)),
            1 => asm_.aluRegReg(0x01, dst, src), // add
            2 => asm_.aluRegReg(0x29, dst, src), // sub
            3 => asm_.aluRegReg(0x21, dst, src), // and
            4 => asm_.aluRegReg(0x09, dst, src), // or
            5 => asm_.aluRegReg(0x31, dst, src), // xor
            6 => asm_.aluRegReg(0x39, dst, src), // cmp
            7 => asm_.aluRegReg(0x85, dst, src), // test
            8 => asm_.aluImm8(random.uintLessThan(u8, 8), dst, random.int(i8)),
            9 => asm_.aluImm32(random.uintLessThan(u8, 8), dst, random.int(i32)),
            10 => asm_.imulRegReg(dst, src),
            11 => asm_.shiftImm(([_]u8{ 4, 5, 7 })[random.uintLessThan(usize, 3)], dst, random.uintLessThan(u8, 64)),
            12 => asm_.incDec(random.uintLessThan(u8, 2), dst),
            13 => asm_.notNeg(2 + random.uintLessThan(u8, 2), dst),
            14 => asm_.lea(dst, 3, disp),
            15 => asm_.load(dst, 3, disp),
            16 => asm_.store(src, 3, disp),
            17 => if (random.boolean()) asm_.movzxByte(dst, 3, disp) else asm_.movsxd(dst, 3, disp),
            18 => asm_.cmov(random.uintLessThan(u8, 16), dst, src),
            19 => {
                asm_.setcc(random.uintLessThan(u8, 16), dst);
                asm_.push(src);
                asm_.pop(dst);
            },
            // The 2026-09-19 templates: memory forms, cl shifts, rotates,
            // bit tests and scans, adc/sbb, movbe, xchg, multiply, divide,
            // and calls into a subroutine that returns.
            20 => asm_.aluMemReg(([_]u8{ 0x01, 0x29, 0x21, 0x09, 0x31, 0x39, 0x85 })[random.uintLessThan(usize, 7)], src, 3, disp),
            21 => asm_.aluRegMem(([_]u8{ 0x03, 0x2B, 0x23, 0x0B, 0x33, 0x3B, 0x13, 0x1B })[random.uintLessThan(usize, 8)], dst, 3, disp),
            22 => asm_.aluMemImm8(random.uintLessThan(u8, 8), 3, disp, random.int(i8)),
            23 => if (random.boolean()) asm_.incDecMem(random.uintLessThan(u8, 2), 3, disp) else asm_.notNegMem(2 + random.uintLessThan(u8, 2), 3, disp),
            24 => if (random.boolean()) asm_.imulRegMem(dst, 3, disp) else asm_.cmovMem(random.uintLessThan(u8, 16), dst, 3, disp),
            25 => if (random.boolean()) asm_.movbeLoad(dst, 3, disp) else asm_.movbeStore(src, 3, disp),
            26 => asm_.shiftCl(([_]u8{ 4, 5, 7 })[random.uintLessThan(usize, 3)], dst),
            27 => asm_.shiftCl(random.uintLessThan(u8, 2), dst),
            28 => asm_.rotateImm(random.uintLessThan(u8, 2), dst, random.uintLessThan(u8, 64)),
            29 => asm_.bitTestRegReg(([_]u8{ 0xA3, 0xAB, 0xB3 })[random.uintLessThan(usize, 3)], dst, src),
            30 => asm_.bitTestRegImm(4 + random.uintLessThan(u8, 3), dst, random.int(u8)),
            31 => asm_.bitScan(0xBC + random.uintLessThan(u8, 2), dst, src, random.boolean()),
            32 => asm_.aluRegReg(if (random.boolean()) 0x11 else 0x19, dst, src), // adc / sbb
            33 => asm_.xchgRegReg(dst, src),
            34 => asm_.mulDiv(4 + random.uintLessThan(u8, 2), src), // mul / imul
            35 => {
                // A non-faulting unsigned divide: rdx = 0, divisor = 7.
                asm_.movImm(2, 0);
                asm_.movImm(divisor, 7);
                asm_.mulDiv(6, divisor);
            },
            36 => {
                // A non-faulting signed divide: rdx = sign(rax), divisor = 7.
                asm_.cqo();
                asm_.movImm(divisor, 7);
                asm_.mulDiv(7, divisor);
            },
            else => if (subroutine) |target| asm_.callRel32(target) else asm_.aluRegReg(0x01, dst, src),
        }
        // Occasionally a forward conditional skip over one register move,
        // so blocks end on branches that are taken and not taken.
        if (random.uintLessThan(u8, 4) == 0) {
            asm_.jccOver(random.uintLessThan(u8, 16), 3);
            asm_.aluRegReg(0x01, dst, src);
        }
    }
}

const DifferentialOutcome = struct {
    regs: ElfRegs,
    exit_code: u64,
    terminated: bool,
    faulted: bool,
    xmm: [16][16]u8,
    ymm_hi: [16][16]u8,
    zmm_hi: [16][32]u8,
    data: [0x1000]u8,
    translated_instructions: u64,
    compiled_blocks: u64,
    verified_blocks: u64,
    mismatches: u64,
    /// Live compiled blocks whose address still held a hotness entry.
    compiled_still_counting: u64 = 0,
    fused_runs: u64 = 0,
    verify_memory_checked: u64 = 0,
    verify_memory_mismatches: u64 = 0,
    verify_memory_failed: u64 = 0,
    verify_memory_unsafe: u64 = 0,
    /// The vector registers before the first instruction, when
    /// `DifferentialConfig.seed_all_vectors` set them.
    initial_xmm: [16][16]u8 = @splat(@splat(0)),
    initial_ymm_hi: [16][16]u8 = @splat(@splat(0)),
};

fn runDifferentialProgram(program: []const u8, seed: u64, translate: bool) DifferentialOutcome {
    return runDifferentialProgramWith(program, seed, translate, false);
}

fn runDifferentialProgramWith(program: []const u8, seed: u64, translate: bool, verify_memory: bool) DifferentialOutcome {
    return runDifferentialProgramConfigured(program, seed, translate, .{ .verify_memory = verify_memory });
}

const DifferentialConfig = struct {
    verify_memory: bool = false,
    /// Translate under the Windows calling convention, as a hosted PE runs:
    /// no flag passes into a call, and a return owes what
    /// `block_jit.returnFlagsLive` finds.
    windows_abi: bool = false,
    /// Give all sixteen vector registers, both halves, distinct random
    /// contents (the default seeds xmm0-xmm7 only), and record them in the
    /// outcome so a test can tell which registers an instruction wrote.
    seed_all_vectors: bool = false,
    /// General registers (bit = x86 register number) pointed at the middle
    /// of the data window, so a memory form using them as its base reads and
    /// writes there.
    base_registers: u16 = 0,
    /// General registers given the value 8, for a memory form's index.
    index_registers: u16 = 0,
    /// Vector registers (bit = register number) given different contents,
    /// both halves, from `perturb_seed`, after everything else is seeded the
    /// same way: a run that differs from the unperturbed one somewhere other
    /// than these registers read one of them.
    perturb_vectors: u16 = 0,
    perturb_seed: u64 = 0,
};

fn runDifferentialProgramConfigured(program: []const u8, seed: u64, translate: bool, config: DifferentialConfig) DifferentialOutcome {
    const verify_memory = config.verify_memory;
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = config.windows_abi;
    const code = MEM_BASE + 0x1000;
    const data = MEM_BASE + 0x20000;
    const stack = MEM_BASE + 0x40000;
    @memcpy(state.mem[0x1000..][0..program.len], program);
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    random.bytes(state.mem[0x20000..][0..0x1000]);
    inline for (.{ "rax", "rcx", "rdx", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14" }) |name| {
        @field(state.regs, name) = random.int(u64);
    }
    for (state.xmm[0..8]) |*register| random.bytes(register);
    if (config.seed_all_vectors) {
        for (state.xmm[0..16]) |*register| random.bytes(register);
        for (state.ymm_hi[0..16]) |*register| random.bytes(register);
    }
    if (config.perturb_vectors != 0) {
        var perturb = std.Random.DefaultPrng.init(config.perturb_seed);
        for (0..16) |register| {
            if (config.perturb_vectors & (@as(u16, 1) << @intCast(register)) == 0) continue;
            perturb.random().bytes(&state.xmm[register]);
            perturb.random().bytes(&state.ymm_hi[register]);
        }
    }
    const initial_xmm = state.xmm[0..16].*;
    const initial_ymm_hi = state.ymm_hi[0..16].*;
    inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" }, 0..) |name, number| {
        if (config.base_registers & (1 << number) != 0) @field(state.regs, name) = data + 0x800;
        if (config.index_registers & (1 << number) != 0) @field(state.regs, name) = 8;
    }
    state.regs.rbx = data;
    state.regs.rsp = stack;
    state.regs.r15 = 40;
    state.regs.rip = code;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = translate;
    state.block_jit_verify_memory = verify_memory;
    state.block_jit_hot_threshold = 2;
    state.runWithLimit(400_000);
    var outcome = DifferentialOutcome{
        .initial_xmm = initial_xmm,
        .initial_ymm_hi = initial_ymm_hi,
        .regs = state.regs,
        .exit_code = state.exit_code,
        .terminated = state.terminated,
        .faulted = state.faulted,
        .xmm = state.xmm[0..16].*,
        .ymm_hi = state.ymm_hi[0..16].*,
        .zmm_hi = state.zmm_hi[0..16].*,
        .data = undefined,
        .translated_instructions = 0,
        .compiled_blocks = 0,
        .verified_blocks = 0,
        .mismatches = 0,
    };
    @memcpy(&outcome.data, state.mem[0x20000..][0..0x1000]);
    if (state.block_jit) |jit| {
        outcome.translated_instructions = jit.instructions_retired;
        outcome.compiled_blocks = jit.compiled;
        outcome.fused_runs = jit.fused_runs;
        outcome.verify_memory_checked = jit.verify_memory_checked;
        outcome.verify_memory_mismatches = jit.verify_memory_mismatches;
        outcome.verify_memory_failed = jit.verify_memory_failed;
        outcome.verify_memory_unsafe = jit.verify_memory_unsafe;
        outcome.verified_blocks = jit.verified;
        outcome.mismatches = jit.mismatches;
        for (jit.blocks) |maybe| {
            const block = maybe orelse continue;
            const base = jit.firstSlot(block.start_rip);
            for (jit.hotness[base .. base + BLOCK_JIT_WAYS]) |entry| {
                if (entry.rip == block.start_rip and !entry.refused) outcome.compiled_still_counting += 1;
            }
        }
    }
    return outcome;
}

test "translated blocks retire the same state as the interpreter over random integer programs" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0x7E57_B10C);
    const random = prng.random();
    var total_translated: u64 = 0;
    var total_verified: u64 = 0;
    for (0..64) |trial| {
        var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
        defer asm_.deinit();
        // A subroutine the body may call: add rax, 1 ; ret, skipped on entry.
        asm_.jmpOver(5);
        const subroutine = asm_.bytes.items.len;
        asm_.aluImm8(0, 0, 1);
        asm_.ret();
        const body_start = asm_.bytes.items.len;
        buildDifferentialBody(&asm_, random, 4 + random.uintLessThan(usize, 10), subroutine);
        asm_.incDec(1, 15); // dec r15
        asm_.jnzBack(body_start);
        asm_.hlt();
        const seed = 0x1000 + trial;
        const interpreted = runDifferentialProgram(asm_.bytes.items, seed, false);
        const translated = runDifferentialProgram(asm_.bytes.items, seed, true);
        try std.testing.expect(interpreted.terminated and translated.terminated);
        try std.testing.expectEqual(interpreted.faulted, translated.faulted);
        try std.testing.expectEqual(interpreted.exit_code, translated.exit_code);
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
            if (@field(interpreted.regs, name) != @field(translated.regs, name)) {
                std.debug.print("trial {d}: {s} differs interpreter=0x{x} translated=0x{x} program={any}\n", .{ trial, name, @field(interpreted.regs, name), @field(translated.regs, name), asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        try std.testing.expectEqual(interpreted.regs.rflags, translated.regs.rflags);
        try std.testing.expectEqualSlices(u8, &interpreted.data, &translated.data);
        try std.testing.expectEqual(@as(u64, 0), translated.mismatches);
        try std.testing.expect(translated.compiled_blocks > 0);
        // A compiled address gives its hotness way back to warming ones.
        try std.testing.expectEqual(@as(u64, 0), translated.compiled_still_counting);
        total_translated += translated.translated_instructions;
        total_verified += translated.verified_blocks;
    }
    // The loops ran forty times each; the second pass and every later one
    // ran as ARM64, so most of the work was translated.
    try std.testing.expect(total_translated > 1000);
    try std.testing.expect(total_verified > 0);
}

test "the memory-aware cross-check passes correct translations of programs that load and store" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0x7E57_B10D);
    const random = prng.random();
    var checked: u64 = 0;
    for (0..48) |trial| {
        var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
        defer asm_.deinit();
        asm_.jmpOver(5);
        const subroutine = asm_.bytes.items.len;
        asm_.aluImm8(0, 0, 1);
        asm_.ret();
        const body_start = asm_.bytes.items.len;
        buildDifferentialBody(&asm_, random, 4 + random.uintLessThan(usize, 10), subroutine);
        asm_.incDec(1, 15); // dec r15
        asm_.jnzBack(body_start);
        asm_.hlt();
        const seed = 0x3000 + trial;
        const interpreted = runDifferentialProgram(asm_.bytes.items, seed, false);
        const verified = runDifferentialProgramWith(asm_.bytes.items, seed, true, true);
        try std.testing.expect(interpreted.terminated and verified.terminated);
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
            if (@field(interpreted.regs, name) != @field(verified.regs, name)) {
                std.debug.print("trial {d}: {s} differs interpreter=0x{x} verified=0x{x} program={any}\n", .{ trial, name, @field(interpreted.regs, name), @field(verified.regs, name), asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        try std.testing.expectEqualSlices(u8, &interpreted.data, &verified.data);
        // A correct translation is never reported as wrong.
        try std.testing.expectEqual(@as(u64, 0), verified.verify_memory_mismatches);
        checked += verified.verify_memory_checked;
    }
    // The check ran: blocks that touch memory were compared, not skipped.
    try std.testing.expect(checked > 20);
}

test "the memory-aware cross-check catches a translation that stores a wrong value and puts the interpreter's back" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    // mov rax, [rbx+0x10] ; add rax, 0x5a ; mov [rbx+0x18], rax ; hlt
    const program = [_]u8{ 0x48, 0x8B, 0x43, 0x10, 0x48, 0x83, 0xC0, 0x5A, 0x48, 0x89, 0x43, 0x18, 0xF4 };
    @memcpy(state.mem[0x1000..][0..program.len], &program);
    std.mem.writeInt(u64, state.mem[0x20010..][0..8], 100, .little);
    state.regs.rbx = MEM_BASE + 0x20000;
    state.regs.rsp = MEM_BASE + 0x40000;
    state.regs.rip = MEM_BASE + 0x1000;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = true;
    state.block_jit_verify_memory = true;
    const jit = state.blockJitActive() orelse return error.NoJit;
    const block = state.compileBlockJit(jit, MEM_BASE + 0x1000) orelse return error.Refused;
    defer freeTranslatedBlock(testing.allocator, block);
    try testing.expect(block.needs_verify);
    // Break the translation: the add's 0x5a becomes 0x5b, wherever it is
    // encoded (an add/adds immediate or a movz).
    var patched = false;
    for (block.code, 0..) |word, index| {
        const top = word >> 24;
        const is_add_imm = (top == 0x91 or top == 0xB1 or top == 0x11 or top == 0x31) and ((word >> 10) & 0xFFF) == 0x5a and ((word >> 22) & 3) == 0;
        const is_movz = ((word & 0xFFE0_0000) == 0xD280_0000 or (word & 0xFFE0_0000) == 0x5280_0000) and ((word >> 5) & 0xFFFF) == 0x5a;
        if (!is_add_imm and !is_movz) continue;
        const replacement = if (is_add_imm) (word & ~(@as(u32, 0xFFF) << 10)) | (@as(u32, 0x5b) << 10) else (word & ~(@as(u32, 0xFFFF) << 5)) | (@as(u32, 0x5b) << 5);
        jit.memory.beginWrite();
        @constCast(block.code)[index] = replacement;
        jit.memory.endWrite(block.code);
        patched = true;
        break;
    }
    if (!patched) return error.SkipZigTest;
    try testing.expect(state.verifyMemoryBlockJit(jit, block, jit.firstSlot(block.start_rip)));
    try testing.expectEqual(@as(u64, 1), jit.verify_memory_mismatches);
    // The interpreter's answer stands, in the register and in memory.
    try testing.expectEqual(@as(u64, 100 + 0x5a), state.regs.rax);
    try testing.expectEqual(@as(u64, 100 + 0x5a), std.mem.readInt(u64, state.mem[0x20018..][0..8], .little));
    // And the address is never compiled again.
    try testing.expect(ElfState.blockJitHotness(jit, block.start_rip).refused);
}

test "the memory-aware cross-check compares where a translation leaves early at a branch to the next instruction" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // xor r10d,r10d ; test r10b,r10b ; je +0 ; mov [rbx+0x10],rax ;
    // add rax,1 ; dec r15 ; jnz top ; hlt - Xenia's `je +0` shape
    var program: [32]u8 = @splat(0xCC);
    const body = [_]u8{ 0x45, 0x31, 0xD2, 0x45, 0x84, 0xD2, 0x0F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x48, 0x89, 0x43, 0x10, 0x48, 0x83, 0xC0, 0x01, 0x49, 0xFF, 0xCF };
    @memcpy(program[0..body.len], &body);
    var at: usize = body.len;
    program[at] = 0x0F;
    program[at + 1] = 0x85;
    const rel: i32 = -@as(i32, @intCast(at + 6));
    @memcpy(program[at + 2 ..][0..4], std.mem.asBytes(&rel));
    at += 6;
    program[at] = 0xF4;
    const interpreted = runDifferentialProgram(program[0 .. at + 1], 0x5151, false);
    const verified = runDifferentialProgramWith(program[0 .. at + 1], 0x5151, true, true);
    try std.testing.expect(interpreted.terminated and verified.terminated);
    try std.testing.expectEqual(interpreted.regs.rax, verified.regs.rax);
    try std.testing.expectEqual(interpreted.regs.rip, verified.regs.rip);
    try std.testing.expectEqualSlices(u8, &interpreted.data, &verified.data);
    // Leaving early at `je +0` is not a disagreement.
    try std.testing.expectEqual(@as(u64, 0), verified.verify_memory_mismatches);
    try std.testing.expect(verified.verify_memory_checked > 0);
}

/// Flag writers at every width, each followed by a run of conditional
/// readers: the shapes the translator fuses so the readers test NZCV.
fn buildFusedRunBody(asm_: *DifferentialAssembler, random: std.Random, count: usize) void {
    const registers = [_]u8{ 0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 };
    const widths = [_]u8{ 8, 16, 32, 64 };
    const group1 = [_]u8{ 0x01, 0x29, 0x21, 0x09, 0x31, 0x39, 0x85 };
    for (0..count) |_| {
        const dst = registers[random.uintLessThan(usize, registers.len)];
        const src = registers[random.uintLessThan(usize, registers.len)];
        const width = widths[random.uintLessThan(usize, widths.len)];
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                const opcode = group1[random.uintLessThan(usize, group1.len)];
                if (width == 64) asm_.aluRegReg(opcode, dst, src) else asm_.aluRegRegSized(opcode, dst, src, width);
            },
            1 => {
                // add, or, and, sub, xor, cmp (not adc/sbb, which read CF).
                const ext = ([_]u8{ 0, 1, 4, 5, 6, 7 })[random.uintLessThan(usize, 6)];
                const value = random.int(i8);
                if (width == 64) asm_.aluImm8(ext, dst, value) else asm_.aluImm8Sized(ext, dst, value, width);
            },
            else => {
                const ext = random.uintLessThan(u8, 2);
                if (width == 64) asm_.incDec(ext, dst) else asm_.incDecSized(ext, dst, width);
            },
        }
        const readers = 1 + random.uintLessThan(usize, 3);
        for (0..readers) |_| {
            const cond = random.uintLessThan(u8, 16);
            const target = registers[random.uintLessThan(usize, registers.len)];
            const disp: i32 = @intCast(random.uintLessThan(u32, 0x1F0) * 8);
            switch (random.uintLessThan(u8, 5)) {
                0 => asm_.setcc(cond, target),
                1 => asm_.setccMem(cond, 3, disp),
                2 => asm_.cmov(cond, target, src),
                3 => asm_.cmovMem(cond, target, 3, disp),
                else => {
                    asm_.jccOver(cond, 3);
                    asm_.aluRegReg(0x01, dst, src);
                },
            }
        }
        // A later reader of every flag the run may still owe.
        switch (random.uintLessThan(u8, 4)) {
            0 => asm_.aluRegReg(0x11, dst, src), // adc
            1 => asm_.setcc(random.uintLessThan(u8, 16), dst),
            else => {},
        }
    }
}

test "fused flag runs retire the same state as the interpreter at every width" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0xF05E_D0F5);
    const random = prng.random();
    var total_translated: u64 = 0;
    var total_fused: u64 = 0;
    for (0..96) |trial| {
        var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
        defer asm_.deinit();
        const body_start = asm_.bytes.items.len;
        buildFusedRunBody(&asm_, random, 3 + random.uintLessThan(usize, 8));
        asm_.incDec(1, 15); // dec r15
        asm_.jnzBack(body_start);
        asm_.hlt();
        const seed = 0x2000 + trial;
        const interpreted = runDifferentialProgram(asm_.bytes.items, seed, false);
        const translated = runDifferentialProgram(asm_.bytes.items, seed, true);
        try std.testing.expect(interpreted.terminated and translated.terminated);
        try std.testing.expectEqual(interpreted.faulted, translated.faulted);
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
            if (@field(interpreted.regs, name) != @field(translated.regs, name)) {
                std.debug.print("trial {d}: {s} differs interpreter=0x{x} translated=0x{x} program={any}\n", .{ trial, name, @field(interpreted.regs, name), @field(translated.regs, name), asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        if (interpreted.regs.rflags != translated.regs.rflags) {
            std.debug.print("trial {d}: rflags differ interpreter=0x{x} translated=0x{x} program={any}\n", .{ trial, interpreted.regs.rflags, translated.regs.rflags, asm_.bytes.items });
            return error.TestUnexpectedResult;
        }
        try std.testing.expectEqualSlices(u8, &interpreted.data, &translated.data);
        try std.testing.expectEqual(@as(u64, 0), translated.mismatches);
        total_translated += translated.translated_instructions;
        total_fused += translated.fused_runs;
    }
    try std.testing.expect(total_translated > 1000);
    // The comparison above is only worth something if the runs were fused.
    try std.testing.expect(total_fused > 200);
}

test "a spin capture interprets its thread, records the load it polls and watches it" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    if (state.windows_guest_threads.len == 0) return error.SkipZigTest;
    // poll: mov al, [rdi+0x2abd] ; dec r15 ; jnz poll ; hlt
    const program = [_]u8{ 0x8A, 0x87, 0xBD, 0x2A, 0x00, 0x00, 0x49, 0xFF, 0xCF, 0x75, 0xF5, 0xF4 };
    @memcpy(state.mem[0x1000..][0..program.len], &program);
    state.mem[0x20000 + 0x2ABD] = 0x40;
    state.regs.rdi = MEM_BASE + 0x20000;
    state.regs.r15 = 100;
    state.regs.rsp = MEM_BASE + 0x40000;
    state.regs.rip = MEM_BASE + 0x1000;
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 2;
    state.guestContextField("windows_active_guest_thread_slot").* = 0;
    state.frame_cost.swaps = 1;
    state.windows_guest_threads[0].spin.reported_at_swaps = 1;
    state.windows_guest_threads[0].spin.capture_watch_epoch = state.spin_watch.epoch.load(.acquire);
    state.windows_guest_threads[0].spin.capture_remaining = 64;
    _ = state.spin_capture_threads.fetchAdd(1, .monotonic);
    state.runWithLimit(10_000);
    try std.testing.expect(state.terminated);
    try std.testing.expectEqual(@as(u32, 0), state.spin_capture_threads.load(.monotonic));
    const spin = &state.windows_guest_threads[0].spin;
    try std.testing.expect(spin.capture_len >= 1);
    try std.testing.expectEqual(MEM_BASE + 0x22ABD, spin.capture[0].address);
    try std.testing.expectEqual(@as(u64, 0x40), spin.capture[0].last);
    try std.testing.expect(state.spin_watch.armed());
    try std.testing.expectEqual(MEM_BASE + 0x22ABD, state.spin_watch.addresses[0].load(.monotonic));
}

test "a spin watch sees translated, interpreted and bulk stores and keeps its page off the write TLB" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    // store: mov byte [rbx+0x10], 1 ; dec r15 ; jnz store ; hlt
    const program = [_]u8{ 0xC6, 0x43, 0x10, 0x01, 0x49, 0xFF, 0xCF, 0x75, 0xF7, 0xF4 };
    @memcpy(state.mem[0x1000..][0..program.len], &program);
    const watched = MEM_BASE + 0x20010;
    try std.testing.expectEqual(@as(?usize, 0), state.spin_watch.arm(watched, 1, 0));
    try std.testing.expect(state.traceWithholdsWriteTlb(watched & ~@as(u64, block_jit.Tlb.page_bytes - 1)));
    state.regs.rbx = MEM_BASE + 0x20000;
    state.regs.r15 = 40;
    state.regs.rsp = MEM_BASE + 0x40000;
    state.regs.rip = MEM_BASE + 0x1000;
    state.block_jit_enabled = true;
    state.block_jit_hot_threshold = 2;
    state.runWithLimit(10_000);
    try std.testing.expect(state.terminated);
    // Every one of the forty stores, translated ones included.
    try std.testing.expectEqual(@as(u64, 40), state.spin_watch.hits[0].load(.monotonic));
    try std.testing.expect(state.block_jit.?.instructions_retired > 0);
    state.writeMemVal(watched + 1, .bits8, 2);
    try std.testing.expectEqual(@as(u64, 40), state.spin_watch.hits[0].load(.monotonic));
    _ = state.fillGuestMemory(watched - 4, 16, 0);
    try std.testing.expectEqual(@as(u64, 41), state.spin_watch.hits[0].load(.monotonic));
}

test "KUSER_SHARED_DATA answers Xenia's interrupt-time read from the guest clock" {
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    // Unmapped and outside the PE runtime: nothing, as before.
    try std.testing.expectEqual(@as(u64, 0), state.read64(kuser_shared.base + kuser_shared.interrupt_time));
    state.windows_runtime_enabled = true;
    if (state.guest_clock.source == .retired_instructions) return error.SkipZigTest;
    state.guest_clock_published_ticks.publish(2_500_000); // 2.5 s
    // Clock::QueryHostInterruptTime: *(u64*)0x7FFE0008, in 100 ns units.
    try std.testing.expectEqual(@as(u64, 25_000_000), state.read64(kuser_shared.base + kuser_shared.interrupt_time));
    try std.testing.expectEqual(@as(u32, 2500), state.read32(kuser_shared.base + kuser_shared.tick_count_low_deprecated));
    state.guest_clock_published_ticks.publish(3_000_000);
    try std.testing.expectEqual(@as(u64, 30_000_000), state.read64(kuser_shared.base + kuser_shared.interrupt_time));
    // The page is read-only data, not a mapping: its neighbours stay empty.
    try std.testing.expectEqual(@as(u64, 0), state.read64(kuser_shared.base + kuser_shared.size));
}

const XeniaSpinOutcome = struct { regs: ElfRegs, ctx: [0x200]u8, data: [0x200]u8, translated: u64, fused: u64, terminated: bool };

/// Halo 3's main-menu wait (2026-10-02, 0xa06b4d93 in RENDER and MAIN): a
/// big-endian countdown of 4 on the guest stack with eight `pause`s a turn,
/// then `cmp ebx, edi; setne [rsi+25]; sete bl; mov [rsi+26], bl; test bl,
/// bl; je` back - wrapped in an outer loop of 40 so the translator runs it.
fn runXeniaSpinProgram(translate: bool) XeniaSpinOutcome {
    // The eight `pause`s (f3 90) are two-byte `nop`s (66 90) here: the
    // single-threaded harness stops at a pause spin, and the offsets stay.
    // `cmp ebx, edi` (39 fb) is `cmp ebx, eax` (39 c3) with eax zero: Xenia's
    // edi is the low half of a 4 GiB-aligned membase, which this harness's
    // memory cannot be.
    const loop_bytes = "c704170000000466906690669066906690669066906690488b5e30678d535039f20f8374030000440f38f014174589d24983ea014589d2678d535039f20f8360030000440f38f11417678d535039f20f83560300000f38f01c174189da4c899680000000c646180039c30f9546190f94c3885e1a84db0f848bffffff";
    var program: [loop_bytes.len / 2 + 16]u8 = @splat(0xCC);
    _ = std.fmt.hexToBytes(program[0 .. loop_bytes.len / 2], loop_bytes) catch unreachable;
    var at: usize = loop_bytes.len / 2;
    // dec r15 ; jnz program start ; hlt
    @memcpy(program[at..][0..3], &[_]u8{ 0x49, 0xFF, 0xCF });
    at += 3;
    program[at] = 0x0F;
    program[at + 1] = 0x85;
    const rel: i32 = -@as(i32, @intCast(at + 6));
    @memcpy(program[at + 2 ..][0..4], std.mem.asBytes(&rel));
    at += 6;
    program[at] = 0xF4;
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    @memcpy(state.mem[0x1000..][0..program.len], &program);
    @memset(state.mem[0x20000..][0..0x20000], 0);
    const ctx = MEM_BASE + 0x30000;
    const r1: u64 = 0x100;
    std.mem.writeInt(u64, state.mem[0x30000 + 48 ..][0..8], r1, .little);
    state.regs.rsi = ctx;
    state.regs.rdi = MEM_BASE + 0x20000;
    state.regs.rdx = r1 + 80;
    state.regs.rax = 0;
    state.regs.rbx = 0x1234_5678_9abc_def0;
    state.regs.r10 = 0x0fed_cba9_8765_4321;
    state.regs.r15 = 40;
    state.regs.rsp = MEM_BASE + 0x40000;
    state.regs.rip = MEM_BASE + 0x1000;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = translate;
    state.block_jit_hot_threshold = 2;
    state.runWithLimit(400_000);
    var outcome = XeniaSpinOutcome{ .regs = state.regs, .ctx = undefined, .data = undefined, .translated = 0, .fused = 0, .terminated = state.terminated };
    @memcpy(&outcome.ctx, state.mem[0x30000..][0..0x200]);
    @memcpy(&outcome.data, state.mem[0x20000..][0..0x200]);
    if (state.block_jit) |jit| {
        outcome.translated = jit.instructions_retired;
        outcome.fused = jit.fused_runs;
    }
    return outcome;
}

test "Xenia's stwcx. helper reports a failed store as failed when translated under the Windows ABI" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // The shape of Xenia's RESERVED_STORE_INT32 (x64_seq_memory.cc) and its
    // reserved-store helper (x64_backend.cc) with the reservation already
    // lost: the helper's `btr` finds no reservation (CF=0), jumps to `done`,
    // and returns ZF = (setz al ; setc ah ; cmp ax, 0x0101) = 0. The caller
    // writes that into the PowerPC CR0 with `setz`. The stale ZF the helper
    // must not return is a materialised 1 from `cmp eax, eax ; jmp`.
    // Each iteration adds the caller's CR0.eq to [rbx+16]: a store reported
    // as made that never was. Translated as the 2026-10-03 run did, every
    // iteration added one, and a lwarx/stwcx. loop under contention believed
    // a lost update had landed.
    const program = [_]u8{
        0x48, 0x83, 0x23, 0xFD, // 00 and qword [rbx], -3  - drop the reservation bit
        0x39, 0xC0, // 04 cmp eax, eax           - ZF = 1
        0xEB, 0x00, // 06 jmp 08                - materialise it
        0xE8, 0x12, 0x00, 0x00, 0x00, // 08 call 1F    - the helper
        0x0F, 0x94, 0x43, 0x08, // 0D setz byte [rbx+8]  - CR0.eq
        0x0F, 0xB6, 0x4B, 0x08, // 11 movzx ecx, byte [rbx+8]
        0x48, 0x01, 0x4B, 0x10, // 15 add [rbx+16], rcx
        0x49, 0xFF, 0xCF, // 19 dec r15
        0x75, 0xE2, // 1C jnz 00
        0xF4, // 1E hlt
        0x48, 0x0F, 0xBA, 0x33, 0x01, // 1F btr qword [rbx], 1 - the reservation bit
        0x73, 0x02, // 24 jnc 28
        0x39, 0xC0, // 26 cmp eax, eax (the store path; not taken here)
        0x0F, 0x94, 0xC0, // 28 setz al
        0x0F, 0x92, 0xC4, // 2B setc ah
        0x66, 0x3D, 0x01, 0x01, // 2E cmp ax, 0x0101
        0xC3, // 32 ret
    };
    const seed = 0x57C_0001;
    const interpreted = runDifferentialProgramConfigured(&program, seed, false, .{ .windows_abi = true });
    const translated = runDifferentialProgramConfigured(&program, seed, true, .{ .windows_abi = true });
    try std.testing.expect(interpreted.terminated and translated.terminated);
    try std.testing.expect(translated.translated_instructions > 100);
    // [rbx+8] holds the last CR0.eq the caller stored; it must be 0.
    try std.testing.expectEqual(@as(u8, 0), interpreted.data[8]);
    try std.testing.expectEqual(interpreted.data[8], translated.data[8]);
    // The success count did not move.
    try std.testing.expectEqualSlices(u8, interpreted.data[16..24], translated.data[16..24]);
    try std.testing.expectEqualSlices(u8, &interpreted.data, &translated.data);
}

test "Xenia's deque erase rebuilds its finish iterator with vpinsrq, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // The bytes of `std::deque<std::pair<u64, VkFence>>::_M_erase`'s
    // erase-everything path in Xenia's MinGW build (0x140bc9463): finish
    // becomes start, field by field, through two vector registers. VPINSRQ
    // decoded as VPINSRD left start.first where finish.node belongs; the
    // next erase freed every "node" from the map to that heap address and
    // ran into a stack guard - the 2026-10-03 campaign-launch crash. Both
    // runs share the decoder, so the check is against what x86 requires,
    // not only against each other.
    const program = [_]u8{
        0x48, 0x89, 0xDF, // mov rdi, rbx            - the deque
        0x48, 0x8D, 0xB3, 0x00, 0x01, 0x00, 0x00, // lea rsi, [rbx+0x100] - the result iterator
        0x4C, 0x8B, 0x77, 0x10, // mov r14, [rdi+0x10]   - start.cur
        0xC5, 0xFA, 0x6F, 0x77, 0x18, // vmovdqu xmm6, [rdi+0x18]  - start.first, start.last
        0x48, 0x8B, 0x5F, 0x28, // mov rbx, [rdi+0x28]   - start.node
        0xC4, 0xC1, 0xF9, 0x6E, 0xC6, // vmovq xmm0, r14
        0xC5, 0xF9, 0x6C, 0xC6, // vpunpcklqdq xmm0, xmm0, xmm6
        0xC5, 0xF9, 0x70, 0xCE, 0x4E, // vpshufd xmm1, xmm6, 0x4e
        0xC4, 0xE3, 0xF1, 0x22, 0xCB, 0x01, // vpinsrq xmm1, xmm1, rbx, 1
        0xC5, 0xFA, 0x7F, 0x4F, 0x40, // vmovdqu [rdi+0x40], xmm1 - finish.last, finish.node
        0xC5, 0xFA, 0x7F, 0x47, 0x30, // vmovdqu [rdi+0x30], xmm0 - finish.cur, finish.first
        0x4C, 0x89, 0x36, // mov [rsi], r14
        0xC5, 0xFA, 0x7F, 0x76, 0x08, // vmovdqu [rsi+8], xmm6
        0x48, 0x89, 0x5E, 0x18, // mov [rsi+0x18], rbx
        0x48, 0x89, 0xFB, // mov rbx, rdi            - keep the base for the next pass
        0x49, 0xFF, 0xCF, // dec r15
        0x75, 0xB7, // jnz 0
        0xF4, // hlt
    };
    const seed = 0xDE0_0E7A;
    for ([_]bool{ false, true }) |translate| {
        const outcome = runDifferentialProgram(&program, seed, translate);
        try std.testing.expect(outcome.terminated and !outcome.faulted);
        if (translate) try std.testing.expect(outcome.translated_instructions > 100);
        const data = &outcome.data;
        // finish = start: cur, first, last, node.
        for (0..4) |field| {
            const start = std.mem.readInt(u64, data[0x10 + field * 8 ..][0..8], .little);
            const finish = std.mem.readInt(u64, data[0x30 + field * 8 ..][0..8], .little);
            const result = std.mem.readInt(u64, data[0x100 + field * 8 ..][0..8], .little);
            if (finish != start or result != start) {
                std.debug.print("deque erase ({s}): field {d} start=0x{x} finish=0x{x} result=0x{x}\n", .{ if (translate) "translated" else "interpreted", field, start, finish, result });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "MXCSR flush-to-zero and denormals-are-zero reach the arithmetic, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Xenia's PowerPC JIT loads MXCSR 0x9FC0 (FTZ | DAZ) before VMX code:
    // the Xbox 360's VMX unit flushes denormals in non-Java mode and titles
    // are written for it. Rosette used to keep the value in a field nothing
    // read, so 1e-20 * 1e-20 stayed 1e-40 and a denormal input still scaled.
    // Halo 3's CPU-side object lighting reached the GPU as 1e8-1e22 and NaN.
    const program = [_]u8{
        0xC7, 0x83, 0x00, 0x02, 0x00, 0x00, 0xC0, 0x9F, 0x00, 0x00, // mov dword [rbx+0x200], 0x9FC0 - Xenia's VMX MXCSR
        0xC5, 0xF8, 0xAE, 0x93, 0x00, 0x02, 0x00, 0x00, // vldmxcsr [rbx+0x200]
        0xB8, 0x08, 0xE5, 0x3C, 0x1E, // mov eax, 0x1E3CE508 - 1e-20
        0xC5, 0xF9, 0x6E, 0xC0, // vmovd xmm0, eax
        0xC5, 0xF9, 0x6E, 0xC8, // vmovd xmm1, eax
        0xC5, 0xFA, 0x59, 0xD1, // vmulss xmm2, xmm0, xmm1 - 1e-40 underflows
        0xC5, 0xF9, 0x7E, 0x93, 0x00, 0x03, 0x00, 0x00, // vmovd [rbx+0x300], xmm2
        0xB8, 0x00, 0x00, 0x01, 0x00, // mov eax, 0x00010000 - a denormal input
        0xC5, 0xF9, 0x6E, 0xC0, // vmovd xmm0, eax
        0xB8, 0xF9, 0x02, 0x15, 0x50, // mov eax, 0x501502F9 - 1e10
        0xC5, 0xF9, 0x6E, 0xC8, // vmovd xmm1, eax
        0xC5, 0xFA, 0x59, 0xD1, // vmulss xmm2, xmm0, xmm1
        0xC5, 0xF9, 0x7E, 0x93, 0x04, 0x03, 0x00, 0x00, // vmovd [rbx+0x304], xmm2
        0xC7, 0x83, 0x04, 0x02, 0x00, 0x00, 0x80, 0x1F, 0x00, 0x00, // mov dword [rbx+0x204], 0x1F80 - the power-on MXCSR
        0x0F, 0xAE, 0x93, 0x04, 0x02, 0x00, 0x00, // ldmxcsr [rbx+0x204]
        0xB8, 0x08, 0xE5, 0x3C, 0x1E, // mov eax, 0x1E3CE508
        0xC5, 0xF9, 0x6E, 0xC0, // vmovd xmm0, eax
        0xC5, 0xF9, 0x6E, 0xC8, // vmovd xmm1, eax
        0xC5, 0xFA, 0x59, 0xD1, // vmulss xmm2, xmm0, xmm1
        0xC5, 0xF9, 0x7E, 0x93, 0x08, 0x03, 0x00, 0x00, // vmovd [rbx+0x308], xmm2
        0xB8, 0x00, 0x00, 0x01, 0x00, // mov eax, 0x00010000
        0xC5, 0xF9, 0x6E, 0xC0, // vmovd xmm0, eax
        0xB8, 0xF9, 0x02, 0x15, 0x50, // mov eax, 0x501502F9
        0xC5, 0xF9, 0x6E, 0xC8, // vmovd xmm1, eax
        0xC5, 0xFA, 0x59, 0xD1, // vmulss xmm2, xmm0, xmm1
        0xC5, 0xF9, 0x7E, 0x93, 0x0C, 0x03, 0x00, 0x00, // vmovd [rbx+0x30c], xmm2
        0xC5, 0xF8, 0xAE, 0x9B, 0x10, 0x03, 0x00, 0x00, // vstmxcsr [rbx+0x310]
        0x49, 0xFF, 0xCF, // dec r15
        0x0F, 0x85, 0x5E, 0xFF, 0xFF, 0xFF, // jnz 0
        0xF4, // hlt
    };
    for ([_]bool{ false, true }) |translate| {
        const outcome = runDifferentialProgram(&program, 0xF7_2E00, translate);
        try std.testing.expect(outcome.terminated and !outcome.faulted);
        if (translate) try std.testing.expect(outcome.translated_instructions > 100);
        const data = &outcome.data;
        const word = struct {
            fn at(bytes: *const [0x1000]u8, offset: usize) u32 {
                return std.mem.readInt(u32, bytes[offset..][0..4], .little);
            }
        }.at;
        // Under 0x9FC0: the underflow and the denormal input are both +0.
        try std.testing.expectEqual(@as(u32, 0), word(data, 0x300));
        try std.testing.expectEqual(@as(u32, 0), word(data, 0x304));
        // Under 0x1F80: IEEE gradual underflow and a scaled denormal.
        try std.testing.expectEqual(@as(u32, 0x0001_16C2), word(data, 0x308));
        try std.testing.expectEqual(@as(u32, 0x0D95_02F9), word(data, 0x30C));
        try std.testing.expectEqual(@as(u32, 0x1F80), word(data, 0x310));
        try std.testing.expectEqual(@as(u32, 0x1F80), outcome.regs.mxcsr);
    }
    // The executor hands the test thread back with IEEE behaviour.
    try std.testing.expect(host_fp_control.matchesGuestMxcsr(host_fp_control.mxcsr_default));
}

test "VTEST sign and pack forms check Xenia's twelve tessellation handles, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // `VulkanPipelineCache::Initialize` (0x140cdd9f0 in Xenia's MinGW build)
    // proves that its twelve tessellation shader handles are non-null with
    // two vector sequences instead of twelve compares: eight handles through
    // vmovdqu / vpcmpeqq / vpor / vextractf128 / vpackssdw / vtestps, then the
    // last four through vmovddup / vpinsrq / vperm2f128 (memory operand) /
    // vinsertf128 / vmovmskpd. Rosette created all twelve modules and returned
    // VK_SUCCESS with a non-null handle for each (no creation failure in the
    // run's log), yet Xenia logged "Failed to create one or more tessellation
    // shaders". This replays the exact bytes with every handle set, which x86
    // says must not reach the warning, and with each single handle cleared,
    // which must. Expected values come from the instruction definitions, not
    // from either executor.
    const Emit = struct {
        buf: [1024]u8 = undefined,
        len: usize = 0,
        fn put(self: *@This(), bytes: []const u8) void {
            @memcpy(self.buf[self.len..][0..bytes.len], bytes);
            self.len += bytes.len;
        }
        fn movabsRax(self: *@This(), value: u64) void {
            self.put(&.{ 0x48, 0xB8 });
            self.put(&@as([8]u8, @bitCast(std.mem.nativeToLittle(u64, value))));
        }
        fn storeRaxAtR13(self: *@This(), disp: u32) void {
            self.put(&.{ 0x49, 0x89, 0x85 }); // mov [r13 + disp32], rax
            self.put(&@as([4]u8, @bitCast(std.mem.nativeToLittle(u32, disp))));
        }
    };
    const warn_flag: usize = 0x200;
    const cases = [_]?usize{ null, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
    for (cases) |cleared| {
        var asm_ = Emit{};
        asm_.put(&.{ 0x49, 0x89, 0xDD }); // mov r13, rbx          - the pipeline cache (this)
        for (0..11) |slot| {
            // Handles as Rosette issues them: high bit set, never zero.
            const handle: u64 = if (cleared != null and cleared.? == slot) 0 else 0xFFFF_F500_0000_0001 + @as(u64, slot) * 0x10;
            asm_.movabsRax(handle);
            asm_.storeRaxAtR13(@intCast(0x128 + slot * 8));
        }
        // The twelfth handle is still in rbx when Xenia checks it.
        const last: u64 = if (cleared != null and cleared.? == 11) 0 else 0xFFFF_F500_0000_00B1;
        asm_.put(&.{ 0x48, 0xBB }); // mov rbx, imm64
        asm_.put(&@as([8]u8, @bitCast(std.mem.nativeToLittle(u64, last))));
        asm_.put(&.{ 0x49, 0x89, 0x9D, 0x80, 0x01, 0x00, 0x00 }); // mov [r13+0x180], rbx
        asm_.put(&.{ 0x41, 0xC6, 0x85, 0x00, 0x02, 0x00, 0x00, 0x00 }); // mov byte [r13+0x200], 0 - the data page starts random
        const top = asm_.len;
        // The first eight handles.
        asm_.put(&.{ 0xC4, 0xC1, 0x7E, 0x6F, 0x8D, 0x28, 0x01, 0x00, 0x00 }); // vmovdqu ymm1, [r13+0x128]
        asm_.put(&.{ 0xC4, 0xC1, 0x7E, 0x6F, 0x95, 0x48, 0x01, 0x00, 0x00 }); // vmovdqu ymm2, [r13+0x148]
        asm_.put(&.{ 0xC5, 0xF9, 0xEF, 0xC0 }); // vpxor xmm0, xmm0, xmm0
        asm_.put(&.{ 0xC4, 0xE2, 0x69, 0x29, 0xD8 }); // vpcmpeqq xmm3, xmm2, xmm0
        asm_.put(&.{ 0xC4, 0xE2, 0x71, 0x29, 0xE0 }); // vpcmpeqq xmm4, xmm1, xmm0
        asm_.put(&.{ 0xC5, 0xD9, 0xEB, 0xDB }); // vpor xmm3, xmm4, xmm3
        asm_.put(&.{ 0xC4, 0xE3, 0x7D, 0x19, 0xD2, 0x01 }); // vextractf128 xmm2, ymm2, 1
        asm_.put(&.{ 0xC4, 0xE2, 0x69, 0x29, 0xD0 }); // vpcmpeqq xmm2, xmm2, xmm0
        asm_.put(&.{ 0xC4, 0xE3, 0x7D, 0x19, 0xC9, 0x01 }); // vextractf128 xmm1, ymm1, 1
        asm_.put(&.{ 0xC4, 0xE2, 0x71, 0x29, 0xC8 }); // vpcmpeqq xmm1, xmm1, xmm0
        asm_.put(&.{ 0xC5, 0xF1, 0xEB, 0xCA }); // vpor xmm1, xmm1, xmm2
        asm_.put(&.{ 0xC5, 0xE1, 0x6B, 0xC9 }); // vpackssdw xmm1, xmm3, xmm1
        asm_.put(&.{ 0xC4, 0xE2, 0x79, 0x0E, 0xC9 }); // vtestps xmm1, xmm1
        asm_.put(&.{ 0x75, 0x37 }); // jne warn
        // The last four.
        asm_.put(&.{ 0xC4, 0xC1, 0x7B, 0x12, 0x8D, 0x78, 0x01, 0x00, 0x00 }); // vmovddup xmm1, [r13+0x178]
        asm_.put(&.{ 0xC4, 0xE3, 0xF1, 0x22, 0xCB, 0x01 }); // vpinsrq xmm1, xmm1, rbx, 1
        asm_.put(&.{ 0xC4, 0xC3, 0x75, 0x06, 0x8D, 0x68, 0x01, 0x00, 0x00, 0x02 }); // vperm2f128 ymm1, ymm1, [r13+0x168], 2
        asm_.put(&.{ 0xC4, 0xE3, 0x7D, 0x19, 0xCA, 0x01 }); // vextractf128 xmm2, ymm1, 1
        asm_.put(&.{ 0xC4, 0xE2, 0x69, 0x29, 0xD0 }); // vpcmpeqq xmm2, xmm2, xmm0
        asm_.put(&.{ 0xC4, 0xE2, 0x71, 0x29, 0xC0 }); // vpcmpeqq xmm0, xmm1, xmm0
        asm_.put(&.{ 0xC4, 0xE3, 0x7D, 0x18, 0xC2, 0x01 }); // vinsertf128 ymm0, ymm0, xmm2, 1
        asm_.put(&.{ 0xC5, 0xFD, 0x50, 0xC0 }); // vmovmskpd eax, ymm0
        asm_.put(&.{ 0x84, 0xC0 }); // test al, al
        asm_.put(&.{ 0x74, 0x08 }); // je ok
        asm_.put(&.{ 0x41, 0x80, 0x8D, 0x00, 0x02, 0x00, 0x00, 0x01 }); // warn: or byte [r13+0x200], 1
        asm_.put(&.{ 0x49, 0xFF, 0xCF }); // ok: dec r15
        const back: i32 = -@as(i32, @intCast(asm_.len + 6 - top));
        asm_.put(&.{ 0x0F, 0x85 }); // jnz top
        asm_.put(&@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, back))));
        asm_.put(&.{0xF4}); // hlt
        const want: u8 = if (cleared == null) 0 else 1;
        for ([_]bool{ false, true }) |translate| {
            const outcome = runDifferentialProgram(asm_.buf[0..asm_.len], 0x7E55_E11A, translate);
            const how = if (translate) "translated" else "interpreted";
            try std.testing.expect(outcome.terminated and !outcome.faulted);
            if (translate) try std.testing.expect(outcome.translated_instructions > 100);
            if (outcome.data[warn_flag] != want) {
                std.debug.print("tessellation handle check ({s}): cleared={?d} warn={d} want={d}\n", .{ how, cleared, outcome.data[warn_flag], want });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "VTEST sign lane forms address memory through their base register, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // VEXTRACTF128 to memory and VINSERTF128 from memory shared VPERM2F128's
    // decode defect: the constructor-style helpers kept the displacement and
    // dropped the base register `readModRM` had recorded, so `[r13+0x340]`
    // was the absolute address 0x340. The expected bytes follow from the
    // instruction definitions: extract stores the high lane of ymm1, insert
    // keeps the low lane of its first source and takes the high lane from
    // memory (imm 1).
    const Emit = struct {
        buf: [1024]u8 = undefined,
        len: usize = 0,
        fn put(self: *@This(), bytes: []const u8) void {
            @memcpy(self.buf[self.len..][0..bytes.len], bytes);
            self.len += bytes.len;
        }
    };
    var asm_ = Emit{};
    asm_.put(&.{ 0x49, 0x89, 0xDD }); // mov r13, rbx - the data page
    var quad: [8]u64 = undefined;
    for (&quad, 0..) |*value, index| {
        value.* = 0xA0A0_1B1B_0000_0000 + @as(u64, index) * 0x0101;
        asm_.put(&.{ 0x48, 0xB8 }); // mov rax, imm64
        asm_.put(&@as([8]u8, @bitCast(std.mem.nativeToLittle(u64, value.*))));
        asm_.put(&.{ 0x49, 0x89, 0x85 }); // mov [r13 + disp32], rax
        asm_.put(&@as([4]u8, @bitCast(std.mem.nativeToLittle(u32, @intCast(0x300 + index * 8)))));
    }
    const top = asm_.len;
    asm_.put(&.{ 0xC4, 0xC1, 0x7E, 0x6F, 0x8D, 0x00, 0x03, 0x00, 0x00 }); // vmovdqu ymm1, [r13+0x300]
    asm_.put(&.{ 0xC4, 0xC3, 0x7D, 0x19, 0x8D, 0x40, 0x03, 0x00, 0x00, 0x01 }); // vextractf128 [r13+0x340], ymm1, 1
    asm_.put(&.{ 0xC4, 0xC3, 0x75, 0x18, 0x95, 0x20, 0x03, 0x00, 0x00, 0x01 }); // vinsertf128 ymm2, ymm1, [r13+0x320], 1
    asm_.put(&.{ 0x49, 0xFF, 0xCF }); // dec r15
    const back: i32 = -@as(i32, @intCast(asm_.len + 6 - top));
    asm_.put(&.{ 0x0F, 0x85 }); // jnz top
    asm_.put(&@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, back))));
    asm_.put(&.{0xF4}); // hlt
    for ([_]bool{ false, true }) |translate| {
        const outcome = runDifferentialProgram(asm_.buf[0..asm_.len], 0x1AE5_0128, translate);
        const how = if (translate) "translated" else "interpreted";
        try std.testing.expect(outcome.terminated and !outcome.faulted);
        if (translate) try std.testing.expect(outcome.translated_instructions > 100);
        var expected_store: [16]u8 = undefined;
        std.mem.writeInt(u64, expected_store[0..8], quad[2], .little);
        std.mem.writeInt(u64, expected_store[8..16], quad[3], .little);
        if (!std.mem.eql(u8, outcome.data[0x340..0x350], &expected_store)) {
            std.debug.print("vextractf128 to memory ({s}) stored {x}, expected {x}\n", .{ how, outcome.data[0x340..0x350], expected_store });
            return error.TestUnexpectedResult;
        }
        var expected_low: [16]u8 = undefined;
        std.mem.writeInt(u64, expected_low[0..8], quad[0], .little);
        std.mem.writeInt(u64, expected_low[8..16], quad[1], .little);
        var expected_high: [16]u8 = undefined;
        std.mem.writeInt(u64, expected_high[0..8], quad[4], .little);
        std.mem.writeInt(u64, expected_high[8..16], quad[5], .little);
        if (!std.mem.eql(u8, &outcome.xmm[2], &expected_low) or !std.mem.eql(u8, &outcome.ymm_hi[2], &expected_high)) {
            std.debug.print("vinsertf128 from memory ({s}): low={x} high={x}, expected low={x} high={x}\n", .{ how, outcome.xmm[2], outcome.ymm_hi[2], expected_low, expected_high });
            return error.TestUnexpectedResult;
        }
    }
}

test "VTEST sign corpus: every memory form in xenia_canary.exe keeps its base, index and RIP-relative operand" {
    // The corpus names each exemplar's memory operand by shape (`m[b+,i,d8]`:
    // an extended base register, a plain index, a byte displacement; `m[rip]`).
    // A decoder that builds its result from a fresh struct instead of the one
    // `readModRM` filled keeps only the displacement, and the executor then
    // addresses `[r13+0x168]` as the absolute 0x168 (VPERM2F128, VINSERTF128
    // and VEXTRACTF128 did). Nothing checked the registers, only the length
    // and the operation.
    const corpus = @embedFile("../../xenia_image_corpus.txt");
    const known_gaps = [_][]const u8{ "shrx", "rdrand", "rdseed", "vhaddp", "vaddsubp", "pushfq", "popfq", "lock " };
    var failures: usize = 0;
    var first_failure: []const u8 = "";
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        const form = fields.next() orelse continue;
        const family = fields.next() orelse continue;
        if (std.mem.startsWith(u8, family, "evex.")) continue;
        const open = std.mem.indexOf(u8, form, "m[") orelse continue;
        const close = std.mem.indexOfScalarPos(u8, form, open, ']') orelse continue;
        // String instructions address through the implicit rsi/rdi, not a
        // ModR/M operand, so there is nothing for the decoder to record.
        if (std.mem.indexOf(u8, form, "es:m[") != null or std.mem.indexOf(u8, form, "ds:m[") != null) continue;
        const known = for (known_gaps) |gap| {
            if (std.mem.startsWith(u8, form, gap)) break true;
        } else false;
        if (known) continue;
        var bytes: [15]u8 = undefined;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (count == bytes.len) break;
            bytes[count] = try std.fmt.parseInt(u8, token, 16);
            count += 1;
        }
        const decoded = decodeInsn(bytes[0..count]);
        // Undecoded forms and NOP-class forms are the other corpus test's.
        if (decoded.op == .invalid or decoded.op == .nop) continue;
        var has_base = false;
        var has_index = false;
        var rip = false;
        var base_extended = false;
        var index_extended = false;
        var parts = std.mem.splitScalar(u8, form[open + 2 .. close], ',');
        while (parts.next()) |part| {
            if (std.mem.eql(u8, part, "b")) {
                has_base = true;
            } else if (std.mem.eql(u8, part, "b+")) {
                has_base = true;
                base_extended = true;
            } else if (std.mem.eql(u8, part, "i")) {
                has_index = true;
            } else if (std.mem.eql(u8, part, "i+")) {
                has_index = true;
                index_extended = true;
            } else if (std.mem.eql(u8, part, "rip")) {
                rip = true;
            }
        }
        const agrees = if (rip)
            decoded.rip_relative
        else
            !decoded.rip_relative and decoded.sib_has_base == has_base and decoded.sib_has_index == has_index and
                (!has_base or ((@intFromEnum(decoded.sib_base_reg) >= 8) == base_extended)) and
                (!has_index or ((@intFromEnum(decoded.sib_index_reg) >= 8) == index_extended));
        if (!agrees) {
            if (failures < 24) std.debug.print("memory operand lost or wrong: {s} -> {s} base={} idx={} rip={}\n", .{ line, @tagName(decoded.op), decoded.sib_has_base, decoded.sib_has_index, decoded.rip_relative });
            if (failures == 0) first_failure = line;
            failures += 1;
        }
    }
    if (failures != 0) std.debug.print("{d} memory form(s) lose their operand; the first is {s}\n", .{ failures, first_failure });
    try testing.expectEqual(@as(usize, 0), failures);
}

test "VTEST sign operand roles: every three-register VEX form Xenia's JIT emits keeps its destination and both sources" {
    // xenia_jit_corpus.txt holds the AT&T text of each form Xenia's x64
    // backend assembles. For `op [$imm,] %rm, %vvvv, %reg` the destination is
    // the last register, the first source (VEX.vvvv) the middle one and the
    // second source (ModR/M.r/m) the first. Operand numbers come from the
    // text, so a decoder that swaps or mis-extends a register field (the
    // R/X/B inversion bits reach xmm8-xmm15) disagrees with it.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        if (!std.mem.startsWith(u8, text, "v")) continue;
        // `op [$imm, ]%a, %b, %c` with exactly three vector registers and no memory operand.
        if (std.mem.indexOfScalar(u8, text, '(') != null) continue;
        var regs: [4]u8 = undefined;
        var count: usize = 0;
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, text, cursor, "%")) |at| {
            const rest = text[at + 1 ..];
            const is_vector = std.mem.startsWith(u8, rest, "xmm") or std.mem.startsWith(u8, rest, "ymm");
            if (!is_vector) {
                count = 99;
                break;
            }
            var end: usize = 3;
            while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') end += 1;
            if (count < regs.len) regs[count] = std.fmt.parseInt(u8, rest[3..end], 10) catch 255;
            count += 1;
            cursor = at + 1 + end;
        }
        if (count != 3) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or !decoded.is_reg_form) continue;
        checked += 1;
        if (decoded.xmm_src2 != regs[0] or decoded.xmm_src != regs[1] or decoded.xmm_dst != regs[2]) {
            if (failures < 40) std.debug.print("operand roles differ: {s} -> {s} dst={d} src={d} src2={d}\n", .{ text, @tagName(decoded.op), decoded.xmm_dst, decoded.xmm_src, decoded.xmm_src2 });
            failures += 1;
        }
    }
    std.debug.print("operand roles: checked {d} three-register VEX forms, {d} differ\n", .{ checked, failures });
    try testing.expect(checked > 100);
}

test "VTEST sign executor roles: every register-only VEX form Xenia's JIT emits writes only its destination, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // The operand-role test above checks the decoder. This one checks the
    // executors: with every vector register seeded, a form may change its
    // destination (and a VEX.128 destination's upper half) and nothing else.
    // Halo 3's D3D clear packs its colour in a VMX routine that keeps the
    // colour in a register across scalar FPU code; a stray write there
    // turned the HDR target's clear from black into pure red.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        if (!std.mem.startsWith(u8, text, "v")) continue;
        if (std.mem.indexOfScalar(u8, text, '(') != null) continue;
        // Forms that write registers they do not name, or the loop's own
        // registers, are outside what this check can express.
        const skipped = [_][]const u8{ "vzeroupper", "vzeroall", "vpcmpestr", "vpcmpistr", "vmaskmov", "vldmxcsr", "vstmxcsr", "%k", "%zmm", "%r15", "%rsp", "%esp", "%rip" };
        var skip = false;
        for (skipped) |name| {
            if (std.mem.indexOf(u8, text, name) != null) skip = true;
        }
        if (skip) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        if (length == 0 or (bytes[0] != 0xC4 and bytes[0] != 0xC5)) continue;
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.len != length) continue;
        // AT&T puts the destination last. A general register or no operand
        // there (flag-only tests, moves to a GPR) means no vector register
        // may change.
        var destination: ?u8 = null;
        if (std.mem.lastIndexOfScalar(u8, text, '%')) |at| {
            const rest = text[at + 1 ..];
            if (std.mem.startsWith(u8, rest, "xmm") or std.mem.startsWith(u8, rest, "ymm")) {
                var end: usize = 3;
                while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') end += 1;
                destination = std.fmt.parseInt(u8, rest[3..end], 10) catch continue;
            }
        }
        // The form, then `dec r15 ; jnz` back to it and `hlt`, so it runs
        // forty times and the translator compiles it.
        var program: [24]u8 = undefined;
        @memcpy(program[0..length], bytes[0..length]);
        program[length..][0..3].* = .{ 0x49, 0xFF, 0xCF };
        program[length + 3] = 0x75;
        program[length + 4] = @bitCast(@as(i8, -@as(i8, @intCast(length + 5))));
        program[length + 5] = 0xF4;
        const runs = [_]bool{ false, true };
        var results: [2]DifferentialOutcome = undefined;
        for (runs, 0..) |translate, run| {
            results[run] = runDifferentialProgramConfigured(program[0 .. length + 6], 0x5EED_0000 + checked, translate, .{ .seed_all_vectors = true });
            const outcome = &results[run];
            if (!outcome.terminated or outcome.faulted) {
                if (failures < 40) std.debug.print("executor roles: {s} ({s}) did not run to completion\n", .{ text, if (translate) "translated" else "interpreted" });
                failures += 1;
                continue;
            }
            for (0..16) |register| {
                if (destination != null and destination.? == register) continue;
                const low_changed = !std.mem.eql(u8, &outcome.xmm[register], &outcome.initial_xmm[register]);
                const high_changed = !std.mem.eql(u8, &outcome.ymm_hi[register], &outcome.initial_ymm_hi[register]);
                if (low_changed or high_changed) {
                    if (failures < 40) std.debug.print("executor roles: {s} ({s}) changed xmm{d}{s}, not only its destination\n", .{ text, if (translate) "translated" else "interpreted", register, if (low_changed) "" else " (upper half)" });
                    failures += 1;
                }
            }
        }
        if (destination) |register| {
            const same = std.mem.eql(u8, &results[0].xmm[register], &results[1].xmm[register]) and
                std.mem.eql(u8, &results[0].ymm_hi[register], &results[1].ymm_hi[register]);
            if (!same) {
                if (failures < 40) std.debug.print("executor roles: {s} leaves different values in its destination interpreted and translated: initial {x}/{x} interpreted {x}/{x} translated {x}/{x}\n", .{
                    text,
                    results[0].initial_xmm[register],
                    results[0].initial_ymm_hi[register],
                    results[0].xmm[register],
                    results[0].ymm_hi[register],
                    results[1].xmm[register],
                    results[1].ymm_hi[register],
                });
                failures += 1;
            }
        }
        checked += 1;
    }
    std.debug.print("executor roles: checked {d} register-only VEX forms, {d} failures\n", .{ checked, failures });
    try testing.expect(checked > 100);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "VTEST sign executor roles: every memory VEX form Xenia's JIT emits touches only its destination and its operand, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Xenia's generated code keeps PowerPC registers in its context and
    // spills to the host stack, so most of its vector traffic is memory
    // forms. Point the base and index registers into the data window, run
    // each form forty times both ways, and require: only the named vector
    // destination changes, and both runs leave the same registers and the
    // same memory.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    const names = [_][]const u8{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" };
    const regNumber = struct {
        fn of(text: []const u8, table: []const []const u8) ?u4 {
            for (table, 0..) |name, number| {
                if (std.mem.eql(u8, text, name)) return @intCast(number);
            }
            return null;
        }
    }.of;
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        if (!std.mem.startsWith(u8, text, "v")) continue;
        const open = std.mem.indexOfScalar(u8, text, '(') orelse continue;
        const close = std.mem.indexOfScalarPos(u8, text, open, ')') orelse continue;
        const skipped = [_][]const u8{ "vzeroupper", "vzeroall", "vpcmpestr", "vpcmpistr", "vmaskmov", "vgather", "vpgather", "%k", "%zmm", "%r15", "%rsp", "%esp", "%rip", "%e", ":" };
        var skip = false;
        for (skipped) |name| {
            if (std.mem.indexOf(u8, text, name) != null) skip = true;
        }
        if (skip) continue;
        var start = open;
        while (start > 0 and text[start - 1] != ' ' and text[start - 1] != ',') start -= 1;
        const displacement_text = text[start..open];
        if (displacement_text.len > 0) {
            const displacement = std.fmt.parseInt(i64, displacement_text, 0) catch continue;
            if (displacement < -0x700 or displacement > 0x700) continue;
        }
        var inside = std.mem.splitScalar(u8, text[open + 1 .. close], ',');
        const base_text = inside.next() orelse "";
        const index_text = inside.next() orelse "";
        var config: DifferentialConfig = .{ .seed_all_vectors = true };
        if (base_text.len > 1) {
            const number = regNumber(base_text[1..], &names) orelse continue;
            config.base_registers |= @as(u16, 1) << number;
        }
        if (index_text.len > 1) {
            const number = regNumber(index_text[1..], &names) orelse continue;
            if (config.base_registers & (@as(u16, 1) << number) != 0) continue;
            config.index_registers |= @as(u16, 1) << number;
        }
        // rbx is the harness's data pointer either way.
        if (std.mem.indexOf(u8, text, "%rbx") != null and !std.mem.eql(u8, base_text, "%rbx")) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        if (length == 0 or (bytes[0] != 0xC4 and bytes[0] != 0xC5)) continue;
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.len != length or decoded.is_reg_form) continue;
        // AT&T puts the destination last: a vector register there is the one
        // register allowed to change; a memory operand there means none may.
        var destination: ?u8 = null;
        if (std.mem.lastIndexOfScalar(u8, text, '%')) |at| {
            if (at > close) {
                const rest = text[at + 1 ..];
                if (std.mem.startsWith(u8, rest, "xmm") or std.mem.startsWith(u8, rest, "ymm")) {
                    var end: usize = 3;
                    while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') end += 1;
                    destination = std.fmt.parseInt(u8, rest[3..end], 10) catch continue;
                }
            }
        }
        var program: [24]u8 = undefined;
        @memcpy(program[0..length], bytes[0..length]);
        program[length..][0..3].* = .{ 0x49, 0xFF, 0xCF };
        program[length + 3] = 0x75;
        program[length + 4] = @bitCast(@as(i8, -@as(i8, @intCast(length + 5))));
        program[length + 5] = 0xF4;
        var results: [2]DifferentialOutcome = undefined;
        var complete = true;
        for ([_]bool{ false, true }, 0..) |translate, run| {
            results[run] = runDifferentialProgramConfigured(program[0 .. length + 6], 0x5EED_8000 + checked, translate, config);
            const outcome = &results[run];
            if (!outcome.terminated or outcome.faulted) {
                if (failures < 40) std.debug.print("memory executor roles: {s} ({s}) did not run to completion\n", .{ text, if (translate) "translated" else "interpreted" });
                failures += 1;
                complete = false;
                continue;
            }
            for (0..16) |register| {
                if (destination != null and destination.? == register) continue;
                const low_changed = !std.mem.eql(u8, &outcome.xmm[register], &outcome.initial_xmm[register]);
                const high_changed = !std.mem.eql(u8, &outcome.ymm_hi[register], &outcome.initial_ymm_hi[register]);
                if (low_changed or high_changed) {
                    if (failures < 40) std.debug.print("memory executor roles: {s} ({s}) changed xmm{d}{s}, not only its destination\n", .{ text, if (translate) "translated" else "interpreted", register, if (low_changed) "" else " (upper half)" });
                    failures += 1;
                }
            }
        }
        if (complete) {
            for (0..16) |register| {
                const same = std.mem.eql(u8, &results[0].xmm[register], &results[1].xmm[register]) and
                    std.mem.eql(u8, &results[0].ymm_hi[register], &results[1].ymm_hi[register]);
                if (!same) {
                    if (failures < 40) std.debug.print("memory executor roles: {s} leaves xmm{d} different interpreted and translated: interpreted {x}/{x} translated {x}/{x}\n", .{ text, register, results[0].xmm[register], results[0].ymm_hi[register], results[1].xmm[register], results[1].ymm_hi[register] });
                    failures += 1;
                }
            }
            if (!std.mem.eql(u8, &results[0].data, &results[1].data)) {
                if (failures < 40) std.debug.print("memory executor roles: {s} leaves different memory interpreted and translated\n", .{text});
                failures += 1;
            }
        }
        checked += 1;
    }
    std.debug.print("memory executor roles: checked {d} memory VEX forms, {d} failures\n", .{ checked, failures });
    try testing.expect(checked > 100);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "VTEST sign scalar conversions Xenia lowers lfs, frsp and fcfid to merge from VEX.vvvv and convert r/m, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // The translator hands these forms to the interpreter, so the executor
    // sweeps compare the interpreter with itself here. Check them against
    // x86: the result goes to ModR/M.reg, the bits above it come from
    // VEX.vvvv, the converted value from r/m, and VEX.128 zeroes the upper
    // YMM half. Xenia's FPU lowering (lfs, frsp, fcfid) runs between a
    // packed VMX value's load and its use in Halo 3's clear packer.
    const Form = struct { bytes: [5]u8, kind: enum { ss2sd, sd2ss, si2sd } };
    const forms = [_]Form{
        .{ .bytes = .{ 0xC4, 0xE1, 0x72, 0x5A, 0xD3 }, .kind = .ss2sd }, // vcvtss2sd xmm2, xmm1, xmm3
        .{ .bytes = .{ 0xC4, 0xE1, 0x73, 0x5A, 0xD3 }, .kind = .sd2ss }, // vcvtsd2ss xmm2, xmm1, xmm3
        .{ .bytes = .{ 0xC4, 0xE1, 0xF3, 0x2A, 0xD0 }, .kind = .si2sd }, // vcvtsi2sd xmm2, xmm1, rax
    };
    for (forms) |form| {
        var program: [11]u8 = undefined;
        @memcpy(program[0..5], &form.bytes);
        program[5..][0..3].* = .{ 0x49, 0xFF, 0xCF }; // dec r15
        program[8] = 0x75;
        program[9] = @bitCast(@as(i8, -10));
        program[10] = 0xF4;
        for ([_]bool{ false, true }) |translate| {
            for (0..6) |trial| {
                const outcome = runDifferentialProgramConfigured(&program, 0xC0F7_0000 + trial, translate, .{ .seed_all_vectors = true });
                try testing.expect(outcome.terminated and !outcome.faulted);
                const merge = outcome.initial_xmm[1];
                const source = outcome.initial_xmm[3];
                var expected = merge;
                switch (form.kind) {
                    .ss2sd => {
                        const value: f32 = @bitCast(std.mem.readInt(u32, source[0..4], .little));
                        const converted: f64 = @floatCast(value);
                        if (!std.math.isNan(value)) std.mem.writeInt(u64, expected[0..8], @bitCast(converted), .little);
                    },
                    .sd2ss => {
                        const value: f64 = @bitCast(std.mem.readInt(u64, source[0..8], .little));
                        const converted: f32 = @floatCast(value);
                        if (!std.math.isNan(value)) std.mem.writeInt(u32, expected[0..4], @bitCast(converted), .little);
                    },
                    .si2sd => {
                        const value: i64 = @bitCast(outcome.regs.rax);
                        const converted: f64 = @floatFromInt(value);
                        std.mem.writeInt(u64, expected[0..8], @bitCast(converted), .little);
                    },
                }
                // NaN payload propagation is not what this checks.
                const nan_source = switch (form.kind) {
                    .ss2sd => std.math.isNan(@as(f32, @bitCast(std.mem.readInt(u32, source[0..4], .little)))),
                    .sd2ss => std.math.isNan(@as(f64, @bitCast(std.mem.readInt(u64, source[0..8], .little)))),
                    .si2sd => false,
                };
                const result = outcome.xmm[2];
                const low_bytes: usize = if (form.kind == .sd2ss) 4 else 8;
                const upper_ok = std.mem.eql(u8, result[low_bytes..], expected[low_bytes..]);
                const low_ok = nan_source or std.mem.eql(u8, result[0..low_bytes], expected[0..low_bytes]);
                const ymm_ok = std.mem.eql(u8, &outcome.ymm_hi[2], &(@as([16]u8, @splat(0))));
                if (!(upper_ok and low_ok and ymm_ok)) {
                    std.debug.print("{s} ({s}) trial {d}: expected {x} got {x} ymm_hi {x}\n", .{ @tagName(form.kind), if (translate) "translated" else "interpreted", trial, expected, result, outcome.ymm_hi[2] });
                    return error.TestUnexpectedResult;
                }
                // The sources are untouched.
                try testing.expectEqualSlices(u8, &merge, &outcome.xmm[1]);
                try testing.expectEqualSlices(u8, &source, &outcome.xmm[3]);
            }
        }
    }
}

test "VTEST sign shifts by an xmm count use its low 64 bits and saturate at the lane width, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // vpsrlw/d/q, vpsraw/d, vpsllw/d/q xmm2, xmm3, xmm1. Xenia emits these
    // for vector shifts by a uniform variable amount; both executors shifted
    // by the (absent) immediate, so they changed nothing.
    const forms = [_]struct { opcode: u8, lane_bits: u7, left: bool, arithmetic: bool }{
        .{ .opcode = 0xD1, .lane_bits = 16, .left = false, .arithmetic = false },
        .{ .opcode = 0xD2, .lane_bits = 32, .left = false, .arithmetic = false },
        .{ .opcode = 0xD3, .lane_bits = 64, .left = false, .arithmetic = false },
        .{ .opcode = 0xE1, .lane_bits = 16, .left = false, .arithmetic = true },
        .{ .opcode = 0xE2, .lane_bits = 32, .left = false, .arithmetic = true },
        .{ .opcode = 0xF1, .lane_bits = 16, .left = true, .arithmetic = false },
        .{ .opcode = 0xF2, .lane_bits = 32, .left = true, .arithmetic = false },
        .{ .opcode = 0xF3, .lane_bits = 64, .left = true, .arithmetic = false },
    };
    for (forms) |form| {
        const counts = [_]u64{ 0, 1, form.lane_bits - 1, form.lane_bits, form.lane_bits + 1, 1 << 32, 1 << 63 };
        for (counts) |count| {
            // mov rax, count ; vpinsrq xmm1, xmm1, rax, 0 (the high qword stays
            // random) ; then the shift forty times.
            var program: [32]u8 = undefined;
            program[0..2].* = .{ 0x48, 0xB8 };
            std.mem.writeInt(u64, program[2..10], count, .little);
            program[10..16].* = .{ 0xC4, 0xE3, 0xF1, 0x22, 0xC8, 0x00 };
            program[16..20].* = .{ 0xC5, 0xE1, form.opcode, 0xD1 };
            program[20..23].* = .{ 0x49, 0xFF, 0xCF };
            program[23] = 0x75;
            program[24] = @bitCast(@as(i8, -9));
            program[25] = 0xF4;
            for ([_]bool{ false, true }) |translate| {
                const outcome = runDifferentialProgramConfigured(program[0..26], 0x5A1F_7000 + count % 977, translate, .{ .seed_all_vectors = true });
                try testing.expect(outcome.terminated and !outcome.faulted);
                const source = outcome.initial_xmm[3];
                var expected: [16]u8 = undefined;
                const lane_bytes: usize = form.lane_bits / 8;
                var offset: usize = 0;
                while (offset < 16) : (offset += lane_bytes) {
                    var value: u64 = 0;
                    for (0..lane_bytes) |byte| value |= @as(u64, source[offset + byte]) << @intCast(byte * 8);
                    const mask: u64 = if (form.lane_bits == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(form.lane_bits)) - 1;
                    const sign = (value >> @intCast(form.lane_bits - 1)) & 1 != 0;
                    const result: u64 = if (count >= form.lane_bits)
                        (if (form.arithmetic and sign) mask else 0)
                    else if (form.left)
                        (value << @intCast(count)) & mask
                    else if (form.arithmetic and sign)
                        ((value >> @intCast(count)) | ~(mask >> @intCast(count))) & mask
                    else
                        value >> @intCast(count);
                    for (0..lane_bytes) |byte| expected[offset + byte] = @truncate(result >> @intCast(byte * 8));
                }
                if (!std.mem.eql(u8, &expected, &outcome.xmm[2])) {
                    std.debug.print("shift 0x{x} by {d} ({s}): expected {x} got {x}\n", .{ form.opcode, count, if (translate) "translated" else "interpreted", expected, outcome.xmm[2] });
                    return error.TestUnexpectedResult;
                }
                if (translate) try testing.expect(outcome.translated_instructions > 0);
            }
        }
    }
}

test "VTEST sign VPERMILPS with a control vector selects whole dwords within each lane, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // xenia_canary.exe's PrimitiveProcessor::QuadListToTriangleList (24-bit
    // indices) shuffles indices with `vpermilps ymm, ymm, ymm`. The
    // translator built its table index from the dword's byte offset in the
    // low byte only, so each result took byte 0 from the selected dword and
    // bytes 1-3 from dword 0: quad lists became garbage triangles once the
    // converter ran translated.
    const forms = [_]struct { bytes: [5]u8, wide: bool }{
        .{ .bytes = .{ 0xC4, 0xE2, 0x61, 0x0C, 0xD1 }, .wide = false }, // vpermilps xmm2, xmm3, xmm1
        .{ .bytes = .{ 0xC4, 0xE2, 0x65, 0x0C, 0xD1 }, .wide = true }, // vpermilps ymm2, ymm3, ymm1
    };
    for (forms) |form| {
        var program: [11]u8 = undefined;
        @memcpy(program[0..5], &form.bytes);
        program[5..][0..3].* = .{ 0x49, 0xFF, 0xCF }; // dec r15
        program[8] = 0x75; // jnz back to the form
        program[9] = @bitCast(@as(i8, -10));
        program[10] = 0xF4;
        for ([_]bool{ false, true }) |translate| {
            for (0..8) |trial| {
                const outcome = runDifferentialProgramConfigured(&program, 0x9E81_0000 + trial, translate, .{ .seed_all_vectors = true });
                try testing.expect(outcome.terminated and !outcome.faulted);
                const halves = [_][16]u8{ outcome.initial_xmm[3], outcome.initial_ymm_hi[3] };
                const controls = [_][16]u8{ outcome.initial_xmm[1], outcome.initial_ymm_hi[1] };
                const results = [_][16]u8{ outcome.xmm[2], outcome.ymm_hi[2] };
                for (0..2) |half| {
                    var expected: [16]u8 = @splat(0);
                    if (half == 0 or form.wide) {
                        for (0..4) |lane| {
                            const select = std.mem.readInt(u32, controls[half][lane * 4 ..][0..4], .little) & 3;
                            @memcpy(expected[lane * 4 ..][0..4], halves[half][select * 4 ..][0..4]);
                        }
                    }
                    if (!std.mem.eql(u8, &expected, &results[half])) {
                        std.debug.print("vpermilps {s} ({s}) half {d}: expected {x} got {x}\n", .{ if (form.wide) "ymm" else "xmm", if (translate) "translated" else "interpreted", half, expected, results[half] });
                        return error.TestUnexpectedResult;
                    }
                }
            }
        }
    }
}

/// The vector registers an encoding names, read from its bytes without the
/// decoder: ModRM.reg, ModRM.r/m in the register form, VEX.vvvv when the
/// form has a third operand (or is a VEX.NDD shift by an immediate, where
/// vvvv is the destination), the is4 register when it has a fourth, and the
/// implicit xmm0 of the legacy blends. `operands` counts the assembler
/// text's operands other than immediates. A register field that holds a
/// general register or an opcode extension is included too; that only
/// narrows what the source checks below perturb.
const NamedVectors = struct {
    mask: u16,
    reg: u8,
    rm: ?u8,
    vex: bool,
    shift_group: bool,
};

fn namedVectorRegisters(bytes: []const u8, operands: usize) ?NamedVectors {
    var pos: usize = 0;
    while (pos < bytes.len) : (pos += 1) {
        switch (bytes[pos]) {
            0x66, 0xF2, 0xF3, 0x2E, 0x3E, 0x26, 0x64, 0x65, 0x36 => {},
            else => break,
        }
    }
    if (pos >= bytes.len) return null;
    var rex_r = false;
    var rex_b = false;
    var vex = false;
    var vvvv: u8 = 0;
    var map: u8 = 1;
    var opcode: u8 = 0;
    if (bytes[pos] == 0xC5) {
        if (pos + 2 >= bytes.len) return null;
        const control = bytes[pos + 1];
        rex_r = control & 0x80 == 0;
        vvvv = (~control >> 3) & 0xF;
        vex = true;
        opcode = bytes[pos + 2];
        pos += 3;
    } else if (bytes[pos] == 0xC4) {
        if (pos + 3 >= bytes.len) return null;
        const select = bytes[pos + 1];
        const control = bytes[pos + 2];
        rex_r = select & 0x80 == 0;
        rex_b = select & 0x20 == 0;
        map = select & 0x1F;
        vvvv = (~control >> 3) & 0xF;
        vex = true;
        opcode = bytes[pos + 3];
        pos += 4;
    } else {
        if (bytes[pos] & 0xF0 == 0x40) {
            rex_r = bytes[pos] & 4 != 0;
            rex_b = bytes[pos] & 1 != 0;
            pos += 1;
        }
        if (pos >= bytes.len or bytes[pos] != 0x0F) return null;
        pos += 1;
        if (pos < bytes.len and (bytes[pos] == 0x38 or bytes[pos] == 0x3A)) {
            map = if (bytes[pos] == 0x38) 2 else 3;
            pos += 1;
        }
        if (pos >= bytes.len) return null;
        opcode = bytes[pos];
        pos += 1;
    }
    if (pos >= bytes.len) return null;
    const modrm = bytes[pos];
    const reg: u8 = ((modrm >> 3) & 7) | (@as(u8, @intFromBool(rex_r)) << 3);
    const rm: ?u8 = if (modrm >> 6 == 3) (modrm & 7) | (@as(u8, @intFromBool(rex_b)) << 3) else null;
    const shift_group = map == 1 and (opcode == 0x71 or opcode == 0x72 or opcode == 0x73);
    var named = NamedVectors{ .mask = @as(u16, 1) << @intCast(reg), .reg = reg, .rm = rm, .vex = vex, .shift_group = shift_group };
    if (rm) |number| named.mask |= @as(u16, 1) << @intCast(number);
    if (vex and (operands >= 3 or shift_group)) named.mask |= @as(u16, 1) << @intCast(vvvv);
    if (operands >= 4) named.mask |= @as(u16, 1) << @intCast(bytes[bytes.len - 1] >> 4);
    // BLENDVPS/BLENDVPD/PBLENDVB and SHA256RNDS2 read xmm0 implicitly.
    if (!vex and map == 2 and (opcode == 0x10 or opcode == 0x14 or opcode == 0x15 or opcode == 0xCB)) named.mask |= 1;
    return named;
}

/// Operands of an assembler text (after its mnemonic) other than
/// immediates, splitting at commas outside () and [], and whether every one
/// of them is a vector register.
fn countTextOperands(operand_text: []const u8) struct { count: usize, vectors_only: bool } {
    var count: usize = 0;
    var vectors_only = true;
    var depth: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= operand_text.len) : (index += 1) {
        const at_end = index == operand_text.len;
        const char: u8 = if (at_end) ',' else operand_text[index];
        switch (char) {
            '(', '[' => depth += 1,
            ')', ']' => depth -|= 1,
            ',' => if (depth == 0) {
                const operand = std.mem.trim(u8, operand_text[start..index], " ");
                start = index + 1;
                if (operand.len == 0 or operand[0] == '$' or std.mem.startsWith(u8, operand, "imm")) continue;
                count += 1;
                const name = if (operand[0] == '%') operand[1..] else operand;
                if (!std.mem.startsWith(u8, name, "xmm") and !std.mem.startsWith(u8, name, "ymm")) vectors_only = false;
            },
            else => {},
        }
    }
    return .{ .count = count, .vectors_only = vectors_only };
}

const SourceCheck = enum { passed, skipped, failed };

/// Runs one form, interpreted, against two oracles that need no reference
/// implementation. Changing every vector register the encoding does not
/// name must leave every general register, the flags, memory and the named
/// registers exactly as they were. And a one-source form's destination must
/// change when its source does. Both executors and the decoder agree with
/// each other on a form that reads the wrong register (the corpus sweeps
/// compare them), so this is what notices: VROUNDPS read xmm0 instead of its
/// r/m operand and turned Halo 3's clear colours into (2^bits - 1, 0, 0, 0).
fn checkFormSources(bytes: []const u8, decoded: DecodedInsn, operand_text: []const u8, label: []const u8, seed: u64, failures: *usize) SourceCheck {
    const operands = countTextOperands(operand_text);
    const named = namedVectorRegisters(bytes, operands.count) orelse return .skipped;
    var config: DifferentialConfig = .{ .seed_all_vectors = true };
    if (!decoded.is_reg_form) {
        if (decoded.rip_relative) return .skipped;
        if (decoded.sib_has_base) config.base_registers |= @as(u16, 1) << @intCast(@intFromEnum(decoded.sib_base_reg));
        if (decoded.sib_has_index) {
            const bit = @as(u16, 1) << @intCast(@intFromEnum(decoded.sib_index_reg));
            if (config.base_registers & bit != 0) return .skipped;
            config.index_registers |= bit;
        }
        if (!decoded.sib_has_base and !decoded.sib_has_index) return .skipped;
        const displacement: i64 = @bitCast(decoded.addr);
        if (displacement < -0x700 or displacement > 0x700) return .skipped;
    }
    for ([_]u8{ 3, 4, 15 }) |number| {
        if (config.base_registers & (@as(u16, 1) << @intCast(number)) != 0 and number != 3) return .skipped;
        if (config.index_registers & (@as(u16, 1) << @intCast(number)) != 0) return .skipped;
    }
    var program: [16]u8 = undefined;
    @memcpy(program[0..bytes.len], bytes);
    program[bytes.len] = 0xF4;
    const code = program[0 .. bytes.len + 1];
    const base = runDifferentialProgramConfigured(code, seed, false, config);
    if (!base.terminated or base.faulted) return .skipped;
    var perturbed_config = config;
    perturbed_config.perturb_vectors = ~named.mask;
    perturbed_config.perturb_seed = seed ^ 0x5A5A_0000;
    const other = runDifferentialProgramConfigured(code, seed, false, perturbed_config);
    var failed = false;
    if (!other.terminated or other.faulted) {
        failed = true;
    } else {
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip", "rflags" }) |name| {
            if (@field(base.regs, name) != @field(other.regs, name)) failed = true;
        }
        if (!std.mem.eql(u8, &base.data, &other.data)) failed = true;
        for (0..16) |register| {
            if (named.mask & (@as(u16, 1) << @intCast(register)) == 0) continue;
            if (!std.mem.eql(u8, &base.xmm[register], &other.xmm[register]) or !std.mem.eql(u8, &base.ymm_hi[register], &other.ymm_hi[register])) failed = true;
        }
    }
    if (failed) {
        if (failures.* < 40) std.debug.print("operand sources: {s} [{x}] depends on a vector register its encoding does not name (named mask 0x{x:0>4})\n", .{ label, bytes, named.mask });
        failures.* += 1;
        return .failed;
    }
    // A one-source vector form: its destination must follow its source.
    if (!named.vex or operands.count != 2 or !operands.vectors_only or !decoded.is_reg_form) return .passed;
    var destination: ?u8 = null;
    for (0..16) |register| {
        const changed = !std.mem.eql(u8, &base.xmm[register], &base.initial_xmm[register]) or !std.mem.eql(u8, &base.ymm_hi[register], &base.initial_ymm_hi[register]);
        if (!changed) continue;
        if (destination != null) return .passed;
        destination = @intCast(register);
    }
    const written = destination orelse return .passed;
    if (std.mem.allEqual(u8, &base.xmm[written], 0)) return .passed;
    const rm = named.rm orelse return .passed;
    const source: u8 = if (named.shift_group) rm else if (named.reg == written) rm else named.reg;
    if (source == written and named.reg != rm and !named.shift_group) return .passed;
    for (0..3) |attempt| {
        var moved = config;
        moved.perturb_vectors = @as(u16, 1) << @intCast(source);
        moved.perturb_seed = seed ^ (0xC0DE_0000 + attempt);
        const outcome = runDifferentialProgramConfigured(code, seed, false, moved);
        if (!outcome.terminated or outcome.faulted) continue;
        if (!std.mem.eql(u8, &outcome.xmm[written], &base.xmm[written]) or !std.mem.eql(u8, &outcome.ymm_hi[written], &base.ymm_hi[written])) return .passed;
    }
    if (failures.* < 40) std.debug.print("operand sources: {s} [{x}] leaves xmm{d} unchanged when its source xmm{d} changes\n", .{ label, bytes, written, source });
    failures.* += 1;
    return .failed;
}

test "VTEST sign operand sources: every VEX form Xenia's JIT emits reads only the registers it names, and follows its source" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        if (!std.mem.startsWith(u8, text, "v")) continue;
        const skipped = [_][]const u8{ "vzeroupper", "vzeroall", "vpcmpestr", "vpcmpistr", "vmaskmov", "vldmxcsr", "vstmxcsr", "gather", "%k", "%zmm", "%r15", "%rsp", "%esp", "%rip" };
        var skip = false;
        for (skipped) |name| {
            if (std.mem.indexOf(u8, text, name) != null) skip = true;
        }
        if (skip) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        if (length == 0 or (bytes[0] != 0xC4 and bytes[0] != 0xC5)) continue;
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.len != length) continue;
        const space = std.mem.indexOfScalar(u8, text, ' ') orelse continue;
        switch (checkFormSources(bytes[0..length], decoded, text[space + 1 ..], text, 0x50C0_0000 + checked, &failures)) {
            .passed, .failed => checked += 1,
            .skipped => {},
        }
    }
    std.debug.print("operand sources: checked {d} VEX forms of Xenia's JIT, {d} failures\n", .{ checked, failures });
    try testing.expect(checked > 300);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "VTEST sign operand sources: every SSE and AVX form in xenia_canary.exe reads only the registers it names, and follows its source" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Thousands of programs: `zig build render-cpu-check` sets this.
    if (std.c.getenv("ROSETTE_EXECUTOR_SWEEP") == null) return error.SkipZigTest;
    const corpus = @embedFile("../../xenia_image_corpus.txt");
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        const shape = fields.next() orelse continue;
        if (std.mem.indexOf(u8, shape, "xmm") == null and std.mem.indexOf(u8, shape, "ymm") == null) continue;
        const skipped = [_][]const u8{ "zeroupper", "zeroall", "pcmpestr", "pcmpistr", "maskmov", "gather", "ldmxcsr", "stmxcsr", "m[rip", "cs:", "fs:", "gs:", "xsave", "xrstor", "fxsave", "fxrstor" };
        var skip = false;
        for (skipped) |name| {
            if (std.mem.indexOf(u8, shape, name) != null) skip = true;
        }
        if (skip) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        if (length == 0 or bytes[0] == 0x62) continue;
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.op == .nop or decoded.len != length) continue;
        const space = std.mem.indexOfScalar(u8, shape, ' ') orelse continue;
        // The image corpus marks extended registers with `+`.
        var operand_text: [96]u8 = undefined;
        var operand_length: usize = 0;
        for (shape[space + 1 ..]) |char| {
            if (char == '+' or operand_length == operand_text.len) continue;
            operand_text[operand_length] = char;
            operand_length += 1;
        }
        switch (checkFormSources(bytes[0..length], decoded, operand_text[0..operand_length], shape, 0x50C1_0000 + checked, &failures)) {
            .passed, .failed => checked += 1,
            .skipped => {},
        }
    }
    std.debug.print("operand sources: checked {d} SSE and AVX forms of xenia_canary.exe, {d} failures\n", .{ checked, failures });
    try testing.expect(checked > 1000);
    try testing.expectEqual(@as(usize, 0), failures);
}

/// Native SSE results for the VEX.128 register forms Xenia's JIT emits. Each
/// form's legacy SSE equivalent (run on a scratch copy of the first source
/// where VEX names a separate one) was executed under Apple Rosetta 2, which
/// implements SSE through SSE4.2, over eight inputs per form. The manifest
/// lists hex | VEX text | lane kind | result | the native snippet; the .bin
/// holds, per form and input, 16 result bytes and RFLAGS. Inputs come from
/// `sseOracleInput`, the generator the native driver ran. To regenerate:
/// `tools/x86_oracle/gen_sse_oracle.py`.
const sse_oracle_manifest = @embedFile("../../xenia_jit_sse_oracle.txt");
const sse_oracle_results = @embedFile("../../xenia_jit_sse_oracle.bin");
const sse_oracle_inputs = 8;

fn sseOracleNext(state: *u64) u64 {
    state.* +%= 0x9E37_79B9_7F4A_7C15;
    var z = state.*;
    z = (z ^ (z >> 30)) *% 0xBF58_476D_1CE4_E5B9;
    z = (z ^ (z >> 27)) *% 0x94D0_49BB_1331_11EB;
    return z ^ (z >> 31);
}

const sse_oracle_f32_special = [16]u32{ 0x00000000, 0x80000000, 0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001, 0xFFC00001, 0x00000001, 0x007FFFFF, 0x80000001, 0x7F7FFFFF, 0x3F800000, 0xBF800000, 0x3F000000, 0x4F000000, 0xCF000000 };
const sse_oracle_f64_special = [16]u64{ 0, 0x8000000000000000, 0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000, 0x7FF0000000000001, 0xFFF8000000000001, 1, 0x000FFFFFFFFFFFFF, 0x8000000000000001, 0x7FEFFFFFFFFFFFFF, 0x3FF0000000000000, 0xBFF0000000000000, 0x3FE0000000000000, 0x41E0000000000000, 0xC1E0000000000000 };
const sse_oracle_int_special = [16]u32{ 0, 1, 0x7F, 0x80, 0xFF, 0x7FFF, 0x8000, 0xFFFF, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x00FF00FF, 0x80008000, 0x7FFF8000, 0x01010101, 0xFFFF0000 };

fn sseOracleLane32(r: u64) u32 {
    const p = r >> 3;
    const value: f32 = switch (r & 7) {
        3 => @floatFromInt(@as(i32, @intCast(p % 2001)) - 1000),
        4 => @as(f32, @floatFromInt(@as(i32, @intCast(p % 2001)) - 1000)) + 0.5,
        5 => return sse_oracle_f32_special[@intCast(p % 16)],
        6 => @as(f32, @floatFromInt(@as(i32, @intCast(p % 2000001)) - 1000000)) / 1000000.0,
        7 => return sse_oracle_int_special[@intCast(p % 16)],
        else => return @truncate(p),
    };
    return @bitCast(value);
}

fn sseOracleLane64(r: u64) u64 {
    const p = r >> 3;
    const value: f64 = switch (r & 7) {
        3 => @floatFromInt(@as(i64, @intCast(p % 2001)) - 1000),
        4 => @as(f64, @floatFromInt(@as(i64, @intCast(p % 2001)) - 1000)) + 0.5,
        5 => return sse_oracle_f64_special[@intCast(p % 16)],
        6 => @as(f64, @floatFromInt(@as(i64, @intCast(p % 2000001)) - 1000000)) / 1000000.0,
        else => return r,
    };
    return @bitCast(value);
}

/// The oracle's inputs: sixteen vector registers (as single or double lanes
/// with integers, halves, specials and unit fractions mixed in) and sixteen
/// general registers, from splitmix64.
fn sseOracleInput(form: usize, input: usize, doubles: bool, xmm: *[16][16]u8, gprs: *[16]u64) void {
    var state: u64 = 0x0A11_CE00_0000_0000 + @as(u64, form) * 64 + input;
    for (xmm) |*register| {
        if (doubles) {
            for (0..2) |lane| std.mem.writeInt(u64, register[lane * 8 ..][0..8], sseOracleLane64(sseOracleNext(&state)), .little);
        } else {
            for (0..4) |lane| std.mem.writeInt(u32, register[lane * 4 ..][0..4], sseOracleLane32(sseOracleNext(&state)), .little);
        }
    }
    for (gprs) |*register| {
        const r = sseOracleNext(&state);
        const p = r >> 3;
        register.* = switch (r & 7) {
            4 => @bitCast(@as(i64, @intCast(p % 2001)) - 1000),
            5 => @bitCast(@as(i64, @as(i32, @bitCast(sse_oracle_int_special[@intCast(p % 16)])))),
            else => r,
        };
    }
}

test "VTEST sign SSE oracle: every VEX.128 register form Xenia's JIT emits matches native SSE under Rosetta 2" {
    // The executor sweeps compare Rosette with itself; both executors share
    // the decoder and many helpers, so a form they agree on can still be
    // wrong (VROUNDPS rounded xmm0 in both). This compares each form with
    // the hardware-faithful result of its SSE equivalent.
    try testing.expectEqual(@as(usize, 0), sse_oracle_results.len % (24 * sse_oracle_inputs));
    var lines = std.mem.splitScalar(u8, sse_oracle_manifest, '\n');
    var form: usize = 0;
    var checked: usize = 0;
    var failures: usize = 0;
    var nan_payloads: usize = 0;
    var failed_forms: usize = 0;
    var undecoded: usize = 0;
    var last_failed_form: usize = std.math.maxInt(usize);
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    // The interpreter is what this checks; the executor sweeps hold the
    // translator to it.
    state.block_jit_enabled = false;
    var stopped: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        defer form += 1;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse return error.BadManifest;
        const text = fields.next() orelse return error.BadManifest;
        const lane = fields.next() orelse return error.BadManifest;
        const result = fields.next() orelse return error.BadManifest;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| : (length += 1) bytes[length] = try std.fmt.parseInt(u8, token, 16);
        var kind: enum { xmm, gpr, flags } = .flags;
        var register: u8 = 0;
        if (std.mem.startsWith(u8, result, "xmm:")) {
            kind = .xmm;
            var parts = std.mem.splitScalar(u8, result[4..], ':');
            register = try std.fmt.parseInt(u8, parts.next() orelse return error.BadManifest, 10);
        } else if (std.mem.startsWith(u8, result, "gpr:")) {
            kind = .gpr;
            register = try std.fmt.parseInt(u8, result[4..], 10);
        }
        // A form the decoder does not know faults rather than computing a
        // wrong value; it is listed, not compared (VADDSUBPS/PD, used by
        // SDL's render copy and FFmpeg's real DFT, are the known ones).
        if (decodeInsn(bytes[0..length]).op == .invalid) {
            std.debug.print("sse oracle: {s} does not decode\n", .{text});
            undecoded += 1;
            continue;
        }
        // Every form has its own address in one shared state, so no decode is
        // ever stale, and runs one step per input.
        const code_offset: usize = 0x1000 + form * 16;
        if (code_offset + 16 > 0x30000) return error.OracleTooLarge;
        @memcpy(state.mem[code_offset..][0..length], bytes[0..length]);
        for (0..sse_oracle_inputs) |input| {
            const record = sse_oracle_results[(form * sse_oracle_inputs + input) * 24 ..][0..24];
            var xmm: [16][16]u8 = undefined;
            var gprs: [16]u64 = undefined;
            sseOracleInput(form, input, std.mem.eql(u8, lane, "pd"), &xmm, &gprs);
            state.xmm[0..16].* = xmm;
            for (state.ymm_hi[0..16]) |*half| half.* = @splat(0xA5);
            inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" }, 0..) |name, number| {
                @field(state.regs, name) = gprs[number];
            }
            state.regs.rsp = MEM_BASE + 0x40000;
            state.regs.rip = MEM_BASE + code_offset;
            state.regs.rflags = 0x2;
            const stepped = state.step();
            const ran = stepped and !state.terminated and !state.faulted and state.regs.rip == MEM_BASE + code_offset + length;
            defer if (!ran) {
                // A form that stops the guest would stop every later one in
                // this state too: start a fresh one.
                if (stopped < 8) std.debug.print("sse oracle: {s} input {d} did not run to its end (terminated={} faulted={} rip=0x{x})\n", .{ text, input, state.terminated, state.faulted, state.regs.rip });
                stopped += 1;
                state.deinit();
                state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
                state.block_jit_enabled = false;
                @memcpy(state.mem[code_offset..][0..length], bytes[0..length]);
            };
            var wrong = !ran;
            switch (kind) {
                .xmm => {
                    if (!std.mem.eql(u8, &state.xmm[register], record[0..16])) wrong = true;
                    if (!std.mem.allEqual(u8, &state.ymm_hi[register], 0)) wrong = true;
                },
                .gpr => {
                    const value: u64 = switch (register) {
                        inline 0...15 => |number| @field(state.regs, ([_][]const u8{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" })[number]),
                        else => unreachable,
                    };
                    if (value != std.mem.readInt(u64, record[0..8], .little)) wrong = true;
                },
                .flags => {
                    // The flags each form defines: PTEST sets ZF and CF (Rosetta
                    // 2 leaves PF from before, though Intel clears it), the
                    // scalar compares ZF, PF and CF.
                    const mask: u64 = if (std.mem.indexOf(u8, text, "ptest") != null) 0x41 else 0x45;
                    if ((state.regs.rflags & mask) != (std.mem.readInt(u64, record[16..24], .little) & mask)) wrong = true;
                },
            }
            // NaN against NaN counts as agreement: Rosette's invalid
            // operations give AArch64's default NaN (0x7FC00000) where x86
            // gives 0xFFC00000, and Xenia normalises NaNs to PowerPC's
            // 0x7FC00000 where a title could see them. Counted, not failed.
            // RCP and RSQRT are estimates whose bits differ between vendors
            // (and between Rosetta 2 and AArch64's FRECPE): both only promise
            // a relative error of 1.5 * 2^-12.
            const estimate = std.mem.indexOf(u8, text, "rcp") != null or std.mem.indexOf(u8, text, "rsqrt") != null;
            if (wrong and estimate and kind == .xmm and ran) {
                var close = true;
                for (0..4) |index| {
                    const got_value: f32 = @bitCast(std.mem.readInt(u32, state.xmm[register][index * 4 ..][0..4], .little));
                    const want_value: f32 = @bitCast(std.mem.readInt(u32, record[index * 4 ..][0..4], .little));
                    if (@as(u32, @bitCast(got_value)) == @as(u32, @bitCast(want_value))) continue;
                    if (std.math.isNan(got_value) and std.math.isNan(want_value)) continue;
                    // x86 treats a denormal input as zero (an infinite
                    // estimate); Rosette computes the exact reciprocal.
                    if (std.math.isInf(want_value) and @abs(got_value) >= 0x1p62 and std.math.signbit(got_value) == std.math.signbit(want_value)) continue;
                    if (!std.math.isFinite(got_value) or !std.math.isFinite(want_value) or @abs(got_value - want_value) > 3.0 / 4096.0 * @abs(want_value)) close = false;
                }
                if (close) wrong = false;
            }
            if (wrong and kind == .xmm and !std.mem.eql(u8, lane, "int") and ran and std.mem.allEqual(u8, &state.ymm_hi[register], 0)) {
                const doubles = std.mem.eql(u8, lane, "pd");
                var all_agree = true;
                var nan_pairs: usize = 0;
                const width: usize = if (doubles) 8 else 4;
                var offset: usize = 0;
                while (offset < 16) : (offset += width) {
                    const got_lane = state.xmm[register][offset..][0..width];
                    const want_lane = record[offset..][0..width];
                    if (std.mem.eql(u8, got_lane, want_lane)) continue;
                    const both_nan = if (doubles)
                        std.math.isNan(@as(f64, @bitCast(std.mem.readInt(u64, got_lane[0..8], .little)))) and std.math.isNan(@as(f64, @bitCast(std.mem.readInt(u64, want_lane[0..8], .little))))
                    else
                        std.math.isNan(@as(f32, @bitCast(std.mem.readInt(u32, got_lane[0..4], .little)))) and std.math.isNan(@as(f32, @bitCast(std.mem.readInt(u32, want_lane[0..4], .little))));
                    if (both_nan) nan_pairs += 1 else all_agree = false;
                }
                if (all_agree) {
                    wrong = false;
                    nan_payloads += nan_pairs;
                }
            }
            if (wrong) {
                if (failed_forms < 400 and last_failed_form != form) {
                    failed_forms += 1;
                    last_failed_form = form;
                    const got: []const u8 = switch (kind) {
                        .xmm => &state.xmm[register],
                        else => std.mem.asBytes(&state.regs.rflags),
                    };
                    std.debug.print("sse oracle: {s} input {d}: expected {x} (flags 0x{x}) got {x} (rax 0x{x}) ran={}\n", .{ text, input, record[0..16], std.mem.readInt(u64, record[16..24], .little), got, state.regs.rax, ran });
                }
                failures += 1;
            }
            checked += 1;
        }
    }
    std.debug.print("sse oracle: checked {d} runs of {d} forms ({d} not decoded), {d} differ from native SSE ({d} NaN lanes differ only in sign or payload)\n", .{ checked, form, undecoded, failures, nan_payloads });
    try testing.expect(undecoded <= 2);
    try testing.expect(form > 250);
    try testing.expectEqual(@as(usize, 0), failures);
}

/// Xenia's x86-64 translation of Halo 3's fixed-point clear-colour packer:
/// PowerPC 0x82169f28, the 8888 and 2_10_10_10 case of the format switch at
/// 0x82169ec8, as a run logged it with ROSETTE_XENIA_DUMP_GUEST_CODE. The
/// bytes run from `vpxor xmm0` (vspltisw v13, 0) to the packed word's store
/// into r10: the scale vector is built with lfd/fcfid/fsubs/frsp/stfs, loaded
/// with lvx, and the colour in v1 is multiplied, clamped, rounded, converted
/// with vctsxs and packed with slw/or.
const xenia_clear_packer = @embedFile("../../xenia_halo3_clear_packer.bin");

const ClearPackerRun = struct {
    packed_word: u64,
    lanes: [4]i32,
    terminated: bool,
    faulted: bool,
    translated_instructions: u64,
    guest: [0x100]u8,
    context: [0x400]u8,
    xmm: [16][16]u8,
    /// The ops the translator handed to the interpreter, busiest first.
    fallbacks: [8]struct { op: usize = 0, count: u64 = 0 } = @splat(.{}),
    /// Translated block executions, and how many of them were entered by a
    /// native chain hop rather than from the dispatcher.
    block_executions: u64 = 0,
    chain_hops: u64 = 0,
    dispatch_entries: u64 = 0,
};

/// Runs the packer `passes` times over a synthetic PPCContext. Guest
/// addresses (r1, the bit-count tables, the 1.0f literal) are moved below
/// 0x10000 and the XMM constant table into the test window; nothing else in
/// the bytes changes. The MMIO checks compare guest addresses with esi, so
/// they all stay below the context's address and no slow path is taken.
fn runXeniaClearPacker(format: u64, colour: [4]f32, translate: bool, passes: u64, stop_at: ?usize) !ClearPackerRun {
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const code: usize = 0x1000;
    const guest: usize = 0x40000; // rdi, the guest's physical memory
    const context: usize = 0x60000; // rsi, the PPCContext
    const constants: usize = 0x70000; // Xenia's XmmConst table, 0x20000000
    const stack_pointer: u32 = 0x8000; // guest r1
    var program: [xenia_clear_packer.len + 32]u8 = undefined;
    @memcpy(program[0..xenia_clear_packer.len], xenia_clear_packer);
    var relocations: usize = 0;
    var at: usize = 0;
    while (at + 4 <= xenia_clear_packer.len) : (at += 1) {
        const value = std.mem.readInt(u32, program[at..][0..4], .little);
        const relocated: ?u32 = if (value >= 0x2000_0000 and value < 0x2000_1000)
            @intCast(MEM_BASE + constants + (value - 0x2000_0000))
        else switch (value) {
            0x8200_0AFC => 0x0AFC, // the 1.0f the fsubs takes off 2^bits
            0x7DFF_A72C => 0xFFFF_A72C, // r31 + 0x820058d4: alpha bit counts
            0x7DFF_A730 => 0xFFFF_A730, // r31 + 0x820058d0: colour bit counts
            else => null,
        };
        if (relocated) |new| {
            std.mem.writeInt(u32, program[at..][0..4], new, .little);
            relocations += 1;
            at += 3;
        }
    }
    try testing.expectEqual(@as(usize, 20), relocations);
    // Between passes, what Xenia's FPU-mode stub does before the next
    // scalar instruction: vldmxcsr [rsi-16] ; btr dword [rsi-8], 0. Then
    // dec rbp ; jnz to the start ; hlt.
    var tail: usize = xenia_clear_packer.len;
    program[tail..][0..10].* = .{ 0xC5, 0xF8, 0xAE, 0x56, 0xF0, 0x0F, 0xBA, 0x76, 0xF8, 0x00 };
    tail += 10;
    program[tail..][0..5].* = .{ 0x48, 0xFF, 0xCD, 0x0F, 0x85 };
    std.mem.writeInt(i32, program[tail + 5 ..][0..4], -@as(i32, @intCast(tail + 9)), .little);
    tail += 9;
    program[tail] = 0xF4;
    tail += 1;
    if (stop_at) |offset| program[offset] = 0xF4;
    @memcpy(state.mem[code..][0..tail], program[0..tail]);

    const table = state.mem[constants..][0..0x500];
    @memset(table, 0);
    for (0..4) |lane| {
        const word = lane * 4;
        std.mem.writeInt(u32, table[0x10 + word ..][0..4], 0x0001_0203 + 0x0404_0404 * @as(u32, @intCast(lane)), .little); // XMMByteSwapMask
        std.mem.writeInt(u32, table[0x20 + word ..][0..4], @bitCast(@as(f32, 1.0)), .little); // XMMOne
        std.mem.writeInt(u32, table[0x100 + word ..][0..4], 0x7FFF_FFFF, .little); // XMMAbsMaskPS
        std.mem.writeInt(u32, table[0x3F0 + word ..][0..4], 0x8000_0000, .little); // XMMIntMin
        std.mem.writeInt(u32, table[0x400 + word ..][0..4], 0x7FFF_FFFF, .little); // XMMIntMax
        std.mem.writeInt(u32, table[0x460 + word ..][0..4], 0x7F80_0000, .little); // XMMFloatInf
        std.mem.writeInt(u32, table[0x470 + word ..][0..4], if (lane % 2 == 1) 0x7FF0_0000 else 0, .little); // XMMDoubleInf
    }
    // default.xex's bit-count tables and the 1.0f literal, big-endian.
    const bit_counts = [_]u8{ 0x08, 0x08, 0x0a, 0x0a, 0x08, 0x08, 0x02, 0x02, 0x00, 0x0c, 0x18, 0x24, 0x30, 0x3c, 0x48, 0x54, 0x64, 0x00, 0x00, 0x00 };
    @memcpy(state.mem[guest + 0x58D0 ..][0..bit_counts.len], &bit_counts);
    state.mem[guest + 0xAFC ..][0..4].* = .{ 0x3F, 0x80, 0x00, 0x00 };

    const ctx = state.mem[context - 0x40 ..][0..0x440];
    @memset(ctx, 0);
    const c = 0x40; // rsi within `ctx`
    // FPU-mode MXCSR: 0x1F80 unless ROSETTE_PACKER_FPU_MXCSR (hex) models a
    // title running the PowerPC FPU in non-IEEE mode (0x9F80), where both
    // modes flush and the translated `ldmxcsr` leaves FPCR alone.
    const fpu_mxcsr: u32 = if (std.c.getenv("ROSETTE_PACKER_FPU_MXCSR")) |text| std.fmt.parseInt(u32, std.mem.span(text), 16) catch 0x1F80 else 0x1F80;
    std.mem.writeInt(u32, ctx[c - 16 ..][0..4], fpu_mxcsr, .little);
    std.mem.writeInt(u32, ctx[c - 12 ..][0..4], 0x9FC0, .little); // VMX-mode MXCSR
    std.mem.writeInt(u64, ctx[c + 48 ..][0..8], stack_pointer, .little); // r1
    std.mem.writeInt(u64, ctx[c + 288 ..][0..8], format, .little); // r31
    for (colour, 0..) |component, lane| std.mem.writeInt(u32, ctx[c + 592 + lane * 4 ..][0..4], @bitCast(component), .little); // v1

    state.regs.rsi = MEM_BASE + context;
    state.regs.rdi = MEM_BASE + guest;
    state.regs.rbp = passes;
    state.regs.rsp = MEM_BASE + 0x30000;
    state.regs.rip = MEM_BASE + code;
    state.regs.rflags = 0x2;
    state.block_jit_enabled = translate;
    state.block_jit_hot_threshold = 2;
    state.block_jit_internal_edges_enabled = !envPresentAndFalse("ROSETTE_X64_BLOCK_JIT_INTERNAL_EDGES");
    state.runWithLimit(2_000_000 + passes * 512);
    var run = ClearPackerRun{
        .packed_word = std.mem.readInt(u64, ctx[c + 120 ..][0..8], .little),
        .lanes = undefined,
        .terminated = state.terminated,
        .faulted = state.faulted,
        .translated_instructions = if (state.block_jit) |jit| jit.instructions_retired else 0,
        .guest = state.mem[guest + stack_pointer ..][0..0x100].*,
        .context = ctx[c..][0..0x400].*,
        .xmm = state.xmm[0..16].*,
    };
    for (&run.lanes, 0..) |*lane, index| lane.* = std.mem.readInt(i32, run.guest[96 + index * 4 ..][0..4], .big);
    if (state.block_jit) |jit| {
        run.block_executions = jit.executions;
        run.chain_hops = jit.native_chain_hops;
        run.dispatch_entries = jit.dispatch_entries;
        if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH_DUMP") != null) {
            for (jit.blocks) |maybe| {
                const block = maybe orelse continue;
                std.debug.print("BLOCK JIT BENCH CODE: rip=0x{x} x86={d} code=0x{x} words=", .{ block.start_rip - (MEM_BASE + code), block.insns.len, @intFromPtr(block.code.ptr) });
                for (block.code) |word| std.debug.print("{x:0>8} ", .{word});
                std.debug.print("\n", .{});
            }
        }
        for (jit.fallback_ops, 0..) |count, op| {
            if (count == 0) continue;
            var slot: usize = run.fallbacks.len;
            while (slot > 0 and run.fallbacks[slot - 1].count < count) : (slot -= 1) {}
            if (slot == run.fallbacks.len) continue;
            var move = run.fallbacks.len - 1;
            while (move > slot) : (move -= 1) run.fallbacks[move] = run.fallbacks[move - 1];
            run.fallbacks[slot] = .{ .op = op, .count = count };
        }
    }
    return run;
}

test "block jit benchmark: Xenia's compiled clear-colour packer, translated (ROSETTE_BLOCK_JIT_BENCH=1)" {
    if (std.c.getenv("ROSETTE_BLOCK_JIT_BENCH") == null) return error.SkipZigTest;
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Real Xenia x86 for a Halo function: context and guest-memory traffic
    // through rsi/rdi, MMIO compares, movbe, scalar FPU emulation and VMX.
    const passes: u64 = if (std.c.getenv("ROSETTE_PACKER_PASSES")) |text| std.fmt.parseInt(u64, std.mem.span(text), 10) catch 200_000 else 200_000;
    const started = monotonicNanoseconds();
    const run = try runXeniaClearPacker(2, .{ 0.25, 0.75, 1.0, 0.0 }, true, passes, null);
    const elapsed = @max(monotonicNanoseconds() -| started, 1);
    try testing.expect(run.terminated and !run.faulted);
    try testing.expectEqual(@as(u64, 0x3FFB_FD00), run.packed_word);
    std.debug.print("BLOCK JIT BENCH: xenia clear packer: {d} translated instructions in {d} ms = {d} M instr/s; block executions per pass {d}.{d:0>2} (chain hops {d}, dispatch entries {d})\n", .{ run.translated_instructions, elapsed / std.time.ns_per_ms, run.translated_instructions * 1000 / elapsed, run.block_executions / passes, (run.block_executions * 100 / passes) % 100, run.chain_hops, run.dispatch_entries });
    for (run.fallbacks) |entry| {
        if (entry.count == 0) continue;
        std.debug.print("BLOCK JIT BENCH:   fallback {s} x{d}\n", .{ ElfState.op_names[entry.op] orelse "?", entry.count });
    }
}

test "VTEST sign Halo 3's clear-colour packer, as Xenia compiled it, quantises the colour interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Halo's HDR target is cleared with W = 0xFF (pure red at 1/128 scale)
    // and its normal buffer with 0x3FF, which is what this code yields if
    // the multiply sees (1.0f, 0, 0, 0). Hand-computed: round(clamp(colour *
    // (2^bits - 1))), packed low component first.
    const cases = [_]struct { format: u64, colour: [4]f32, lanes: [4]i32, word: u64 }{
        // 2_10_10_10 (the code before these bytes remaps format 10 to 2):
        // 10, 10, 10 and 2 bits.
        .{ .format = 2, .colour = .{ 0.25, 0.75, 1.0, 0.0 }, .lanes = .{ 256, 767, 1023, 0 }, .word = 0x3FFB_FD00 },
        // 8888, Halo's HDR clear colour.
        .{ .format = 0, .colour = .{ 0.0, 0.0, 1.0 / 256.0, 0.0 }, .lanes = .{ 0, 0, 1, 0 }, .word = 0x0001_0000 },
        .{ .format = 0, .colour = .{ 0.2, 0.4, 0.6, 1.0 }, .lanes = .{ 51, 102, 153, 255 }, .word = 0xFF99_6633 },
    };
    for (cases) |case| {
        for ([_]bool{ false, true }) |translate| {
            const run = try runXeniaClearPacker(case.format, case.colour, translate, 24, null);
            if (!run.terminated or run.faulted or !std.mem.eql(i32, &case.lanes, &run.lanes) or run.packed_word != case.word) {
                std.debug.print("clear packer format {d} {s}: lanes {any} word 0x{x} (expected {any} 0x{x}) terminated={} faulted={} translated={d}\n", .{ case.format, if (translate) "translated" else "interpreted", run.lanes, run.packed_word, case.lanes, case.word, run.terminated, run.faulted, run.translated_instructions });
                return error.TestUnexpectedResult;
            }
            if (translate) try testing.expect(run.translated_instructions > 0);
        }
    }
}

test "VTEST sign executor roles: every SSE and AVX form in xenia_canary.exe writes only its destination, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Thousands of programs: `zig build render-cpu-check` sets this.
    if (std.c.getenv("ROSETTE_EXECUTOR_SWEEP") == null) return error.SkipZigTest;
    // The same check over the emulator's own compiled code, legacy SSE
    // included: Xenia's JIT compiler, its GPU command processor and its
    // kernel run these forms, so a stray write here miscompiles or
    // misbehaves downstream. The corpus names register classes, not
    // numbers, so the decoder (verified by the corpus agreement tests)
    // supplies the destination and the base and index registers.
    const corpus = @embedFile("../../xenia_image_corpus.txt");
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        const shape = fields.next() orelse continue;
        if (std.mem.indexOf(u8, shape, "xmm") == null and std.mem.indexOf(u8, shape, "ymm") == null) continue;
        const skipped = [_][]const u8{ "zeroupper", "zeroall", "pcmpestr", "pcmpistr", "maskmov", "gather", "ldmxcsr", "stmxcsr", "m[rip", "cs:", "fs:", "gs:", "xsave", "xrstor", "fxsave", "fxrstor" };
        var skip = false;
        for (skipped) |name| {
            if (std.mem.indexOf(u8, shape, name) != null) skip = true;
        }
        if (skip) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        if (length == 0 or bytes[0] == 0x62) continue;
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.op == .nop or decoded.len != length or decoded.rip_relative) continue;
        // The loop counter, the stack and the data pointer are the harness's.
        const reserved = [_]u8{ 3, 4, 15 };
        var touches_reserved = false;
        for (reserved) |number| {
            if (@intFromEnum(decoded.dst_reg) == number or @intFromEnum(decoded.src_reg) == number) touches_reserved = true;
            if (!decoded.is_reg_form and decoded.sib_has_index and @intFromEnum(decoded.sib_index_reg) == number) touches_reserved = true;
            if (!decoded.is_reg_form and decoded.sib_has_base and @intFromEnum(decoded.sib_base_reg) == number and number != 3) touches_reserved = true;
        }
        if (touches_reserved) continue;
        var config: DifferentialConfig = .{ .seed_all_vectors = true };
        if (!decoded.is_reg_form) {
            if (decoded.sib_has_base) config.base_registers |= @as(u16, 1) << @intCast(@intFromEnum(decoded.sib_base_reg));
            if (decoded.sib_has_index) {
                const bit = @as(u16, 1) << @intCast(@intFromEnum(decoded.sib_index_reg));
                if (config.base_registers & bit != 0) continue;
                config.index_registers |= bit;
            }
            if (!decoded.sib_has_base and !decoded.sib_has_index) continue;
            const displacement: i64 = @bitCast(decoded.addr);
            if (displacement < -0x700 or displacement > 0x700) continue;
        }
        // The shape lists operands source first, destination last.
        const last_comma = std.mem.lastIndexOfScalar(u8, shape, ',');
        const last_operand = if (last_comma) |at| shape[at + 1 ..] else shape;
        const vector_destination = std.mem.startsWith(u8, last_operand, "xmm") or std.mem.startsWith(u8, last_operand, "ymm");
        const destination: ?u8 = if (vector_destination) decoded.xmm_dst else null;
        var program: [24]u8 = undefined;
        @memcpy(program[0..length], bytes[0..length]);
        program[length..][0..3].* = .{ 0x49, 0xFF, 0xCF };
        program[length + 3] = 0x75;
        program[length + 4] = @bitCast(@as(i8, -@as(i8, @intCast(length + 5))));
        program[length + 5] = 0xF4;
        var results: [2]DifferentialOutcome = undefined;
        var complete = true;
        for ([_]bool{ false, true }, 0..) |translate, run| {
            results[run] = runDifferentialProgramConfigured(program[0 .. length + 6], 0x5EED_C000 + checked, translate, config);
            const outcome = &results[run];
            if (!outcome.terminated or outcome.faulted) {
                complete = false;
                continue;
            }
            for (0..16) |register| {
                if (destination != null and destination.? == register) continue;
                const low_changed = !std.mem.eql(u8, &outcome.xmm[register], &outcome.initial_xmm[register]);
                const high_changed = !std.mem.eql(u8, &outcome.ymm_hi[register], &outcome.initial_ymm_hi[register]);
                if (low_changed or high_changed) {
                    if (failures < 40) std.debug.print("image executor roles: {s} [{s}] ({s}) changed xmm{d}{s}, not only its destination\n", .{ shape, hex, if (translate) "translated" else "interpreted", register, if (low_changed) "" else " (upper half)" });
                    failures += 1;
                }
            }
        }
        if (!complete) continue;
        for (0..16) |register| {
            const same = std.mem.eql(u8, &results[0].xmm[register], &results[1].xmm[register]) and
                std.mem.eql(u8, &results[0].ymm_hi[register], &results[1].ymm_hi[register]);
            if (!same) {
                if (failures < 40) std.debug.print("image executor roles: {s} [{s}] leaves xmm{d} different interpreted and translated: interpreted {x}/{x} translated {x}/{x}\n", .{ shape, hex, register, results[0].xmm[register], results[0].ymm_hi[register], results[1].xmm[register], results[1].ymm_hi[register] });
                failures += 1;
            }
        }
        if (!std.mem.eql(u8, &results[0].data, &results[1].data)) {
            if (failures < 40) std.debug.print("image executor roles: {s} [{s}] leaves different memory interpreted and translated\n", .{ shape, hex });
            failures += 1;
        }
        checked += 1;
    }
    std.debug.print("image executor roles: checked {d} SSE and AVX forms, {d} failures\n", .{ checked, failures });
    try testing.expect(checked > 100);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "VTEST sign executor roles: every integer form in xenia_canary.exe leaves the same registers and memory interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Thousands of programs: `zig build render-cpu-check` sets this.
    if (std.c.getenv("ROSETTE_EXECUTOR_SWEEP") == null) return error.SkipZigTest;
    // Xenia's JIT compiler, register allocator and command processor are
    // ordinary integer code in the emulator's image. A form the translator
    // runs differently from the interpreter changes what they compute -
    // and through them the code Xenia generates for the title. Flags are
    // left to the flag tests: many forms leave some architecturally
    // undefined.
    const corpus = @embedFile("../../xenia_image_corpus.txt");
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        const shape = fields.next() orelse continue;
        if (std.mem.indexOf(u8, shape, "xmm") != null or std.mem.indexOf(u8, shape, "ymm") != null or std.mem.indexOf(u8, shape, "mm") != null) continue;
        const skipped_prefixes = [_][]const u8{ "j", "call", "ret", "loop", "int", "sys", "ud", "hlt", "push", "pop", "enter", "leave", "movs", "stos", "lods", "scas", "cmps", "rep", "ins", "outs", "rdtsc", "cpuid", "rdrand", "rdseed", "xgetbv", "rdpid", "div", "idiv", "xchg", "cmpxchg", "lock", "xadd", "bound", "f", "xsave", "xrstor", "pause", "nop", "wait", "lfence", "mfence", "sfence", "prefetch", "clflush", "bsf", "bsr", "cld", "std", "cli", "sti", "lahf", "sahf", "inb", "inw", "inl", "outb", "outw", "outl", "lgdt", "lidt", "mov %cr", "rdmsr", "wrmsr", "rdpmc", "xlat", "aaa", "das", "daa", "aas", "into", "ldmxcsr", "stmxcsr", "emms", "endbr" };
        const skipped_operands = [_][]const u8{ "m[rip", "cs:", "fs:", "gs:", "es:", "ss:", "ds:", "st(" };
        var skip = false;
        for (skipped_prefixes) |name| {
            if (std.mem.startsWith(u8, shape, name)) skip = true;
        }
        for (skipped_operands) |name| {
            if (std.mem.indexOf(u8, shape, name) != null) skip = true;
        }
        if (skip) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        // EVEX (AVX-512) encodings are vector forms whose shapes name a
        // mask, not an xmm register; the SSE and AVX sweeps own vectors.
        if (length == 0 or bytes[0] == 0x62 or std.mem.indexOf(u8, shape, "{k") != null) continue;
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.op == .nop or decoded.len != length or decoded.rip_relative) continue;
        const reserved = [_]u8{ 3, 4, 15 };
        var touches_reserved = false;
        for (reserved) |number| {
            if (@intFromEnum(decoded.dst_reg) == number or @intFromEnum(decoded.src_reg) == number) touches_reserved = true;
            if (!decoded.is_reg_form and decoded.sib_has_index and @intFromEnum(decoded.sib_index_reg) == number) touches_reserved = true;
            if (!decoded.is_reg_form and decoded.sib_has_base and @intFromEnum(decoded.sib_base_reg) == number and number != 3) touches_reserved = true;
        }
        if (touches_reserved) continue;
        var config: DifferentialConfig = .{ .seed_all_vectors = true };
        if (!decoded.is_reg_form) {
            if (decoded.sib_has_base) config.base_registers |= @as(u16, 1) << @intCast(@intFromEnum(decoded.sib_base_reg));
            if (decoded.sib_has_index) {
                const bit = @as(u16, 1) << @intCast(@intFromEnum(decoded.sib_index_reg));
                if (config.base_registers & bit != 0) continue;
                config.index_registers |= bit;
            }
            if (!decoded.sib_has_base and !decoded.sib_has_index) continue;
            const displacement: i64 = @bitCast(decoded.addr);
            if (displacement < -0x700 or displacement > 0x700) continue;
            // A form that rewrites its own base or index would address
            // somewhere new on the next pass.
            const writes = @as(u16, 1) << @intCast(@intFromEnum(decoded.dst_reg));
            if ((config.base_registers | config.index_registers) & writes != 0) continue;
        }
        var program: [24]u8 = undefined;
        @memcpy(program[0..length], bytes[0..length]);
        program[length..][0..3].* = .{ 0x49, 0xFF, 0xCF };
        program[length + 3] = 0x75;
        program[length + 4] = @bitCast(@as(i8, -@as(i8, @intCast(length + 5))));
        program[length + 5] = 0xF4;
        var results: [2]DifferentialOutcome = undefined;
        var complete = true;
        for ([_]bool{ false, true }, 0..) |translate, run| {
            results[run] = runDifferentialProgramConfigured(program[0 .. length + 6], 0x5EED_E000 + checked, translate, config);
            if (!results[run].terminated or results[run].faulted) complete = false;
        }
        if (!complete) continue;
        var same = std.mem.eql(u8, &results[0].data, &results[1].data);
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
            if (@field(results[0].regs, name) != @field(results[1].regs, name)) {
                if (failures < 40) std.debug.print("integer executor roles: {s} [{s}] leaves {s} different: interpreted 0x{x} translated 0x{x}\n", .{ shape, hex, name, @field(results[0].regs, name), @field(results[1].regs, name) });
                same = false;
            }
        }
        for (0..16) |register| {
            if (!std.mem.eql(u8, &results[1].xmm[register], &results[1].initial_xmm[register]) or !std.mem.eql(u8, &results[0].xmm[register], &results[0].initial_xmm[register])) {
                if (failures < 40) std.debug.print("integer executor roles: {s} [{s}] changed xmm{d}\n", .{ shape, hex, register });
                same = false;
            }
        }
        if (!same) {
            if (failures < 40 and !std.mem.eql(u8, &results[0].data, &results[1].data)) std.debug.print("integer executor roles: {s} [{s}] leaves different memory\n", .{ shape, hex });
            failures += 1;
        }
        checked += 1;
    }
    std.debug.print("integer executor roles: checked {d} integer forms, {d} failures\n", .{ checked, failures });
    try testing.expect(checked > 500);
    try testing.expectEqual(@as(usize, 0), failures);
}

test "VTEST sign hoisted vector and scalar accesses through one base agree interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Xenia's generated code reaches its PowerPC context through [rsi+disp]
    // with a mix of 4-, 8- and 16-byte loads and stores, so the translator
    // hoists one translated base for the whole block. A single-instruction
    // sweep never forms a hoist; these blocks do, with xmm0-xmm15, scalar
    // and vector accesses interleaved at overlapping offsets.
    var prng = std.Random.DefaultPrng.init(0x4015_7001);
    const random = prng.random();
    var translated_total: u64 = 0;
    for (0..96) |trial| {
        var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
        defer asm_.deinit();
        const body_start = asm_.bytes.items.len;
        const count = 12 + random.uintLessThan(usize, 24);
        for (0..count) |_| {
            const x = random.uintLessThan(u8, 16);
            const not_r: u8 = if (x >= 8) 0x00 else 0x80;
            const modrm: u8 = 0x80 | ((x & 7) << 3) | 3; // [rbx + disp32]
            const disp: u32 = random.uintLessThan(u32, 0x1F0 / 4 + 1) * 4;
            switch (random.uintLessThan(u8, 11)) {
                0 => asm_.put(&.{ 0xC5, not_r | 0x78, 0x10, modrm }), // vmovups xmm, m128
                1 => asm_.put(&.{ 0xC5, not_r | 0x78, 0x11, modrm }), // vmovups m128, xmm
                2 => asm_.put(&.{ 0xC5, not_r | 0x7A, 0x10, modrm }), // vmovss xmm, m32
                3 => asm_.put(&.{ 0xC5, not_r | 0x7A, 0x11, modrm }), // vmovss m32, xmm
                4 => asm_.put(&.{ 0xC5, not_r | 0x7B, 0x10, modrm }), // vmovsd xmm, m64
                5 => asm_.put(&.{ 0xC5, not_r | 0x7B, 0x11, modrm }), // vmovsd m64, xmm
                6 => {
                    const r = ([_]u8{ 0, 1, 2, 6, 7 })[random.uintLessThan(usize, 5)];
                    asm_.put(&.{ if (random.boolean()) 0x8B else 0x89, 0x80 | (r << 3) | 3 });
                },
                7 => {
                    asm_.put(&.{ 0xC5, not_r | 0x79, 0x6E, 0xC0 | ((x & 7) << 3) }); // vmovd xmm, eax
                    continue;
                },
                8 => {
                    const a = random.uintLessThan(u8, 16);
                    const b = random.uintLessThan(u8, 8);
                    asm_.put(&.{ 0xC5, not_r | ((~a & 0x0F) << 3), 0x59, 0xC0 | ((x & 7) << 3) | b }); // vmulps
                    continue;
                },
                9 => {
                    asm_.put(&.{ 0xC5, not_r | 0x78, 0x28, modrm }); // vmovaps xmm, m128
                    asm_.imm32(disp & ~@as(u32, 15));
                    continue;
                },
                else => {
                    asm_.put(&.{ 0xC5, not_r | 0x78, 0x29, modrm }); // vmovaps m128, xmm
                    asm_.imm32(disp & ~@as(u32, 15));
                    continue;
                },
            }
            asm_.imm32(disp);
        }
        asm_.incDec(1, 15); // dec r15
        asm_.jnzBack(body_start);
        asm_.hlt();
        const seed = 0x4015_0000 + trial;
        const interpreted = runDifferentialProgramConfigured(asm_.bytes.items, seed, false, .{ .seed_all_vectors = true });
        const translated = runDifferentialProgramConfigured(asm_.bytes.items, seed, true, .{ .seed_all_vectors = true });
        try std.testing.expect(interpreted.terminated and translated.terminated);
        try std.testing.expect(!interpreted.faulted and !translated.faulted);
        translated_total += translated.translated_instructions;
        var same = std.mem.eql(u8, &interpreted.data, &translated.data);
        for (0..16) |register| {
            if (!std.mem.eql(u8, &interpreted.xmm[register], &translated.xmm[register]) or
                !std.mem.eql(u8, &interpreted.ymm_hi[register], &translated.ymm_hi[register]))
            {
                std.debug.print("hoisted accesses trial {d}: xmm{d} interpreted {x}/{x} translated {x}/{x}\n", .{ trial, register, interpreted.xmm[register], interpreted.ymm_hi[register], translated.xmm[register], translated.ymm_hi[register] });
                same = false;
            }
        }
        inline for (.{ "rax", "rcx", "rdx", "rsi", "rdi" }) |name| {
            if (@field(interpreted.regs, name) != @field(translated.regs, name)) {
                std.debug.print("hoisted accesses trial {d}: {s} interpreted 0x{x} translated 0x{x}\n", .{ trial, name, @field(interpreted.regs, name), @field(translated.regs, name) });
                same = false;
            }
        }
        if (!same) {
            std.debug.print("hoisted accesses trial {d} program {any}\n", .{ trial, asm_.bytes.items });
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expect(translated_total > 10_000);
}

test "VTEST sign memory operands: every form Xenia's JIT emits keeps its exact base, index, scale and displacement" {
    // The shape check (`m[b+,i,d8]`) only says a register exists. The JIT
    // corpus names them, so compare the decoded base and index register
    // numbers, the scale and the displacement with the AT&T text. r12 and r13
    // as base or index, rsp and rbp, and the no-index encoding are the
    // classic places a decoder goes wrong, and Xenia's generated code lives in
    // r12 and r13.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    const names = [_][]const u8{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" };
    const regNumber = struct {
        fn of(text: []const u8, table: []const []const u8) ?u8 {
            for (table, 0..) |name, number| {
                if (std.mem.eql(u8, text, name)) return @intCast(number);
            }
            return null;
        }
    }.of;
    var checked: usize = 0;
    var failures: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const text = fields.next() orelse continue;
        const open = std.mem.indexOfScalar(u8, text, '(') orelse continue;
        const close = std.mem.indexOfScalarPos(u8, text, open, ')') orelse continue;
        if (std.mem.indexOf(u8, text, "%es:") != null or std.mem.indexOf(u8, text, "%ds:") != null or
            std.mem.indexOf(u8, text, "%fs:") != null or std.mem.indexOf(u8, text, "%gs:") != null) continue;
        if (std.mem.startsWith(u8, text, "rep") or std.mem.startsWith(u8, text, "movs") or std.mem.startsWith(u8, text, "stos") or
            std.mem.startsWith(u8, text, "lods") or std.mem.startsWith(u8, text, "scas") or std.mem.startsWith(u8, text, "cmps")) continue;
        // Displacement: the text before '(' after the last operand separator.
        var start = open;
        while (start > 0 and text[start - 1] != ' ') start -= 1;
        const displacement_text = text[start..open];
        var inside = std.mem.splitScalar(u8, text[open + 1 .. close], ',');
        const base_text = inside.next() orelse "";
        const index_text = inside.next() orelse "";
        const scale_text = inside.next() orelse "";
        if (std.mem.startsWith(u8, base_text, "%e") or std.mem.startsWith(u8, index_text, "%e")) continue;
        var bytes: [15]u8 = undefined;
        var length: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (length == bytes.len) break;
            bytes[length] = try std.fmt.parseInt(u8, token, 16);
            length += 1;
        }
        const decoded = decodeInsn(bytes[0..length]);
        if (decoded.op == .invalid or decoded.op == .nop or decoded.is_reg_form) continue;
        checked += 1;
        var ok = true;
        if (std.mem.eql(u8, base_text, "%rip")) {
            ok = decoded.rip_relative;
        } else {
            const has_base = base_text.len > 1;
            const has_index = index_text.len > 1;
            ok = !decoded.rip_relative and decoded.sib_has_base == has_base and decoded.sib_has_index == has_index;
            if (ok and has_base) ok = regNumber(base_text[1..], &names) == @as(?u8, @intCast(@intFromEnum(decoded.sib_base_reg)));
            if (ok and has_index) {
                ok = regNumber(index_text[1..], &names) == @as(?u8, @intCast(@intFromEnum(decoded.sib_index_reg)));
                const scale: u8 = if (scale_text.len == 0) 1 else std.fmt.parseInt(u8, scale_text, 10) catch 0;
                ok = ok and (@as(u8, 1) << decoded.sib_scale) == scale;
            }
            const expected: i64 = blk: {
                if (displacement_text.len == 0) break :blk 0;
                const negative = displacement_text[0] == '-';
                const digits = if (negative) displacement_text[1..] else displacement_text;
                const magnitude = if (std.mem.startsWith(u8, digits, "0x")) std.fmt.parseInt(i64, digits[2..], 16) catch 0 else std.fmt.parseInt(i64, digits, 10) catch 0;
                break :blk if (negative) -magnitude else magnitude;
            };
            if (ok) ok = @as(i64, @bitCast(decoded.addr)) == expected;
        }
        if (!ok) {
            if (failures < 40) std.debug.print("memory operand differs: {s} -> {s} base={} r{d} idx={} r{d} scale={d} addr=0x{x} rip={}\n", .{ text, @tagName(decoded.op), decoded.sib_has_base, @intFromEnum(decoded.sib_base_reg), decoded.sib_has_index, @intFromEnum(decoded.sib_index_reg), @as(u8, 1) << decoded.sib_scale, decoded.addr, decoded.rip_relative });
            failures += 1;
        }
    }
    std.debug.print("memory operands: checked {d} forms with a ModR/M memory operand, {d} differ\n", .{ checked, failures });
    try testing.expect(checked > 100);
}

test "byte and word forms name AH..DH and keep their width, interpreted and translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // Every form here decoded as something else that is also valid: FE as a
    // 32-bit INC/DEC (so `incb %ah` was `inc %esp`), F6/84/D0/C0 with AH..BH
    // read as SPL..DIL (libstdc++'s `testb $8, %ah` in _S_format_float),
    // 66 0F AF as a 32-bit IMUL, and `lock incq` as a 32-bit atomic. The
    // expected values are worked out from the x86 definitions, not taken
    // from either executor.
    const body = [_]u8{
        0x48, 0xB8, 0x66, 0x55, 0x44, 0x33, 0x22, 0x22, 0x11, 0x11, // mov rax, 0x1111222233445566 (AH 0x55)
        0x48, 0xB9, 0x01, 0x7F, 0x44, 0x44, 0x33, 0x33, 0x22, 0x22, // mov rcx, 0x2222333344447f01 (CH 0x7f)
        0x48, 0xBA, 0x10, 0xFF, 0x55, 0x55, 0x44, 0x44, 0x33, 0x33, // mov rdx, 0x333344445555ff10 (DH 0xff)
        0x48, 0xBE, 0xEE, 0xDD, 0xCC, 0xCC, 0xBB, 0xBB, 0xAA, 0xAA, // mov rsi, sentinel
        0x48, 0xBF, 0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12, // mov rdi, sentinel
        0x48, 0xBD, 0x0D, 0xF0, 0xAD, 0x0B, 0x0D, 0xF0, 0xAD, 0x0B, // mov rbp, sentinel
        0xC7, 0x43, 0x20, 0xFF, 0xFF, 0xFF, 0xFF, // mov dword [rbx+0x20], 0xffffffff
        0xC7, 0x43, 0x24, 0x00, 0x00, 0x00, 0x00, // mov dword [rbx+0x24], 0
        0xC7, 0x43, 0x28, 0xFF, 0x00, 0x00, 0x00, // mov dword [rbx+0x28], 0xff
        0xFE, 0xC4, // inc ah             -> 0x56
        0xFE, 0xCD, // dec ch             -> 0x7e
        0xFE, 0xC6, // inc dh             -> 0x00, ZF
        0x0F, 0x94, 0x43, 0x10, // sete [rbx+0x10]   -> 1
        0xF6, 0xD4, // not ah             -> 0xa9
        0xF6, 0xDD, // neg ch             -> 0x82
        0xD0, 0xE5, // shl ch, 1          -> 0x04
        0xC0, 0xEC, 0x02, // shr ah, 2    -> 0x2a
        0xD0, 0xC5, // rol ch, 1          -> 0x08
        0xF6, 0xC4, 0x08, // test ah, 8   -> nonzero
        0x0F, 0x95, 0x43, 0x11, // setne [rbx+0x11]  -> 1
        0x84, 0xE5, // test ch, ah        -> nonzero
        0x0F, 0x95, 0x43, 0x12, // setne [rbx+0x12]  -> 1
        0xF6, 0xE5, // mul ch             -> ax = 0x66 * 0x08 = 0x0330
        0x66, 0x0F, 0xAF, 0xD1, // imul dx, cx       -> dx = 0x0010 * 0x0801 = 0x8010
        0xF0, 0x48, 0xFF, 0x43, 0x20, // lock inc qword [rbx+0x20] -> 0x1_0000_0000
        0xFE, 0x43, 0x28, // inc byte [rbx+0x28] -> 0x00, ZF, nothing carried
        0x0F, 0x94, 0x43, 0x13, // sete [rbx+0x13]   -> 1
        0x49, 0xFF, 0xCF, // dec r15
    };
    const back: i32 = -@as(i32, body.len + 6);
    const program = body ++ [_]u8{ 0x0F, 0x85 } ++ @as([4]u8, @bitCast(back)) ++ [_]u8{0xF4}; // jnz top ; hlt
    for ([_]bool{ false, true }) |translate| {
        const outcome = runDifferentialProgram(&program, 0xB17E_0A11, translate);
        const how = if (translate) "translated" else "interpreted";
        try std.testing.expect(outcome.terminated and !outcome.faulted);
        if (translate) try std.testing.expect(outcome.translated_instructions > 100);
        const expected_regs = [_]struct { name: []const u8, got: u64, want: u64 }{
            .{ .name = "rax", .got = outcome.regs.rax, .want = 0x1111_2222_3344_0330 },
            .{ .name = "rcx", .got = outcome.regs.rcx, .want = 0x2222_3333_4444_0801 },
            .{ .name = "rdx", .got = outcome.regs.rdx, .want = 0x3333_4444_5555_8010 },
            .{ .name = "rsi", .got = outcome.regs.rsi, .want = 0xAAAA_BBBB_CCCC_DDEE },
            .{ .name = "rdi", .got = outcome.regs.rdi, .want = 0x1234_5678_9ABC_DEF0 },
            .{ .name = "rbp", .got = outcome.regs.rbp, .want = 0x0BAD_F00D_0BAD_F00D },
            .{ .name = "rsp", .got = outcome.regs.rsp, .want = MEM_BASE + 0x40000 },
        };
        for (expected_regs) |entry| {
            if (entry.got != entry.want) {
                std.debug.print("byte/word forms ({s}): {s}=0x{x}, expected 0x{x}\n", .{ how, entry.name, entry.got, entry.want });
                return error.TestUnexpectedResult;
            }
        }
        const data = &outcome.data;
        try std.testing.expectEqualSlices(u8, &.{ 1, 1, 1, 1 }, data[0x10..0x14]);
        try std.testing.expectEqual(@as(u64, 0x1_0000_0000), std.mem.readInt(u64, data[0x20..0x28], .little));
        try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, data[0x28..0x2C], .little));
    }
}

test "Halo 3's menu spin-wait retires the same state translated as interpreted" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // The MMIO guard is `cmp edx, esi; jae`: the context's low half must
    // lie above the stack slot the loop counts in.
    try std.testing.expect(@as(u32, @truncate(MEM_BASE + 0x30000)) > 0x150);
    const interpreted = runXeniaSpinProgram(false);
    const translated = runXeniaSpinProgram(true);
    try std.testing.expect(interpreted.terminated and translated.terminated);
    inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rsi", "rdi", "r10", "r15", "rip" }) |name| {
        if (@field(interpreted.regs, name) != @field(translated.regs, name)) {
            std.debug.print("spin: {s} differs interpreter=0x{x} translated=0x{x}\n", .{ name, @field(interpreted.regs, name), @field(translated.regs, name) });
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(interpreted.regs.rflags, translated.regs.rflags);
    try std.testing.expectEqualSlices(u8, &interpreted.ctx, &translated.ctx);
    try std.testing.expectEqualSlices(u8, &interpreted.data, &translated.data);
    if (interpreted.regs.r15 != 0) std.debug.print("spin: stopped rip=0x{x} (offset 0x{x}) r15={d} rdx=0x{x} rsi=0x{x}\n", .{ interpreted.regs.rip, interpreted.regs.rip -% (MEM_BASE + 0x1000), interpreted.regs.r15, interpreted.regs.rdx, interpreted.regs.rsi });
    try std.testing.expectEqual(@as(u64, 0), interpreted.regs.r15);
    try std.testing.expect(translated.translated > 1000);
}

test "translated blocks retire the same vector state as the interpreter over random AVX programs" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0xA5_5E_D0);
    const random = prng.random();
    var total_translated: u64 = 0;
    for (0..64) |trial| {
        var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
        defer asm_.deinit();
        const body_start = asm_.bytes.items.len;
        buildVectorBody(&asm_, random, 6 + random.uintLessThan(usize, 10));
        // A little integer work keeps the flags and general registers moving.
        buildDifferentialBody(&asm_, random, 1 + random.uintLessThan(usize, 3), null);
        if (random.uintLessThan(u8, 4) == 0) asm_.vzeroupper();
        asm_.incDec(1, 15); // dec r15
        asm_.jnzBack(body_start);
        asm_.hlt();
        const seed = 0x5000 + trial;
        const interpreted = runDifferentialProgram(asm_.bytes.items, seed, false);
        const translated = runDifferentialProgram(asm_.bytes.items, seed, true);
        if (!interpreted.terminated or interpreted.faulted) {
            std.debug.print("trial {d}: the interpreter did not finish the program (faulted={}) program={any}\n", .{ trial, interpreted.faulted, asm_.bytes.items });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(translated.terminated);
        try std.testing.expectEqual(interpreted.exit_code, translated.exit_code);
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip" }) |name| {
            if (@field(interpreted.regs, name) != @field(translated.regs, name)) {
                std.debug.print("vector trial {d}: {s} differs interpreter=0x{x} translated=0x{x} program={any}\n", .{ trial, name, @field(interpreted.regs, name), @field(translated.regs, name), asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        try std.testing.expectEqual(interpreted.regs.rflags, translated.regs.rflags);
        for (0..16) |register| {
            if (!std.mem.eql(u8, &interpreted.xmm[register], &translated.xmm[register]) or
                !std.mem.eql(u8, &interpreted.ymm_hi[register], &translated.ymm_hi[register]) or
                !std.mem.eql(u8, &interpreted.zmm_hi[register], &translated.zmm_hi[register]))
            {
                std.debug.print("vector trial {d}: xmm{d} differs\n  interpreter xmm={any} hi={any}\n  translated  xmm={any} hi={any}\n  program={any}\n", .{ trial, register, interpreted.xmm[register], interpreted.ymm_hi[register], translated.xmm[register], translated.ymm_hi[register], asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        try std.testing.expectEqualSlices(u8, &interpreted.data, &translated.data);
        try std.testing.expectEqual(@as(u64, 0), translated.mismatches);
        total_translated += translated.translated_instructions;
    }
    try std.testing.expect(total_translated > 1000);
}

/// Xenia's hot forms from the 2026-09-21 fallback census, locked
/// read-modify-writes at every width, and a data base that moves between
/// memory accesses - the shapes a hoisted base pointer and the newest
/// templates are exposed to.
fn buildHotFormBody(asm_: *DifferentialAssembler, random: std.Random, count: usize) void {
    const gprs = [_]u8{ 0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 13, 14 };
    var emitted: usize = 0;
    while (emitted < count) : (emitted += 1) {
        const dst = random.uintLessThan(u8, 8);
        const src1 = random.uintLessThan(u8, 8);
        const src2 = random.uintLessThan(u8, 8);
        const gpr = gprs[random.uintLessThan(usize, gprs.len)];
        const disp: i32 = @intCast(random.uintLessThan(u32, 0xF0) * 16);
        const imm = random.int(u8);
        switch (random.uintLessThan(u8, 20)) {
            18 => {
                // XObject::Retain/Release: `lock inc|dec dword [rbx+d]`,
                // then the branch and setcc that read its ZF.
                asm_.put(&.{ 0xF0, 0xFF });
                asm_.memOperand(random.uintLessThan(u8, 2), 3, disp);
                asm_.setcc(4, gpr); // sete
                asm_.jccOver(5, 3); // jne over one register add
                asm_.aluRegReg(0x01, gpr, gpr);
            },
            19 => {
                // `lock add|sub qword [rbx+d], imm8` and a dependent jcc.
                asm_.put(&.{ 0xF0, 0x48, 0x83 });
                asm_.memOperand(if (random.boolean()) 0 else 5, 3, disp);
                asm_.put(&.{@bitCast(random.int(i8))});
                asm_.jccOver(random.uintLessThan(u8, 16), 3);
                asm_.aluRegReg(0x01, gpr, gpr);
            },
            0 => asm_.vexRR(1, 1, false, 0xF4, dst, src1, src2), // vpmuludq
            1 => asm_.vexRM(1, 1, false, 0xF4, dst, src1, disp),
            2 => asm_.vexRRI(3, 1, false, 0x0E, dst, src1, src2, imm), // vpblendw
            3 => asm_.vexRMI(3, 1, false, 0x0E, dst, src1, disp, imm),
            4 => asm_.vexRRI(1, 1, false, 0xC6, dst, src1, src2, imm), // vshufpd
            5 => asm_.vexRMI(1, 1, false, 0xC6, dst, src1, disp, imm),
            6 => asm_.vexRRI(3, 1, false, 0x21, dst, src1, src2, imm), // vinsertps
            7 => asm_.vexRMI(3, 1, false, 0x21, dst, src1, disp, imm),
            8 => asm_.vex256(1, 0, 0x5A, dst, 0, src2, 0), // vcvtps2pd ymm, xmm
            9 => asm_.vex256(1, 0, 0x5A, dst, 0, null, disp), // vcvtps2pd ymm, [m]
            10 => asm_.vex256(1, 0, 0x11, src1, 0, null, disp), // vmovups [m], ymm
            11 => asm_.vex256(1, 0, 0x10, dst, 0, null, disp), // vmovups ymm, [m]
            12 => asm_.vmxcsr(random.boolean(), disp),
            13 => {
                // winpthreads' mutex and its lazy event: xchg the state word,
                // cmpxchg the event pointer, and a branch on the ZF it left.
                asm_.lockedMemReg(random.uintLessThan(u8, 3), ([_]u8{ 16, 32, 64 })[random.uintLessThan(usize, 3)], gpr, disp);
                asm_.setcc(4, gprs[random.uintLessThan(usize, gprs.len)]); // sete
            },
            14 => {
                // The base moves, is used, and moves back.
                const amount: i8 = @intCast(16 * (1 + random.uintLessThan(u8, 4)));
                asm_.moveBase(false, amount);
                asm_.store(gpr, 3, disp);
                asm_.load(gprs[random.uintLessThan(usize, gprs.len)], 3, disp +% 8);
                asm_.moveBase(true, amount);
            },
            15 => asm_.load(gpr, 3, disp),
            16 => asm_.store(gpr, 3, disp),
            else => {
                asm_.push(3);
                asm_.load(gpr, 3, disp);
                asm_.pop(3);
            },
        }
    }
}

test "translated blocks retire the same state as the interpreter over Xenia's hot forms, moving bases and locked RMW" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var prng = std.Random.DefaultPrng.init(0x4A11_0F0E);
    const random = prng.random();
    var total_translated: u64 = 0;
    for (0..96) |trial| {
        var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
        defer asm_.deinit();
        const body_start = asm_.bytes.items.len;
        buildHotFormBody(&asm_, random, 6 + random.uintLessThan(usize, 12));
        buildDifferentialBody(&asm_, random, 1 + random.uintLessThan(usize, 3), null);
        asm_.incDec(1, 15); // dec r15
        asm_.jnzBack(body_start);
        asm_.hlt();
        const seed = 0x9000 + trial;
        const interpreted = runDifferentialProgram(asm_.bytes.items, seed, false);
        const translated = runDifferentialProgram(asm_.bytes.items, seed, true);
        if (!interpreted.terminated or interpreted.faulted) {
            std.debug.print("hot-form trial {d}: the interpreter did not finish the program (faulted={}) program={any}\n", .{ trial, interpreted.faulted, asm_.bytes.items });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(translated.terminated);
        inline for (.{ "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip", "rflags", "mxcsr" }) |name| {
            if (@field(interpreted.regs, name) != @field(translated.regs, name)) {
                std.debug.print("hot-form trial {d}: {s} differs interpreter=0x{x} translated=0x{x} program={any}\n", .{ trial, name, @field(interpreted.regs, name), @field(translated.regs, name), asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        for (0..16) |register| {
            if (!std.mem.eql(u8, &interpreted.xmm[register], &translated.xmm[register]) or
                !std.mem.eql(u8, &interpreted.ymm_hi[register], &translated.ymm_hi[register]))
            {
                std.debug.print("hot-form trial {d}: xmm{d} differs\n  interpreter xmm={any} hi={any}\n  translated  xmm={any} hi={any}\n  program={any}\n", .{ trial, register, interpreted.xmm[register], interpreted.ymm_hi[register], translated.xmm[register], translated.ymm_hi[register], asm_.bytes.items });
                return error.TestUnexpectedResult;
            }
        }
        if (!std.mem.eql(u8, &interpreted.data, &translated.data)) {
            const first = std.mem.indexOfDiff(u8, &interpreted.data, &translated.data).?;
            std.debug.print("hot-form trial {d}: data differs first at +0x{x} interpreter={any} translated={any} program={any}\n", .{ trial, first, interpreted.data[first..@min(first + 16, 0x1000)], translated.data[first..@min(first + 16, 0x1000)], asm_.bytes.items });
            return error.TestUnexpectedResult;
        }
        try std.testing.expectEqual(@as(u64, 0), translated.mismatches);
        total_translated += translated.translated_instructions;
    }
    try std.testing.expect(total_translated > 1000);
}

test "a translated block is dropped when its bytes change and recompiled from the new bytes" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
    defer asm_.deinit();
    // loop: add rax, 1 ; dec r15 ; jnz loop ; hlt
    asm_.aluImm8(0, 0, 1);
    asm_.incDec(1, 15);
    asm_.jnzBack(0);
    asm_.hlt();
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    @memcpy(state.mem[0x1000..][0..asm_.bytes.items.len], asm_.bytes.items);
    state.regs.rip = MEM_BASE + 0x1000;
    state.regs.rsp = MEM_BASE + 0x40000;
    state.regs.r15 = 8;
    state.block_jit_hot_threshold = 2;
    state.runWithLimit(1000);
    try std.testing.expect(state.terminated);
    try std.testing.expectEqual(@as(u64, 8), state.regs.rax);
    const jit = state.block_jit.?;
    try std.testing.expect(jit.compiled >= 1);
    const compiled_before = jit.compiled;
    // Patch `add rax, 1` into `add rax, 2` in place and run the loop again.
    state.mem[0x1000 + 3] = 2;
    state.terminated = false;
    state.regs.rip = MEM_BASE + 0x1000;
    state.regs.rax = 0;
    state.regs.r15 = 8;
    state.runWithLimit(1000);
    try std.testing.expect(state.terminated);
    try std.testing.expectEqual(@as(u64, 16), state.regs.rax);
    try std.testing.expect(jit.invalidations >= 1);
    try std.testing.expect(jit.compiled > compiled_before);
    try std.testing.expectEqual(@as(u64, 0), jit.mismatches);
}

test "continuation validation ignores data and retired bytes but detects future bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const code = MEM_BASE + 0x1000;
    var bytes = [_]u8{ 0x90, 0x90, 0x90 };
    @memcpy(state.mem[0x1000..][0..bytes.len], &bytes);
    var insns: [3]block_jit.Insn = undefined;
    for (&insns, 0..) |*insn, index| insn.* = .{
        .rip = code + index,
        .len = 1,
        .decoded = decodeInsn(&.{0x90}),
        .segment = .ds,
    };
    const block = block_jit.Block{
        .helpers = undefined, // never executed: this tests only source admission
        .start_rip = code,
        .end_rip = code + bytes.len,
        .insns = &insns,
        .bytes = &bytes,
        .code = &.{},
        .native_count = 3,
        .fallback_count = 0,
        .register_only = true,
    };
    state.block_jit_scratch = .{ .block = &block, .index = 0 };
    state.write8(MEM_BASE + 0x8000, 0xcc);
    try testing.expect(!state.blockJitContinuationChanged());
    state.write8(code, 0xcc); // consumed instruction, not the continuation
    try testing.expect(!state.blockJitContinuationChanged());
    state.write8(code + 1, 0xcc);
    try testing.expect(state.blockJitContinuationChanged());
    state.block_jit_scratch.index = 2;
    try testing.expect(!state.blockJitContinuationChanged()); // no remaining instruction
}

test "translated stores stop before a rewritten continuation in native and fallback lanes" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    for ([_]bool{ false, true }) |vector_store| {
        var state = ElfState.initWithMemory(testing.allocator, 0x80000);
        defer state.deinit();
        const code = MEM_BASE + 0x1000;
        const prefix: []const u8 = if (vector_store)
            &.{ 0x48, 0x89, 0xdb, 0xc5, 0xfa, 0x7f, 0x03 } // mov rbx,rbx; vmovdqu xmm0,[rbx]
        else
            &.{ 0x48, 0x89, 0xdb, 0x89, 0x0b }; // mov rbx,rbx; mov ecx,[rbx]
        @memcpy(state.mem[0x1000..][0..prefix.len], prefix);
        const suffix = [_]u8{ 0x48, 0xc7, 0xc0, 1, 0, 0, 0, 0xf4, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90 };
        @memcpy(state.mem[0x1000 + prefix.len ..][0..suffix.len], &suffix);
        state.block_jit_hot_threshold = 2;
        for (1..9) |value| {
            state.terminated = false;
            state.regs.rip = code;
            state.regs.rsp = MEM_BASE + 0x40000;
            state.regs.rbx = code + prefix.len + (if (vector_store) @as(u64, 0) else 3);
            state.regs.rcx = value;
            state.xmm[0] = suffix;
            state.xmm[0][3] = @intCast(value);
            state.runWithLimit(1000);
            try testing.expect(state.terminated and !state.faulted);
            try testing.expectEqual(@as(u64, @intCast(value)), state.regs.rax);
        }
        try testing.expect(state.block_jit.?.instructions_retired > 0);
        try testing.expect(state.block_jit.?.aborts > 0);
        try testing.expect(state.block_jit.?.continuation_write_aborts > 0);
        try testing.expectEqual(@as(u64, 0), state.block_jit.?.mismatches);
    }
}

test "UI scissor packed AVX conversion and clamping retain a nonempty rectangle in both tiers" {
    // Isolated instruction fixture for the unsigned-extent conversion and
    // clipping sequence. No PE is loaded and no Xenia code is launched.
    const program = [_]u8{
        0x48, 0x89, 0xdb, // mov rbx, rbx: one native template among fallbacks
        0xc5, 0xfa, 0x7e, 0x40, 0x10, // vmovq [rax+16], xmm0
        0xc4, 0xe2, 0x79, 0x35, 0xc0, // vpmovzxdq xmm0, xmm0
        0xc5, 0xfb, 0x12, 0x0b, // vmovddup [rbx], xmm1
        0xc5, 0xf9, 0xeb, 0xc1, // vpor xmm0, xmm0, xmm1
        0xc5, 0xf9, 0x5c, 0xc1, // vsubpd xmm0, xmm0, xmm1
        0xc5, 0xf9, 0x5a, 0xc0, // vcvtpd2ps xmm0, xmm0
        0xc5, 0xfb, 0x10, 0x49, 0x18, // vmovsd [rcx+24], xmm1
        0xc5, 0xf8, 0x5e, 0xc9, // vdivps xmm1, xmm0, xmm1
        0xc5, 0xfb, 0x10, 0x52, 0x1c, // vmovsd [rdx+28], xmm2
        0xc5, 0xfb, 0x10, 0x5a, 0x24, // vmovsd [rdx+36], xmm3
        0xc5, 0xf0, 0x59, 0xd2, // vmulps xmm2, xmm1, xmm2
        0xc5, 0xd8, 0x57, 0xe4, // vxorps xmm4, xmm4, xmm4
        0xc5, 0xe8, 0x5f, 0xd4, // vmaxps xmm2, xmm2, xmm4
        0xc5, 0x68, 0x5d, 0xc0, // vminps xmm8, xmm2, xmm0
        0xc5, 0xf0, 0x59, 0xcb, // vmulps xmm1, xmm1, xmm3
        0xc4, 0xc1, 0x70, 0x5f, 0xc8, // vmaxps xmm1, xmm1, xmm8
        0xc5, 0xf0, 0xc2, 0xd0, 0x01, // vcmpltps xmm2, xmm1, xmm0
        0xc5, 0xe8, 0xc6, 0xd2, 0x50, // vshufps xmm2, xmm2, xmm2, 0x50
        0xc5, 0xf9, 0x50, 0xc2, // vmovmskpd eax, xmm2
        0xf4,
    };
    for ([_]bool{ false, true }) |translate| {
        if (translate and !block_jit.CodeMemory.available()) continue;
        var state = ElfState.initWithMemory(testing.allocator, 0x80000);
        defer state.deinit();
        @memcpy(state.mem[0x1000..][0..program.len], &program);
        const data = MEM_BASE + 0x20000;
        state.write64(data, 0x4330_0000_0000_0000); // double 2^52
        state.write32(data + 0x110, 1280);
        state.write32(data + 0x114, 720);
        state.write32(data + 0x218, @bitCast(@as(f32, 1280)));
        state.write32(data + 0x21c, @bitCast(@as(f32, 720)));
        state.write32(data + 0x31c, @bitCast(@as(f32, 10)));
        state.write32(data + 0x320, @bitCast(@as(f32, 20)));
        state.write32(data + 0x324, @bitCast(@as(f32, 640)));
        state.write32(data + 0x328, @bitCast(@as(f32, 480)));
        state.block_jit_enabled = translate;
        state.block_jit_hot_threshold = 2;
        for (0..8) |_| {
            state.terminated = false;
            state.regs.rip = MEM_BASE + 0x1000;
            state.regs.rax = data + 0x100;
            state.regs.rbx = data;
            state.regs.rcx = data + 0x200;
            state.regs.rdx = data + 0x300;
            state.regs.rsp = MEM_BASE + 0x40000;
            state.runWithLimit(1000);
            try testing.expect(!state.faulted);
            try testing.expectEqual(@as(u64, 3), state.regs.rax);
            try testing.expectEqual(@as(f32, 10), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[8][0..4], .little))));
            try testing.expectEqual(@as(f32, 20), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[8][4..8], .little))));
            const scissor_x = @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[1][0..4], .little)));
            try testing.expectEqual(@as(f32, 640), scissor_x);
            try testing.expectEqual(@as(f32, 480), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[1][4..8], .little))));
        }
        if (translate) try testing.expect(state.block_jit.?.instructions_retired != 0);
    }
}

// Windows page-protection TLB regression fixtures.
const TlbProtectionOutcome = struct {
    rax: u64,
    violations: u64,
    fills: u64,
    admitted_before: bool,
    admitted_after_protect: bool,
    admitted_after_executable: bool,
};

/// Run a store loop twice, protecting its data page read-only in between.
fn runTlbProtectionProgram(translate: bool) TlbProtectionOutcome {
    var asm_ = DifferentialAssembler{ .allocator = std.testing.allocator };
    defer asm_.deinit();
    // loop: mov [rbx + 0x10], rax ; add rax, 1 ; dec r15 ; jnz loop ; hlt
    asm_.store(0, 3, 0x10);
    asm_.aluImm8(0, 0, 1);
    asm_.incDec(1, 15);
    asm_.jnzBack(0);
    asm_.hlt();
    var state = ElfState.initWithMemory(std.testing.allocator, 0x80000);
    defer state.deinit();
    const code = MEM_BASE + 0x1000;
    const data = MEM_BASE + 0x20000;
    @memcpy(state.mem[0x1000..][0..asm_.bytes.items.len], asm_.bytes.items);
    state.regs.rbx = data;
    state.regs.rsp = MEM_BASE + 0x40000;
    state.regs.rip = code;
    state.regs.r15 = 100;
    state.regs.rax = 0;
    state.block_jit_enabled = translate;
    state.block_jit_hot_threshold = 2;
    state.windows_runtime_enabled = true;
    state.runWithLimit(100_000);
    std.debug.assert(state.terminated);
    const admitted_before = state.ownerBlockJitTlb().lookup(true, data + 0x10) != null;
    // PAGE_READONLY on the data page: every later store faults. With no
    // vectored handler installed the access is performed and counted.
    state.noteGuestPageProtection(data, 0x1000, 0x02, "test", 0);
    const admitted_after_protect = state.ownerBlockJitTlb().lookup(true, data + 0x10) != null;
    state.terminated = false;
    state.regs.rip = code;
    state.regs.r15 = 100;
    state.runWithLimit(100_000);
    std.debug.assert(state.terminated);
    // Back to accessible, run once more so the page is admitted again,
    // then make it executable: the write side must be dropped.
    state.clearGuestPageProtection(data, 0x1000);
    state.terminated = false;
    state.regs.rip = code;
    state.regs.r15 = 4;
    state.runWithLimit(100_000);
    state.configureWindowsExecutableRanges(&.{.{ .guest_base = data, .length = 0x1000 }});
    const admitted_after_executable = state.ownerBlockJitTlb().lookup(true, data + 0x10) != null;
    return .{
        .rax = state.regs.rax,
        .violations = state.guest_access_violations_raised,
        .fills = if (state.block_jit) |jit| jit.tlb_fills else 0,
        .admitted_before = admitted_before,
        .admitted_after_protect = admitted_after_protect,
        .admitted_after_executable = admitted_after_executable,
    };
}

test "a store trace withholds only the write TLB, and only while it can still fire" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    if (state.blockJitActive() == null) return error.SkipZigTest;
    const page = MEM_BASE + 0x20000;

    // The Xenia run script exports ROSETTE_ELF_TRACE_WINDOWS_MEMORY=1, and
    // this guard used to refuse every page for the whole run because of it.
    // The mapped-write trace prints only stores above its floor that miss
    // the process image, so an image page keeps its write TLB even while
    // the trace can still fire.
    state.trace_windows_memory = true;
    try testing.expect(!state.traceWithholdsWriteTlb(page));
    try testing.expect(state.traceWithholdsWriteTlb(ElfState.windows_memory_trace_floor));
    state.blockJitTlbConsider(page, 4, false);
    state.blockJitTlbConsider(page, 4, true);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) != null);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) != null);

    // The trace spends a fixed budget in the first moments of a run; once it
    // is spent it observes nothing, so it withholds nothing.
    state.windows_memory_trace_events.store(ElfState.windows_memory_trace_budget, .monotonic);
    try testing.expect(!state.traceWithholdsWriteTlb(ElfState.windows_memory_trace_floor));

    // A watched store address has no budget and must see stores all run
    // long - on its own page. Its neighbours keep the write TLB.
    state.ownerBlockJitTlb().flush(true, true);
    state.trace_write_address = page + 0x10;
    try testing.expect(state.traceWithholdsWriteTlb(page));
    try testing.expect(!state.traceWithholdsWriteTlb(page + block_jit.Tlb.page_bytes));
    state.blockJitTlbConsider(page, 4, true);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) == null);
    state.blockJitTlbConsider(page, 4, false);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) != null);
    state.blockJitTlbConsider(page + block_jit.Tlb.page_bytes, 4, true);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page + block_jit.Tlb.page_bytes) != null);
}

test "mapped-write trace stops withholding write TLB after its guest-step window" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    if (state.blockJitActive() == null) return error.SkipZigTest;
    state.trace_windows_memory = true;

    try testing.expect(state.windowsMemoryTraceLive());
    try testing.expect(state.traceWithholdsWriteTlb(ElfState.windows_memory_trace_floor));

    state.executed_steps = ElfState.windows_memory_trace_step_budget;
    try testing.expect(!state.windowsMemoryTraceLive());
    try testing.expect(state.windows_memory_trace_step_closed.load(.monotonic));
    try testing.expect(!state.traceWithholdsWriteTlb(ElfState.windows_memory_trace_floor));
}

test "mapped-write trace reservations enforce the shared event cap" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    for (0..ElfState.windows_memory_trace_budget) |_| {
        try testing.expect(state.claimWindowsMemoryTraceEvent());
    }
    try testing.expect(!state.claimWindowsMemoryTraceEvent());
    try testing.expectEqual(
        ElfState.windows_memory_trace_budget,
        state.windows_memory_trace_events.load(.monotonic),
    );
}

test "a worker's VEX arithmetic and compare instructions change the worker's registers, not the owner's" {
    // The shared vector helpers (`x86_vector_helpers`, `evex_runtime`)
    // used to read and write `self.xmm` / `self.regs.rflags` directly, so on
    // a Windows worker they operated on the process owner's registers: on
    // 2026-09-25 that broke libstdc++'s path splitting on Xenia's Emulator
    // thread and turned a component length into a 10.8 GB allocation.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.block_jit_enabled = false;
    const program = [_]u8{
        0xC5, 0xF0, 0x58, 0xC2, // vaddps xmm0, xmm1, xmm2
        0xC5, 0xF8, 0x2E, 0xCA, // vucomiss xmm1, xmm2
    };
    const code = state.mem_base + 0x1000;
    @memcpy(state.guestMemory(code, program.len).?, &program);

    var context: WindowsGuestThreadContext = .{};
    context.regs.rip = code;
    context.regs.rsp = state.mem_base + 0x40000;
    context.regs.rflags = 0x2;
    for (0..4) |lane| {
        std.mem.writeInt(u32, context.xmm[1][lane * 4 ..][0..4], @bitCast(@as(f32, 1.0)), .little);
        std.mem.writeInt(u32, context.xmm[2][lane * 4 ..][0..4], @bitCast(@as(f32, 2.0)), .little);
    }
    const owner_xmm = state.xmm;
    const owner_rflags = state.regs.rflags;

    const binding = windows_guest_execution_binding();
    const previous = binding.*;
    binding.* = .{ .owner = @ptrCast(&state), .context = &context };
    defer binding.* = previous;
    for (0..program.len / 4) |_| try testing.expect(state.step());

    try testing.expectEqual(code + program.len, context.regs.rip);
    for (0..4) |lane| {
        try testing.expectEqual(@as(f32, 3.0), @as(f32, @bitCast(std.mem.readInt(u32, context.xmm[0][lane * 4 ..][0..4], .little))));
    }
    // 1.0 < 2.0: CF set, ZF and PF clear, in the worker's flags - the ones
    // its next `jb`/`ja` reads.
    try testing.expect(context.regs.rflags & RFL_CF != 0);
    try testing.expect(context.regs.rflags & RFL_ZF == 0);
    try testing.expectEqualSlices(u8, std.mem.asBytes(&owner_xmm), std.mem.asBytes(&state.xmm));
    try testing.expectEqual(owner_rflags, state.regs.rflags);
}

test "a call probe sees every call and its return, interpreted or translated" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    // loop: call f ; dec rcx ; jnz loop ; jmp $        f: mov eax, 7 ; ret
    const program = [_]u8{
        0xE8, 0x08, 0x00, 0x00, 0x00, // loop: call f (+8)
        0x48, 0xFF, 0xC9, // dec rcx
        0x75, 0xF6, // jnz loop
        0xEB, 0xFE, // jmp $
        0x90, // pad
        0xB8, 0x07, 0x00, 0x00, 0x00, // f: mov eax, 7
        0xC3, // ret
    };
    for ([_]bool{ false, true }) |translate| {
        var state = ElfState.init(testing.allocator);
        defer state.deinit();
        state.windows_runtime_enabled = true;
        state.block_jit_enabled = translate;
        state.block_jit_hot_threshold = 2;
        const code = state.mem_base + 0x1000;
        @memcpy(state.guestMemory(code, program.len).?, &program);
        try testing.expect(state.call_probes.add(code + 13, "f"));
        state.call_probes.budget = 0; // count only; keep the test quiet
        state.rebuildBlockJitHookFilter();
        state.regs.rip = code;
        state.regs.rsp = state.mem_base + 0x40000;
        state.regs.rcx = 20;
        const exit_rip = code + 10;
        var steps: usize = 0;
        while (state.regs.rip != exit_rip and steps < 5000 and !state.terminated) : (steps += 1) _ = state.step();
        try testing.expectEqual(exit_rip, state.regs.rip);
        try testing.expectEqual(@as(u64, 7), state.regs.rax);
        try testing.expectEqual(@as(u64, 20), state.call_probes.probes[0].calls);
        try testing.expectEqual(@as(u64, 20), state.call_probes.probes[0].returns);
    }
}

test "a write past a guest heap block's end is reported when the block is freed" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const inside = state.guestAlloc(24, 8).?;
    state.write8(inside + 23, 0x41);
    try testing.expect(state.releaseGuestAllocation(inside));
    try testing.expectEqual(@as(u64, 0), state.windows_heap_overruns);

    const overrun = state.guestAlloc(24, 8).?;
    state.write8(overrun + 24, 0x41); // one byte past the end
    try testing.expect(state.releaseGuestAllocation(overrun));
    try testing.expectEqual(@as(u64, 1), state.windows_heap_overruns);

    // An in-place shrink moves the guard to the new end without reporting
    // the guest's own bytes past it.
    const shrinking = state.guestAlloc(64, 8).?;
    for (0..64) |offset| state.write8(shrinking + offset, 0x5A);
    try testing.expectEqual(shrinking, state.reallocateGuest(shrinking, 16, 8).?);
    try testing.expect(state.releaseGuestAllocation(shrinking));
    try testing.expectEqual(@as(u64, 1), state.windows_heap_overruns);

    // The guard is never part of the guest's block.
    const next = state.guestAlloc(16, 16).?;
    const after = state.guestAlloc(16, 16).?;
    try testing.expect(after >= next + 16 + heap_guard.default_guard_bytes);

    // A page-aligned block carries no guard: the next one starts on the very
    // next page, and its bytes are never read as the first one's guard.
    const page = state.guestAlloc(0x1000, 0x1000).?;
    const next_page = state.guestAlloc(0x1000, 0x1000).?;
    try testing.expectEqual(page + 0x1000, next_page);
    state.write8(next_page, 0x41);
    try testing.expect(state.releaseGuestAllocation(page));
    try testing.expectEqual(@as(u64, 1), state.windows_heap_overruns);
}

test "a worker's translated blocks work on the worker's registers" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.block_jit_hot_threshold = 2;
    const program = [_]u8{
        0x48, 0x01, 0xC8, // loop: add rax, rcx
        0xC5, 0xF8, 0x58, 0xC1, // vaddps xmm0, xmm0, xmm1
        0x48, 0xFF, 0xCA, // dec rdx
        0x75, 0xF4, // jnz loop
        0xEB, 0xFE, // jmp $
    };
    const code = state.mem_base + 0x1000;
    @memcpy(state.guestMemory(code, program.len).?, &program);
    const exit_rip = code + program.len - 2;

    var context: WindowsGuestThreadContext = .{};
    context.regs.rip = code;
    context.regs.rsp = state.mem_base + 0x40000;
    context.regs.rflags = 0x2;
    context.regs.rcx = 3;
    context.regs.rdx = 100;
    for (0..4) |lane| std.mem.writeInt(u32, context.xmm[1][lane * 4 ..][0..4], @bitCast(@as(f32, 1.0)), .little);
    context.block_jit_tlb = state.ensureWindowsGuestThreadTlb(0) orelse return error.OutOfMemory;
    const owner_regs = state.regs;
    const owner_xmm = state.xmm;

    const binding = windows_guest_execution_binding();
    const previous = binding.*;
    binding.* = .{ .owner = @ptrCast(&state), .context = &context };
    defer binding.* = previous;
    var steps: usize = 0;
    while (context.regs.rip != exit_rip and steps < 5000 and !state.terminated) : (steps += 1) _ = state.step();

    try testing.expectEqual(exit_rip, context.regs.rip);
    try testing.expectEqual(@as(u64, 300), context.regs.rax);
    try testing.expectEqual(@as(u64, 0), context.regs.rdx);
    for (0..4) |lane| {
        try testing.expectEqual(@as(f32, 100.0), @as(f32, @bitCast(std.mem.readInt(u32, context.xmm[0][lane * 4 ..][0..4], .little))));
    }
    // The loop was translated, and the translation never touched the owner.
    try testing.expect(state.block_jit != null and state.block_jit.?.instructions_retired > 0);
    try testing.expectEqualSlices(u8, std.mem.asBytes(&owner_regs), std.mem.asBytes(&state.regs));
    try testing.expectEqualSlices(u8, std.mem.asBytes(&owner_xmm), std.mem.asBytes(&state.xmm));
}

test "blocks dropped under a live translated execution outlive it, and a full code memory waits to reset" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.block_jit_hot_threshold = 2;
    const program = [_]u8{
        0x48, 0x01, 0xC8, // loop: add rax, rcx
        0x48, 0xFF, 0xCA, // dec rdx
        0x75, 0xF8, // jnz loop
        0xEB, 0xFE, // jmp $
    };
    const code = state.mem_base + 0x1000;
    @memcpy(state.guestMemory(code, program.len).?, &program);
    const exit_rip = code + program.len - 2;
    const Loop = struct {
        fn run(s: *ElfState, entry: u64, exit: u64) !void {
            s.regs.rip = entry;
            s.regs.rsp = s.mem_base + 0x40000;
            s.regs.rflags = 0x2;
            s.regs.rax = 0;
            s.regs.rcx = 2;
            s.regs.rdx = 50;
            var steps: usize = 0;
            while (s.regs.rip != exit and steps < 5000 and !s.terminated) : (steps += 1) _ = s.step();
            try testing.expectEqual(exit, s.regs.rip);
            try testing.expectEqual(@as(u64, 100), s.regs.rax);
        }
    };
    try Loop.run(&state, code, exit_rip);
    const jit = state.block_jit orelse return error.TestUnexpectedResult;
    const block = state.blockJitFind(code) orelse return error.TestUnexpectedResult;
    const live = jit.liveBlocks();
    const compiled = jit.compiled;
    const resets = jit.resets;

    // An outer block is live on the host stack; the nested slice its helper
    // ran drops every block and then finds the code memory full.
    jit.lifetime.enter();
    state.blockJitDropAll();
    try testing.expect(state.blockJitFind(code) == null);
    try testing.expectEqual(live, jit.lifetime.retired.items.len);
    // Still allocated: the outer block's helpers and instructions are read
    // after the nested slice returns.
    try testing.expectEqual(code, block.start_rip);
    state.resetBlockJit(jit);
    try testing.expect(jit.lifetime.reset_pending);
    try testing.expectEqual(resets, jit.resets);
    try testing.expectEqual(@as(u64, 1), jit.lifetime.stats.deferred_resets);
    // The nested slice keeps running correctly, interpreted: nothing is
    // compiled into memory the reset has not reclaimed.
    try Loop.run(&state, code, exit_rip);
    try testing.expectEqual(compiled, jit.compiled);

    // The outermost execution returns: the retired blocks are freed (the
    // testing allocator fails the test on a leak) and the reset runs.
    state.leaveBlockJitExecution(jit);
    try testing.expectEqual(@as(u32, 0), jit.lifetime.active_executions);
    try testing.expectEqual(@as(usize, 0), jit.lifetime.retired.items.len);
    try testing.expect(!jit.lifetime.reset_pending);
    try testing.expectEqual(resets + 1, jit.resets);
    try testing.expectEqual(@as(u64, 0), jit.lifetime.stats.retire_leaks);
    // A deferred compile was not a refusal: the loop is translated again.
    try Loop.run(&state, code, exit_rip);
    try testing.expect(jit.compiled > compiled);
    try testing.expect(state.blockJitFind(code) != null);
}

test "cooperative guest contexts keep separate TLBs and mapping changes invalidate each one" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    const page = MEM_BASE + 0x20000;
    const owner_host = state.mem.ptr + 0x20000;
    const owner_tlb = state.ownerBlockJitTlb();
    const worker_tlb = state.ensureWindowsGuestThreadTlb(0) orelse return error.OutOfMemory;
    const second_worker_tlb = state.ensureWindowsGuestThreadTlb(1) orelse return error.OutOfMemory;

    try testing.expect(worker_tlb != owner_tlb);
    try testing.expect(second_worker_tlb != owner_tlb and second_worker_tlb != worker_tlb);
    owner_tlb.fill(true, page, owner_host);
    worker_tlb.fill(true, page, owner_host);
    second_worker_tlb.fill(true, page, owner_host);
    try testing.expect(owner_tlb.lookup(true, page) != null);
    try testing.expect(worker_tlb.lookup(true, page) != null);
    try testing.expect(second_worker_tlb.lookup(true, page) != null);

    state.block_jit_tlb_active = worker_tlb;
    const worker_context = state.captureWindowsGuestContext();
    try testing.expectEqual(worker_tlb, worker_context.block_jit_tlb.?);
    state.block_jit_tlb_active = null;
    state.restoreWindowsGuestContext(&worker_context);
    try testing.expectEqual(worker_tlb, state.activeBlockJitTlb());

    state.invalidateAllBlockJitTlbs(page, block_jit.Tlb.page_bytes);
    try testing.expect(owner_tlb.lookup(true, page) == null);
    try testing.expect(worker_tlb.lookup(true, page) == null);
    try testing.expect(second_worker_tlb.lookup(true, page) == null);
}

test "idempotent page protections do not invalidate live owner or worker TLB entries" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    const page = MEM_BASE + 0x30000;
    const host = state.mem.ptr + 0x30000;
    const worker_tlb = state.ensureWindowsGuestThreadTlb(0) orelse return error.OutOfMemory;

    state.noteGuestPageProtection(page, block_jit.Tlb.page_bytes, 0x02, "VirtualProtect", 0);
    state.ownerBlockJitTlb().fill(false, page, host);
    worker_tlb.fill(false, page, host);
    state.noteGuestPageProtection(page, block_jit.Tlb.page_bytes, 0x02, "VirtualProtect", 0);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) != null);
    try testing.expect(worker_tlb.lookup(false, page) != null);

    state.clearGuestPageProtection(page, block_jit.Tlb.page_bytes);
    state.ownerBlockJitTlb().fill(true, page, host);
    worker_tlb.fill(true, page, host);
    state.clearGuestPageProtection(page, block_jit.Tlb.page_bytes);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) != null);
    try testing.expect(worker_tlb.lookup(true, page) != null);
}

test "clearing page protection reports when it already invalidated the TLB" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    const page = MEM_BASE + 0x38000;
    state.noteGuestPageProtection(page, block_jit.Tlb.page_bytes, 0x01, "test protection", 0);
    const before_clear = state.parallel_tlb_cross_invalidations.load(.monotonic);

    try testing.expect(state.clearGuestPageProtectionAndReportInvalidation(page, block_jit.Tlb.page_bytes));
    try testing.expectEqual(before_clear + 1, state.parallel_tlb_cross_invalidations.load(.monotonic));
    try testing.expect(!state.clearGuestPageProtectionAndReportInvalidation(page, block_jit.Tlb.page_bytes));
    try testing.expectEqual(before_clear + 1, state.parallel_tlb_cross_invalidations.load(.monotonic));
}

test "non-temporal vector stores runtime guard refuses every queued or non-direct mode" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    var record: block_jit.Scratch = .{};
    const prior = tso_memory.setActiveStoreBuffer(null);
    defer _ = tso_memory.setActiveStoreBuffer(prior);
    state.refreshBlockJitGuards(&record);
    try testing.expectEqual(@as(u8, 0), record.direct_non_temporal);
    state.parallel_guest_execution = true;
    state.parallel_direct_tlb = true;
    state.block_jit_tlb_enabled = true;
    state.refreshBlockJitGuards(&record);
    try testing.expectEqual(@as(u8, 1), record.direct_non_temporal);
    const buffer = state.guest_store_buffers.forContext(null);
    _ = tso_memory.setActiveStoreBuffer(buffer);
    state.refreshBlockJitGuards(&record);
    // Even an empty bound queue is ineligible; no ordering proof is assumed.
    try testing.expectEqual(@as(u8, 0), record.direct_non_temporal);
    _ = tso_memory.setActiveStoreBuffer(null);
    state.parallel_direct_tlb = false;
    state.refreshBlockJitGuards(&record);
    try testing.expectEqual(@as(u8, 0), record.direct_non_temporal);
    state.parallel_direct_tlb = true;
    state.block_jit_tlb_enabled = false;
    state.refreshBlockJitGuards(&record);
    try testing.expectEqual(@as(u8, 0), record.direct_non_temporal);
    state.block_jit_tlb_enabled = true;
    state.block_jit_streaming_stores_enabled = false;
    state.refreshBlockJitGuards(&record);
    try testing.expectEqual(@as(u8, 0), record.direct_non_temporal);
}

test "parallel mode admits pages to the executing context's TLB and retires them across threads" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    if (state.blockJitActive() == null) return error.SkipZigTest;
    const page = MEM_BASE + 0x20000;
    const host = state.mem.ptr + 0x20000;
    const worker_tlb = state.ensureWindowsGuestThreadTlb(0) orelse return error.OutOfMemory;
    state.ownerBlockJitTlb().fill(false, page, host);
    worker_tlb.fill(true, page, host);

    // The transition is a stop-the-world boundary and starts every table
    // clean.
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) == null);
    try testing.expect(worker_tlb.lookup(true, page) == null);
    // No store queue while the direct route is live: a translated access
    // must never miss its own thread's earlier store.
    try testing.expect(state.parallelDirectTlbActive());
    try testing.expect(state.activeGuestTsoStoreBuffer() == null);

    // The executing context admits the page to its own table, and a hit is
    // the host page itself.
    state.blockJitTlbConsider(page, 4, false);
    state.blockJitTlbConsider(page, 4, true);
    try testing.expectEqual(@intFromPtr(host) + 8, @intFromPtr(state.ownerBlockJitTlb().lookup(false, page + 8).?));
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) != null);
    worker_tlb.fillOrdered(true, page, host);

    // A protection change retires every executor's entries it makes wrong
    // under a new epoch: a write-protected page loses its write entries
    // and keeps the read one, and is admitted for reading only.
    const epoch = state.block_jit_tlb_epoch.load(.monotonic);
    state.noteGuestPageProtection(page, block_jit.Tlb.page_bytes, 0x02, "VirtualProtect", 0); // PAGE_READONLY
    try testing.expect(state.block_jit_tlb_epoch.load(.monotonic) > epoch);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) != null);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) == null);
    try testing.expect(worker_tlb.lookup(true, page) == null);
    state.blockJitTlbConsider(page, 4, true);
    state.blockJitTlbConsider(page, 4, false);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) == null);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) != null);
    // No access retires the read entry too; accessible again retires
    // nothing, but moves the epoch so cached refusals are asked again.
    state.noteGuestPageProtection(page, block_jit.Tlb.page_bytes, 0x01, "VirtualProtect", 0); // PAGE_NOACCESS
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) == null);
    const relaxed_epoch = state.block_jit_tlb_epoch.load(.monotonic);
    state.noteGuestPageProtection(page, block_jit.Tlb.page_bytes, 0x04, "VirtualProtect", 0); // PAGE_READWRITE
    try testing.expect(state.block_jit_tlb_epoch.load(.monotonic) > relaxed_epoch);
    state.blockJitTlbConsider(page, 4, true);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, page) != null);

    // Flushes reach every table too.
    state.flushAllBlockJitTlbs(true, true);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) == null);
    try testing.expect(state.parallel_tlb_cross_invalidations.load(.monotonic) >= 2);

    // With the direct route switched off for an A/B run, nothing is admitted
    // and the per-thread queue returns.
    state.parallel_direct_tlb = false;
    try testing.expect(!state.parallelDirectTlbActive());
    try testing.expect(state.activeGuestTsoStoreBuffer() != null);
    state.blockJitTlbConsider(page, 4, false);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, page) == null);
}

test "native device aliases use ordered direct TLBs only for complete parallel pages" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    if (state.blockJitActive() == null) return error.SkipZigTest;
    const first_worker = state.ensureWindowsGuestThreadTlb(0) orelse return error.OutOfMemory;
    const second_worker = state.ensureWindowsGuestThreadTlb(1) orelse return error.OutOfMemory;
    const owner = state.ownerBlockJitTlb();
    const tlbs = [_]*block_jit.Tlb{ owner, first_worker, second_worker };
    const protected_page = state.mem_base + 0x30000;
    state.noteGuestPageProtection(protected_page, block_jit.Tlb.page_bytes, 0x01, "VirtualProtect", 0);
    try testing.expectEqual(tso_memory_policy.MemoryClass.fault_routed, state.guestMemoryClass(protected_page, 4, true));

    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    try testing.expect(state.parallelDirectTlbActive());

    var device_bytes: [block_jit.Tlb.page_bytes * 2]u8 align(4096) = @splat(0);
    const alias = state.borrowNativeMemory(&device_bytes) orelse return error.OutOfMemory;
    const page_bytes: u64 = block_jit.Tlb.page_bytes;
    try testing.expectEqual(@as(u64, 0), alias & (page_bytes - 1));
    try testing.expectEqual(tso_memory_policy.MemoryClass.device_backed, state.guestMemoryRangeClass(alias, 4, true));

    // Complete host-mapped pages can use the parallel direct route: generated
    // scalar accesses are acquire/release, vector accesses are ordered 64-bit
    // lanes, and no executor has a store queue in this mode. Each context
    // still owns and fills its own TLB.
    for (tlbs) |tlb| {
        state.block_jit_tlb_active = tlb;
        for (0..2) |page_index| {
            const page_index_u64: u64 = @intCast(page_index);
            const page_index_usize: usize = @intCast(page_index_u64);
            const page_bytes_usize: usize = @intCast(block_jit.Tlb.page_bytes);
            const offset = page_index_u64 * block_jit.Tlb.page_bytes;
            const address = alias + offset;
            const host = @intFromPtr(device_bytes[page_index_usize * page_bytes_usize ..].ptr);
            state.blockJitTlbConsider(address, 4, false);
            state.blockJitTlbConsider(address, 4, true);
            try testing.expectEqual(host, @intFromPtr(tlb.lookup(false, address).?));
            try testing.expectEqual(host, @intFromPtr(tlb.lookup(true, address).?));
        }
    }
    state.block_jit_tlb_active = null;
    const alias_jit = state.tlbFillBlockJit() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u64, 12), alias_jit.tlb_fills);
    try testing.expectEqual(@as(u64, 0), alias_jit.tlb_fill_refusals);

    // A partial mapping cannot authorize an entire page in the JIT. Keep its
    // accesses on the bounds-checked device helper.
    var short_bytes: [32]u8 align(4096) = @splat(0);
    const short_alias = state.borrowNativeMemory(&short_bytes) orelse return error.OutOfMemory;
    state.block_jit_tlb_active = state.ownerBlockJitTlb();
    state.blockJitTlbConsider(short_alias, 4, false);
    state.blockJitTlbConsider(short_alias, 4, true);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, short_alias) == null);
    try testing.expect(state.ownerBlockJitTlb().lookup(true, short_alias) == null);
    state.releaseNativeMemory(short_alias);

    // The cooperative/queued route retains the class-aware helper contract.
    state.flushAllBlockJitTlbs(true, true);
    state.parallel_direct_tlb = false;
    state.block_jit_tlb_active = state.ownerBlockJitTlb();
    state.blockJitTlbConsider(alias, 4, false);
    try testing.expect(state.ownerBlockJitTlb().lookup(false, alias) == null);
    state.parallel_direct_tlb = true;
    state.block_jit_tlb_active = null;

    // Release and re-publish both retire stale owner/worker entries. The
    // second fill simulates a translation admitted at the lifetime edge;
    // publication must still revoke it before the slot exposes new bytes.
    for (tlbs) |tlb| {
        tlb.fillOrdered(false, alias, &device_bytes);
        tlb.fillOrdered(true, alias, &device_bytes);
    }
    state.releaseNativeMemory(alias);
    for (tlbs) |tlb| {
        try testing.expect(tlb.lookup(false, alias) == null);
        try testing.expect(tlb.lookup(true, alias) == null);
        tlb.fillOrdered(false, alias, &device_bytes);
        tlb.fillOrdered(true, alias, &device_bytes);
    }
    const reused_alias = state.borrowNativeMemory(&device_bytes) orelse return error.OutOfMemory;
    try testing.expectEqual(alias, reused_alias);
    for (tlbs) |tlb| {
        try testing.expect(tlb.lookup(false, alias) == null);
        try testing.expect(tlb.lookup(true, alias) == null);
    }
    // Reuse advances the TLB epoch. Each executor must refill the page from
    // the new alias lifetime rather than retain the previous host pointer.
    const fills_before_reuse = alias_jit.tlb_fills;
    const misses_before_reuse = alias_jit.tlb_refusal_cache.misses;
    const hits_before_reuse = alias_jit.tlb_refusal_cache.hits;
    for (tlbs) |tlb| {
        state.block_jit_tlb_active = tlb;
        state.blockJitTlbConsider(reused_alias, 4, false);
        state.blockJitTlbConsider(reused_alias, 4, true);
        try testing.expectEqual(@intFromPtr(device_bytes[0..].ptr), @intFromPtr(tlb.lookup(false, reused_alias).?));
        try testing.expectEqual(@intFromPtr(device_bytes[0..].ptr), @intFromPtr(tlb.lookup(true, reused_alias).?));
    }
    state.block_jit_tlb_active = null;
    try testing.expectEqual(fills_before_reuse + 6, alias_jit.tlb_fills);
    try testing.expectEqual(misses_before_reuse + 6, alias_jit.tlb_refusal_cache.misses);
    try testing.expectEqual(hits_before_reuse, alias_jit.tlb_refusal_cache.hits);

    // A helper-routed device operation still publishes an earlier temporal
    // RAM store, performs its own direct update, and leaves no device write
    // in the RAM queue.
    var queue: tso_memory.StoreBuffer = .{};
    const previous_queue = tso_memory.setActiveStoreBuffer(&queue);
    defer _ = tso_memory.setActiveStoreBuffer(previous_queue);
    tso_memory.store(u32, state.mem[0x100..], 0xA1B2_C3D4);
    try testing.expectEqual(@as(usize, 1), queue.pendingCount());
    state.write32(reused_alias + 0x20, 0x1122_3344);
    try testing.expectEqual(@as(usize, 0), queue.pendingCount());
    try testing.expectEqual(@as(u32, 0xA1B2_C3D4), std.mem.readInt(u32, state.mem[0x100..][0..4], .little));
    try testing.expectEqual(@as(u32, 0x1122_3344), std.mem.readInt(u32, device_bytes[0x20..][0..4], .little));
}

test "non-temporal vector stores publish earlier RAM stores and bypass requeueing" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    var queue: tso_memory.StoreBuffer = .{};
    const previous_queue = tso_memory.setActiveStoreBuffer(&queue);
    defer _ = tso_memory.setActiveStoreBuffer(previous_queue);

    tso_memory.store(u32, state.mem[0x100..], 0xA1B2_C3D4);
    try testing.expectEqual(@as(usize, 1), queue.pendingCount());
    const address = state.mem_base + 0x2000;
    const payload: [16]u8 = .{ 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F };
    state.writeMem128NonTemporal(address, payload);

    try testing.expectEqual(@as(usize, 0), queue.pendingCount());
    try testing.expectEqual(@as(u32, 0xA1B2_C3D4), std.mem.readInt(u32, state.mem[0x100..][0..4], .little));
    try testing.expectEqualSlices(u8, &payload, state.mem[0x2000..][0..payload.len]);
}

test "parallel first mapped-code fetch atomically retires every worker write TLB" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    if (state.blockJitActive() == null) return error.SkipZigTest;

    const mapping: u64 = 0xFFFF_F000_0000_0F21;
    const code_page: u64 = 0x6000_0000;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, code_page, 0x10000, 0).?;
    const first_worker = state.ensureWindowsGuestThreadTlb(0) orelse return error.OutOfMemory;
    const second_worker = state.ensureWindowsGuestThreadTlb(1) orelse return error.OutOfMemory;

    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const host = state.windowsMappedMemoryConst(code_page, block_jit.Tlb.page_bytes).?.ptr;
    const tlbs = [_]*block_jit.Tlb{ state.ownerBlockJitTlb(), first_worker, second_worker };
    for (tlbs) |tlb| {
        tlb.fillOrdered(false, code_page, @constCast(host));
        tlb.fillOrdered(true, code_page, @constCast(host));
    }
    const range = state.windows_mapped_ranges.find(code_page, 1).?;
    try testing.expect(!state.mappedRangeCodeFetched(range));
    const invalidations_before = state.parallel_tlb_cross_invalidations.load(.monotonic);

    const ConcurrentFetch = struct {
        state: *ElfState,
        source: WindowsMappedCodeSlice,
        ready: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        start: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

        fn mark(self: *@This()) void {
            _ = self.ready.fetchAdd(1, .release);
            while (self.start.load(.acquire) == 0) std.atomic.spinLoopHint();
            self.state.noteMappedCodeFetched(self.source);
        }
    };
    const source = state.windowsMappedCodeMemoryConst(code_page, 1).?;
    var concurrent = ConcurrentFetch{ .state = &state, .source = source };
    const first = try std.Thread.spawn(.{}, ConcurrentFetch.mark, .{&concurrent});
    const second = try std.Thread.spawn(.{}, ConcurrentFetch.mark, .{&concurrent});
    while (concurrent.ready.load(.acquire) != 2) std.atomic.spinLoopHint();
    concurrent.start.store(1, .release);
    first.join();
    second.join();

    try testing.expect(state.mappedRangeCodeFetched(range));
    try testing.expectEqual(invalidations_before + 1, state.parallel_tlb_cross_invalidations.load(.monotonic));
    for (tlbs) |tlb| {
        try testing.expect(tlb.lookup(false, code_page) != null);
        try testing.expect(tlb.lookup(true, code_page) == null);
    }
}

test "parallel mapped alias write publishes code bytes before its shared generation" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    const mapping: u64 = 0xFFFF_F000_0000_0F22;
    const code: u64 = 0x6000_0000;
    const alias: u64 = 0x7000_0000;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, code, 0x10000, 0).?;
    _ = state.mapWindowsMemoryView(mapping, alias, 0x10000, 0).?;
    const mapping_index = state.windowsMappingIndex(mapping).?;
    const initial_generation = ElfState.loadCodeGeneration(&state.windows_file_mappings[mapping_index].code_generation);
    state.parallel_guest_execution = true;
    defer state.parallel_guest_execution = false;

    const Shared = struct {
        state: *ElfState,
        generation: *const u64,
        initial_generation: u64,
        code_address: u64,
        expected: [8]u8,
        ready: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        start: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        result: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

        fn observe(self: *@This()) void {
            _ = self.ready.fetchAdd(1, .release);
            while (self.start.load(.acquire) == 0) std.atomic.spinLoopHint();
            for (0..2_000_000) |_| {
                if (ElfState.loadCodeGeneration(self.generation) <= self.initial_generation) {
                    std.atomic.spinLoopHint();
                    continue;
                }
                self.result.store(if (self.state.guestCodeRangeMatches(self.code_address, &self.expected)) 1 else 2, .release);
                return;
            }
            self.result.store(3, .release);
        }
    };
    var shared = Shared{
        .state = &state,
        .generation = &state.windows_file_mappings[mapping_index].code_generation,
        .initial_generation = initial_generation,
        .code_address = code,
        .expected = .{ 0x48, 0xB8, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 },
    };
    const observer = try std.Thread.spawn(.{}, Shared.observe, .{&shared});
    while (shared.ready.load(.acquire) != 1) std.atomic.spinLoopHint();
    shared.start.store(1, .release);
    const copied = state.copyToGuest(alias, &shared.expected);
    observer.join();
    try testing.expect(copied);
    try testing.expectEqual(@as(u8, 1), shared.result.load(.acquire));
    try testing.expectEqual(initial_generation + 1, ElfState.loadCodeGeneration(shared.generation));
}

test "a translator table grows fourfold without evicting and empties the slots links named" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const jit = BlockJitState.createSized(testing.allocator, 16, 64 << 20) orelse return error.SkipZigTest;
    defer jit.destroy(testing.allocator);
    jit.max_entries = 64;

    // Four sets of four ways; seat what fits, as `runBlockJit` would.
    const program = [_]u8{ 0x48, 0x83, 0xC0, 0x01, 0xC3 }; // add rax, 1 ; ret
    var seated: usize = 0;
    var linked_slot: ?*?*block_jit.Block = null;
    for (0..12) |index| {
        const rip = state.mem_base + 0x1000 + index * 0x40;
        try testing.expect(state.copyToGuest(rip, &program));
        const block = state.compileBlockJit(jit, rip) orelse return error.TestUnexpectedResult;
        const base = jit.firstSlot(rip);
        for (jit.blocks[base .. base + BLOCK_JIT_WAYS]) |*slot| {
            if (slot.* == null) {
                slot.* = block;
                seated += 1;
                linked_slot = slot;
                break;
            }
        } else BlockJitState.freeBlock(testing.allocator, block);
        jit.hotness[base] = .{ .rip = rip, .count = 20 };
    }
    const hot_before = blk: {
        var count: usize = 0;
        for (jit.hotness) |entry| {
            if (entry.rip != 0) count += 1;
        }
        break :blk count;
    };

    // Not while a translated execution is live, and not below an eighth.
    jit.pressure = 1;
    try testing.expect(!jit.growIfPressed(testing.allocator));
    jit.pressure = 2;
    jit.lifetime.enter();
    try testing.expect(!jit.growIfPressed(testing.allocator));
    _ = jit.lifetime.leave(testing.allocator);
    try testing.expect(jit.growIfPressed(testing.allocator));

    try testing.expectEqual(@as(usize, 64), jit.blocks.len);
    try testing.expectEqual(@as(u32, 1), jit.growths);
    try testing.expectEqual(@as(u64, 0), jit.pressure);
    try testing.expectEqual(seated, jit.liveBlocks());
    for (jit.blocks, 0..) |maybe, index| {
        const block = maybe orelse continue;
        const base = jit.firstSlot(block.start_rip);
        try testing.expect(index >= base and index < base + BLOCK_JIT_WAYS);
    }
    var hot_after: usize = 0;
    for (jit.hotness) |entry| {
        if (entry.rip != 0) hot_after += 1;
    }
    try testing.expectEqual(hot_before, hot_after);
    // A chain link into the old table now reads null and is re-armed.
    try testing.expect(linked_slot.?.* == null);
    try testing.expectEqual(@as(usize, 1), jit.retired_tables.items.len);

    // The ceiling holds.
    jit.pressure = 1 << 20;
    try testing.expect(!jit.growIfPressed(testing.allocator));
    try testing.expectEqual(@as(usize, 64), jit.blocks.len);
}

test "a hotness entry taken from a warming address counts as table pressure" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const jit = BlockJitState.createSized(testing.allocator, 16, 64 << 20) orelse return error.SkipZigTest;
    defer jit.destroy(testing.allocator);

    // Five addresses in one set: the fifth must take a way from a warming one.
    var same_set: [BLOCK_JIT_WAYS + 1]u64 = undefined;
    var found: usize = 0;
    var candidate: u64 = 0x1_4000_0000;
    const target_base = jit.firstSlot(candidate);
    while (found < same_set.len) : (candidate += 2) {
        if (jit.firstSlot(candidate) != target_base) continue;
        same_set[found] = candidate;
        found += 1;
    }
    for (same_set[0..BLOCK_JIT_WAYS]) |rip| {
        const hot = ElfState.blockJitHotness(jit, rip);
        hot.count = 3;
    }
    try testing.expectEqual(@as(u64, 0), jit.hotness_replacements);
    const newcomer = ElfState.blockJitHotness(jit, same_set[BLOCK_JIT_WAYS]);
    try testing.expectEqual(same_set[BLOCK_JIT_WAYS], newcomer.rip);
    try testing.expectEqual(@as(u64, 1), jit.hotness_replacements);
    try testing.expectEqual(@as(u64, 1), jit.pressure);
}

test "unmapping generated-code aliases retires owner and worker block caches" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mapping: u64 = 0xFFFF_F000_0000_0F23;
    const owner_code: u64 = 0x6000_0000;
    const worker_code: u64 = 0x7000_0000;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, owner_code, 0x10000, 0).?;
    _ = state.mapWindowsMemoryView(mapping, worker_code, 0x10000, 0).?;
    const program = [_]u8{ 0x48, 0x83, 0xC0, 0x01, 0xC3 }; // add rax, 1 ; ret
    try testing.expect(state.copyToGuest(owner_code, &program));

    const owner_jit = state.blockJitActive() orelse return error.SkipZigTest;
    state.parallel_guest_execution = true;
    defer state.parallel_guest_execution = false;
    const worker_jit = state.parallelWorkerBlockJit(0) orelse return error.SkipZigTest;
    const mapping_index = state.windowsMappingIndex(mapping).?;
    const owner_block = state.compileBlockJit(owner_jit, owner_code) orelse return error.TestUnexpectedResult;
    const worker_block = state.compileBlockJit(worker_jit, worker_code) orelse return error.TestUnexpectedResult;
    try testing.expect(owner_block.source_mapped and worker_block.source_mapped);
    try testing.expectEqual(mapping_index, owner_block.source_index);
    try testing.expectEqual(mapping_index, worker_block.source_index);

    const owner_slot = owner_jit.firstSlot(owner_code);
    const worker_slot = worker_jit.firstSlot(worker_code);
    owner_jit.blocks[owner_slot] = owner_block;
    worker_jit.blocks[worker_slot] = worker_block;
    try testing.expectEqual(@as(usize, 1), owner_jit.liveBlocks());
    try testing.expectEqual(@as(usize, 1), worker_jit.liveBlocks());

    try testing.expect(state.unmapWindowsMemoryView(worker_code));
    try testing.expect(owner_jit.blocks[owner_slot] == null);
    try testing.expect(worker_jit.blocks[worker_slot] == null);
    try testing.expectEqual(@as(u64, 1), owner_jit.dropped_unmapped);
    try testing.expectEqual(@as(u64, 1), worker_jit.dropped_unmapped);
}

test "parallel executable alias writes stale owner and worker translations by generation" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const mapping: u64 = 0xFFFF_F000_0000_0F24;
    const owner_code: u64 = 0x6000_0000;
    const worker_code: u64 = 0x7000_0000;
    const writer_alias: u64 = 0x8000_0000;
    try testing.expect(state.createWindowsMemoryMapping(mapping, 0x10000, std.math.maxInt(u64)));
    _ = state.mapWindowsMemoryView(mapping, owner_code, 0x10000, 0).?;
    _ = state.mapWindowsMemoryView(mapping, worker_code, 0x10000, 0).?;
    _ = state.mapWindowsMemoryView(mapping, writer_alias, 0x10000, 0).?;
    const original = [_]u8{ 0x48, 0x83, 0xC0, 0x01, 0xC3 }; // add rax, 1 ; ret
    const replacement = [_]u8{ 0x48, 0x83, 0xC0, 0x02, 0xC3 }; // add rax, 2 ; ret
    try testing.expect(state.copyToGuest(owner_code, &original));

    const owner_jit = state.blockJitActive() orelse return error.SkipZigTest;
    state.parallel_guest_execution = true;
    defer state.parallel_guest_execution = false;
    const worker_jit = state.parallelWorkerBlockJit(0) orelse return error.SkipZigTest;
    const mapping_index = state.windowsMappingIndex(mapping).?;
    const owner_block = state.compileBlockJit(owner_jit, owner_code) orelse return error.TestUnexpectedResult;
    const worker_block = state.compileBlockJit(worker_jit, worker_code) orelse return error.TestUnexpectedResult;
    try testing.expect(owner_block.source_mapped and worker_block.source_mapped);
    try testing.expectEqual(mapping_index, owner_block.source_index);
    try testing.expectEqual(mapping_index, worker_block.source_index);
    const initial_generation = ElfState.loadCodeGeneration(&state.windows_file_mappings[mapping_index].code_generation);

    const owner_slot = owner_jit.firstSlot(owner_code);
    const worker_slot = worker_jit.firstSlot(worker_code);
    owner_jit.blocks[owner_slot] = owner_block;
    worker_jit.blocks[worker_slot] = worker_block;
    try testing.expectEqual(@as(usize, 1), owner_jit.liveBlocks());
    try testing.expectEqual(@as(usize, 1), worker_jit.liveBlocks());

    // Write through a third alias. The mapping-wide release generation must
    // make both executors reject their cached old bytes on their next entry.
    try testing.expect(state.copyToGuest(writer_alias, &replacement));
    try testing.expectEqual(initial_generation + 1, ElfState.loadCodeGeneration(&state.windows_file_mappings[mapping_index].code_generation));
    try testing.expect(state.blockJitFindValidSlot(owner_jit, owner_code) == null);
    try testing.expect(state.blockJitFindValidSlot(worker_jit, worker_code) == null);
    try testing.expectEqual(@as(u64, 1), owner_jit.dropped_stale);
    try testing.expectEqual(@as(u64, 1), worker_jit.dropped_stale);
}

test "parallel PE scheduler starts a private guest context on a host worker" {
    var state = ElfState.initWithMemory(testing.allocator, 4 * 1024 * 1024);
    defer state.deinit();
    const image_base: u64 = 0x140000000;
    state.mem_base = image_base;
    state.mem_size = state.mem.len;
    state.image_low = image_base;
    state.image_high = image_base + 0x10000;
    state.heap_next = image_base + 0x20000;
    state.guest_heap_limit = image_base + state.mem_size - 0x10000;
    state.windows_process_peb = image_base + 0x8000;
    state.windows_runtime_enabled = true;
    state.regs.rax = 0xCAFE;
    const start = image_base + 0x1000;
    const code_offset: usize = @intCast(start - image_base);
    const code = [_]u8{ 0xB8, 42, 0, 0, 0, 0xC3 }; // mov eax,42; ret
    @memcpy(state.mem[code_offset .. code_offset + code.len], &code);
    state.configureWindowsExecutableRanges(&.{.{ .guest_base = start, .length = 0x1000 }});
    state.setParallelGuestExecution(true);

    try testing.expect(state.enqueueWindowsGuestThread(0xF000000000000001, start, 0, 64 * 1024, true));
    try testing.expectEqual(@as(u64, 0), state.serviceWindowsGuestThreads(64));
    try testing.expect(state.windows_guest_threads[0].parallel_worker.isStarted());

    state.windows_guest_threads[0].parallel_worker.join();
    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[0].status);
    try testing.expectEqual(@as(u64, 42), state.windows_guest_threads[0].context.regs.rax);
    try testing.expectEqual(@as(u64, 0xCAFE), state.regs.rax);
    try testing.expect(state.windowsWorkerSteps() >= 3);
    try testing.expectEqual(state.windowsWorkerSteps(), state.totalInterpretedSteps());
}

test "parallel workers pass message-passing through their direct TLBs in x86 order" {
    // A producer stores data then flag, counting down; a consumer on another
    // host thread loads flag then data. x86-TSO forbids a consumer that saw
    // flag == f (f != 0) from then reading data > f. Both loops run as
    // translated code whose accesses hit their own thread's TLB as one LDAR
    // or STLR - the direct route this replaces went through the stripe
    // helper for every access.
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    var state = ElfState.initWithMemory(testing.allocator, 4 * 1024 * 1024);
    defer state.deinit();
    const image_base: u64 = 0x140000000;
    state.mem_base = image_base;
    state.mem_size = state.mem.len;
    state.image_low = image_base;
    state.image_high = image_base + 0x10000;
    state.heap_next = image_base + 0x20000;
    state.guest_heap_limit = image_base + state.mem_size - 0x10000;
    state.windows_process_peb = image_base + 0x8000;
    state.windows_runtime_enabled = true;
    state.block_jit_hot_threshold = 2;
    const producer_start = image_base + 0x1000;
    const consumer_start = image_base + 0x1100;
    const shared = image_base + 0xA000;
    const producer = [_]u8{
        0x48, 0xC7, 0xC2, 0x80, 0x84, 0x1E, 0x00, // mov rdx, 2000000
        0x48, 0x89, 0x11, // loop: mov [rcx], rdx      (data)
        0x48, 0x89, 0x51, 0x08, // mov [rcx+8], rdx   (flag)
        0x48, 0xFF, 0xCA, // dec rdx
        0x75, 0xF4, // jnz loop
        0x31, 0xC0, // xor eax, eax
        0xC3, // ret
    };
    const consumer = [_]u8{
        0x45, 0x31, 0xC0, // xor r8d, r8d            (violations)
        0x49, 0xC7, 0xC1, 0x00, 0xC2, 0xEB, 0x0B, // mov r9, 200000000 (budget)
        0x48, 0x8B, 0x41, 0x08, // loop: mov rax, [rcx+8] (flag)
        0x48, 0x8B, 0x11, // mov rdx, [rcx]            (data)
        0x48, 0x85, 0xC0, // test rax, rax
        0x74, 0x0E, // jz tail
        0x48, 0x39, 0xC2, // cmp rdx, rax
        0x76, 0x03, // jbe ok
        0x49, 0xFF, 0xC0, // inc r8
        0x48, 0x83, 0xF8, 0x01, // ok: cmp rax, 1
        0x74, 0x05, // je done
        0x49, 0xFF, 0xC9, // tail: dec r9
        0x75, 0xE1, // jnz loop
        0x4C, 0x89, 0xC0, // done: mov rax, r8
        0xC3, // ret
    };
    @memcpy(state.mem[0x1000 .. 0x1000 + producer.len], &producer);
    @memcpy(state.mem[0x1100 .. 0x1100 + consumer.len], &consumer);
    state.configureWindowsExecutableRanges(&.{.{ .guest_base = producer_start, .length = 0x1000 }});
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    try testing.expect(state.parallelDirectTlbActive());

    try testing.expect(state.enqueueWindowsGuestThread(0xF000000000000001, consumer_start, shared, 64 * 1024, true));
    try testing.expect(state.enqueueWindowsGuestThread(0xF000000000000002, producer_start, shared, 64 * 1024, true));
    _ = state.serviceWindowsGuestThreads(64);
    _ = state.serviceWindowsGuestThreads(64);
    try testing.expect(state.windows_guest_threads[0].parallel_worker.isStarted());
    try testing.expect(state.windows_guest_threads[1].parallel_worker.isStarted());
    state.windows_guest_threads[0].parallel_worker.join();
    state.windows_guest_threads[1].parallel_worker.join();

    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[0].status);
    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[1].status);
    try testing.expectEqual(@as(u64, 0), state.windows_guest_threads[0].context.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.read64(shared));
    try testing.expectEqual(@as(u64, 1), state.read64(shared + 8));
    // The accesses went through each worker's own table, not the helper.
    for (0..2) |slot| {
        const jit = state.windows_guest_threads[slot].parallel_block_jit orelse return error.TestUnexpectedResult;
        try testing.expect(jit.tlb_fills > 0);
        try testing.expect(jit.instructions_retired > 1_000_000);
        try testing.expectEqual(@as(u64, 0), jit.mismatches);
    }
}

test "the translator's TLB is emptied by a protection change and never lets a protected store skip its fault" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const interpreted = runTlbProtectionProgram(false);
    const translated = runTlbProtectionProgram(true);
    try std.testing.expectEqual(@as(u64, 204), interpreted.rax);
    try std.testing.expectEqual(interpreted.rax, translated.rax);
    try std.testing.expectEqual(@as(u64, 100), interpreted.violations);
    try std.testing.expectEqual(interpreted.violations, translated.violations);
    try std.testing.expect(translated.fills > 0);
    try std.testing.expect(translated.admitted_before);
    try std.testing.expect(!translated.admitted_after_protect);
    try std.testing.expect(!translated.admitted_after_executable);
}
