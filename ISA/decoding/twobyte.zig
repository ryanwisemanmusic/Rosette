//! Family: twobyte — 0F two-byte / three-byte opcodes + SSE byte decode.
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const addressing = @import("addressing.zig");
const groups = @import("groups.zig");
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

fn decodeLegacySseCompare(
    bytes: []const u8,
    pos: *usize,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    has_66: bool,
    has_f2: bool,
    has_f3: bool,
) DecodedInsn {
    // 0F C2 is the four legacy compare families. The mandatory prefix is the
    // precision/operation selector, and the final byte is the comparison
    // predicate. Normalize the two-operand SSE destination into source1 so
    // the shared scalar/packed compare executor can be used unchanged.
    if ((has_f2 and has_f3) or (has_66 and (has_f2 or has_f3)) or pos.* >= bytes.len) return .{};

    var decoded = DecodedInsn{ .legacy_sse = true };
    const operand_size: Size = if (has_f2 or has_66) .bits64 else .bits32;
    const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, operand_size);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = decoded.xmm_dst;
    if (decoded.is_reg_form) {
        decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    if (pos.* >= bytes.len) return .{};
    decoded.imm = bytes[pos.*];
    pos.* += 1;
    decoded.size = operand_size;
    decoded.uses_imm = true;
    decoded.op = if (has_f2)
        .vcmpsd
    else if (has_f3)
        .vcmpss
    else if (has_66)
        .vcmppd
    else
        .vcmpps;
    decoded.len = @intCast(pos.*);
    return decoded;
}

pub fn decodeTwoByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, rex: u8) DecodedInsn {
    var d = DecodedInsn{};
    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const opcode2 = bytes[pos.*];
    pos.* += 1;

    if (opcode2 == 0x05) {
        d.op = .syscall;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x0B) {
        d.op = .ud2;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x31) {
        // RDTSC has no ModR/M operand and writes EDX:EAX. The executor uses
        // the deterministic guest step clock rather than the host wall clock
        // so translated code observes a stable, monotonic time source.
        d.op = .rdtsc;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x77) {
        d.op = .emms;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x01 and has_f3 and !has_66 and !has_f2 and pos.* < bytes.len and bytes[pos.*] == 0xF9) {
        // RDTSCP is the F3 0F 01 F9 form. Its mandatory prefix is checked
        // here so the reserved unprefixed form cannot be mistaken for a
        // valid system-register read.
        pos.* += 1;
        d.op = .rdtscp;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x18 or opcode2 == 0x0D) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits8);
        if (d.is_reg_form) return .{};
        d.addr = rm.addr;
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x1F) {
        if (pos.* >= bytes.len) return .{};
        _ = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits32);
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 >= 0x40 and opcode2 <= 0x4F) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.dst_reg = rm.reg;
        d.cond = @enumFromInt(@as(u4, @truncate(opcode2 & 0x0F)));
        if (d.is_reg_form) {
            d.op = .cmovcc_reg_reg;
            d.src_reg = addressing.rmRegister(rm.addr);
        } else {
            d.op = .cmovcc_reg_mem;
            d.addr = rm.addr;
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 >= 0x80 and opcode2 <= 0x8F) {
        d.op = .jcc_rel32;
        d.cond = mapJccCond32(opcode2);
        if (pos.* + 4 > bytes.len) return .{};
        d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
        d.rip_relative = true;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 >= 0x90 and opcode2 <= 0x9F) {
        return decodeSetcc(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, rex != 0, opcode2);
    }

    if (opcode2 == 0xA2) {
        d.op = .cpuid;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x01 and pos.* < bytes.len and bytes[pos.*] == 0xD0) {
        pos.* += 1;
        d.op = .xgetbv;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0xAF) {
        return decodeImulTwoOp(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB0 or opcode2 == 0xB1) {
        return decodeCmpxchg(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xA3 or opcode2 == 0xAB or opcode2 == 0xB3 or opcode2 == 0xBB) {
        if (pos.* >= bytes.len) return .{};
        const is_mem = bytes[pos.*] < 0xC0;
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.src_reg = rm.reg;
        if (is_mem) {
            d.addr = rm.addr;
            d.op = switch (opcode2) {
                0xA3 => .bt_mem_reg,
                0xAB => .bts_mem_reg,
                0xB3 => .btr_mem_reg,
                0xBB => .btc_mem_reg,
                else => unreachable,
            };
        } else {
            d.dst_reg = addressing.rmRegister(rm.addr);
            d.op = switch (opcode2) {
                0xA3 => .bt_reg_reg,
                0xAB => .bts_reg_reg,
                0xB3 => .btr_reg_reg,
                0xBB => .btc_reg_reg,
                else => unreachable,
            };
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xA4 or opcode2 == 0xA5 or opcode2 == 0xAC or opcode2 == 0xAD) {
        // SHLD/SHRD r/m, r, imm8 (0F A4 / 0F AC) and r/m, r, CL
        // (0F A5 / 0F AD). ModRM.reg is the *source* whose bits fill the
        // vacated end, not a second destination.
        if (pos.* >= bytes.len) return .{};
        const is_mem = bytes[pos.*] < 0xC0;
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.src_reg = rm.reg;
        const uses_cl = opcode2 == 0xA5 or opcode2 == 0xAD;
        if (!uses_cl) {
            if (pos.* >= bytes.len) return .{};
            d.imm = bytes[pos.*];
            pos.* += 1;
            d.uses_imm = true;
        }
        const left = opcode2 == 0xA4 or opcode2 == 0xA5;
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (left)
                (if (uses_cl) Op.shld_mem_cl else Op.shld_mem_imm8)
            else
                (if (uses_cl) Op.shrd_mem_cl else Op.shrd_mem_imm8);
        } else {
            d.dst_reg = addressing.rmRegister(rm.addr);
            d.op = if (left)
                (if (uses_cl) Op.shld_reg_cl else Op.shld_reg_imm8)
            else
                (if (uses_cl) Op.shrd_reg_cl else Op.shrd_reg_imm8);
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xBA) {
        // Group 8: BT/BTS/BTR/BTC with imm8 (0F BA /4-7 ib).
        if (pos.* >= bytes.len) return .{};
        const group_modrm = bytes[pos.*];
        const group_op = (group_modrm >> 3) & 0x07;
        if (group_op < 4) return .{}; // groups 0-3 are reserved
        const is_mem = group_modrm < 0xC0;
        // REX.R does not extend the opcode field of a ModRM opcode group.
        const rm = readModRM(&d, bytes, pos, false, rex_x, rex_b, d.size);
        if (pos.* >= bytes.len) return .{};
        d.imm = bytes[pos.*];
        pos.* += 1;
        d.uses_imm = true;
        if (is_mem) {
            d.addr = rm.addr;
            d.op = switch (group_op) {
                4 => .bt_mem_imm,
                5 => .bts_mem_imm,
                6 => .btr_mem_imm,
                7 => .btc_mem_imm,
                else => unreachable,
            };
        } else {
            d.dst_reg = addressing.rmRegister(rm.addr);
            d.op = switch (group_op) {
                4 => .bt_reg_imm,
                5 => .bts_reg_imm,
                6 => .btr_reg_imm,
                7 => .btc_reg_imm,
                else => unreachable,
            };
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xB8) {
        // POPCNT is mandatory-F3. Without F3, 0F B8 is not this instruction.
        if (!has_f3 or pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.dst_reg = rm.reg;
        if (d.is_reg_form) {
            d.op = .popcnt_reg_reg;
            d.src_reg = addressing.rmRegister(rm.addr);
        } else {
            d.op = .popcnt_reg_mem;
            d.addr = rm.addr;
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xB6 or opcode2 == 0xB7) {
        return decodeMovzx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, rex != 0);
    }

    if (opcode2 == 0xBC or opcode2 == 0xBD) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.dst_reg = rm.reg;
        if (d.is_reg_form) {
            d.src_reg = addressing.rmRegister(rm.addr);
            d.op = if (has_f3)
                if (opcode2 == 0xBC) .tzcnt_reg_reg else .lzcnt_reg_reg
            else if (opcode2 == 0xBC)
                .bsf_reg_reg
            else
                .bsr_reg_reg;
        } else {
            d.addr = rm.addr;
            d.op = if (has_f3)
                if (opcode2 == 0xBC) .tzcnt_reg_mem else .lzcnt_reg_mem
            else if (opcode2 == 0xBC)
                .bsf_reg_mem
            else
                .bsr_reg_mem;
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xBE or opcode2 == 0xBF) {
        return decodeMovsx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, rex != 0);
    }

    if (opcode2 == 0xC0 or opcode2 == 0xC1) {
        return decodeXadd(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 >= 0xC8 and opcode2 <= 0xCF) {
        if (has_66) return .{};
        d.op = .bswap_reg;
        d.size = if (rex_w) .bits64 else .bits32;
        d.dst_reg = mapReg(opcode2 - 0xC8, rex_b);
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0x10 or opcode2 == 0x11) {
        return decodeMovupsMovss(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0x28 or opcode2 == 0x29) {
        return decodeMovaps(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0x2E or opcode2 == 0x2F) {
        // COMISS/UCOMISS and their 66-prefixed double-precision forms are
        // legacy two-operand comparisons. Reuse the VEX comparison executor
        // by making ModRM.reg both the destination and its first source; the
        // legacy_sse bit keeps the upper YMM state unchanged where relevant.
        if (has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, if (has_66) .bits64 else .bits32);
        decoded.xmm_src = @intFromEnum(rm.reg);
        decoded.op = if (has_66) .vucomisd else .vucomiss;
        if (decoded.is_reg_form) {
            decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x2A) {
        // CVTSI2SS (F3 0F 2A) and CVTSI2SD (F2 0F 2A) convert a signed GPR
        // or memory integer into the low lane of an XMM destination. Like
        // the other legacy scalar SSE operations, the upper XMM lanes and
        // the architectural YMM upper half are preserved.
        if (has_66 or (has_f2 and has_f3) or (!has_f2 and !has_f3) or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const source_size: Size = if (rex_w) .bits64 else .bits32;
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, source_size);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = decoded.xmm_dst;
        decoded.size = source_size;
        if (has_f3) {
            decoded.op = if (decoded.is_reg_form) .vcvtsi2ss_xmm_reg else .vcvtsi2ss_xmm_mem;
        } else {
            decoded.op = if (decoded.is_reg_form) .vcvtsi2sd_xmm_reg else .vcvtsi2sd_xmm_mem;
        }
        if (decoded.is_reg_form) {
            decoded.src_reg = addressing.rmRegister(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x2C or opcode2 == 0x2D) {
        // CVTTSS2SI/CVTTSD2SI (2C) and CVTSS2SI/CVTSD2SI (2D) convert a
        // scalar XMM or memory value to a signed GPR. F3 selects single
        // precision and F2 selects double precision; REX.W selects a
        // 64-bit integer destination.
        if (has_66 or (has_f2 and has_f3) or (!has_f2 and !has_f3) or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, if (has_f2) .bits64 else .bits32);
        decoded.dst_reg = rm.reg;
        decoded.size = if (rex_w) .bits64 else .bits32;
        decoded.op = if (opcode2 == 0x2C)
            if (has_f3) .vcvttss2si else .vcvttsd2si
        else if (has_f3)
            .vcvtss2si
        else
            .vcvtsd2si;
        if (decoded.is_reg_form) {
            decoded.xmm_src = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x12 or opcode2 == 0x13 or opcode2 == 0x16 or opcode2 == 0x17) {
        return decodeLegacySseHalfMove(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0x38) {
        return decodeThreeByte(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, 0x38);
    }

    if (opcode2 == 0x3A) {
        return decodeThreeByte(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, 0x3A);
    }

    if (opcode2 == 0x40 or opcode2 == 0x41) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x50) {
        // MOVMSKPS/MOVMSKPD only accept a register-form XMM source.
        if (pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        if (!decoded.is_reg_form) return .{};
        decoded.op = if (has_66) .vmovmskpd else .vmovmskps;
        decoded.dst_reg = rm.reg;
        decoded.xmm_src = addressing.rmVectorIndex(rm.addr);
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x51) {
        // SQRTPS/SQRTPD and scalar SQRTSS/SQRTSD. Scalar legacy forms merge
        // their low result into the old destination, while packed forms use
        // the r/m vector directly.
        if (pos.* >= bytes.len or (has_66 and has_f2) or (has_66 and has_f3)) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, if (has_f2 or has_66) .bits64 else .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = decoded.xmm_dst;
        decoded.op = if (has_f2)
            .vsqrtsd
        else if (has_f3)
            .vsqrtss
        else if (has_66)
            .vsqrtpd
        else
            .vsqrtps;
        if (decoded.is_reg_form) {
            decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x5A) {
        return decodeLegacySseConversion(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3);
    }

    if (opcode2 == 0xD6 and has_66) {
        // 66 0F D6 /r is the legacy SSE2 MOVQ store form:
        // MOVQ xmm2/m64, xmm1.  The ModRM.reg XMM register is the source;
        // ModRM.r/m selects either a 64-bit memory destination or the low
        // 64-bit destination XMM register when mod=3.
        if (has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true, .size = .bits64 };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = if (decoded.is_reg_form) .vmovq_xmm_xmm else .vmovq_mem64_xmm;
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (decoded.is_reg_form) {
            decoded.xmm_dst = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x7E and has_f3) {
        // F3 0F 7E /r is the SSE2 MOVQ load from xmm/m64.  Unlike the
        // 66-prefixed MOVD/MOVQ transfer family below, this encoding is
        // intrinsically a 64-bit XMM load and does not require REX.W.
        if (has_66 or has_f2 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true, .size = .bits64 };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = if (decoded.is_reg_form) .vmovq_xmm_xmm else .vmovq_xmm_mem64;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (decoded.is_reg_form) {
            decoded.xmm_src = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x6E or opcode2 == 0x7E) {
        // MOVD xmm,r/m32 and MOVD r/m32,xmm require the 66 prefix in the
        // XMM form. With REX.W, the same encodings are MOVQ and carry a full
        // 64-bit GPR or memory operand. The legacy operation shares the VEX
        // executor, but unlike VEX it does not clear the destination
        // register's upper YMM half.
        if (!has_66 or has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        const transfer_size: Size = if (rex_w) .bits64 else .bits32;
        var decoded = DecodedInsn{ .legacy_sse = true, .size = transfer_size };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, transfer_size);
        if (opcode2 == 0x6E) {
            decoded.op = if (rex_w)
                (if (decoded.is_reg_form) .vmovq_xmm_reg64 else .vmovq_xmm_mem64)
            else
                (if (decoded.is_reg_form) .vmovd_xmm_reg32 else .vmovd_xmm_mem32);
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (decoded.is_reg_form) {
                decoded.src_reg = addressing.rmRegister(rm.addr);
            } else {
                decoded.addr = rm.addr;
            }
        } else {
            decoded.op = if (rex_w)
                (if (decoded.is_reg_form) .vmovq_reg64_xmm else .vmovq_mem64_xmm)
            else
                (if (decoded.is_reg_form) .vmovd_reg32_xmm else .vmovd_mem32_xmm);
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (decoded.is_reg_form) {
                decoded.dst_reg = addressing.rmRegister(rm.addr);
            } else {
                decoded.addr = rm.addr;
            }
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x60 or opcode2 == 0x61 or opcode2 == 0x62 or opcode2 == 0x68 or
        opcode2 == 0x69 or opcode2 == 0x6A or opcode2 == 0x6C or opcode2 == 0x6D)
    {
        // The 66-prefixed forms are the legacy SSE2 PUNPCK family.  Reuse
        // the VEX-shaped operation identities used by the shared executor,
        // but retain legacy_sse so the destination's upper YMM half is not
        // zeroed (unlike a VEX.128 instruction).  Unprefixed 0F 60/61/62/
        // 64-6A/6C-6D are MMX encodings and remain outside this XMM decoder
        // until the MMX register file is modeled.
        if (!has_66 or has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = switch (opcode2) {
            0x60 => .vpunpcklbw,
            0x61 => .vpunpcklwd,
            0x62 => .vpunpckldq,
            0x68 => .vpunpckhbw,
            0x69 => .vpunpckhwd,
            0x6A => .vpunpckhdq,
            0x6C => .vpunpcklqdq,
            0x6D => .vpunpckhqdq,
            else => return .{},
        };
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = decoded.xmm_dst;
        if (decoded.is_reg_form) {
            decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x6F or opcode2 == 0x7F) {
        // MOVDQA (66) and MOVDQU (F3) are the two XMM forms of the legacy
        // aligned/unaligned vector move family.  Plain 0F 6F/7F is an MMX
        // move and is intentionally left to the MMX boundary until that
        // register file is modeled.
        const is_dqa = has_66 and !has_f2 and !has_f3;
        const is_dqu = has_f3 and !has_66 and !has_f2;
        if ((!is_dqa and !is_dqu) or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        if (opcode2 == 0x6F) {
            decoded.op = if (is_dqa)
                (if (decoded.is_reg_form) .vmovdqa_xmm_xmm else .vmovdqa_xmm_mem)
            else
                (if (decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_xmm_mem);
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (decoded.is_reg_form) {
                decoded.xmm_src = addressing.rmVectorIndex(rm.addr);
            } else {
                decoded.addr = rm.addr;
            }
        } else {
            decoded.op = if (is_dqa)
                (if (decoded.is_reg_form) .vmovdqa_xmm_xmm else .vmovdqa_mem_xmm)
            else
                (if (decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_mem_xmm);
            if (decoded.is_reg_form) {
                decoded.xmm_dst = addressing.rmVectorIndex(rm.addr);
                decoded.xmm_src = @intFromEnum(rm.reg);
            } else {
                decoded.xmm_src = @intFromEnum(rm.reg);
                decoded.addr = rm.addr;
            }
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 >= 0x54 and opcode2 <= 0x57) {
        return decodeLegacySseBinary(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0xEF) {
        // 66 0F EF /r is PXOR for XMM registers.  The unprefixed form is
        // the MMX instruction and F2/F3 are not valid aliases; leave those
        // forms invalid until the MMX register file is modeled.
        if (!has_66 or has_f2 or has_f3) return .{};
        return decodeLegacySseBinary(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0xDB or opcode2 == 0xDF or opcode2 == 0xEB) {
        // PAND (DB), PANDN (DF), and POR (EB) are the integer packed-XMM
        // counterparts to the AND/ANDN/OR floating-point encodings.  All
        // three require 66 in the legacy SSE2 form; the unprefixed bytes are
        // MMX instructions and must not enter the XMM executor.
        if (!has_66 or has_f2 or has_f3) return .{};
        return decodeLegacySseBinary(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0x58 or opcode2 == 0x59 or opcode2 == 0x5C or opcode2 == 0x5D or opcode2 == 0x5E or opcode2 == 0x5F) {
        return decodeLegacySseArithmetic(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0xC2) {
        return decodeLegacySseCompare(bytes, &pos.*, rex_r, rex_x, rex_b, has_66, has_f2, has_f3);
    }

    if (opcode2 == 0xC6) {
        // SHUFPS (0F C6 /r ib) and SHUFPD (66 0F C6 /r ib) are legacy
        // two-operand shuffle instructions.  Normalize the destination as
        // source1 so CLEO's immediate binary path can execute both forms;
        // legacy_sse preserves the destination's upper YMM half.
        if (has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, if (has_66) .bits64 else .bits32);
        decoded.op = if (has_66) .vshufpd else .vshufps;
        decoded.size = if (has_66) .bits64 else .bits32;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = decoded.xmm_dst;
        if (decoded.is_reg_form) {
            decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        if (pos.* >= bytes.len) return .{};
        decoded.imm = bytes[pos.*];
        pos.* += 1;
        decoded.uses_imm = true;
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x63 or opcode2 == 0x67 or opcode2 == 0x6B) {
        // PACKSSWB, PACKUSWB, and PACKSSDW are legacy SSE2 two-operand
        // narrowing operations.  Their packed source width is the full XMM
        // register, so use the existing CLEO binary pack implementation and
        // retain legacy_sse for the upper-YMM preservation rule.
        if (!has_66 or has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true, .size = .bits64 };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = switch (opcode2) {
            0x63 => .vpacksswb,
            0x67 => .vpackuswb,
            0x6B => .vpackssdw,
            else => unreachable,
        };
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = decoded.xmm_dst;
        if (decoded.is_reg_form) {
            decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0xD4) {
        // 66 0F D4 /r is the legacy SSE2 PADDQ form.  The shared vector
        // executor already implements the operation as VPADDQ, but the
        // legacy encoding is a two-operand instruction: ModRM.reg is both
        // the destination and the first source, while ModRM.r/m is the
        // second source.  Keep the legacy marker so the destination's upper
        // YMM half remains untouched, as required by a legacy SSE operation.
        // The unprefixed form is the MMX PADDQ encoding and is not decoded by
        // this XMM path; F2/F3 are reserved for this opcode.
        if (!has_66 or has_f2 or has_f3 or pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{ .legacy_sse = true, .size = .bits64 };
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpaddq;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = decoded.xmm_dst;
        if (decoded.is_reg_form) {
            decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
        } else {
            decoded.addr = rm.addr;
        }
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    if (opcode2 == 0x70) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 3));
        return d;
    }

    if (opcode2 == 0xD1 or opcode2 == 0xD2 or opcode2 == 0xD3) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xD7) {
        if (!has_66) {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos.* + 1));
            return d;
        }
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        if (!d.is_reg_form) {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos.*));
            return d;
        }
        d.xmm_src = @intFromEnum(@as(RegId, addressing.rmRegister(rm.addr)));
        d.dst_reg = rm.reg;
        d.op = .pmovmskb;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0xE6) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xF1 or opcode2 == 0xF2 or opcode2 == 0xF3 or opcode2 == 0xF4 or opcode2 == 0xF5) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xAE) {
        if (pos.* >= bytes.len) return .{};
        const modrm = bytes[pos.*];
        const group = (modrm >> 3) & 7;
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits32);
        // Fences use a register-form ModR/M byte whose r/m field is ignored.
        // The decoder must identify them explicitly: treating MFENCE as a
        // NOP allows host/guest memory-ordering races to pass unnoticed.
        // Keep MOD=11 and the opcode-extension bits, while ignoring the
        // architecturally unused r/m field.  0xC7 would discard bit 3 and
        // turn LFENCE (E8) into C0; the fence encodings are E8/F0/F8.
        const fence_code = modrm & 0xF8;
        if (d.is_reg_form and fence_code == 0xE8) {
            d.op = .lfence;
        } else if (d.is_reg_form and fence_code == 0xF0) {
            d.op = .mfence;
        } else if (d.is_reg_form and fence_code == 0xF8) {
            d.op = .sfence;
        } else if (!d.is_reg_form and group == 2) {
            d.op = .ldmxcsr_mem32;
        } else if (!d.is_reg_form and group == 3) {
            d.op = .stmxcsr_mem32;
        } else {
            // Preserve the existing boundary-safe behavior for 0F AE forms
            // whose full architectural state model is not yet represented.
            d.op = .nop;
        }
        d.size = .bits32;
        d.addr = rm.addr;
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xC7) {
        if (pos.* >= bytes.len) return .{};
        const modrm_byte = bytes[pos.*];
        const reg = (modrm_byte >> 3) & 7;
        if (reg == 1) {
            const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
            if (d.is_reg_form) return .{};
            d.addr = rm.addr;
            d.op = if (rex_w) .cmpxchg16b_mem else .cmpxchg8b_mem;
            d.len = @intCast(pos.*);
            return d;
        }
        return .{};
    }

    return .{};
}

pub fn decodeThreeByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, opcode: u8) DecodedInsn {
    if (opcode == 0x38 and has_f2 and !has_f3 and pos.* < bytes.len) {
        const opcode3 = bytes[pos.*];
        if (opcode3 == 0xF0 or opcode3 == 0xF1) {
            pos.* += 1;
            var decoded = DecodedInsn{};
            if (pos.* >= bytes.len) return .{};
            const is_memory = bytes[pos.*] < 0xC0;
            const source_size: Size = if (opcode3 == 0xF0)
                .bits8
            else if (rex_w)
                .bits64
            else if (has_66)
                .bits16
            else
                .bits32;
            const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, source_size);
            decoded.op = if (is_memory) .crc32_reg_mem else .crc32_reg_reg;
            decoded.size = source_size;
            decoded.dst_size = if (rex_w) .bits64 else .bits32;
            decoded.dst_reg = rm.reg;
            if (is_memory) {
                decoded.addr = rm.addr;
            } else {
                decoded.src_reg = addressing.rmRegister(rm.addr);
            }
            decoded.len = @intCast(pos.*);
            return decoded;
        }
    }

    // MOVDIR64B is encoded as 66 0F 38 F8 /r.  The ModR/M.reg operand is a
    // GPR containing the 64-byte destination address; the r/m operand is the
    // source memory block.  It is not a normal register-to-memory move, so it
    // needs its own operation identity instead of being mistaken for MOVBE.
    if (opcode == 0x38 and has_66 and !has_f2 and !has_f3 and pos.* < bytes.len and bytes[pos.*] == 0xF8) {
        pos.* += 1;
        if (pos.* >= bytes.len) return .{};
        var decoded = DecodedInsn{};
        const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        if (decoded.is_reg_form) return .{};
        decoded.op = .movdir64b;
        decoded.size = .bits64;
        decoded.dst_reg = rm.reg;
        decoded.addr = rm.addr;
        decoded.len = @intCast(pos.*);
        return decoded;
    }

    // MOVBE is deliberately handled separately from F2-prefixed CRC32 even
    // though both use 0F 38 F0/F1. Leaving an unprefixed MOVBE to the generic
    // fallback used to consume only `0F 38 F0`, after which the ModRM and
    // displacement bytes were executed as standalone instructions. Besides
    // producing a wrong value, that silently corrupts memory and permanently
    // loses the generated-code instruction boundary.
    if (opcode == 0x38 and !has_f2 and !has_f3 and pos.* < bytes.len) {
        const opcode3 = bytes[pos.*];
        if (opcode3 == 0xF0 or opcode3 == 0xF1) {
            pos.* += 1;
            if (pos.* >= bytes.len) return .{};

            var decoded = DecodedInsn{};
            const operand_size: Size = if (rex_w)
                .bits64
            else if (has_66)
                .bits16
            else
                .bits32;
            const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, operand_size);
            // Intel defines MOVBE only between a GPR and memory. Treat the
            // reserved register-to-register encoding as invalid rather than
            // manufacturing semantics for it.
            if (decoded.is_reg_form) return .{};

            decoded.size = operand_size;
            decoded.addr = rm.addr;
            if (opcode3 == 0xF0) {
                decoded.op = .movbe_reg_mem;
                decoded.dst_reg = rm.reg;
            } else {
                decoded.op = .movbe_mem_reg;
                decoded.src_reg = rm.reg;
            }
            decoded.len = @intCast(pos.*);
            return decoded;
        }
    }

    if (pos.* >= bytes.len) return .{};
    const opcode3 = bytes[pos.*];
    if (opcode3 == 0xF5 or opcode3 == 0xF7 or opcode3 == 0xFA or opcode3 == 0xFB or opcode3 == 0xFC) {
        pos.* += 1;
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, false, opcode3, .nop);
    }
    // Never consume just the opcode bytes of an unsupported three-byte
    // instruction. Its ModRM/SIB/displacement/immediate length is unknown,
    // so a partial NOP would resume in operand data and convert a clean
    // unsupported-instruction report into arbitrary memory corruption.
    return .{};
}

pub fn decodeSseBytes(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, sse_op: anytype) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    _ = opcode;
    var d = DecodedInsn{};
    if (pos.* >= bytes.len) return .{};
    const modrm = bytes[pos.*];
    const is_reg = modrm >= 0xC0;
    if (is_reg) {
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        d.xmm_dst = @intFromEnum(rm.reg);
        d.xmm_src = @intFromEnum(@as(RegId, addressing.rmRegister(rm.addr)));
        if (comptime std.mem.eql(u8, @tagName(sse_op), "xor")) {
            d.op = .xorps_xmm_xmm;
        } else {
            d.op = .nop;
        }
        d.len = @as(u8, @intCast(pos.*));
        return d;
    } else {
        _ = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }
}

fn decodeLegacySseBinary(
    bytes: []const u8,
    pos: *usize,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    has_66: bool,
    has_f2: bool,
    has_f3: bool,
    opcode: u8,
) DecodedInsn {
    // AND/ANDN/OR/XOR packed single/double accept no mandatory prefix or
    // 66. The integer PAND/PANDN/POR forms are routed here too after the
    // caller has verified their required 66 prefix. F2/F3 are different
    // scalar instruction families and must not be accidentally reinterpreted
    // as a bitwise operation.
    if (has_f2 or has_f3 or pos.* >= bytes.len) return .{};
    var decoded = DecodedInsn{ .legacy_sse = true };
    const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.xmm_src = decoded.xmm_dst;
    // Keep the long-standing two-register XORPS representation used by the
    // ELF processor. The shared VEX-shaped representation remains useful for
    // the other legacy SSE forms (and for the memory form), but changing this
    // established operation tag would make an otherwise unrelated decoder
    // contract regress.
    if (!has_66 and opcode == 0x57 and decoded.is_reg_form) {
        decoded.op = .xorps_xmm_xmm;
        decoded.xmm_src = addressing.rmVectorIndex(rm.addr);
        decoded.len = @intCast(pos.*);
        return decoded;
    }
    decoded.op = switch (opcode) {
        0x54 => if (has_66) .vandpd else .vandps,
        0x55 => if (has_66) .vandnpd else .vandnps,
        0x56 => if (has_66) .vorpd else .vorps,
        0x57 => if (has_66) .vxorpd else .vxorps,
        0xDB => .vandpd,
        0xDF => .vandnpd,
        0xEB => .vorpd,
        0xEF => .vpxor,
        else => return .{},
    };
    if (decoded.is_reg_form) {
        decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    decoded.len = @intCast(pos.*);
    return decoded;
}

fn decodeLegacySseHalfMove(
    bytes: []const u8,
    pos: *usize,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    has_66: bool,
    has_f2: bool,
    has_f3: bool,
    opcode: u8,
) DecodedInsn {
    // F2/F3 select MOVDDUP/MOVSLDUP/MOVSHDUP, which are separate broadcast
    // operations. Do not reinterpret those encodings as a half move.
    if (has_f2 or has_f3 or pos.* >= bytes.len) return .{};
    var decoded = DecodedInsn{ .legacy_sse = true };
    const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, .bits64);

    if (decoded.is_reg_form) {
        // In the legacy, unprefixed register forms 0F 12/16 are MOVHLPS and
        // MOVLHPS. The 66-prefixed register forms belong to MOVLPD/MOVHPD
        // and are deliberately left invalid here until their register form
        // is represented explicitly.
        if (has_66 or (opcode != 0x12 and opcode != 0x16)) return .{};
        decoded.op = if (opcode == 0x12) .vmovhlps else .vmovlhps;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = addressing.rmVectorIndex(rm.addr);
    } else {
        decoded.op = switch (opcode) {
            0x12 => if (has_66) .vmovlpd_xmm_xmm_mem64 else .vmovlps_xmm_xmm_mem64,
            0x13 => if (has_66) .vmovlpd_mem64_xmm else .vmovlps_mem64_xmm,
            0x16 => if (has_66) .vmovhpd_xmm_xmm_mem64 else .vmovhps_xmm_xmm_mem64,
            0x17 => if (has_66) .vmovhpd_mem64_xmm else .vmovhps_mem64_xmm,
            else => return .{},
        };
        if (opcode == 0x12 or opcode == 0x16) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            // The load forms merge into the old destination XMM register.
            decoded.xmm_src = decoded.xmm_dst;
        } else {
            decoded.xmm_src = @intFromEnum(rm.reg);
        }
        decoded.addr = rm.addr;
    }
    decoded.len = @intCast(pos.*);
    return decoded;
}

fn decodeLegacySseArithmetic(
    bytes: []const u8,
    pos: *usize,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    has_66: bool,
    has_f2: bool,
    has_f3: bool,
    opcode: u8,
) DecodedInsn {
    if (has_66 and (has_f2 or has_f3)) return .{};
    if (pos.* >= bytes.len) return .{};
    var decoded = DecodedInsn{ .legacy_sse = true };
    const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, if (has_66 or has_f2) .bits64 else .bits32);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    // Legacy SSE has DEST as the first source; the VEX executor's source1
    // field is therefore normalized to the same XMM register.
    decoded.xmm_src = decoded.xmm_dst;
    decoded.op = switch (opcode) {
        0x58 => if (has_f3) .vaddss else if (has_f2) .vaddsd else if (has_66) .vaddpd else .vaddps,
        0x59 => if (has_f3) .vmulss else if (has_f2) .vmulsd else if (has_66) .vmulpd else .vmulps,
        0x5C => if (has_f3) .vsubss else if (has_f2) .vsubsd else if (has_66) .vsubpd else .vsubps,
        0x5D => if (has_f3) .vminss else if (has_f2) .vminsd else if (has_66) .vminpd else .vminps,
        0x5E => if (has_f3) .vdivss else if (has_f2) .vdivsd else if (has_66) .vdivpd else .vdivps,
        0x5F => if (has_f3) .vmaxss else if (has_f2) .vmaxsd else if (has_66) .vmaxpd else .vmaxps,
        else => return .{},
    };
    if (decoded.is_reg_form) {
        decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    decoded.len = @intCast(pos.*);
    return decoded;
}

fn decodeLegacySseConversion(
    bytes: []const u8,
    pos: *usize,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    has_66: bool,
    has_f2: bool,
    has_f3: bool,
) DecodedInsn {
    // 0F 5A is the packed conversion family, with mandatory prefixes
    // selecting the scalar forms:
    //
    //   0F 5A       CVTPS2PD xmm, xmm/m64
    //   66 0F 5A    CVTPD2PS xmm, xmm/m128
    //   F3 0F 5A    CVTSS2SD xmm, xmm/m32
    //   F2 0F 5A    CVTSD2SS xmm, xmm/m64
    //
    // The VEX executor already owns the operation tags for this family. The
    // legacy_sse marker is important: legacy SSE preserves the destination's
    // upper YMM half, while the corresponding VEX.128 operation clears it.
    // Multiple mandatory prefixes are reserved rather than being silently
    // assigned one precedence over another.
    if ((has_66 and (has_f2 or has_f3)) or (has_f2 and has_f3) or pos.* >= bytes.len) return .{};

    var decoded = DecodedInsn{ .legacy_sse = true };
    const source_size: Size = if (has_f3) .bits32 else .bits64;
    const rm = readModRM(&decoded, bytes, pos, rex_r, rex_x, rex_b, source_size);
    decoded.xmm_dst = @intFromEnum(rm.reg);

    if (has_f3) {
        // CVTSS2SD is a scalar two-operand merge: the destination is also
        // the preserved first source for the upper XMM lanes.
        decoded.op = .vcvtss2sd;
        decoded.xmm_src = decoded.xmm_dst;
    } else if (has_f2) {
        // CVTSD2SS has the same merge shape, with a double source.
        decoded.op = .vcvtsd2ss;
        decoded.xmm_src = decoded.xmm_dst;
    } else if (has_66) {
        decoded.op = .vcvtpd2ps;
        decoded.xmm_src = decoded.xmm_dst;
    } else {
        decoded.op = .vcvtps2pd;
        decoded.xmm_src = decoded.xmm_dst;
    }

    if (decoded.is_reg_form) {
        decoded.xmm_src2 = addressing.rmVectorIndex(rm.addr);
    } else {
        decoded.addr = rm.addr;
    }
    decoded.len = @intCast(pos.*);
    return decoded;
}
