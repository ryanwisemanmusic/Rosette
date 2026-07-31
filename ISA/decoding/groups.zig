//! Family: groups — ModRM-group opcode families (0x80-0xFF groups, movzx/movsx/...).
//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).

const std = @import("std");
const types = @import("types.zig");
const addressing = @import("addressing.zig");
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

pub fn decodeArithRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, arith_type: enum { add, @"or", adc, sbb, @"and", sub, xor, cmp }) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;

    const is_byte = (opcode & 0x01) == 0;
    const sz: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
    const is_reg_reg = bytes[start_pos + 1] >= 0xC0;
    const is_mem_to_reg = (opcode & 0x02) != 0;

    const reg_mem_ops: [8]Op = .{
        .add_reg8_mem8, .or_reg8_mem8,  .adc_reg8_mem8, .sbb_reg8_mem8,
        .and_reg8_mem8, .sub_reg8_mem8, .xor_reg8_mem8, .cmp_reg8_mem8,
    };
    const mem_reg_ops: [8]Op = .{
        .add_mem8_reg8, .or_mem8_reg8,  .invalid,       .invalid,
        .and_mem8_reg8, .sub_mem8_reg8, .xor_mem8_reg8, .cmp_mem8_reg8,
    };
    const reg_reg_ops: [8]Op = .{
        .add_reg8_reg8, .or_reg8_reg8,  .invalid,       .sbb_reg8_reg8,
        .and_reg8_reg8, .sub_reg8_reg8, .xor_reg8_reg8, .cmp_reg8_reg8,
    };

    const base_op = if (arith_type == .sbb and !is_reg_reg and (!is_mem_to_reg or sz != .bits8))
        .invalid
    else if (is_reg_reg)
        reg_reg_ops[@intFromEnum(arith_type)]
    else if (is_mem_to_reg)
        reg_mem_ops[@intFromEnum(arith_type)]
    else
        mem_reg_ops[@intFromEnum(arith_type)];
    const off = @intFromEnum(sz) - @intFromEnum(Size.bits8);
    d.op = if (base_op == .invalid)
        .invalid
    else
        @enumFromInt(@intFromEnum(base_op) + off);

    if (is_reg_reg) {
        if (is_mem_to_reg) {
            d.dst_reg = rm.reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
            d.src_reg = rm.reg;
        }
        d.is_reg_form = true;
    } else if (is_mem_to_reg) {
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.src_reg = rm.reg;
        d.addr = rm.addr;
    }
    d.size = sz;
    d.len = @as(u8, @intCast(pos));

    return d;
}

pub fn decodeMovRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;

    _ = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x88 or opcode == 0x8A) .bits8 else .bits32;

    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];

    const to_reg = (opcode & 0x02) != 0;
    const byte_op = opcode == 0x88 or opcode == 0x8A;

    const actual_sz: Size = if (byte_op) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, actual_sz);
    const is_reg = modrm >= 0xC0;

    if (to_reg) {
        if (is_reg) {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_reg8,
                .bits16 => .mov_reg16_reg16,
                .bits32 => .mov_reg32_reg32,
                .bits64 => .mov_reg64_reg64,
            };
            d.dst_reg = rm.reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_mem8,
                .bits16 => .mov_reg16_mem16,
                .bits32 => .mov_reg32_mem32,
                .bits64 => .mov_reg64_mem64,
            };
            d.dst_reg = rm.reg;
            d.addr = rm.addr;
        }
    } else {
        if (is_reg) {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_reg8,
                .bits16 => .mov_reg16_reg16,
                .bits32 => .mov_reg32_reg32,
                .bits64 => .mov_reg64_reg64,
            };
            d.dst_reg = @enumFromInt(rm.addr);
            d.src_reg = rm.reg;
        } else {
            d.op = switch (actual_sz) {
                .bits8 => .mov_mem8_reg8,
                .bits16 => .mov_mem16_reg16,
                .bits32 => .mov_mem32_reg32,
                .bits64 => .mov_mem64_reg64,
            };
            d.addr = rm.addr;
            d.src_reg = rm.reg;
        }
    }

    d.size = actual_sz;
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeLea(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    if (modrm < 0xC0) {
        const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        d.op = .lea_reg_mem;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
        d.size = sz;
        d.len = @as(u8, @intCast(pos));
        return d;
    }
    d.op = .invalid;
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodePopRm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits64;
    _ = sz;
    if (modrm >= 0xC0) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        d.op = .pop_reg;
        d.dst_reg = @enumFromInt(rm.addr);
    } else {
        d.op = .pop_mem64;
        d.addr = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64).addr;
    }
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeGroup1Imm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group_op = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x80) .bits8 else .bits32;

    const is_byte_imm = opcode == 0x80 or opcode == 0x83;
    const imm_size: u8 = if (is_byte_imm) 1 else if (sz == .bits16) 2 else 4;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (pos + imm_size > bytes.len) return .{};
    const imm: u64 = if (is_byte_imm)
        if (opcode == 0x83) @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos]))))) else bytes[pos]
    else if (imm_size == 2)
        std.mem.readInt(u16, bytes[pos..][0..2], .little)
    else if (sz == .bits64)
        @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(std.mem.readInt(u32, bytes[pos..][0..4], .little))))))
    else
        std.mem.readInt(u32, bytes[pos..][0..4], .little);
    pos += imm_size;

    const base_sz = if (sz == .bits8) Size.bits8 else if (sz == .bits16) Size.bits16 else if (sz == .bits32) Size.bits32 else Size.bits64;

    const group_ops: [8]Op = .{
        .add_reg8_imm8, .or_reg8_imm8,  .adc_reg8_imm8, .sbb_reg8_imm8,
        .and_reg8_imm8, .sub_reg8_imm8, .xor_reg8_imm8, .cmp_reg8_imm8,
    };

    if (is_mem) {
        if (group_op == 1) {
            d.op = if (is_byte_imm)
                switch (base_sz) {
                    .bits8 => .or_mem8_imm8,
                    .bits16 => .or_mem16_imm8,
                    .bits32 => .or_mem32_imm8,
                    .bits64 => .or_mem64_imm8,
                }
            else switch (base_sz) {
                .bits8 => .or_mem8_imm8,
                .bits16 => .or_mem16_imm32,
                .bits32 => .or_mem32_imm32,
                .bits64 => .or_mem64_imm32,
            };
            d.addr = rm.addr;
            d.imm = imm;
            d.size = base_sz;
            d.len = @intCast(pos);
            return d;
        }
        const mem_group_ops: [8]Op = .{
            .add_mem8_imm8, .invalid, .invalid, .invalid,
            .invalid,       .invalid, .invalid, .cmp_mem8_imm8,
        };
        const base = mem_group_ops[group_op];
        if (base == .invalid) {
            d.op = .invalid;
            d.len = @as(u8, @intCast(pos));
            return d;
        }
        const off = @intFromEnum(base_sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base) + off);
        d.addr = rm.addr;
    } else {
        const base = group_ops[group_op];
        const off = @intFromEnum(base_sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base) + off);
        d.dst_reg = @enumFromInt(rm.addr);
    }

    d.imm = imm;
    d.size = base_sz;
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeGroup2Shift(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group_op = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode == 0xC0 or opcode == 0xD0 or opcode == 0xD2;
    const size: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const uses_cl = opcode == 0xD2 or opcode == 0xD3;

    if (group_op != 0 and group_op != 1 and group_op != 4 and group_op != 5 and group_op != 7) {
        d.op = .invalid;
        d.len = @intCast(pos + 1);
        return d;
    }
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, size);
    const count: u64 = if (opcode == 0xC0 or opcode == 0xC1) blk: {
        if (pos >= bytes.len) return .{};
        const immediate = bytes[pos];
        pos += 1;
        break :blk immediate;
    } else if (uses_cl) 0 else 1;

    if (uses_cl) {
        d.op = if (is_mem)
            switch (group_op) {
                0 => .rol_mem_cl,
                1 => .ror_mem_cl,
                4 => .shl_mem_cl,
                5 => .shr_mem_cl,
                else => .sar_mem_cl,
            }
        else switch (group_op) {
            0 => .rol_reg_cl,
            1 => .ror_reg_cl,
            4 => .shl_reg_cl,
            5 => .shr_reg_cl,
            else => .sar_reg_cl,
        };
    } else if (is_mem) {
        d.op = switch (group_op) {
            0 => .rol_mem_imm,
            1 => .ror_mem_imm,
            4 => .shl_mem_imm,
            5 => .shr_mem_imm,
            else => .sar_mem_imm,
        };
    } else {
        d.op = switch (group_op) {
            0 => .rol_reg_imm,
            1 => .ror_reg_imm,
            4 => .shl_reg_imm,
            5 => .shr_reg_imm,
            else => .sar_reg_imm,
        };
    }
    d.size = size;
    d.imm = count;
    if (is_mem) {
        d.addr = rm.addr;
    } else {
        d.dst_reg = @enumFromInt(rm.addr);
    }
    d.len = @intCast(pos);
    return d;
}

pub fn decodeMovMemImm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    if (((modrm >> 3) & 7) != 0) return .{};
    const is_mem = modrm < 0xC0;

    if (opcode == 0xC6) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        d.size = .bits8;
        if (is_mem) {
            d.op = .mov_mem8_imm8;
            d.addr = rm.addr;
        } else {
            d.op = .mov_reg_imm;
            d.dst_reg = @enumFromInt(rm.addr);
        }
        d.imm = bytes[pos];
        pos += 1;
    } else {
        const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        d.size = sz;
        if (sz == .bits16) {
            if (pos + 2 > bytes.len) return .{};
            d.op = .mov_mem16_imm16;
            d.imm = std.mem.readInt(u16, bytes[pos..][0..2], .little);
            pos += 2;
        } else if (sz == .bits64) {
            if (pos + 4 > bytes.len) return .{};
            d.op = .mov_mem64_imm32;
            const imm32 = std.mem.readInt(u32, bytes[pos..][0..4], .little);
            d.imm = @bitCast(@as(i64, @as(i32, @bitCast(imm32))));
            pos += 4;
        } else {
            if (pos + 4 > bytes.len) return .{};
            d.op = .mov_mem32_imm32;
            d.imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
            pos += 4;
        }
        if (is_mem) {
            d.addr = rm.addr;
        } else {
            d.op = .mov_reg_imm;
            d.dst_reg = @enumFromInt(rm.addr);
        }
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeGroup3(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};

    const modrm = bytes[pos];
    const group = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;
    const sz: Size = if (opcode == 0xF6) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (group == 2) {
        const base_op: Op = if (is_mem) .not_mem8 else .not_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) {
            d.addr = rm.addr;
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
        }
        d.len = @intCast(pos);
        return d;
    }

    if (group == 3) {
        const base_op: Op = if (is_mem) .neg_mem8 else .neg_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) {
            d.addr = rm.addr;
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
        }
        d.len = @intCast(pos);
        return d;
    }

    if (group == 4) {
        if (is_mem) {
            d.op = @enumFromInt(@intFromEnum(Op.mul_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
            d.size = sz;
            d.addr = rm.addr;
            d.len = @intCast(pos);
            return d;
        }
        d.op = @enumFromInt(@intFromEnum(Op.mul_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }

    if (group == 5) {
        if (is_mem) {
            d.op = @enumFromInt(@intFromEnum(Op.imul_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
            d.size = sz;
            d.addr = rm.addr;
            d.len = @intCast(pos);
            return d;
        }
        d.op = @enumFromInt(@intFromEnum(Op.imul_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }

    if (group == 6 and sz != .bits8) {
        const base_op: Op = if (is_mem) .div_mem8 else .div_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) d.addr = rm.addr else d.dst_reg = @enumFromInt(rm.addr);
        if (!is_mem) d.src_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }
    if (group == 7 and sz != .bits8) {
        const base_op: Op = if (is_mem) .idiv_mem8 else .idiv_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) d.addr = rm.addr else d.dst_reg = @enumFromInt(rm.addr);
        if (!is_mem) d.src_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }

    if (group != 0 and group != 1) {
        d.op = .invalid;
        d.len = @intCast(pos);
        return d;
    }

    const imm_len: usize = switch (sz) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32, .bits64 => 4,
    };
    if (pos + imm_len > bytes.len) return .{};
    d.imm = switch (sz) {
        .bits8 => bytes[pos],
        .bits16 => std.mem.readInt(u16, bytes[pos..][0..2], .little),
        .bits32 => std.mem.readInt(u32, bytes[pos..][0..4], .little),
        .bits64 => @bitCast(@as(i64, @as(i32, @bitCast(std.mem.readInt(u32, bytes[pos..][0..4], .little))))),
    };
    pos += imm_len;
    const base_op: Op = if (is_mem) .test_mem8_imm8 else .test_reg8_imm8;
    d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
    d.size = sz;
    if (is_mem) {
        d.addr = rm.addr;
    } else {
        d.dst_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.len = @intCast(pos);
    return d;
}

pub fn decodeGroup4_5(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    if (opcode == 0xFE) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        if (group == 0) {
            if (is_mem) {
                d.op = @enumFromInt(@intFromEnum(Op.inc_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.addr = rm.addr;
            } else {
                d.op = @enumFromInt(@intFromEnum(Op.inc_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.dst_reg = @enumFromInt(rm.addr);
            }
        } else if (group == 1) {
            if (is_mem) {
                d.op = @enumFromInt(@intFromEnum(Op.dec_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.addr = rm.addr;
            } else {
                d.op = @enumFromInt(@intFromEnum(Op.dec_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.dst_reg = @enumFromInt(rm.addr);
            }
        } else {
            d.op = .invalid;
        }
        d.len = @as(u8, @intCast(pos));
        return d;
    }

    if (opcode == 0xFF) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        switch (group) {
            0 => {
                if (is_mem) {
                    d.op = @enumFromInt(@intFromEnum(Op.inc_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.addr = rm.addr;
                } else {
                    d.op = @enumFromInt(@intFromEnum(Op.inc_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            1 => {
                if (is_mem) {
                    d.op = @enumFromInt(@intFromEnum(Op.dec_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.addr = rm.addr;
                } else {
                    d.op = @enumFromInt(@intFromEnum(Op.dec_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            2 => {
                if (is_mem) {
                    d.op = .call_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .call_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            3 => {
                if (is_mem) {
                    d.op = .call_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .call_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            4 => {
                if (is_mem) {
                    d.op = .jmp_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .jmp_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                    d.addr = 0;
                }
            },
            5 => {
                if (is_mem) {
                    d.op = .jmp_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .jmp_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                    d.addr = 0;
                }
            },
            6 => {
                if (is_mem) {
                    d.op = .push_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .push_reg;
                    // PUSH reads a register: src_reg is the single canonical field.
                    d.src_reg = @enumFromInt(rm.addr);
                }
            },
            else => {
                d.op = .invalid;
            },
        }
        d.len = @as(u8, @intCast(pos));
        return d;
    }

    d.op = .invalid;
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeTestRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x84) .bits8 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits8 => .test_mem8_reg8,
            .bits16 => .test_mem16_reg16,
            .bits32 => .test_mem32_reg32,
            .bits64 => .test_mem64_reg64,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits8 => .test_reg8_reg8,
            .bits16 => .test_reg16_reg16,
            .bits32 => .test_reg32_reg32,
            .bits64 => .test_reg64_reg64,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeXchgRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, _: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .xchg_mem32_reg32,
            .bits64 => .xchg_mem64_reg64,
            else => .invalid,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits32 => .xchg_reg32_reg32,
            .bits64 => .xchg_reg64_reg64,
            else => .invalid,
        };
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = rm.reg;
        d.is_reg_form = true;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeImulImm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const imm_is_byte = opcode == 0x6B;
    const imm_size: usize = if (imm_is_byte) 1 else if (sz == .bits16) 2 else 4;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (pos + imm_size > bytes.len) return .{};
    const imm: u64 = if (imm_is_byte)
        @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos])))))
    else if (imm_size == 2)
        std.mem.readInt(u16, bytes[pos..][0..2], .little)
    else
        std.mem.readInt(u32, bytes[pos..][0..4], .little);
    pos += imm_size;

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_mem32_imm8,
            .bits64 => .imul_reg64_mem64_imm8,
            else => .imul_reg32_mem32_imm8,
        };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_reg32_imm8,
            .bits64 => .imul_reg64_reg64_imm8,
            else => .imul_reg32_reg32_imm8,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.imm = imm;
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeImulTwoOp(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_mem32,
            .bits64 => .imul_reg64_mem64,
            else => .imul_reg32_mem32,
        };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_reg32,
            .bits64 => .imul_reg64_reg64,
            else => .imul_reg32_reg32,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeCmpxchg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    // 0F B0 is always the byte form.  0F B1 follows the operand-size
    // attribute. Treating B0 as B1/32 corrupts the three bytes adjacent to
    // std::atomic<uint8_t> and makes a successful compare-exchange appear to
    // fail when the neighbouring bytes are nonzero.
    const sz: Size = if (opcode2 == 0xB0)
        .bits8
    else if (rex_w)
        .bits64
    else if (has_66)
        .bits16
    else
        .bits32;
    // The Op identifies the CMPXCHG variant, but the executor intentionally
    // uses DecodedInsn.size for the accumulator, destination, replacement and
    // flags. Leaving this at its default (bits32) makes 0F B0 operate on four
    // bytes even though it was decoded as cmpxchg_mem8_reg8. Xenia's
    // TimerQueue uses lock cmpxchgb for its WaitItem state.
    d.size = sz;
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits8 => .cmpxchg_mem8_reg8,
            .bits16 => .cmpxchg_mem16_reg16,
            .bits32 => .cmpxchg_mem32_reg32,
            .bits64 => .cmpxchg_mem64_reg64,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits8 => .cmpxchg_reg8_reg8,
            .bits16 => .cmpxchg_reg16_reg16,
            .bits32 => .cmpxchg_reg32_reg32,
            .bits64 => .cmpxchg_reg64_reg64,
        };
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = rm.reg;
        d.is_reg_form = true;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeMovzx(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode2 == 0xB6;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .movzx_reg32_mem8 else .movzx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = if (is_byte) .movzx_reg32_mem8 else .movzx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.size = sz;

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeMovsx(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode2 == 0xBE;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .movsx_reg32_mem8 else .movsx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = if (is_byte) .movsx_reg32_mem8 else .movsx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.size = sz;

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeXadd(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    // 0F C0 = byte XADD, 0F C1 = word/dword/qword XADD
    const is_byte = opcode2 == 0xC0;
    const sz: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    d.size = sz;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .xadd_mem8_reg8 else switch (sz) {
            .bits32 => .xadd_mem32_reg32,
            .bits64 => .xadd_mem64_reg64,
            else => .xadd_mem32_reg32,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeSetcc(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits8);

    const setcc_conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };

    if (is_mem) {
        d.op = .setcc_mem8;
        d.addr = rm.addr;
    } else {
        d.op = .setcc_reg8;
        d.dst_reg = @enumFromInt(rm.addr);
    }

    d.cond = setcc_conditions[opcode2 & 0x0F];
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeMovupsMovss(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const to_reg = opcode2 == 0x10;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);

    // Scalar MOVSS/MOVSD need lane-preserving semantics. MOVUPS transfers the
    // full register and is required by Xbyak's feature-mask bookkeeping.
    if (has_f2 or has_f3) {
        d.op = .nop;
    } else if (to_reg) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movups_xmm_mem;
            d.addr = rm.addr;
        } else {
            d.op = .movups_xmm_xmm;
            d.xmm_src = @intCast(rm.addr);
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movups_mem_xmm;
            d.addr = rm.addr;
        } else {
            d.op = .movups_xmm_xmm;
            d.xmm_dst = @intCast(rm.addr);
        }
    }
    d.len = @as(u8, @intCast(pos));
    return d;
}

pub fn decodeMovaps(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const to_reg = opcode2 == 0x28;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);

    if (to_reg) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movaps_xmm_mem;
            d.addr = rm.addr;
        } else {
            d.op = .movaps_xmm_xmm;
            d.xmm_src = @intCast(rm.addr);
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movaps_mem_xmm;
            d.addr = rm.addr;
        } else {
            d.op = .movaps_xmm_xmm;
            d.xmm_dst = @intCast(rm.addr);
        }
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}
