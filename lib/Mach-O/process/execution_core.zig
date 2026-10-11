// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const BOUND_IMPORT_THUNK_BASE = __ProcessInternals._BOUND_IMPORT_THUNK_BASE;
const ControlTransferContext = __ProcessInternals._ControlTransferContext;
const DecodeCacheEntry = __ProcessInternals._DecodeCacheEntry;
const DecodedInsn = __ProcessInternals._DecodedInsn;
const FastPlainDecode = __ProcessInternals._FastPlainDecode;
const GUEST_SIGILL = __ProcessInternals._GUEST_SIGILL;
const GuestAccess = __ProcessInternals._GuestAccess;
const GuestFile = __ProcessInternals._GuestFile;
const GuestSignalFrame = __ProcessInternals._GuestSignalFrame;
const ImportHandlerResult = __ProcessInternals._ImportHandlerResult;
const InitializerRunOutcome = __ProcessInternals._InitializerRunOutcome;
const RFL_CF = __ProcessInternals._RFL_CF;
const RegId = __ProcessInternals._RegId;
const Regs = __ProcessInternals._Regs;
const Size = __ProcessInternals._Size;
const application_framework = __ProcessInternals._application_framework;
const compat_handlers = __ProcessInternals._compat_handlers;
const compat_runtime = __ProcessInternals._compat_runtime;
const constants = __ProcessInternals._constants;
const contract = __ProcessInternals._contract;
const crash_diag = __ProcessInternals._crash_diag;
const decodeInsn = __ProcessInternals._decodeInsn;
const decodeInsnCompat = __ProcessInternals._decodeInsnCompat;
const dynamic_library_forwarder = __ProcessInternals._dynamic_library_forwarder;
const execution_helpers = __ProcessInternals._execution_helpers;
const execution_history = __ProcessInternals._execution_history;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const guest_fs = __ProcessInternals._guest_fs;
const hasRelativeControlDisplacement = __ProcessInternals._hasRelativeControlDisplacement;
const import_dispatch = __ProcessInternals._import_dispatch;
const initialization_resolution = __ProcessInternals._initialization_resolution;
const initializers = __ProcessInternals._initializers;
const isApplicationControlFlow = __ProcessInternals._isApplicationControlFlow;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_metadata = __ProcessInternals._macho_metadata;
const main = __ProcessInternals._main;
const memory_access = __ProcessInternals._memory_access;
const scheduling = __ProcessInternals._scheduling;
const signal_handling = __ProcessInternals._signal_handling;
const specialRipTableContains = __ProcessInternals._specialRipTableContains;
const std = __ProcessInternals._std;
const tlv_runtime = __ProcessInternals._tlv_runtime;
const translation_cache = __ProcessInternals._translation_cache;
const translation_domain = __ProcessInternals._translation_domain;
const translation_economics = __ProcessInternals._translation_economics;
const x64_decoder = __ProcessInternals._x64_decoder;
const BankOccupancy = __ProcessInternals._BankOccupancy;
const DecodeCacheSelection = __ProcessInternals._DecodeCacheSelection;
const PrimaryDecodeCacheSelection = __ProcessInternals._PrimaryDecodeCacheSelection;
const addrToOffset = __ProcessInternals._addrToOffset;
const dumpStepTraceBuffer = __ProcessInternals._dumpStepTraceBuffer;
const ensureGuestAccess = __ProcessInternals._ensureGuestAccess;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const noteGuestWrite = __ProcessInternals._noteGuestWrite;
const read64 = __ProcessInternals._read64;
const readMemVal = __ProcessInternals._readMemVal;
const recordEndianEvidence = __ProcessInternals._recordEndianEvidence;
const terminateForGuestAccess = __ProcessInternals._terminateForGuestAccess;
const translateGuest = __ProcessInternals._translateGuest;
const tryRepairGeneratedEndianBeforeDispatch = __ProcessInternals._tryRepairGeneratedEndianBeforeDispatch;
const write64 = __ProcessInternals._write64;
const write8 = __ProcessInternals._write8;
const writeMemVal = __ProcessInternals._writeMemVal;
const configureGuestLogMirror = MachOState.configureGuestLogMirror;
const deinit = MachOState.deinit;
const dumpCoopBootstrapTrace = MachOState.dumpCoopBootstrapTrace;
const dumpCoopHeartbeatTrace = MachOState.dumpCoopHeartbeatTrace;
const dumpMemInitTrace = MachOState.dumpMemInitTrace;
const dumpUiHandoffTrace = MachOState.dumpUiHandoffTrace;
const execute = MachOState.execute;
const failFastOnTranslationCause = MachOState.failFastOnTranslationCause;
const fileOffsetForVaddr = MachOState.fileOffsetForVaddr;
const run = MachOState.run;
const step = MachOState.step;

pub fn handleImportImpl(self: anytype, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
    return import_dispatch.handleImportImpl(self, imported);
}

pub fn handleVirtualSleepSchedulingBoundary(self: anytype, reason: []const u8) bool {
    return import_dispatch.handleVirtualSleepSchedulingBoundary(self, reason);
}

pub fn handleDirectImportCall(self: anytype, imported: macho_metadata.ImportedSymbol) void {
    import_dispatch.handleDirectImportCall(self, imported);
}

pub fn recordUnresolvedImport(
    self: anytype,
    imported: macho_metadata.ImportedSymbol,
    return_address: u64,
    synthetic_result: u64,
) void {
    import_dispatch.recordUnresolvedImport(self, imported, return_address, synthetic_result);
}

pub noinline fn continueGuestExit(self: anytype) bool {
    return import_dispatch.continueGuestExit(self);
}

pub fn handleSigaction(self: anytype) u64 {
    return signal_handling.handleSigaction(self);
}

pub fn deliverGuestSignal(
    self: anytype,
    signal: u8,
    fault_rip: u64,
    instruction_len: u8,
    fault_address: u64,
    fault_access: ?GuestAccess,
    fault_width: u8,
    fault_instruction: []const u8,
) bool {
    return signal_handling.deliverGuestSignal(self, signal, fault_rip, instruction_len, fault_address, fault_access, fault_width, fault_instruction);
}

pub fn signalIsActive(self: anytype, signal: u8) bool {
    return signal_handling.signalIsActive(self, signal);
}

pub fn resetActiveGuestSignalState(self: anytype) void {
    scheduling.resetActiveGuestSignalState(self);
}

pub fn ensureGuestSignalFrameStorage(self: anytype, frame: *GuestSignalFrame) bool {
    return signal_handling.ensureGuestSignalFrameStorage(self, frame);
}

pub noinline fn finishGuestSignalReturn(self: anytype) bool {
    return signal_handling.finishGuestSignalReturn(self);
}

pub fn terminateForUnresolvedImport(self: anytype) void {
    crash_diag.terminateForUnresolvedImport(self);
}

pub fn recoverLibcppSharedControlBlockCall(
    self: anytype,
    instruction_address: u64,
    operand_address: u64,
) ?u64 {
    return crash_diag.recoverLibcppSharedControlBlockCall(self, instruction_address, operand_address);
}

pub fn isXModuleMatchesSymbol(symbol: []const u8) bool {
    return crash_diag.isXModuleMatchesSymbol(symbol);
}

pub fn findNearNullBaseTransition(self: anytype, register: RegId, terminal_value: u64) ?crash_diag.NearNullBaseTransition {
    return crash_diag.findNearNullBaseTransition(self, register, terminal_value);
}

pub fn ensureXmoduleVtable(self: anytype) ?u64 {
    return crash_diag.ensureXmoduleVtable(self);
}

pub fn recoverNearNullBaseRegister(self: anytype, d: *DecodedInsn) bool {
    return crash_diag.recoverNearNullBaseRegister(self, d);
}

pub fn recoverNullVtableSlot(self: anytype, instruction_address: u64, operand_address: u64) ?u64 {
    return crash_diag.recoverNullVtableSlot(self, instruction_address, operand_address);
}

pub fn logCrashDiagnostics(self: anytype, context: ControlTransferContext) void {
    crash_diag.logCrashDiagnostics(self, context);
}

pub fn terminateForInvalidControlTransfer(self: anytype, context: ControlTransferContext) void {
    crash_diag.terminateForInvalidControlTransfer(self, context);
}

pub fn handleOpen(self: anytype) u64 {
    return guest_fs.handleOpen(self);
}

pub fn registerGuestFd(self: anytype, host_fd: c_int) ?u64 {
    return guest_fs.registerGuestFd(self, host_fd);
}

pub fn setGuestErrno(self: anytype, value: c_int) void {
    guest_fs.setGuestErrno(self, value);
}

pub fn hostFd(self: anytype, guest_or_host_fd: u64) ?c_int {
    return guest_fs.hostFd(self, guest_or_host_fd);
}

pub fn handleFstatat(self: anytype) u64 {
    return guest_fs.handleFstatat(self);
}

pub fn handleOpenat(self: anytype) u64 {
    return guest_fs.handleOpenat(self);
}

pub fn handleFstat(self: anytype) u64 {
    return guest_fs.handleFstat(self);
}

pub fn handleFtruncate(self: anytype) u64 {
    return guest_fs.handleFtruncate(self);
}

pub fn handleOpendir(self: anytype) ?u64 {
    return guest_fs.handleOpendir(self);
}

pub fn handleClosedir(self: anytype) u64 {
    return guest_fs.handleClosedir(self);
}

pub fn handleWrite(self: anytype) u64 {
    return guest_fs.handleWrite(self);
}

pub fn handleClose(self: anytype) u64 {
    return guest_fs.handleClose(self);
}

pub fn hostWriteAll(self: anytype, file: *GuestFile, bytes: []const u8) bool {
    return guest_fs.hostWriteAll(self, file, bytes);
}

pub fn handleFopen(self: anytype) ?u64 {
    return guest_fs.handleFopen(self);
}

pub fn handleFdopen(self: anytype) ?u64 {
    return guest_fs.handleFdopen(self);
}

pub fn handleFileno(self: anytype) u64 {
    return guest_fs.handleFileno(self);
}

pub fn handleFclose(self: anytype) u64 {
    return guest_fs.handleFclose(self);
}

pub fn handleFputs(self: anytype) u64 {
    return guest_fs.handleFputs(self);
}

pub fn handleFwrite(self: anytype) u64 {
    return guest_fs.handleFwrite(self);
}

pub fn handleFread(self: anytype) u64 {
    return guest_fs.handleFread(self);
}

pub fn handleFflush(self: anytype) u64 {
    return guest_fs.handleFflush(self);
}

pub fn handleFtell(self: anytype) u64 {
    return guest_fs.handleFtell(self);
}

pub fn handleFseek(self: anytype) u64 {
    return guest_fs.handleFseek(self);
}

pub fn handleFerror(self: anytype) u64 {
    return guest_fs.handleFerror(self);
}

pub fn handleFprintf(self: anytype) u64 {
    return guest_fs.handleFprintf(self);
}

pub fn handleSnprintf(self: anytype) u64 {
    return guest_fs.handleSnprintf(self);
}

pub fn handlePrintfLike(self: anytype, file_opt: ?*GuestFile, format_address: u64, arguments: []const u64) u64 {
    return guest_fs.handlePrintfLike(self, file_opt, format_address, arguments);
}

pub fn handlePutchar(self: anytype) u64 {
    return guest_fs.handlePutchar(self);
}

pub fn handleGtkInitCheck(self: anytype) u64 {
    return guest_fs.handleGtkInitCheck(self);
}

pub fn nextVarArg(self: anytype, arguments: []const u64, gp_index: *usize, stack_arg_addr: *u64) u64 {
    if (gp_index.* < arguments.len) {
        defer gp_index.* += 1;
        return arguments[gp_index.*];
    }
    const addr = stack_arg_addr.*;
    stack_arg_addr.* += 8;
    return self.read64(addr);
}

pub fn noteGuestFieldAccess(self: anytype, decoded: DecodedInsn) void {
    const is_write = switch (decoded.op) {
        .mov_mem64_reg64,
        .mov_mem32_reg32,
        .mov_mem16_reg16,
        .mov_mem8_reg8,
        .mov_mem64_imm32,
        .mov_mem32_imm32,
        .mov_mem16_imm16,
        .mov_mem8_imm8,
        .movbe_mem_reg,
        => true,
        .mov_reg64_mem64,
        .mov_reg32_mem32,
        .mov_reg16_mem16,
        .mov_reg8_mem8,
        .movbe_reg_mem,
        => false,
        else => return,
    };
    if (!decoded.sib_has_base or decoded.sib_has_index or decoded.rip_relative) return;
    const base = self.regVal(decoded.sib_base_reg, .bits64);
    const effective = decoded.addr;
    if (base == 0 or effective < base) return;
    self.guest_fields.note(base, effective - base, is_write);
}

pub fn seedProvenanceWatch(self: anytype, decoded: DecodedInsn) void {
    if (self.provenance_watch.full()) return;
    if (decoded.op != .mov_reg64_mem64) return;
    if (!decoded.sib_has_base or decoded.sib_has_index or decoded.rip_relative) return;
    // On the execute path `decoded.addr` is the *resolved* effective
    // address (the decode cache applies live registers), not the raw
    // displacement. Recover the displacement rather than adding the base a
    // second time.
    const base = self.regVal(decoded.sib_base_reg, .bits64);
    const effective = decoded.addr;
    if (effective < base) return;
    _ = self.provenance_watch.seedFromOperand(base, effective - base);
}

pub fn recordTrace(self: anytype, decoded: DecodedInsn) void {
    self.execution_history.record(self.active_guest_thread, .{
        .thread_handle = self.active_guest_thread,
        .history_epoch = self.execution_history_epoch,
        .rip = self.regs.rip,
        .op = decoded.op,
        .len = decoded.len,
        .rsp = self.regs.rsp,
        .rax = self.regs.rax,
        .rbx = self.regs.rbx,
        .rcx = self.regs.rcx,
        .rdx = self.regs.rdx,
        .rsi = self.regs.rsi,
        .rdi = self.regs.rdi,
        .rbp = self.regs.rbp,
        .r8 = self.regs.r8,
        .r9 = self.regs.r9,
        .r10 = self.regs.r10,
        .r11 = self.regs.r11,
        .r12 = self.regs.r12,
        .r13 = self.regs.r13,
        .r14 = self.regs.r14,
        .r15 = self.regs.r15,
    });
}

pub fn shouldTraceRIP(self: anytype, rip: u64) bool {
    if (self.trace_range_start) |start| {
        const end = self.trace_range_end orelse start;
        return rip >= start and rip <= end;
    }
    return false;
}

pub fn dumpRecentTrace(self: anytype) void {
    const count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (count == 0) return;
    log.err("recent trace dump (most recent last, count={d})", .{count});
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const entry = self.execution_history.chronological(self.active_guest_thread, i) orelse continue;
        log.err("trace[{d}]: thread=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
            i,
            entry.thread_handle,
            entry.rip,
            @tagName(entry.op),
            entry.len,
            entry.rsp,
            entry.rax,
            entry.rcx,
            entry.rdx,
        });
    }
}

pub inline fn regVal(self: anytype, id: RegId, size: Size) u64 {
    return x64_decoder.regVal(&self.regs, id, size);
}

pub inline fn setReg(self: anytype, id: RegId, size: Size, val: u64) void {
    x64_decoder.setReg(&self.regs, id, size, val);
}

pub inline fn regOperandVal(self: anytype, id: RegId, size: Size, high8: bool) u64 {
    return x64_decoder.registerOperandValue(&self.regs, .{ .id = id, .high8 = high8 }, size);
}

pub inline fn setRegOperand(self: anytype, id: RegId, size: Size, high8: bool, val: u64) void {
    x64_decoder.setRegisterOperand(&self.regs, .{ .id = id, .high8 = high8 }, size, val);
}

pub fn setFlagsSub(self: anytype, a: u64, b: u64, result: u64, size: Size) void {
    x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
}

pub fn setFlagsAdd(self: anytype, a: u64, b: u64, result: u64, size: Size) void {
    x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
}

pub fn setFlagsIncDec(self: anytype, input: u64, result: u64, size: Size, is_inc: bool) void {
    x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
}

pub fn setFlagsLogic(self: anytype, result: u64, size: Size) void {
    x64_decoder.applyLogic(&self.regs.rflags, result, size);
}

pub fn executeHighwayRegisterBinary(self: anytype, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size) void {
    const width: x64_decoder.highway.Width = switch (size) {
        .bits8 => .bits8,
        .bits16 => .bits16,
        .bits32 => .bits32,
        .bits64 => .bits64,
    };
    const evaluated = x64_decoder.highway.evaluate(
        op,
        width,
        self.regOperandVal(d.dst_reg, size, d.dst_high8),
        self.regOperandVal(d.src_reg, size, d.src_high8),
        self.regs.rflags,
    );
    self.regs.rflags = evaluated.rflags;
    if (evaluated.writeback) self.setRegOperand(d.dst_reg, size, d.dst_high8, evaluated.value);
}

pub fn executeHighwayMemoryBinary(
    self: anytype,
    d: DecodedInsn,
    op: x64_decoder.highway.BinaryOp,
    size: Size,
    direction: x64_decoder.highway.MemoryDirection,
) void {
    const width: x64_decoder.highway.Width = switch (size) {
        .bits8 => .bits8,
        .bits16 => .bits16,
        .bits32 => .bits32,
        .bits64 => .bits64,
    };
    // F6 (throughput audit): no `ensureGuestAccess` pre-check here. It did a
    // sparse probe plus a `translateGuest`, and `readMemVal`/`writeMemVal`
    // below immediately repeat both — so every `add reg,[mem]`,
    // `cmp [mem],reg` and friend translated its address twice. The
    // accessors already terminate on an inaccessible address, through the
    // same `terminateForGuestAccess`, with a better instruction label than
    // `@tagName(op)` gave.
    const reg = if (direction == .memory_to_register) d.dst_reg else d.src_reg;
    const reg_high8 = if (direction == .memory_to_register) d.dst_high8 else d.src_high8;
    const memory_value = self.readMemVal(d.addr, size);
    // Endian-contract evidence belongs only to JIT-generated code. Native
    // Xenia executes a large number of 32-bit memory comparisons; sending
    // each through a sparse executable probe and evidence ring made an
    // exceptional recovery predicate part of the ordinary hot path.
    const generated_endian_candidate =
        op == .cmp and size == .bits32 and direction == .memory_to_register and
        (self.regs.rip < self.executable_min or self.regs.rip >= self.executable_max);
    if (generated_endian_candidate) {
        self.recordEndianEvidence(.cmp_witness, reg, d.addr, size, memory_value);
    }
    var register_value = self.regOperandVal(reg, size, reg_high8);
    if (generated_endian_candidate) {
        if (self.tryRepairGeneratedEndianBeforeDispatch(reg, d.addr, memory_value, d.len)) |restored| {
            register_value = restored;
        }
    }
    const evaluated = x64_decoder.highway.evaluateMemory(op, width, register_value, memory_value, direction, self.regs.rflags);
    self.regs.rflags = evaluated.rflags;
    if (evaluated.write_register) self.setRegOperand(reg, size, reg_high8, evaluated.value);
    if (evaluated.write_memory) self.writeMemVal(d.addr, size, evaluated.value);
}

pub fn executeHighwayImmediate(self: anytype, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size, memory: bool) void {
    const width: x64_decoder.highway.Width = switch (size) {
        .bits8 => .bits8,
        .bits16 => .bits16,
        .bits32 => .bits32,
        .bits64 => .bits64,
    };
    // F6: same removal as `executeHighwayMemoryBinary` — `readMemVal` and
    // `writeMemVal` perform and report the translation themselves.
    const lhs = if (memory) self.readMemVal(d.addr, size) else self.regOperandVal(d.dst_reg, size, d.dst_high8);
    const evaluated = x64_decoder.highway.evaluate(op, width, lhs, d.imm, self.regs.rflags);
    self.regs.rflags = evaluated.rflags;
    if (evaluated.writeback) {
        if (memory) self.writeMemVal(d.addr, size, evaluated.value) else self.setRegOperand(d.dst_reg, size, d.dst_high8, evaluated.value);
    }
}

pub fn setFlag(self: anytype, flag: u32, enabled: bool) void {
    if (enabled) {
        self.regs.rflags |= flag;
    } else {
        self.regs.rflags &= ~flag;
    }
}

pub fn executeBitTestRegister(
    self: anytype,
    d: DecodedInsn,
    operation: x64_decoder.BitTestOperation,
    immediate_index: bool,
) void {
    const value = self.regVal(d.dst_reg, d.size);
    const raw_index = if (immediate_index) d.imm else self.regVal(d.src_reg, d.size);
    const result = x64_decoder.bitTestRegister(d.size, value, raw_index, operation);
    self.setFlag(RFL_CF, result.carry);
    if (operation != .probe) self.setReg(d.dst_reg, d.size, result.value);
}

pub fn executeBitTestMemory(
    self: anytype,
    d: DecodedInsn,
    operation: x64_decoder.BitTestOperation,
    immediate_index: bool,
) void {
    const operand = if (immediate_index)
        x64_decoder.bitTestMemoryOperandImmediate(d.size, d.addr, d.imm)
    else
        x64_decoder.bitTestMemoryOperand(d.size, d.addr, self.regVal(d.src_reg, d.size));
    const resolved = operand orelse {
        self.faulted = true;
        self.terminated = true;
        return;
    };
    const value = self.readMemVal(resolved.address, d.size);
    const result = x64_decoder.bitTestRegister(d.size, value, resolved.bit_index, operation);
    self.setFlag(RFL_CF, result.carry);
    if (operation != .probe) self.writeMemVal(resolved.address, d.size, result.value);
}

pub fn terminateForMemoryAccess(self: anytype, check: x64_decoder.highway.MemoryCheck, instruction: []const u8) void {
    const access: GuestAccess = switch (check.access) {
        .read => .read,
        .write => .write,
        .execute => .execute,
        .atomic_read_modify_write => .write,
    };
    self.terminateForGuestAccess(check.address, check.bytes, access, instruction);
}

pub fn bitWidth(size: Size) u7 {
    return execution_helpers.bitWidth(size);
}

pub fn maskForSize(size: Size) u64 {
    return execution_helpers.maskForSize(size);
}

pub fn signBitForSize(size: Size) u64 {
    return execution_helpers.signBitForSize(size);
}

pub fn arithmeticShiftRight(value: u64, size: Size, count: u6) u64 {
    const signed: i64 = switch (size) {
        .bits8 => @as(i8, @bitCast(@as(u8, @truncate(value)))),
        .bits16 => @as(i16, @bitCast(@as(u16, @truncate(value)))),
        .bits32 => @as(i32, @bitCast(@as(u32, @truncate(value)))),
        .bits64 => @bitCast(value),
    };
    return @as(u64, @bitCast(signed >> count)) & maskForSize(size);
}

pub fn setupInitialStack(self: anytype, args: []const []const u8) void {
    var sp = self.mem_base + self.mem_size;

    sp -= 8;
    self.write64(sp, 0);

    sp -= 8;
    const envp_addr = sp;
    self.write64(sp, 0);

    var arg_addrs: std.ArrayList(u64) = .empty;
    defer arg_addrs.deinit(self.allocator);
    for (args) |arg| {
        sp -|= arg.len + 1;
        for (arg, 0..) |c, i| {
            self.write8(sp + i, c);
        }
        self.write8(sp + arg.len, 0);
        arg_addrs.append(self.allocator, sp) catch {};
    }

    sp -= 8;
    self.write64(sp, 0);

    for (0..arg_addrs.items.len) |i| {
        sp -= 8;
        self.write64(sp, arg_addrs.items[arg_addrs.items.len - 1 - i]);
    }
    const argv_addr = sp;

    sp -= 8;
    const argc_val: u64 = @intCast(args.len);
    self.write64(sp, argc_val);

    sp &= ~@as(u64, 15);
    sp -= 8;

    self.regs.rdi = argc_val;
    self.regs.rsi = argv_addr;
    self.regs.rdx = envp_addr;
    self.regs.rsp = sp;
}

pub fn setupMachOState(self: anytype, path: []const u8, args: []const []const u8) void {
    machoCapturePrint("ROSETTE: setupMachOState called with path: '{s}'\n", .{path});
    machoCapturePrint("ROSETTE: Argument count: {d}\n", .{args.len});
    for (args, 0..) |arg, i| {
        machoCapturePrint("ROSETTE:   argv[{d}] = '{s}'\n", .{ i, arg });
    }

    self.configureGuestLogMirror(args);
    self.launch_options.configure(args);
    var argument_index: usize = 0;
    while (argument_index < args.len) : (argument_index += 1) {
        const argument = args[argument_index];
        if (std.mem.eql(u8, argument, "--storage_root") and argument_index + 1 < args.len) {
            self.fs_forwarder.configurePaths(args[argument_index + 1]);
            break;
        }
        const prefix = "--storage_root=";
        if (std.mem.startsWith(u8, argument, prefix)) {
            self.fs_forwarder.configurePaths(argument[prefix.len..]);
            break;
        }
        if (std.mem.eql(u8, argument, "--fs-fallback") and argument_index + 1 < args.len) {
            self.fs_forwarder.addFallbackRoot(args[argument_index + 1]);
        }
        const fb_prefix = "--fs-fallback=";
        if (std.mem.startsWith(u8, argument, fb_prefix)) {
            self.fs_forwarder.addFallbackRoot(argument[fb_prefix.len..]);
        }
        if (std.mem.eql(u8, argument, "--no-xenia-compat")) {
            self.has_xenia_compat = false;
            machoCapturePrint(
                "macho-processor: Xenia-specific compatibility handlers disabled (--no-xenia-compat)\n",
                .{},
            );
        }
        if (std.mem.eql(u8, argument, "--wall-clock-time")) {
            self.guest_time.time_mode = .wall_clock;
            self.guest_time.captureWallClockBaseline();
            machoCapturePrint(
                "macho-processor: wall-clock time mode enabled (--wall-clock-time)\n",
                .{},
            );
        }
        // Generic alternatives to Xenia-specific --storage_root
        if (std.mem.eql(u8, argument, "--storage-root") and argument_index + 1 < args.len) {
            self.fs_forwarder.configurePaths(args[argument_index + 1]);
            break;
        }
        const sr_prefix = "--storage-root=";
        if (std.mem.startsWith(u8, argument, sr_prefix)) {
            self.fs_forwarder.configurePaths(argument[sr_prefix.len..]);
            break;
        }
        if (std.mem.eql(u8, argument, "--data-dir") and argument_index + 1 < args.len) {
            self.fs_forwarder.configurePaths(args[argument_index + 1]);
            break;
        }
        const dd_prefix = "--data-dir=";
        if (std.mem.startsWith(u8, argument, dd_prefix)) {
            self.fs_forwarder.configurePaths(argument[dd_prefix.len..]);
            break;
        }
        // Generic alternative to Xenia-specific --fs-fallback
        if (std.mem.eql(u8, argument, "--fs-fallback-path") and argument_index + 1 < args.len) {
            self.fs_forwarder.addFallbackRoot(args[argument_index + 1]);
        }
        const fbp_prefix = "--fs-fallback-path=";
        if (std.mem.startsWith(u8, argument, fbp_prefix)) {
            self.fs_forwarder.addFallbackRoot(argument[fbp_prefix.len..]);
        }
    }
    var full_args = std.ArrayList([]const u8).empty;
    defer full_args.deinit(self.allocator);
    full_args.append(self.allocator, path) catch {};
    for (args) |a| full_args.append(self.allocator, a) catch {};

    machoCapturePrint("ROSETTE: Full argv count (including path): {d}\n", .{full_args.items.len});
    machoCapturePrint("ROSETTE: Entry point vaddr: 0x{x}\n", .{self.entry_point_vaddr});

    // Trace range is left unset by default. Set trace_range_start/trace_range_end
    // here (e.g. 0x1332000..0x1333000) to enable target-trace logging for debugging.
    self.last_trace_rip = 0;
    self.last_trace_op = 0;
    self.trace_repeat_count = 0;
    self.setupInitialStack(full_args.items);
    self.regs.rip = self.entry_point_vaddr;

    machoCapturePrint("ROSETTE: setupMachOState complete - RIP set to 0x{x}\n", .{self.regs.rip});
}

pub fn initializerAbi(self: anytype) initialization_resolution.AbiSnapshot {
    return initializers.initializerAbi(self);
}

pub fn beginInitializerTransaction(self: anytype) void {
    initializers.beginInitializerTransaction(self);
}

pub fn rollbackInitializerTransaction(self: anytype) bool {
    return initializers.rollbackInitializerTransaction(self);
}

pub fn commitInitializerTransaction(self: anytype) bool {
    return initializers.commitInitializerTransaction(self);
}

pub fn runOneInitializer(self: anytype, launch_regs: Regs, index: usize, is_retry: bool) InitializerRunOutcome {
    return initializers.runOneInitializer(self, launch_regs, index, is_retry);
}

pub fn runInitializers(self: anytype) bool {
    return initializers.runInitializers(self);
}

pub fn appendTrivialVector(self: anytype, vector: u64, item: u64, element_size: u64, minimum_capacity: u32) bool {
    return initializers.appendTrivialVector(self, vector, item, element_size, minimum_capacity);
}

pub fn handleLibcppBasicStringSubstr(self: anytype) bool {
    return compat_handlers.handleLibcppBasicStringSubstr(self);
}

pub noinline fn handleInternalCompatibility(self: anytype) bool {
    return compat_handlers.handleInternalCompatibility(self);
}

pub fn handlePageEntryBulkInitialization(self: anytype) bool {
    return compat_handlers.handlePageEntryBulkInitialization(self);
}

pub fn handleLocalLibcppStreamCompatibility(self: anytype) bool {
    return compat_handlers.handleLocalLibcppStreamCompatibility(self);
}

pub fn capturePositionalLaunchOptions(self: anytype) void {
    compat_handlers.capturePositionalLaunchOptions(self);
}

pub fn handleGuestLogBridge(self: anytype) bool {
    return compat_handlers.handleGuestLogBridge(self);
}

pub fn handleCxxoptsSplitOptionNames(self: anytype) bool {
    return compat_handlers.handleCxxoptsSplitOptionNames(self);
}

pub noinline fn handleTomlAsciiFastPath(self: anytype) bool {
    return compat_handlers.handleTomlAsciiFastPath(self);
}

pub noinline fn handleTomlReadNextIntegrity(self: anytype) void {
    compat_handlers.handleTomlReadNextIntegrity(self);
}

pub noinline fn handlePatchDbEmptyPatchArray(self: anytype) bool {
    return compat_handlers.handlePatchDbEmptyPatchArray(self);
}

pub fn logStalledInstructionDetails(self: anytype) void {
    compat_handlers.logStalledInstructionDetails(self);
}

pub fn executionFingerprint(self: anytype) u64 {
    var hash: u64 = 0x9e37_79b9_7f4a_7c15;
    const values = [_]u64{
        self.regs.rax,    self.regs.rbx, self.regs.rcx, self.regs.rdx,
        self.regs.rsi,    self.regs.rdi, self.regs.rbp, self.regs.rsp,
        self.regs.r8,     self.regs.r9,  self.regs.r10, self.regs.r11,
        self.regs.r12,    self.regs.r13, self.regs.r14, self.regs.r15,
        self.regs.rflags,
    };
    for (values) |value| {
        hash ^= value +% 0x9e37_79b9_7f4a_7c15 +% (hash << 6) +% (hash >> 2);
    }
    return if (hash == 0) 1 else hash;
}

pub fn executableInstructionBytesAt(self: anytype, address: u64) ?[]const u8 {
    // Dynamically generated x64 code (Xenia's code cache begins at
    // 0xA0000000) lives in sparse mappings rather than self.mem. Fetch
    // from the executable sparse view first so mprotect metadata remains
    // authoritative and reservation-backed JIT pages are decodable.
    // F12 (throughput audit): one descending probe, not sixteen.
    //
    // This used to call `executableBytesConst` with count = 16, 15, 14 …
    // until one succeeded, and each of those calls re-ran `isExecutable`
    // *and* the page-cache probe internally — three page-cache lookups per
    // iteration for a question already answered. The common case cost 3
    // probes instead of 1; near the end of a mapping it degraded to ~48.
    //
    // Halving instead of decrementing bounds the tail at 5 probes while
    // keeping the same result: the longest prefix, up to 16 bytes, that the
    // executable mapping can supply. A shorter slice is always safe — the
    // decoder rejects a truncated instruction rather than misreading one.
    if (self.sparse_memory.isExecutable(address, 1)) {
        var count: u64 = 16;
        while (count > 1) : (count /= 2) {
            if (self.sparse_memory.executableBytesConst(address, count)) |bytes| return bytes;
        }
        return self.sparse_memory.executableBytesConst(address, 1);
    }

    const offset = self.addrToOffset(address) orelse return null;
    if (offset >= self.mem.len) return null;
    const remaining = self.mem.len - @as(usize, @intCast(offset));
    return self.mem[@intCast(offset)..][0..@min(@as(usize, 16), remaining)];
}

pub inline fn translationDomainFor(self: anytype, address: u64) translation_domain.Domain {
    if (address >= self.executable_min and address < self.executable_max) return .static_image;
    if (address >= BOUND_IMPORT_THUNK_BASE or address >= tlv_runtime.bootstrap_thunk) return .thunk_bridge;
    return .dynamic_generated;
}

pub inline fn decodeCacheSetBaseFor(self: anytype, address: u64, domain: translation_domain.Domain) usize {
    _ = self;
    return translation_domain.primarySetBase(address, domain);
}

pub inline fn decodeCacheSetBaseForChoice(
    self: anytype,
    address: u64,
    domain: translation_domain.Domain,
    choice: usize,
) usize {
    _ = self;
    return translation_domain.primarySetBaseChoice(address, domain, choice);
}

pub inline fn decodeCacheSetBasesFor(
    self: anytype,
    address: u64,
    domain: translation_domain.Domain,
) [translation_cache.primary_set_choice_count]usize {
    _ = self;
    return translation_domain.primarySetBases(address, domain);
}

pub inline fn decodeCacheAlternateSetBaseFor(
    self: anytype,
    address: u64,
    domain: translation_domain.Domain,
) usize {
    return self.decodeCacheSetBaseForChoice(address, domain, 1);
}

pub inline fn decodeVictimCacheSetBaseFor(self: anytype, address: u64, domain: translation_domain.Domain) usize {
    _ = self;
    return translation_domain.victimSetBase(address, domain);
}

pub inline fn noteDecodeDomainHit(self: anytype, domain: translation_domain.Domain) void {
    self.decode_domain_hits[domain.bank()] +|= 1;
}

pub inline fn noteDecodeDomainMiss(self: anytype, domain: translation_domain.Domain) void {
    self.decode_domain_misses[domain.bank()] +|= 1;
}

pub inline fn noteDecodeDomainFill(self: anytype, domain: translation_domain.Domain) void {
    self.decode_domain_fills[domain.bank()] +|= 1;
}

pub fn specialRipPossible(self: anytype) bool {
    if (self.special_rip_table_failed) return true; // fallback: run the chain always
    const rip = self.regs.rip;
    // All synthetic/thunk bases live at or above the TLV bootstrap thunk
    // (0xFFFF_F700_0000_0000). One watermark compare replaces the five
    // per-region probes for the overwhelmingly common main-image rip.
    if (rip >= tlv_runtime.bootstrap_thunk) {
        if (rip >= BOUND_IMPORT_THUNK_BASE) return true;
        if (compat_runtime.syntheticThunk(rip) != null) return true;
        if (tlv_runtime.Runtime.handles(rip)) return true;
        if (rip >= dynamic_library_forwarder.GUEST_SYMBOL_THUNK_BASE) {
            const offset = rip - dynamic_library_forwarder.GUEST_SYMBOL_THUNK_BASE;
            if (offset != 0 and offset % 16 == 1 and
                (offset - 1) / 16 < dynamic_library_forwarder.MAX_GUEST_SYMBOLS)
            {
                return true;
            }
        }
        return false;
    }
    if (self.special_rip_table.len != 0 and specialRipTableContains(self.special_rip_table, rip)) return true;
    if (rip >= self.stub_helper_start and rip < self.stub_helper_end) return true;
    if (self.libcpp_stream_target_max != 0 and
        rip >= self.libcpp_stream_target_min and
        rip <= self.libcpp_stream_target_max) return true;
    if (self.config_parsing_active and self.regs.rdi == 0 and
        self.libcxx_streams.latestPatchSchemaHasEmptyPatchSet())
    {
        return true;
    }
    return false;
}

pub fn buildSpecialRipTable(self: anytype) !void {
    var entries: [64]u64 = undefined;
    var count: usize = 0;
    const targets = &self.internal_targets;
    const fixed = [_]u64{
        targets.cxxopts_split_option_names,
        targets.xenia_cpu_feature_detector_initialize_cpu_info,
        targets.xenia_vulkan_provider_vulkan_device,
        targets.parse_launch_arguments,
        targets.initialize_logging,
        targets.shutdown_logging,
        targets.guest_log_get_thread_buffer,
        targets.guest_log_append_formatted,
        targets.guest_log_append_view,
        targets.libcxx_basic_streambuf_pubsetbuf,
        targets.libcxx_basic_ifstream_default_constructor,
        targets.libcxx_basic_ifstream_destructor_1,
        targets.libcxx_basic_ifstream_destructor_2,
        targets.libcxx_getline,
        targets.libcxx_getline_delimiter,
        targets.libcxx_basic_string_substr,
        targets.print_config_to_log,
        targets.imgui_default_malloc,
        targets.imgui_default_free,
        targets.imgui_mem_alloc,
        targets.imgui_mem_free,
        targets.imgui_settings_push_back,
        targets.imgui_create_context,
        targets.imgui_get_current_window,
        targets.imgui_text_ex,
        targets.page_entry_construct_at_end,
    };
    for (fixed) |address| {
        if (address != 0) {
            entries[count] = address;
            count += 1;
        }
    }
    for (targets.cvar_add_to_launch_options[0..targets.cvar_add_to_launch_options_count]) |address| {
        if (address != 0) {
            entries[count] = address;
            count += 1;
        }
    }
    if (self.toml_ascii_entry) |address| {
        entries[count] = address;
        count += 1;
    }
    if (self.toml_read_next_entry) |address| {
        entries[count] = address;
        count += 1;
    }
    // The fixed targets (26) + cvar vector (32) + toml entries (2) bound
    // at 60 < 64. Assert rather than silently truncate: a truncated table
    // would make the gate miss entries and skip handler dispatch with no
    // diagnostic — the exact failure mode a completeness gate must not have.
    std.debug.assert(count <= entries.len);
    std.mem.sort(u64, entries[0..count], {}, std.sort.asc(u64));
    // Deduplicate adjacent equal addresses (multiple conditions may match).
    var write: usize = 0;
    for (entries[0..count]) |address| {
        if (write != 0 and entries[write - 1] == address) continue;
        entries[write] = address;
        write += 1;
    }
    self.special_rip_table = try self.allocator.dupe(u64, entries[0..write]);
    machoCapturePrint(
        "macho-processor: special-RIP table built: entries={d} (R2/N3 single-probe dispatch)\n",
        .{self.special_rip_table.len},
    );
}

pub fn addressNeedsLiveRegisters(decoded: DecodedInsn) bool {
    if (decoded.rip_relative) return false;
    return decoded.sib_has_base or decoded.sib_has_index or
        decoded.segment == .fs or decoded.segment == .gs;
}

pub inline fn noteDecodeCacheUse(ways: []DecodeCacheEntry, used: *DecodeCacheEntry) void {
    if (used.recently_used) return;
    _ = ways;
    used.recently_used = true;
}

pub inline fn noteDecodeCacheReuse(entry: *DecodeCacheEntry) void {
    entry.reuse_count +|= 1;
}

pub inline fn resolveCachedDecode(self: anytype, entry: *const DecodeCacheEntry) DecodedInsn {
    var decoded = entry.decoded;
    if (addressNeedsLiveRegisters(decoded)) {
        const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
        decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
            .displacement = entry.displacement,
            .has_index = decoded.sib_has_index,
            .index_reg = decoded.sib_index_reg,
            .scale = decoded.sib_scale,
            .has_base = decoded.sib_has_base,
            .base_reg = decoded.sib_base_reg,
            .rip_relative = decoded.rip_relative,
            .segment = decoded.segment,
        }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
    }
    return decoded;
}

pub inline fn decodeCacheEntryOccupied(entry: *const DecodeCacheEntry) bool {
    return entry.rip != std.math.maxInt(u64) and entry.instruction_byte_count != 0;
}

pub fn sampleBankOccupancy(self: anytype, domain: translation_domain.Domain) BankOccupancy {
    const layout = translation_cache.primary_layout;
    const local_sets = layout.localSetCount(domain);
    const first_set = layout.bankFirstSet(domain);
    const stride: usize = 64;
    var result = BankOccupancy{
        .capacity = local_sets * layout.ways,
        .sampled_sets = 0,
        .sampled_entries = 0,
        .occupied = 0,
    };
    var local: usize = 0;
    while (local < local_sets) : (local += stride) {
        const set_base = (first_set + local) * layout.ways;
        if (set_base + layout.ways > self.decode_cache.len) break;
        for (self.decode_cache[set_base..][0..layout.ways]) |*entry| {
            if (decodeCacheEntryOccupied(entry)) result.occupied += 1;
        }
        result.sampled_sets += 1;
        result.sampled_entries += layout.ways;
    }
    return result;
}

pub fn selectDecodeCacheWay(ways: []DecodeCacheEntry) DecodeCacheSelection {
    var states: [translation_cache.max_replacement_ways]translation_cache.ReplacementState = undefined;
    if (ways.len > states.len) unreachable;
    for (ways, 0..) |candidate, index| {
        states[index] = .{
            .occupied = decodeCacheEntryOccupied(&candidate),
            .recently_used = candidate.recently_used,
            .reuse_count = candidate.reuse_count,
        };
    }
    const choice = translation_cache.chooseReplacement(states[0..ways.len]) orelse unreachable;
    if (choice.reset_reference_bits) {
        for (ways) |*candidate| candidate.recently_used = false;
    }
    return .{
        .entry = &ways[choice.index],
        .empty = choice.empty,
    };
}

pub fn selectPrimaryDecodeCacheSet(
    self: anytype,
    set_bases: [translation_cache.primary_set_choice_count]usize,
) PrimaryDecodeCacheSelection {
    var candidates: [translation_cache.primary_set_choice_count]translation_cache.SetOccupancy = undefined;
    var any_free = false;
    for (set_bases, 0..) |set_base, index| {
        const ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        var occupied: usize = 0;
        for (ways) |*candidate| {
            if (decodeCacheEntryOccupied(candidate)) occupied += 1;
        }
        candidates[index] = .{ .occupied = occupied, .ways = ways.len };
        if (occupied < ways.len) any_free = true;
    }
    if (any_free) {
        const index = translation_cache.chooseSet(&candidates) orelse unreachable;
        const set_base = set_bases[index];
        const ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        const choice = selectDecodeCacheWay(ways);
        return .{ .entry = choice.entry, .empty = choice.empty, .set_base = set_base };
    }
    // Every choice is full. Only now is the replacement policy worth
    // running on both sets, and only now is the working set genuinely
    // over capacity — which is the condition strict policy exists to stop
    // on, so nothing here tries to soften it.
    var victims: [translation_cache.primary_set_choice_count]*DecodeCacheEntry = undefined;
    for (set_bases, 0..) |set_base, index| {
        const ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        const choice = selectDecodeCacheWay(ways);
        victims[index] = choice.entry;
        candidates[index].victim_reuse_count = choice.entry.reuse_count;
        candidates[index].victim_recently_used = choice.entry.recently_used;
    }
    const index = translation_cache.chooseSet(&candidates) orelse unreachable;
    return .{ .entry = victims[index], .empty = false, .set_base = set_bases[index] };
}

pub fn saveStaticDecodeL2(self: anytype, source: *const DecodeCacheEntry) void {
    if (source.domain != .static_image or !decodeCacheEntryOccupied(source)) return;
    const set_base = translation_cache.staticL2SetBase(source.rip);
    const ways = self.static_decode_l2[set_base..][0..constants.DECODE_STATIC_L2_WAYS];
    var selected: ?*DecodeCacheEntry = null;
    for (ways) |*candidate| {
        if (candidate.rip == source.rip) {
            selected = candidate;
            break;
        }
    }
    if (selected == null) selected = selectDecodeCacheWay(ways).entry;
    selected.?.* = source.*;
    selected.?.recently_used = false;
    self.static_decode_l2_fills +|= 1;
}

pub fn restoreStaticDecodeL2(
    self: anytype,
    fetch_address: u64,
    primary_ways: []DecodeCacheEntry,
) ?DecodedInsn {
    if (self.translationDomainFor(fetch_address) != .static_image) return null;
    const set_base = translation_cache.staticL2SetBase(fetch_address);
    const ways = self.static_decode_l2[set_base..][0..constants.DECODE_STATIC_L2_WAYS];
    for (ways) |*candidate| {
        if (candidate.rip != fetch_address or candidate.domain != .static_image) continue;
        if (!decodeCacheEntryOccupied(candidate)) {
            candidate.* = .{};
            continue;
        }
        const selection = selectDecodeCacheWay(primary_ways);
        if (!selection.empty) self.saveDecodeCacheVictim(selection.entry);
        selection.entry.* = candidate.*;
        selection.entry.code_generation = self.code_generation;
        selection.entry.recently_used = true;
        noteDecodeCacheUse(ways, candidate);
        noteDecodeCacheReuse(candidate);
        noteDecodeCacheReuse(selection.entry);
        self.static_decode_l2_hits +|= 1;
        self.decode_cache_hits +|= 1;
        self.noteDecodeDomainHit(.static_image);
        return self.resolveCachedDecode(selection.entry);
    }
    return null;
}

pub fn invalidateStaticDecodeL2Range(self: anytype, address: u64, count: u64) void {
    if (count == 0 or self.static_decode_l2.len == 0) return;
    const end = address +| count;
    for (self.static_decode_l2) |*entry| {
        if (!decodeCacheEntryOccupied(entry)) continue;
        const instruction_length = @max(@as(u64, entry.decoded.len), 1);
        const instruction_end = entry.rip +| instruction_length;
        if (entry.rip < end and instruction_end > address) entry.* = .{};
    }
}

pub fn saveDecodeCacheVictim(self: anytype, evicted: *const DecodeCacheEntry) void {
    if (!decodeCacheEntryOccupied(evicted)) return;
    const set_base = self.decodeVictimCacheSetBaseFor(evicted.rip, evicted.domain);
    const ways = self.decode_victim_cache[set_base..][0..constants.DECODE_VICTIM_CACHE_WAYS];
    var selected: ?*DecodeCacheEntry = null;
    for (ways) |*candidate| {
        if (candidate.rip == evicted.rip) {
            selected = candidate;
            break;
        }
    }
    if (selected == null) selected = selectDecodeCacheWay(ways).entry;
    selected.?.* = evicted.*;
    // The entry has just moved tiers. Require one real secondary hit before
    // it is protected from another victim insertion.
    selected.?.recently_used = false;
    self.decode_cache_victim_fills +|= 1;
}

pub fn restoreDecodeCacheVictim(
    self: anytype,
    fetch_address: u64,
    destination: *DecodeCacheEntry,
) ?DecodedInsn {
    const domain = self.translationDomainFor(fetch_address);
    const set_base = self.decodeVictimCacheSetBaseFor(fetch_address, domain);
    const ways = self.decode_victim_cache[set_base..][0..constants.DECODE_VICTIM_CACHE_WAYS];
    for (ways) |*candidate| {
        if (candidate.rip != fetch_address or candidate.domain != domain) continue;
        if (candidate.instruction_byte_count == 0) {
            candidate.* = .{};
            continue;
        }
        if (candidate.code_generation != self.code_generation) {
            const current_bytes = self.executableInstructionBytesAt(fetch_address) orelse return null;
            if (current_bytes.len < candidate.instruction_byte_count or
                !std.mem.eql(
                    u8,
                    candidate.instruction_bytes[0..candidate.instruction_byte_count],
                    current_bytes[0..candidate.instruction_byte_count],
                ))
            {
                candidate.* = .{};
                self.decode_cache_victim_stale_rejections +|= 1;
                return null;
            }
            candidate.code_generation = self.code_generation;
        }

        const displaced = destination.*;
        destination.* = candidate.*;
        candidate.* = displaced;
        candidate.recently_used = false;
        destination.recently_used = true;
        noteDecodeCacheReuse(destination);
        self.decode_cache_hits +|= 1;
        self.noteDecodeDomainHit(domain);
        self.decode_cache_victim_hits +|= 1;
        return self.resolveCachedDecode(destination);
    }
    return null;
}

pub inline fn decodeFastPlain(self: anytype) ?FastPlainDecode {
    const rip = self.regs.rip;
    const domain = self.translationDomainFor(rip);
    const set_bases = self.decodeCacheSetBasesFor(rip, domain);
    for (set_bases) |set_base| {
        const ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        for (ways) |*candidate| {
            if (candidate.rip == rip and candidate.domain == domain and
                candidate.code_generation == self.code_generation and
                candidate.fast_plain)
            {
                self.decode_cache_hits +|= 1;
                self.noteDecodeDomainHit(domain);
                noteDecodeCacheUse(ways, candidate);
                noteDecodeCacheReuse(candidate);
                var decoded = candidate.decoded;
                if (addressNeedsLiveRegisters(decoded)) {
                    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
                    decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                        .displacement = candidate.displacement,
                        .has_index = decoded.sib_has_index,
                        .index_reg = decoded.sib_index_reg,
                        .scale = decoded.sib_scale,
                        .has_base = decoded.sib_has_base,
                        .base_reg = decoded.sib_base_reg,
                        .rip_relative = decoded.rip_relative,
                        .segment = decoded.segment,
                    }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
                }
                return .{ .decoded = decoded, .host_image = candidate.host_image };
            }
        }
    }
    return null;
}

pub fn decodeWithLiveOperands(self: anytype, gates_free: bool) ?DecodedInsn {
    // F17 (throughput audit): CS has no base in long mode — `segmentBase`
    // returns 0 for every segment but FS and GS (see addressing.zig). The
    // call was two compares and a load per instruction to add zero.
    const fetch_address = self.regs.rip;
    // Set-associative lookup with two independently hashed choices.
    // Direct-mapped, two hot instructions whose addresses hash together
    // evicted each other on every execution and never recovered — a
    // permanent conflict miss for code that is otherwise perfectly
    // cacheable. The sibling choice lets a usable set absorb an unlucky
    // bucket without relaxing the fail-fast rule for a genuinely full
    // working set. Sixteen ways still keeps rare same-set startup bursts
    // from displacing a reusable immutable decode.
    const domain = self.translationDomainFor(fetch_address);
    const set_bases = self.decodeCacheSetBasesFor(fetch_address, domain);
    var set_base: usize = set_bases[0];
    var ways: []DecodeCacheEntry = undefined;
    var entry: *DecodeCacheEntry = undefined;
    var main_entry_found = false;
    for (set_bases) |candidate_set_base| {
        const candidate_ways = self.decode_cache[candidate_set_base..][0..constants.DECODE_CACHE_WAYS];
        for (candidate_ways) |*candidate| {
            if (candidate.rip == fetch_address and candidate.domain == domain) {
                entry = candidate;
                ways = candidate_ways;
                set_base = candidate_set_base;
                main_entry_found = true;
                break;
            }
        }
        if (main_entry_found) break;
    }
    var selected: ?PrimaryDecodeCacheSelection = null;
    if (!main_entry_found) {
        const destination = self.selectPrimaryDecodeCacheSet(set_bases);
        selected = destination;
        entry = destination.entry;
        set_base = destination.set_base;
        ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        if (self.restoreDecodeCacheVictim(fetch_address, entry)) |decoded| return decoded;
        if (self.restoreStaticDecodeL2(fetch_address, ways)) |decoded| return decoded;
    }
    // P0-2 (perf audit): generation-keyed fast path. Every executable
    // write bumps self.code_generation (noteGuestWrite) and precisely
    // clears overlapping entries, so a matching generation proves no
    // executable write touched this address since the entry was
    // populated — the cached decode is valid without re-fetching and
    // byte-comparing the source. Only when the generation moved (e.g. a
    // non-overlapping JIT write elsewhere) fall back to the byte check,
    // and re-arm the generation on a confirmed match so the next hit
    // takes the fast path again.
    if (entry.rip == fetch_address and entry.code_generation == self.code_generation) {
        self.decode_cache_hits +|= 1;
        self.noteDecodeDomainHit(domain);
        noteDecodeCacheUse(ways, entry);
        noteDecodeCacheReuse(entry);
        var decoded = entry.decoded;
        if (addressNeedsLiveRegisters(decoded)) {
            const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
            decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                .displacement = entry.displacement,
                .has_index = decoded.sib_has_index,
                .index_reg = decoded.sib_index_reg,
                .scale = decoded.sib_scale,
                .has_base = decoded.sib_has_base,
                .base_reg = decoded.sib_base_reg,
                .rip_relative = decoded.rip_relative,
                .segment = decoded.segment,
            }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
        }
        return decoded;
    }
    // Executable writes invalidate overlapping entries at the shared
    // memory-write boundary. Do not globally discard unrelated decoded
    // host/Xenia instructions whenever the JIT emits a new block.
    const fetched_bytes = if (entry.rip == fetch_address)
        self.executableInstructionBytesAt(fetch_address)
    else
        null;
    const cached_bytes_match = if (fetched_bytes) |current_bytes|
        entry.instruction_byte_count != 0 and
            current_bytes.len >= entry.instruction_byte_count and
            std.mem.eql(
                u8,
                entry.instruction_bytes[0..entry.instruction_byte_count],
                current_bytes[0..entry.instruction_byte_count],
            )
    else
        false;
    if (entry.rip == fetch_address and cached_bytes_match) {
        self.decode_cache_hits +|= 1;
        self.noteDecodeDomainHit(domain);
        noteDecodeCacheUse(ways, entry);
        noteDecodeCacheReuse(entry);
        entry.code_generation = self.code_generation;
        var decoded = entry.decoded;
        if (addressNeedsLiveRegisters(decoded)) {
            const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
            decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                .displacement = entry.displacement,
                .has_index = decoded.sib_has_index,
                .index_reg = decoded.sib_index_reg,
                .scale = decoded.sib_scale,
                .has_base = decoded.sib_has_base,
                .base_reg = decoded.sib_base_reg,
                .rip_relative = decoded.rip_relative,
                .segment = decoded.segment,
            }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
        }
        return decoded;
    }
    var stale_rejected = false;
    if (entry.rip == fetch_address) {
        // Never execute a cached decode whose source bytes changed. This
        // catches JIT publication paths that did not pass through the
        // normal guest write boundary without flushing unrelated code.
        self.decode_cache_stale_rejections +|= 1;
        stale_rejected = true;
        entry.* = .{};
    }
    self.decode_cache_misses +|= 1;
    self.noteDecodeDomainMiss(domain);
    // Select the victim before recording economics: this is the only point
    // where the runtime can prove vacancy versus eviction. A byte mismatch
    // takes precedence because it proves executable mutation even though
    // clearing the stale entry also creates a vacant way.
    const selection = selected orelse blk: {
        const choice = selectDecodeCacheWay(ways);
        break :blk PrimaryDecodeCacheSelection{
            .entry = choice.entry,
            .empty = choice.empty,
            .set_base = set_base,
        };
    };
    entry = selection.entry;
    set_base = selection.set_base;
    const victim_is_empty = selection.empty;
    const victim_was_reused = !victim_is_empty and entry.reuse_count != 0;
    if (!victim_is_empty) {
        // The displaced decode is about to be overwritten. Both secondary
        // tiers are populated here, at the one point where a decode is
        // genuinely leaving the primary and a later lookup could need it
        // back without paying for the decoder again.
        self.saveDecodeCacheVictim(entry);
        self.saveStaticDecodeL2(entry);
    }
    if (victim_is_empty) {
        self.decode_cache_vacant_misses +|= 1;
    } else if (victim_was_reused) {
        self.decode_cache_conflict_misses +|= 1;
    } else {
        self.decode_cache_cold_eviction_misses +|= 1;
    }
    const fill_cause: translation_economics.Cause = if (stale_rejected)
        .stale_bytes
    else if (victim_is_empty)
        .vacant_fill
    else if (victim_was_reused)
        .capacity_conflict
    else
        .cold_eviction;
    const bytes = fetched_bytes orelse self.executableInstructionBytesAt(fetch_address) orelse return null;
    // Economics describes cache fills, not failed fetch attempts. Keep the
    // proven cause local until source bytes exist and a decode can actually
    // be installed in the selected way.
    self.translation_economics.noteDecode(fetch_address, self.executed_steps, fill_cause);
    const cache_way = (@intFromPtr(entry) - @intFromPtr(ways.ptr)) / @sizeOf(DecodeCacheEntry);
    self.failFastOnTranslationCause(
        fetch_address,
        domain,
        fill_cause,
        set_base,
        cache_way,
        entry,
        victim_is_empty,
        victim_was_reused,
        stale_rejected,
        bytes,
    );
    self.noteDecodeDomainFill(domain);
    var decoded = decodeInsn(bytes);
    if (decoded.op == .invalid and self.sparse_memory.containsMapped(fetch_address, 1)) {
        decoded = decodeInsnCompat(bytes);
    }
    const prefixes = x64_decoder.decodeLegacyPrefixes(bytes);
    decoded.has_0x67 = prefixes.address_size_override;
    // F5 (throughput audit): resolve LOCK here, once, instead of in
    // `execute` on every instruction.
    //
    // `execute` used to re-read the byte at RIP through `guestMemoryConst`
    // — a full guest address translation, sparse probe included — purely to
    // test for 0xF0, on every interpreted instruction. The prefix scan
    // above already has the answer and the result is cached with the rest
    // of the decode.
    //
    // It is also more correct. The old test looked only at `bytes[0]`, so a
    // LOCK that followed a segment or operand-size override, or that sat
    // before a REX byte, was missed. `decodeLegacyPrefixes` walks the whole
    // prefix run. `or` rather than `=` because several decode paths already
    // set `lock` themselves.
    decoded.lock = decoded.lock or prefixes.lock;
    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
    const base_register: ?RegId = if (decoded.sib_has_base) decoded.sib_base_reg else null;
    decoded.segment = x64_decoder.selectSegment(.explicit_data, base_register, prefixes.segment_override);
    const raw_displacement = decoded.addr;
    if (!hasRelativeControlDisplacement(decoded.op)) {
        decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
            .displacement = raw_displacement,
            .has_index = decoded.sib_has_index,
            .index_reg = decoded.sib_index_reg,
            .scale = decoded.sib_scale,
            .has_base = decoded.sib_has_base,
            .base_reg = decoded.sib_base_reg,
            .rip_relative = decoded.rip_relative,
            .segment = decoded.segment,
        }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
    }
    const instruction_byte_count: u8 = @intCast(@min(
        @as(usize, @max(decoded.len, 1)),
        @min(bytes.len, @as(usize, 15)),
    ));
    entry.* = .{
        .rip = fetch_address,
        .domain = domain,
        .code_generation = self.code_generation,
        .decoded = decoded,
        .displacement = raw_displacement,
        .instruction_byte_count = instruction_byte_count,
        // The fast path is only sound for a fill that ran the validation
        // gate chain and saw it decline. `gates_free` already means the
        // special-RIP chain declined and the address was executable; the
        // config-parsing clause is monotone (it only ever turns off), and
        // the special-RIP table, once built, never changes — so the extra
        // guards below are belt-and-suspenders that keep startup and the
        // failed-table fallback on the slow path without needing to
        // reason about either invariant.
        .fast_plain = gates_free and
            !self.config_parsing_active and
            !self.special_rip_table_failed,
        // Computed here, once per fill, so the execution-history filter can
        // classify this instruction with one load on later hits instead of
        // re-running the range compare on every step.
        .host_image = fetch_address >= self.executable_min and
            fetch_address < self.executable_max,
    };
    // F4: this page now holds a cached decode, so a later store into it has
    // to run the invalidation walk. Noted for the instruction's whole
    // extent, because a store to its last byte must still find it.
    noteDecodeCacheUse(ways, entry);
    self.decode_cache_pages.note(fetch_address);
    self.decode_cache_pages.note(fetch_address +| (@as(u64, instruction_byte_count) -| 1));
    @memcpy(
        entry.instruction_bytes[0..instruction_byte_count],
        bytes[0..instruction_byte_count],
    );
    return decoded;
}

pub noinline fn reportDecodeFailure(self: anytype) bool {
    if (self.terminated) return false;
    const rip = self.regs.rip;
    machoCapturePrint("macho-processor: decode failed at rip=0x{x}\n", .{rip});
    if (self.sparse_memory.containsMapped(rip, 1)) {
        const bytes = self.executableInstructionBytesAt(rip) orelse
            self.sparse_memory.bytesConst(rip, 1) orelse &.{};
        machoCapturePrint(
            "macho-processor: decode failed in sparse generated-code mapping: mapped=true executable={} readable={} bytes={any}; this is not an unmapped Mach-O address\n",
            .{
                self.sparse_memory.isExecutable(rip, 1),
                self.sparse_memory.bytesConst(rip, 1) != null,
                bytes,
            },
        );
    } else if (self.fileOffsetForVaddr(rip)) |file_off| {
        const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
        const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
        machoCapturePrint("macho-processor: decode failed file_offset=0x{x} bytes={any}\n", .{ file_off, file_bytes });
    } else {
        machoCapturePrint("macho-processor: decode failed at unmapped address\n", .{});
    }
    self.faulted = true;
    self.exit_code = 127;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.decode_failed);
    self.terminated = true;
    return false;
}

pub noinline fn emitTargetTrace(self: anytype, decoded: DecodedInsn) void {
    const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
    const trace_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
    const trace_key = self.regs.rip;
    const op_key = @intFromEnum(decoded.op);
    if (trace_key == self.last_trace_rip and op_key == self.last_trace_op) {
        self.trace_repeat_count +|= 1;
        return;
    }
    if (self.trace_repeat_count > 0) {
        log.info("target-trace: previous trace repeated {d} times", .{self.trace_repeat_count + 1});
    }
    self.last_trace_rip = trace_key;
    self.last_trace_op = op_key;
    self.trace_repeat_count = 0;
    log.info("target-trace: rip=0x{x} op={s} len={d} bytes={any} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
        self.regs.rip,
        @tagName(decoded.op),
        decoded.len,
        trace_bytes,
        self.regs.rsp,
        self.regs.rax,
        self.regs.rcx,
        self.regs.rdx,
    });
}

pub noinline fn reportCoopBootstrapComplete(self: anytype) void {
    self.coop_bootstrap_active = false;
    const first = &self.coop_bootstrap_entries[0];
    const last = &self.coop_bootstrap_entries[23];
    const symbol = self.metadata.nearestSymbol(first.rip);
    machoCapturePrint(
        "macho-processor: GTK worker bootstrapping successful: thread=0x{x} first_rip=0x{x} last_rip=0x{x} first_symbol={s}\n",
        .{
            first.thread,                                    first.rip, last.rip,
            self.metadata.symbolLabelFor(symbol, first.rip),
        },
    );
}

pub noinline fn recoverNonExecutableRip(self: anytype) bool {
    if (self.pending_control_transfer) |context| {
        // Generated code dispatching to an unpatched Xenia indirection
        // sentinel (a guest-module address) is the same recoverable
        // code-cache miss as a null function pointer: skip the
        // transfer and keep the run alive. The target poll below runs
        // only at this terminal raise site, never on the hot path.
        // Only recover when the failed RIP is exactly the transfer
        // target: a stale pending context (from an earlier transfer
        // that was never consulted) must not hijack an unrelated
        // non-executable RIP.
        if (context.target_address == self.regs.rip and
            memory_access.tryRecoverGeneratedGuestDispatchMiss(self, context, context.return_address != 0))
        {
            return true;
        }
        memory_access.dumpGuestDispatchTargetPoll(self, self.regs.rip);
        memory_access.logNonExecutableTarget(self, self.regs.rip, context);
        self.terminateForInvalidControlTransfer(context);
        self.dumpRecentTrace();
        return false;
    }
    memory_access.dumpGuestDispatchTargetPoll(self, self.regs.rip);
    memory_access.logNonExecutableTarget(self, self.regs.rip, null);
    machoCapturePrint(
        "macho-processor: invalid control-flow target rip=0x{x}; address is not an executable instruction target\n",
        .{self.regs.rip},
    );
    self.dumpRecentTrace();
    self.faulted = true;
    self.exit_code = 127;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
    self.terminated = true;
    return false;
}

pub noinline fn reportInvalidInstruction(self: anytype) bool {
    const mem_bytes = self.executableInstructionBytesAt(self.regs.rip) orelse &.{};
    const rip = self.regs.rip;
    if (self.addrToOffset(rip)) |mem_off| {
        machoCapturePrint("macho-processor: invalid instruction at rip=0x{x}, mem_off=0x{x}, bytes: {any}\n", .{ rip, mem_off, mem_bytes });
    } else if (self.sparse_memory.containsMapped(rip, 1)) {
        machoCapturePrint("macho-processor: invalid instruction in sparse generated code at rip=0x{x}, bytes: {any}\n", .{ rip, mem_bytes });
    } else {
        machoCapturePrint("macho-processor: invalid instruction at unmapped rip=0x{x}, bytes: {any}\n", .{ rip, mem_bytes });
    }
    if (x64_decoder.capabilities.classifyRequirement(mem_bytes)) |requirement| {
        machoCapturePrint(
            "macho-processor: ISA requirement: {s} encoding requires {s}; virtual profile={s}, advertised={}\n",
            .{
                @tagName(requirement.encoding),
                x64_decoder.capabilities.featureLabel(requirement.feature),
                self.cpu_profile.label(),
                x64_decoder.capabilities.supports(self.cpu_profile, requirement.feature),
            },
        );
    }
    if (self.fileOffsetForVaddr(rip)) |file_off| {
        const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
        const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
        machoCapturePrint("macho-processor: invalid instruction source-map: rip=0x{x} file_off=0x{x} file_bytes={any}\n", .{ rip, file_off, file_bytes });
    } else {
        machoCapturePrint("macho-processor: invalid instruction source-map: rip=0x{x} file_off=<unmapped>\n", .{rip});
    }
    // Whose defect is this? The decoder returns `invalid` both for bytes
    // that are not an x86-64 instruction and for a real instruction it has
    // not implemented, and the two call for opposite handling.
    //
    // A genuine bad encoding earns a guest #UD: that is what the hardware
    // would raise, and the title's own handler is entitled to it. A real
    // instruction Rosette merely lacks must never be delivered that way —
    // real hardware would have executed it, so handing the guest a #UD
    // tells it its own code is invalid, and a handler that swallows the
    // signal carries on with the instruction's effect silently missing.
    // That is the run continuing on a lie, which is worse than stopping.
    const encoding_class = x64_decoder.coverage.classifyEncoding(mem_bytes);
    const rosette_gap = encoding_class == .refused;
    machoCapturePrint(
        "macho-processor: invalid instruction class={s} owner={s}; {s}\n",
        .{
            encoding_class.label(),
            if (rosette_gap) "rosette:decoder" else "guest:code",
            if (rosette_gap)
                "the opcode census recognises this slot as a real user-mode-reachable instruction, so this is a decoder coverage gap and the run stops here. Delivering #UD would tell the title its own instruction is invalid and let a handler carry on without its effect"
            else
                "this encoding is not a user-mode-reachable x86-64 instruction, so a guest #UD is the architecturally correct answer rather than a Rosette gap",
        },
    );
    self.dumpStepTraceBuffer();
    self.dumpCoopBootstrapTrace();
    self.dumpMemInitTrace();
    self.dumpCoopHeartbeatTrace();
    self.dumpUiHandoffTrace();
    self.dumpRecentTrace();
    if (!rosette_gap and
        self.deliverGuestSignal(GUEST_SIGILL, self.regs.rip, 1, self.regs.rip, null, 0, mem_bytes))
    {
        return true;
    }
    self.faulted = true;
    self.exit_code = 127;
    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
    self.terminated = true;
    return false;
}

pub fn observeApplicationControlTransfer(self: anytype, decoded: DecodedInsn, source: u64) void {
    if (!self.application_framework.controlFlowTracingEnabled()) return;
    if (!isApplicationControlFlow(decoded.op)) return;

    const fallthrough = source +% decoded.len;
    const target = self.regs.rip;
    self.application_framework.observeControlTransfer(
        .guest,
        source,
        target,
        self.executed_steps,
        self.active_guest_thread,
        !self.terminated and target != fallthrough,
        @tagName(decoded.op),
    );
}
