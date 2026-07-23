const std = @import("std");
const builtin = @import("builtin");
const x64_decoder = @import("x64_decoder");

const Regs = x64_decoder.Regs;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const Cond = x64_decoder.Condition;
const Op = x64_decoder.Op;
const DecodedInsn = x64_decoder.DecodedInsn;
const BitScanKind = x64_decoder.BitScanKind;
const bitScan = x64_decoder.bitScan;
const crc32cAccumulator = x64_decoder.crc32cAccumulator;

const RFL_CF = x64_decoder.RFL_CF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;

pub fn decodeInsn(bytes: []const u8) DecodedInsn {
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
                rex = bytes[pos];
                pos += 1;
            },
            else => break,
        }
    }

    if (pos >= bytes.len) return .{};

    const rex_w = (rex & 0x08) != 0;
    const rex_r = (rex & 0x04) != 0;
    const rex_x = (rex & 0x02) != 0;
    const rex_b = (rex & 0x01) != 0;

    const op_size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    _ = op_size;

    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const opcode = bytes[pos];

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
            d.dst_reg = mapReg(reg_num, rex_b);
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

        0xAC, 0xAD => {
            d.op = .lods;
            d.size = if (opcode == 0xAC) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
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
            return decodeMovRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x8D => {
            return decodeLea(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x8F => {
            return decodePopRm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x00...0x03 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .add);
        },
        0x08...0x0B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .@"or");
        },
        0x18...0x1B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .sbb);
        },
        0x20...0x23 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .@"and");
        },
        0x28...0x2B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .sub);
        },
        0x30...0x33 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .xor);
        },
        0x38...0x3B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .cmp);
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
            d.dst_reg = mapReg(opcode - 0xB0, rex_b);
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
            return decodeMovMemImm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xD8, 0xD9, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF => {
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
                x87.imm = rm.addr & 7;
                x87.len = @intCast(modrm_pos);
                if (opcode == 0xD9 and group == 0) x87.op = .fld_st else if (opcode == 0xD9 and group == 1) x87.op = .fxch_st else if (opcode == 0xDB and bytes[pos + 1] == 0xE3) x87.op = .fninit else if (opcode == 0xDD and group == 0) x87.op = .ffree_st else if (opcode == 0xDD and group == 3) x87.op = .fstp_st else if (opcode == 0xDF and bytes[pos + 1] == 0xE0) x87.op = .fnstsw_ax else if (opcode == 0xDF and bytes[pos + 1] >= 0xE8 and bytes[pos + 1] <= 0xEF) x87.op = .fucomip_st else return .{};
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
                    3 => x87.op = .fstp_mem64,
                    else => return .{},
                },
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

        0xE8 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .call_rel32;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.rip_relative = true;
            d.len = 5;
        },

        0xE9 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.rip_relative = true;
            d.len = 5;
        },
        0xEB => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.rip_relative = true;
            d.len = 2;
        },

        0xFE, 0xFF => {
            return decodeGroup4_5(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x98 => {
            if (rex_w) {
                d.op = .cqo;
            } else if (has_66) {
                d.op = .cwd;
            } else {
                d.op = .cdq;
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
            d.op = .nop;
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

        0x40...0x47 => {
            if (opcode == 0x40) {
                d.op = .nop;
            } else {
                d.op = .inc_reg64;
                const reg_num: u8 = opcode - 0x40;
                d.dst_reg = mapReg(reg_num, false);
            }
            d.len = @as(u8, @intCast(pos + 1));
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
            d.op = .nop;
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

// The D8 family targets ST(0); DC and DE target ST(i).  Their reversed
// subtract/divide encodings use the opposite operand order.
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

pub fn decodeVex2(bytes: []const u8, start_pos: usize) DecodedInsn {
    if (start_pos + 3 > bytes.len) return .{};

    const vex = bytes[start_pos + 1];
    const opcode = bytes[start_pos + 2];
    const rex_r = (vex & 0x80) == 0;
    const vector_256 = (vex & 0x04) != 0;
    const prefix = vex & 0x03;

    if (opcode == 0x77 and (vex & 0x78) == 0x78 and !vector_256 and prefix == 0) {
        return .{ .op = .vzeroupper, .len = @intCast(start_pos + 3) };
    }
    if (start_pos + 3 >= bytes.len) return .{};

    if (opcode == 0x6E and (vex & 0x78) == 0x78 and !vector_256 and prefix == 1) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.op = .vmovd_xmm_mem32;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vmovd_xmm_reg32;
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x7E and (vex & 0x78) == 0x78 and !vector_256 and prefix == 2) {
        var decoded = DecodedInsn{ .size = .bits64 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_memory) {
            decoded.op = .vmovq_xmm_mem64;
            decoded.addr = rm.addr;
        } else {
            return .{};
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((opcode == 0x64 or opcode == 0x65 or opcode == 0x66 or opcode == 0x74 or opcode == 0x75 or opcode == 0x76) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x64 => .vpcmpgtb,
            0x65 => .vpcmpgtw,
            0x66 => .vpcmpgtd,
            0x74 => .vpcmpeqb,
            0x75 => .vpcmpeqw,
            0x76 => .vpcmpeqd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x62 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpckldq, .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x6C and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpcklqdq, .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFD: VEX.NDS.LIG.66.0F.WIG 70 /r ib
    if (opcode == 0x70 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpshufd, .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @intCast(rm.addr);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        }
        // Immediate byte for shuffle control
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((opcode == 0x12 or opcode == 0x13 or opcode == 0x16 or opcode == 0x17) and
        !vector_256 and (prefix == 0 or prefix == 1))
    {
        return decodeVexHalfMove(bytes, start_pos + 3, opcode, prefix, vex, rex_r, false, false);
    }

    if ((opcode == 0x16 and prefix == 2) or (opcode == 0x12 and (prefix == 2 or prefix == 3))) {
        return decodeVexDuplicateMove(bytes, start_pos + 3, opcode, prefix, vex, rex_r, false, false, vector_256);
    }

    if (opcode == 0x2A and !vector_256 and (prefix == 2 or prefix == 3)) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_mem else .vcvtsi2sd_xmm_mem;
        } else {
            decoded.src_reg = @enumFromInt(rm.addr);
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_reg else .vcvtsi2sd_xmm_reg;
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x5A and !vector_256 and prefix == 2) {
        var decoded = DecodedInsn{ .op = .vcvtss2sd, .size = .bits32 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((opcode == 0x2C or opcode == 0x2D) and !vector_256 and (prefix == 2 or prefix == 3) and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.dst_reg = rm.reg;
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x2C)
            if (prefix == 2) .vcvttss2si else .vcvttsd2si
        else if (prefix == 2)
            .vcvtss2si
        else
            .vcvtsd2si;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x58 or opcode == 0x59 or opcode == 0x5C or opcode == 0x5E) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var arithmetic_pos = start_pos + 3;
        const is_mem = bytes[arithmetic_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &arithmetic_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x58 => switch (prefix) {
                0 => .vaddps,
                1 => .vaddpd,
                2 => .vaddss,
                3 => .vaddsd,
                else => unreachable,
            },
            0x59 => switch (prefix) {
                0 => .vmulps,
                1 => .vmulpd,
                2 => .vmulss,
                3 => .vmulsd,
                else => unreachable,
            },
            0x5C => switch (prefix) {
                0 => .vsubps,
                1 => .vsubpd,
                2 => .vsubss,
                3 => .vsubsd,
                else => unreachable,
            },
            0x5E => switch (prefix) {
                0 => .vdivps,
                1 => .vdivpd,
                2 => .vdivss,
                3 => .vdivsd,
                else => unreachable,
            },
            else => unreachable,
        };
        decoded.len = @intCast(arithmetic_pos);
        return decoded;
    }

    if (opcode >= 0x54 and opcode <= 0x57 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var bitwise_pos = start_pos + 3;
        const is_mem = bytes[bitwise_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &bitwise_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x54 => if (prefix == 0) .vandps else .vandpd,
            0x55 => if (prefix == 0) .vandnps else .vandnpd,
            0x56 => if (prefix == 0) .vorps else .vorpd,
            0x57 => if (prefix == 0) .vxorps else .vxorpd,
            else => unreachable,
        };
        decoded.len = @intCast(bitwise_pos);
        return decoded;
    }

    if ((opcode == 0xDB or opcode == 0xDF or opcode == 0xEB or opcode == 0xEF) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pp_pos = start_pos + 3;
        const is_mem = bytes[pp_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pp_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xDB => .vpand,
            0xDF => .vpandn,
            0xEB => .vpor,
            0xEF => .vpxor,
            else => unreachable,
        };
        decoded.len = @intCast(pp_pos);
        return decoded;
    }

    if ((opcode == 0x2E or opcode == 0x2F) and (vex & 0x78) == 0x78 and !vector_256 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{};
        var compare_pos = start_pos + 3;
        const is_mem = bytes[compare_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &compare_pos, rex_r, false, false, .bits64);
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = if (prefix == 0) .vucomiss else .vucomisd;
        decoded.len = @intCast(compare_pos);
        return decoded;
    }

    if (opcode == 0xD7 and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.dst_reg = rm.reg;
        decoded.xmm_src = @intCast(rm.addr);
        decoded.op = if (vector_256) .vpmovmskb_ymm else .vpmovmskb;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMULUDQ: VEX.NDS.128.66.0F.WIG F4 /r
    if (opcode == 0xF4 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = .vpmuludq;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // Variable-count packed logical shifts. The count is the low 64 bits of
    // the third XMM/m128 operand and applies to every element.
    if ((opcode == 0xD1 or opcode == 0xD2 or opcode == 0xD3 or
        opcode == 0xF1 or opcode == 0xF2 or opcode == 0xF3) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xD1 => .vpsrlw,
            0xD2 => .vpsrld,
            0xD3 => .vpsrlq,
            0xF1 => .vpsllw,
            0xF2 => .vpslld,
            0xF3 => .vpsllq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPUNPCKHBW/HDQ/HWD: VEX.NDS.128.66.0F.WIG 68/69/6A /r
    if ((opcode == 0x68 or opcode == 0x69 or opcode == 0x6A) and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x68 => .vpunpckhbw,
            0x69 => .vpunpckhwd,
            0x6A => .vpunpckhdq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPUNPCKLBW/LWD/LQD: VEX.NDS.128.66.0F.WIG 60/61/62 /r
    if ((opcode == 0x60 or opcode == 0x61) and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x60 => .vpunpcklbw,
            0x61 => .vpunpcklwd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFB: VEX.NDS.128.66.0F.WIG 00 /r ib
    if (opcode == 0x00 and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        // Immediate byte for shuffle control
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = .vpshufb;
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSHUFD: VEX.NDS.LIG.66.0F.WIG 70 /r ib (already handled above, keeping for reference)

    // Immediate-count packed shifts: /2 and /3 shift right, /6 and /7
    // shift left. VEX.vvvv is the destination and ModRM.r/m is the source.
    if ((opcode == 0x71 or opcode == 0x72 or opcode == 0x73) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        const group = (@intFromEnum(rm.reg) & 0x07);
        if (group != 2 and group != 3 and group != 6 and group != 7) return .{};
        decoded.xmm_dst = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
        decoded.op = switch (opcode) {
            0x71 => if (group == 2) .vpsrlw else .vpsllw,
            0x72 => if (group == 2) .vpsrld else .vpslld,
            0x73 => switch (group) {
                2 => .vpsrlq,
                3 => .vpsrldq,
                6 => .vpsllq,
                7 => .vpslldq,
                else => unreachable,
            },
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPSUBB/PSUBD/PSUBQ/PSUBW: VEX.NDS.128.66.0F.WIG F8/FA/FB/F9 /r
    if ((opcode == 0xF8 or opcode == 0xFA or opcode == 0xFB or opcode == 0xF9) and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xF8 => .vpsubb,
            0xFA => .vpsubd,
            0xFB => .vpsubq,
            0xF9 => .vpsubw,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPADDB/PADDW/PADDD/PADDQ: VEX.NDS.128/256.66.0F.WIG FC/FD/FE/D4 /r
    if ((opcode == 0xFC or opcode == 0xFD or opcode == 0xFE or opcode == 0xD4) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xFC => .vpaddb,
            0xFD => .vpaddw,
            0xFE => .vpaddd,
            0xD4 => .vpaddq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMULLW: VEX.NDS.128.66.0F.WIG D5 /r
    if (opcode == 0xD5 and prefix == 1 and (vex & 0x78) == 0x78) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = .vpmullw;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if ((vex & 0x78) != 0x78) return .{};

    var d = DecodedInsn{ .vector_256 = vector_256 };
    var pos = start_pos + 3;
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, false, false, .bits64);

    const is_load = switch (opcode) {
        0x6F, 0x10, 0x28 => true,
        0x7F, 0x11, 0x29 => false,
        else => return .{},
    };

    const family: enum { dqu, dqa, ups, aps, upd, apd, ss, sd } = switch (opcode) {
        0x6F, 0x7F => switch (prefix) {
            1 => .dqa,
            2 => .dqu,
            else => return .{},
        },
        0x10, 0x11 => switch (prefix) {
            0 => .ups,
            1 => .upd,
            2 => .ss,
            3 => .sd,
            else => unreachable,
        },
        0x28, 0x29 => switch (prefix) {
            0 => .aps,
            1 => .apd,
            else => return .{},
        },
        else => unreachable,
    };

    if ((family == .ss or family == .sd) and !is_mem) return .{};
    if ((family == .ss or family == .sd) and vector_256) return .{};

    if (is_load) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_mem,
                .dqa => .vmovdqa_ymm_mem,
                .ups => .vmovups_ymm_mem,
                .aps => .vmovaps_ymm_mem,
                .upd => .vmovupd_ymm_mem,
                .apd => .vmovapd_ymm_mem,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_mem,
                .dqa => .vmovdqa_xmm_mem,
                .ups => .vmovups_xmm_mem,
                .aps => .vmovaps_xmm_mem,
                .upd => .vmovupd_xmm_mem,
                .apd => .vmovapd_xmm_mem,
                .ss => .vmovss_xmm_mem,
                .sd => .vmovsd_xmm_mem,
            };
        } else {
            d.xmm_src = @intCast(rm.addr);
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_ymm,
                .dqa => .vmovdqa_ymm_ymm,
                .ups => .vmovups_ymm_ymm,
                .aps => .vmovaps_ymm_ymm,
                .upd => .vmovupd_ymm_ymm,
                .apd => .vmovapd_ymm_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_xmm,
                .dqa => .vmovdqa_xmm_xmm,
                .ups => .vmovups_xmm_xmm,
                .aps => .vmovaps_xmm_xmm,
                .upd => .vmovupd_xmm_xmm,
                .apd => .vmovapd_xmm_xmm,
                .ss, .sd => unreachable,
            };
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_mem_ymm,
                .dqa => .vmovdqa_mem_ymm,
                .ups => .vmovups_mem_ymm,
                .aps => .vmovaps_mem_ymm,
                .upd => .vmovupd_mem_ymm,
                .apd => .vmovapd_mem_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_mem_xmm,
                .dqa => .vmovdqa_mem_xmm,
                .ups => .vmovups_mem_xmm,
                .aps => .vmovaps_mem_xmm,
                .upd => .vmovupd_mem_xmm,
                .apd => .vmovapd_mem_xmm,
                .ss => .vmovss_mem_xmm,
                .sd => .vmovsd_mem_xmm,
            };
        } else {
            d.xmm_dst = @intCast(rm.addr);
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_ymm,
                .dqa => .vmovdqa_ymm_ymm,
                .ups => .vmovups_ymm_ymm,
                .aps => .vmovaps_ymm_ymm,
                .upd => .vmovupd_ymm_ymm,
                .apd => .vmovapd_ymm_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_xmm,
                .dqa => .vmovdqa_xmm_xmm,
                .ups => .vmovups_xmm_xmm,
                .aps => .vmovaps_xmm_xmm,
                .upd => .vmovupd_xmm_xmm,
                .apd => .vmovapd_xmm_xmm,
                .ss, .sd => unreachable,
            };
        }
    }

    d.len = @intCast(pos);
    return d;
}

pub const VexArithmetic = enum { add, multiply, subtract, divide };
pub const VexBitwise = enum { @"and", and_not, @"or", xor };
pub fn shuffleBytes(source: [16]u8, mask: [16]u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    for (mask, 0..) |selector, index| {
        if (selector & 0x80 == 0) result[index] = source[selector & 0x0F];
    }
    return result;
}

pub fn compareEqualDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const left = std.mem.readInt(u32, lhs[offset..][0..4], .little);
        const right = std.mem.readInt(u32, rhs[offset..][0..4], .little);
        std.mem.writeInt(u32, result[offset..][0..4], if (left == right) std.math.maxInt(u32) else 0, .little);
    }
    return result;
}

pub fn unpackLowDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    @memcpy(result[0..4], lhs[0..4]);
    @memcpy(result[4..8], rhs[0..4]);
    @memcpy(result[8..12], lhs[4..8]);
    @memcpy(result[12..16], rhs[4..8]);
    return result;
}

pub fn permutePackedDoubles(source: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    const low_source: usize = if (control & 0x01 == 0) 0 else 8;
    const high_source: usize = if (control & 0x02 == 0) 0 else 8;
    @memcpy(result[0..8], source[low_source..][0..8]);
    @memcpy(result[8..16], source[high_source..][0..8]);
    return result;
}

pub fn bitwiseAndAllZero(a: [16]u8, b: [16]u8) bool {
    for (a, b) |ai, bi| if (ai & bi != 0) return false;
    return true;
}

pub fn bitwiseAndNotAllZero(a: [16]u8, b: [16]u8) bool {
    for (a, b) |ai, bi| if (~ai & bi != 0) return false;
    return true;
}

pub fn applyVexCompare(lhs: [16]u8, rhs: [16]u8, op: Op) [16]u8 {
    var result: [16]u8 = undefined;
    switch (op) {
        .vpcmpeqb => {
            for (&result, lhs, rhs) |*dst, l, r| dst.* = if (l == r) 0xFF else 0x00;
        },
        .vpcmpgtb => {
            for (&result, lhs, rhs) |*dst, l, r| dst.* = if (@as(i8, @bitCast(l)) > @as(i8, @bitCast(r))) 0xFF else 0x00;
        },
        .vpcmpeqw => {
            for (0..8) |lane| {
                const off = lane * 2;
                const l = std.mem.readInt(u16, lhs[off..][0..2], .little);
                const r = std.mem.readInt(u16, rhs[off..][0..2], .little);
                const mask: u16 = if (l == r) 0xFFFF else 0x0000;
                std.mem.writeInt(u16, result[off..][0..2], mask, .little);
            }
        },
        .vpcmpgtw => {
            for (0..8) |lane| {
                const off = lane * 2;
                const l: i16 = @bitCast(std.mem.readInt(u16, lhs[off..][0..2], .little));
                const r: i16 = @bitCast(std.mem.readInt(u16, rhs[off..][0..2], .little));
                const mask: u16 = if (l > r) 0xFFFF else 0x0000;
                std.mem.writeInt(u16, result[off..][0..2], mask, .little);
            }
        },
        .vpcmpeqd => {
            for (0..4) |lane| {
                const off = lane * 4;
                const l = std.mem.readInt(u32, lhs[off..][0..4], .little);
                const r = std.mem.readInt(u32, rhs[off..][0..4], .little);
                const mask: u32 = if (l == r) std.math.maxInt(u32) else 0;
                std.mem.writeInt(u32, result[off..][0..4], mask, .little);
            }
        },
        .vpcmpeqq => {
            for (0..2) |lane| {
                const off = lane * 8;
                const l = std.mem.readInt(u64, lhs[off..][0..8], .little);
                const r = std.mem.readInt(u64, rhs[off..][0..8], .little);
                const mask: u64 = if (l == r) std.math.maxInt(u64) else 0;
                std.mem.writeInt(u64, result[off..][0..8], mask, .little);
            }
        },
        .vpcmpgtd => {
            for (0..4) |lane| {
                const off = lane * 4;
                const l: i32 = @bitCast(std.mem.readInt(u32, lhs[off..][0..4], .little));
                const r: i32 = @bitCast(std.mem.readInt(u32, rhs[off..][0..4], .little));
                const mask: u32 = if (l > r) std.math.maxInt(u32) else 0;
                std.mem.writeInt(u32, result[off..][0..4], mask, .little);
            }
        },
        .vpcmpgtq => {
            for (0..2) |lane| {
                const off = lane * 8;
                const l: i64 = @bitCast(std.mem.readInt(u64, lhs[off..][0..8], .little));
                const r: i64 = @bitCast(std.mem.readInt(u64, rhs[off..][0..8], .little));
                const mask: u64 = if (l > r) std.math.maxInt(u64) else 0;
                std.mem.writeInt(u64, result[off..][0..8], mask, .little);
            }
        },
        else => unreachable,
    }
    return result;
}

pub fn vexArithmeticForOp(op: Op) VexArithmetic {
    return switch (op) {
        .vaddss, .vaddsd, .vaddps, .vaddpd => .add,
        .vmulss, .vmulsd, .vmulps, .vmulpd => .multiply,
        .vsubss, .vsubsd, .vsubps, .vsubpd => .subtract,
        .vdivss, .vdivsd, .vdivps, .vdivpd => .divide,
        else => unreachable,
    };
}

pub fn applyVexArithmetic(comptime Float: type, lhs: Float, rhs: Float, operation: VexArithmetic) Float {
    return switch (operation) {
        .add => lhs + rhs,
        .multiply => lhs * rhs,
        .subtract => lhs - rhs,
        .divide => lhs / rhs,
    };
}

pub fn vexBitwiseForOp(op: Op) VexBitwise {
    return switch (op) {
        .vandps, .vandpd, .vpand => .@"and",
        .vandnps, .vandnpd, .vpandn => .and_not,
        .vorps, .vorpd, .vpor => .@"or",
        .vxorps, .vxorpd, .vpxor => .xor,
        else => unreachable,
    };
}

pub fn applyVexBitwise(lhs: [16]u8, rhs: [16]u8, operation: VexBitwise) [16]u8 {
    var result: [16]u8 = undefined;
    for (&result, lhs, rhs) |*destination, left, right| {
        destination.* = switch (operation) {
            .@"and" => left & right,
            .and_not => ~left & right,
            .@"or" => left | right,
            .xor => left ^ right,
        };
    }
    return result;
}

pub fn applyVexPackedF32(lhs: [16]u8, rhs: [16]u8, operation: VexArithmetic) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const lhs_value: f32 = @bitCast(std.mem.readInt(u32, lhs[offset..][0..4], .little));
        const rhs_value: f32 = @bitCast(std.mem.readInt(u32, rhs[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(applyVexArithmetic(f32, lhs_value, rhs_value, operation)), .little);
    }
    return result;
}

pub fn applyVexPackedF64(lhs: [16]u8, rhs: [16]u8, operation: VexArithmetic) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const lhs_value: f64 = @bitCast(std.mem.readInt(u64, lhs[offset..][0..8], .little));
        const rhs_value: f64 = @bitCast(std.mem.readInt(u64, rhs[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(applyVexArithmetic(f64, lhs_value, rhs_value, operation)), .little);
    }
    return result;
}

pub fn roundVexFloat(comptime Float: type, value: Float, immediate: u8) Float {
    if (std.math.isNan(value) or std.math.isInf(value)) return value;
    const mode: u2 = if (immediate & 0x04 != 0) 0 else @truncate(immediate);
    return switch (mode) {
        0 => roundNearestEven(Float, value),
        1 => @floor(value),
        2 => @ceil(value),
        3 => @trunc(value),
    };
}

pub fn roundNearestEven(comptime Float: type, value: Float) Float {
    const lower = @floor(value);
    const fraction = value - lower;
    const half: Float = 0.5;
    if (fraction < half) return lower;
    if (fraction > half) return lower + 1.0;
    return if (@mod(lower, 2.0) == 0.0) lower else lower + 1.0;
}

pub fn roundVexPackedF32(source: [16]u8, immediate: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const value: f32 = @bitCast(std.mem.readInt(u32, source[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(roundVexFloat(f32, value, immediate)), .little);
    }
    return result;
}

pub fn roundVexPackedF64(source: [16]u8, immediate: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const value: f64 = @bitCast(std.mem.readInt(u64, source[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(roundVexFloat(f64, value, immediate)), .little);
    }
    return result;
}

pub fn convertVexFloatToSigned(comptime Float: type, value: Float, size: Size, truncate: bool) u64 {
    const rounded = if (truncate) @trunc(value) else roundNearestEven(Float, value);
    if (std.math.isNan(rounded)) return integerIndefinite(size);

    return switch (size) {
        .bits32 => blk: {
            const minimum: Float = -2147483648.0;
            const maximum_exclusive: Float = 2147483648.0;
            if (rounded < minimum or rounded >= maximum_exclusive) break :blk integerIndefinite(size);
            const signed: i32 = @intFromFloat(rounded);
            break :blk @as(u32, @bitCast(signed));
        },
        .bits64 => blk: {
            const minimum: Float = -9223372036854775808.0;
            const maximum_exclusive: Float = 9223372036854775808.0;
            if (rounded < minimum or rounded >= maximum_exclusive) break :blk integerIndefinite(size);
            const signed: i64 = @intFromFloat(rounded);
            break :blk @bitCast(signed);
        },
        else => unreachable,
    };
}

pub fn integerIndefinite(size: Size) u64 {
    return if (size == .bits64) @as(u64, 1) << 63 else @as(u64, 1) << 31;
}

pub fn decodeVex3(bytes: []const u8, start_pos: usize) DecodedInsn {
    if (start_pos + 5 > bytes.len) return .{};
    const vex_map = bytes[start_pos + 1];
    const vex_control = bytes[start_pos + 2];
    const opcode = bytes[start_pos + 3];
    const opcode_map = vex_map & 0x1F;
    const rex_r = (vex_map & 0x80) == 0;
    const rex_x = (vex_map & 0x40) == 0;
    const rex_b = (vex_map & 0x20) == 0;
    const rex_w = (vex_control & 0x80) != 0;
    const vector_256 = (vex_control & 0x04) != 0;
    const prefix = vex_control & 0x03;

    if (opcode_map == 1 and
        (opcode == 0x12 or opcode == 0x13 or opcode == 0x16 or opcode == 0x17) and
        !vector_256 and (prefix == 0 or prefix == 1))
    {
        return decodeVexHalfMove(bytes, start_pos + 4, opcode, prefix, vex_control, rex_r, rex_x, rex_b);
    }

    if (opcode_map == 1 and
        ((opcode == 0x16 and prefix == 2) or (opcode == 0x12 and (prefix == 2 or prefix == 3))))
    {
        return decodeVexDuplicateMove(bytes, start_pos + 4, opcode, prefix, vex_control, rex_r, rex_x, rex_b, vector_256);
    }

    if (opcode_map == 1 and opcode == 0x76 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpcmpeqd;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x62 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpckldq, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x6C and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpunpcklqdq, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPMULUDQ: VEX.NDS.128/256.66.0F.WIG F4 /r
    if (opcode_map == 1 and opcode == 0xF4 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpmuludq, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and
        (opcode == 0xD1 or opcode == 0xD2 or opcode == 0xD3 or
            opcode == 0xF1 or opcode == 0xF2 or opcode == 0xF3) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xD1 => .vpsrlw,
            0xD2 => .vpsrld,
            0xD3 => .vpsrlq,
            0xF1 => .vpsllw,
            0xF2 => .vpslld,
            0xF3 => .vpsllq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and
        (opcode == 0xF8 or opcode == 0xF9 or opcode == 0xFA or opcode == 0xFB or
            opcode == 0xFC or opcode == 0xFD or opcode == 0xFE or opcode == 0xD4 or opcode == 0xD5) and prefix == 1)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xF8 => .vpsubb,
            0xF9 => .vpsubw,
            0xFA => .vpsubd,
            0xFB => .vpsubq,
            0xFC => .vpaddb,
            0xFD => .vpaddw,
            0xFE => .vpaddd,
            0xD4 => .vpaddq,
            0xD5 => .vpmullw,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x0E and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpblendw, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        decoded.uses_imm = true;
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x05 and prefix == 1) {
        var decoded = DecodedInsn{ .op = .vpermilpd, .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x6E or opcode == 0x7E)) {
        if (!rex_w or vector_256 or prefix != 1 or (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .size = .bits64 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (opcode == 0x6E) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (is_mem) {
                decoded.op = .vmovq_xmm_mem64;
                decoded.addr = rm.addr;
            } else {
                decoded.op = .vmovq_xmm_reg64;
                decoded.src_reg = @enumFromInt(rm.addr);
            }
        } else {
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (is_mem) {
                decoded.op = .vmovq_mem64_xmm;
                decoded.addr = rm.addr;
            } else {
                decoded.op = .vmovq_reg64_xmm;
                decoded.dst_reg = @enumFromInt(rm.addr);
            }
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x2A) {
        if (vector_256 or (prefix != 2 and prefix != 3)) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @as(u8, @truncate((~vex_control >> 3) & 0x0F));
        if (is_mem) {
            decoded.addr = rm.addr;
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_mem else .vcvtsi2sd_xmm_mem;
        } else {
            decoded.src_reg = @enumFromInt(rm.addr);
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_reg else .vcvtsi2sd_xmm_reg;
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x5A) {
        if (rex_w or vector_256 or prefix != 2) return .{};
        var decoded = DecodedInsn{ .op = .vcvtss2sd, .size = .bits32 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x2C or opcode == 0x2D)) {
        if (vector_256 or (prefix != 2 and prefix != 3) or (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.dst_reg = rm.reg;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x2C)
            if (prefix == 2) .vcvttss2si else .vcvttsd2si
        else if (prefix == 2)
            .vcvtss2si
        else
            .vcvtsd2si;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and opcode == 0x00 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpshufb;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and opcode == 0x17 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vptest;
        decoded.xmm_src = @intFromEnum(rm.reg);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and (opcode == 0x29 or opcode == 0x37) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x29 => .vpcmpeqq,
            0x37 => .vpcmpgtq,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode >= 0x08 and opcode <= 0x0B and prefix == 1) {
        const is_scalar = opcode == 0x0A or opcode == 0x0B;
        if (is_scalar and vector_256) return .{};
        if (!is_scalar and (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (opcode) {
            0x08 => .vroundps,
            0x09 => .vroundpd,
            0x0A => .vroundss,
            0x0B => .vroundsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    // VPINSRD/VPINSRQ/VPINSRW: VEX.NDS.LIG.66.0F38.WIG 22/23/2A /r ib
    if (opcode_map == 3 and (opcode == 0x22 or opcode == 0x23 or opcode == 0x2A) and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_memory;
        if (is_memory) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        // Immediate byte for index
        if (pos >= bytes.len) return .{};
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (opcode) {
            0x22 => .vpinsrd,
            0x23 => .vpinsrq,
            0x2A => .vpinsrw,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x20 and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .size = .bits8 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.op = .vpinsrb_xmm_xmm_mem8;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vpinsrb_xmm_xmm_reg32;
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x64 or opcode == 0x65 or opcode == 0x66 or opcode == 0x74 or opcode == 0x75 or opcode == 0x76) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x64 => .vpcmpgtb,
            0x65 => .vpcmpgtw,
            0x66 => .vpcmpgtd,
            0x74 => .vpcmpeqb,
            0x75 => .vpcmpeqw,
            0x76 => .vpcmpeqd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0xDB or opcode == 0xDF or opcode == 0xEB or opcode == 0xEF) and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pp_pos = start_pos + 4;
        const is_mem = bytes[pp_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pp_pos, rex_r, rex_x, rex_b, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0xDB => .vpand,
            0xDF => .vpandn,
            0xEB => .vpor,
            0xEF => .vpxor,
            else => unreachable,
        };
        decoded.len = @intCast(pp_pos);
        return decoded;
    }

    // Three-byte VEX is required when X/B extension bits address r8-r15 even
    // for ordinary 0F-map moves. Xbyak emits this form for VMOVDQU [r9],xmm0.
    if (opcode_map == 1 and (opcode == 0x6F or opcode == 0x7F) and
        (prefix == 1 or prefix == 2) and (vex_control & 0x78) == 0x78)
    {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_memory = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        const unaligned = prefix == 2;
        if (opcode == 0x6F) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (is_memory) {
                decoded.addr = rm.addr;
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_ymm_mem else .vmovdqa_ymm_mem
                else if (unaligned)
                    .vmovdqu_xmm_mem
                else
                    .vmovdqa_xmm_mem;
            } else {
                decoded.xmm_src = @intCast(rm.addr);
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_ymm_ymm else .vmovdqa_ymm_ymm
                else if (unaligned)
                    .vmovdqu_xmm_xmm
                else
                    .vmovdqa_xmm_xmm;
            }
        } else {
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (is_memory) {
                decoded.addr = rm.addr;
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_mem_ymm else .vmovdqa_mem_ymm
                else if (unaligned)
                    .vmovdqu_mem_xmm
                else
                    .vmovdqa_mem_xmm;
            } else {
                decoded.xmm_dst = @intCast(rm.addr);
                decoded.op = if (vector_256)
                    if (unaligned) .vmovdqu_ymm_ymm else .vmovdqa_ymm_ymm
                else if (unaligned)
                    .vmovdqu_xmm_xmm
                else
                    .vmovdqa_xmm_xmm;
            }
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    return .{};
}

pub fn decodeVexHalfMove(
    bytes: []const u8,
    modrm_pos: usize,
    opcode: u8,
    prefix: u8,
    vex_control: u8,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
) DecodedInsn {
    if (modrm_pos >= bytes.len or bytes[modrm_pos] >= 0xC0) return .{};

    const is_load = opcode == 0x12 or opcode == 0x16;
    if (!is_load and (vex_control & 0x78) != 0x78) return .{};

    var decoded = DecodedInsn{};
    var pos = modrm_pos;
    const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
    decoded.addr = rm.addr;
    if (is_load) {
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
    } else {
        decoded.xmm_src = @intFromEnum(rm.reg);
    }
    decoded.op = switch (opcode) {
        0x12 => if (prefix == 0) .vmovlps_xmm_xmm_mem64 else .vmovlpd_xmm_xmm_mem64,
        0x13 => if (prefix == 0) .vmovlps_mem64_xmm else .vmovlpd_mem64_xmm,
        0x16 => if (prefix == 0) .vmovhps_xmm_xmm_mem64 else .vmovhpd_xmm_xmm_mem64,
        0x17 => if (prefix == 0) .vmovhps_mem64_xmm else .vmovhpd_mem64_xmm,
        else => unreachable,
    };
    decoded.len = @intCast(pos);
    return decoded;
}

pub fn decodeVexDuplicateMove(
    bytes: []const u8,
    modrm_pos: usize,
    opcode: u8,
    prefix: u8,
    vex_control: u8,
    rex_r: bool,
    rex_x: bool,
    rex_b: bool,
    vector_256: bool,
) DecodedInsn {
    if (modrm_pos >= bytes.len or (vex_control & 0x78) != 0x78) return .{};

    var decoded = DecodedInsn{ .vector_256 = vector_256 };
    var pos = modrm_pos;
    const is_mem = bytes[pos] < 0xC0;
    const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
    decoded.xmm_dst = @intFromEnum(rm.reg);
    decoded.is_reg_form = !is_mem;
    if (is_mem) {
        decoded.addr = rm.addr;
    } else {
        decoded.xmm_src = @intCast(rm.addr);
    }
    decoded.op = if (opcode == 0x16) .vmovshdup else if (prefix == 2) .vmovsldup else .vmovddup;
    decoded.len = @intCast(pos);
    return decoded;
}

pub fn duplicateVectorElements(op: Op, source: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    switch (op) {
        .vmovshdup => {
            result[0..4].* = source[4..8].*;
            result[4..8].* = source[4..8].*;
            result[8..12].* = source[12..16].*;
            result[12..16].* = source[12..16].*;
        },
        .vmovsldup => {
            result[0..4].* = source[0..4].*;
            result[4..8].* = source[0..4].*;
            result[8..12].* = source[8..12].*;
            result[12..16].* = source[8..12].*;
        },
        .vmovddup => {
            result[0..8].* = source[0..8].*;
            result[8..16].* = source[0..8].*;
        },
        else => unreachable,
    }
    return result;
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

    if (opcode2 == 0xB3) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.src_reg = rm.reg;
        if (d.is_reg_form) {
            d.dst_reg = @enumFromInt(rm.addr);
            d.op = .btr_reg_reg;
        } else {
            d.addr = rm.addr;
            d.op = .btr_mem_reg;
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

    if (opcode2 == 0xC1) {
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

pub fn hasModRM(byte: u8) bool {
    _ = byte;
    return true;
}

pub fn mapReg(reg_num: u8, rex_b: bool) RegId {
    const r = reg_num + @as(u8, if (rex_b) 8 else 0);
    return @enumFromInt(r);
}

pub fn mapJccCond8(opcode: u8) Cond {
    const conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };
    return conditions[opcode & 0x0F];
}

pub fn mapJccCond32(opcode: u8) Cond {
    const conditions: [12]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np,
    };
    const idx = opcode & 0x0F;
    if (idx < 12) return conditions[idx];
    if (idx == 12) return .l;
    if (idx == 13) return .ge;
    if (idx == 14) return .le;
    return .g;
}

pub fn readModRM(d: *DecodedInsn, bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, _: Size) struct { reg: RegId, addr: u64 } {
    const modrm = bytes[pos.*];
    pos.* += 1;
    const mod = (modrm >> 6) & 3;
    const reg_num = (modrm >> 3) & 7;
    const rm_num = modrm & 7;

    const reg = mapReg(reg_num, rex_r);

    d.sib_has_base = false;
    d.sib_has_index = false;
    d.rip_relative = false;
    d.is_reg_form = false;

    if (mod == 3) {
        d.is_reg_form = true;
        return .{ .reg = reg, .addr = @as(u64, @intFromEnum(mapReg(rm_num, rex_b))) };
    }

    var disp: u64 = 0;

    if (rm_num == 4) {
        const sib = bytes[pos.*];
        pos.* += 1;
        const scale = (sib >> 6) & 3;
        const index_num = (sib >> 3) & 7;
        const base_num = sib & 7;

        if (index_num != 4) {
            d.sib_has_index = true;
            d.sib_index_reg = mapReg(index_num, rex_x);
            d.sib_scale = @as(u2, @intCast(scale));
        }

        if (mod == 0 and base_num == 5) {
            d.rip_relative = true;
        } else {
            d.sib_has_base = true;
            d.sib_base_reg = mapReg(base_num, rex_b);
        }

        if (mod == 0 and base_num == 5) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        } else if (mod == 1) {
            disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
            pos.* += 1;
        } else if (mod == 2) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        }
        return .{ .reg = reg, .addr = disp };
    }

    if (mod == 0 and rm_num == 5) {
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        d.rip_relative = true;
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else if (mod == 1) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
        pos.* += 1;
    } else if (mod == 2) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
    }

    return .{ .reg = reg, .addr = disp };
}

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

    if (group == 4 and !is_mem) {
        d.op = @enumFromInt(@intFromEnum(Op.mul_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        d.dst_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }

    if (group == 6 and sz != .bits8) {
        const base_op: Op = if (is_mem) .div_mem8 else .div_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) d.addr = rm.addr else d.dst_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }
    if (group == 7 and sz != .bits8) {
        const base_op: Op = if (is_mem) .idiv_mem8 else .idiv_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) d.addr = rm.addr else d.dst_reg = @enumFromInt(rm.addr);
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
                    d.dst_reg = @enumFromInt(rm.addr);
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
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    d.size = sz;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
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
