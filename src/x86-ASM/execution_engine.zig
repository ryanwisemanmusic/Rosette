const std = @import("std");
const isa = @import("instruction_set.zig");
const Opcode = isa.Opcode;
const Register = isa.Register;
const InstructionDef = isa.InstructionDef;
const INSTRUCTION_SIZE = isa.INSTRUCTION_SIZE;
const Executor = @import("instruction_operations.zig").Executor;
const raw_decode = @import("raw_decoder.zig");
const trace = @import("instruction_trace.zig");
const runtime_abi = @import("runtime_abi_handshake");
const traps = runtime_abi.traps;
const code_text = @import("entrypoint_code_text_segment");
const reg_trace = @import("register-tracing/runtime.zig");
const stack_trace = @import("stack/runtime.zig");
const decode_trace = @import("instruction-decoding/runtime.zig");
const exception_trace = @import("exceptions/runtime.zig");
const reg_map = @import("register_mapping.zig");
const highway = isa.isa_registry.highway;

pub const ThunkHandler = *const fn (*Executor) void;

pub const ThunkTable = struct {
    handlers: [64]?ThunkHandler = [_]?ThunkHandler{null} ** 64,

    pub fn set(self: *ThunkTable, id: usize, handler: ThunkHandler) void {
        self.handlers[id] = handler;
    }

    pub fn call(self: *ThunkTable, id: usize, ex: *Executor) void {
        if (self.handlers[id]) |h| h(ex);
    }
};

/// Registered IAT entries for import dispatch.
/// Maps absolute memory address → function name (e.g. "_SetConsoleTextAttribute@8").
const MAX_IAT_ENTRIES = 2048;
var iat_addrs: [MAX_IAT_ENTRIES]u32 = [_]u32{0} ** MAX_IAT_ENTRIES;
var iat_names: [MAX_IAT_ENTRIES][]const u8 = [_][]const u8{undefined} ** MAX_IAT_ENTRIES;
var iat_count: u32 = 0;

pub fn clearIatEntries() void {
    iat_count = 0;
}

pub fn addIatEntry(addr: u32, name: []const u8) void {
    if (iat_count >= MAX_IAT_ENTRIES) return;
    const idx = iat_count;
    iat_count += 1;
    iat_addrs[idx] = addr;
    iat_names[idx] = name;
}

fn lookupIatEntry(addr: u32) ?[]const u8 {
    var i: u32 = 0;
    while (i < iat_count) : (i += 1) {
        if (iat_addrs[i] == addr) return iat_names[i];
    }
    return null;
}

const max_opcode = @intFromEnum(Opcode.exit);

fn stopFetchFault(ex: *Executor, start_eip: u32, reason: []const u8) bool {
    ex.regs.pending_exception = traps.pendingException(.BadInstructionPointer);
    runtime_abi.common.trapViolation(
        .BadInstructionPointer,
        "x86-raw-pe",
        "instruction_fetch",
        "eip=0x{x} base=0x{x} len={d} reason={s}",
        .{ start_eip, ex.mem.base, ex.mem.data.len, reason },
    );
    return false;
}

fn logBadInstructionPointer(scope: []const u8, source_eip: u32, target_eip: u32, guard: code_text.Guard, check: code_text.CheckResult) void {
    if (code_text.rvaToVaIfInImage(guard, target_eip)) |va| {
        runtime_abi.common.trapViolation(
            .BadInstructionPointer,
            "x86-raw-pe",
            "eip_text_segment",
            "{s}: source_eip=0x{x} target_eip=0x{x} status={s} reason=\"{s}\" image=[0x{x}..0x{x}] rva_hint_va=0x{x}",
            .{ scope, source_eip, target_eip, @tagName(check.status), code_text.statusDescription(check.status), guard.image_base, guard.imageEnd(), va },
        );
        return;
    }
    runtime_abi.common.trapViolation(
        .BadInstructionPointer,
        "x86-raw-pe",
        "eip_text_segment",
        "{s}: source_eip=0x{x} target_eip=0x{x} status={s} reason=\"{s}\" image=[0x{x}..0x{x}]",
        .{ scope, source_eip, target_eip, @tagName(check.status), code_text.statusDescription(check.status), guard.image_base, guard.imageEnd() },
    );
}

fn stopBadInstructionPointer(ex: *Executor, source_eip: u32, target_eip: u32, scope: []const u8, check: code_text.CheckResult) bool {
    ex.regs.eip = target_eip;
    ex.regs.pending_exception = traps.pendingException(.BadInstructionPointer);
    exception_trace.logFault(scope, .invalid_opcode, 6, target_eip, target_eip, target_eip, &ex.regs);
    logBadInstructionPointer(scope, source_eip, target_eip, ex.codeTextGuard(), check);
    return false;
}

fn validateControlTransferTarget(ex: *Executor, source_eip: u32, target_eip: u32, scope: []const u8) bool {
    const guard = ex.codeTextGuard();
    const check = code_text.checkInstructionPointer(guard, target_eip, 1);
    if (check.isValid()) return true;
    return stopBadInstructionPointer(ex, source_eip, target_eip, scope, check);
}

fn readRawRm32(ex: *Executor, operand: raw_decode.Rm32) ?u32 {
    return switch (operand) {
        .reg => |reg| ex.regs.get(reg),
        .mem => |mem| blk: {
            const addr = mem.resolve(&ex.regs) orelse return null;
            break :blk ex.mem.read32(addr);
        },
    };
}

fn resolveRawMemAddr(operand: raw_decode.Rm32, regs: *const reg_map.RegisterFile) ?u32 {
    return switch (operand) {
        .mem => |mem| mem.resolve(regs),
        else => null,
    };
}

fn dispatchIatCall(ex: *Executor, start_eip: u32, iat_addr: u32, name: []const u8, next_eip: u32) bool {
    if (ex.import_table.get(name) == null) return false;
    reg_trace.logControlTransfer("iat_call", start_eip, iat_addr, &ex.regs);
    stack_trace.logState("before_iat_call", .before_call, &ex.regs, &ex.mem);
    ex.push(next_eip);
    stack_trace.logState("after_iat_call_push", .after_call, &ex.regs, &ex.mem);
    const ret_addr = ex.regs.pop(&ex.mem);
    ex.dispatch_import(name);
    if (ex.terminated) return false;
    stack_trace.logState("after_iat_thunk", .after_call, &ex.regs, &ex.mem);
    ex.regs.eip = ret_addr;
    return true;
}

fn dispatchIatJmp(ex: *Executor, iat_addr: u32, name: []const u8) bool {
    if (ex.import_table.get(name) == null) return false;
    reg_trace.logControlTransfer("iat_jmp", 0, iat_addr, &ex.regs);
    stack_trace.logState("before_iat_jmp", .before_call, &ex.regs, &ex.mem);
    const ret_addr = ex.regs.pop(&ex.mem);
    ex.dispatch_import(name);
    if (ex.terminated) return false;
    stack_trace.logState("after_iat_jmp", .after_call, &ex.regs, &ex.mem);
    ex.regs.eip = ret_addr;
    return true;
}

fn stopRawUnsupported(ex: *Executor, start_eip: u32, decoded: raw_decode.DecodedInstruction, reason: []const u8) bool {
    ex.regs.pending_exception = traps.pendingException(.UnsupportedInstruction);
    exception_trace.logFault("raw-x86-unsupported", .invalid_opcode, 6, decoded.opcode, start_eip, start_eip, &ex.regs);
    runtime_abi.common.trapViolation(
        .UnsupportedInstruction,
        "x86-raw-pe",
        "unsupported_instruction",
        "eip=0x{x} instruction={s} isa={s} reason={s}",
        .{ start_eip, decoded.textSlice(), decoded.isa_path, reason },
    );
    return false;
}

fn executeRawDecoded(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    const next_eip = start_eip + @as(u32, decoded.len);
    switch (decoded.op) {
        .nop => {},
        .ret => {
            const target = ex.mem.read32(ex.regs.esp);
            reg_trace.logControlTransfer("ret", start_eip, target, &ex.regs);
            stack_trace.logState("before_raw_ret", .before_call, &ex.regs, &ex.mem);
            ex.regs.eip = ex.regs.pop(&ex.mem);
            stack_trace.logState("after_raw_ret", .after_call, &ex.regs, &ex.mem);
            return validateControlTransferTarget(ex, start_eip, ex.regs.eip, "ret");
        },
        .jmp_rel => {
            reg_trace.logControlTransfer("jmp", start_eip, decoded.target, &ex.regs);
            ex.regs.eip = decoded.target;
            return validateControlTransferTarget(ex, start_eip, decoded.target, "jmp");
        },
        .call_rel => {
            reg_trace.logControlTransfer("call", start_eip, decoded.target, &ex.regs);
            stack_trace.logState("before_raw_call", .before_call, &ex.regs, &ex.mem);
            ex.push(next_eip);
            stack_trace.logState("after_raw_call_push", .after_call, &ex.regs, &ex.mem);
            ex.regs.eip = decoded.target;
            return validateControlTransferTarget(ex, start_eip, decoded.target, "call");
        },
        .push_reg => ex.push(ex.regs.get(decoded.register.?)),
        .pop_reg => ex.regs.set(decoded.register.?, ex.regs.pop(&ex.mem)),
        .push_imm => ex.push(decoded.immediate),
        .mov_reg_imm => ex.regs.set(decoded.register.?, decoded.immediate),
        .binary_reg_reg => {
            const rm_register = switch (decoded.operand.?) {
                .reg => |reg| reg,
                .mem => return stopRawUnsupported(ex, start_eip, decoded, "shared scalar adapter expected a register operand"),
            };
            const to_reg = (decoded.opcode & 0x02) != 0;
            const dst = if (to_reg) decoded.register.? else rm_register;
            const src = if (to_reg) rm_register else decoded.register.?;
            const lhs = readRegisterWidth(&ex.regs, dst, decoded.width);
            const rhs = readRegisterWidth(&ex.regs, src, decoded.width);
            const evaluated = highway.evaluate(decoded.binary_op.?, decoded.width, lhs, rhs, ex.regs.flags.raw());
            ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
            if (evaluated.writeback) writeRegisterWidth(&ex.regs, dst, decoded.width, evaluated.value);
        },
        .group5_inc => switch (decoded.operand.?) {
            .reg => |reg| ex.inc(reg),
            .mem => return stopRawUnsupported(ex, start_eip, decoded, "INC r/m32 memory execution is not implemented yet"),
        },
        .group5_dec => switch (decoded.operand.?) {
            .reg => |reg| ex.dec(reg),
            .mem => return stopRawUnsupported(ex, start_eip, decoded, "DEC r/m32 memory execution is not implemented yet"),
        },
        .group5_call => {
            const target = readRawRm32(ex, decoded.operand.?) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "could not resolve CALL r/m32 target address");

            if (resolveRawMemAddr(decoded.operand.?, &ex.regs)) |mem_addr| {
                if (lookupIatEntry(mem_addr)) |name| {
                    return dispatchIatCall(ex, start_eip, mem_addr, name, next_eip);
                }
            }

            reg_trace.logControlTransfer("call [r/m32]", start_eip, target, &ex.regs);
            stack_trace.logState("before_raw_call_indirect", .before_call, &ex.regs, &ex.mem);
            ex.push(next_eip);
            stack_trace.logState("after_raw_call_indirect_push", .after_call, &ex.regs, &ex.mem);
            ex.regs.eip = target;
            return validateControlTransferTarget(ex, start_eip, target, "call [r/m32]");
        },
        .group5_jmp => {
            const target = readRawRm32(ex, decoded.operand.?) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "could not resolve JMP r/m32 target address");

            if (resolveRawMemAddr(decoded.operand.?, &ex.regs)) |mem_addr| {
                if (lookupIatEntry(mem_addr)) |name| {
                    return dispatchIatJmp(ex, mem_addr, name);
                }
            }

            reg_trace.logControlTransfer("jmp [r/m32]", start_eip, target, &ex.regs);
            ex.regs.eip = target;
            return validateControlTransferTarget(ex, start_eip, target, "jmp [r/m32]");
        },
        .group5_push => {
            const value = readRawRm32(ex, decoded.operand.?) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "could not resolve PUSH r/m32 source address");
            ex.push(value);
        },
        .invalid, .recognized_unimplemented => {
            return stopRawUnsupported(ex, start_eip, decoded, decoded.unsupported_reason);
        },
    }
    ex.regs.eip = next_eip;
    return true;
}

fn readRegisterWidth(regs: *const reg_map.RegisterFile, reg: reg_map.Register, width: highway.Width) u64 {
    return switch (width) {
        .bits8 => regs.get8(reg),
        .bits16 => regs.get16(reg),
        .bits32, .bits64 => regs.get(reg),
    };
}

fn writeRegisterWidth(regs: *reg_map.RegisterFile, reg: reg_map.Register, width: highway.Width, value: u64) void {
    switch (width) {
        .bits8 => regs.set8(reg, @truncate(value)),
        .bits16 => regs.set16(reg, @truncate(value)),
        .bits32, .bits64 => regs.set(reg, @truncate(value)),
    }
}

fn execRawNext(ex: *Executor) bool {
    const start_eip = ex.regs.eip;
    const base = ex.mem.base;
    reg_trace.logInstructionBoundary("pre", "raw-x86-pe", start_eip, &ex.regs, ex.mem.base, ex.mem.data.len);
    runtime_abi.x86.validateExecutorState("pre-raw-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.flags.raw());
    runtime_abi.x86.validateExtendedState("pre-raw-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.abiState());
    const ip_check = code_text.checkInstructionPointer(ex.codeTextGuard(), start_eip, 1);
    if (!ip_check.isValid()) return stopBadInstructionPointer(ex, start_eip, start_eip, "instruction_fetch", ip_check);

    if (start_eip < base) return stopFetchFault(ex, start_eip, "EIP is below loaded image base");
    const offset = start_eip - base;
    if (offset >= ex.mem.data.len) return stopFetchFault(ex, start_eip, "EIP is outside loaded image");

    const available = ex.mem.data.len - offset;
    const window_len = @min(@as(usize, raw_decode.max_instruction_len), available);
    runtime_abi.x86.validateInstructionFetch(start_eip, ex.mem.base, ex.mem.data.len, window_len);
    const raw_window = ex.mem.data[offset .. offset + window_len];
    const decoded = raw_decode.decodeInstruction(start_eip, raw_window) catch {
        ex.regs.pending_exception = traps.pendingException(.UnsupportedInstruction);
        exception_trace.logFault("raw-x86-decode", .invalid_opcode, 6, if (raw_window.len > 0) raw_window[0] else 0, start_eip, start_eip, &ex.regs);
        decode_trace.validateInstructionWindow("raw-x86-decode-invalid", start_eip, raw_window, false, null);
        return false;
    };
    const decoded_ip_check = code_text.checkInstructionPointer(ex.codeTextGuard(), start_eip, decoded.len);
    if (!decoded_ip_check.isValid()) return stopBadInstructionPointer(ex, start_eip, start_eip, "instruction_fetch_width", decoded_ip_check);

    defer {
        runtime_abi.x86.validateExecutorState("post-raw-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.flags.raw());
        runtime_abi.x86.validateExtendedState("post-raw-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.abiState());
        reg_trace.logInstructionBoundary("post", decoded.mnemonic, start_eip, &ex.regs, ex.mem.base, ex.mem.data.len);
    }

    decode_trace.validateRawInstructionWindow(decoded.mnemonic, start_eip, raw_window[0..decoded.len], decoded);
    if (decoded.status != .executable) {
        return stopRawUnsupported(ex, start_eip, decoded, decoded.unsupported_reason);
    }
    return executeRawDecoded(ex, decoded, start_eip);
}

pub fn execNext(ex: *Executor, tt: *ThunkTable) bool {
    if (ex.terminated) return false;
    if (ex.execution_mode == .raw_x86_pe) return execRawNext(ex);

    const start_eip = ex.regs.eip;
    const base = ex.mem.base;
    reg_trace.logInstructionBoundary("pre", "decode", start_eip, &ex.regs, ex.mem.base, ex.mem.data.len);
    runtime_abi.x86.validateExecutorState("pre-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.flags.raw());
    runtime_abi.x86.validateExtendedState("pre-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.abiState());
    if (start_eip < base) return stopFetchFault(ex, start_eip, "EIP is below scripted memory base");
    const offset = start_eip - base;
    runtime_abi.x86.validateInstructionFetch(start_eip, ex.mem.base, ex.mem.data.len, INSTRUCTION_SIZE);
    if (offset + INSTRUCTION_SIZE > ex.mem.data.len) return false;
    const slice = ex.mem.data[offset .. offset + INSTRUCTION_SIZE];

    if (slice[0] > max_opcode) {
        ex.regs.pending_exception = traps.pendingException(.UnsupportedInstruction);
        exception_trace.logFault("decode-invalid", .invalid_opcode, 6, slice[0], start_eip, start_eip, &ex.regs);
        decode_trace.validateInstructionWindow("decode-invalid", start_eip, slice, false, null);
        return false;
    }

    const inst = isa.decode(slice);
    defer {
        runtime_abi.x86.validateExecutorState("post-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.flags.raw());
        runtime_abi.x86.validateExtendedState("post-step", ex.mem.base, ex.mem.data.len, ex.regs.eip, ex.regs.esp, ex.regs.ebp, ex.regs.abiState());
        reg_trace.logInstructionBoundary("post", @tagName(inst.opcode), start_eip, &ex.regs, ex.mem.base, ex.mem.data.len);
    }
    decode_trace.validateInstructionWindow(@tagName(inst.opcode), start_eip, slice, true, inst);
    trace.logInstruction(start_eip, inst, ex);

    switch (inst.opcode) {
        .nop => {},
        .mov_reg_imm => ex.mov_reg_imm(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .mov_reg_reg => ex.mov_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .mov_mem_imm => ex.mov_mem_imm(@as(u32, @bitCast(inst.op1)), @as(u32, @bitCast(inst.op2))),
        .mov_mem_reg => ex.mov_mem_reg(@as(u32, @bitCast(inst.op1)), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .mov_reg_mem => ex.mov_reg_mem(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .movzx_reg_mem => ex.movzx_reg_mem(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .mov_mem_reg8 => {
            const addr = @as(u32, @bitCast(inst.op1));
            const val = ex.regs.get8(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2))))));
            ex.mem.write8(addr, val);
        },
        .lea_reg_mem => ex.lea_reg_mem(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .add_reg_imm => ex.add_reg_imm(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .add_reg_reg => ex.add_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .sub_reg_imm => ex.sub_reg_imm(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .sub_reg_reg => ex.sub_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .inc_reg => ex.inc(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .dec_reg => ex.dec(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .mul_reg => ex.mul_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .imul_reg => ex.imul_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .div_reg => ex.div_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .xor_reg_reg => ex.xor_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .and_reg_reg => ex.and_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .or_reg_reg => ex.or_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .not_reg => ex.not_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .neg_reg => ex.neg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .shl_reg_cl => ex.shl_reg_cl(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .shr_reg_cl => ex.shr_reg_cl(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1)))))),
        .cmp_reg_imm => ex.cmp_reg_imm(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @as(u32, @bitCast(inst.op2))),
        .cmp_reg_reg => ex.cmp_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),
        .test_reg_reg => ex.test_reg_reg(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), @enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op2)))))),

        .jmp => {
            reg_trace.logControlTransfer("jmp", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
            ex.regs.eip = @as(u32, @bitCast(inst.op1));
            return true;
        },
        .je => {
            if (ex.regs.flags.zf == 1) {
                reg_trace.logControlTransfer("je", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
                ex.regs.eip = @as(u32, @bitCast(inst.op1));
                return true;
            }
        },
        .jne => {
            if (ex.regs.flags.zf == 0) {
                reg_trace.logControlTransfer("jne", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
                ex.regs.eip = @as(u32, @bitCast(inst.op1));
                return true;
            }
        },
        .jl => {
            if (ex.regs.flags.sf != ex.regs.flags.of) {
                reg_trace.logControlTransfer("jl", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
                ex.regs.eip = @as(u32, @bitCast(inst.op1));
                return true;
            }
        },
        .jge => {
            if (ex.regs.flags.sf == ex.regs.flags.of) {
                reg_trace.logControlTransfer("jge", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
                ex.regs.eip = @as(u32, @bitCast(inst.op1));
                return true;
            }
        },
        .jg => {
            if (ex.regs.flags.zf == 0 and ex.regs.flags.sf == ex.regs.flags.of) {
                reg_trace.logControlTransfer("jg", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
                ex.regs.eip = @as(u32, @bitCast(inst.op1));
                return true;
            }
        },
        .jle => {
            if (ex.regs.flags.zf == 1 or ex.regs.flags.sf != ex.regs.flags.of) {
                reg_trace.logControlTransfer("jle", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
                ex.regs.eip = @as(u32, @bitCast(inst.op1));
                return true;
            }
        },

        .call => {
            reg_trace.logControlTransfer("call", start_eip, @as(u32, @bitCast(inst.op1)), &ex.regs);
            stack_trace.logState("before_call", .before_call, &ex.regs, &ex.mem);
            ex.push(start_eip + INSTRUCTION_SIZE);
            stack_trace.logState("after_call_push", .after_call, &ex.regs, &ex.mem);
            ex.regs.eip = @as(u32, @bitCast(inst.op1));
            return true;
        },
        .ret => {
            reg_trace.logControlTransfer("ret", start_eip, ex.mem.read32(ex.regs.esp), &ex.regs);
            stack_trace.logState("before_ret", .before_call, &ex.regs, &ex.mem);
            ex.regs.eip = ex.regs.pop(&ex.mem);
            stack_trace.logState("after_ret", .after_call, &ex.regs, &ex.mem);
            return true;
        },
        .ret_imm => {
            reg_trace.logControlTransfer("ret_imm", start_eip, ex.mem.read32(ex.regs.esp), &ex.regs);
            stack_trace.logState("before_ret_imm", .before_call, &ex.regs, &ex.mem);
            ex.regs.eip = ex.regs.pop(&ex.mem);
            ex.regs.esp +|= @as(u32, @bitCast(inst.op1));
            stack_trace.logState("after_ret_imm", .after_call, &ex.regs, &ex.mem);
            return true;
        },
        .push_reg => {
            const val = ex.regs.get(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))));
            ex.push(val);
        },
        .pop_reg => {
            const val = ex.regs.pop(&ex.mem);
            ex.regs.set(@enumFromInt(@as(u4, @truncate(@as(u32, @bitCast(inst.op1))))), val);
        },

        .call_thunk => {
            const id = @as(u32, @bitCast(inst.op1));
            reg_trace.logThunkCall(id, &ex.regs);
            stack_trace.logState("before_thunk", .before_call, &ex.regs, &ex.mem);
            ex.regs.eip = start_eip + INSTRUCTION_SIZE;
            tt.call(@intCast(id), ex);
            stack_trace.logState("after_thunk", .after_call, &ex.regs, &ex.mem);
            return true;
        },

        .exit => return false,
    }

    ex.regs.eip = start_eip + INSTRUCTION_SIZE;
    return true;
}

pub fn run(ex: *Executor, tt: *ThunkTable) void {
    while (execNext(ex, tt)) {}
}

test "raw PE mode executes Group5 absolute indirect JMP" {
    var ex = Executor.init(std.testing.allocator, 0x300000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x0041F7A2;
    ex.regs.esp = 0x00600000;
    ex.mem.stack_hint = ex.regs.esp;

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 6], &[_]u8{ 0xFF, 0x25, 0x00, 0x20, 0x40, 0x00 });
    ex.mem.write32(0x00402000, 0x00401234);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00401234), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.pending_exception);
}

test "raw PE register arithmetic executes through the ISA highway" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0xFFFF_FFFF;
    ex.regs.ecx = 1;

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 2], &[_]u8{ 0x01, 0xC8 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
}
