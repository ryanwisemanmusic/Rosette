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

pub fn decodeTwoByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, _: u8) DecodedInsn {
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
            d.src_reg = @enumFromInt(rm.addr);
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
        return decodeSetcc(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
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
            d.dst_reg = @enumFromInt(rm.addr);
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
            d.dst_reg = @enumFromInt(rm.addr);
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
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.op = .popcnt_reg_mem;
            d.addr = rm.addr;
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xB6 or opcode2 == 0xB7) {
        return decodeMovzx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xBC or opcode2 == 0xBD) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.dst_reg = rm.reg;
        if (d.is_reg_form) {
            d.src_reg = @enumFromInt(rm.addr);
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
        return decodeMovsx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
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
        d.op = .nop;
        const extra = if (pos.* + 1 <= bytes.len and hasModRM(bytes[pos.*])) @as(u8, 1) else @as(u8, 0);
        d.len = @as(u8, @intCast(pos.* + extra));
        return d;
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

    if (opcode2 == 0x50 or opcode2 == 0x51) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x54) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"and");
    }

    if (opcode2 == 0x55) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"and");
    }

    if (opcode2 == 0x56) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"or");
    }

    if (opcode2 == 0x57) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .xor);
    }

    if (opcode2 == 0x58 or opcode2 == 0x59 or opcode2 == 0x5C or opcode2 == 0x5E or opcode2 == 0x5F) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
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
        d.xmm_src = @intFromEnum(@as(RegId, @enumFromInt(@as(u8, @intCast(rm.addr)))));
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

    if (opcode2 == 0xEF) {
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
        if (pos.* < bytes.len) {
            const modrm = bytes[pos.*];
            const reg = (modrm >> 3) & 7;
            if (reg == 5 or reg == 6 or reg == 7) {
                d.op = .nop;
                d.len = @as(u8, @intCast(pos.* + 1));
                return d;
            }
        }
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 1));
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
                decoded.src_reg = @enumFromInt(rm.addr);
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
    var d = DecodedInsn{};
    d.op = .nop;
    d.len = @as(u8, @intCast(pos.* + 1));
    return d;
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
        d.xmm_src = @intFromEnum(@as(RegId, @enumFromInt(@as(u8, @intCast(rm.addr)))));
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
