const std = @import("std");
const isa = @import("instruction_set.zig");
const Opcode = isa.Opcode;
const Register = isa.Register;
const InstructionDef = isa.InstructionDef;
const INSTRUCTION_SIZE = isa.INSTRUCTION_SIZE;
const Executor = @import("instruction_operations.zig").Executor;
const raw_decode = @import("raw_decoder.zig");
const raw_x87 = @import("raw_x87.zig");
const trace = @import("instruction_trace.zig");
const runtime_abi = @import("runtime_abi_handshake");
const traps = runtime_abi.traps;
const code_text = @import("entrypoint_code_text_segment");
const reg_trace = @import("register-tracing/runtime.zig");
const stack_trace = @import("stack/runtime.zig");
const decode_trace = @import("instruction-decoding/runtime.zig");
const exception_trace = @import("exceptions/runtime.zig");
const string_trace = @import("string-ops/runtime.zig");
const reg_map = @import("register_mapping.zig");
const highway = @import("isa_highway");
const isa_registry = @import("isa_registry");
const isa_math = isa_registry.math.core;

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
const IatEntry = struct {
    owner: ?*const Executor,
    address: u32,
    name: []const u8,
    direct_target: bool = false,
};
var iat_entries: [MAX_IAT_ENTRIES]IatEntry = undefined;
var iat_count: u32 = 0;

pub fn clearIatEntries() void {
    iat_count = 0;
}

pub fn addIatEntry(addr: u32, name: []const u8) void {
    if (iat_count >= MAX_IAT_ENTRIES) return;
    iat_entries[iat_count] = .{ .owner = null, .address = addr, .name = name };
    iat_count += 1;
}

pub fn addIatEntryForExecutor(ex: *const Executor, addr: u32, name: []const u8) void {
    if (iat_count >= MAX_IAT_ENTRIES) return;
    iat_entries[iat_count] = .{ .owner = ex, .address = addr, .name = name };
    iat_count += 1;
}

/// Register a synthetic guest function pointer returned by APIs such as
/// wglGetProcAddress. Unlike an IAT slot, the target is the pointer value
/// itself and therefore must not be dereferenced as guest memory.
pub fn addIatDirectTargetForExecutor(ex: *const Executor, target: u32, name: []const u8) void {
    var i: u32 = 0;
    while (i < iat_count) : (i += 1) {
        const entry = &iat_entries[i];
        if (entry.owner == ex and entry.direct_target and entry.address == target and
            std.ascii.eqlIgnoreCase(entry.name, name)) return;
    }
    if (iat_count >= MAX_IAT_ENTRIES) return;
    iat_entries[iat_count] = .{ .owner = ex, .address = target, .name = name, .direct_target = true };
    iat_count += 1;
}

fn lookupIatEntry(ex: *const Executor, addr: u32) ?[]const u8 {
    var i: u32 = 0;
    while (i < iat_count) : (i += 1) {
        const entry = iat_entries[i];
        if (entry.address == addr and (entry.owner == null or entry.owner.? == ex)) return entry.name;
    }
    return null;
}

const IatTarget = struct {
    address: u32,
    name: []const u8,
};

/// Before the Windows loader resolves an import, the IAT still contains the
/// corresponding PE32 import-name RVA. Code can copy that value into a
/// register and call it indirectly, bypassing the usual `call [IAT]` route.
/// Resolve that value back to its IAT slot so the same registered import
/// handler can service both forms.
fn lookupIatTarget(ex: *const Executor, target: u32) ?IatTarget {
    if (target == 0) return null;
    var i: u32 = 0;
    while (i < iat_count) : (i += 1) {
        const entry = iat_entries[i];
        if (entry.owner != null and entry.owner.? != ex) continue;
        if (entry.direct_target) {
            if (entry.address == target and ex.import_table.contains(entry.name)) {
                return .{ .address = entry.address, .name = entry.name };
            }
            continue;
        }
        if (entry.address < ex.mem.base) continue;
        const offset: usize = @intCast(entry.address - ex.mem.base);
        if (offset > ex.mem.data.len or ex.mem.data.len - offset < 4) continue;
        if (ex.mem.read32(entry.address) == target) return .{ .address = entry.address, .name = entry.name };
    }
    return null;
}

/// Return a previously registered direct synthetic pointer for a dynamic
/// import name (for example, an OpenGL extension returned by WGL).
pub fn lookupIatDirectFunctionPointer(ex: *const Executor, name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < iat_count) : (i += 1) {
        const entry = iat_entries[i];
        if (entry.owner != null and entry.owner.? != ex) continue;
        if (entry.direct_target and std.ascii.eqlIgnoreCase(entry.name, name) and
            ex.import_table.contains(entry.name)) return entry.address;
    }
    return null;
}

/// Return the guest value currently stored in an imported function's IAT slot.
/// The raw PE runner uses this value as a callable synthetic address, which is
/// resolved back to the import by `lookupIatTarget` at indirect-call time.
pub fn lookupIatFunctionPointer(ex: *const Executor, name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < iat_count) : (i += 1) {
        const entry = iat_entries[i];
        if (entry.owner != null and entry.owner.? != ex) continue;
        if (entry.direct_target) continue;
        if (!std.ascii.eqlIgnoreCase(entry.name, name) or !ex.import_table.contains(entry.name)) continue;
        if (entry.address < ex.mem.base) continue;
        const offset: usize = @intCast(entry.address - ex.mem.base);
        if (offset > ex.mem.data.len or ex.mem.data.len - offset < 4) continue;
        return ex.mem.read32(entry.address);
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
    if (ex.raw_stop_eip != 0 and target_eip == ex.raw_stop_eip) return true;
    const guard = ex.codeTextGuard();
    const check = code_text.checkInstructionPointer(guard, target_eip, 1);
    if (check.isValid()) return true;
    return stopBadInstructionPointer(ex, source_eip, target_eip, scope, check);
}

fn isGuestExecutableAddress(ex: *const Executor, target_eip: u32) bool {
    return code_text.checkInstructionPointer(ex.codeTextGuard(), target_eip, 1).isValid();
}

fn rawConditionPassed(flags: reg_map.Flags, condition: u4) bool {
    return switch (condition) {
        0x0 => flags.of != 0,
        0x1 => flags.of == 0,
        0x2 => flags.cf != 0,
        0x3 => flags.cf == 0,
        0x4 => flags.zf != 0,
        0x5 => flags.zf == 0,
        0x6 => flags.cf != 0 or flags.zf != 0,
        0x7 => flags.cf == 0 and flags.zf == 0,
        0x8 => flags.sf != 0,
        0x9 => flags.sf == 0,
        0xA => flags.pf != 0,
        0xB => flags.pf == 0,
        0xC => flags.sf != flags.of,
        0xD => flags.sf == flags.of,
        0xE => flags.zf != 0 or flags.sf != flags.of,
        0xF => flags.zf == 0 and flags.sf == flags.of,
    };
}

fn applyRawMathFlag(current: u1, value: isa_math.FlagValue) u1 {
    return switch (value) {
        .clear => 0,
        .set => 1,
        .preserve, .undefined => current,
    };
}

fn applyRawMathFlags(regs: *reg_map.RegisterFile, flags: isa_math.Flags) void {
    regs.flags.cf = applyRawMathFlag(regs.flags.cf, flags.cf);
    regs.flags.pf = applyRawMathFlag(regs.flags.pf, flags.pf);
    regs.flags.af = applyRawMathFlag(regs.flags.af, flags.af);
    regs.flags.zf = applyRawMathFlag(regs.flags.zf, flags.zf);
    regs.flags.sf = applyRawMathFlag(regs.flags.sf, flags.sf);
    regs.flags.of = applyRawMathFlag(regs.flags.of, flags.of);
}

fn readRawRm32(ex: *Executor, decoded: raw_decode.DecodedInstruction) ?u32 {
    return switch (decoded.operand.?) {
        .reg => |reg| ex.regs.get(reg),
        .mem => blk: {
            const addr = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse return null;
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

fn resolveRawLinearAddr(operand: raw_decode.Rm32, segment_override: ?raw_decode.SegmentOverride, regs: *const reg_map.RegisterFile) ?u32 {
    const offset = resolveRawMemAddr(operand, regs) orelse return null;
    const segment_base: u32 = switch (segment_override orelse return offset) {
        .cs => regs.cs_desc.base,
        .ds => regs.ds_desc.base,
        .es => regs.es_desc.base,
        .fs => regs.fs_desc.base,
        .gs => regs.gs_desc.base,
        .ss => regs.ss_desc.base,
    };
    const linear = @as(u64, segment_base) + offset;
    if (linear > std.math.maxInt(u32)) return null;
    return @intCast(linear);
}

fn checkedRawMoveAddress(ex: *Executor, decoded: raw_decode.DecodedInstruction, access: highway.MemoryAccess) ?u32 {
    const address = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse return null;
    const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
    if (!range.allowed()) return null;
    return address;
}

fn executeRawGroup2Shift(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    const extension = decoded.modrm.?.reg;
    const width_bits: u32 = decoded.width.bits();
    const width_shift: u6 = @intCast(width_bits);
    const mask = (@as(u64, 1) << width_shift) - 1;
    const count_source = if (decoded.shift_from_cl) ex.regs.ecx else decoded.immediate;
    var count = count_source & 0x1F;
    if (extension <= 1) {
        count %= width_bits;
    } else if (extension == 2 or extension == 3) {
        count %= width_bits + 1;
    }
    if (count == 0) return true;

    var memory_address: ?u32 = null;
    const value: u64 = switch (decoded.operand.?) {
        .reg => |reg| readRegisterWidth(&ex.regs, reg, decoded.width),
        .mem => blk: {
            const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "Group2 shift source address is invalid or unmapped");
            memory_address = address;
            break :blk readMemoryWidth(&ex.mem, address, decoded.width);
        },
    };
    var result = value;
    var carry: u1 = ex.regs.flags.cf;
    const count_shift: u6 = @intCast(count);
    switch (extension) {
        0 => {
            for (0..count) |_| {
                const next_carry: u1 = @intCast((result >> (width_shift - 1)) & 1);
                result = ((result << 1) & mask) | next_carry;
                carry = next_carry;
            }
        },
        1 => {
            for (0..count) |_| {
                carry = @intCast(result & 1);
                result = (result >> 1) | (@as(u64, carry) << @intCast(width_bits - 1));
            }
        },
        2 => {
            for (0..count) |_| {
                const next_carry: u1 = @intCast((result >> (width_shift - 1)) & 1);
                result = ((result << 1) & mask) | carry;
                carry = next_carry;
            }
        },
        3 => {
            for (0..count) |_| {
                const next_carry: u1 = @intCast(result & 1);
                result = (result >> 1) | (@as(u64, carry) << @intCast(width_bits - 1));
                carry = next_carry;
            }
        },
        4, 6 => {
            if (count <= width_bits) {
                carry = @intCast((value >> @intCast(width_bits - count)) & 1);
            }
            result = if (count >= width_bits) 0 else (value << count_shift) & mask;
        },
        5 => {
            if (count <= width_bits) carry = @intCast((value >> @intCast(count - 1)) & 1);
            result = if (count >= width_bits) 0 else value >> count_shift;
        },
        7 => {
            if (count <= width_bits) carry = @intCast((value >> @intCast(count - 1)) & 1);
            const signed_value: i64 = switch (decoded.width) {
                .bits8 => @as(i8, @bitCast(@as(u8, @truncate(value)))),
                .bits16 => @as(i16, @bitCast(@as(u16, @truncate(value)))),
                .bits32 => @as(i32, @bitCast(@as(u32, @truncate(value)))),
                .bits64 => unreachable, // This executor only decodes 8/16/32-bit PE32 operands.
            };
            result = if (count >= width_bits)
                (if (signed_value < 0) mask else 0)
            else
                @as(u64, @bitCast(signed_value >> count_shift)) & mask;
        },
    }

    if (extension <= 3) {
        ex.regs.flags.cf = carry;
        if (count == 1) {
            ex.regs.flags.of = if (extension == 0 or extension == 2)
                @intCast(((result >> @intCast(width_bits - 1)) & 1) ^ carry)
            else
                @intCast(((result >> @intCast(width_bits - 1)) ^ (result >> @intCast(width_bits - 2))) & 1);
        }
    } else {
        ex.regs.flags.cf = carry;
        const sign = (result >> @intCast(width_bits - 1)) & 1;
        ex.regs.flags.zf = @intFromBool(result == 0);
        ex.regs.flags.sf = @intCast(sign);
        ex.regs.flags.pf = @intCast((@popCount(@as(u8, @truncate(result))) & 1) ^ 1);
        if (count == 1) {
            ex.regs.flags.of = switch (extension) {
                4, 6 => @intCast(sign ^ @as(u64, carry)),
                5 => @intCast((value >> @intCast(width_bits - 1)) & 1),
                7 => 0,
                else => unreachable,
            };
        }
    }

    switch (decoded.operand.?) {
        .reg => |reg| writeRegisterWidth(&ex.regs, reg, decoded.width, result),
        .mem => {
            const address = memory_address.?;
            if (decoded.locked) {
                const atomic = highway.validateAtomic(address, decoded.width, true);
                if (!atomic.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(atomic.fault.?));
            }
            const access: highway.MemoryAccess = if (decoded.locked) .atomic_read_modify_write else .write;
            const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
            if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "Group2 shift destination address is invalid or unmapped");
            writeMemoryWidth(&ex.mem, address, decoded.width, result);
        },
    }
    return true;
}

fn executeRawSetcc(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid on SETcc");
    const value: u8 = @intFromBool(rawConditionPassed(ex.regs.flags, decoded.condition));
    switch (decoded.operand.?) {
        .reg => ex.regs.setByte(decoded.byte_rm_register.?, value),
        .mem => {
            const address = checkedRawMoveAddress(ex, decoded, .write) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "SETcc destination address is invalid or unmapped");
            ex.mem.write8(address, value);
        },
    }
    return true;
}

fn executeRawIncDecRegister(ex: *Executor, decoded: raw_decode.DecodedInstruction, increment: bool) void {
    const register = decoded.register.?;
    const old_carry = ex.regs.flags.cf;
    const current = readRegisterWidth(&ex.regs, register, decoded.width);
    const operation: highway.BinaryOp = if (increment) .add else .sub;
    const evaluated = highway.evaluate(operation, decoded.width, current, 1, ex.regs.flags.raw());
    ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
    ex.regs.flags.cf = old_carry;
    writeRegisterWidth(&ex.regs, register, decoded.width, evaluated.value);
}

fn executeRawGroup5IncDec(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32, increment: bool) bool {
    switch (decoded.operand.?) {
        .reg => |register| {
            if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for register INC/DEC");
            const old_carry = ex.regs.flags.cf;
            if (decoded.width == .bits8) {
                const byte_register = decoded.byte_rm_register orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "byte INC/DEC register was not decoded");
                const operation: highway.BinaryOp = if (increment) .add else .sub;
                const evaluated = highway.evaluate(operation, decoded.width, ex.regs.getByte(byte_register), 1, ex.regs.flags.raw());
                ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                ex.regs.flags.cf = old_carry;
                ex.regs.setByte(byte_register, @truncate(evaluated.value));
                return true;
            }
            const current = readRegisterWidth(&ex.regs, register, decoded.width);
            const operation: highway.BinaryOp = if (increment) .add else .sub;
            const evaluated = highway.evaluate(operation, decoded.width, current, 1, ex.regs.flags.raw());
            ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
            ex.regs.flags.cf = old_carry;
            writeRegisterWidth(&ex.regs, register, decoded.width, evaluated.value);
            return true;
        },
        .mem => {
            const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "INC/DEC source address is invalid or unmapped");
            if (decoded.locked) {
                const atomic = highway.validateAtomic(address, decoded.width, true);
                if (!atomic.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(atomic.fault.?));
            }
            const access: highway.MemoryAccess = if (decoded.locked) .atomic_read_modify_write else .write;
            const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
            if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "INC/DEC destination address is invalid or unmapped");

            const old_carry = ex.regs.flags.cf;
            const current = readMemoryWidth(&ex.mem, address, decoded.width);
            var transaction = highway.beginAtomic(address, decoded.width, .sequential, decoded.locked, current);
            const operation: highway.BinaryOp = if (increment) .add else .sub;
            const evaluated = highway.evaluate(operation, decoded.width, current, 1, ex.regs.flags.raw());
            ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
            ex.regs.flags.cf = old_carry;
            writeMemoryWidth(&ex.mem, address, decoded.width, evaluated.value);
            if (decoded.locked) highway.commitAtomic(&transaction, evaluated.value);
            return true;
        },
    }
}

fn executeRawMove(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    const register_is_destination = if (decoded.opcode >= 0xA0 and decoded.opcode <= 0xA3)
        (decoded.opcode & 0x02) == 0
    else
        (decoded.opcode & 0x02) != 0;
    if (decoded.width == .bits8) {
        if (register_is_destination) {
            const value: u8 = switch (decoded.operand.?) {
                .reg => ex.regs.getByte(decoded.byte_rm_register.?),
                .mem => blk: {
                    const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "MOV byte source address is invalid or unmapped");
                    break :blk ex.mem.read8(address);
                },
            };
            ex.regs.setByte(decoded.byte_register.?, value);
        } else {
            const value = ex.regs.getByte(decoded.byte_register.?);
            switch (decoded.operand.?) {
                .reg => ex.regs.setByte(decoded.byte_rm_register.?, value),
                .mem => {
                    const address = checkedRawMoveAddress(ex, decoded, .write) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "MOV byte destination address is invalid or unmapped");
                    ex.mem.write8(address, value);
                },
            }
        }
    } else if (register_is_destination) {
        const value: u64 = switch (decoded.operand.?) {
            .reg => |reg| readRegisterWidth(&ex.regs, reg, decoded.width),
            .mem => blk: {
                const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "MOV source address is invalid or unmapped");
                break :blk readMemoryWidth(&ex.mem, address, decoded.width);
            },
        };
        writeRegisterWidth(&ex.regs, decoded.register.?, decoded.width, value);
    } else {
        const value = readRegisterWidth(&ex.regs, decoded.register.?, decoded.width);
        switch (decoded.operand.?) {
            .reg => |reg| writeRegisterWidth(&ex.regs, reg, decoded.width, value),
            .mem => {
                const address = checkedRawMoveAddress(ex, decoded, .write) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "MOV destination address is invalid or unmapped");
                writeMemoryWidth(&ex.mem, address, decoded.width, value);
            },
        }
    }

    ex.regs.eip = start_eip + @as(u32, decoded.len);
    return true;
}

fn dispatchIatCall(ex: *Executor, start_eip: u32, iat_addr: u32, name: []const u8, next_eip: u32) bool {
    const boundary = highway.systemBoundary(.pe32, .import, iat_addr, name);
    if (boundary.disposition != .forward) {
        if (rawExecTraceEnabled()) std.debug.print("PE32_EXEC_IAT_DECLINED eip=0x{X:0>8} slot=0x{X:0>8} import={s} disposition={s}\n", .{
            start_eip,
            iat_addr,
            name,
            @tagName(boundary.disposition),
        });
        return false;
    }
    if (ex.import_table.get(name) == null) {
        if (rawExecTraceEnabled()) std.debug.print("PE32_EXEC_IAT_MISSING eip=0x{X:0>8} slot=0x{X:0>8} import={s}\n", .{ start_eip, iat_addr, name });
        return false;
    }
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
    const boundary = highway.systemBoundary(.pe32, .import, iat_addr, name);
    if (boundary.disposition != .forward) return false;
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

/// Keep PE32 investigation output opt-in and failure-only: normal emulation
/// should not acquire per-instruction logging overhead, while a stopped guest
/// still needs enough state to distinguish a bad guest pointer from an
/// unsupported instruction implementation.
fn rawExecTraceEnabled() bool {
    const value_ptr = std.c.getenv("ROSETTE_PE32_EXEC_TRACE") orelse return false;
    const value = std.mem.sliceTo(value_ptr, 0);
    return std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
}

fn stopRawUnsupported(ex: *Executor, start_eip: u32, decoded: raw_decode.DecodedInstruction, reason: []const u8) bool {
    if (rawExecTraceEnabled()) {
        const effective_address = if (decoded.operand) |operand|
            resolveRawLinearAddr(operand, decoded.segment_override, &ex.regs)
        else
            null;
        const memory_check = if (effective_address) |address|
            highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, .read, true)
        else
            null;
        const range_status: []const u8 = if (memory_check) |check|
            if (check.fault) |fault| @tagName(fault) else "allowed"
        else
            "not-a-memory-operand";
        std.debug.print(
            "PE32_EXEC_STOP eip=0x{X:0>8} instruction={s} isa={s} reason={s} " ++
                "eax=0x{X:0>8} ebx=0x{X:0>8} ecx=0x{X:0>8} edx=0x{X:0>8} " ++
                "esi=0x{X:0>8} edi=0x{X:0>8} ebp=0x{X:0>8} esp=0x{X:0>8} eflags=0x{X:0>8} " ++
                "mem_base=0x{X:0>8} mem_len=0x{X} effective_address=0x{X:0>8} has_effective_address={} range={s}\n",
            .{
                start_eip,
                decoded.textSlice(),
                decoded.isa_path,
                reason,
                ex.regs.eax,
                ex.regs.ebx,
                ex.regs.ecx,
                ex.regs.edx,
                ex.regs.esi,
                ex.regs.edi,
                ex.regs.ebp,
                ex.regs.esp,
                ex.regs.flags.raw(),
                ex.mem.base,
                ex.mem.data.len,
                effective_address orelse 0,
                effective_address != null,
                range_status,
            },
        );
    }
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

fn rawStackSpanValid(ex: *const Executor, address: u32, size: u32) bool {
    if (address < ex.mem.base) return false;
    const offset: usize = @intCast(address - ex.mem.base);
    return offset <= ex.mem.data.len and size <= ex.mem.data.len - offset;
}

fn executeRawPusha(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    const word_bytes: u32 = if (decoded.width == .bits16) 2 else 4;
    const span_bytes = word_bytes * 8;
    const original_esp = ex.regs.esp;
    if (original_esp < span_bytes) return stopRawUnsupported(ex, start_eip, decoded, "PUSHA stack address underflowed PE32");
    const destination = original_esp - span_bytes;
    if (!rawStackSpanValid(ex, destination, span_bytes)) {
        return stopRawUnsupported(ex, start_eip, decoded, "PUSHA stack destination is unmapped or unwritable");
    }

    const values = [_]u32{
        ex.regs.eax,
        ex.regs.ecx,
        ex.regs.edx,
        ex.regs.ebx,
        original_esp,
        ex.regs.ebp,
        ex.regs.esi,
        ex.regs.edi,
    };
    var stack_pointer = original_esp;
    for (values) |value| {
        stack_pointer -= word_bytes;
        writeMemoryWidth(&ex.mem, stack_pointer, decoded.width, value);
    }
    ex.regs.esp = destination;
    ex.mem.stack_hint = destination;
    return true;
}

fn executeRawPopa(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    const word_bytes: u32 = if (decoded.width == .bits16) 2 else 4;
    const span_bytes = word_bytes * 8;
    const original_esp = ex.regs.esp;
    if (!rawStackSpanValid(ex, original_esp, span_bytes)) {
        return stopRawUnsupported(ex, start_eip, decoded, "POPA stack source is unmapped or unreadable");
    }

    const destinations = [_]?reg_map.Register{
        .edi,
        .esi,
        .ebp,
        null, // The saved SP/ESP slot is discarded.
        .ebx,
        .edx,
        .ecx,
        .eax,
    };
    var stack_pointer = original_esp;
    for (destinations) |destination| {
        const value = readMemoryWidth(&ex.mem, stack_pointer, decoded.width);
        if (destination) |register| writeRegisterWidth(&ex.regs, register, decoded.width, value);
        stack_pointer += word_bytes;
    }
    ex.regs.esp = stack_pointer;
    return true;
}

fn executeRawDecoded(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32) bool {
    const next_eip = start_eip + @as(u32, decoded.len);
    switch (decoded.op) {
        .nop => {},
        .string_movs => return executeRawStringMovs(ex, decoded, start_eip, next_eip),
        .string_stos => return executeRawStringStos(ex, decoded, start_eip, next_eip),
        .string_scas => return executeRawStringScas(ex, decoded, start_eip, next_eip),
        .x87 => raw_x87.execute(&ex.regs, &ex.mem, decoded) catch |err| return stopRawUnsupported(ex, start_eip, decoded, @errorName(err)),
        .clear_direction_flag => ex.regs.flags.df = 0,
        .set_direction_flag => ex.regs.flags.df = 1,
        .sahf => {
            const sahf_mask: u32 = 0xD5; // CF, PF, AF, ZF, SF
            const ah: u8 = @truncate(ex.regs.eax >> 8);
            ex.regs.flags = reg_map.Flags.fromRaw((ex.regs.flags.raw() & ~sahf_mask) | (@as(u32, ah) & sahf_mask) | 0x2);
        },
        .ret => {
            const target = ex.mem.read32(ex.regs.esp);
            reg_trace.logControlTransfer("ret", start_eip, target, &ex.regs);
            stack_trace.logState("before_raw_ret", .before_call, &ex.regs, &ex.mem);
            ex.regs.eip = ex.regs.pop(&ex.mem);
            if (decoded.opcode == 0xC2) ex.regs.esp +%= decoded.immediate;
            stack_trace.logState("after_raw_ret", .after_call, &ex.regs, &ex.mem);
            return validateControlTransferTarget(ex, start_eip, ex.regs.eip, "ret");
        },
        .jmp_rel => {
            reg_trace.logControlTransfer("jmp", start_eip, decoded.target, &ex.regs);
            ex.regs.eip = decoded.target;
            return validateControlTransferTarget(ex, start_eip, decoded.target, "jmp");
        },
        .jcc_rel => {
            const taken = rawConditionPassed(ex.regs.flags, decoded.condition);
            const target = if (taken) decoded.target else next_eip;
            reg_trace.logControlTransfer(decoded.mnemonic, start_eip, target, &ex.regs);
            ex.regs.eip = target;
            if (taken) return validateControlTransferTarget(ex, start_eip, target, decoded.mnemonic);
            return true;
        },
        .call_rel => {
            reg_trace.logControlTransfer("call", start_eip, decoded.target, &ex.regs);
            stack_trace.logState("before_raw_call", .before_call, &ex.regs, &ex.mem);
            ex.push(next_eip);
            stack_trace.logState("after_raw_call_push", .after_call, &ex.regs, &ex.mem);
            ex.regs.eip = decoded.target;
            return validateControlTransferTarget(ex, start_eip, decoded.target, "call");
        },
        .pusha => {
            if (!executeRawPusha(ex, decoded, start_eip)) return false;
        },
        .popa => {
            if (!executeRawPopa(ex, decoded, start_eip)) return false;
        },
        .push_reg => ex.push(ex.regs.get(decoded.register.?)),
        .pop_reg => ex.regs.set(decoded.register.?, ex.regs.pop(&ex.mem)),
        .leave => {
            ex.regs.esp = ex.regs.ebp;
            if (decoded.width == .bits16) {
                ex.regs.set16(.ebp, ex.mem.read16(ex.regs.esp));
                ex.regs.esp +%= 2;
            } else {
                ex.regs.ebp = ex.regs.pop(&ex.mem);
            }
        },
        .sign_extend_accumulator => {
            if (decoded.width == .bits16) {
                const ax: u16 = ex.regs.get16(.eax);
                ex.regs.set16(.edx, if (ax & 0x8000 != 0) 0xFFFF else 0);
            } else {
                ex.regs.edx = if (ex.regs.eax & 0x8000_0000 != 0) std.math.maxInt(u32) else 0;
            }
        },
        .push_imm => ex.push(decoded.immediate),
        .push_flags => {
            const stack_width: u32 = if (decoded.width == .bits16) 2 else 4;
            const next_esp = ex.regs.esp -% stack_width;
            const range = highway.validateRange(ex.mem.base, ex.mem.data.len, next_esp, decoded.width, .write, true);
            if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "PUSHF stack destination is unmapped or unwritable");
            const value = ex.regs.flags.raw() | 0x2;
            if (decoded.width == .bits16) {
                ex.regs.esp = next_esp;
                ex.mem.stack_hint = next_esp;
                ex.mem.write16(next_esp, @truncate(value));
            } else {
                ex.push(value);
            }
        },
        .pop_flags => {
            const stack_width: u32 = if (decoded.width == .bits16) 2 else 4;
            const range = highway.validateRange(ex.mem.base, ex.mem.data.len, ex.regs.esp, decoded.width, .read, true);
            if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "POPF stack source is unmapped or unreadable");
            const value: u32 = if (decoded.width == .bits16)
                ex.mem.read16(ex.regs.esp)
            else
                ex.mem.read32(ex.regs.esp);
            ex.regs.esp +%= stack_width;
            // The emulator runs guest applications at user privilege. POPF can
            // restore arithmetic/control status but cannot change IF or IOPL.
            const writable_mask: u32 = if (decoded.width == .bits16)
                0x0000_0DD5
            else
                0x0024_0DD5;
            ex.regs.flags = reg_map.Flags.fromRaw((ex.regs.flags.raw() & ~writable_mask) | (value & writable_mask) | 0x2);
        },
        .cpuid => {
            // Report the portable PE32 execution contract rather than leaking
            // the host CPU's features into guest feature dispatch. Optional
            // SIMD/TSC bits stay clear until their instructions are admitted.
            const leaf = ex.regs.eax;
            ex.regs.eax = 0;
            ex.regs.ebx = 0;
            ex.regs.ecx = 0;
            ex.regs.edx = 0;
            switch (leaf) {
                0 => {
                    ex.regs.eax = 1;
                    ex.regs.ebx = 0x756E_6547; // "Genu"
                    ex.regs.edx = 0x4965_6E69; // "ineI"
                    ex.regs.ecx = 0x6C65_746E; // "ntel"
                },
                1 => {
                    ex.regs.eax = 0x0000_0600; // generic family 6, no model claims
                    ex.regs.edx = 0x0000_0001; // x87 only; no optional ISA extensions
                },
                0x8000_0000 => ex.regs.eax = 0x8000_0000,
                else => {},
            }
        },
        .mov_byte_reg_imm => ex.regs.setByte(decoded.byte_register.?, @truncate(decoded.immediate)),
        .mov_reg_imm => writeRegisterWidth(&ex.regs, decoded.register.?, decoded.width, decoded.immediate),
        .xchg_eax_reg => {
            const eax_value = readRegisterWidth(&ex.regs, .eax, decoded.width);
            const other_value = readRegisterWidth(&ex.regs, decoded.register.?, decoded.width);
            writeRegisterWidth(&ex.regs, .eax, decoded.width, other_value);
            writeRegisterWidth(&ex.regs, decoded.register.?, decoded.width, eax_value);
        },
        .mov_rm => return executeRawMove(ex, decoded, start_eip),
        .mov_extend => {
            if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for MOVSX/MOVZX");
            const source: u64 = switch (decoded.operand.?) {
                .reg => |reg| if (decoded.source_width == .bits8)
                    ex.regs.getByte(decoded.byte_rm_register.?)
                else
                    readRegisterWidth(&ex.regs, reg, decoded.source_width),
                .mem => blk: {
                    const address = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "MOVSX/MOVZX source address overflowed PE32");
                    const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.source_width, .read, true);
                    if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "MOVSX/MOVZX source address is unmapped or unreadable");
                    break :blk readMemoryWidth(&ex.mem, address, decoded.source_width);
                },
            };
            const value: u64 = if (!decoded.sign_extend) source else blk: {
                const signed_value: i32 = switch (decoded.source_width) {
                    .bits8 => @as(i8, @bitCast(@as(u8, @truncate(source)))),
                    .bits16 => @as(i16, @bitCast(@as(u16, @truncate(source)))),
                    else => return stopRawUnsupported(ex, start_eip, decoded, "MOVSX source width is unsupported"),
                };
                break :blk @as(u32, @bitCast(signed_value));
            };
            writeRegisterWidth(&ex.regs, decoded.register.?, decoded.width, value);
        },
        .setcc => {
            if (!executeRawSetcc(ex, decoded, start_eip)) return false;
        },
        .group2_shift => {
            if (!executeRawGroup2Shift(ex, decoded, start_eip)) return false;
        },
        .mov_immediate_rm => switch (decoded.operand.?) {
            .reg => |reg| writeRegisterWidth(&ex.regs, reg, decoded.width, decoded.immediate),
            .mem => {
                const address = checkedRawMoveAddress(ex, decoded, .write) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "MOV immediate destination address is invalid or unmapped");
                writeMemoryWidth(&ex.mem, address, decoded.width, decoded.immediate);
            },
        },
        .lea => {
            const address = switch (decoded.operand.?) {
                .mem => |mem| mem.resolveWrapping(&ex.regs),
                .reg => return stopRawUnsupported(ex, start_eip, decoded, "LEA requires a memory addressing form"),
            };
            writeRegisterWidth(&ex.regs, decoded.register.?, decoded.width, address);
        },
        .binary => switch (decoded.operand.?) {
            .reg => |rm_register| {
                if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK requires a writable memory destination");
                const to_reg = (decoded.opcode & 0x02) != 0;
                if (decoded.width == .bits8) {
                    const dst = if (to_reg) decoded.byte_register.? else decoded.byte_rm_register.?;
                    const src = if (to_reg) decoded.byte_rm_register.? else decoded.byte_register.?;
                    const evaluated = highway.evaluate(decoded.binary_op.?, .bits8, ex.regs.getByte(dst), ex.regs.getByte(src), ex.regs.flags.raw());
                    ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                    if (evaluated.writeback) ex.regs.setByte(dst, @truncate(evaluated.value));
                } else {
                    const dst = if (to_reg) decoded.register.? else rm_register;
                    const src = if (to_reg) rm_register else decoded.register.?;
                    const lhs = readRegisterWidth(&ex.regs, dst, decoded.width);
                    const rhs = readRegisterWidth(&ex.regs, src, decoded.width);
                    const evaluated = highway.evaluate(decoded.binary_op.?, decoded.width, lhs, rhs, ex.regs.flags.raw());
                    ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                    if (evaluated.writeback) writeRegisterWidth(&ex.regs, dst, decoded.width, evaluated.value);
                }
            },
            .mem => {
                const address = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "shared memory transaction address overflowed PE32");
                const direction: highway.MemoryDirection = if ((decoded.opcode & 0x02) != 0) .memory_to_register else .register_to_memory;
                if (decoded.locked and (direction != .register_to_memory or decoded.binary_op.? == .cmp or decoded.binary_op.? == .test_bits))
                    return stopRawUnsupported(ex, start_eip, decoded, "LOCK requires a read-modify-write operation");
                const access: highway.MemoryAccess = if (decoded.locked)
                    .atomic_read_modify_write
                else if (direction == .register_to_memory and decoded.binary_op.? != .cmp and decoded.binary_op.? != .test_bits)
                    .write
                else
                    .read;
                const atomic = highway.validateAtomic(address, decoded.width, decoded.locked);
                if (!atomic.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(atomic.fault.?));
                const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
                if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(range.fault.?));
                const register_value = if (decoded.width == .bits8)
                    ex.regs.getByte(decoded.byte_register.?)
                else
                    readRegisterWidth(&ex.regs, decoded.register.?, decoded.width);
                const memory_value = readMemoryWidth(&ex.mem, address, decoded.width);
                var transaction = highway.beginAtomic(address, decoded.width, .sequential, decoded.locked, memory_value);
                const evaluated = highway.evaluateMemory(decoded.binary_op.?, decoded.width, register_value, memory_value, direction, ex.regs.flags.raw());
                ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                if (evaluated.write_register) {
                    if (decoded.width == .bits8)
                        ex.regs.setByte(decoded.byte_register.?, @truncate(evaluated.value))
                    else
                        writeRegisterWidth(&ex.regs, decoded.register.?, decoded.width, evaluated.value);
                }
                if (evaluated.write_memory) {
                    writeMemoryWidth(&ex.mem, address, decoded.width, evaluated.value);
                    highway.commitAtomic(&transaction, evaluated.value);
                }
            },
        },
        .binary_immediate => switch (decoded.operand.?) {
            .reg => |reg| {
                if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK requires a memory destination");
                if (decoded.width == .bits8) {
                    const byte_reg = decoded.byte_rm_register.?;
                    const evaluated = highway.evaluate(decoded.binary_op.?, .bits8, ex.regs.getByte(byte_reg), decoded.immediate, ex.regs.flags.raw());
                    ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                    if (evaluated.writeback) ex.regs.setByte(byte_reg, @truncate(evaluated.value));
                } else {
                    const lhs = readRegisterWidth(&ex.regs, reg, decoded.width);
                    const evaluated = highway.evaluate(decoded.binary_op.?, decoded.width, lhs, decoded.immediate, ex.regs.flags.raw());
                    ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                    if (evaluated.writeback) writeRegisterWidth(&ex.regs, reg, decoded.width, evaluated.value);
                }
            },
            .mem => {
                const address = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "immediate memory transaction address overflowed PE32");
                const check = highway.validateAtomic(address, decoded.width, decoded.locked);
                if (!check.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(check.fault.?));
                if (decoded.locked and (decoded.binary_op.? == .cmp or decoded.binary_op.? == .test_bits))
                    return stopRawUnsupported(ex, start_eip, decoded, "LOCK requires a read-modify-write operation");
                const access: highway.MemoryAccess = if (decoded.locked)
                    .atomic_read_modify_write
                else if (decoded.binary_op.? == .cmp or decoded.binary_op.? == .test_bits)
                    .read
                else
                    .write;
                const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
                if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(range.fault.?));
                const lhs = readMemoryWidth(&ex.mem, address, decoded.width);
                var transaction = highway.beginAtomic(address, decoded.width, .sequential, decoded.locked, lhs);
                const evaluated = highway.evaluate(decoded.binary_op.?, decoded.width, lhs, decoded.immediate, ex.regs.flags.raw());
                ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                if (evaluated.writeback) {
                    writeMemoryWidth(&ex.mem, address, decoded.width, evaluated.value);
                    highway.commitAtomic(&transaction, evaluated.value);
                }
            },
        },
        .group3_not => switch (decoded.operand.?) {
            .reg => |reg| {
                if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK prefix is invalid for a register NOT");
                const mask: u64 = (@as(u64, 1) << @as(u6, @intCast(decoded.width.bits()))) - 1;
                if (decoded.width == .bits8) {
                    const byte_reg = decoded.byte_rm_register orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "8-bit NOT register alias is missing");
                    const result = ~@as(u64, ex.regs.getByte(byte_reg)) & mask;
                    ex.regs.setByte(byte_reg, @truncate(result));
                } else {
                    const result = ~readRegisterWidth(&ex.regs, reg, decoded.width) & mask;
                    writeRegisterWidth(&ex.regs, reg, decoded.width, result);
                }
            },
            .mem => {
                const address = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "NOT memory address overflowed PE32");
                const atomic = highway.validateAtomic(address, decoded.width, decoded.locked);
                if (!atomic.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(atomic.fault.?));
                const access: highway.MemoryAccess = if (decoded.locked) .atomic_read_modify_write else .write;
                const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
                if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(range.fault.?));
                const mask: u64 = (@as(u64, 1) << @as(u6, @intCast(decoded.width.bits()))) - 1;
                const before = readMemoryWidth(&ex.mem, address, decoded.width);
                const result = ~before & mask;
                var transaction = highway.beginAtomic(address, decoded.width, .sequential, decoded.locked, before);
                writeMemoryWidth(&ex.mem, address, decoded.width, result);
                if (decoded.locked) highway.commitAtomic(&transaction, result);
            },
        },
        .group3_neg => switch (decoded.operand.?) {
            .reg => |reg| {
                if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK prefix is invalid for a register NEG");
                const byte_reg = if (decoded.width == .bits8) decoded.byte_rm_register else null;
                if (decoded.width == .bits8 and byte_reg == null) {
                    return stopRawUnsupported(ex, start_eip, decoded, "8-bit NEG register alias is missing");
                }
                const operand: u64 = if (byte_reg) |alias|
                    ex.regs.getByte(alias)
                else
                    readRegisterWidth(&ex.regs, reg, decoded.width);
                const evaluated = highway.evaluate(.sub, decoded.width, 0, operand, ex.regs.flags.raw());
                ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                if (byte_reg) |alias| {
                    ex.regs.setByte(alias, @truncate(evaluated.value));
                } else {
                    writeRegisterWidth(&ex.regs, reg, decoded.width, evaluated.value);
                }
            },
            .mem => {
                const address = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs) orelse
                    return stopRawUnsupported(ex, start_eip, decoded, "NEG memory address overflowed PE32");
                const atomic = highway.validateAtomic(address, decoded.width, decoded.locked);
                if (!atomic.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(atomic.fault.?));
                const access: highway.MemoryAccess = if (decoded.locked) .atomic_read_modify_write else .write;
                const range = highway.validateRange(ex.mem.base, ex.mem.data.len, address, decoded.width, access, true);
                if (!range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, @tagName(range.fault.?));
                const before = readMemoryWidth(&ex.mem, address, decoded.width);
                var transaction = highway.beginAtomic(address, decoded.width, .sequential, decoded.locked, before);
                const evaluated = highway.evaluate(.sub, decoded.width, 0, before, ex.regs.flags.raw());
                ex.regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
                writeMemoryWidth(&ex.mem, address, decoded.width, evaluated.value);
                highway.commitAtomic(&transaction, evaluated.value);
            },
        },
        .group3_div => {
            if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for DIV");
            const divisor: u64 = switch (decoded.operand.?) {
                .reg => |reg| readRegisterWidth(&ex.regs, reg, decoded.width),
                .mem => blk: {
                    const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "DIV source address is invalid or unmapped");
                    break :blk readMemoryWidth(&ex.mem, address, decoded.width);
                },
            };
            if (decoded.width == .bits16) {
                const dividend = (@as(u32, ex.regs.edx & 0xFFFF) << 16) | (ex.regs.eax & 0xFFFF);
                if (divisor == 0) return stopRawUnsupported(ex, start_eip, decoded, "DIV by zero raises #DE, which this PE runner cannot deliver yet");
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u16)) return stopRawUnsupported(ex, start_eip, decoded, "DIV quotient overflow raises #DE, which this PE runner cannot deliver yet");
                ex.regs.set16(.eax, @intCast(quotient));
                ex.regs.set16(.edx, @intCast(dividend % divisor));
            } else {
                const dividend = (@as(u64, ex.regs.edx) << 32) | ex.regs.eax;
                if (divisor == 0) return stopRawUnsupported(ex, start_eip, decoded, "DIV by zero raises #DE, which this PE runner cannot deliver yet");
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u32)) return stopRawUnsupported(ex, start_eip, decoded, "DIV quotient overflow raises #DE, which this PE runner cannot deliver yet");
                ex.regs.eax = @intCast(quotient);
                ex.regs.edx = @intCast(dividend % divisor);
            }
        },
        .group3_idiv => {
            if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for IDIV");
            const divisor_bits: u64 = switch (decoded.operand.?) {
                .reg => |reg| readRegisterWidth(&ex.regs, reg, decoded.width),
                .mem => blk: {
                    const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "IDIV source address is invalid or unmapped");
                    break :blk readMemoryWidth(&ex.mem, address, decoded.width);
                },
            };
            if (decoded.width == .bits16) {
                const dividend_bits = (@as(u32, ex.regs.edx & 0xFFFF) << 16) | @as(u32, ex.regs.eax & 0xFFFF);
                const dividend: i32 = @bitCast(dividend_bits);
                const divisor: i16 = @bitCast(@as(u16, @truncate(divisor_bits)));
                if (divisor == 0) return stopRawUnsupported(ex, start_eip, decoded, "IDIV by zero raises #DE, which this PE runner cannot deliver yet");
                if (dividend == std.math.minInt(i32) and divisor == -1) {
                    return stopRawUnsupported(ex, start_eip, decoded, "IDIV quotient overflow raises #DE, which this PE runner cannot deliver yet");
                }
                const quotient = @divTrunc(dividend, @as(i32, divisor));
                if (quotient < std.math.minInt(i16) or quotient > std.math.maxInt(i16)) {
                    return stopRawUnsupported(ex, start_eip, decoded, "IDIV quotient overflow raises #DE, which this PE runner cannot deliver yet");
                }
                const remainder = @rem(dividend, @as(i32, divisor));
                ex.regs.set16(.eax, @bitCast(@as(i16, @intCast(quotient))));
                ex.regs.set16(.edx, @bitCast(@as(i16, @intCast(remainder))));
            } else {
                const dividend_bits = (@as(u64, ex.regs.edx) << 32) | @as(u64, ex.regs.eax);
                const dividend: i64 = @bitCast(dividend_bits);
                const divisor: i32 = @bitCast(@as(u32, @truncate(divisor_bits)));
                if (divisor == 0) return stopRawUnsupported(ex, start_eip, decoded, "IDIV by zero raises #DE, which this PE runner cannot deliver yet");
                if (dividend == std.math.minInt(i64) and divisor == -1) {
                    return stopRawUnsupported(ex, start_eip, decoded, "IDIV quotient overflow raises #DE, which this PE runner cannot deliver yet");
                }
                const quotient = @divTrunc(dividend, @as(i64, divisor));
                if (quotient < std.math.minInt(i32) or quotient > std.math.maxInt(i32)) {
                    return stopRawUnsupported(ex, start_eip, decoded, "IDIV quotient overflow raises #DE, which this PE runner cannot deliver yet");
                }
                const remainder = @rem(dividend, @as(i64, divisor));
                ex.regs.eax = @bitCast(@as(i32, @intCast(quotient)));
                ex.regs.edx = @bitCast(@as(i32, @intCast(remainder)));
            }
        },
        .imul_rm => {
            const destination = decoded.register.?;
            const source: u64 = switch (decoded.operand.?) {
                .reg => |reg| readRegisterWidth(&ex.regs, reg, decoded.width),
                .mem => blk: {
                    const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "IMUL source address is invalid or unmapped");
                    break :blk readMemoryWidth(&ex.mem, address, decoded.width);
                },
            };
            if (decoded.width == .bits16) {
                const lhs: i16 = @bitCast(ex.regs.get16(destination));
                const rhs: i16 = @bitCast(@as(u16, @truncate(source)));
                const product: i32 = @as(i32, lhs) * @as(i32, rhs);
                const low: u16 = @truncate(@as(u32, @bitCast(product)));
                const overflow = product != @as(i32, @as(i16, @bitCast(low)));
                ex.regs.set16(destination, low);
                ex.regs.flags.cf = @intFromBool(overflow);
                ex.regs.flags.of = @intFromBool(overflow);
            } else {
                const lhs: i32 = @bitCast(ex.regs.get(destination));
                const rhs: i32 = @bitCast(@as(u32, @truncate(source)));
                const product: i64 = @as(i64, lhs) * @as(i64, rhs);
                const low: u32 = @truncate(@as(u64, @bitCast(product)));
                const overflow = product != @as(i64, @as(i32, @bitCast(low)));
                ex.regs.set(destination, low);
                ex.regs.flags.cf = @intFromBool(overflow);
                ex.regs.flags.of = @intFromBool(overflow);
            }
        },
        .imul_immediate => {
            const destination = decoded.register.?;
            const source: u64 = switch (decoded.operand.?) {
                .reg => |reg| readRegisterWidth(&ex.regs, reg, decoded.width),
                .mem => blk: {
                    const address = checkedRawMoveAddress(ex, decoded, .read) orelse
                        return stopRawUnsupported(ex, start_eip, decoded, "IMUL source address is invalid or unmapped");
                    break :blk readMemoryWidth(&ex.mem, address, decoded.width);
                },
            };
            if (decoded.width == .bits16) {
                const lhs: i16 = @bitCast(@as(u16, @truncate(source)));
                const rhs: i16 = @bitCast(@as(u16, @truncate(decoded.immediate)));
                const product: i32 = @as(i32, lhs) * @as(i32, rhs);
                const low: u16 = @truncate(@as(u32, @bitCast(product)));
                const overflow = product != @as(i32, @as(i16, @bitCast(low)));
                ex.regs.set16(destination, low);
                ex.regs.flags.cf = @intFromBool(overflow);
                ex.regs.flags.of = @intFromBool(overflow);
            } else {
                const lhs: i32 = @bitCast(@as(u32, @truncate(source)));
                const rhs: i32 = @bitCast(decoded.immediate);
                const product: i64 = @as(i64, lhs) * @as(i64, rhs);
                const low: u32 = @truncate(@as(u64, @bitCast(product)));
                const overflow = product != @as(i64, @as(i32, @bitCast(low)));
                ex.regs.set(destination, low);
                ex.regs.flags.cf = @intFromBool(overflow);
                ex.regs.flags.of = @intFromBool(overflow);
            }
        },
        .inc_reg => executeRawIncDecRegister(ex, decoded, true),
        .dec_reg => executeRawIncDecRegister(ex, decoded, false),
        .group5_inc => {
            if (!executeRawGroup5IncDec(ex, decoded, start_eip, true)) return false;
        },
        .group5_dec => {
            if (!executeRawGroup5IncDec(ex, decoded, start_eip, false)) return false;
        },
        .group4_inc => {
            if (!executeRawGroup5IncDec(ex, decoded, start_eip, true)) return false;
        },
        .group4_dec => {
            if (!executeRawGroup5IncDec(ex, decoded, start_eip, false)) return false;
        },
        .group5_call => {
            const target = readRawRm32(ex, decoded) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "could not resolve CALL r/m32 target address");

            if (resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs)) |mem_addr| {
                if (!isGuestExecutableAddress(ex, target)) {
                    if (lookupIatEntry(ex, mem_addr)) |name| {
                        return dispatchIatCall(ex, start_eip, mem_addr, name, next_eip);
                    }
                }
            }
            if (!isGuestExecutableAddress(ex, target)) {
                if (lookupIatTarget(ex, target)) |import| {
                    return dispatchIatCall(ex, start_eip, import.address, import.name, next_eip);
                }
            }

            if (rawExecTraceEnabled() and !isGuestExecutableAddress(ex, target)) {
                const maybe_slot = resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs);
                std.debug.print("PE32_EXEC_UNRESOLVED_CALL eip=0x{X:0>8} slot=0x{X:0>8} has_slot={} target=0x{X:0>8} eax=0x{X:0>8} ecx=0x{X:0>8} edx=0x{X:0>8}\n", .{
                    start_eip,
                    maybe_slot orelse 0,
                    maybe_slot != null,
                    target,
                    ex.regs.eax,
                    ex.regs.ecx,
                    ex.regs.edx,
                });
            }

            reg_trace.logControlTransfer("call [r/m32]", start_eip, target, &ex.regs);
            stack_trace.logState("before_raw_call_indirect", .before_call, &ex.regs, &ex.mem);
            ex.push(next_eip);
            stack_trace.logState("after_raw_call_indirect_push", .after_call, &ex.regs, &ex.mem);
            ex.regs.eip = target;
            return validateControlTransferTarget(ex, start_eip, target, "call [r/m32]");
        },
        .group5_jmp => {
            const target = readRawRm32(ex, decoded) orelse
                return stopRawUnsupported(ex, start_eip, decoded, "could not resolve JMP r/m32 target address");

            if (resolveRawLinearAddr(decoded.operand.?, decoded.segment_override, &ex.regs)) |mem_addr| {
                if (!isGuestExecutableAddress(ex, target)) {
                    if (lookupIatEntry(ex, mem_addr)) |name| {
                        return dispatchIatJmp(ex, mem_addr, name);
                    }
                }
            }
            if (!isGuestExecutableAddress(ex, target)) {
                if (lookupIatTarget(ex, target)) |import| {
                    return dispatchIatJmp(ex, import.address, import.name);
                }
            }

            reg_trace.logControlTransfer("jmp [r/m32]", start_eip, target, &ex.regs);
            ex.regs.eip = target;
            return validateControlTransferTarget(ex, start_eip, target, "jmp [r/m32]");
        },
        .group5_push => {
            const value = readRawRm32(ex, decoded) orelse
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

fn readMemoryWidth(memory: *const reg_map.Memory, address: u32, width: highway.Width) u64 {
    return switch (width) {
        .bits8 => memory.read8(address),
        .bits16 => memory.read16(address),
        .bits32, .bits64 => memory.read32(address),
    };
}

fn writeMemoryWidth(memory: *reg_map.Memory, address: u32, width: highway.Width, value: u64) void {
    switch (width) {
        .bits8 => memory.write8(address, @truncate(value)),
        .bits16 => memory.write16(address, @truncate(value)),
        .bits32, .bits64 => memory.write32(address, @truncate(value)),
    }
}

fn rawSegmentBase(regs: *const reg_map.RegisterFile, segment: raw_decode.SegmentOverride) u32 {
    return switch (segment) {
        .cs => regs.cs_desc.base,
        .ds => regs.ds_desc.base,
        .es => regs.es_desc.base,
        .fs => regs.fs_desc.base,
        .gs => regs.gs_desc.base,
        .ss => regs.ss_desc.base,
    };
}

fn rawSegmentAddress(offset: u32, base: u32) ?u32 {
    const linear = @as(u64, base) + offset;
    if (linear > std.math.maxInt(u32)) return null;
    return @intCast(linear);
}

fn executeRawStringMovs(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32, next_eip: u32) bool {
    if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for MOVS");

    const count_before = if (decoded.repeated) ex.regs.ecx else 1;
    const source_before = ex.regs.esi;
    const destination_before = ex.regs.edi;
    const width_bytes: u32 = decoded.width.bits() / 8;
    const source_segment = decoded.segment_override orelse .ds;
    const source_base = rawSegmentBase(&ex.regs, source_segment);
    const destination_base = rawSegmentBase(&ex.regs, .es);
    var completed: u32 = 0;

    while (completed < count_before) {
        const source_address = rawSegmentAddress(ex.regs.esi, source_base) orelse
            return stopRawUnsupported(ex, start_eip, decoded, "MOVS source segment address overflowed PE32");
        const destination_address = rawSegmentAddress(ex.regs.edi, destination_base) orelse
            return stopRawUnsupported(ex, start_eip, decoded, "MOVS destination segment address overflowed PE32");
        const source_range = highway.validateRange(ex.mem.base, ex.mem.data.len, source_address, decoded.width, .read, true);
        if (!source_range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "MOVS source address is unmapped or unreadable");
        const destination_range = highway.validateRange(ex.mem.base, ex.mem.data.len, destination_address, decoded.width, .write, true);
        if (!destination_range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "MOVS destination address is unmapped or unwritable");

        const value = readMemoryWidth(&ex.mem, source_address, decoded.width);
        writeMemoryWidth(&ex.mem, destination_address, decoded.width, value);
        if (ex.regs.flags.df == 0) {
            ex.regs.esi +%= width_bytes;
            ex.regs.edi +%= width_bytes;
        } else {
            ex.regs.esi -%= width_bytes;
            ex.regs.edi -%= width_bytes;
        }
        if (decoded.repeated) ex.regs.ecx -%= 1;
        completed += 1;
    }

    if (decoded.repeated) {
        string_trace.validateStringOp(
            "raw_movs",
            .movs,
            .rep,
            &ex.regs,
            count_before,
            ex.regs.ecx,
            source_before,
            ex.regs.esi,
            destination_before,
            ex.regs.edi,
            @intCast(width_bytes),
            false,
            false,
        );
    }
    ex.regs.eip = next_eip;
    return true;
}

fn executeRawStringStos(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32, next_eip: u32) bool {
    if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for STOS");

    const count_before = if (decoded.repeated) ex.regs.ecx else 1;
    const source_before = ex.regs.esi;
    const destination_before = ex.regs.edi;
    const width_bytes: u32 = decoded.width.bits() / 8;
    const destination_base = rawSegmentBase(&ex.regs, .es);
    const value: u64 = switch (decoded.width) {
        .bits8 => ex.regs.eax & 0xFF,
        .bits16 => ex.regs.eax & 0xFFFF,
        .bits32, .bits64 => ex.regs.eax,
    };
    var completed: u32 = 0;

    while (completed < count_before) {
        const destination_address = rawSegmentAddress(ex.regs.edi, destination_base) orelse
            return stopRawUnsupported(ex, start_eip, decoded, "STOS destination segment address overflowed PE32");
        const destination_range = highway.validateRange(ex.mem.base, ex.mem.data.len, destination_address, decoded.width, .write, true);
        if (!destination_range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "STOS destination address is unmapped or unwritable");
        writeMemoryWidth(&ex.mem, destination_address, decoded.width, value);
        if (ex.regs.flags.df == 0)
            ex.regs.edi +%= width_bytes
        else
            ex.regs.edi -%= width_bytes;
        if (decoded.repeated) ex.regs.ecx -%= 1;
        completed += 1;
    }

    if (decoded.repeated) {
        string_trace.validateStringOp(
            "raw_stos",
            .stos,
            .rep,
            &ex.regs,
            count_before,
            ex.regs.ecx,
            source_before,
            source_before,
            destination_before,
            ex.regs.edi,
            @intCast(width_bytes),
            false,
            false,
        );
    }
    ex.regs.eip = next_eip;
    return true;
}

fn executeRawStringScas(ex: *Executor, decoded: raw_decode.DecodedInstruction, start_eip: u32, next_eip: u32) bool {
    if (decoded.locked) return stopRawUnsupported(ex, start_eip, decoded, "LOCK is invalid for SCAS");

    const count_before = if (decoded.repeated) ex.regs.ecx else 1;
    const destination_before = ex.regs.edi;
    const width_bytes: u32 = decoded.width.bits() / 8;
    const destination_base = rawSegmentBase(&ex.regs, .es);
    var completed: u32 = 0;
    var terminated_on_match = false;

    while (completed < count_before) {
        const destination_address = rawSegmentAddress(ex.regs.edi, destination_base) orelse
            return stopRawUnsupported(ex, start_eip, decoded, "SCAS destination segment address overflowed PE32");
        const destination_range = highway.validateRange(ex.mem.base, ex.mem.data.len, destination_address, decoded.width, .read, true);
        if (!destination_range.allowed()) return stopRawUnsupported(ex, start_eip, decoded, "SCAS destination address is unmapped or unreadable");

        const accumulator = readRegisterWidth(&ex.regs, .eax, decoded.width);
        const value = readMemoryWidth(&ex.mem, destination_address, decoded.width);
        applyRawMathFlags(&ex.regs, isa_math.sub(@enumFromInt(decoded.width.bits()), accumulator, value).flags);
        if (ex.regs.flags.df == 0)
            ex.regs.edi +%= width_bytes
        else
            ex.regs.edi -%= width_bytes;
        if (decoded.repeated) ex.regs.ecx -%= 1;
        completed += 1;

        if (ex.regs.flags.zf != 0) terminated_on_match = true;
        if (decoded.repeated and
            ((decoded.repeat_not_equal and ex.regs.flags.zf != 0) or
                (!decoded.repeat_not_equal and ex.regs.flags.zf == 0)))
        {
            break;
        }
    }

    if (decoded.repeated or completed != 0) {
        const trace_count_after = if (decoded.repeated) ex.regs.ecx else 0;
        const repeat_mode: string_trace.StringRepMode = if (!decoded.repeated)
            .none
        else if (decoded.repeat_not_equal)
            .repne
        else
            .repe;
        string_trace.validateStringOp(
            "raw_scas",
            .scas,
            repeat_mode,
            &ex.regs,
            count_before,
            trace_count_after,
            ex.regs.esi,
            ex.regs.esi,
            destination_before,
            ex.regs.edi,
            @intCast(width_bytes),
            terminated_on_match,
            false,
        );
    }
    ex.regs.eip = next_eip;
    return true;
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
        // A synthetic DllMain return address is consumed by the caller's
        // bounded loop immediately after RET. Validate the real instruction
        // boundary for all normal steps, while keeping this one stop token out
        // of the guest executable-address range checks.
        const validation_eip = if (ex.raw_stop_eip != 0 and ex.regs.eip == ex.raw_stop_eip) start_eip else ex.regs.eip;
        runtime_abi.x86.validateExecutorState("post-raw-step", ex.mem.base, ex.mem.data.len, validation_eip, ex.regs.esp, ex.regs.ebp, ex.regs.flags.raw());
        runtime_abi.x86.validateExtendedState("post-raw-step", ex.mem.base, ex.mem.data.len, validation_eip, ex.regs.esp, ex.regs.ebp, ex.regs.abiState());
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

test "raw PE FWAIT advances one byte without changing synchronous x87 state" {
    var ex = Executor.init(std.testing.allocator, 0x300000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00401000;
    const offset = ex.regs.eip - ex.mem.base;
    ex.mem.data[offset] = 0x9B;
    ex.regs.fpu.status = 0x1234;
    ex.regs.fpu.control = 0x027F;

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00401001), ex.regs.eip);
    try std.testing.expectEqual(@as(u16, 0x1234), ex.regs.fpu.status);
    try std.testing.expectEqual(@as(u16, 0x027F), ex.regs.fpu.control);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.pending_exception);
}

test "raw PE 16-bit MOV immediate preserves high register bits and instruction alignment" {
    var ex = Executor.init(std.testing.allocator, 0x300000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00401000;
    ex.regs.eax = 0xCAFE_0000;
    const program = [_]u8{ 0x66, 0xB8, 0x01, 0x00, 0xF6, 0xC2, 0x08 };
    const offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[offset .. offset + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00401004), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0xCAFE_0001), ex.regs.eax);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00401007), ex.regs.eip);
}

fn testIatImportHandler(ctx: *Executor) void {
    ctx.regs.eax = 0x12345678;
}

test "raw PE indirect register CALL resolves an IAT lookup value" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x0040F000;
    ex.regs.ebx = 0x0000BB44;
    try ex.import_table.put("GetProcessHeap", testIatImportHandler);
    clearIatEntries();
    defer clearIatEntries();
    addIatEntry(0x00402000, "GetProcessHeap");
    ex.mem.write32(0x00402000, 0x0000BB44);
    const code_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[code_offset .. code_offset + 2], &[_]u8{ 0xFF, 0xD3 }); // call ebx

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x12345678), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0x0040F000), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.pending_exception);
}

test "raw PE indirect CALL honors a guest-patched IAT function pointer" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x0040F000;
    try ex.import_table.put("GetProcessHeap", testIatImportHandler);
    clearIatEntries();
    defer clearIatEntries();
    addIatEntryForExecutor(&ex, 0x00400300, "GetProcessHeap");

    // The injected guest DLL replaces the imported API with its own code.
    ex.mem.write32(0x00400300, 0x00400200);
    const call = [_]u8{ 0xFF, 0x15, 0x00, 0x03, 0x40, 0x00 };
    const call_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[call_offset .. call_offset + call.len], &call);
    const hook = [_]u8{ 0xB8, 0xBE, 0xBA, 0xFE, 0xCA, 0xC3 }; // mov eax, 0xCAFEBABE; ret
    const hook_offset: usize = 0x200;
    @memcpy(ex.mem.data[hook_offset .. hook_offset + hook.len], &hook);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400200), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0x00400106), ex.mem.read32(ex.regs.esp));

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xCAFE_BABE), ex.regs.eax);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400106), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0x0040F000), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.pending_exception);
}

test "executor-owned IAT entries cannot resolve in a different PE address space" {
    var first = Executor.init(std.testing.allocator, 0x10000);
    defer first.deinit();
    first.mem.base = 0x00400000;
    try first.import_table.put("LoadLibraryA", testIatImportHandler);

    var second = Executor.init(std.testing.allocator, 0x10000);
    defer second.deinit();
    second.mem.base = 0x00400000;
    try second.import_table.put("LoadLibraryA", testIatImportHandler);

    clearIatEntries();
    defer clearIatEntries();
    first.mem.write32(0x00402000, 0x0000BBAA);
    second.mem.write32(0x00402000, 0x0000CCDD);
    addIatEntryForExecutor(&first, 0x00402000, "LoadLibraryA");

    try std.testing.expectEqual(@as(?u32, 0x0000BBAA), lookupIatFunctionPointer(&first, "LoadLibraryA"));
    try std.testing.expectEqual(@as(?u32, null), lookupIatFunctionPointer(&second, "LoadLibraryA"));
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

test "raw PE Group2 shifts execute register and signed memory forms" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00001234;
    ex.regs.ebp = 0x00400200;
    ex.mem.write32(0x00400208, 0x80000000);

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 7], &[_]u8{
        0xC1, 0xE0, 0x08, // shl eax, 8
        0xC1, 0x7D, 0x08, 0x08, // sar dword ptr [ebp+8], 8
    });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00123400), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x00400103), ex.regs.eip);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFF800000), ex.mem.read32(0x00400208));
    try std.testing.expectEqual(@as(u32, 0x00400107), ex.regs.eip);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);
}

test "raw PE SETcc writes condition results to byte register and memory" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.ebp = 0x00407000;
    ex.regs.eax = 0xAABBCC00;
    ex.regs.flags.zf = 1;
    const program = [_]u8{
        0x0F, 0x94, 0xC0, // sete al
        0x0F, 0x95, 0x45, 0xFC, // setne byte ptr [ebp-4]
        0x0F, 0x94, 0x45, 0xFB, // sete byte ptr [ebp-5]
    };
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xAABBCC01), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x00400103), ex.regs.eip);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u8, 0), ex.mem.read8(0x00406FFC));
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u8, 1), ex.mem.read8(0x00406FFB));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
}

test "raw PE legacy INC and DEC update width-specific flags while preserving carry" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0xFFFFFFFF;
    ex.regs.flags.cf = 1;
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 3], &[_]u8{ 0x40, 0x66, 0x48 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x0000FFFF), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);
}

test "raw PE TEST changes status flags without writing its memory operand" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00400200;
    ex.regs.ecx = 0xF0;
    ex.regs.flags.cf = 1;
    ex.regs.flags.of = 1;
    ex.mem.write32(ex.regs.eax, 0x0F);

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 2], &[_]u8{ 0x85, 0x08 }); // test [eax], ecx
    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x0F), ex.mem.read32(ex.regs.eax));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.of);
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
}

test "raw PE TEST accumulator-immediate updates flags without changing accumulator" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x1234_8000;
    const program = [_]u8{
        0xA8, 0x80, // test al, 0x80
        0x66, 0xA9, 0x02, 0x91, // test ax, 0x9102
        0xA9, 0x00, 0x00, 0x00, 0x80, // test eax, 0x80000000
    };
    @memcpy(ex.mem.data[0x100 .. 0x100 + program.len], &program);
    var thunks = ThunkTable{};

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1234_8000), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.sf);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1234_8000), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1234_8000), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.sf);
}

test "raw PE PUSHF and POPF round-trip user-writable flags at both stack widths" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00408000;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    ex.regs.flags.iopl = 0;
    ex.regs.flags.if_ = 1;
    const program = [_]u8{ 0x9C, 0x9D, 0x66, 0x9C, 0x66, 0x9D };
    @memcpy(ex.mem.data[0x100 .. 0x100 + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00407FFC), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0x0000_0243), ex.mem.read32(ex.regs.esp));
    ex.regs.flags.cf = 0;
    ex.regs.flags.zf = 0;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00408000), ex.regs.esp);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.if_);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00407FFE), ex.regs.esp);
    ex.regs.flags.cf = 0;
    ex.regs.flags.zf = 0;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00408000), ex.regs.esp);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
}

test "raw PE PUSHA and POPA preserve the original stack slot at both widths" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00408000;
    ex.regs.eax = 0xAAAA_0001;
    ex.regs.ecx = 0xBBBB_0002;
    ex.regs.edx = 0xCCCC_0003;
    ex.regs.ebx = 0xDDDD_0004;
    ex.regs.ebp = 0xEEEE_0005;
    ex.regs.esi = 0xFFFF_0006;
    ex.regs.edi = 0x9999_0007;
    const program = [_]u8{ 0x60, 0x61, 0x66, 0x60, 0x66, 0x61 };
    @memcpy(ex.mem.data[0x100 .. 0x100 + program.len], &program);
    var thunks = ThunkTable{};

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00407FE0), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0x9999_0007), ex.mem.read32(0x00407FE0));
    try std.testing.expectEqual(@as(u32, 0xFFFF_0006), ex.mem.read32(0x00407FE4));
    try std.testing.expectEqual(@as(u32, 0xEEEE_0005), ex.mem.read32(0x00407FE8));
    try std.testing.expectEqual(@as(u32, 0x00408000), ex.mem.read32(0x00407FEC));
    ex.regs.eax = 0;
    ex.regs.ecx = 0;
    ex.regs.edx = 0;
    ex.regs.ebx = 0;
    ex.regs.ebp = 0;
    ex.regs.esi = 0;
    ex.regs.edi = 0;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00408000), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0xAAAA_0001), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0xBBBB_0002), ex.regs.ecx);
    try std.testing.expectEqual(@as(u32, 0xCCCC_0003), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0xDDDD_0004), ex.regs.ebx);
    try std.testing.expectEqual(@as(u32, 0xEEEE_0005), ex.regs.ebp);
    try std.testing.expectEqual(@as(u32, 0xFFFF_0006), ex.regs.esi);
    try std.testing.expectEqual(@as(u32, 0x9999_0007), ex.regs.edi);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00407FF0), ex.regs.esp);
    try std.testing.expectEqual(@as(u16, 0x0007), ex.mem.read16(0x00407FF0));
    try std.testing.expectEqual(@as(u16, 0x8000), ex.mem.read16(0x00407FF6));
    ex.regs.eax = 0x1111_0000;
    ex.regs.ecx = 0x2222_0000;
    ex.regs.edx = 0x3333_0000;
    ex.regs.ebx = 0x4444_0000;
    ex.regs.ebp = 0x5555_0000;
    ex.regs.esi = 0x6666_0000;
    ex.regs.edi = 0x7777_0000;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00408000), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0x1111_0001), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x2222_0002), ex.regs.ecx);
    try std.testing.expectEqual(@as(u32, 0x3333_0003), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0x4444_0004), ex.regs.ebx);
    try std.testing.expectEqual(@as(u32, 0x5555_0005), ex.regs.ebp);
    try std.testing.expectEqual(@as(u32, 0x6666_0006), ex.regs.esi);
    try std.testing.expectEqual(@as(u32, 0x7777_0007), ex.regs.edi);
}

test "raw PE MOV r8 immediate preserves the rest of the legacy register" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x1234_5678;
    const program = [_]u8{ 0xB0, 0x25, 0xB4, 0x7F };
    @memcpy(ex.mem.data[0x100 .. 0x100 + program.len], &program);
    var thunks = ThunkTable{};

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1234_5625), ex.regs.eax);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1234_7F25), ex.regs.eax);
}

test "raw PE CPUID reports only the portable emulated CPU contract" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0;
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0x0F, 0xA2 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 1), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x756E_6547), ex.regs.ebx);
    try std.testing.expectEqual(@as(u32, 0x4965_6E69), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0x6C65_746E), ex.regs.ecx);

    ex.regs.eip = 0x00400100;
    ex.regs.eax = 1;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x0000_0600), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 1), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.ecx);
}

test "raw PE IDIV truncates signed quotient and remainder at word and dword widths" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0xFFFF_FFD6; // -42 low dword
    ex.regs.edx = 0xFFFF_FFFF; // high dword of signed -42
    ex.regs.ecx = 5;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    const flags_before = ex.regs.flags.raw();
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0xF7, 0xF9 }); // idiv ecx
    @memcpy(ex.mem.data[0x110..0x113], &[_]u8{ 0x66, 0xF7, 0xF9 }); // idiv cx

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFF8), ex.regs.eax); // -8
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFE), ex.regs.edx); // -2
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
    try std.testing.expectEqual(flags_before, ex.regs.flags.raw());

    ex.regs.eip = 0x00400110;
    ex.regs.eax = 0x1234_FFD6; // AX = -42
    ex.regs.edx = 0xABCD_FFFF; // DX:AX = -42
    ex.regs.ecx = 0x8765_0005; // CX = 5
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1234_FFF8), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0xABCD_FFFE), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0x00400113), ex.regs.eip);
    try std.testing.expectEqual(flags_before, ex.regs.flags.raw());
}

test "raw PE CWD and CDQ sign extend accumulator without changing flags" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x80000001;
    ex.regs.edx = 0x12345678;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    ex.regs.flags.sf = 1;
    const flags_before = ex.regs.flags.raw();
    @memcpy(ex.mem.data[0x100..0x101], &[_]u8{0x99});
    @memcpy(ex.mem.data[0x110..0x112], &[_]u8{ 0x66, 0x99 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0x00400101), ex.regs.eip);
    try std.testing.expectEqual(flags_before, ex.regs.flags.raw());

    ex.regs.eip = 0x00400110;
    ex.regs.eax = 0x12348001;
    ex.regs.edx = 0xABCD5678;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xABCDFFFF), ex.regs.edx);
    try std.testing.expectEqual(@as(u32, 0x00400112), ex.regs.eip);
    try std.testing.expectEqual(flags_before, ex.regs.flags.raw());
}

test "raw PE REP MOVS copies directionally with segment bases and count semantics" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.ds_desc.base = 0x00400000;
    ex.regs.es_desc.base = 0x00400000;
    ex.regs.esi = 0x200;
    ex.regs.edi = 0x300;
    ex.regs.ecx = 3;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    ex.mem.write32(0x00400200, 0x11223344);
    ex.mem.write32(0x00400204, 0x55667788);
    ex.mem.write32(0x00400208, 0x99AABBCC);
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0xF3, 0xA5 });
    @memcpy(ex.mem.data[0x110..0x112], &[_]u8{ 0xF3, 0xA4 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0x20C), ex.regs.esi);
    try std.testing.expectEqual(@as(u32, 0x30C), ex.regs.edi);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.ecx);
    try std.testing.expectEqual(@as(u32, 0x11223344), ex.mem.read32(0x00400300));
    try std.testing.expectEqual(@as(u32, 0x55667788), ex.mem.read32(0x00400304));
    try std.testing.expectEqual(@as(u32, 0x99AABBCC), ex.mem.read32(0x00400308));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);

    ex.regs.eip = 0x00400110;
    ex.regs.esi = 0x202;
    ex.regs.edi = 0x302;
    ex.regs.ecx = 3;
    ex.regs.flags.df = 1;
    @memcpy(ex.mem.data[0x200..0x203], &[_]u8{ 0x11, 0x22, 0x33 });
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x1FF), ex.regs.esi);
    try std.testing.expectEqual(@as(u32, 0x2FF), ex.regs.edi);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.ecx);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x11, 0x22, 0x33 }, ex.mem.data[0x300..0x303]);
}

test "raw PE MOVZX and MOVSX preserve source widths and sign behavior" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00400200;
    ex.regs.ecx = 0xABCDEF80;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    ex.mem.write16(0x00400200, 0xFEDC);
    @memcpy(ex.mem.data[0x100..0x103], &[_]u8{ 0x0F, 0xB7, 0x08 }); // movzx ecx, word ptr [eax]
    @memcpy(ex.mem.data[0x110..0x113], &[_]u8{ 0x0F, 0xBE, 0xC1 }); // movsx eax, cl

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x0000FEDC), ex.regs.ecx);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);

    ex.regs.eip = 0x00400110;
    ex.regs.ecx = 0xABCDEF80;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
}

test "raw PE REP STOS fills the destination with width-correct accumulator data" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.es_desc.base = 0x00400000;
    ex.regs.edi = 0x400;
    ex.regs.ecx = 3;
    ex.regs.eax = 0xAABBCCDD;
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0xF3, 0xAB }); // rep stosd

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.regs.ecx);
    try std.testing.expectEqual(@as(u32, 0x40C), ex.regs.edi);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), ex.mem.read32(0x00400400));
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), ex.mem.read32(0x00400404));
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), ex.mem.read32(0x00400408));
}

test "raw PE SCAS honors REPNE REPE direction flags and count semantics" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.es_desc.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.edi = 0x500;
    ex.regs.ecx = 4;
    ex.regs.eax = 0x00000000;
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0xF2, 0xAE }); // repne scasb
    @memcpy(ex.mem.data[0x110..0x112], &[_]u8{ 0xF3, 0xAE }); // repe scasb
    @memcpy(ex.mem.data[0x120..0x121], &[_]u8{0xAE}); // scasb
    @memcpy(ex.mem.data[0x500..0x504], &[_]u8{ 1, 2, 0, 3 });
    @memcpy(ex.mem.data[0x600..0x604], &[_]u8{ 0, 0, 1, 0 });
    ex.regs.flags.df = 0;

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x503), ex.regs.edi);
    try std.testing.expectEqual(@as(u32, 1), ex.regs.ecx);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);

    ex.regs.eip = 0x00400110;
    ex.regs.edi = 0x600;
    ex.regs.ecx = 4;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x603), ex.regs.edi);
    try std.testing.expectEqual(@as(u32, 1), ex.regs.ecx);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);

    ex.regs.eip = 0x00400120;
    ex.regs.edi = 0x700;
    ex.regs.ecx = 9;
    ex.regs.eax = 0x12340034;
    ex.regs.flags.df = 1;
    ex.mem.write8(0x00400700, 0x34);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x6FF), ex.regs.edi);
    try std.testing.expectEqual(@as(u32, 9), ex.regs.ecx);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u32, 0x12340034), ex.regs.eax);
}

test "raw PE CLD and STD only update the direction flag" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.flags.df = 1;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0xFC, 0xFD });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.df);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u32, 0x00400101), ex.regs.eip);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.df);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
}

test "raw PE accumulator XCHG swaps full and partial register widths without flags" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00408000;
    ex.regs.esp = 0x0040F000;
    ex.regs.flags.cf = 1;
    ex.regs.flags.zf = 1;
    @memcpy(ex.mem.data[0x100..0x101], &[_]u8{0x94}); // xchg eax, esp
    @memcpy(ex.mem.data[0x110..0x112], &[_]u8{ 0x66, 0x91 }); // xchg ax, cx

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x0040F000), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x00408000), ex.regs.esp);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);

    ex.regs.eip = 0x00400110;
    ex.regs.eax = 0x12340001;
    ex.regs.ecx = 0xABCD0002;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x12340002), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0xABCD0001), ex.regs.ecx);
}

test "raw PE NOT complements register and memory operands without changing flags" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00400200;
    ex.regs.esi = 0xA5A55A5A;
    ex.regs.flags.zf = 1;
    ex.regs.flags.cf = 1;
    const flags_before = ex.regs.flags.raw();
    ex.mem.write32(ex.regs.eax, 0x12345678);

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 4], &[_]u8{ 0xF7, 0x10, 0xF7, 0xD6 });
    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xEDCBA987), ex.mem.read32(ex.regs.eax));
    try std.testing.expectEqual(flags_before, ex.regs.flags.raw());
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x5A5AA5A5), ex.regs.esi);
    try std.testing.expectEqual(flags_before, ex.regs.flags.raw());
}

test "raw PE NEG handles register widths, arithmetic flags, and locked memory" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 5;
    @memcpy(ex.mem.data[0x100..0x102], &[_]u8{ 0xF7, 0xD8 }); // neg eax
    @memcpy(ex.mem.data[0x110..0x113], &[_]u8{ 0x66, 0xF7, 0xD8 }); // neg ax
    @memcpy(ex.mem.data[0x120..0x123], &[_]u8{ 0xF0, 0xF7, 0x18 }); // lock neg dword ptr [eax]
    @memcpy(ex.mem.data[0x130..0x132], &[_]u8{ 0xF7, 0x18 }); // neg dword ptr [eax]

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFB), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.of);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);

    ex.regs.eip = 0x00400110;
    ex.regs.eax = 0xABCD8000;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xABCD8000), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.of);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);

    ex.regs.eip = 0x00400120;
    ex.regs.eax = 0x00400300;
    ex.mem.write32(ex.regs.eax, 7);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFF9), ex.mem.read32(ex.regs.eax));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.of);

    ex.regs.eip = 0x00400130;
    ex.mem.write32(ex.regs.eax, 0);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.mem.read32(ex.regs.eax));
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
}

test "raw PE F6 TEST byte-immediate inspects memory without modifying it" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00400300;
    ex.mem.write8(ex.regs.eax + 0x70, 0x02);
    @memcpy(ex.mem.data[0x100..0x104], &[_]u8{ 0xF6, 0x40, 0x70, 0x02 });
    var thunks = ThunkTable{};

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u8, 0x02), ex.mem.read8(ex.regs.eax + 0x70));
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.cf);
}

test "raw PE F6 NEG and NOT use the selected high-byte register alias" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x12348005;
    @memcpy(ex.mem.data[0x100..0x106], &[_]u8{
        0xF6, 0xDC, // neg ah
        0xF6, 0xD4, // not ah
        0xF6, 0xD8, // neg al
    });
    var thunks = ThunkTable{};

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x12348005), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.of);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x12347F05), ex.regs.eax);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x12347FFB), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.of);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.sf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);
}

test "raw PE unsigned DIV writes quotient and remainder at operand width" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00000064;
    ex.regs.edx = 0;
    ex.regs.ecx = 10;
    const entry_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_offset .. entry_offset + 2], &[_]u8{ 0xF7, 0xF1 }); // div ecx

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 10), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0), ex.regs.edx);

    ex.regs.eip = 0x00400110;
    ex.regs.eax = 0xABCD0064;
    ex.regs.edx = 0x12340000;
    ex.regs.ecx = 10;
    const word_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[word_offset .. word_offset + 3], &[_]u8{ 0x66, 0xF7, 0xF1 }); // div cx
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xABCD000A), ex.regs.eax);
    try std.testing.expectEqual(@as(u32, 0x12340000), ex.regs.edx);
}

test "raw PE two-operand IMUL writes a signed product and overflow flags" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0xFFFFFFFE;
    ex.regs.ecx = 3;
    const entry_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_offset .. entry_offset + 3], &[_]u8{ 0x0F, 0xAF, 0xC1 }); // imul eax, ecx

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFA), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.of);

    ex.regs.eip = 0x00400110;
    ex.regs.eax = 0xABCDFFFE;
    ex.regs.ecx = 3;
    const word_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[word_offset .. word_offset + 4], &[_]u8{ 0x66, 0x0F, 0xAF, 0xC1 }); // imul ax, cx
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xABCDFFFA), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.cf);

    ex.regs.eip = 0x00400120;
    ex.regs.eax = 0x40000000;
    ex.regs.ecx = 4;
    const overflow_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[overflow_offset .. overflow_offset + 3], &[_]u8{ 0x0F, 0xAF, 0xC1 });
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.of);
}

test "raw PE LEAVE restores the saved frame and stack pointer" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00400180;
    ex.regs.ebp = 0x00400200;
    ex.mem.write32(ex.regs.ebp, 0xDEADBEEF);
    const entry_off = ex.regs.eip - ex.mem.base;
    ex.mem.data[entry_off] = 0xC9;

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), ex.regs.ebp);
    try std.testing.expectEqual(@as(u32, 0x00400204), ex.regs.esp);
    try std.testing.expectEqual(@as(u32, 0x00400101), ex.regs.eip);
}

test "raw PE FS override accesses the synthetic TEB base" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x0040F000;
    ex.regs.eax = 0xDEADBEEF;
    ex.regs.fs = 0x3B;
    ex.regs.fs_desc.base = 0x00408000;
    ex.regs.fs_desc.limit = 0xFFF;
    ex.mem.write32(0x00408000, std.math.maxInt(u32));

    const program = [_]u8{
        0x64, 0xFF, 0x35, 0, 0, 0, 0, // push dword ptr fs:[0]
        0x64, 0xA3, 0, 0, 0, 0, // mov dword ptr fs:[0], eax
    };
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(std.math.maxInt(u32), ex.mem.read32(ex.regs.esp));
    try std.testing.expectEqual(@as(u32, 0x00400107), ex.regs.eip);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), ex.mem.read32(ex.regs.fs_desc.base));
}

test "raw PE C6 and C7 write immediate byte, word, and dword memory" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.ebp = 0x00407000;
    const program = [_]u8{
        0xC7, 0x45, 0xFC, 0xFE, 0xFF, 0xFF, 0xFF,
        0xC6, 0x45, 0xF8, 0x7A, 0x66, 0xC7, 0x45,
        0xFA, 0x34, 0x12,
    };
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), ex.mem.read32(ex.regs.ebp - 4));
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u8, 0x7A), ex.mem.read8(ex.regs.ebp - 8));
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u16, 0x1234), ex.mem.read16(ex.regs.ebp - 6));
}

test "raw PE MOV register, memory, byte-alias, and operand-size forms execute" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00408000;
    ex.regs.ebp = 0x00407000;
    ex.regs.ecx = 0x00400200;

    // mov ebp, esp; mov [ecx], eax; mov edx, [ecx]
    // mov [ecx], ah; mov ah, [ecx]; mov bp, ax
    const program = [_]u8{
        0x8B, 0xEC,
        0x89, 0x01,
        0x8B, 0x11,
        0x88, 0x21,
        0x8A, 0x21,
        0x66, 0x8B,
        0xE8, 0xA1,
        0x00, 0x03,
        0x40, 0x00,
    };
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(ex.regs.esp, ex.regs.ebp);

    ex.regs.eax = 0x11223344;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x11223344), ex.mem.read32(ex.regs.ecx));
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x11223344), ex.regs.edx);

    ex.regs.eax = 0xAABBCCDD;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u8, 0xCC), ex.mem.read8(ex.regs.ecx));
    ex.regs.eax = 0x00110022;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x0011CC22), ex.regs.eax);

    ex.regs.ebp = 0x00401234;
    ex.regs.eax = 0xABCD5678;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00405678), ex.regs.ebp);

    ex.mem.write32(0x00400300, 0x89ABCDEF);
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x89ABCDEF), ex.regs.eax);
}

test "raw PE accumulator immediate arithmetic executes through the ISA highway" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = std.math.maxInt(u32);
    const entry_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_offset .. entry_offset + 5], &[_]u8{ 0x05, 1, 0, 0, 0 }); // add eax, 1

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
}

test "raw PE Group5 INC and DEC update memory and preserve carry" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esi = 0x00407000;
    ex.regs.flags.cf = 1;
    ex.mem.write32(0x00407008, 0xFFFFFFFF);
    const program = [_]u8{
        0xFF, 0x46, 0x08, // inc dword ptr [esi+8]
        0xFF, 0x4E, 0x08, // dec dword ptr [esi+8]
        0x66, 0xFF, 0x46, 0x08, // inc word ptr [esi+8]
    };
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + program.len], &program);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0), ex.mem.read32(0x00407008));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), ex.mem.read32(0x00407008));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
    try std.testing.expectEqual(@as(u32, 0x00400106), ex.regs.eip);

    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0xFFFF0000), ex.mem.read32(0x00407008));
    try std.testing.expectEqual(@as(u1, 1), ex.regs.flags.cf);
}

test "raw PE short conditional branch follows the guest status flags" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x0040FFF0;
    ex.regs.ebp = ex.regs.esp;

    const taken_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[taken_offset .. taken_offset + 2], &[_]u8{ 0x74, 0x02 });
    ex.regs.flags.zf = 1;
    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400104), ex.regs.eip);

    ex.regs.eip = 0x00400110;
    const not_taken_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[not_taken_offset .. not_taken_offset + 2], &[_]u8{ 0x74, 0x02 });
    ex.regs.flags.zf = 0;
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400112), ex.regs.eip);
}

test "raw PE near conditional branch follows the guest status flags" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.flags.zf = 1;
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 6], &[_]u8{ 0x0F, 0x84, 0x02, 0, 0, 0 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400108), ex.regs.eip);
}

test "raw PE RET imm16 pops return address and applies stack cleanup" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00408000;
    const entry_offset = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_offset .. entry_offset + 3], &[_]u8{ 0xC2, 0x04, 0x00 });
    ex.mem.write32(ex.regs.esp, 0x00400200);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00400200), ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0x00408008), ex.regs.esp);
}

test "raw PE synthetic DLL return boundary is accepted without mapping executable memory" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00408000;
    ex.raw_stop_eip = 0xFFFF_FF00;
    ex.mem.data[0x100] = 0xC3;
    ex.mem.write32(ex.regs.esp, ex.raw_stop_eip);

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(ex.raw_stop_eip, ex.regs.eip);
    try std.testing.expectEqual(@as(u32, 0x00408004), ex.regs.esp);
}

test "raw PE LEA computes an effective address without reading memory" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.esp = 0x00408000;
    ex.regs.ebp = ex.regs.esp;
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 4], &[_]u8{ 0x8D, 0x74, 0x24, 0x10 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x00408010), ex.regs.esi);
    try std.testing.expectEqual(@as(u32, 0x00400104), ex.regs.eip);
}

test "raw PE LEA wraps 32-bit scaled effective address arithmetic" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.ecx = 0x40000000;
    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 3], &[_]u8{ 0x8D, 0x0C, 0x89 }); // lea ecx, [ecx+ecx*4]

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 0x40000000), ex.regs.ecx);
    try std.testing.expectEqual(@as(u32, 0x00400103), ex.regs.eip);
}

test "raw PE memory arithmetic executes through the ISA transaction highway" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00400200;
    ex.regs.ecx = 3;
    ex.mem.write32(ex.regs.eax, 10);

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 2], &[_]u8{ 0x29, 0x08 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 7), ex.mem.read32(ex.regs.eax));
    try std.testing.expectEqual(@as(u1, 0), ex.regs.flags.zf);
    try std.testing.expectEqual(@as(u32, 0x00400102), ex.regs.eip);
}

test "raw PE byte arithmetic preserves AH CH DH BH aliases" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x0000_0200;
    ex.regs.ecx = 0x0000_0500;

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 2], &[_]u8{ 0x28, 0xE5 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u8, 3), ex.regs.getByte(.{ .base = .ecx, .high = true }));
    try std.testing.expectEqual(@as(u8, 2), ex.regs.getByte(.{ .base = .eax, .high = true }));
}

test "raw PE LOCK memory immediate commits one highway transaction" {
    var ex = Executor.init(std.testing.allocator, 0x10000);
    defer ex.deinit();
    ex.setRawX86PeMode();
    ex.mem.base = 0x00400000;
    ex.regs.eip = 0x00400100;
    ex.regs.eax = 0x00400201;
    ex.mem.write32(ex.regs.eax, 10);

    const entry_off = ex.regs.eip - ex.mem.base;
    @memcpy(ex.mem.data[entry_off .. entry_off + 4], &[_]u8{ 0xF0, 0x83, 0x28, 0x01 });

    var thunks = ThunkTable{};
    try std.testing.expect(execNext(&ex, &thunks));
    try std.testing.expectEqual(@as(u32, 9), ex.mem.read32(ex.regs.eax));
}
