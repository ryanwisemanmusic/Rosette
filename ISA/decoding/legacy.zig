//! Family: legacy — legacy 1-byte opcodes: MOV family + main dispatch + accumulator immediates.
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const addressing = @import("addressing.zig");
const groups = @import("groups.zig");
const twobyte = @import("twobyte.zig");
const pref = @import("prefix.zig");
const vexmod = @import("vex.zig");
const LegacyPrefixes = pref.LegacyPrefixes;
const VexPrefix = pref.VexPrefix;
const EvexPrefix = pref.EvexPrefix;
const decodeLegacyPrefixes = pref.decodeLegacyPrefixes;
const decodeVexPrefix = pref.decodeVexPrefix;
const decodeEvexPrefix = pref.decodeEvexPrefix;
const decodeVexInstruction = vexmod.decodeVexInstruction;
const decodeVex2 = vexmod.decodeVex2;
const decodeVex3 = vexmod.decodeVex3;
const decodeVexHalfMove = vexmod.decodeVexHalfMove;
const decodeVexDuplicateMove = vexmod.decodeVexDuplicateMove;
const highway = types.highway;
const isa_decode = types.isa_decode;
const capabilities = types.capabilities;
const OperandSize = types.OperandSize;
const Condition = types.Condition;
const Size = types.Size;
const Cond = types.Cond;
const RegId = types.RegId;
const Regs = types.Regs;
const Segment = types.Segment;
const SegmentState = types.SegmentState;
const ExecutionMode = types.ExecutionMode;
const MemoryReferenceKind = types.MemoryReferenceKind;
const RFL_CF = types.RFL_CF;
const RFL_PF = types.RFL_PF;
const RFL_AF = types.RFL_AF;
const RFL_ZF = types.RFL_ZF;
const RFL_SF = types.RFL_SF;
const RFL_OF = types.RFL_OF;
const statusByteForLahf = types.statusByteForLahf;
const applySahf = types.applySahf;
const BitTestOperation = types.BitTestOperation;
const bitTestRegister = types.bitTestRegister;
const bitTestAndResetRegister = types.bitTestAndResetRegister;
const bitTestMemoryOperand = types.bitTestMemoryOperand;
const bitTestMemoryOperandImmediate = types.bitTestMemoryOperandImmediate;
const RegisterOperand = types.RegisterOperand;
const MemoryOperand = types.MemoryOperand;
const RmOperand = types.RmOperand;
const DecodedModRm = types.DecodedModRm;
const applySub = types.applySub;
const applySbb = types.applySbb;
const applyAdd = types.applyAdd;
const applyIncDec = types.applyIncDec;
const applyLogic = types.applyLogic;
const evalCond = types.evalCond;
const regVal = types.regVal;
const setReg = types.setReg;
const BitScanKind = types.BitScanKind;
const BitScanResult = types.BitScanResult;
const PopulationCountResult = types.PopulationCountResult;
const Op = types.Op;
const DecodedInsn = types.DecodedInsn;
const decodeRegister = addressing.decodeRegister;
const defaultSegment = addressing.defaultSegment;
const selectSegment = addressing.selectSegment;
const segmentBase = addressing.segmentBase;
const resolveMemoryAddress = addressing.resolveMemoryAddress;
const decodeMemoryOperand = addressing.decodeMemoryOperand;
const decodeModRm = addressing.decodeModRm;
const hasModRM = addressing.hasModRM;
const mapReg = addressing.mapReg;
const mapJccCond8 = addressing.mapJccCond8;
const mapJccCond32 = addressing.mapJccCond32;
const readModRM = addressing.readModRM;
const decodeArithRmReg = groups.decodeArithRmReg;
const decodeMovRmReg = groups.decodeMovRmReg;
const decodeLea = groups.decodeLea;
const decodePopRm = groups.decodePopRm;
const decodeGroup1Imm = groups.decodeGroup1Imm;
const decodeGroup2Shift = groups.decodeGroup2Shift;
const decodeMovMemImm = groups.decodeMovMemImm;
const decodeGroup3 = groups.decodeGroup3;
const decodeGroup4_5 = groups.decodeGroup4_5;
const decodeTestRmReg = groups.decodeTestRmReg;
const decodeXchgRmReg = groups.decodeXchgRmReg;
const decodeImulImm = groups.decodeImulImm;
const decodeImulTwoOp = groups.decodeImulTwoOp;
const decodeCmpxchg = groups.decodeCmpxchg;
const decodeMovzx = groups.decodeMovzx;
const decodeMovsx = groups.decodeMovsx;
const decodeXadd = groups.decodeXadd;
const decodeSetcc = groups.decodeSetcc;
const decodeMovupsMovss = groups.decodeMovupsMovss;
const decodeMovaps = groups.decodeMovaps;
const decodeTwoByte = twobyte.decodeTwoByte;
const decodeThreeByte = twobyte.decodeThreeByte;
const decodeSseBytes = twobyte.decodeSseBytes;

// F2 (throughput audit): `inline` so a register operand costs an indexed load
// at the call site rather than a call frame around one. `execute` reads or
// writes a register several times per interpreted instruction.
pub inline fn registerOperandValue(regs: *const Regs, operand: RegisterOperand, size: OperandSize) u64 {
    if (!operand.high8) return regVal(regs, operand.id, size);
    std.debug.assert(size == .bits8);
    return (regVal(regs, operand.id, .bits16) >> 8) & 0xFF;
}

pub inline fn setRegisterOperand(regs: *Regs, operand: RegisterOperand, size: OperandSize, value: u64) void {
    if (!operand.high8) {
        setReg(regs, operand.id, size, value);
        return;
    }
    std.debug.assert(size == .bits8);
    const old = regVal(regs, operand.id, .bits16);
    setReg(regs, operand.id, .bits16, (old & 0x00FF) | ((value & 0xFF) << 8));
}

fn operandSizeForW(prefixes: LegacyPrefixes, byte_form: bool) OperandSize {
    if (byte_form) return .bits8;
    if (prefixes.operand_size_override) return .bits16;
    if (prefixes.rexW()) return .bits64;
    return .bits32;
}

fn setMemory(decoded: *DecodedInsn, memory: MemoryOperand) void {
    decoded.addr = memory.displacement;
    decoded.sib_has_index = memory.has_index;
    decoded.sib_index_reg = memory.index_reg;
    decoded.sib_scale = memory.scale;
    decoded.sib_has_base = memory.has_base;
    decoded.sib_base_reg = memory.base_reg;
    decoded.rip_relative = memory.rip_relative;
    decoded.segment = memory.segment;
}

fn movRegRegOp(size: OperandSize) Op {
    return switch (size) {
        .bits8 => .mov_reg8_reg8,
        .bits16 => .mov_reg16_reg16,
        .bits32 => .mov_reg32_reg32,
        .bits64 => .mov_reg64_reg64,
    };
}

fn movRegMemOp(size: OperandSize) Op {
    return switch (size) {
        .bits8 => .mov_reg8_mem8,
        .bits16 => .mov_reg16_mem16,
        .bits32 => .mov_reg32_mem32,
        .bits64 => .mov_reg64_mem64,
    };
}

fn movMemRegOp(size: OperandSize) Op {
    return switch (size) {
        .bits8 => .mov_mem8_reg8,
        .bits16 => .mov_mem16_reg16,
        .bits32 => .mov_mem32_reg32,
        .bits64 => .mov_mem64_reg64,
    };
}

fn movMemImmOp(size: OperandSize) Op {
    return switch (size) {
        .bits8 => .mov_mem8_imm8,
        .bits16 => .mov_mem16_imm16,
        .bits32 => .mov_mem32_imm32,
        .bits64 => .mov_mem64_imm32,
    };
}

fn readUnsignedImmediate(bytes: []const u8, pos: *usize, byte_count: usize) ?u64 {
    if (pos.* + byte_count > bytes.len) return null;
    const value: u64 = switch (byte_count) {
        1 => bytes[pos.*],
        2 => std.mem.readInt(u16, bytes[pos.*..][0..2], .little),
        4 => std.mem.readInt(u32, bytes[pos.*..][0..4], .little),
        8 => std.mem.readInt(u64, bytes[pos.*..][0..8], .little),
        else => unreachable,
    };
    pos.* += byte_count;
    return value;
}

/// Decode the ModR/M byte following a VEX prefix and parse the operand
/// information common to all VEX-encoded instructions. Handles register
/// and memory forms with SIB/displacement.
pub fn decodeLegacyMov(bytes: []const u8, pos: *usize, prefixes: LegacyPrefixes, opcode: u8) ?DecodedInsn {
    switch (opcode) {
        0x88...0x8B => {
            const size = operandSizeForW(prefixes, opcode & 1 == 0);
            const operands = decodeModRm(bytes, pos, prefixes, size == .bits8) orelse return null;
            const load = opcode & 2 != 0;
            var decoded = DecodedInsn{
                .size = size,
                .len = @intCast(pos.*),
                .has_0x67 = prefixes.address_size_override,
                .lock = prefixes.lock,
            };
            switch (operands.rm) {
                .register => |rm_reg| {
                    decoded.op = movRegRegOp(size);
                    const dst = if (load) operands.reg else rm_reg;
                    const src = if (load) rm_reg else operands.reg;
                    decoded.dst_reg = dst.id;
                    decoded.dst_high8 = dst.high8;
                    decoded.src_reg = src.id;
                    decoded.src_high8 = src.high8;
                    decoded.is_reg_form = true;
                },
                .memory => |memory| {
                    decoded.op = if (load) movRegMemOp(size) else movMemRegOp(size);
                    if (load) {
                        decoded.dst_reg = operands.reg.id;
                        decoded.dst_high8 = operands.reg.high8;
                    } else {
                        decoded.src_reg = operands.reg.id;
                        decoded.src_high8 = operands.reg.high8;
                    }
                    setMemory(&decoded, memory);
                },
            }
            return decoded;
        },
        0xA0...0xA3 => {
            const load = opcode < 0xA2;
            const size = operandSizeForW(prefixes, opcode & 1 == 0);
            const address_bytes: usize = if (prefixes.address_size_override) 4 else 8;
            const address = readUnsignedImmediate(bytes, pos, address_bytes) orelse return null;
            return .{
                .op = if (load) movRegMemOp(size) else movMemRegOp(size),
                .size = size,
                .dst_reg = .al_ax_eax_rax,
                .src_reg = .al_ax_eax_rax,
                .addr = address,
                .len = @intCast(pos.*),
                .has_0x67 = prefixes.address_size_override,
                .lock = prefixes.lock,
            };
        },
        0xB0...0xB7 => {
            const register = decodeRegister(opcode - 0xB0, prefixes.rexB(), true, prefixes.has_rex);
            const immediate = readUnsignedImmediate(bytes, pos, 1) orelse return null;
            return .{
                .op = .mov_reg_imm,
                .size = .bits8,
                .dst_reg = register.id,
                .dst_high8 = register.high8,
                .imm = immediate,
                .len = @intCast(pos.*),
                .has_0x67 = prefixes.address_size_override,
                .lock = prefixes.lock,
            };
        },
        0xB8...0xBF => {
            const size = operandSizeForW(prefixes, false);
            const register = decodeRegister(opcode - 0xB8, prefixes.rexB(), false, prefixes.has_rex);
            const immediate_bytes: usize = switch (size) {
                .bits16 => 2,
                .bits32 => 4,
                .bits64 => 8,
                .bits8 => unreachable,
            };
            const immediate = readUnsignedImmediate(bytes, pos, immediate_bytes) orelse return null;
            return .{
                .op = .mov_reg_imm,
                .size = size,
                .dst_reg = register.id,
                .imm = immediate,
                .len = @intCast(pos.*),
                .has_0x67 = prefixes.address_size_override,
                .lock = prefixes.lock,
            };
        },
        0xC6, 0xC7 => {
            const size = operandSizeForW(prefixes, opcode == 0xC6);
            const operands = decodeModRm(bytes, pos, prefixes, size == .bits8) orelse return null;
            if (operands.group != 0) return null;
            const immediate_bytes: usize = switch (size) {
                .bits8 => 1,
                .bits16 => 2,
                .bits32, .bits64 => 4,
            };
            var immediate = readUnsignedImmediate(bytes, pos, immediate_bytes) orelse return null;
            if (size == .bits64) immediate = @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(immediate))))));
            var decoded = DecodedInsn{
                .size = size,
                .imm = immediate,
                .len = @intCast(pos.*),
                .has_0x67 = prefixes.address_size_override,
                .lock = prefixes.lock,
            };
            switch (operands.rm) {
                .register => |register| {
                    decoded.op = .mov_reg_imm;
                    decoded.dst_reg = register.id;
                    decoded.dst_high8 = register.high8;
                    decoded.is_reg_form = true;
                },
                .memory => |memory| {
                    decoded.op = movMemImmOp(size);
                    setMemory(&decoded, memory);
                },
            }
            return decoded;
        },
        else => return null,
    }
}

fn decodeMovForTest(bytes: []const u8) ?DecodedInsn {
    const prefixes = decodeLegacyPrefixes(bytes);
    if (prefixes.len >= bytes.len) return null;
    var pos = prefixes.len;
    const opcode = bytes[pos];
    pos += 1;
    return decodeLegacyMov(bytes, &pos, prefixes, opcode);
}

test "shared MOV decoder covers width direction and extended registers" {
    const Case = struct {
        bytes: []const u8,
        op: Op,
        size: OperandSize,
        dst: RegId,
        src: RegId,
    };
    const cases = [_]Case{
        .{ .bytes = &.{ 0x88, 0xD3 }, .op = .mov_reg8_reg8, .size = .bits8, .dst = .bl_bx_ebx_rbx, .src = .dl_dx_edx_rdx },
        .{ .bytes = &.{ 0x8A, 0xDA }, .op = .mov_reg8_reg8, .size = .bits8, .dst = .bl_bx_ebx_rbx, .src = .dl_dx_edx_rdx },
        .{ .bytes = &.{ 0x66, 0x89, 0xD8 }, .op = .mov_reg16_reg16, .size = .bits16, .dst = .al_ax_eax_rax, .src = .bl_bx_ebx_rbx },
        .{ .bytes = &.{ 0x89, 0xD8 }, .op = .mov_reg32_reg32, .size = .bits32, .dst = .al_ax_eax_rax, .src = .bl_bx_ebx_rbx },
        .{ .bytes = &.{ 0x48, 0x89, 0xD8 }, .op = .mov_reg64_reg64, .size = .bits64, .dst = .al_ax_eax_rax, .src = .bl_bx_ebx_rbx },
        .{ .bytes = &.{ 0x4D, 0x89, 0xC8 }, .op = .mov_reg64_reg64, .size = .bits64, .dst = .r8b_r8w_r8d_r8, .src = .r9b_r9w_r9d_r9 },
    };
    for (cases) |case| {
        const decoded = decodeMovForTest(case.bytes) orelse return error.ExpectedMov;
        try std.testing.expectEqual(case.op, decoded.op);
        try std.testing.expectEqual(case.size, decoded.size);
        try std.testing.expectEqual(case.dst, decoded.dst_reg);
        try std.testing.expectEqual(case.src, decoded.src_reg);
        try std.testing.expect(decoded.is_reg_form);
    }
}

test "shared MOV decoder covers SIB displacement and immediate forms" {
    const load = decodeMovForTest(&[_]u8{ 0x48, 0x8B, 0x44, 0x8B, 0xF0 }) orelse return error.ExpectedMov;
    try std.testing.expectEqual(Op.mov_reg64_mem64, load.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load.dst_reg);
    try std.testing.expect(load.sib_has_base);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, load.sib_base_reg);
    try std.testing.expect(load.sib_has_index);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load.sib_index_reg);
    try std.testing.expectEqual(@as(u2, 2), load.sib_scale);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), load.addr);

    const imm16 = decodeMovForTest(&[_]u8{ 0x66, 0xC7, 0xC0, 0x34, 0x12 }) orelse return error.ExpectedMov;
    try std.testing.expectEqual(Op.mov_reg_imm, imm16.op);
    try std.testing.expectEqual(OperandSize.bits16, imm16.size);
    try std.testing.expectEqual(@as(u64, 0x1234), imm16.imm);
    try std.testing.expectEqual(@as(u8, 5), imm16.len);

    const imm64_memory = decodeMovForTest(&[_]u8{ 0x48, 0xC7, 0x45, 0xF8, 0xFF, 0xFF, 0xFF, 0xFF }) orelse return error.ExpectedMov;
    try std.testing.expectEqual(Op.mov_mem64_imm32, imm64_memory.op);
    try std.testing.expectEqual(std.math.maxInt(u64), imm64_memory.imm);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, imm64_memory.sib_base_reg);

    const fs_load = decodeMovForTest(&[_]u8{ 0x64, 0x48, 0x8B, 0x45, 0xF8 }) orelse return error.ExpectedMov;
    try std.testing.expectEqual(Segment.fs, fs_load.segment);
    const stack_load = decodeMovForTest(&[_]u8{ 0x48, 0x8B, 0x45, 0xF8 }) orelse return error.ExpectedMov;
    try std.testing.expectEqual(Segment.ss, stack_load.segment);
}

test "shared VEX decoder handles both VMOVD transfer directions" {
    const to_gpr = decodeVexInstruction(&[_]u8{ 0xC5, 0xF9, 0x7E, 0xC0 }) orelse
        return error.ExpectedVmovd;
    try std.testing.expectEqual(Op.vmovd_reg32_xmm, to_gpr.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, to_gpr.dst_reg);
    try std.testing.expectEqual(@as(u8, 0), to_gpr.xmm_src);
    try std.testing.expectEqual(OperandSize.bits32, to_gpr.size);
    try std.testing.expectEqual(@as(u8, 4), to_gpr.len);

    const to_xmm = decodeVexInstruction(&[_]u8{ 0xC5, 0xF9, 0x6E, 0xC8 }) orelse
        return error.ExpectedVmovd;
    try std.testing.expectEqual(Op.vmovd_xmm_reg32, to_xmm.op);
    try std.testing.expectEqual(@as(u8, 1), to_xmm.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, to_xmm.src_reg);

    const to_memory = decodeVexInstruction(&[_]u8{ 0xC5, 0xF9, 0x7E, 0x09 }) orelse
        return error.ExpectedVmovd;
    try std.testing.expectEqual(Op.vmovd_mem32_xmm, to_memory.op);
    try std.testing.expectEqual(@as(u8, 1), to_memory.xmm_src);
    try std.testing.expect(!to_memory.is_reg_form);
}

test "shared VEX decoder recognizes broadcast families" {
    const scalar_single = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE2, 0x79, 0x18, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.vbroadcastss, scalar_single.op);
    try std.testing.expectEqual(OperandSize.bits32, scalar_single.size);
    try std.testing.expect(!scalar_single.vector_256);
    try std.testing.expect(!scalar_single.is_reg_form);
    try std.testing.expectEqual(@as(u64, 0x10), scalar_single.addr);
    try std.testing.expectEqual(@as(u8, 9), scalar_single.len);

    const wide_double = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE2, 0x7D, 0x19, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.vbroadcastsd, wide_double.op);
    try std.testing.expectEqual(OperandSize.bits64, wide_double.size);
    try std.testing.expect(wide_double.vector_256);

    const invalid_double_width = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE2, 0xF9, 0x19, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.invalid, invalid_double_width.op);

    const wide_single = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE2, 0x7D, 0x18, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.vbroadcastss, wide_single.op);
    try std.testing.expect(wide_single.vector_256);

    const wide_integer = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE2, 0x7D, 0x5A, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.vbroadcasti128, wide_integer.op);
    try std.testing.expect(wide_integer.vector_256);

    const missing_reserved_vvvv = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE2, 0x41, 0x18, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.invalid, missing_reserved_vvvv.op);
}

test "shared VEX decoder recognizes VMOVQ memory stores" {
    const decoded = decodeLegacyInstruction(
        &[_]u8{ 0xC5, 0xF9, 0xD6, 0x05, 0x10, 0x00, 0x00, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.vmovq_mem64_xmm, decoded.op);
    try std.testing.expectEqual(OperandSize.bits64, decoded.size);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try std.testing.expect(!decoded.is_reg_form);
    try std.testing.expectEqual(@as(u64, 0x10), decoded.addr);
}

test "shared VEX decoder recognizes VPERMILPD immediate form" {
    const decoded = decodeLegacyInstruction(
        &[_]u8{ 0xC4, 0xE3, 0x79, 0x05, 0x94, 0x24, 0xA8, 0x00, 0x00, 0x00, 0x01 },
        .long64,
    );
    try std.testing.expectEqual(Op.vpermilpd, decoded.op);
    try std.testing.expectEqual(@as(u8, 2), decoded.xmm_dst);
    try std.testing.expect(!decoded.is_reg_form);
    try std.testing.expect(decoded.uses_imm);
    try std.testing.expectEqual(@as(u64, 1), decoded.imm);
    try std.testing.expectEqual(@as(u64, 0xA8), decoded.addr);
    try std.testing.expectEqual(@as(u8, 11), decoded.len);
}

test "shared legacy path decodes Xenia VMINSD absolute SIB form" {
    const decoded = decodeLegacyInstruction(
        &[_]u8{ 0xC5, 0xDB, 0x5D, 0x0C, 0x25, 0x10, 0xC4, 0x77, 0x06 },
        .long64,
    );
    try std.testing.expectEqual(Op.vminsd, decoded.op);
    try std.testing.expectEqual(@as(u8, 9), decoded.len);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 4), decoded.xmm_src);
    try std.testing.expect(!decoded.is_reg_form);
    try std.testing.expectEqual(@as(u64, 0x0677_C410), decoded.addr);
}

test "shared VEX decoder owns MXCSR transfer encodings" {
    const load = decodeVexInstruction(&[_]u8{ 0xC5, 0xF8, 0xAE, 0x56, 0xF0 }) orelse
        return error.ExpectedVldmxcsr;
    try std.testing.expectEqual(Op.ldmxcsr_mem32, load.op);
    try std.testing.expectEqual(OperandSize.bits32, load.size);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), load.addr);
    try std.testing.expectEqual(@as(u8, 5), load.len);

    const store = decodeVexInstruction(&[_]u8{ 0xC5, 0xF8, 0xAE, 0x5F, 0x20 }) orelse
        return error.ExpectedVstmxcsr;
    try std.testing.expectEqual(Op.stmxcsr_mem32, store.op);
    try std.testing.expectEqual(@as(u64, 0x20), store.addr);
    try std.testing.expectEqual(@as(u8, 5), store.len);

    // The VEX register form is reserved and must remain invalid rather than
    // aliasing a fence or silently becoming a NOP.
    try std.testing.expect(decodeVexInstruction(&[_]u8{ 0xC5, 0xF8, 0xAE, 0xD0 }) == null);
}

test "shared legacy path decodes VEX BMI GPR operands" {
    const shlx = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE2, 0xC1, 0xF7, 0xC0 }, .long64);
    try std.testing.expectEqual(Op.shlx, shlx.op);
    try std.testing.expectEqual(OperandSize.bits64, shlx.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, shlx.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, shlx.src_reg);
    try std.testing.expectEqual(RegId.bh_di_edi_rdi, shlx.src_reg2);
    try std.testing.expectEqual(@as(u8, 5), shlx.len);

    const shrx = decodeLegacyInstruction(&[_]u8{ 0xC4, 0x42, 0xE3, 0xF7, 0xDB }, .long64);
    try std.testing.expectEqual(Op.shrx, shrx.op);
    try std.testing.expectEqual(RegId.r11b_r11w_r11d_r11, shrx.dst_reg);
    try std.testing.expectEqual(RegId.r11b_r11w_r11d_r11, shrx.src_reg);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, shrx.src_reg2);

    const andn = decodeLegacyInstruction(&[_]u8{ 0xC4, 0x42, 0xF0, 0xF2, 0xE0 }, .long64);
    try std.testing.expectEqual(Op.andn, andn.op);
    try std.testing.expectEqual(RegId.r12b_r12w_r12d_r12, andn.dst_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, andn.src_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, andn.src_reg2);

    const bzhi = decodeLegacyInstruction(&[_]u8{ 0xC4, 0x42, 0x88, 0xF5, 0xF7 }, .long64);
    try std.testing.expectEqual(Op.bzhi, bzhi.op);
    try std.testing.expectEqual(RegId.r14b_r14w_r14d_r14, bzhi.dst_reg);
    try std.testing.expectEqual(RegId.r15b_r15w_r15d_r15, bzhi.src_reg);
    try std.testing.expectEqual(RegId.r14b_r14w_r14d_r14, bzhi.src_reg2);

    const mulx = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE2, 0xEB, 0xF6, 0xF6 }, .long64);
    try std.testing.expectEqual(Op.mulx, mulx.op);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, mulx.dst_reg);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, mulx.src_reg);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, mulx.dst_reg2);

    const rorx = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE3, 0x7B, 0xF0, 0xF6, 0x01 }, .long64);
    try std.testing.expectEqual(Op.rorx, rorx.op);
    try std.testing.expectEqual(OperandSize.bits32, rorx.size);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, rorx.dst_reg);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, rorx.src_reg);
    try std.testing.expectEqual(@as(u64, 1), rorx.imm);
    try std.testing.expectEqual(@as(u8, 6), rorx.len);
}

test "shared legacy path recognizes timing, fence, and x87 boundaries" {
    const rdtsc = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x31 }, .long64);
    try std.testing.expectEqual(Op.rdtsc, rdtsc.op);
    try std.testing.expectEqual(@as(u8, 2), rdtsc.len);

    const rdtscp = decodeLegacyInstruction(&[_]u8{ 0xF3, 0x0F, 0x01, 0xF9 }, .long64);
    try std.testing.expectEqual(Op.rdtscp, rdtscp.op);
    try std.testing.expectEqual(@as(u8, 4), rdtscp.len);

    const emms = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x77 }, .long64);
    try std.testing.expectEqual(Op.emms, emms.op);
    try std.testing.expectEqual(@as(u8, 2), emms.len);

    const wait = decodeLegacyInstruction(&[_]u8{0x9B}, .long64);
    try std.testing.expectEqual(Op.wait, wait.op);
    try std.testing.expectEqual(@as(u8, 1), wait.len);

    const fences = [_]struct { bytes: []const u8, op: Op }{
        .{ .bytes = &[_]u8{ 0x0F, 0xAE, 0xE8 }, .op = .lfence },
        .{ .bytes = &[_]u8{ 0x0F, 0xAE, 0xF0 }, .op = .mfence },
        .{ .bytes = &[_]u8{ 0x0F, 0xAE, 0xF8 }, .op = .sfence },
    };
    for (fences) |case| {
        const decoded = decodeLegacyInstruction(case.bytes, .long64);
        try std.testing.expectEqual(case.op, decoded.op);
        try std.testing.expectEqual(@as(u8, 3), decoded.len);
        try std.testing.expect(decoded.is_reg_form);
    }
}

test "shared legacy path decodes opmask register transfers" {
    const to_mask = decodeLegacyInstruction(&[_]u8{ 0xC5, 0xFB, 0x92, 0xC8 }, .long64);
    try std.testing.expectEqual(Op.kmovd, to_mask.op);
    try std.testing.expectEqual(@as(u3, 1), to_mask.dst_k);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, to_mask.src_reg);
    try std.testing.expect(to_mask.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), to_mask.len);

    const from_mask = decodeLegacyInstruction(&[_]u8{ 0xC5, 0xFB, 0x93, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.kmovd, from_mask.op);
    try std.testing.expect(from_mask.mask_to_gpr);
    try std.testing.expectEqual(@as(u3, 1), from_mask.src_k);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, from_mask.dst_reg);

    const qword = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE1, 0xFB, 0x92, 0xC8 }, .long64);
    try std.testing.expectEqual(Op.kmovq, qword.op);
    try std.testing.expectEqual(@as(u3, 1), qword.dst_k);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, qword.src_reg);

    const word = decodeLegacyInstruction(&[_]u8{ 0xC5, 0xF8, 0x92, 0xD1 }, .long64);
    try std.testing.expectEqual(Op.kmovw, word.op);
    try std.testing.expectEqual(@as(u3, 2), word.dst_k);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, word.src_reg);

    const dword_load = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x90, 0x08 }, .long64);
    try std.testing.expectEqual(Op.kmovd, dword_load.op);
    try std.testing.expectEqual(@as(u3, 1), dword_load.dst_k);
    try std.testing.expect(!dword_load.is_reg_form);

    const dword_store = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x91, 0x08 }, .long64);
    try std.testing.expectEqual(Op.kmovd, dword_store.op);
    try std.testing.expect(dword_store.mask_to_gpr);
    try std.testing.expectEqual(@as(u3, 1), dword_store.src_k);
    try std.testing.expect(!dword_store.is_reg_form);
}

test "shared legacy path decodes VEX bit-test and dot-product forms" {
    const vtest = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE2, 0x79, 0x0E, 0xC0 }, .long64);
    try std.testing.expectEqual(Op.vtestps, vtest.op);
    try std.testing.expectEqual(@as(u8, 0), vtest.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), vtest.xmm_src2);
    try std.testing.expect(vtest.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), vtest.len);

    const dot = decodeLegacyInstruction(&[_]u8{ 0xC4, 0xE2, 0x79, 0x50, 0xC0 }, .long64);
    try std.testing.expectEqual(Op.vpdpbusd, dot.op);
    try std.testing.expectEqual(@as(u8, 0), dot.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), dot.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), dot.xmm_src2);
    try std.testing.expect(dot.is_reg_form);
}

test "shared legacy path decodes Windows Xenia EVEX vector forms" {
    const high_register = decodeLegacyInstruction(
        &[_]u8{ 0x62, 0xA2, 0x7E, 0x28, 0x35, 0xC9 },
        .long64,
    );
    try std.testing.expectEqual(Op.vpmovqd, high_register.op);
    try std.testing.expect(high_register.is_evex);
    try std.testing.expect(high_register.vector_256);
    try std.testing.expectEqual(@as(u8, 17), high_register.xmm_src);
    try std.testing.expectEqual(@as(u8, 17), high_register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 6), high_register.len);

    const masked_compare = decodeLegacyInstruction(
        &[_]u8{ 0x62, 0xD1, 0x7F, 0xC9, 0x6F, 0x00 },
        .long64,
    );
    try std.testing.expectEqual(Op.vmovdqu_ymm_mem, masked_compare.op);
    try std.testing.expect(masked_compare.is_evex);
    try std.testing.expectEqual(@as(u8, 1), masked_compare.opmask);
    try std.testing.expect(masked_compare.zero_mask);
    try std.testing.expectEqual(@as(u8, 0), masked_compare.xmm_dst);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, masked_compare.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 6), masked_compare.len);

    const extract = decodeLegacyInstruction(
        &[_]u8{ 0x62, 0xA3, 0xFD, 0x48, 0x3B, 0xC1, 0x01 },
        .long64,
    );
    try std.testing.expectEqual(Op.vextracti64x4, extract.op);
    try std.testing.expect(extract.is_evex);
    try std.testing.expectEqual(@as(u8, 16), extract.xmm_src);
    try std.testing.expectEqual(@as(u8, 17), extract.xmm_dst);
    try std.testing.expectEqual(@as(u64, 1), extract.imm);
    try std.testing.expectEqual(@as(u8, 7), extract.len);

    const compare_bytes = [_]u8{ 0x62, 0xF3, 0x6D, 0x08, 0x3F, 0x0D, 0x4B, 0x2D, 0x6E, 0x00, 0x01 };
    const compare = decodeLegacyInstruction(&compare_bytes, .long64);
    try std.testing.expectEqual(Op.vpcmpb, compare.op);
    try std.testing.expect(compare.is_evex);
    try std.testing.expectEqual(@as(u3, 1), compare.dst_k);
    try std.testing.expectEqual(@as(u8, 2), compare.xmm_src);
    try std.testing.expect(!compare.is_reg_form);
    try std.testing.expectEqual(@as(u64, 1), compare.imm);
    try std.testing.expectEqual(@as(u8, 11), compare.len);
}

test "shared legacy path decodes MOVDIR64B as a 64-byte memory move" {
    const decoded = decodeLegacyInstruction(
        &[_]u8{ 0x66, 0x44, 0x0F, 0x38, 0xF8, 0x0C, 0x02 },
        .long64,
    );
    try std.testing.expectEqual(Op.movdir64b, decoded.op);
    try std.testing.expect(!decoded.is_reg_form);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, decoded.sib_base_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.sib_index_reg);
    try std.testing.expectEqual(@as(u8, 7), decoded.len);
}

test "shared MOV decoder preserves high-byte versus REX low-byte registers" {
    const legacy = decodeMovForTest(&[_]u8{ 0x88, 0xE0 }) orelse return error.ExpectedMov; // mov al, ah
    try std.testing.expectEqual(Op.mov_reg8_reg8, legacy.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, legacy.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, legacy.src_reg);
    try std.testing.expect(!legacy.dst_high8);
    try std.testing.expect(legacy.src_high8);

    const rex = decodeMovForTest(&[_]u8{ 0x40, 0x88, 0xE0 }) orelse return error.ExpectedMov; // mov al, spl
    try std.testing.expectEqual(RegId.ah_sp_esp_rsp, rex.src_reg);
    try std.testing.expect(!rex.src_high8);

    const legacy_imm = decodeMovForTest(&[_]u8{ 0xB4, 0x12 }) orelse return error.ExpectedMov; // mov ah, 0x12
    try std.testing.expect(legacy_imm.dst_high8);
    const rex_imm = decodeMovForTest(&[_]u8{ 0x40, 0xB4, 0x12 }) orelse return error.ExpectedMov; // mov spl, 0x12
    try std.testing.expectEqual(RegId.ah_sp_esp_rsp, rex_imm.dst_reg);
    try std.testing.expect(!rex_imm.dst_high8);
}

test "SETcc uses the ModRM r/m field for AH versus SPL" {
    const setb_ah = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x92, 0xC4 }, .long64);
    try std.testing.expectEqual(Op.setcc_reg8, setb_ah.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, setb_ah.dst_reg);
    try std.testing.expect(setb_ah.dst_high8);

    const setb_spl = decodeLegacyInstruction(&[_]u8{ 0x40, 0x0F, 0x92, 0xC4 }, .long64);
    try std.testing.expectEqual(Op.setcc_reg8, setb_spl.op);
    try std.testing.expectEqual(RegId.ah_sp_esp_rsp, setb_spl.dst_reg);
    try std.testing.expect(!setb_spl.dst_high8);

    var regs = Regs{ .rax = 1, .rsp = 0x1a2d_f000 };
    setRegisterOperand(&regs, .{ .id = setb_ah.dst_reg, .high8 = setb_ah.dst_high8 }, .bits8, 1);
    try std.testing.expectEqual(@as(u64, 0x101), regs.rax);
    try std.testing.expectEqual(@as(u64, 0x1a2d_f000), regs.rsp);
}

test "top-level arithmetic decoder preserves legacy high-byte registers" {
    const add_al_ah = decodeLegacyInstruction(&[_]u8{ 0x00, 0xE0 }, .long64);
    try std.testing.expectEqual(Op.add_reg8_reg8, add_al_ah.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, add_al_ah.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, add_al_ah.src_reg);
    try std.testing.expect(!add_al_ah.dst_high8);
    try std.testing.expect(add_al_ah.src_high8);
    try std.testing.expectEqual(@as(u8, 2), add_al_ah.len);

    const add_al_spl = decodeLegacyInstruction(&[_]u8{ 0x40, 0x00, 0xE0 }, .long64);
    try std.testing.expectEqual(Op.add_reg8_reg8, add_al_spl.op);
    try std.testing.expectEqual(RegId.ah_sp_esp_rsp, add_al_spl.src_reg);
    try std.testing.expect(!add_al_spl.src_high8);
    try std.testing.expectEqual(@as(u8, 3), add_al_spl.len);

    const add_ah_al = decodeLegacyInstruction(&[_]u8{ 0x02, 0xE0 }, .long64);
    try std.testing.expect(add_ah_al.dst_high8);
    try std.testing.expect(!add_ah_al.src_high8);
}

test "top-level ADC decoder covers generated register and memory forms" {
    const generated_immediate = decodeLegacyInstruction(&[_]u8{ 0x49, 0x83, 0xD6, 0x00 }, .long64);
    try std.testing.expectEqual(Op.adc_reg64_imm8, generated_immediate.op);
    try std.testing.expectEqual(Size.bits64, generated_immediate.size);
    try std.testing.expectEqual(RegId.r14b_r14w_r14d_r14, generated_immediate.dst_reg);
    try std.testing.expectEqual(@as(u64, 0), generated_immediate.imm);
    try std.testing.expectEqual(@as(u8, 4), generated_immediate.len);

    const generated = decodeLegacyInstruction(&[_]u8{ 0x11, 0xF3, 0x4C, 0x89 }, .long64);
    try std.testing.expectEqual(Op.adc_reg32_reg32, generated.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, generated.dst_reg);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, generated.src_reg);
    try std.testing.expectEqual(Size.bits32, generated.size);
    try std.testing.expectEqual(@as(u8, 2), generated.len);

    const load64 = decodeLegacyInstruction(&[_]u8{ 0x48, 0x13, 0x48, 0x08 }, .long64);
    try std.testing.expectEqual(Op.adc_reg64_mem64, load64.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load64.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load64.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), load64.addr);

    const store8 = decodeLegacyInstruction(&[_]u8{ 0x10, 0x20 }, .long64);
    try std.testing.expectEqual(Op.adc_mem8_reg8, store8.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store8.src_reg);
    try std.testing.expect(store8.src_high8);
}

test "Group1 full-width register immediates keep their immediate width" {
    const add = decodeLegacyInstruction(&[_]u8{ 0x81, 0xC1, 0x39, 0x01, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.add_reg32_imm32, add.op);
    try std.testing.expectEqual(Size.bits32, add.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, add.dst_reg);
    try std.testing.expectEqual(@as(u64, 0x139), add.imm);
    try std.testing.expectEqual(@as(u8, 6), add.len);

    const add_imm8 = decodeLegacyInstruction(&[_]u8{ 0x83, 0xC1, 0x39 }, .long64);
    try std.testing.expectEqual(Op.add_reg32_imm8, add_imm8.op);
    try std.testing.expectEqual(@as(u64, 0x39), add_imm8.imm);
    try std.testing.expectEqual(@as(u8, 3), add_imm8.len);

    const and_full = decodeLegacyInstruction(&[_]u8{ 0x81, 0xE1, 0xFF, 0x00, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.and_reg32_imm32, and_full.op);

    const or_full = decodeLegacyInstruction(&[_]u8{ 0x81, 0xC9, 0x39, 0x01, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.or_reg32_imm32, or_full.op);
    try std.testing.expectEqual(@as(u8, 6), or_full.len);

    const sub_memory = decodeLegacyInstruction(&[_]u8{ 0x83, 0x68, 0x08, 0x01 }, .long64);
    try std.testing.expectEqual(Op.sub_mem32_imm8, sub_memory.op);
    try std.testing.expectEqual(Size.bits32, sub_memory.size);
    try std.testing.expectEqual(@as(u64, 8), sub_memory.addr);
    try std.testing.expectEqual(@as(u64, 1), sub_memory.imm);
    try std.testing.expectEqual(@as(u8, 4), sub_memory.len);

    const adc_full = decodeLegacyInstruction(&[_]u8{ 0x81, 0xD1, 0x39, 0x01, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.adc_reg32_imm32, adc_full.op);

    const sbb_full = decodeLegacyInstruction(&[_]u8{ 0x81, 0xD9, 0x39, 0x01, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.sbb_reg32_imm32, sbb_full.op);

    const xor_full = decodeLegacyInstruction(&[_]u8{ 0x81, 0xF1, 0x39, 0x01, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.xor_reg32_imm32, xor_full.op);

    const cmp_full = decodeLegacyInstruction(&[_]u8{ 0x48, 0x81, 0xFB, 0x80, 0x00, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.cmp_reg64_imm32, cmp_full.op);
    try std.testing.expectEqual(Size.bits64, cmp_full.size);
    try std.testing.expectEqual(@as(u64, 0x80), cmp_full.imm);
    try std.testing.expectEqual(@as(u8, 7), cmp_full.len);

    const byte_alias = decodeLegacyInstruction(&[_]u8{ 0x82, 0xC1, 0x39 }, .long64);
    try std.testing.expectEqual(Op.add_reg8_imm8, byte_alias.op);
    try std.testing.expectEqual(Size.bits8, byte_alias.size);
}

test "TEST register and memory forms preserve the decoded operand width" {
    const byte_register = decodeLegacyInstruction(&[_]u8{ 0x84, 0xC0 }, .long64);
    try std.testing.expectEqual(Op.test_reg8_reg8, byte_register.op);
    try std.testing.expectEqual(Size.bits8, byte_register.size);

    const byte_memory = decodeLegacyInstruction(&[_]u8{ 0x84, 0x00 }, .long64);
    try std.testing.expectEqual(Op.test_mem8_reg8, byte_memory.op);
    try std.testing.expectEqual(Size.bits8, byte_memory.size);

    const dword_register = decodeLegacyInstruction(&[_]u8{ 0x85, 0xC0 }, .long64);
    try std.testing.expectEqual(Op.test_reg32_reg32, dword_register.op);
    try std.testing.expectEqual(Size.bits32, dword_register.size);
}

test "top-level MOV dispatch uses the shared high-byte decoder" {
    const decoded = decodeLegacyInstruction(&[_]u8{ 0x88, 0xE0 }, .long64); // mov al, ah
    try std.testing.expectEqual(Op.mov_reg8_reg8, decoded.op);
    try std.testing.expect(!decoded.dst_high8);
    try std.testing.expect(decoded.src_high8);
}

test "top-level three-byte dispatch preserves MOVBE boundaries" {
    // Exact Xenia-generated sequence observed at the failure boundary. MOVBE
    // occupies eight bytes; the following CMP begins at byte eight.
    const dword_load = decodeLegacyInstruction(&[_]u8{
        0x0F, 0x38, 0xF0, 0x9F, 0x00, 0x00, 0x00, 0x00,
        0x83, 0xFB, 0x00,
    }, .long64);
    try std.testing.expectEqual(Op.movbe_reg_mem, dword_load.op);
    try std.testing.expectEqual(Size.bits32, dword_load.size);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, dword_load.dst_reg);
    try std.testing.expectEqual(RegId.bh_di_edi_rdi, dword_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0), dword_load.addr);
    try std.testing.expectEqual(@as(u8, 8), dword_load.len);

    const qword_load = decodeLegacyInstruction(&[_]u8{ 0x48, 0x0F, 0x38, 0xF0, 0x48, 0x08 }, .long64);
    try std.testing.expectEqual(Op.movbe_reg_mem, qword_load.op);
    try std.testing.expectEqual(Size.bits64, qword_load.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, qword_load.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, qword_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), qword_load.addr);
    try std.testing.expectEqual(@as(u8, 6), qword_load.len);

    const word_store = decodeLegacyInstruction(&[_]u8{ 0x66, 0x0F, 0x38, 0xF1, 0x4A, 0x10 }, .long64);
    try std.testing.expectEqual(Op.movbe_mem_reg, word_store.op);
    try std.testing.expectEqual(Size.bits16, word_store.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, word_store.src_reg);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, word_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), word_store.addr);
    try std.testing.expectEqual(@as(u8, 6), word_store.len);
}

test "unsupported three-byte opcode never becomes a partial nop" {
    const unsupported = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x38, 0x42, 0x80, 0x00, 0x00, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.invalid, unsupported.op);
    try std.testing.expectEqual(@as(u8, 0), unsupported.len);
}

test "shared legacy prefix decoder normalizes prefix classes" {
    const prefixes = decodeLegacyPrefixes(&[_]u8{ 0xF0, 0x2E, 0x66, 0x67, 0xF3, 0x4D, 0x89, 0xC8 });
    try std.testing.expectEqual(@as(usize, 6), prefixes.len);
    try std.testing.expect(prefixes.lock);
    try std.testing.expectEqual(@as(?Segment, .cs), prefixes.segment_override);
    try std.testing.expect(prefixes.operand_size_override);
    try std.testing.expect(prefixes.address_size_override);
    try std.testing.expectEqual(@as(@TypeOf(prefixes.repeat), .rep), prefixes.repeat);
    try std.testing.expect(prefixes.rexW());
    try std.testing.expect(prefixes.rexR());
    try std.testing.expect(prefixes.rexB());
    // Verify LOCK prefix propagates to DecodedInsn
    const mov = decodeMovForTest(&[_]u8{ 0xF0, 0x89, 0xC8 }).?;
    try std.testing.expect(mov.lock);
}

test "shared legacy decoder preserves address-size override for MOV EAX,[EBX]" {
    const decoded = decodeLegacyInstruction(&[_]u8{ 0x67, 0x8B, 0x03 }, .long64);
    try std.testing.expectEqual(Op.mov_reg32_mem32, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expect(decoded.has_0x67);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0), decoded.addr);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "shared legacy decoder recognizes REP MOVSQ and the full string family" {
    const movsq = decodeLegacyInstruction(&[_]u8{ 0xF3, 0x48, 0xA5, 0x48, 0x8D, 0x7D }, .long64);
    try std.testing.expectEqual(Op.movs, movsq.op);
    try std.testing.expectEqual(Size.bits64, movsq.size);
    try std.testing.expectEqual(@as(@TypeOf(movsq.repeat), .rep), movsq.repeat);
    try std.testing.expect(!movsq.has_0x67);
    try std.testing.expectEqual(@as(u8, 3), movsq.len);

    const movsd_address32 = decodeLegacyInstruction(&[_]u8{ 0x67, 0xF3, 0xA5 }, .long64);
    try std.testing.expectEqual(Op.movs, movsd_address32.op);
    try std.testing.expectEqual(Size.bits32, movsd_address32.size);
    try std.testing.expectEqual(@as(@TypeOf(movsd_address32.repeat), .rep), movsd_address32.repeat);
    try std.testing.expect(movsd_address32.has_0x67);
    try std.testing.expectEqual(@as(u8, 3), movsd_address32.len);

    const cmpsw = decodeLegacyInstruction(&[_]u8{ 0x66, 0xA7 }, .long64);
    try std.testing.expectEqual(Op.cmps, cmpsw.op);
    try std.testing.expectEqual(Size.bits16, cmpsw.size);
    try std.testing.expectEqual(@as(u8, 2), cmpsw.len);

    const scas = decodeLegacyInstruction(&[_]u8{ 0xF2, 0xAF }, .long64);
    try std.testing.expectEqual(Op.scas, scas.op);
    try std.testing.expectEqual(Size.bits32, scas.size);
    try std.testing.expectEqual(@as(@TypeOf(scas.repeat), .repne), scas.repeat);

    try std.testing.expectEqual(Op.stos, decodeLegacyInstruction(&[_]u8{0xAA}, .long64).op);
    try std.testing.expectEqual(Op.lods, decodeLegacyInstruction(&[_]u8{0xAC}, .long64).op);
}

test "shared legacy decoder recognizes SSE2 PUNPCK XMM forms" {
    const cases = [_]struct {
        opcode: u8,
        want: Op,
    }{
        .{ .opcode = 0x60, .want = .vpunpcklbw },
        .{ .opcode = 0x61, .want = .vpunpcklwd },
        .{ .opcode = 0x62, .want = .vpunpckldq },
        .{ .opcode = 0x68, .want = .vpunpckhbw },
        .{ .opcode = 0x69, .want = .vpunpckhwd },
        .{ .opcode = 0x6A, .want = .vpunpckhdq },
        .{ .opcode = 0x6C, .want = .vpunpcklqdq },
        .{ .opcode = 0x6D, .want = .vpunpckhqdq },
    };
    for (cases) |case| {
        const bytes = [_]u8{ 0x66, 0x0F, case.opcode, 0xF1 };
        const decoded = decodeLegacyInstruction(&bytes, .long64);
        try std.testing.expectEqual(case.want, decoded.op);
        try std.testing.expect(decoded.legacy_sse);
        try std.testing.expect(decoded.is_reg_form);
        try std.testing.expectEqual(@as(u8, 4), decoded.len);
    }
}

test "shared legacy decoder recognizes SSE2 PXOR without consuming the next instruction" {
    const decoded = decodeLegacyInstruction(&[_]u8{
        0x66, 0x0F, 0xEF, 0xC1,
        0xC7, 0x40, 0x08, 0x00,
        0x00, 0x00, 0x00,
    }, .long64);
    try std.testing.expectEqual(Op.vpxor, decoded.op);
    try std.testing.expect(decoded.legacy_sse);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);

    const unprefixed = decodeLegacyInstruction(&[_]u8{ 0x0F, 0xEF, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.invalid, unprefixed.op);
    try std.testing.expectEqual(@as(u8, 0), unprefixed.len);
}

test "shared legacy decoder recognizes MOVHPS and MOVLHPS forms" {
    const memory_load = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x16, 0x35, 0xD0, 0x40, 0x01, 0x00 }, .long64);
    try std.testing.expectEqual(Op.vmovhps_xmm_xmm_mem64, memory_load.op);
    try std.testing.expect(memory_load.legacy_sse);
    try std.testing.expect(!memory_load.is_reg_form);
    try std.testing.expectEqual(@as(u8, 6), memory_load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 7), memory_load.len);

    const register_move = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x16, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.vmovlhps, register_move.op);
    try std.testing.expect(register_move.legacy_sse);
    try std.testing.expect(register_move.is_reg_form);
    try std.testing.expectEqual(@as(u8, 0), register_move.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), register_move.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), register_move.len);
}

test "shared legacy decoder recognizes scalar SSE conversion forms" {
    const cvtss2sd = decodeLegacyInstruction(&[_]u8{ 0xF3, 0x0F, 0x5A, 0xC9 }, .long64);
    try std.testing.expectEqual(Op.vcvtss2sd, cvtss2sd.op);
    try std.testing.expect(cvtss2sd.legacy_sse);
    try std.testing.expect(cvtss2sd.is_reg_form);
    try std.testing.expectEqual(@as(u8, 1), cvtss2sd.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), cvtss2sd.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), cvtss2sd.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), cvtss2sd.len);

    const cvtsd2ss = decodeLegacyInstruction(&[_]u8{ 0xF2, 0x0F, 0x5A, 0xD2 }, .long64);
    try std.testing.expectEqual(Op.vcvtsd2ss, cvtsd2ss.op);
    try std.testing.expect(cvtsd2ss.legacy_sse);
    try std.testing.expect(cvtsd2ss.is_reg_form);
    try std.testing.expectEqual(@as(u8, 2), cvtsd2ss.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), cvtsd2ss.xmm_src);
    try std.testing.expectEqual(@as(u8, 2), cvtsd2ss.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), cvtsd2ss.len);

    const cvtps2pd = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x5A, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.vcvtps2pd, cvtps2pd.op);
    try std.testing.expect(cvtps2pd.legacy_sse);
    try std.testing.expectEqual(@as(u8, 3), cvtps2pd.len);

    const cvtpd2ps = decodeLegacyInstruction(&[_]u8{ 0x66, 0x0F, 0x5A, 0xE3 }, .long64);
    try std.testing.expectEqual(Op.vcvtpd2ps, cvtpd2ps.op);
    try std.testing.expect(cvtpd2ps.legacy_sse);
    try std.testing.expectEqual(@as(u8, 4), cvtpd2ps.len);

    const conflicting_prefixes = decodeLegacyInstruction(&[_]u8{ 0x66, 0xF3, 0x0F, 0x5A, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.invalid, conflicting_prefixes.op);
    try std.testing.expectEqual(@as(u8, 0), conflicting_prefixes.len);
}

test "shared legacy decoder recognizes integer-to-scalar SSE conversions" {
    const cvtsi2sd_reg = decodeLegacyInstruction(&[_]u8{ 0xF2, 0x49, 0x0F, 0x2A, 0xD0 }, .long64);
    try std.testing.expectEqual(Op.vcvtsi2sd_xmm_reg, cvtsi2sd_reg.op);
    try std.testing.expect(cvtsi2sd_reg.legacy_sse);
    try std.testing.expect(cvtsi2sd_reg.is_reg_form);
    try std.testing.expectEqual(Size.bits64, cvtsi2sd_reg.size);
    try std.testing.expectEqual(@as(u8, 2), cvtsi2sd_reg.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), cvtsi2sd_reg.xmm_src);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, cvtsi2sd_reg.src_reg);
    try std.testing.expectEqual(@as(u8, 5), cvtsi2sd_reg.len);

    const cvtsi2ss_mem = decodeLegacyInstruction(&[_]u8{ 0xF3, 0x0F, 0x2A, 0x04, 0x25, 0x20, 0x10, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.vcvtsi2ss_xmm_mem, cvtsi2ss_mem.op);
    try std.testing.expect(cvtsi2ss_mem.legacy_sse);
    try std.testing.expect(!cvtsi2ss_mem.is_reg_form);
    try std.testing.expectEqual(Size.bits32, cvtsi2ss_mem.size);
    try std.testing.expectEqual(@as(u8, 9), cvtsi2ss_mem.len);

    const missing_precision_prefix = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x2A, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.invalid, missing_precision_prefix.op);
    try std.testing.expectEqual(@as(u8, 0), missing_precision_prefix.len);
}

test "shared legacy decoder recognizes scalar SSE conversions to integer" {
    const trunc_sd = decodeLegacyInstruction(&[_]u8{ 0xF2, 0x48, 0x0F, 0x2C, 0xC0 }, .long64);
    try std.testing.expectEqual(Op.vcvttsd2si, trunc_sd.op);
    try std.testing.expect(trunc_sd.legacy_sse);
    try std.testing.expect(trunc_sd.is_reg_form);
    try std.testing.expectEqual(Size.bits64, trunc_sd.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, trunc_sd.dst_reg);
    try std.testing.expectEqual(@as(u8, 0), trunc_sd.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), trunc_sd.len);

    const rounded_ss = decodeLegacyInstruction(&[_]u8{ 0xF3, 0x0F, 0x2D, 0x05, 0x20, 0x10, 0x00, 0x00 }, .long64);
    try std.testing.expectEqual(Op.vcvtss2si, rounded_ss.op);
    try std.testing.expect(rounded_ss.legacy_sse);
    try std.testing.expect(!rounded_ss.is_reg_form);
    try std.testing.expectEqual(Size.bits32, rounded_ss.size);
    try std.testing.expectEqual(@as(u8, 8), rounded_ss.len);

    const missing_precision_prefix = decodeLegacyInstruction(&[_]u8{ 0x0F, 0x2C, 0xC1 }, .long64);
    try std.testing.expectEqual(Op.invalid, missing_precision_prefix.op);
    try std.testing.expectEqual(@as(u8, 0), missing_precision_prefix.len);
}

pub fn decodeLegacyInstruction(bytes: []const u8, mode: ExecutionMode) DecodedInsn {
    if (bytes.len == 0) return .{};
    var pos: usize = 0;
    var d = DecodedInsn{};
    var rex: u8 = 0;
    var has_66: bool = false;
    var has_f0: bool = false;
    var has_f2: bool = false;
    var has_f3: bool = false;
    var has_0f: bool = false;

    while (pos < bytes.len) {
        switch (bytes[pos]) {
            0x66 => {
                has_66 = true;
                pos += 1;
            },
            0x67 => {
                pos += 1;
            },
            0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65 => {
                // Legacy segment overrides are still accepted in 64-bit mode
                // and are commonly used in compiler-generated long NOPs.
                pos += 1;
            },
            0xF0 => {
                has_f0 = true;
                pos += 1;
            },
            0xF2 => {
                has_f2 = true;
                pos += 1;
            },
            0xF3 => {
                has_f3 = true;
                pos += 1;
            },
            0x40...0x4F => {
                if (mode == .long64) {
                    rex = bytes[pos];
                    pos += 1;
                } else {
                    break;
                }
            },
            else => break,
        }
    }

    if (pos >= bytes.len) return .{};

    const rex_w = (rex & 0x08) != 0;
    const rex_r = (rex & 0x04) != 0;
    const rex_x = (rex & 0x02) != 0;
    const rex_b = (rex & 0x01) != 0;
    const prefixes = decodeLegacyPrefixes(bytes);

    const op_size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    _ = op_size;

    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    d.has_0x67 = prefixes.address_size_override;
    d.repeat = prefixes.repeat;
    d.lock = prefixes.lock;
    d.segment = selectSegment(.string_source, .dh_si_esi_rsi, prefixes.segment_override);

    const opcode = bytes[pos];

    if (opcode == 0x62) {
        // In 64-bit mode 0x62 is the EVEX prefix. Route it through the same
        // decoder used by standalone ISA tests; treating it as legacy BOUND
        // here would make every AVX-512 instruction invalid in production.
        var evex = decodeVexInstruction(bytes[pos..]) orelse return .{};
        evex.lock = has_f0;
        evex.len = @intCast(@as(usize, evex.len) + pos);
        return evex;
    }

    if (opcode == 0xC4) {
        var vex = decodeVex3(bytes, pos);
        vex.lock = has_f0;
        return vex;
    }
    if (opcode == 0xC5) {
        var vex = decodeVex2(bytes, pos);
        vex.lock = has_f0;
        return vex;
    }

    if (opcode == 0x0F) {
        pos += 1;
        if (pos >= bytes.len) return .{};
        has_0f = true;
        var decoded = decodeTwoByte(bytes, &pos, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, rex);
        decoded.lock = has_f0;
        return decoded;
    }

    if (opcode == 0x90) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos + 1));
        return d;
    }

    if (opcode == 0xF5 or opcode == 0xF8 or opcode == 0xF9) {
        d.op = switch (opcode) {
            0xF5 => .cmc,
            0xF8 => .clc,
            0xF9 => .stc,
            else => unreachable,
        };
        d.len = @intCast(pos + 1);
        return d;
    }

    switch (opcode) {
        0x50...0x57 => {
            d.op = .push_reg;
            const reg_num: u8 = opcode - 0x50;
            // PUSH reads a register: src_reg is the single canonical field.
            d.src_reg = mapReg(reg_num, rex_b);
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x58...0x5F => {
            d.op = .pop_reg;
            const reg_num: u8 = opcode - 0x58;
            d.dst_reg = mapReg(reg_num, rex_b);
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x63 => {
            if (!rex_w or pos + 1 >= bytes.len) return .{};
            var movsxd = DecodedInsn{ .size = .bits64 };
            var modrm_pos = pos + 1;
            const is_mem = bytes[modrm_pos] < 0xC0;
            const rm = readModRM(&movsxd, bytes, &modrm_pos, rex_r, rex_x, rex_b, .bits32);
            movsxd.dst_reg = rm.reg;
            if (is_mem) {
                movsxd.op = .movsxd_reg64_mem32;
                movsxd.addr = rm.addr;
            } else {
                movsxd.op = .movsxd_reg64_reg32;
                movsxd.src_reg = @enumFromInt(rm.addr);
            }
            movsxd.len = @intCast(modrm_pos);
            return movsxd;
        },

        0x68, 0x6A => {
            d.op = .push_imm;
            if (opcode == 0x68) {
                if (pos + 5 > bytes.len) return .{};
                d.imm = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                d.len = 6;
            } else {
                if (pos + 2 > bytes.len) return .{};
                d.imm = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
                d.len = 2;
            }
        },

        0xA4, 0xA5, 0xA6, 0xA7, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF => {
            d.op = switch (opcode) {
                0xA4, 0xA5 => .movs,
                0xA6, 0xA7 => .cmps,
                0xAA, 0xAB => .stos,
                0xAC, 0xAD => .lods,
                0xAE, 0xAF => .scas,
                else => unreachable,
            };
            d.size = switch (opcode) {
                0xA4, 0xA6, 0xAA, 0xAC, 0xAE => .bits8,
                else => if (rex_w) .bits64 else if (has_66) .bits16 else .bits32,
            };
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x69, 0x6B => {
            return decodeImulImm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x70...0x7F => {
            d.op = .jcc_rel8;
            d.cond = mapJccCond8(opcode);
            if (pos + 2 > bytes.len) return .{};
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.rip_relative = true;
            d.len = 2;
        },

        0x84, 0x85 => {
            return decodeTestRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x86, 0x87 => {
            return decodeXchgRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x88, 0x89, 0x8A, 0x8B => {
            var operand_pos = pos + 1;
            return decodeLegacyMov(bytes, &operand_pos, prefixes, opcode) orelse .{};
        },

        0x8D => {
            return decodeLea(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x8F => {
            return decodePopRm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x00...0x03 => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .add);
        },
        0x08...0x0B => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .@"or");
        },
        0x10...0x13 => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .adc);
        },
        0x18...0x1B => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .sbb);
        },
        0x20...0x23 => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .@"and");
        },
        0x28...0x2B => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .sub);
        },
        0x30...0x33 => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .xor);
        },
        0x38...0x3B => {
            return decodeArithRmReg(bytes, pos, prefixes, opcode, .cmp);
        },

        0x80...0x83 => {
            return decodeGroup1Imm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3 => {
            return decodeGroup2Shift(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xF6, 0xF7 => {
            return decodeGroup3(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xB0...0xB7 => {
            d.op = .mov_reg_imm;
            // decodeRegister maps the high-byte aliases (AH/CH/DH/BH) to
            // their base register id (0-3) with high8=true, which is the
            // contract setRegisterOperand/registerOperandValue expect.
            // mapReg alone would emit the aliased id (ah_sp_esp_rsp=4) and
            // corrupt the wrong register at execution time.
            const register = decodeRegister(opcode - 0xB0, rex_b, true, rex != 0);
            d.dst_reg = register.id;
            d.dst_high8 = register.high8;
            d.size = .bits8;
            if (pos + 2 > bytes.len) return .{};
            d.imm = bytes[pos + 1];
            d.len = @as(u8, @intCast(pos + 2));
        },

        0xC2, 0xC3 => {
            d.op = .ret;
            if (opcode == 0xC2) {
                if (pos + 3 > bytes.len) return .{};
                d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
                d.len = 3;
            } else {
                d.imm = 0;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },

        0xC6, 0xC7 => {
            var operand_pos = pos + 1;
            return decodeLegacyMov(bytes, &operand_pos, prefixes, opcode) orelse .{};
        },

        0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF => {
            if (pos + 2 > bytes.len) return .{};
            var x87 = DecodedInsn{};
            var modrm_pos = pos + 1;
            const rm = readModRM(&x87, bytes, &modrm_pos, rex_r, rex_x, rex_b, .bits64);
            const group = @intFromEnum(rm.reg) & 7;
            if (opcode == 0xD8 or opcode == 0xDC or opcode == 0xDE) {
                if (!x87.is_reg_form) return .{};
                const operation = x87BinaryOperation(opcode, group) orelse return .{};
                const stack_index: u64 = rm.addr & 7;
                const destination: u64 = if (opcode == 0xD8) 0 else stack_index;
                const source: u64 = if (opcode == 0xD8) stack_index else 0;
                x87.op = .x87_binary;
                x87.imm = @as(u64, operation) | (destination << 3) | (source << 6) | (if (opcode == 0xDE) @as(u64, 1) << 9 else 0);
                x87.len = @intCast(modrm_pos);
                return x87;
            }
            if (x87.is_reg_form) {
                x87.len = @intCast(modrm_pos);
                if (!decodeX87RegisterForm(opcode, bytes[pos + 1], group, @intCast(rm.addr & 7), &x87)) return .{};
                return x87;
            }
            x87.addr = rm.addr;
            x87.len = @intCast(modrm_pos);
            switch (opcode) {
                0xD9 => switch (group) {
                    0 => x87.op = .fld_mem32,
                    3 => x87.op = .fstp_mem32,
                    5 => x87.op = .fldcw_mem16,
                    7 => x87.op = .fnstcw_mem16,
                    else => return .{},
                },
                0xDB => switch (group) {
                    0 => x87.op = .fild_mem32,
                    5 => x87.op = .fld_mem80,
                    7 => x87.op = .fstp_mem80,
                    else => return .{},
                },
                0xDD => switch (group) {
                    0 => x87.op = .fld_mem64,
                    1 => x87.op = .fisttp_mem64,
                    3 => x87.op = .fstp_mem64,
                    else => return .{},
                },
                0xDA => x87.op = .nop,
                0xDF => switch (group) {
                    0 => x87.op = .fild_mem16,
                    5 => x87.op = .fild_mem64,
                    else => return .{},
                },
                else => unreachable,
            }
            return x87;
        },

        0xCC => {
            d.op = .hlt;
            d.len = @as(u8, @intCast(pos + 1));
        },

        // HLT has both the one-byte C1/INT3-adjacent breakpoint-shaped
        // spelling used by the historical decoder above and its architectural
        // F4 opcode.  PE64 bounded runs use the architectural form as their
        // in-guest termination sentinel, so it must decode identically.
        0xF4 => {
            d.op = .hlt;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0xE8 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .call_rel32;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.imm = d.addr;
            d.rip_relative = true;
            d.len = 5;
        },

        0xE9 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.imm = d.addr;
            d.rip_relative = true;
            d.len = 5;
        },
        0xEB => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.imm = d.addr;
            d.rip_relative = true;
            d.len = 2;
        },

        0xFE, 0xFF => {
            return decodeGroup4_5(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x98 => {
            if (rex_w) {
                d.op = .cdqe;
            } else if (has_66) {
                d.op = .cbw;
            } else {
                d.op = .cwde;
            }
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x99 => {
            if (rex_w) {
                d.op = .cqo;
            } else if (has_66) {
                d.op = .cwd;
            } else {
                d.op = .cdq;
            }
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x9B => {
            d.op = .wait;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x05 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .add_accum_imm),
        0x0D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .or_accum_imm),
        0x15 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .adc_accum_imm),
        0x1D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .sbb_accum_imm),
        0x25 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .and_accum_imm),
        0x2D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .sub_accum_imm),
        0x35 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .xor_accum_imm),
        0x3D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .cmp_accum_imm),

        0x8C => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 2));
        },

        0xA8 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .test_reg8_imm8;
            d.size = .bits8;
            d.dst_reg = .al_ax_eax_rax;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },

        0xA9 => {
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            const imm_len: usize = if (sz == .bits16) 2 else 4;
            if (pos + 1 + imm_len > bytes.len) return .{};
            d.op = switch (sz) {
                .bits16 => .test_reg16_imm16,
                .bits32 => .test_reg32_imm32,
                .bits64 => .test_reg64_imm32,
                .bits8 => unreachable,
            };
            d.size = sz;
            d.dst_reg = .al_ax_eax_rax;
            if (sz == .bits16) {
                d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
            } else {
                const imm32 = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                d.imm = if (sz == .bits64)
                    @bitCast(@as(i64, @as(i32, @bitCast(imm32))))
                else
                    imm32;
            }
            d.len = @intCast(pos + 1 + imm_len);
        },

        0xB8...0xBF => {
            d.op = .mov_reg_imm;
            d.dst_reg = mapReg(opcode - 0xB8, rex_b);
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.size = sz;
            switch (sz) {
                .bits16 => {
                    if (pos + 3 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
                    d.len = @as(u8, @intCast(pos + 3));
                },
                .bits32 => {
                    if (pos + 5 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                    d.len = @as(u8, @intCast(pos + 5));
                },
                .bits64 => {
                    if (pos + 9 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u64, bytes[pos + 1 ..][0..8], .little);
                    d.len = @as(u8, @intCast(pos + 9));
                },
                .bits8 => unreachable,
            }
        },

        0x0C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .or_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x14 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .adc_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x1C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sbb_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x24 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .and_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x2C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sub_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x34 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .xor_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x3C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .cmp_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x04 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .add_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },

        0x06, 0x0E, 0x16, 0x1E => {
            if (mode != .compatibility) {
                d.op = .invalid;
            } else {
                // Segment push (ES/CS/SS/DS) in compatibility mode. PUSH reads
                // a register, so src_reg is the canonical field.
                d.op = .push_reg;
                d.src_reg = .al_ax_eax_rax;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },
        0x07, 0x17, 0x1F => {
            if (mode != .compatibility) {
                d.op = .invalid;
            } else {
                d.op = .pop_reg;
                d.dst_reg = .al_ax_eax_rax;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },
        0x27, 0x2F, 0x37, 0x3F => {
            if (mode != .compatibility) {
                d.op = .invalid;
            } else {
                d.op = .nop;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },

        0x40...0x47 => {
            if (mode == .compatibility) {
                d.op = .inc_reg32;
                const reg_num: u8 = opcode - 0x40;
                d.dst_reg = mapReg(reg_num, false);
                d.len = @as(u8, @intCast(pos + 1));
            } else {
                d.op = .invalid;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },
        0x48...0x4F => {
            if (mode == .compatibility) {
                d.op = .dec_reg32;
                const reg_num: u8 = opcode - 0x48;
                d.dst_reg = mapReg(reg_num, false);
                d.len = @as(u8, @intCast(pos + 1));
            } else {
                d.op = .invalid;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },

        0xC9 => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x6C, 0x6D, 0x6E, 0x6F => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x9C => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9D => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9E => {
            d.op = .sahf;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9F => {
            d.op = .lahf;
            d.len = @as(u8, @intCast(pos + 1));
        },

        else => {
            d.op = .invalid;
            d.len = @as(u8, @intCast(pos + 1));
        },
    }

    d.lock = has_f0;
    return d;
}

fn decodeX87RegisterForm(opcode: u8, modrm: u8, group: u8, source: u8, d: *DecodedInsn) bool {
    d.imm = source;
    switch (opcode) {
        0xD9 => {
            if (group == 0) {
                d.op = .fld_st;
                return true;
            }
            if (group == 1) {
                d.op = .fxch_st;
                return true;
            }
            if (modrm == 0xEE) {
                d.op = .fldz;
                d.imm = 0;
                return true;
            }
        },
        0xDA => {
            d.op = switch (group) {
                0 => .fcmovb_st,
                1 => .fcmove_st,
                2 => .fcmovbe_st,
                3 => .fcmovu_st,
                else => return false,
            };
            d.cond = switch (group) {
                0 => .b,
                1 => .e,
                2 => .be,
                3 => .p,
                else => unreachable,
            };
            return true;
        },
        0xDB => {
            if (group <= 3) {
                d.op = switch (group) {
                    0 => .fcmovnb_st,
                    1 => .fcmovne_st,
                    2 => .fcmovnbe_st,
                    3 => .fcmovnu_st,
                    else => unreachable,
                };
                d.cond = switch (group) {
                    0 => .ae,
                    1 => .ne,
                    2 => .a,
                    3 => .np,
                    else => unreachable,
                };
                return true;
            }
            if (group == 4 and modrm == 0xE3) {
                d.op = .fninit;
                return true;
            }
            if (group == 5 and modrm >= 0xE8 and modrm <= 0xEF) {
                d.op = .fucomi_st;
                return true;
            }
            if (group == 6 and modrm >= 0xF0 and modrm <= 0xF7) {
                d.op = .fcomi_st;
                return true;
            }
        },
        0xDD => {
            if (group == 0) {
                d.op = .ffree_st;
                return true;
            }
            if (group == 3) {
                d.op = .fstp_st;
                return true;
            }
        },
        0xDF => {
            if (group == 4 and modrm == 0xE0) {
                d.op = .fnstsw_ax;
                return true;
            }
            if (group == 5 and modrm >= 0xE8 and modrm <= 0xEF) {
                d.op = .fucomip_st;
                return true;
            }
            if (group == 6 and modrm >= 0xF0 and modrm <= 0xF7) {
                d.op = .fcomip_st;
                return true;
            }
        },
        else => {},
    }
    return false;
}

pub fn x87BinaryOperation(opcode: u8, group: u8) ?u3 {
    return switch (opcode) {
        0xD8 => switch (group) {
            0 => 0, // FADD ST(0), ST(i)
            1 => 1, // FMUL ST(0), ST(i)
            4 => 2, // FSUB ST(0), ST(i)
            5 => 3, // FSUBR ST(0), ST(i)
            6 => 4, // FDIV ST(0), ST(i)
            7 => 5, // FDIVR ST(0), ST(i)
            else => null,
        },
        0xDC, 0xDE => switch (group) {
            0 => 0, // FADD[P] ST(i), ST(0)
            1 => 1, // FMUL[P] ST(i), ST(0)
            4 => 3, // FSUBR[P] ST(i), ST(0)
            5 => 2, // FSUB[P] ST(i), ST(0)
            6 => 5, // FDIVR[P] ST(i), ST(0)
            7 => 4, // FDIV[P] ST(i), ST(0)
            else => null,
        },
        else => null,
    };
}

pub fn decodeAccumulatorImmediate(bytes: []const u8, opcode_pos: usize, rex_w: bool, has_66: bool, op: Op) DecodedInsn {
    const size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const immediate_size: usize = if (size == .bits16) 2 else 4;
    if (opcode_pos + 1 + immediate_size > bytes.len) return .{};

    var decoded = DecodedInsn{
        .op = op,
        .size = size,
        .dst_reg = .al_ax_eax_rax,
        .len = @intCast(opcode_pos + 1 + immediate_size),
    };
    if (size == .bits16) {
        decoded.imm = std.mem.readInt(u16, bytes[opcode_pos + 1 ..][0..2], .little);
    } else {
        const immediate = std.mem.readInt(u32, bytes[opcode_pos + 1 ..][0..4], .little);
        decoded.imm = if (size == .bits64)
            @bitCast(@as(i64, @as(i32, @bitCast(immediate))))
        else
            immediate;
    }
    return decoded;
}
