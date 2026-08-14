//! Mach-O x86 decoder and vector-semantics regression suite.
//!
//! Kept outside process.zig so runtime lifecycle code is not buried under ISA
//! fixtures, while remaining part of the Mach-O processor test target.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_core = @import("macho_core");
const packed_ops = macho_core.packed_ops;
const guest_memory_geometry = @import("dyld").guest_memory_geometry;

const Op = x64_decoder.Op;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const Cond = x64_decoder.Condition;
const bitScan = x64_decoder.bitScan;
const populationCount = x64_decoder.populationCount;
const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF: u32 = 1 << 2;
const RFL_AF: u32 = 1 << 4;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;
const X87State = macho_core.types.X87State;
const X87Tag = macho_core.types.X87Tag;

const decoder = @import("macho_core").decoder;
const process = @import("process.zig");
const DecodedInsn = x64_decoder.DecodedInsn;

const decodeInsn = decoder.decodeInsn;
const decodeVex2 = decoder.decodeVex2;
const decodeVex3 = decoder.decodeVex3;
const decodeVexHalfMove = decoder.decodeVexHalfMove;
const decodeVexDuplicateMove = decoder.decodeVexDuplicateMove;
const x87BinaryOperation = decoder.x87BinaryOperation;
const decodeAccumulatorImmediate = decoder.decodeAccumulatorImmediate;
const decodeTwoByte = decoder.decodeTwoByte;
const decodeThreeByte = decoder.decodeThreeByte;
const decodeSseBytes = decoder.decodeSseBytes;
const hasModRM = decoder.hasModRM;
const mapReg = decoder.mapReg;
const mapJccCond8 = decoder.mapJccCond8;
const mapJccCond32 = decoder.mapJccCond32;
const readModRM = decoder.readModRM;
const decodeArithRmReg = decoder.decodeArithRmReg;
const decodeMovRmReg = decoder.decodeMovRmReg;
const decodeLea = decoder.decodeLea;
const decodePopRm = decoder.decodePopRm;
const decodeGroup1Imm = decoder.decodeGroup1Imm;
const decodeGroup2Shift = decoder.decodeGroup2Shift;
const decodeMovMemImm = decoder.decodeMovMemImm;
const decodeGroup3 = decoder.decodeGroup3;
const decodeGroup4_5 = decoder.decodeGroup4_5;
const decodeTestRmReg = decoder.decodeTestRmReg;
const decodeXchgRmReg = decoder.decodeXchgRmReg;
const decodeImulImm = decoder.decodeImulImm;
const decodeImulTwoOp = decoder.decodeImulTwoOp;
const decodeCmpxchg = decoder.decodeCmpxchg;
const decodeMovzx = decoder.decodeMovzx;
const decodeMovsx = decoder.decodeMovsx;
const decodeXadd = decoder.decodeXadd;
const decodeSetcc = decoder.decodeSetcc;
const decodeMovupsMovss = decoder.decodeMovupsMovss;
const decodeMovaps = decoder.decodeMovaps;

const VexArithmetic = decoder.VexArithmetic;
const VexBitwise = decoder.VexBitwise;
const shuffleBytes = decoder.shuffleBytes;
const compareEqualDwords = decoder.compareEqualDwords;
const unpackLowDwords = decoder.unpackLowDwords;
const permutePackedDoubles = decoder.permutePackedDoubles;
const bitwiseAndAllZero = decoder.bitwiseAndAllZero;
const bitwiseAndNotAllZero = decoder.bitwiseAndNotAllZero;
const applyVexCompare = decoder.applyVexCompare;
const vexArithmeticForOp = decoder.vexArithmeticForOp;
const applyVexArithmetic = decoder.applyVexArithmetic;
const vexBitwiseForOp = decoder.vexBitwiseForOp;
const applyVexBitwise = decoder.applyVexBitwise;
const applyVexPackedF32 = decoder.applyVexPackedF32;
const applyVexPackedF64 = decoder.applyVexPackedF64;
const sqrtVexPackedF32 = decoder.sqrtVexPackedF32;
const sqrtVexPackedF64 = decoder.sqrtVexPackedF64;
const roundVexFloat = decoder.roundVexFloat;
const roundNearestEven = decoder.roundNearestEven;
const roundVexPackedF32 = decoder.roundVexPackedF32;
const roundVexPackedF64 = decoder.roundVexPackedF64;
const convertVexFloatToSigned = decoder.convertVexFloatToSigned;
const integerIndefinite = decoder.integerIndefinite;
const duplicateVectorElements = decoder.duplicateVectorElements;

fn multiplyUnsignedEvenDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    return packed_ops.multiplyUnsignedEvenDwords(lhs, rhs);
}

fn shufflePackedDwords(source: [16]u8, control: u8) [16]u8 {
    return packed_ops.shufflePackedDwords(source, control);
}

fn shufflePackedSingles(lhs: [16]u8, rhs: [16]u8, control: u8) [16]u8 {
    return packed_ops.shufflePackedSingles(lhs, rhs, control);
}

fn unpackLowQwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    return packed_ops.unpackLowQwords(lhs, rhs);
}

fn blendPackedWords(lhs: [16]u8, rhs: [16]u8, control: u8) [16]u8 {
    return packed_ops.blendPackedWords(lhs, rhs, control);
}

const PackedIntegerOperation = packed_ops.PackedIntegerOperation;

fn packedIntegerOperation(op: Op) PackedIntegerOperation {
    return switch (op) {
        .vpaddb, .vpaddw, .vpaddd, .vpaddq => .add,
        .vpsubb, .vpsubw, .vpsubd, .vpsubq => .sub,
        .vpmullw => .mul_low,
        else => unreachable,
    };
}

fn packedIntegerLaneBits(op: Op) u8 {
    return switch (op) {
        .vpaddb, .vpsubb => 8,
        .vpaddw, .vpsubw, .vpmullw => 16,
        .vpaddd, .vpsubd => 32,
        .vpaddq, .vpsubq => 64,
        else => unreachable,
    };
}

fn packedIntegerBinary(lhs: [16]u8, rhs: [16]u8, lane_bits: u8, operation: PackedIntegerOperation) [16]u8 {
    return packed_ops.packedIntegerBinary(lhs, rhs, lane_bits, operation);
}

fn packedShiftLaneBits(op: Op) u8 {
    return switch (op) {
        .vpsllw, .vpsrlw => 16,
        .vpslld, .vpsrld => 32,
        .vpsllq, .vpsrlq => 64,
        else => unreachable,
    };
}

fn shiftPackedElements(source: [16]u8, lane_bits: u8, count: u64, left: bool) [16]u8 {
    return packed_ops.shiftPackedElements(source, lane_bits, count, left);
}

fn shiftPackedBytes(source: [16]u8, count: u64, left: bool) [16]u8 {
    return packed_ops.shiftPackedBytes(source, count, left);
}

/// Darwin's `_SC_PAGESIZE` selector is 29. Process-level page queries describe
/// the VM syscall contract, not Rosette's finer-grained guest metadata.
fn guestSysconf(selector: i32) u64 {
    return guest_memory_geometry.darwinSysconf(selector) orelse @bitCast(@as(i64, -1));
}

fn sdlCompatibilityVersion() [3]u8 {
    return .{ 2, 0, 0 };
}

test "Darwin sysconf reports the host VM page contract" {
    try std.testing.expectEqual(guest_memory_geometry.host_vm_page_size, guestSysconf(29));
    try std.testing.expectEqual(std.math.maxInt(u64), guestSysconf(-1));
    try std.testing.expectEqual(std.math.maxInt(u64), guestSysconf(9999));
}

test "SDL compatibility version satisfies SDL2 callers" {
    const version = sdlCompatibilityVersion();
    try std.testing.expectEqual(@as(u8, 2), version[0]);
    try std.testing.expectEqual(@as(u8, 0), version[1]);
    try std.testing.expectEqual(@as(u8, 0), version[2]);
}

test "decode Xbyak shl ecx immediate" {
    const decoded = decodeInsn(&[_]u8{ 0xC1, 0xE1, 0x08 });
    try std.testing.expectEqual(Op.shl_reg_imm, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 8), decoded.imm);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode group two implicit and arithmetic shifts" {
    const shr = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try std.testing.expectEqual(Op.shr_reg_imm, shr.op);
    try std.testing.expectEqual(@as(u64, 1), shr.imm);
    try std.testing.expectEqual(@as(u8, 2), shr.len);

    const sar = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try std.testing.expectEqual(Op.sar_reg_imm, sar.op);
    try std.testing.expectEqual(Size.bits64, sar.size);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, sar.dst_reg);
    try std.testing.expectEqual(@as(u64, 3), sar.imm);
    try std.testing.expectEqual(@as(u8, 4), sar.len);

    const shr_cl = decodeInsn(&[_]u8{ 0xD3, 0xE8 });
    try std.testing.expectEqual(Op.shr_reg_cl, shr_cl.op);
    try std.testing.expectEqual(Size.bits32, shr_cl.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, shr_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), shr_cl.len);

    const sar_cl = decodeInsn(&[_]u8{ 0xD3, 0xF8 });
    try std.testing.expectEqual(Op.sar_reg_cl, sar_cl.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sar_cl.dst_reg);
}

test "decode group two rotate forms" {
    const fmt_ror = decodeInsn(&[_]u8{ 0xD3, 0xC8 });
    try std.testing.expectEqual(Op.ror_reg_cl, fmt_ror.op);
    try std.testing.expectEqual(Size.bits32, fmt_ror.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_ror.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), fmt_ror.len);

    const rol_byte_memory = decodeInsn(&[_]u8{ 0xC0, 0x07, 0x03 });
    try std.testing.expectEqual(Op.rol_mem_imm, rol_byte_memory.op);
    try std.testing.expectEqual(Size.bits8, rol_byte_memory.size);
    try std.testing.expectEqual(@as(u64, 3), rol_byte_memory.imm);

    const ror_rax = decodeInsn(&[_]u8{ 0x48, 0xD1, 0xC8 });
    try std.testing.expectEqual(Op.ror_reg_imm, ror_rax.op);
    try std.testing.expectEqual(Size.bits64, ror_rax.size);
    try std.testing.expectEqual(@as(u64, 1), ror_rax.imm);
}

test "decode CRC32 forms without consuming the following instruction" {
    const imgui_hash = decodeInsn(&[_]u8{ 0xF2, 0x0F, 0x38, 0xF0, 0xC1, 0xE9, 0x8F, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.crc32_reg_reg, imgui_hash.op);
    try std.testing.expectEqual(Size.bits8, imgui_hash.size);
    try std.testing.expectEqual(Size.bits32, imgui_hash.dst_size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, imgui_hash.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, imgui_hash.src_reg);
    try std.testing.expectEqual(@as(u8, 5), imgui_hash.len);

    const qword_memory = decodeInsn(&[_]u8{ 0xF2, 0x48, 0x0F, 0x38, 0xF1, 0x48, 0x08 });
    try std.testing.expectEqual(Op.crc32_reg_mem, qword_memory.op);
    try std.testing.expectEqual(Size.bits64, qword_memory.size);
    try std.testing.expectEqual(Size.bits64, qword_memory.dst_size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, qword_memory.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, qword_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), qword_memory.addr);
    try std.testing.expectEqual(@as(u8, 7), qword_memory.len);
}

test "decode MOVBE forms without entering ModRM or displacement bytes" {
    // Exact generated-code shape from the Xenia bootstrap failure. The four
    // zero displacement bytes must remain part of MOVBE, not become ADDs.
    const dword_load = decodeInsn(&[_]u8{
        0x0F, 0x38, 0xF0, 0x9F, 0x00, 0x00, 0x00, 0x00,
        0x83, 0xFB, 0x00,
    });
    try std.testing.expectEqual(Op.movbe_reg_mem, dword_load.op);
    try std.testing.expectEqual(Size.bits32, dword_load.size);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, dword_load.dst_reg);
    try std.testing.expectEqual(RegId.bh_di_edi_rdi, dword_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0), dword_load.addr);
    try std.testing.expectEqual(@as(u8, 8), dword_load.len);

    const qword_load = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x38, 0xF0, 0x48, 0x08 });
    try std.testing.expectEqual(Op.movbe_reg_mem, qword_load.op);
    try std.testing.expectEqual(Size.bits64, qword_load.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, qword_load.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, qword_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), qword_load.addr);
    try std.testing.expectEqual(@as(u8, 6), qword_load.len);

    const word_store = decodeInsn(&[_]u8{ 0x66, 0x0F, 0x38, 0xF1, 0x4A, 0x10 });
    try std.testing.expectEqual(Op.movbe_mem_reg, word_store.op);
    try std.testing.expectEqual(Size.bits16, word_store.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, word_store.src_reg);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, word_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), word_store.addr);
    try std.testing.expectEqual(@as(u8, 6), word_store.len);
}

test "unsupported three-byte opcode fails at its real boundary" {
    const unsupported = decodeInsn(&[_]u8{ 0x0F, 0x38, 0x42, 0x80, 0x00, 0x00, 0x00, 0x00 });
    try std.testing.expectEqual(Op.invalid, unsupported.op);
    try std.testing.expectEqual(@as(u8, 0), unsupported.len);
}

test "decode register MOVZX without consuming the following instruction" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xB6, 0xC0, 0x48, 0x83, 0xC4, 0x30 });
    try std.testing.expectEqual(Op.movzx_reg32_mem8, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.src_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "SETcc distinguishes legacy high-byte registers from REX byte registers" {
    // Exact generated-code instruction from the Xenia failure. Without REX,
    // r/m=4 is AH, not SPL.
    const legacy = decodeInsn(&[_]u8{ 0x0F, 0x92, 0xC4 });
    try std.testing.expectEqual(Op.setcc_reg8, legacy.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, legacy.dst_reg);
    try std.testing.expect(legacy.dst_high8);
    try std.testing.expectEqual(@as(u8, 3), legacy.len);

    const rex = decodeInsn(&[_]u8{ 0x40, 0x0F, 0x92, 0xC4 });
    try std.testing.expectEqual(Op.setcc_reg8, rex.op);
    try std.testing.expectEqual(RegId.ah_sp_esp_rsp, rex.dst_reg);
    try std.testing.expect(!rex.dst_high8);
    try std.testing.expectEqual(@as(u8, 4), rex.len);
}

test "decode legacy and VEX MXCSR memory transfers at the full boundary" {
    const legacy_load = decodeInsn(&[_]u8{ 0x0F, 0xAE, 0x56, 0xF0 });
    try std.testing.expectEqual(Op.ldmxcsr_mem32, legacy_load.op);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, legacy_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), legacy_load.addr);
    try std.testing.expectEqual(@as(u8, 4), legacy_load.len);

    // Exact instruction shape reported by Xenia: vldmxcsr [rsi-0x10].
    const vex_load = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0xAE, 0x56, 0xF0 });
    try std.testing.expectEqual(Op.ldmxcsr_mem32, vex_load.op);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, vex_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), vex_load.addr);
    try std.testing.expectEqual(@as(u8, 5), vex_load.len);

    const vex_store = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0xAE, 0x5F, 0x20 });
    try std.testing.expectEqual(Op.stmxcsr_mem32, vex_store.op);
    try std.testing.expectEqual(RegId.bh_di_edi_rdi, vex_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x20), vex_store.addr);
    try std.testing.expectEqual(@as(u8, 5), vex_store.len);
}

test "decode UD2 undefined instruction" {
    const ud2 = decodeInsn(&[_]u8{ 0x0F, 0x0B, 0x48, 0x8B, 0x45, 0xB0 });
    try std.testing.expectEqual(Op.ud2, ud2.op);
    try std.testing.expectEqual(@as(u8, 2), ud2.len);
}

test "decode MOVSX memory and accumulator byte immediate forms" {
    const movsx = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBE, 0x48, 0x03 });
    try std.testing.expectEqual(Op.movsx_reg32_mem8, movsx.op);
    try std.testing.expectEqual(Size.bits64, movsx.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, movsx.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, movsx.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), movsx.addr);
    try std.testing.expectEqual(@as(u8, 5), movsx.len);

    const and_al = decodeInsn(&[_]u8{ 0x24, 0x01 });
    try std.testing.expectEqual(Op.and_reg8_imm8, and_al.op);
    try std.testing.expectEqual(Size.bits8, and_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), and_al.imm);
    try std.testing.expectEqual(@as(u8, 2), and_al.len);
}

test "decode accumulator TEST immediate forms" {
    const test_al = decodeInsn(&[_]u8{ 0xA8, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_al.op);
    try std.testing.expectEqual(Size.bits8, test_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, test_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_al.imm);
    try std.testing.expectEqual(@as(u8, 2), test_al.len);

    const test_rax = decodeInsn(&[_]u8{ 0x48, 0xA9, 0x00, 0x00, 0x00, 0x80 });
    try std.testing.expectEqual(Op.test_reg64_imm32, test_rax.op);
    try std.testing.expectEqual(Size.bits64, test_rax.size);
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_8000_0000), test_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), test_rax.len);
}

test "decode accumulator immediate arithmetic widths" {
    const add_rax = decodeInsn(&[_]u8{ 0x48, 0x05, 0xAB, 0x00, 0x00, 0x00 });
    try std.testing.expectEqual(Op.add_accum_imm, add_rax.op);
    try std.testing.expectEqual(Size.bits64, add_rax.size);
    try std.testing.expectEqual(@as(u64, 0xAB), add_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), add_rax.len);

    const sub_ax = decodeInsn(&[_]u8{ 0x66, 0x2D, 0x34, 0x12 });
    try std.testing.expectEqual(Op.sub_accum_imm, sub_ax.op);
    try std.testing.expectEqual(Size.bits16, sub_ax.size);
    try std.testing.expectEqual(@as(u64, 0x1234), sub_ax.imm);

    const cmp_rax_negative = decodeInsn(&[_]u8{ 0x48, 0x3D, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.cmp_accum_imm, cmp_rax_negative.op);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), cmp_rax_negative.imm);
}

test "decode full near conditional jump range" {
    const jc = decodeInsn(&[_]u8{ 0x0F, 0x82, 0xA7, 0x01, 0x00, 0x00 });
    try std.testing.expectEqual(Op.jcc_rel32, jc.op);
    try std.testing.expectEqual(Cond.b, jc.cond);
    try std.testing.expectEqual(@as(u64, 0x1A7), jc.addr);
    try std.testing.expect(jc.rip_relative);
    try std.testing.expectEqual(@as(u8, 6), jc.len);
}

test "decode both directions of 64-bit AND memory operands" {
    const load_and = decodeInsn(&[_]u8{ 0x48, 0x23, 0x08 });
    try std.testing.expectEqual(Op.and_reg64_mem64, load_and.op);
    try std.testing.expectEqual(Size.bits64, load_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_and.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), load_and.len);

    const store_and = decodeInsn(&[_]u8{ 0x48, 0x21, 0x08 });
    try std.testing.expectEqual(Op.and_mem64_reg64, store_and.op);
    try std.testing.expectEqual(Size.bits64, store_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, store_and.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), store_and.len);
}

test "decode arithmetic byte width and operand direction" {
    const xor_al = decodeInsn(&[_]u8{ 0x30, 0xC0 });
    try std.testing.expectEqual(Op.xor_reg8_reg8, xor_al.op);
    try std.testing.expectEqual(Size.bits8, xor_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.src_reg);

    const sub_mem = decodeInsn(&[_]u8{ 0x29, 0x08 });
    try std.testing.expectEqual(Op.sub_mem32_reg32, sub_mem.op);
    try std.testing.expectEqual(Size.bits32, sub_mem.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, sub_mem.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sub_mem.sib_base_reg);
}

test "decode SBB register forms used for borrow masks" {
    const failing = decodeInsn(&[_]u8{ 0x19, 0xC9 });
    try std.testing.expectEqual(Op.sbb_reg32_reg32, failing.op);
    try std.testing.expectEqual(Size.bits32, failing.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing.src_reg);
    try std.testing.expectEqual(@as(u8, 2), failing.len);

    const reverse_64 = decodeInsn(&[_]u8{ 0x48, 0x1B, 0xC8 });
    try std.testing.expectEqual(Op.sbb_reg64_reg64, reverse_64.op);
    try std.testing.expectEqual(Size.bits64, reverse_64.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, reverse_64.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, reverse_64.src_reg);
}

test "decode group three TEST register immediate" {
    const test_cl = decodeInsn(&[_]u8{ 0xF6, 0xC1, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_cl.op);
    try std.testing.expectEqual(Size.bits8, test_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, test_cl.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_cl.imm);
    try std.testing.expectEqual(@as(u8, 3), test_cl.len);
}

test "decode CPUID and XGETBV" {
    const cpuid = decodeInsn(&[_]u8{ 0x0F, 0xA2 });
    try std.testing.expectEqual(Op.cpuid, cpuid.op);
    try std.testing.expectEqual(@as(u8, 2), cpuid.len);

    const xgetbv = decodeInsn(&[_]u8{ 0x0F, 0x01, 0xD0 });
    try std.testing.expectEqual(Op.xgetbv, xgetbv.op);
    try std.testing.expectEqual(@as(u8, 3), xgetbv.len);
}

test "decode non-W REX prefixes used by CPUID result copies" {
    const mov_r9d_eax = decodeInsn(&[_]u8{ 0x41, 0x89, 0xC1 });
    try std.testing.expectEqual(Op.mov_reg32_reg32, mov_r9d_eax.op);
    try std.testing.expectEqual(Size.bits32, mov_r9d_eax.size);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_r9d_eax.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, mov_r9d_eax.src_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_r9d_eax.len);

    const mov_mem_r9d = decodeInsn(&[_]u8{ 0x45, 0x89, 0x08 });
    try std.testing.expectEqual(Op.mov_mem32_reg32, mov_mem_r9d.op);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_mem_r9d.src_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, mov_mem_r9d.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_mem_r9d.len);
}

test "decode Xbyak unaligned feature-mask copy" {
    const load = decodeInsn(&[_]u8{ 0x0F, 0x10, 0x00 });
    try std.testing.expectEqual(Op.movups_xmm_mem, load.op);
    try std.testing.expectEqual(@as(u8, 0), load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 3), load.len);

    const store = decodeInsn(&[_]u8{ 0x0F, 0x29, 0x45, 0xF0 });
    try std.testing.expectEqual(Op.movaps_mem_xmm, store.op);
    try std.testing.expectEqual(@as(u8, 0), store.xmm_src);
    try std.testing.expectEqual(@as(u8, 4), store.len);
}

test "decode 128-bit VEX move families" {
    // Exact Clang/libc++ initializer sequence previously rejected by Rosette:
    // C4.C1.78.10 /r with SIB base r12 is VMOVUPS xmm0, [r12].
    const initializer_extended_base_load = decodeInsn(&[_]u8{ 0xC4, 0xC1, 0x78, 0x10, 0x04, 0x24 });
    try std.testing.expectEqual(Op.vmovups_xmm_mem, initializer_extended_base_load.op);
    try std.testing.expectEqual(@as(u8, 0), initializer_extended_base_load.xmm_dst);
    try std.testing.expect(initializer_extended_base_load.sib_has_base);
    try std.testing.expectEqual(RegId.r12b_r12w_r12d_r12, initializer_extended_base_load.sib_base_reg);
    try std.testing.expect(!initializer_extended_base_load.sib_has_index);
    try std.testing.expectEqual(@as(u8, 6), initializer_extended_base_load.len);

    const extended_base_store = decodeInsn(&[_]u8{ 0xC4, 0xC1, 0x7A, 0x7F, 0x01 });
    try std.testing.expectEqual(Op.vmovdqu_mem_xmm, extended_base_store.op);
    try std.testing.expectEqual(@as(u8, 0), extended_base_store.xmm_src);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, extended_base_store.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 5), extended_base_store.len);

    const load_dqu = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x6F, 0x00 });
    try std.testing.expectEqual(Op.vmovdqu_xmm_mem, load_dqu.op);
    try std.testing.expectEqual(@as(u8, 0), load_dqu.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_dqu.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 4), load_dqu.len);

    const store_dqa = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x7F, 0x45, 0xF0 });
    try std.testing.expectEqual(Op.vmovdqa_mem_xmm, store_dqa.op);
    try std.testing.expectEqual(@as(u8, 0), store_dqa.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store_dqa.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), store_dqa.addr);
    try std.testing.expectEqual(@as(u8, 5), store_dqa.len);

    const register_ups = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x10, 0xCA });
    try std.testing.expectEqual(Op.vmovups_xmm_xmm, register_ups.op);
    try std.testing.expectEqual(@as(u8, 1), register_ups.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), register_ups.xmm_src);

    const load_ss = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x10, 0x01 });
    try std.testing.expectEqual(Op.vmovss_xmm_mem, load_ss.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_ss.sib_base_reg);

    const store_ss = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x11, 0x00 });
    try std.testing.expectEqual(Op.vmovss_mem_xmm, store_ss.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_ss.sib_base_reg);

    const load_sd = decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x10, 0x02 });
    try std.testing.expectEqual(Op.vmovsd_xmm_mem, load_sd.op);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, load_sd.sib_base_reg);
}

test "decode VEX dword move and byte insertion" {
    const move_register = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6E, 0xC0 });
    try std.testing.expectEqual(Op.vmovd_xmm_reg32, move_register.op);
    try std.testing.expectEqual(@as(u8, 0), move_register.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, move_register.src_reg);
    try std.testing.expectEqual(@as(u8, 4), move_register.len);

    const move_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6E, 0x09 });
    try std.testing.expectEqual(Op.vmovd_xmm_mem32, move_memory.op);
    try std.testing.expectEqual(@as(u8, 1), move_memory.xmm_dst);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, move_memory.sib_base_reg);

    const extract_register = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x7E, 0xC0 });
    try std.testing.expectEqual(Op.vmovd_reg32_xmm, extract_register.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, extract_register.dst_reg);
    try std.testing.expectEqual(@as(u8, 0), extract_register.xmm_src);
    try std.testing.expectEqual(Size.bits32, extract_register.size);
    try std.testing.expectEqual(@as(u8, 4), extract_register.len);

    const extract_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x7E, 0x09 });
    try std.testing.expectEqual(Op.vmovd_mem32_xmm, extract_memory.op);
    try std.testing.expectEqual(@as(u8, 1), extract_memory.xmm_src);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, extract_memory.sib_base_reg);

    const extract_register_vex3 = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x79, 0x7E, 0xC8 });
    try std.testing.expectEqual(Op.vmovd_reg32_xmm, extract_register_vex3.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, extract_register_vex3.dst_reg);
    try std.testing.expectEqual(@as(u8, 1), extract_register_vex3.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), extract_register_vex3.len);

    const insert_register = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x20, 0xC0, 0x0F });
    try std.testing.expectEqual(Op.vpinsrb_xmm_xmm_reg32, insert_register.op);
    try std.testing.expectEqual(@as(u8, 0), insert_register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), insert_register.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, insert_register.src_reg);
    try std.testing.expectEqual(@as(u64, 15), insert_register.imm);
    try std.testing.expectEqual(@as(u8, 6), insert_register.len);

    const insert_memory = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x20, 0x00, 0x05 });
    try std.testing.expectEqual(Op.vpinsrb_xmm_xmm_mem8, insert_memory.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, insert_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 5), insert_memory.imm);

    const shuffle = decodeInsn(&[_]u8{ 0xC4, 0xE2, 0x79, 0x00, 0xC1 });
    try std.testing.expectEqual(Op.vpshufb, shuffle.op);
    try std.testing.expect(!shuffle.vector_256);
    try std.testing.expectEqual(@as(u8, 0), shuffle.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), shuffle.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), shuffle.xmm_src2);
    try std.testing.expect(shuffle.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), shuffle.len);
}

test "decode VEX qword moves between XMM general registers and memory" {
    const failing_vex2_load = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x7E, 0x40, 0x48 });
    try std.testing.expectEqual(Op.vmovq_xmm_mem64, failing_vex2_load.op);
    try std.testing.expectEqual(@as(u8, 0), failing_vex2_load.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, failing_vex2_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x48), failing_vex2_load.addr);
    try std.testing.expectEqual(@as(u8, 5), failing_vex2_load.len);

    const failing_signbit_move = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0xC0 });
    try std.testing.expectEqual(Op.vmovq_reg64_xmm, failing_signbit_move.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, failing_signbit_move.dst_reg);
    try std.testing.expectEqual(@as(u8, 0), failing_signbit_move.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), failing_signbit_move.len);

    // Xenia's CONVERT_I64_F64 sequence must preserve all 64 source bits for
    // its overflow-sign test. Keep the exact macOS emitter boundary covered:
    // vmovq rcx, xmm4; vcvtsd2si rbx, xmm4.
    const xenia_signbit_move = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0xE1 });
    try std.testing.expectEqual(Op.vmovq_reg64_xmm, xenia_signbit_move.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, xenia_signbit_move.dst_reg);
    try std.testing.expectEqual(@as(u8, 4), xenia_signbit_move.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), xenia_signbit_move.len);

    const xenia_conversion = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFB, 0x2D, 0xDC });
    try std.testing.expectEqual(Op.vcvtsd2si, xenia_conversion.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, xenia_conversion.dst_reg);
    try std.testing.expectEqual(@as(u8, 4), xenia_conversion.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), xenia_conversion.len);

    const load_register = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x6E, 0xC8 });
    try std.testing.expectEqual(Op.vmovq_xmm_reg64, load_register.op);
    try std.testing.expectEqual(@as(u8, 1), load_register.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_register.src_reg);

    const store_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0x45, 0xF8 });
    try std.testing.expectEqual(Op.vmovq_mem64_xmm, store_memory.op);
    try std.testing.expectEqual(@as(u8, 0), store_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), store_memory.addr);
}

test "decode VEX low and high packed half moves" {
    const failing_store = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x13, 0x85, 0xD8, 0xFD, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.vmovlpd_mem64_xmm, failing_store.op);
    try std.testing.expectEqual(@as(u8, 0), failing_store.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, failing_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x228))), failing_store.addr);
    try std.testing.expectEqual(@as(u8, 8), failing_store.len);

    const low_load = decodeInsn(&[_]u8{ 0xC5, 0xE8, 0x12, 0x08 });
    try std.testing.expectEqual(Op.vmovlps_xmm_xmm_mem64, low_load.op);
    try std.testing.expectEqual(@as(u8, 1), low_load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), low_load.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, low_load.sib_base_reg);

    const high_store = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x17, 0x4D, 0xF8 });
    try std.testing.expectEqual(Op.vmovhpd_mem64_xmm, high_store.op);
    try std.testing.expectEqual(@as(u8, 1), high_store.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, high_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), high_store.addr);
}

test "decode and execute VEX duplicate moves" {
    const failing = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x16, 0xC0 });
    try std.testing.expectEqual(Op.vmovshdup, failing.op);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src);
    try std.testing.expect(failing.is_reg_form);
    try std.testing.expect(!failing.vector_256);
    try std.testing.expectEqual(@as(u8, 4), failing.len);

    const low_memory = decodeInsn(&[_]u8{ 0xC5, 0xFE, 0x12, 0x4D, 0xE0 });
    try std.testing.expectEqual(Op.vmovsldup, low_memory.op);
    try std.testing.expectEqual(@as(u8, 1), low_memory.xmm_dst);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, low_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x20))), low_memory.addr);
    try std.testing.expect(low_memory.vector_256);
    try std.testing.expect(!low_memory.is_reg_form);

    const doubles = duplicateVectorElements(.vmovddup, .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 });
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7 }, &doubles);
}

test "decode 256-bit VEX packed moves" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xFE, 0x6F, 0x00 });
    try std.testing.expectEqual(Op.vmovdqu_ymm_mem, decoded.op);

    const copy_state = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x10, 0x00 });
    try std.testing.expectEqual(Op.vmovups_ymm_mem, copy_state.op);

    const store_state = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x11, 0x07 });
    try std.testing.expectEqual(Op.vmovups_mem_ymm, store_state.op);

    const zero_upper = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x77 });
    try std.testing.expectEqual(Op.vzeroupper, zero_upper.op);
    try std.testing.expectEqual(@as(u8, 3), zero_upper.len);
}

test "decode the reported VEX2 VPMULUDQ instruction" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xF4, 0xC1, 0xC5, 0xF9, 0x7F });
    try std.testing.expectEqual(Op.vpmuludq, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expect(!decoded.vector_256);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);

    const vex3 = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x79, 0xF4, 0xC1 });
    try std.testing.expectEqual(Op.vpmuludq, vex3.op);
    try std.testing.expectEqual(@as(u8, 0), vex3.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), vex3.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), vex3.xmm_src2);
    try std.testing.expectEqual(@as(u8, 5), vex3.len);

    const memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xF4, 0x45, 0xE0 });
    try std.testing.expectEqual(Op.vpmuludq, memory.op);
    try std.testing.expectEqual(@as(u8, 0), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x20))), memory.addr);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), memory.len);

    const extended = decodeInsn(&[_]u8{ 0xC4, 0x41, 0x31, 0xF4, 0xC2 });
    try std.testing.expectEqual(Op.vpmuludq, extended.op);
    try std.testing.expectEqual(@as(u8, 8), extended.xmm_dst);
    try std.testing.expectEqual(@as(u8, 9), extended.xmm_src);
    try std.testing.expectEqual(@as(u8, 10), extended.xmm_src2);
    try std.testing.expect(extended.is_reg_form);
    try std.testing.expect(!extended.vector_256);

    const ymm = decodeInsn(&[_]u8{ 0xC5, 0xFD, 0xF4, 0xC1 });
    try std.testing.expectEqual(Op.vpmuludq, ymm.op);
    try std.testing.expect(ymm.vector_256);

    const wrong_prefix = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0xF4, 0xC1 });
    try std.testing.expectEqual(Op.invalid, wrong_prefix.op);

    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u32, lhs[0..4], 3, .little);
    std.mem.writeInt(u32, lhs[8..12], 7, .little);
    std.mem.writeInt(u32, rhs[0..4], 5, .little);
    std.mem.writeInt(u32, rhs[8..12], 11, .little);
    const product = multiplyUnsignedEvenDwords(lhs, rhs);
    try std.testing.expectEqual(@as(u64, 15), std.mem.readInt(u64, product[0..8], .little));
    try std.testing.expectEqual(@as(u64, 77), std.mem.readInt(u64, product[8..16], .little));

    std.mem.writeInt(u32, lhs[0..4], std.math.maxInt(u32), .little);
    std.mem.writeInt(u32, rhs[0..4], std.math.maxInt(u32), .little);
    const wide_product = multiplyUnsignedEvenDwords(lhs, rhs);
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFE00000001), std.mem.readInt(u64, wide_product[0..8], .little));
}

test "VPSHUFD applies its immediate independently to every 128-bit lane" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x70, 0xC1, 0x1B });
    try std.testing.expectEqual(Op.vpshufd, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src);
    try std.testing.expectEqual(@as(u64, 0x1B), decoded.imm);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), decoded.len);

    var source: [16]u8 = undefined;
    for (0..4) |lane| {
        std.mem.writeInt(u32, source[lane * 4 ..][0..4], @intCast(lane + 1), .little);
    }
    const reversed = shufflePackedDwords(source, 0x1B);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, reversed[0..4], .little));
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, reversed[4..8], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, reversed[8..12], .little));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, reversed[12..16], .little));

    const broadcast = shufflePackedDwords(source, 0x00);
    for (0..4) |lane| {
        try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, broadcast[lane * 4 ..][0..4], .little));
    }
}

test "VSHUFPS decodes the exact Xenia JIT fault and preserves three-operand semantics" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xD0, 0xC6, 0xED, 0x93 });
    try std.testing.expectEqual(Op.vshufps, decoded.op);
    try std.testing.expectEqual(@as(u8, 5), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 5), decoded.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), decoded.xmm_src2);
    try std.testing.expectEqual(@as(u64, 0x93), decoded.imm);
    try std.testing.expect(decoded.uses_imm);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), decoded.len);

    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    for (0..4) |lane| {
        std.mem.writeInt(u32, lhs[lane * 4 ..][0..4], @intCast(10 + lane), .little);
        std.mem.writeInt(u32, rhs[lane * 4 ..][0..4], @intCast(20 + lane), .little);
    }
    const shuffled = shufflePackedSingles(lhs, rhs, 0x93);
    try std.testing.expectEqual(@as(u32, 13), std.mem.readInt(u32, shuffled[0..4], .little));
    try std.testing.expectEqual(@as(u32, 10), std.mem.readInt(u32, shuffled[4..8], .little));
    try std.testing.expectEqual(@as(u32, 21), std.mem.readInt(u32, shuffled[8..12], .little));
    try std.testing.expectEqual(@as(u32, 22), std.mem.readInt(u32, shuffled[12..16], .little));

    const memory = decodeInsn(&[_]u8{ 0xC5, 0xE8, 0xC6, 0x48, 0x20, 0x1B });
    try std.testing.expectEqual(Op.vshufps, memory.op);
    try std.testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), memory.xmm_src);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x20), memory.addr);

    const wide = decodeInsn(&[_]u8{ 0xC5, 0xEC, 0xC6, 0xCB, 0x1B });
    try std.testing.expectEqual(Op.vshufps, wide.op);
    try std.testing.expect(wide.vector_256);
}

test "decode and execute the XXH3 packed integer VEX cluster" {
    const addq_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xD4, 0x45, 0xE0 });
    try std.testing.expectEqual(Op.vpaddq, addq_memory.op);
    try std.testing.expectEqual(@as(u8, 0), addq_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), addq_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, addq_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x20))), addq_memory.addr);
    try std.testing.expect(!addq_memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), addq_memory.len);

    const shift_right = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xD3, 0xC1 });
    try std.testing.expectEqual(Op.vpsrlq, shift_right.op);
    try std.testing.expectEqual(@as(u8, 0), shift_right.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), shift_right.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), shift_right.xmm_src2);
    try std.testing.expect(!shift_right.uses_imm);
    try std.testing.expectEqual(@as(u8, 4), shift_right.len);

    const shift_left = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xF3, 0xC2 });
    try std.testing.expectEqual(Op.vpsllq, shift_left.op);
    try std.testing.expectEqual(@as(u8, 2), shift_left.xmm_src2);

    const blend = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x0E, 0xDA, 0xCC });
    try std.testing.expectEqual(Op.vpblendw, blend.op);
    try std.testing.expectEqual(@as(u8, 3), blend.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), blend.xmm_src);
    try std.testing.expectEqual(@as(u8, 2), blend.xmm_src2);
    try std.testing.expectEqual(@as(u64, 0xCC), blend.imm);
    try std.testing.expectEqual(@as(u8, 6), blend.len);

    const unpack = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6C, 0xC1 });
    try std.testing.expectEqual(Op.vpunpcklqdq, unpack.op);
    try std.testing.expectEqual(@as(u8, 0), unpack.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), unpack.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), unpack.xmm_src2);

    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u64, lhs[0..8], std.math.maxInt(u64), .little);
    std.mem.writeInt(u64, lhs[8..16], 0x100, .little);
    std.mem.writeInt(u64, rhs[0..8], 2, .little);
    std.mem.writeInt(u64, rhs[8..16], 0x20, .little);

    const sum = packedIntegerBinary(lhs, rhs, 64, .add);
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, sum[0..8], .little));
    try std.testing.expectEqual(@as(u64, 0x120), std.mem.readInt(u64, sum[8..16], .little));

    const shifted_right = shiftPackedElements(lhs, 64, 4, false);
    try std.testing.expectEqual(@as(u64, 0x0FFF_FFFF_FFFF_FFFF), std.mem.readInt(u64, shifted_right[0..8], .little));
    const shifted_left = shiftPackedElements(rhs, 64, 32, true);
    try std.testing.expectEqual(@as(u64, 0x0000_0002_0000_0000), std.mem.readInt(u64, shifted_left[0..8], .little));

    const blended = blendPackedWords(lhs, rhs, 0xCC);
    const blend_control: u8 = 0xCC;
    for (0..8) |lane| {
        const expected = if ((blend_control >> @intCast(lane)) & 1 != 0)
            std.mem.readInt(u16, rhs[lane * 2 ..][0..2], .little)
        else
            std.mem.readInt(u16, lhs[lane * 2 ..][0..2], .little);
        try std.testing.expectEqual(expected, std.mem.readInt(u16, blended[lane * 2 ..][0..2], .little));
    }

    const interleaved = unpackLowQwords(lhs, rhs);
    try std.testing.expectEqual(std.mem.readInt(u64, lhs[0..8], .little), std.mem.readInt(u64, interleaved[0..8], .little));
    try std.testing.expectEqual(std.mem.readInt(u64, rhs[0..8], .little), std.mem.readInt(u64, interleaved[8..16], .little));
}

test "decode VEX signed integer scalar conversions" {
    const failing_memory = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x2A, 0x45, 0xE8 });
    try std.testing.expectEqual(Op.vcvtsi2ss_xmm_mem, failing_memory.op);
    try std.testing.expectEqual(Size.bits32, failing_memory.size);
    try std.testing.expectEqual(@as(u8, 0), failing_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, failing_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x18))), failing_memory.addr);
    try std.testing.expectEqual(@as(u8, 5), failing_memory.len);

    const two_byte_register = decodeInsn(&[_]u8{ 0xC5, 0xEB, 0x2A, 0xC9 });
    try std.testing.expectEqual(Op.vcvtsi2sd_xmm_reg, two_byte_register.op);
    try std.testing.expectEqual(Size.bits32, two_byte_register.size);
    try std.testing.expectEqual(@as(u8, 1), two_byte_register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), two_byte_register.xmm_src);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, two_byte_register.src_reg);

    const to_float = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFA, 0x2A, 0xC0 });
    try std.testing.expectEqual(Op.vcvtsi2ss_xmm_reg, to_float.op);
    try std.testing.expectEqual(Size.bits64, to_float.size);
    try std.testing.expectEqual(@as(u8, 0), to_float.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), to_float.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, to_float.src_reg);
    try std.testing.expectEqual(@as(u8, 5), to_float.len);

    const to_double = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7B, 0x2A, 0x09 });
    try std.testing.expectEqual(Op.vcvtsi2sd_xmm_mem, to_double.op);
    try std.testing.expectEqual(Size.bits32, to_double.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, to_double.sib_base_reg);
}

test "decode VCVTSS2SD register and memory forms" {
    const register = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x5A, 0xC1 });
    try std.testing.expectEqual(Op.vcvtss2sd, register.op);
    try std.testing.expectEqual(@as(u8, 0), register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), register.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), register.xmm_src2);
    try std.testing.expect(register.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), register.len);

    const memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7A, 0x5A, 0x48, 0x10 });
    try std.testing.expectEqual(Op.vcvtss2sd, memory.op);
    try std.testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), memory.xmm_src);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), memory.addr);
}

test "decode VCVTSD2SS register form" {
    // VCVTSD2SS xmm0, xmm0, xmm1: C5 FB 5A C1 (F2 prefix, VEX.L=1)
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x5A, 0xC1 });
    try std.testing.expectEqual(Op.vcvtsd2ss, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    try std.testing.expect(decoded.is_reg_form);
}

test "decode VEX scalar and packed arithmetic" {
    const boundary = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x58, 0xC0 });
    try std.testing.expectEqual(Op.vaddss, boundary.op);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_src2);
    try std.testing.expect(boundary.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), boundary.len);

    const packed_256 = decodeInsn(&[_]u8{ 0xC5, 0xEC, 0x59, 0xCB });
    try std.testing.expectEqual(Op.vmulps, packed_256.op);
    try std.testing.expectEqual(@as(u8, 1), packed_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), packed_256.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), packed_256.xmm_src2);
    try std.testing.expect(packed_256.vector_256);

    const scalar_memory = decodeInsn(&[_]u8{ 0xC5, 0xEB, 0x5E, 0x08 });
    try std.testing.expectEqual(Op.vdivsd, scalar_memory.op);
    try std.testing.expectEqual(@as(u8, 1), scalar_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), scalar_memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, scalar_memory.sib_base_reg);
    try std.testing.expect(!scalar_memory.is_reg_form);
}

test "decode VEX square root forms including ImGui crash boundary" {
    // VSQRTSS xmm0, xmm0, xmm1 — the exact instruction encountered while
    // ImGui was building the presenter font atlas.
    const imgui_scalar = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x51, 0xC1 });
    try std.testing.expectEqual(Op.vsqrtss, imgui_scalar.op);
    try std.testing.expectEqual(Size.bits32, imgui_scalar.size);
    try std.testing.expectEqual(@as(u8, 0), imgui_scalar.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), imgui_scalar.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), imgui_scalar.xmm_src2);
    try std.testing.expect(imgui_scalar.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), imgui_scalar.len);

    const packed_256 = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x51, 0xCB });
    try std.testing.expectEqual(Op.vsqrtps, packed_256.op);
    try std.testing.expectEqual(@as(u8, 1), packed_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 3), packed_256.xmm_src2);
    try std.testing.expect(packed_256.vector_256);
    try std.testing.expect(packed_256.is_reg_form);

    const double_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x79, 0x51, 0x48, 0x10 });
    try std.testing.expectEqual(Op.vsqrtpd, double_memory.op);
    try std.testing.expectEqual(Size.bits64, double_memory.size);
    try std.testing.expectEqual(@as(u8, 1), double_memory.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, double_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), double_memory.addr);
    try std.testing.expect(!double_memory.is_reg_form);
}

test "VEX packed square root preserves independent float lanes" {
    var singles = [_]u8{0} ** 16;
    for ([_]f32{ 1.0, 4.0, 9.0, 16.0 }, 0..) |value, lane| {
        std.mem.writeInt(u32, singles[lane * 4 ..][0..4], @bitCast(value), .little);
    }
    const single_roots = sqrtVexPackedF32(singles);
    for ([_]f32{ 1.0, 2.0, 3.0, 4.0 }, 0..) |expected, lane| {
        const actual: f32 = @bitCast(std.mem.readInt(u32, single_roots[lane * 4 ..][0..4], .little));
        try std.testing.expectEqual(expected, actual);
    }

    var doubles = [_]u8{0} ** 16;
    std.mem.writeInt(u64, doubles[0..8], @bitCast(@as(f64, 25.0)), .little);
    std.mem.writeInt(u64, doubles[8..16], @bitCast(@as(f64, 36.0)), .little);
    const double_roots = sqrtVexPackedF64(doubles);
    try std.testing.expectEqual(@as(f64, 5.0), @as(f64, @bitCast(std.mem.readInt(u64, double_roots[0..8], .little))));
    try std.testing.expectEqual(@as(f64, 6.0), @as(f64, @bitCast(std.mem.readInt(u64, double_roots[8..16], .little))));
}

test "decode VEX bitwise vector operations" {
    const zero = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x57, 0xC0 });
    try std.testing.expectEqual(Op.vxorps, zero.op);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_src2);
    try std.testing.expect(!zero.vector_256);

    const and_not_256 = decodeInsn(&[_]u8{ 0xC5, 0xED, 0x55, 0x08 });
    try std.testing.expectEqual(Op.vandnpd, and_not_256.op);
    try std.testing.expectEqual(@as(u8, 1), and_not_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), and_not_256.xmm_src);
    try std.testing.expect(and_not_256.vector_256);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_not_256.sib_base_reg);
}

test "decode VPCMPEQD register memory and extended-register forms" {
    const failing = decodeInsn(&[_]u8{ 0xC5, 0xFD, 0x76, 0xC0 });
    try std.testing.expectEqual(Op.vpcmpeqd, failing.op);
    try std.testing.expect(failing.vector_256);
    try std.testing.expect(failing.is_reg_form);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), failing.len);

    const memory = decodeInsn(&[_]u8{ 0xC5, 0xED, 0x76, 0x08 });
    try std.testing.expectEqual(Op.vpcmpeqd, memory.op);
    try std.testing.expect(memory.vector_256);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.sib_base_reg);

    const extended = decodeInsn(&[_]u8{ 0xC4, 0x41, 0x6D, 0x76, 0xC8 });
    try std.testing.expectEqual(Op.vpcmpeqd, extended.op);
    try std.testing.expectEqual(@as(u8, 9), extended.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), extended.xmm_src);
    try std.testing.expectEqual(@as(u8, 8), extended.xmm_src2);
}

test "VPCMPEQD compares independent dword lanes" {
    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u32, lhs[0..4], 7, .little);
    std.mem.writeInt(u32, rhs[0..4], 7, .little);
    std.mem.writeInt(u32, lhs[4..8], 9, .little);
    std.mem.writeInt(u32, rhs[4..8], 10, .little);
    const result = compareEqualDwords(lhs, rhs);
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, result[4..8], .little));
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[8..12], .little));
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[12..16], .little));
}

test "decode VEX unordered scalar comparisons" {
    const single = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x2E, 0xC1 });
    try std.testing.expectEqual(Op.vucomiss, single.op);
    try std.testing.expectEqual(@as(u8, 0), single.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), single.xmm_src2);
    try std.testing.expect(single.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), single.len);

    const double_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x2F, 0x08 });
    try std.testing.expectEqual(Op.vucomisd, double_memory.op);
    try std.testing.expectEqual(@as(u8, 1), double_memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, double_memory.sib_base_reg);
    try std.testing.expect(!double_memory.is_reg_form);
}

test "decode VEX scalar and packed rounding" {
    const ceiling = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x0A, 0xC1, 0x0A });
    try std.testing.expectEqual(Op.vroundss, ceiling.op);
    try std.testing.expectEqual(@as(u8, 0), ceiling.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), ceiling.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), ceiling.xmm_src2);
    try std.testing.expectEqual(@as(u64, 0x0A), ceiling.imm);
    try std.testing.expectEqual(@as(u8, 6), ceiling.len);

    const packed_round = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x08, 0x00, 0x03 });
    try std.testing.expectEqual(Op.vroundps, packed_round.op);
    try std.testing.expect(packed_round.vector_256);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, packed_round.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), packed_round.imm);
}

test "decode VPEXTRB/W/D/Q (VEX.128.66.0F3A 14-17)" {
    // Exact bytes from the Xenia JIT-generated-code fault at 0xa004b4dd:
    // VPEXTRB r32, xmm4, 3 — ModRM.reg is the source XMM, ModRM.r/m the
    // destination GPR.
    const extract_b = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x14, 0xE3, 0x03 });
    try std.testing.expectEqual(Op.vpextrb, extract_b.op);
    try std.testing.expectEqual(@as(u64, 3), extract_b.imm);
    try std.testing.expectEqual(@as(u8, 6), extract_b.len);
    try std.testing.expectEqual(@as(u8, 4), extract_b.xmm_src);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, extract_b.dst_reg);
    try std.testing.expect(extract_b.is_reg_form);

    const extract_w = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x15, 0xC3, 0x02 });
    try std.testing.expectEqual(Op.vpextrw, extract_w.op);
    try std.testing.expectEqual(@as(u64, 2), extract_w.imm);

    const extract_d = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x16, 0xC3, 0x01 });
    try std.testing.expectEqual(Op.vpextrd, extract_d.op);
    try std.testing.expectEqual(@as(u64, 1), extract_d.imm);

    // VPEXTRQ is the W1 encoding (byte3 bit 7 set): C4 E3 F9 17 ...
    const extract_q = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0xF9, 0x17, 0xC3, 0x00 });
    try std.testing.expectEqual(Op.vpextrq, extract_q.op);
    try std.testing.expectEqual(@as(u8, 6), extract_q.len);
    try std.testing.expectEqual(@as(u8, 0), extract_q.xmm_src);

    // Memory form: VPEXTRD [rax], xmm1, 1
    const extract_mem = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x16, 0x08, 0x01 });
    try std.testing.expectEqual(Op.vpextrd, extract_mem.op);
    try std.testing.expect(!extract_mem.is_reg_form);
    try std.testing.expectEqual(@as(u8, 1), extract_mem.xmm_src);
    try std.testing.expectEqual(@as(u64, 1), extract_mem.imm);
}

test "decode VPSUB/VPADD/VPUNPCK 3-operand VEX2 with real vvvv source" {
    // Exact bytes from the Xenia JIT-generated-code fault at 0xa004b554:
    // VPSUBB xmm0, xmm1, xmm3 — VEX2 vvvv=1110 selects a real source register.
    const sub_b = decodeInsn(&[_]u8{ 0xC5, 0xF1, 0xF8, 0xC3 });
    try std.testing.expectEqual(Op.vpsubb, sub_b.op);
    try std.testing.expectEqual(@as(u8, 0), sub_b.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), sub_b.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), sub_b.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), sub_b.len);
    try std.testing.expect(sub_b.is_reg_form);

    // VPXOR xmm1, xmm0, [0x06778350] — ModRM 0x0C selects a SIB byte, and SIB
    // 0x25 is index=none, base=101. With mod=00 that escape means "no base
    // register, disp32 follows": an *absolute* address, not a RIP-relative one.
    // RIP-relative is only mod=00 rm=101 with no SIB at all, which the case
    // below covers. This test asserted `rip_relative` on the absolute form and
    // never ran to be contradicted.
    const xor_mem = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xEF, 0x0C, 0x25, 0x50, 0x83, 0x77, 0x06 });
    try std.testing.expectEqual(Op.vpxor, xor_mem.op);
    try std.testing.expectEqual(@as(u8, 1), xor_mem.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), xor_mem.xmm_src);
    try std.testing.expect(!xor_mem.is_reg_form);
    try std.testing.expect(!xor_mem.rip_relative);
    try std.testing.expect(!xor_mem.sib_has_base);
    try std.testing.expectEqual(@as(u64, 0x0677_8350), xor_mem.addr);

    // The genuine RIP-relative encoding of the same instruction, for contrast:
    // ModRM 0x0D is mod=00 rm=101 with no SIB byte.
    const xor_rip = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xEF, 0x0D, 0x50, 0x83, 0x77, 0x06 });
    try std.testing.expectEqual(Op.vpxor, xor_rip.op);
    try std.testing.expect(xor_rip.rip_relative);
    try std.testing.expect(!xor_rip.sib_has_base);

    // 256-bit VPADDD ymm0, ymm1, ymm3 — L=1 (0xF5) with a real vvvv source
    const add_d = decodeInsn(&[_]u8{ 0xC5, 0xF5, 0xFE, 0xC3 });
    try std.testing.expectEqual(Op.vpaddd, add_d.op);
    try std.testing.expect(add_d.vector_256);
    try std.testing.expectEqual(@as(u8, 1), add_d.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), add_d.xmm_src2);

    // VPUNPCKLBW xmm0, xmm1, xmm3 — same-class guard fix (vvvv=1110 source)
    const unpack = decodeInsn(&[_]u8{ 0xC5, 0xF1, 0x60, 0xC3 });
    try std.testing.expectEqual(Op.vpunpcklbw, unpack.op);
    try std.testing.expectEqual(@as(u8, 1), unpack.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), unpack.xmm_src2);
}

test "decode VBLENDVPS/VBLENDVPD/VPBLENDVB variable-blend (0F3A 4A/4B/4C)" {
    // Exact bytes from the Xenia JIT-generated-code fault at 0xa004b566:
    // VPBLENDVB xmm3, xmm2, [rax], xmm1 — the mask register is encoded in
    // imm8[7:4] (0x10 -> xmm1); imm8[3:0] is ignored.
    const blend = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x69, 0x4C, 0x18, 0x10 });
    try std.testing.expectEqual(Op.vpblendvb, blend.op);
    try std.testing.expectEqual(@as(u8, 3), blend.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), blend.xmm_src);
    try std.testing.expect(!blend.is_reg_form);
    try std.testing.expectEqual(@as(u8, 1), blend.xmm_mask);
    try std.testing.expectEqual(@as(u64, 0x10), blend.imm);
    try std.testing.expectEqual(@as(u8, 6), blend.len);

    // Register form: VPBLENDVB xmm0, xmm2, xmm3, xmm1
    const blend_reg = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x69, 0x4C, 0xC3, 0x10 });
    try std.testing.expectEqual(Op.vpblendvb, blend_reg.op);
    try std.testing.expect(blend_reg.is_reg_form);
    try std.testing.expectEqual(@as(u8, 0), blend_reg.xmm_dst);
    try std.testing.expectEqual(@as(u8, 3), blend_reg.xmm_src2);
    try std.testing.expectEqual(@as(u8, 1), blend_reg.xmm_mask);

    // 256-bit form (VEX.L=1): VPBLENDVB ymm0, ymm2, ymm3, ymm1
    const blend_256 = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x6D, 0x4C, 0xC3, 0x10 });
    try std.testing.expectEqual(Op.vpblendvb, blend_256.op);
    try std.testing.expect(blend_256.vector_256);

    // VBLENDVPS (4A) and VBLENDVPD (4B) share the same RVMR encoding
    const blend_ps = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x69, 0x4A, 0xC3, 0x10 });
    try std.testing.expectEqual(Op.vblendvps, blend_ps.op);
    try std.testing.expectEqual(@as(u8, 2), blend_ps.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), blend_ps.xmm_mask);
    const blend_pd = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x69, 0x4B, 0xC3, 0x10 });
    try std.testing.expectEqual(Op.vblendvpd, blend_pd.op);
    try std.testing.expectEqual(@as(u8, 2), blend_pd.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), blend_pd.xmm_mask);

    // VEX.W=1 is #UD for the variable-blend family
    const bad_w = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0xF9, 0x4C, 0xC3, 0x10 });
    try std.testing.expectEqual(Op.invalid, bad_w.op);
}

test "VEX rounding modes include ties-to-even" {
    try std.testing.expectEqual(@as(f32, 2.0), roundVexFloat(f32, 2.5, 0));
    try std.testing.expectEqual(@as(f32, 4.0), roundVexFloat(f32, 3.5, 0));
    try std.testing.expectEqual(@as(f32, -3.0), roundVexFloat(f32, -2.1, 1));
    try std.testing.expectEqual(@as(f32, -2.0), roundVexFloat(f32, -2.1, 2));
    try std.testing.expectEqual(@as(f32, -2.0), roundVexFloat(f32, -2.9, 3));
}

test "decode VEX scalar float to signed integer conversions" {
    const imgui_truncate_memory = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x2C, 0x45, 0xFC, 0xC5, 0xFA, 0x2A, 0xC0 });
    try std.testing.expectEqual(Op.vcvttss2si, imgui_truncate_memory.op);
    try std.testing.expectEqual(Size.bits32, imgui_truncate_memory.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, imgui_truncate_memory.dst_reg);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, imgui_truncate_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -4))), imgui_truncate_memory.addr);
    try std.testing.expect(!imgui_truncate_memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), imgui_truncate_memory.len);

    const truncate_to_64 = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFA, 0x2C, 0xC1 });
    try std.testing.expectEqual(Op.vcvttss2si, truncate_to_64.op);
    try std.testing.expectEqual(Size.bits64, truncate_to_64.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, truncate_to_64.dst_reg);
    try std.testing.expectEqual(@as(u8, 1), truncate_to_64.xmm_src);
    try std.testing.expect(truncate_to_64.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), truncate_to_64.len);

    const round_double_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7B, 0x2D, 0x08 });
    try std.testing.expectEqual(Op.vcvtsd2si, round_double_memory.op);
    try std.testing.expectEqual(Size.bits32, round_double_memory.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, round_double_memory.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, round_double_memory.sib_base_reg);
}

test "VEX float to signed conversion handles rounding and overflow" {
    try std.testing.expectEqual(@as(u64, 3), convertVexFloatToSigned(f32, 3.9, .bits64, true));
    try std.testing.expectEqual(@as(u64, 4), convertVexFloatToSigned(f32, 3.5, .bits64, false));
    try std.testing.expectEqual(@as(u64, 2), convertVexFloatToSigned(f32, 2.5, .bits64, false));
    try std.testing.expectEqual(@as(u64, 0x8000_0000), convertVexFloatToSigned(f64, std.math.nan(f64), .bits32, true));
    try std.testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), convertVexFloatToSigned(f64, 1.0e30, .bits64, true));
}

test "decode MOVSXD from memory" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0x63, 0x09 });
    try std.testing.expectEqual(Op.movsxd_reg64_mem32, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode signed 64-bit register division" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xF9 });
    try std.testing.expectEqual(Op.idiv_reg64, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode unsigned 64-bit register division" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xF1 });
    try std.testing.expectEqual(Op.div_reg64, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode signed and unsigned 32-bit register division" {
    const signed = decodeInsn(&[_]u8{ 0xF7, 0xF9 });
    try std.testing.expectEqual(Op.idiv_reg32, signed.op);
    try std.testing.expectEqual(Size.bits32, signed.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, signed.dst_reg);

    const unsigned = decodeInsn(&[_]u8{ 0xF7, 0xF1 });
    try std.testing.expectEqual(Op.div_reg32, unsigned.op);
    try std.testing.expectEqual(Size.bits32, unsigned.size);
}

test "decode signed and unsigned memory division" {
    const unsigned = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x75, 0xF8 });
    try std.testing.expectEqual(Op.div_mem64, unsigned.op);
    try std.testing.expectEqual(Size.bits64, unsigned.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, unsigned.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 7), unsigned.addr);
    try std.testing.expectEqual(@as(u8, 4), unsigned.len);

    const signed = decodeInsn(&[_]u8{ 0xF7, 0x7B, 0x10 });
    try std.testing.expectEqual(Op.idiv_mem32, signed.op);
    try std.testing.expectEqual(Size.bits32, signed.size);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, signed.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), signed.addr);
    try std.testing.expectEqual(@as(u8, 3), signed.len);
}

test "decode group three NOT register and memory forms" {
    const register = decodeInsn(&[_]u8{ 0xF6, 0xD1 });
    try std.testing.expectEqual(Op.not_reg8, register.op);
    try std.testing.expectEqual(Size.bits8, register.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, register.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), register.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x55, 0xF8 });
    try std.testing.expectEqual(Op.not_mem64, memory.op);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), memory.addr);
}

test "decode group three NEG register and memory forms" {
    const failing_neg_cl = decodeInsn(&[_]u8{ 0xF6, 0xD9 });
    try std.testing.expectEqual(Op.neg_reg8, failing_neg_cl.op);
    try std.testing.expectEqual(Size.bits8, failing_neg_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing_neg_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), failing_neg_cl.len);

    const neg_qword_memory = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x5D, 0xF8 });
    try std.testing.expectEqual(Op.neg_mem64, neg_qword_memory.op);
    try std.testing.expectEqual(Size.bits64, neg_qword_memory.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, neg_qword_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), neg_qword_memory.addr);
}

test "decode group three unsigned multiply register widths" {
    const multiply64 = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xE1 });
    try std.testing.expectEqual(Op.mul_reg64, multiply64.op);
    try std.testing.expectEqual(Size.bits64, multiply64.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, multiply64.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), multiply64.len);

    const multiply8 = decodeInsn(&[_]u8{ 0xF6, 0xE2 });
    try std.testing.expectEqual(Op.mul_reg8, multiply8.op);
    try std.testing.expectEqual(Size.bits8, multiply8.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, multiply8.dst_reg);
}

test "decode carry flag control instructions" {
    try std.testing.expectEqual(Op.cmc, decodeInsn(&[_]u8{0xF5}).op);
    try std.testing.expectEqual(Op.clc, decodeInsn(&[_]u8{0xF8}).op);
    try std.testing.expectEqual(Op.stc, decodeInsn(&[_]u8{0xF9}).op);
}

test "decode status-byte flag transfer instructions" {
    const sahf = decodeInsn(&[_]u8{0x9E});
    try std.testing.expectEqual(Op.sahf, sahf.op);
    try std.testing.expectEqual(@as(u8, 1), sahf.len);

    const lahf = decodeInsn(&[_]u8{0x9F});
    try std.testing.expectEqual(Op.lahf, lahf.op);
    try std.testing.expectEqual(@as(u8, 1), lahf.len);
}

test "decode bit scan and count instructions without losing ModRM" {
    const fmt_bsr = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBD, 0xC0 });
    try std.testing.expectEqual(Op.bsr_reg_reg, fmt_bsr.op);
    try std.testing.expectEqual(Size.bits64, fmt_bsr.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_bsr.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_bsr.src_reg);
    try std.testing.expectEqual(@as(u8, 4), fmt_bsr.len);

    const memory_bsf = decodeInsn(&[_]u8{ 0x0F, 0xBC, 0x48, 0x08 });
    try std.testing.expectEqual(Op.bsf_reg_mem, memory_bsf.op);
    try std.testing.expectEqual(Size.bits32, memory_bsf.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_bsf.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory_bsf.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory_bsf.addr);
    try std.testing.expectEqual(@as(u8, 4), memory_bsf.len);

    const lzcnt = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xBD, 0xC3 });
    try std.testing.expectEqual(Op.lzcnt_reg_reg, lzcnt.op);
    try std.testing.expectEqual(Size.bits64, lzcnt.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, lzcnt.dst_reg);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, lzcnt.src_reg);
    try std.testing.expectEqual(@as(u8, 5), lzcnt.len);
}

test "decode POPCNT exact FBO failure and width variants" {
    const exact_failure = decodeInsn(&[_]u8{ 0xF3, 0x0F, 0xB8, 0xC0, 0x5D, 0xC3 });
    try std.testing.expectEqual(Op.popcnt_reg_reg, exact_failure.op);
    try std.testing.expectEqual(Size.bits32, exact_failure.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, exact_failure.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, exact_failure.src_reg);
    try std.testing.expectEqual(@as(u8, 4), exact_failure.len);

    const memory_16 = decodeInsn(&[_]u8{ 0x66, 0xF3, 0x0F, 0xB8, 0x48, 0x08 });
    try std.testing.expectEqual(Op.popcnt_reg_mem, memory_16.op);
    try std.testing.expectEqual(Size.bits16, memory_16.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_16.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory_16.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory_16.addr);

    const register_64 = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xB8, 0xD3 });
    try std.testing.expectEqual(Op.popcnt_reg_reg, register_64.op);
    try std.testing.expectEqual(Size.bits64, register_64.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, register_64.dst_reg);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, register_64.src_reg);

    try std.testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0x0F, 0xB8, 0xC0 }).op);
}

test "POPCNT semantics mask width and define status flags" {
    const all_status_flags = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF;
    const nonzero = populationCount(.bits32, 0xFFFF_FFFF_0000_000B, all_status_flags | RFL_DF);
    try std.testing.expectEqual(@as(u64, 3), nonzero.value);
    try std.testing.expectEqual(@as(u32, RFL_DF), nonzero.rflags & (all_status_flags | RFL_DF));

    const zero = populationCount(.bits64, 0, all_status_flags | RFL_DF);
    try std.testing.expectEqual(@as(u64, 0), zero.value);
    try std.testing.expectEqual(@as(u32, RFL_ZF | RFL_DF), zero.rflags & (all_status_flags | RFL_DF));
}

test "decode BTR register forms without consuming following instructions" {
    const exact_failure = decodeInsn(&[_]u8{ 0x0F, 0xB3, 0xC8, 0x89, 0x85 });
    try std.testing.expectEqual(Op.btr_reg_reg, exact_failure.op);
    try std.testing.expectEqual(Size.bits32, exact_failure.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, exact_failure.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, exact_failure.src_reg);
    try std.testing.expectEqual(@as(u8, 3), exact_failure.len);

    const rex_w = decodeInsn(&[_]u8{ 0x4D, 0x0F, 0xB3, 0xC8 });
    try std.testing.expectEqual(Op.btr_reg_reg, rex_w.op);
    try std.testing.expectEqual(Size.bits64, rex_w.size);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, rex_w.dst_reg);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, rex_w.src_reg);
}

test "decode BT family register-index forms" {
    const cases = [_]struct {
        bytes: [3]u8,
        op: Op,
    }{
        .{ .bytes = .{ 0x0F, 0xA3, 0xC8 }, .op = .bt_reg_reg },
        .{ .bytes = .{ 0x0F, 0xAB, 0xC8 }, .op = .bts_reg_reg },
        .{ .bytes = .{ 0x0F, 0xB3, 0xC8 }, .op = .btr_reg_reg },
        .{ .bytes = .{ 0x0F, 0xBB, 0xC8 }, .op = .btc_reg_reg },
    };
    for (cases) |case| {
        const decoded = decodeInsn(&case.bytes);
        try std.testing.expectEqual(case.op, decoded.op);
        try std.testing.expectEqual(Size.bits32, decoded.size);
        try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
        try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.src_reg);
        try std.testing.expectEqual(@as(u8, 3), decoded.len);
    }
}

test "decode Group 8 BT family immediate register and memory forms" {
    const register_cases = [_]struct {
        modrm: u8,
        op: Op,
    }{
        .{ .modrm = 0xE1, .op = .bt_reg_imm },
        .{ .modrm = 0xE9, .op = .bts_reg_imm },
        .{ .modrm = 0xF1, .op = .btr_reg_imm },
        .{ .modrm = 0xF9, .op = .btc_reg_imm },
    };
    for (register_cases) |case| {
        const decoded = decodeInsn(&.{ 0x0F, 0xBA, case.modrm, 0x01 });
        try std.testing.expectEqual(case.op, decoded.op);
        try std.testing.expectEqual(Size.bits32, decoded.size);
        try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
        try std.testing.expectEqual(@as(u64, 1), decoded.imm);
        try std.testing.expect(decoded.uses_imm);
        try std.testing.expectEqual(@as(u8, 4), decoded.len);
    }

    const memory_cases = [_]struct {
        modrm: u8,
        op: Op,
    }{
        .{ .modrm = 0x20, .op = .bt_mem_imm },
        .{ .modrm = 0x28, .op = .bts_mem_imm },
        .{ .modrm = 0x30, .op = .btr_mem_imm },
        .{ .modrm = 0x38, .op = .btc_mem_imm },
    };
    for (memory_cases) |case| {
        const decoded = decodeInsn(&.{ 0x0F, 0xBA, case.modrm, 0x1F });
        try std.testing.expectEqual(case.op, decoded.op);
        try std.testing.expectEqual(Size.bits32, decoded.size);
        try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.sib_base_reg);
        try std.testing.expectEqual(@as(u64, 0x1F), decoded.imm);
        try std.testing.expectEqual(@as(u8, 4), decoded.len);
    }

    try std.testing.expectEqual(
        Op.invalid,
        decodeInsn(&.{ 0x0F, 0xBA, 0xC1, 0x01 }).op,
    );
}

test "decode observed PPC Format AA bit extraction sequence" {
    const bytes = [_]u8{
        0x0F, 0xBA, 0xE1, 0x01, // bt ecx, 1
        0x19, 0xC0, // sbb eax, eax
        0x24, 0x01, // and al, 1
        0x0F, 0xB6, 0xC0, // movzx eax, al
    };
    const bit_test = decodeInsn(&bytes);
    try std.testing.expectEqual(Op.bt_reg_imm, bit_test.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, bit_test.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), bit_test.imm);
    try std.testing.expectEqual(@as(u8, 4), bit_test.len);

    const sbb = decodeInsn(bytes[bit_test.len..]);
    try std.testing.expectEqual(Op.sbb_reg32_reg32, sbb.op);
    try std.testing.expectEqual(@as(u8, 2), sbb.len);

    const bit_and = decodeInsn(bytes[bit_test.len + sbb.len ..]);
    // Opcode 0x24 is `AND AL, imm8`. The decoder routes the 8-bit accumulator
    // forms (0x24/0x2C/0x34/0x3C) through the reg8 arm with the destination
    // fixed to AL rather than giving them a separate `*_accum_imm` opcode; the
    // wider forms (0x25 and friends) keep the accumulator naming. Same
    // destination, same immediate, same length — only the opcode name differs,
    // and this assertion expected the wider form's name.
    try std.testing.expectEqual(Op.and_reg8_imm8, bit_and.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, bit_and.dst_reg);
    try std.testing.expectEqual(Size.bits8, bit_and.size);
    try std.testing.expectEqual(@as(u64, 1), bit_and.imm);
}

test "decode BSWAP register family" {
    const initializer_bswap = decodeInsn(&[_]u8{ 0x0F, 0xC8 });
    try std.testing.expectEqual(Op.bswap_reg, initializer_bswap.op);
    try std.testing.expectEqual(Size.bits32, initializer_bswap.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, initializer_bswap.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), initializer_bswap.len);

    const extended_bswap = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xCF });
    try std.testing.expectEqual(Op.bswap_reg, extended_bswap.op);
    try std.testing.expectEqual(Size.bits64, extended_bswap.size);
    try std.testing.expectEqual(RegId.r15b_r15w_r15d_r15, extended_bswap.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), extended_bswap.len);
}

test "bit scan and count semantics cover zero and operand width" {
    const bsr = bitScan(.bits64, .bsr, 0x8000_0000_0000_0000);
    try std.testing.expectEqual(@as(u64, 63), bsr.value);
    try std.testing.expect(bsr.write_destination);
    try std.testing.expect(!bsr.zero_flag);
    try std.testing.expectEqual(@as(?bool, null), bsr.carry_flag);

    const empty_bsf = bitScan(.bits32, .bsf, 0);
    try std.testing.expect(!empty_bsf.write_destination);
    try std.testing.expect(empty_bsf.zero_flag);

    const empty_tzcnt = bitScan(.bits16, .tzcnt, 0);
    try std.testing.expectEqual(@as(u64, 16), empty_tzcnt.value);
    try std.testing.expectEqual(@as(?bool, true), empty_tzcnt.carry_flag);

    const lzcnt = bitScan(.bits32, .lzcnt, 0x0000_0100);
    try std.testing.expectEqual(@as(u64, 23), lzcnt.value);
    try std.testing.expectEqual(@as(?bool, false), lzcnt.carry_flag);
}

test "unknown two-byte opcode is rejected at its real boundary" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xFF, 0xC0 });
    try std.testing.expectEqual(Op.invalid, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.len);
}

test "decode conditional moves without losing the ModRM byte" {
    const register = decodeInsn(&[_]u8{ 0x0F, 0x42, 0xC1 });
    try std.testing.expectEqual(Op.cmovcc_reg_reg, register.op);
    try std.testing.expectEqual(Cond.b, register.cond);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, register.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, register.src_reg);
    try std.testing.expectEqual(@as(u8, 3), register.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x45, 0x45, 0xF8 });
    try std.testing.expectEqual(Op.cmovcc_reg_mem, memory.op);
    try std.testing.expectEqual(Cond.ne, memory.cond);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.dst_reg);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 7), memory.addr);
    try std.testing.expectEqual(@as(u8, 5), memory.len);
}

test "decode 64-bit OR register immediate without aliasing memory opcodes" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0x83, 0xC9, 0x01 });
    try std.testing.expectEqual(Op.or_reg64_imm8, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), decoded.imm);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0x83, 0x49, 0x08, 0x01 });
    try std.testing.expectEqual(Op.or_mem64_imm8, memory.op);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory.addr);
    try std.testing.expectEqual(@as(u64, 1), memory.imm);
    try std.testing.expectEqual(@as(u8, 5), memory.len);
}

test "decode the reported ADCQ register immediate" {
    // Exact bytes at the reported Xenia failure RIP: adc r14, 0.
    const decoded = decodeInsn(&[_]u8{ 0x49, 0x83, 0xD6, 0x00 });
    try std.testing.expectEqual(Op.adc_reg64_imm8, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.r14b_r14w_r14d_r14, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 0), decoded.imm);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);
}

test "decode XCHG ModRM register and memory forms without aliasing" {
    // 4C 87 C3 is XCHG RBX,R8, the exact instruction family that previously
    // fell through the memory executor and attempted to dereference address 0.
    const register = decodeInsn(&[_]u8{ 0x4C, 0x87, 0xC3 });
    try std.testing.expectEqual(Op.xchg_reg64_reg64, register.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, register.dst_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, register.src_reg);
    try std.testing.expect(register.is_reg_form);
    try std.testing.expectEqual(@as(u8, 3), register.len);

    const memory = decodeInsn(&[_]u8{ 0x4C, 0x87, 0x03 });
    try std.testing.expectEqual(Op.xchg_mem64_reg64, memory.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, memory.sib_base_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, memory.src_reg);
    try std.testing.expect(!memory.is_reg_form);
}

test "decode CMPXCHG ModRM register form without aliasing memory" {
    const register = decodeInsn(&[_]u8{ 0x4C, 0x0F, 0xB1, 0xC3 });
    try std.testing.expectEqual(Op.cmpxchg_reg64_reg64, register.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, register.dst_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, register.src_reg);
    try std.testing.expect(register.is_reg_form);
}

test "decode CMPXCHG byte and word forms without widening atomics" {
    const byte_memory = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB0, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem8_reg8, byte_memory.op);
    try std.testing.expectEqual(Size.bits8, byte_memory.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, byte_memory.src_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_memory.sib_base_reg);
    try std.testing.expect(!byte_memory.is_reg_form);

    const word_memory = decodeInsn(&[_]u8{ 0xF0, 0x66, 0x0F, 0xB1, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem16_reg16, word_memory.op);
    try std.testing.expectEqual(Size.bits16, word_memory.size);

    const byte_register = decodeInsn(&[_]u8{ 0x0F, 0xB0, 0xD1 });
    try std.testing.expectEqual(Op.cmpxchg_reg8_reg8, byte_register.op);
    try std.testing.expectEqual(Size.bits8, byte_register.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_register.dst_reg);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, byte_register.src_reg);
    try std.testing.expect(byte_register.is_reg_form);
}

test "decode compiler long NOP with segment override" {
    const decoded = decodeInsn(&[_]u8{ 0x66, 0x66, 0x2E, 0x0F, 0x1F, 0x84, 0x00, 0, 0, 0, 0 });
    try std.testing.expectEqual(Op.nop, decoded.op);
    try std.testing.expectEqual(@as(u8, 11), decoded.len);
}

test "decode prefetch memory hint as no-op" {
    const prefetchnta = decodeInsn(&[_]u8{ 0x0F, 0x18, 0x00, 0x5D, 0xC3 });
    try std.testing.expectEqual(Op.nop, prefetchnta.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, prefetchnta.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), prefetchnta.len);

    const prefetchw = decodeInsn(&[_]u8{ 0x0F, 0x0D, 0x48, 0x20 });
    try std.testing.expectEqual(Op.nop, prefetchw.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, prefetchw.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x20), prefetchw.addr);
    try std.testing.expectEqual(@as(u8, 4), prefetchw.len);
}

test "decode x87 integer and extended-real forms used by chrono timeout path" {
    const load = decodeInsn(&[_]u8{ 0xDF, 0x6D, 0xC8, 0xDB, 0x7D, 0xD0 });
    try std.testing.expectEqual(Op.fild_mem64, load.op);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -56))), load.addr);
    try std.testing.expectEqual(@as(u8, 3), load.len);

    const store = decodeInsn(&[_]u8{ 0xDB, 0x7D, 0xD0, 0x31, 0xC0 });
    try std.testing.expectEqual(Op.fstp_mem80, store.op);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -48))), store.addr);
    try std.testing.expectEqual(@as(u8, 3), store.len);

    // FLD m80real in libc++'s duration comparison. This was previously
    // misdecoded as FILD m32int, forcing every finite sleep to duration::max().
    const load_extended = decodeInsn(&[_]u8{ 0xDB, 0x6D, 0xB4 });
    try std.testing.expectEqual(Op.fld_mem80, load_extended.op);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, load_extended.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -76))), load_extended.addr);
    try std.testing.expectEqual(@as(u8, 3), load_extended.len);

    const load_i32 = decodeInsn(&[_]u8{ 0xDB, 0x00 });
    try std.testing.expectEqual(Op.fild_mem32, load_i32.op);
}

test "x87 stack tracks physical tags and status TOP" {
    var x87 = X87State{};
    try std.testing.expectEqual(@as(u16, 0xFFFF), x87.tagWord());
    try std.testing.expectEqual(@as(u16, 0), x87.statusWord());

    try std.testing.expect(x87.push(1.0));
    try std.testing.expect(x87.push(2.0));
    try std.testing.expectEqual(@as(u3, 6), x87.top);
    try std.testing.expectEqual(@as(u16, 0x0FFF), x87.tagWord());
    try std.testing.expectEqual(@as(u16, 0x3000), x87.statusWord() & 0x3800);
    try std.testing.expectEqual(@as(f64, 2.0), x87.get(0).?);
    try std.testing.expectEqual(@as(f64, 1.0), x87.get(1).?);

    _ = x87.pop();
    try std.testing.expectEqual(@as(u3, 7), x87.top);
    try std.testing.expectEqual(X87Tag.empty, x87.tags[6]);
    try std.testing.expectEqual(X87Tag.valid, x87.tags[7]);
}

test "x87 stack faults preserve TOP and report overflow or underflow" {
    var x87 = X87State{};
    try std.testing.expect(x87.push(0.0));
    try std.testing.expect(x87.push(1.0));
    try std.testing.expect(x87.push(2.0));
    try std.testing.expect(x87.push(3.0));
    try std.testing.expect(x87.push(4.0));
    try std.testing.expect(x87.push(5.0));
    try std.testing.expect(x87.push(6.0));
    try std.testing.expect(x87.push(7.0));
    const top_before = x87.top;
    try std.testing.expect(!x87.push(8.0));
    try std.testing.expectEqual(top_before, x87.top);
    try std.testing.expect((x87.statusWord() & 0x0241) == 0x0241);

    x87.reset();
    try std.testing.expect(x87.pop() == null);
    try std.testing.expect((x87.statusWord() & 0x0241) == 0x0041);
}

test "decode x87 memory and stack forms" {
    const fild16 = decodeInsn(&[_]u8{ 0xDF, 0x00 });
    try std.testing.expectEqual(Op.fild_mem16, fild16.op);
    try std.testing.expectEqual(@as(u8, 2), fild16.len);

    const fld64 = decodeInsn(&[_]u8{ 0xDD, 0x00 });
    try std.testing.expectEqual(Op.fld_mem64, fld64.op);
    const fstp32 = decodeInsn(&[_]u8{ 0xD9, 0x18 });
    try std.testing.expectEqual(Op.fstp_mem32, fstp32.op);
    const fld_st3 = decodeInsn(&[_]u8{ 0xD9, 0xC3 });
    try std.testing.expectEqual(Op.fld_st, fld_st3.op);
    try std.testing.expectEqual(@as(u64, 3), fld_st3.imm);
    const fnstsw = decodeInsn(&[_]u8{ 0xDF, 0xE0 });
    try std.testing.expectEqual(Op.fnstsw_ax, fnstsw.op);

    const fmulp = decodeInsn(&[_]u8{ 0xDE, 0xC9 });
    try std.testing.expectEqual(Op.x87_binary, fmulp.op);
    try std.testing.expectEqual(@as(u64, 0x209), fmulp.imm);

    const fucomip = decodeInsn(&[_]u8{ 0xDF, 0xE9 });
    try std.testing.expectEqual(Op.fucomip_st, fucomip.op);
    try std.testing.expectEqual(@as(u64, 1), fucomip.imm);
}

test "x87 FMULP writes ST(i) before popping ST(0)" {
    var x87 = X87State{};
    try std.testing.expect(x87.push(3.0));
    try std.testing.expect(x87.push(4.0));
    x87.binary(1, 0, 1, true);
    try std.testing.expectEqual(@as(u3, 7), x87.top);
    try std.testing.expectEqual(@as(f64, 12.0), x87.get(0).?);
    try std.testing.expectEqual(X87Tag.empty, x87.tags[6]);
}

test "decode C6 and C7 register immediate forms" {
    const byte_move = decodeInsn(&[_]u8{ 0x41, 0xC6, 0xC0, 0x7F });
    try std.testing.expectEqual(Op.mov_reg_imm, byte_move.op);
    try std.testing.expectEqual(Size.bits8, byte_move.size);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, byte_move.dst_reg);
    try std.testing.expectEqual(@as(u64, 0x7F), byte_move.imm);

    const max_unsigned = decodeInsn(&[_]u8{ 0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.mov_reg_imm, max_unsigned.op);
    try std.testing.expectEqual(Size.bits64, max_unsigned.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, max_unsigned.dst_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), max_unsigned.imm);
    try std.testing.expectEqual(@as(u8, 7), max_unsigned.len);
}

test "decode C7 memory immediate sign extends to 64 bits" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xC7, 0x00, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.mov_mem64_imm32, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), decoded.imm);
}

// A5 (perf audit): a decode-cache hit skips address resolution when no live
// register contributes. The claim being pinned is an equivalence, not a
// heuristic — an instruction whose address names no base, no index and no
// FS/GS segment resolves to the same value on every hit, so the value stored
// when the entry was populated is still correct.
//
// Getting this wrong is silent: the interpreter would execute against a stale
// effective address rather than fault, so the predicate is tested directly.
test "address resolution is skipped only when nothing live contributes to it" {
    const needsLive = process.MachOState.addressNeedsLiveRegisters;

    // `mov eax, [rbx+0x20]` — a base register contributes.
    var with_base = DecodedInsn{ .op = .mov_reg32_mem32 };
    with_base.sib_has_base = true;
    with_base.sib_base_reg = .bl_bx_ebx_rbx;
    try std.testing.expect(needsLive(with_base));

    // `mov eax, [rbx*4+0x20]` — an index register contributes.
    var with_index = DecodedInsn{ .op = .mov_reg32_mem32 };
    with_index.sib_has_index = true;
    with_index.sib_index_reg = .bl_bx_ebx_rbx;
    try std.testing.expect(needsLive(with_index));

    // RIP-relative was already excluded before this change and stays excluded:
    // the populate path resolves it and the hit path must not touch it.
    var rip_relative = DecodedInsn{ .op = .mov_reg32_mem32 };
    rip_relative.rip_relative = true;
    try std.testing.expect(!needsLive(rip_relative));

    // FS and GS are the only segments with a non-zero base in long mode, and a
    // thread-local address moves with the thread.
    var thread_local = DecodedInsn{ .op = .mov_reg64_mem64 };
    thread_local.segment = .fs;
    try std.testing.expect(needsLive(thread_local));
    var gs_relative = DecodedInsn{ .op = .mov_reg64_mem64 };
    gs_relative.segment = .gs;
    try std.testing.expect(needsLive(gs_relative));

    // Register-to-register, an immediate form and a plain displacement: none
    // of these has anything that can change between hits.
    try std.testing.expect(!needsLive(DecodedInsn{ .op = .mov_reg64_reg64 }));
    try std.testing.expect(!needsLive(DecodedInsn{ .op = .mov_reg_imm }));
    try std.testing.expect(!needsLive(DecodedInsn{ .op = .jcc_rel32 }));
    var absolute = DecodedInsn{ .op = .mov_reg32_mem32 };
    absolute.addr = 0x1234;
    try std.testing.expect(!needsLive(absolute));
}

// The encoding that killed a run at step 5.37B: `C5 F8 C2 D1 04`, which is
// `vcmpps xmm2, xmm0, xmm1, 4` — Xenia's mask-producing float compare. Both
// VEX forms were missing, which the VEX2/VEX3 differential test cannot catch:
// that test proves the two forms *agree*, and here they agreed on rejecting a
// real instruction.
test "VEX 0F C2 decodes to the four compare forms in both VEX encodings" {
    const two_byte = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0xC2, 0xD1, 0x04, 0x0F });
    try std.testing.expectEqual(Op.vcmpps, two_byte.op);
    try std.testing.expectEqual(@as(u8, 5), two_byte.len);
    try std.testing.expectEqual(@as(u8, 2), two_byte.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), two_byte.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), two_byte.xmm_src2);
    try std.testing.expectEqual(@as(u64, 4), two_byte.imm);
    try std.testing.expect(two_byte.is_reg_form);

    // The prefix selects the width and packing, exactly as for the arithmetic
    // forms next to it.
    try std.testing.expectEqual(Op.vcmppd, decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xC2, 0xD1, 0x04, 0x0F }).op);
    try std.testing.expectEqual(Op.vcmpss, decodeInsn(&[_]u8{ 0xC5, 0xFA, 0xC2, 0xD1, 0x04, 0x0F }).op);
    try std.testing.expectEqual(Op.vcmpsd, decodeInsn(&[_]u8{ 0xC5, 0xFB, 0xC2, 0xD1, 0x04, 0x0F }).op);

    // The three-byte form a register above xmm7 forces.
    const three_byte = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x78, 0xC2, 0xD1, 0x04, 0x0F });
    try std.testing.expectEqual(Op.vcmpps, three_byte.op);
    try std.testing.expectEqual(@as(u8, 6), three_byte.len);
    try std.testing.expectEqual(@as(u64, 4), three_byte.imm);
}

test "SIMD compare predicates produce lane masks and reject what is not modelled" {
    const VexComparePredicate = decoder.VexComparePredicate;

    // The eight base relations, and the NaN rule that separates the ordered
    // forms from the unordered ones.
    const quiet_nan = std.math.nan(f32);
    try std.testing.expect(VexComparePredicate.fromImmediate(0).?.evaluate(@as(f32, 1.0), 1.0));
    try std.testing.expect(!VexComparePredicate.fromImmediate(0).?.evaluate(quiet_nan, quiet_nan));
    try std.testing.expect(VexComparePredicate.fromImmediate(3).?.evaluate(quiet_nan, @as(f32, 1.0)));
    try std.testing.expect(VexComparePredicate.fromImmediate(4).?.evaluate(quiet_nan, @as(f32, 1.0)));
    try std.testing.expect(VexComparePredicate.fromImmediate(7).?.evaluate(@as(f32, 1.0), 2.0));
    try std.testing.expect(!VexComparePredicate.fromImmediate(7).?.evaluate(quiet_nan, @as(f32, 1.0)));

    // The signalling and extended variants select the same relation; only the
    // exception behaviour differs, and that is not modelled here.
    try std.testing.expectEqual(
        VexComparePredicate.equal,
        VexComparePredicate.fromImmediate(0x08).?,
    );
    try std.testing.expectEqual(
        VexComparePredicate.not_equal,
        VexComparePredicate.fromImmediate(0x14).?,
    );

    // A whole-vector mask: `vcmpps ..., 4` (NEQ) over four lanes, two equal.
    var left: [16]u8 = undefined;
    var right: [16]u8 = undefined;
    const lanes = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const others = [_]f32{ 1.0, 9.0, 3.0, 9.0 };
    for (0..4) |lane| {
        std.mem.writeInt(u32, left[lane * 4 ..][0..4], @bitCast(lanes[lane]), .little);
        std.mem.writeInt(u32, right[lane * 4 ..][0..4], @bitCast(others[lane]), .little);
    }
    const mask = decoder.compareVexPackedF32(left, right, .not_equal);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, mask[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), std.mem.readInt(u32, mask[4..8], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, mask[8..12], .little));
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), std.mem.readInt(u32, mask[12..16], .little));
}

// The encoding that ended the previous run: `C4 C1 7A 5B C0`, which is
// `vcvttps2dq xmm0, xmm8` — a three-byte VEX only because the source is above
// xmm7. Both VEX forms of 0F 5B were missing from the real decode paths, and
// the test-only path had the F3 case mapped to the wrong opcode entirely.
test "VEX 0F 5B decodes the packed float/dword conversions in both VEX forms" {
    const failing = decodeInsn(&[_]u8{ 0xC4, 0xC1, 0x7A, 0x5B, 0xC0, 0x0F });
    try std.testing.expectEqual(Op.vcvttps2dq, failing.op);
    try std.testing.expectEqual(@as(u8, 5), failing.len);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 8), failing.xmm_src2);
    try std.testing.expect(failing.is_reg_form);

    // The prefix picks the direction, and F3 additionally picks truncation
    // over the current rounding mode. Getting F3 and no-prefix the same way
    // round converts in the opposite direction — the bug in the old mapping.
    try std.testing.expectEqual(Op.vcvtdq2ps, decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x5B, 0xC1, 0x0F }).op);
    try std.testing.expectEqual(Op.vcvtps2dq, decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x5B, 0xC1, 0x0F }).op);
    try std.testing.expectEqual(Op.vcvttps2dq, decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x5B, 0xC1, 0x0F }).op);
    // F2 0F 5B is not an instruction and must stay rejected.
    try std.testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x5B, 0xC1, 0x0F }).op);
}

test "packed float/dword conversion rounds, truncates and reports the indefinite" {
    var source: [16]u8 = undefined;
    const lanes = [_]f32{ 2.7, -2.7, 1.5, 2.5 };
    for (0..4) |lane| {
        std.mem.writeInt(u32, source[lane * 4 ..][0..4], @bitCast(lanes[lane]), .little);
    }

    // Truncation is toward zero, in both signs.
    const truncated = decoder.convertVexPackedFloatToDword(source, true);
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, truncated[0..4], .little));
    try std.testing.expectEqual(@as(i32, -2), std.mem.readInt(i32, truncated[4..8], .little));

    // Rounding is the other form's behaviour, and differs from truncation
    // exactly where it should.
    const rounded = decoder.convertVexPackedFloatToDword(source, false);
    try std.testing.expectEqual(@as(i32, 3), std.mem.readInt(i32, rounded[0..4], .little));
    try std.testing.expectEqual(@as(i32, -3), std.mem.readInt(i32, rounded[4..8], .little));

    // Anything unrepresentable is the integer indefinite, not a saturated or
    // wrapped value: guest code may test for exactly this sentinel.
    var extremes: [16]u8 = undefined;
    const unrepresentable = [_]f32{
        std.math.nan(f32),
        std.math.inf(f32),
        -std.math.inf(f32),
        4.0e9,
    };
    for (0..4) |lane| {
        std.mem.writeInt(u32, extremes[lane * 4 ..][0..4], @bitCast(unrepresentable[lane]), .little);
    }
    const converted = decoder.convertVexPackedFloatToDword(extremes, true);
    for (0..4) |lane| {
        try std.testing.expectEqual(
            decoder.integer_indefinite,
            std.mem.readInt(i32, converted[lane * 4 ..][0..4], .little),
        );
    }

    // And the reverse direction round-trips the values it can represent.
    const back = decoder.convertVexPackedDwordToFloat(truncated);
    try std.testing.expectEqual(@as(f32, 2.0), @as(f32, @bitCast(std.mem.readInt(u32, back[0..4], .little))));
    try std.testing.expectEqual(@as(f32, -2.0), @as(f32, @bitCast(std.mem.readInt(u32, back[4..8], .little))));
}

// `C4 C1 39 72 F0 1F` = `vpslld xmm8, xmm8, 31`. A *group* opcode: ModRM.reg
// selects the shift, VEX.vvvv is the destination and ModRM.r/m the source, so a
// source above xmm7 needs REX.B and therefore the three-byte prefix — which was
// the form the decoder lacked.
test "VEX 0F 71/72/73 immediate shifts decode in both VEX forms" {
    const failing = decodeInsn(&[_]u8{ 0xC4, 0xC1, 0x39, 0x72, 0xF0, 0x1F, 0x0F });
    try std.testing.expectEqual(Op.vpslld, failing.op);
    try std.testing.expectEqual(@as(u8, 6), failing.len);
    try std.testing.expectEqual(@as(u8, 8), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 8), failing.xmm_src);
    try std.testing.expectEqual(@as(u64, 31), failing.imm);

    // Every member of the group, in the three-byte form. ModRM.reg is the
    // selector: /2 and /3 shift right, /6 and /7 left.
    const members = [_]struct { opcode: u8, reg: u8, op: Op }{
        .{ .opcode = 0x71, .reg = 2, .op = .vpsrlw },
        .{ .opcode = 0x71, .reg = 6, .op = .vpsllw },
        .{ .opcode = 0x72, .reg = 2, .op = .vpsrld },
        .{ .opcode = 0x72, .reg = 6, .op = .vpslld },
        .{ .opcode = 0x73, .reg = 2, .op = .vpsrlq },
        .{ .opcode = 0x73, .reg = 3, .op = .vpsrldq },
        .{ .opcode = 0x73, .reg = 6, .op = .vpsllq },
        .{ .opcode = 0x73, .reg = 7, .op = .vpslldq },
    };
    for (members) |member| {
        const modrm: u8 = 0xC0 | (member.reg << 3);
        const decoded = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x79, member.opcode, modrm, 0x04, 0x0F });
        try std.testing.expectEqual(member.op, decoded.op);
        try std.testing.expectEqual(@as(u64, 4), decoded.imm);
    }

    // A reg field that is not a group member stays rejected rather than
    // decoding as whichever arm happened to be last.
    try std.testing.expectEqual(
        Op.invalid,
        decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x79, 0x72, 0xC0, 0x04, 0x0F }).op,
    );
}

// `C5 FA 53 C0` = `vrcpss xmm0, xmm0, xmm0`. Unlike the previous four decoder
// gaps this one was in the *image*, not in generated code — Xenia's own
// compiled reciprocal — so it was reached the moment the pipeline cache built
// its first pipeline rather than after billions of JIT steps.
test "VEX 0F 52/53 reciprocal forms decode, packed and scalar" {
    const failing = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x53, 0xC0, 0x0F });
    try std.testing.expectEqual(Op.vrcpss, failing.op);
    try std.testing.expectEqual(@as(u8, 4), failing.len);

    // The prefix picks packed versus scalar, and the scalar forms are
    // three-operand: VEX.vvvv supplies the upper lanes.
    try std.testing.expectEqual(Op.vrcpps, decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x53, 0xC1, 0x0F }).op);
    try std.testing.expectEqual(Op.vrsqrtss, decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x52, 0xC0, 0x0F }).op);
    try std.testing.expectEqual(Op.vrsqrtps, decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x52, 0xC1, 0x0F }).op);
    try std.testing.expectEqual(Op.vrcpss, decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7A, 0x53, 0xC0, 0x0F }).op);

    // 66 and F2 are not defined for either opcode and stay rejected.
    try std.testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x53, 0xC1, 0x0F }).op);
    try std.testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x52, 0xC1, 0x0F }).op);

    // The two instructions that follow the faulting one in the image, so the
    // stream is verified to resynchronise rather than just the one encoding.
    try std.testing.expectEqual(Op.vmovaps_mem_xmm, decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x29, 0x45, 0xC0, 0x0F }).op);
    try std.testing.expectEqual(Op.vmovss_xmm_mem, decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x10, 0x4D, 0xC0, 0x0F }).op);
}

test "approximate reciprocals match the hardware's special cases" {
    // The approximation itself is within spec at any accuracy — RCPPS is only
    // guaranteed to ~12 bits and differs between CPU models — but the special
    // cases are exact and must match.
    try std.testing.expectEqual(@as(f32, 0.25), decoder.approximateReciprocal(4.0));
    try std.testing.expectEqual(@as(f32, 0.5), decoder.approximateReciprocalSqrt(4.0));

    try std.testing.expect(std.math.isPositiveInf(decoder.approximateReciprocal(0.0)));
    try std.testing.expect(std.math.isNegativeInf(decoder.approximateReciprocal(-0.0)));
    try std.testing.expectEqual(@as(f32, 0.0), decoder.approximateReciprocal(std.math.inf(f32)));
    // A negative input to the square-root form is a NaN, not a reciprocal.
    try std.testing.expect(std.math.isNan(decoder.approximateReciprocalSqrt(-1.0)));
    try std.testing.expect(std.math.isPositiveInf(decoder.approximateReciprocalSqrt(0.0)));

    // Packed form covers every lane independently.
    var source: [16]u8 = undefined;
    const lanes = [_]f32{ 1.0, 2.0, 4.0, 8.0 };
    for (0..4) |lane| {
        std.mem.writeInt(u32, source[lane * 4 ..][0..4], @bitCast(lanes[lane]), .little);
    }
    const reciprocals = decoder.reciprocalVexPackedF32(source, false);
    const expected = [_]f32{ 1.0, 0.5, 0.25, 0.125 };
    for (0..4) |lane| {
        try std.testing.expectEqual(
            expected[lane],
            @as(f32, @bitCast(std.mem.readInt(u32, reciprocals[lane * 4 ..][0..4], .little))),
        );
    }
}
