const std = @import("std");
const scaffold = @import("decode_scaffold.zig");
const reg_map = @import("register_mapping.zig");
const isa_registry = @import("isa_registry");
const highway = @import("isa_highway");

const ModRm = scaffold.ModRm;
const Sib = scaffold.Sib;
const Register = reg_map.Register;
const ByteRegister = reg_map.ByteRegister;
pub const SegmentOverride = scaffold.SegmentOverride;

pub const max_instruction_len = 15;

pub const DecodeStatus = enum {
    executable,
    recognized_unimplemented,
    invalid,
};

pub const ControlKind = enum {
    none,
    near_jump,
    conditional_jump,
    near_call,
    near_return,
};

pub const RawOp = enum {
    invalid,
    recognized_unimplemented,
    nop,
    ret,
    jmp_rel,
    jcc_rel,
    call_rel,
    push_reg,
    pop_reg,
    pusha,
    popa,
    leave,
    sign_extend_accumulator,
    push_imm,
    push_flags,
    pop_flags,
    sahf,
    cpuid,
    mov_byte_reg_imm,
    mov_reg_imm,
    mov_rm,
    mov_immediate_rm,
    mov_extend,
    xchg_eax_reg,
    lea,
    binary,
    binary_immediate,
    group3_neg,
    group3_not,
    group3_div,
    group3_idiv,
    imul_rm,
    imul_immediate,
    inc_reg,
    dec_reg,
    set_direction_flag,
    clear_direction_flag,
    setcc,
    group4_inc,
    group4_dec,
    group5_inc,
    group5_dec,
    group2_shift,
    group5_call,
    group5_jmp,
    group5_push,
    string_movs,
    string_stos,
    string_scas,
    x87,
};

pub const EffectiveAddress = struct {
    absolute: ?u32 = null,
    base: ?Register = null,
    index: ?Register = null,
    scale: u8 = 1,
    displacement: i32 = 0,

    pub fn resolve(self: EffectiveAddress, regs: *const reg_map.RegisterFile) ?u32 {
        var value: i64 = 0;
        if (self.absolute) |absolute| value += @as(i64, @intCast(absolute));
        if (self.base) |base| value += @as(i64, @intCast(regs.get(base)));
        if (self.index) |index| value += @as(i64, @intCast(regs.get(index))) * @as(i64, self.scale);
        value += self.displacement;
        if (value < 0 or value > std.math.maxInt(u32)) return null;
        return @intCast(value);
    }

    /// LEA computes a 32-bit effective offset, so arithmetic wraps modulo
    /// 2^32 instead of reporting an address-overflow fault.
    pub fn resolveWrapping(self: EffectiveAddress, regs: *const reg_map.RegisterFile) u32 {
        var value: u32 = self.absolute orelse 0;
        if (self.base) |base| value +%= regs.get(base);
        if (self.index) |index| value +%= regs.get(index) *% @as(u32, self.scale);
        const displacement_bits: u32 = @bitCast(self.displacement);
        value +%= displacement_bits;
        return value;
    }
};

pub const Rm32 = union(enum) {
    reg: Register,
    mem: EffectiveAddress,
};

const GroupInfo = struct {
    op: RawOp,
    mnemonic: []const u8,
    control: ControlKind,
    executable: bool,
    reason: []const u8,
};

pub const DecodedInstruction = struct {
    address: u32,
    len: u8,
    bytes: [max_instruction_len]u8 = [_]u8{0} ** max_instruction_len,
    opcode: u8,
    modrm: ?ModRm = null,
    sib: ?Sib = null,
    op: RawOp,
    status: DecodeStatus,
    control: ControlKind = .none,
    mnemonic: []const u8,
    isa_path: []const u8,
    operand: ?Rm32 = null,
    register: ?Register = null,
    immediate: u32 = 0,
    shift_from_cl: bool = false,
    binary_op: ?highway.BinaryOp = null,
    width: highway.Width = .bits32,
    source_width: highway.Width = .bits32,
    sign_extend: bool = false,
    condition: u4 = 0,
    byte_register: ?ByteRegister = null,
    byte_rm_register: ?ByteRegister = null,
    locked: bool = false,
    repeated: bool = false,
    repeat_not_equal: bool = false,
    segment_override: ?scaffold.SegmentOverride = null,
    transfer: ?highway.ControlTransfer = null,
    target: u32 = 0,
    text: [96]u8 = [_]u8{0} ** 96,
    text_len: u8 = 0,
    unsupported_reason: []const u8 = "",

    pub fn textSlice(self: *const DecodedInstruction) []const u8 {
        return self.text[0..self.text_len];
    }
};

const PrefixState = struct {
    operand_size_override: bool = false,
    address_size_override: bool = false,
    count: u8 = 0,
    locked: bool = false,
    repeated: bool = false,
    repeat_not_equal: bool = false,
    segment_override: ?scaffold.SegmentOverride = null,
};

fn reg32Name(reg: Register) []const u8 {
    return switch (reg) {
        .eax => "eax",
        .ecx => "ecx",
        .edx => "edx",
        .ebx => "ebx",
        .esp => "esp",
        .ebp => "ebp",
        .esi => "esi",
        .edi => "edi",
    };
}

fn reg16Name(reg: Register) []const u8 {
    return switch (reg) {
        .eax => "ax",
        .ecx => "cx",
        .edx => "dx",
        .ebx => "bx",
        .esp => "sp",
        .ebp => "bp",
        .esi => "si",
        .edi => "di",
    };
}

fn byteRegisterName(reg: ByteRegister) []const u8 {
    return switch (reg.base) {
        .eax => if (reg.high) "ah" else "al",
        .ecx => if (reg.high) "ch" else "cl",
        .edx => if (reg.high) "dh" else "dl",
        .ebx => if (reg.high) "bh" else "bl",
        .esp, .ebp, .esi, .edi => unreachable,
    };
}

fn conditionMnemonic(condition: u4) []const u8 {
    return switch (condition) {
        0x0 => "jo",
        0x1 => "jno",
        0x2 => "jb",
        0x3 => "jae",
        0x4 => "je",
        0x5 => "jne",
        0x6 => "jbe",
        0x7 => "ja",
        0x8 => "js",
        0x9 => "jns",
        0xA => "jp",
        0xB => "jnp",
        0xC => "jl",
        0xD => "jge",
        0xE => "jle",
        0xF => "jg",
    };
}

fn setccMnemonic(condition: u4) []const u8 {
    return switch (condition) {
        0x0 => "seto",
        0x1 => "setno",
        0x2 => "setb",
        0x3 => "setae",
        0x4 => "sete",
        0x5 => "setne",
        0x6 => "setbe",
        0x7 => "seta",
        0x8 => "sets",
        0x9 => "setns",
        0xA => "setp",
        0xB => "setnp",
        0xC => "setl",
        0xD => "setge",
        0xE => "setle",
        0xF => "setg",
    };
}

fn conditionIsaPath(condition: u4) []const u8 {
    return switch (condition) {
        0x0 => "JMP/JO.inc",
        0x1 => "JMP/JNO.inc",
        0x2 => "JMP/JB.inc",
        0x3 => "JMP/JAE.inc",
        0x4 => "JMP/JE.inc",
        0x5 => "JMP/JNE.inc",
        0x6 => "JMP/JBE.inc",
        0x7 => "JMP/JA.inc",
        0x8 => "JMP/JS.inc",
        0x9 => "JMP/JNS.inc",
        0xA => "JMP/JP.inc",
        0xB => "JMP/JNP.inc",
        0xC => "JMP/JL.inc",
        0xD => "JMP/JGE.inc",
        0xE => "JMP/JLE.inc",
        0xF => "JMP/JG.inc",
    };
}

fn registerFromBits(bits: u3) Register {
    return @enumFromInt(@as(u4, bits));
}

fn readU8(cursor: *scaffold.DecodeCursor) !u8 {
    return cursor.readU8();
}

fn readU32(cursor: *scaffold.DecodeCursor) !u32 {
    var result: u32 = 0;
    for (0..4) |shift| {
        result |= @as(u32, try readU8(cursor)) << @intCast(shift * 8);
    }
    return result;
}

fn readU16(cursor: *scaffold.DecodeCursor) !u16 {
    return @as(u16, try readU8(cursor)) | (@as(u16, try readU8(cursor)) << 8);
}

fn readI32(cursor: *scaffold.DecodeCursor) !i32 {
    return @bitCast(try readU32(cursor));
}

fn readI8(cursor: *scaffold.DecodeCursor) !i8 {
    return @bitCast(try readU8(cursor));
}

fn parsePrefixes(cursor: *scaffold.DecodeCursor) !PrefixState {
    var prefixes = PrefixState{};
    while (cursor.remaining() > 0 and cursor.offset < max_instruction_len) {
        const byte = cursor.bytes[cursor.offset];
        switch (byte) {
            0x66 => prefixes.operand_size_override = true,
            0x67 => prefixes.address_size_override = true,
            0xF0 => prefixes.locked = true,
            0xF2 => {
                prefixes.repeated = true;
                prefixes.repeat_not_equal = true;
            },
            0xF3 => {
                prefixes.repeated = true;
                prefixes.repeat_not_equal = false;
            },
            0x2E => prefixes.segment_override = .cs,
            0x36 => prefixes.segment_override = .ss,
            0x3E => prefixes.segment_override = .ds,
            0x26 => prefixes.segment_override = .es,
            0x64 => prefixes.segment_override = .fs,
            0x65 => prefixes.segment_override = .gs,
            else => break,
        }
        _ = try readU8(cursor);
        prefixes.count +|= 1;
    }
    return prefixes;
}

fn parseRm32(cursor: *scaffold.DecodeCursor, modrm: ModRm, out_sib: *?Sib) !Rm32 {
    if (modrm.mod == 3) {
        return .{ .reg = registerFromBits(modrm.rm) };
    }

    var mem = EffectiveAddress{};
    if (modrm.mod == 0 and modrm.rm == 5) {
        mem.absolute = try readU32(cursor);
        return .{ .mem = mem };
    }

    if (modrm.rm == 4) {
        const sib = try cursor.readSib();
        out_sib.* = sib;
        mem.scale = switch (sib.scale) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 8,
        };
        if (sib.index != 4) mem.index = registerFromBits(sib.index);
        if (modrm.mod == 0 and sib.base == 5) {
            mem.absolute = try readU32(cursor);
        } else {
            mem.base = registerFromBits(sib.base);
        }
    } else {
        mem.base = registerFromBits(modrm.rm);
    }

    mem.displacement = switch (modrm.mod) {
        0 => 0,
        1 => @as(i32, try readI8(cursor)),
        2 => try readI32(cursor),
        else => unreachable,
    };
    return .{ .mem = mem };
}

fn appendText(result: *DecodedInstruction, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.bufPrint(&result.text, fmt, args);
    result.text_len = @intCast(text.len);
}

fn formatRm32(buf: []u8, rm: Rm32) ![]const u8 {
    return switch (rm) {
        .reg => |reg| std.fmt.bufPrint(buf, "{s}", .{reg32Name(reg)}),
        .mem => |mem| blk: {
            if (mem.absolute) |absolute| {
                if (mem.base == null and mem.index == null and mem.displacement == 0) {
                    break :blk try std.fmt.bufPrint(buf, "[0x{X:0>8}]", .{absolute});
                }
            }
            if (mem.base) |base| {
                if (mem.index) |index| {
                    if (mem.displacement == 0) {
                        break :blk try std.fmt.bufPrint(buf, "[{s}+{s}*{d}]", .{ reg32Name(base), reg32Name(index), mem.scale });
                    }
                    if (mem.displacement < 0) {
                        break :blk try std.fmt.bufPrint(buf, "[{s}+{s}*{d}-0x{X}]", .{ reg32Name(base), reg32Name(index), mem.scale, @as(u32, @intCast(-mem.displacement)) });
                    }
                    break :blk try std.fmt.bufPrint(buf, "[{s}+{s}*{d}+0x{X}]", .{ reg32Name(base), reg32Name(index), mem.scale, @as(u32, @intCast(mem.displacement)) });
                }
                if (mem.displacement == 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}]", .{reg32Name(base)});
                }
                if (mem.displacement < 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}-0x{X}]", .{ reg32Name(base), @as(u32, @intCast(-mem.displacement)) });
                }
                break :blk try std.fmt.bufPrint(buf, "[{s}+0x{X}]", .{ reg32Name(base), @as(u32, @intCast(mem.displacement)) });
            }
            if (mem.index) |index| {
                if (mem.displacement == 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}*{d}]", .{ reg32Name(index), mem.scale });
                }
                if (mem.displacement < 0) {
                    break :blk try std.fmt.bufPrint(buf, "[{s}*{d}-0x{X}]", .{ reg32Name(index), mem.scale, @as(u32, @intCast(-mem.displacement)) });
                }
                break :blk try std.fmt.bufPrint(buf, "[{s}*{d}+0x{X}]", .{ reg32Name(index), mem.scale, @as(u32, @intCast(mem.displacement)) });
            }
            break :blk try std.fmt.bufPrint(buf, "[0x{X:0>8}]", .{mem.absolute orelse 0});
        },
    };
}

fn relTarget(address: u32, len: usize, rel: i32) u32 {
    const next = address +% @as(u32, @intCast(len));
    return next +% @as(u32, @bitCast(rel));
}

fn sourcePathForMnemonic(mnemonic: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(mnemonic, "add")) return "ADD/ADD.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "adc")) return "ADC-SBB/ADC.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "bit_and")) return "AND/AND.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "bit_or")) return "OR/OR.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "bit_xor")) return "XOR/XOR.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "call")) return "CALL-RET/CALL.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "cmp")) return "CMP/CMP.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "dec")) return "INC-DEC/DEC.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "inc")) return "INC-DEC/INC.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "idiv")) return "DIV/DIV.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "div")) return "DIV/DIV.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "jmp")) return "JMP/JMP.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "leave")) return "CALL-RET/LEAVE.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "mov")) return "MOV/MOV.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "nop")) return "INTERNAL/NOP";
    if (std.ascii.eqlIgnoreCase(mnemonic, "neg")) return "NEG/NEG.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "not")) return "NOT/NOT.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "pop")) return "POP/POP.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "push")) return "PUSH/PUSH.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "ret")) return "CALL-RET/RET.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "sbb")) return "ADC-SBB/SBB.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "sub")) return "SUB/SUB.inc";
    if (std.ascii.eqlIgnoreCase(mnemonic, "test")) return "TEST/TEST.inc";
    return "UNKNOWN";
}

fn finish(result: *DecodedInstruction, bytes: []const u8, len: usize) !DecodedInstruction {
    result.len = @intCast(len);
    const copy_len = @min(bytes.len, @min(len, result.bytes.len));
    @memcpy(result.bytes[0..copy_len], bytes[0..copy_len]);
    return result.*;
}

fn makeBase(address: u32, opcode: u8, op: RawOp, status: DecodeStatus, mnemonic: []const u8) DecodedInstruction {
    return .{
        .address = address,
        .len = 0,
        .opcode = opcode,
        .op = op,
        .status = status,
        .mnemonic = mnemonic,
        .isa_path = sourcePathForMnemonic(mnemonic),
    };
}

fn x87Mnemonic(opcode: u8, modrm: ModRm) []const u8 {
    if (modrm.mod == 3) {
        if (opcode == 0xD8) return switch (modrm.reg) {
            0 => "fadd",
            1 => "fmul",
            2 => "fcom",
            3 => "fcomp",
            4 => "fsub",
            5 => "fsubr",
            6 => "fdiv",
            7 => "fdivr",
        };
        if (opcode == 0xD9 and modrm.reg == 0) return "fld";
        if (opcode == 0xD9 and modrm.reg == 1) return "fxch";
        if (opcode == 0xD9 and modrm.reg == 4 and modrm.rm == 0) return "fchs";
        if (opcode == 0xD9 and modrm.reg == 4 and modrm.rm == 1) return "fabs";
        if (opcode == 0xD9 and modrm.reg == 5) return switch (modrm.rm) {
            0 => "fld1",
            1 => "fldl2t",
            2 => "fldl2e",
            3 => "fldpi",
            4 => "fldlg2",
            5 => "fldln2",
            6 => "fldz",
            else => "x87",
        };
        if (opcode == 0xD9 and modrm.reg == 6 and modrm.rm == 1) return "fyl2x";
        if (opcode == 0xD9 and modrm.reg == 7) return switch (modrm.rm) {
            2 => "fsqrt",
            6 => "fsin",
            7 => "fcos",
            else => "x87",
        };
        if (opcode == 0xDB and modrm.reg == 4 and modrm.rm == 2) return "fnclex";
        if (opcode == 0xDF and modrm.reg == 4 and modrm.rm == 0) return "fnstsw";
        if (opcode == 0xDF and modrm.reg == 5) return "fucomip";
        if (opcode == 0xDE and modrm.reg == 0) return "faddp";
        if (opcode == 0xDE and modrm.reg == 5) return "fsubp";
        if (opcode == 0xDD and modrm.reg == 2) return "fst";
        if (opcode == 0xDD and modrm.reg == 3) return "fstp";
        return "x87";
    }
    return switch (opcode) {
        0xD8 => switch (modrm.reg) {
            0 => "fadd",
            1 => "fmul",
            2 => "fcom",
            3 => "fcomp",
            4 => "fsub",
            5 => "fsubr",
            6 => "fdiv",
            7 => "fdivr",
        },
        0xD9 => switch (modrm.reg) {
            0 => "fld",
            2 => "fst",
            3 => "fstp",
            5 => "fldcw",
            7 => "fnstcw",
            else => "x87",
        },
        0xDA => switch (modrm.reg) {
            0 => "fiadd",
            1 => "fimul",
            2 => "ficom",
            3 => "ficomp",
            4 => "fisub",
            5 => "fisubr",
            6 => "fidiv",
            7 => "fidivr",
        },
        0xDB => switch (modrm.reg) {
            0 => "fild",
            5 => "fld",
            else => "x87",
        },
        0xDC => switch (modrm.reg) {
            0 => "fadd",
            1 => "fmul",
            2 => "fcom",
            3 => "fcomp",
            4 => "fsub",
            5 => "fsubr",
            6 => "fdiv",
            7 => "fdivr",
        },
        0xDE => switch (modrm.reg) {
            0 => "fiadd",
            1 => "fimul",
            2 => "ficom",
            3 => "ficomp",
            4 => "fisub",
            5 => "fisubr",
            6 => "fidiv",
            7 => "fidivr",
        },
        0xDF => switch (modrm.reg) {
            0 => "fild",
            7 => "fistp",
            else => "x87",
        },
        0xDD => switch (modrm.reg) {
            0 => "fld",
            2 => "fst",
            3 => "fstp",
            else => "x87",
        },
        else => "x87",
    };
}

fn x87EncodingSupported(opcode: u8, modrm: ModRm) bool {
    if (modrm.mod == 3) {
        return opcode == 0xD8 or
            (opcode == 0xD9 and modrm.reg == 0) or
            (opcode == 0xD9 and modrm.reg == 1) or
            (opcode == 0xD9 and modrm.reg == 4 and modrm.rm <= 1) or
            (opcode == 0xD9 and modrm.reg == 5 and modrm.rm <= 6) or
            (opcode == 0xD9 and modrm.reg == 6 and modrm.rm == 1) or
            (opcode == 0xD9 and modrm.reg == 7 and (modrm.rm == 2 or modrm.rm == 6 or modrm.rm == 7)) or
            (opcode == 0xDB and modrm.reg == 4 and modrm.rm == 2) or
            (opcode == 0xDF and modrm.reg == 4 and modrm.rm == 0) or
            (opcode == 0xDF and modrm.reg == 5) or
            (opcode == 0xDE and (modrm.reg == 0 or modrm.reg == 5) and modrm.rm != 0) or
            (opcode == 0xDD and (modrm.reg == 2 or modrm.reg == 3));
    }
    return switch (opcode) {
        0xD9 => modrm.reg == 0 or modrm.reg == 2 or modrm.reg == 3 or modrm.reg == 5 or modrm.reg == 7, // FLD/FST/FSTP m32real; FLDCW/FNSTCW m16
        0xDB => modrm.reg == 0 or modrm.reg == 5, // FILD m32 / FLD m80
        0xDA, 0xDE => true, // Integer FADD/FMUL/FCOM/FCOMP/FSUB/FSUBR/FDIV/FDIVR
        0xD8 => true, // FADD/FMUL/FCOM/FCOMP/FSUB/FSUBR/FDIV/FDIVR m32real
        0xDC => true, // FADD/FMUL/FCOM/FCOMP/FSUB/FSUBR/FDIV/FDIVR m64real
        0xDD => modrm.reg == 0 or modrm.reg == 2 or modrm.reg == 3, // FLD/FST/FSTP m64real
        0xDF => modrm.reg == 0 or modrm.reg == 7, // FILD m16int / FISTP m64int
        else => false,
    };
}

fn decodeX87(address: u32, opcode: u8, cursor: *scaffold.DecodeCursor, prefixes: PrefixState, bytes: []const u8) !DecodedInstruction {
    const modrm = try cursor.readModRm();
    var sib: ?Sib = null;
    const operand = try parseRm32(cursor, modrm, &sib);
    const mnemonic = x87Mnemonic(opcode, modrm);
    const supported = x87EncodingSupported(opcode, modrm) and !prefixes.locked and !prefixes.repeated;
    var result = makeBase(address, opcode, if (supported) .x87 else .recognized_unimplemented, if (supported) .executable else .recognized_unimplemented, mnemonic);
    result.isa_path = "X87/X87.inc";
    result.modrm = modrm;
    result.sib = sib;
    result.operand = operand;
    result.segment_override = prefixes.segment_override;
    result.width = switch (opcode) {
        0xD9 => if (modrm.reg == 5 or modrm.reg == 7) .bits16 else .bits32,
        0xD8 => .bits32,
        0xDB => if (modrm.reg == 0) .bits32 else .bits64,
        0xDA => .bits32,
        0xDE => .bits16,
        0xDF => if (modrm.reg == 7) .bits64 else .bits16,
        0xDC, 0xDD => .bits64,
        else => .bits32,
    };
    if (!supported) {
        result.unsupported_reason = if (prefixes.locked or prefixes.repeated)
            "LOCK/REP prefixes are not valid on this supported x87 subset"
        else
            "x87 encoding is decoded but not implemented by the PE raw bridge";
    }

    if (modrm.mod == 3) {
        try appendText(&result, "{s}", .{mnemonic});
    } else {
        var rm_buf: [64]u8 = undefined;
        const rm_text = try formatRm32(&rm_buf, operand);
        try appendText(&result, "{s} {s}", .{ mnemonic, rm_text });
    }
    return finish(&result, bytes, cursor.offset);
}

pub fn decodeInstruction(address: u32, bytes: []const u8) !DecodedInstruction {
    if (bytes.len == 0) return error.EndOfStream;

    var cursor = scaffold.DecodeCursor{ .bytes = bytes[0..@min(bytes.len, max_instruction_len)] };
    const prefixes = try parsePrefixes(&cursor);
    const opcode = try readU8(&cursor);

    if (prefixes.address_size_override) {
        var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "address-size-override");
        result.isa_path = "UNKNOWN";
        result.unsupported_reason = "16-bit addressing forms are not executable in the PE raw bridge yet";
        try appendText(&result, "db 0x{X:0>2}", .{opcode});
        return finish(&result, bytes, cursor.offset);
    }

    if (opcode >= 0xD8 and opcode <= 0xDF) return decodeX87(address, opcode, &cursor, prefixes, bytes);

    switch (opcode) {
        0x40...0x47, 0x48...0x4F => {
            const is_increment = opcode < 0x48;
            const register: Register = @enumFromInt(@as(u4, @truncate(opcode & 7)));
            const mnemonic = if (is_increment) "inc" else "dec";
            var result = makeBase(address, opcode, if (is_increment) .inc_reg else .dec_reg, .executable, mnemonic);
            result.register = register;
            result.width = if (prefixes.operand_size_override) .bits16 else .bits32;
            try appendText(&result, "{s} {s}", .{ mnemonic, if (result.width == .bits16) reg16Name(register) else reg32Name(register) });
            return finish(&result, bytes, cursor.offset);
        },
        0x0F => {
            const second = try readU8(&cursor);
            if (second == 0xA2) {
                var result = makeBase(address, second, .cpuid, .executable, "cpuid");
                result.isa_path = "CPU/CPUID.inc";
                try appendText(&result, "cpuid", .{});
                return finish(&result, bytes, cursor.offset);
            } else if (second >= 0x80 and second <= 0x8F) {
                const relative = try readI32(&cursor);
                const condition: u4 = @truncate(second & 0x0F);
                const mnemonic = conditionMnemonic(condition);
                var result = makeBase(address, second, .jcc_rel, .executable, mnemonic);
                result.control = .conditional_jump;
                result.condition = condition;
                result.isa_path = conditionIsaPath(condition);
                result.transfer = highway.relativeControl(.conditional_jump, address, @intCast(cursor.offset), relative, true);
                result.target = @truncate(result.transfer.?.target);
                try appendText(&result, "{s} 0x{X:0>8}", .{ mnemonic, result.target });
                return finish(&result, bytes, cursor.offset);
            } else if (second >= 0x90 and second <= 0x9F) {
                const modrm = try cursor.readModRm();
                var sib: ?Sib = null;
                const rm = try parseRm32(&cursor, modrm, &sib);
                const condition: u4 = @truncate(second & 0x0F);
                const mnemonic = setccMnemonic(condition);
                var result = makeBase(address, second, .setcc, .executable, mnemonic);
                result.modrm = modrm;
                result.sib = sib;
                result.operand = rm;
                result.width = .bits8;
                result.condition = condition;
                result.segment_override = prefixes.segment_override;
                result.locked = prefixes.locked;
                if (modrm.mod == 3) result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
                if (prefixes.locked) {
                    result.op = .recognized_unimplemented;
                    result.status = .recognized_unimplemented;
                    result.unsupported_reason = "LOCK is invalid on SETcc";
                }
                var rm_buf: [64]u8 = undefined;
                const rm_text = if (result.byte_rm_register) |byte_reg|
                    try std.fmt.bufPrint(&rm_buf, "{s}", .{byteRegisterName(byte_reg)})
                else
                    try formatRm32(&rm_buf, rm);
                try appendText(&result, "{s} {s}", .{ mnemonic, rm_text });
                return finish(&result, bytes, cursor.offset);
            } else if (second == 0xB6 or second == 0xB7 or second == 0xBE or second == 0xBF) {
                const modrm = try cursor.readModRm();
                var sib: ?Sib = null;
                const rm = try parseRm32(&cursor, modrm, &sib);
                const source_width: highway.Width = if (second == 0xB6 or second == 0xBE) .bits8 else .bits16;
                const destination_width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
                const sign_extend = second == 0xBE or second == 0xBF;
                const destination = registerFromBits(modrm.reg);
                const mnemonic: []const u8 = if (sign_extend) "movsx" else "movzx";
                var result = makeBase(address, second, .mov_extend, .executable, mnemonic);
                result.modrm = modrm;
                result.sib = sib;
                result.operand = rm;
                result.register = destination;
                result.width = destination_width;
                result.source_width = source_width;
                result.sign_extend = sign_extend;
                result.segment_override = prefixes.segment_override;
                result.locked = prefixes.locked;
                result.isa_path = if (sign_extend) "MOV/MOVSX.inc" else "MOV/MOVZX.inc";
                if (destination_width.bits() <= source_width.bits()) {
                    result.op = .recognized_unimplemented;
                    result.status = .recognized_unimplemented;
                    result.unsupported_reason = "MOVSX/MOVZX destination must be wider than its source";
                } else if (prefixes.locked) {
                    result.op = .recognized_unimplemented;
                    result.status = .recognized_unimplemented;
                    result.unsupported_reason = "LOCK is invalid for MOVSX/MOVZX";
                }
                var rm_buf: [64]u8 = undefined;
                const rm_text = if (source_width == .bits8 and modrm.mod == 3) blk: {
                    result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
                    break :blk try std.fmt.bufPrint(&rm_buf, "{s}", .{byteRegisterName(result.byte_rm_register.?)});
                } else try formatRm32(&rm_buf, rm);
                const destination_text = if (destination_width == .bits16) reg16Name(destination) else reg32Name(destination);
                try appendText(&result, "{s} {s}, {s}", .{ mnemonic, destination_text, rm_text });
                return finish(&result, bytes, cursor.offset);
            } else if (second == 0xAF) {
                const modrm = try cursor.readModRm();
                var sib: ?Sib = null;
                const rm = try parseRm32(&cursor, modrm, &sib);
                const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
                const destination = registerFromBits(modrm.reg);
                var result = makeBase(address, second, .imul_rm, .executable, "imul");
                result.modrm = modrm;
                result.sib = sib;
                result.operand = rm;
                result.register = destination;
                result.width = width;
                result.segment_override = prefixes.segment_override;
                result.locked = prefixes.locked;
                if (prefixes.locked) {
                    result.op = .recognized_unimplemented;
                    result.status = .recognized_unimplemented;
                    result.unsupported_reason = "LOCK is invalid on two-operand IMUL";
                }
                var rm_buf: [64]u8 = undefined;
                const rm_text = try formatRm32(&rm_buf, rm);
                try appendText(&result, "imul {s}, {s}", .{ if (width == .bits16) reg16Name(destination) else reg32Name(destination), rm_text });
                return finish(&result, bytes, cursor.offset);
            }
            var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "db");
            result.isa_path = "UNKNOWN";
            result.unsupported_reason = "two-byte opcode is not decoded by the PE raw bridge yet";
            try appendText(&result, "db 0x0F, 0x{X:0>2}", .{second});
            return finish(&result, bytes, cursor.offset);
        },
        0x9C, 0x9D => {
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            const is_push = opcode == 0x9C;
            var result = makeBase(address, opcode, if (is_push) .push_flags else .pop_flags, .executable, if (is_push) "pushf" else "popf");
            result.width = width;
            result.isa_path = if (is_push)
                (if (width == .bits16) "PUSH/PUSHF.inc" else "PUSH/PUSHFD.inc")
            else
                "UNKNOWN";
            try appendText(&result, "{s}", .{if (is_push) (if (width == .bits16) "pushf" else "pushfd") else if (width == .bits16) "popf" else "popfd"});
            return finish(&result, bytes, cursor.offset);
        },
        0x9E => {
            var result = makeBase(address, opcode, .sahf, .executable, "sahf");
            result.isa_path = "FLAGS/SAHF";
            try appendText(&result, "sahf", .{});
            return finish(&result, bytes, cursor.offset);
        },
        0x99 => {
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            const mnemonic: []const u8 = if (width == .bits16) "cwd" else "cdq";
            var result = makeBase(address, opcode, .sign_extend_accumulator, .executable, mnemonic);
            result.width = width;
            result.isa_path = "CONVERT/CWD-CDQ.inc";
            try appendText(&result, "{s}", .{mnemonic});
            return finish(&result, bytes, cursor.offset);
        },
        0x90 => {
            var result = makeBase(address, opcode, .nop, .executable, "nop");
            try appendText(&result, "nop", .{});
            return finish(&result, bytes, cursor.offset);
        },
        0x9B => {
            // The raw PE model executes x87 operations synchronously and does
            // not queue deferred x87 exceptions, so FWAIT only advances EIP.
            var result = makeBase(address, opcode, .nop, .executable, "fwait");
            result.isa_path = "X87/X87.inc";
            try appendText(&result, "fwait", .{});
            return finish(&result, bytes, cursor.offset);
        },
        0xFC, 0xFD => {
            const set = opcode == 0xFD;
            var result = makeBase(address, opcode, if (set) .set_direction_flag else .clear_direction_flag, .executable, if (set) "std" else "cld");
            result.isa_path = if (set) "FLAGS/STD" else "FLAGS/CLD";
            try appendText(&result, "{s}", .{if (set) "std" else "cld"});
            return finish(&result, bytes, cursor.offset);
        },
        0x91...0x97 => {
            const register: Register = @enumFromInt(@as(u4, @truncate(opcode & 7)));
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            var result = makeBase(address, opcode, .xchg_eax_reg, .executable, "xchg");
            result.register = register;
            result.width = width;
            result.isa_path = "XCHG/XCHG.inc";
            if (prefixes.locked) {
                result.op = .recognized_unimplemented;
                result.status = .recognized_unimplemented;
                result.unsupported_reason = "LOCK is invalid for register XCHG";
            }
            const accumulator = if (width == .bits16) "ax" else "eax";
            const other = if (width == .bits16) reg16Name(register) else reg32Name(register);
            try appendText(&result, "xchg {s}, {s}", .{ accumulator, other });
            return finish(&result, bytes, cursor.offset);
        },
        0xA4, 0xA5 => {
            const width: highway.Width = if (opcode == 0xA4)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const mnemonic: []const u8 = if (width == .bits8) "movsb" else if (width == .bits16) "movsw" else "movsd";
            var result = makeBase(address, opcode, .string_movs, .executable, mnemonic);
            result.width = width;
            result.segment_override = prefixes.segment_override;
            result.repeated = prefixes.repeated;
            result.isa_path = "STRING-OPS/MOVS";
            if (prefixes.locked) {
                result.op = .recognized_unimplemented;
                result.status = .recognized_unimplemented;
                result.unsupported_reason = "LOCK is invalid for MOVS";
            }
            try appendText(&result, "{s}{s}", .{ if (prefixes.repeated) "rep " else "", mnemonic });
            return finish(&result, bytes, cursor.offset);
        },
        0xAA, 0xAB => {
            const width: highway.Width = if (opcode == 0xAA)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const mnemonic: []const u8 = if (width == .bits8) "stosb" else if (width == .bits16) "stosw" else "stosd";
            var result = makeBase(address, opcode, .string_stos, .executable, mnemonic);
            result.width = width;
            result.repeated = prefixes.repeated;
            result.isa_path = "STRING-OPS/STOS";
            if (prefixes.locked) {
                result.op = .recognized_unimplemented;
                result.status = .recognized_unimplemented;
                result.unsupported_reason = "LOCK is invalid for STOS";
            }
            try appendText(&result, "{s}{s}", .{ if (prefixes.repeated) "rep " else "", mnemonic });
            return finish(&result, bytes, cursor.offset);
        },
        0xAE, 0xAF => {
            const width: highway.Width = if (opcode == 0xAE)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const mnemonic: []const u8 = if (width == .bits8) "scasb" else if (width == .bits16) "scasw" else "scasd";
            var result = makeBase(address, opcode, .string_scas, .executable, mnemonic);
            result.width = width;
            result.repeated = prefixes.repeated;
            result.repeat_not_equal = prefixes.repeat_not_equal;
            result.isa_path = "STRING-OPS/SCAS";
            if (prefixes.locked) {
                result.op = .recognized_unimplemented;
                result.status = .recognized_unimplemented;
                result.unsupported_reason = "LOCK is invalid for SCAS";
            }
            const repeat_text: []const u8 = if (!prefixes.repeated) "" else if (prefixes.repeat_not_equal) "repne " else "repe ";
            try appendText(&result, "{s}{s}", .{ repeat_text, mnemonic });
            return finish(&result, bytes, cursor.offset);
        },
        0xC2, 0xC3 => {
            const stack_cleanup = if (opcode == 0xC2) try readU16(&cursor) else 0;
            var result = makeBase(address, opcode, .ret, .executable, "ret");
            result.control = .near_return;
            result.immediate = stack_cleanup;
            if (opcode == 0xC2) {
                try appendText(&result, "ret 0x{X}", .{stack_cleanup});
            } else {
                try appendText(&result, "ret", .{});
            }
            return finish(&result, bytes, cursor.offset);
        },
        0x60, 0x61 => {
            const is_pusha = opcode == 0x60;
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            const mnemonic = if (is_pusha)
                (if (width == .bits16) "pusha" else "pushad")
            else
                (if (width == .bits16) "popa" else "popad");
            const supported = !prefixes.locked and !prefixes.repeated;
            var result = makeBase(
                address,
                opcode,
                if (is_pusha) .pusha else .popa,
                if (supported) .executable else .recognized_unimplemented,
                mnemonic,
            );
            result.width = width;
            result.isa_path = if (is_pusha) "PUSH/PUSHA.inc" else "POP/POPA.inc";
            if (!supported) result.unsupported_reason = "LOCK/REP prefixes are invalid for PUSHA/POPA";
            try appendText(&result, "{s}", .{mnemonic});
            return finish(&result, bytes, cursor.offset);
        },
        0x50...0x57 => {
            const reg: Register = @enumFromInt(@as(u4, @truncate(opcode - 0x50)));
            var result = makeBase(address, opcode, .push_reg, .executable, "push");
            result.register = reg;
            try appendText(&result, "push {s}", .{reg32Name(reg)});
            return finish(&result, bytes, cursor.offset);
        },
        0x58...0x5F => {
            const reg: Register = @enumFromInt(@as(u4, @truncate(opcode - 0x58)));
            var result = makeBase(address, opcode, .pop_reg, .executable, "pop");
            result.register = reg;
            try appendText(&result, "pop {s}", .{reg32Name(reg)});
            return finish(&result, bytes, cursor.offset);
        },
        0xC9 => {
            var result = makeBase(address, opcode, .leave, .executable, "leave");
            result.width = if (prefixes.operand_size_override) .bits16 else .bits32;
            try appendText(&result, "leave", .{});
            return finish(&result, bytes, cursor.offset);
        },
        0x68 => {
            const imm = try readU32(&cursor);
            var result = makeBase(address, opcode, .push_imm, .executable, "push");
            result.immediate = imm;
            try appendText(&result, "push 0x{X:0>8}", .{imm});
            return finish(&result, bytes, cursor.offset);
        },
        0x6A => {
            const imm8 = try readI8(&cursor);
            var result = makeBase(address, opcode, .push_imm, .executable, "push");
            result.immediate = @as(u32, @bitCast(@as(i32, imm8)));
            try appendText(&result, "push {d}", .{imm8});
            return finish(&result, bytes, cursor.offset);
        },
        0x69, 0x6B => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            const immediate: u32 = if (opcode == 0x6B)
                @bitCast(@as(i32, try readI8(&cursor)))
            else if (width == .bits16)
                @as(u32, try readU16(&cursor))
            else
                try readU32(&cursor);
            const destination = registerFromBits(modrm.reg);
            var result = makeBase(address, opcode, .imul_immediate, .executable, "imul");
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.register = destination;
            result.width = width;
            result.immediate = immediate;
            result.segment_override = prefixes.segment_override;
            result.locked = prefixes.locked;
            result.isa_path = "IMUL/IMUL-IMMEDIATE.inc";
            if (prefixes.locked) {
                result.op = .recognized_unimplemented;
                result.status = .recognized_unimplemented;
                result.unsupported_reason = "LOCK is invalid on immediate IMUL";
            }
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            try appendText(&result, "imul {s}, {s}, 0x{X}", .{
                if (width == .bits16) reg16Name(destination) else reg32Name(destination),
                rm_text,
                immediate,
            });
            return finish(&result, bytes, cursor.offset);
        },
        0xB0...0xB7 => {
            const reg = ByteRegister.fromEncoding(@truncate(opcode - 0xB0));
            const immediate = try readU8(&cursor);
            const supported = !prefixes.locked and !prefixes.repeated;
            var result = makeBase(
                address,
                opcode,
                .mov_byte_reg_imm,
                if (supported) .executable else .recognized_unimplemented,
                "mov",
            );
            result.byte_register = reg;
            result.width = .bits8;
            result.immediate = immediate;
            if (!supported) result.unsupported_reason = "LOCK/REP prefixes are invalid for MOV r8, imm8";
            try appendText(&result, "mov {s}, 0x{X:0>2}", .{ byteRegisterName(reg), immediate });
            return finish(&result, bytes, cursor.offset);
        },
        0xB8...0xBF => {
            const reg: Register = @enumFromInt(@as(u4, @truncate(opcode - 0xB8)));
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            const imm: u32 = if (width == .bits16) try readU16(&cursor) else try readU32(&cursor);
            var result = makeBase(address, opcode, .mov_reg_imm, .executable, "mov");
            result.register = reg;
            result.width = width;
            result.immediate = imm;
            try appendText(&result, "mov {s}, 0x{X}", .{ if (width == .bits16) reg16Name(reg) else reg32Name(reg), imm });
            return finish(&result, bytes, cursor.offset);
        },
        0xE8 => {
            const rel = try readI32(&cursor);
            var result = makeBase(address, opcode, .call_rel, .executable, "call");
            result.control = .near_call;
            result.transfer = highway.relativeControl(.call, address, @intCast(cursor.offset), rel, true);
            result.target = @truncate(result.transfer.?.target);
            try appendText(&result, "call 0x{X:0>8}", .{result.target});
            return finish(&result, bytes, cursor.offset);
        },
        0xE9 => {
            const rel = try readI32(&cursor);
            var result = makeBase(address, opcode, .jmp_rel, .executable, "jmp");
            result.control = .near_jump;
            result.transfer = highway.relativeControl(.jump, address, @intCast(cursor.offset), rel, true);
            result.target = @truncate(result.transfer.?.target);
            try appendText(&result, "jmp 0x{X:0>8}", .{result.target});
            return finish(&result, bytes, cursor.offset);
        },
        0x70...0x7F => {
            const relative = try readI8(&cursor);
            const condition: u4 = @truncate(opcode & 0x0F);
            const mnemonic = conditionMnemonic(condition);
            var result = makeBase(address, opcode, .jcc_rel, .executable, mnemonic);
            result.control = .conditional_jump;
            result.condition = condition;
            result.isa_path = conditionIsaPath(condition);
            result.transfer = highway.relativeControl(.conditional_jump, address, @intCast(cursor.offset), relative, true);
            result.target = @truncate(result.transfer.?.target);
            try appendText(&result, "{s} 0x{X:0>8}", .{ mnemonic, result.target });
            return finish(&result, bytes, cursor.offset);
        },
        0x84, 0x85 => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            const width: highway.Width = if (opcode == 0x84)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            var result = makeBase(address, opcode, .binary, .executable, "test");
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.register = registerFromBits(modrm.reg);
            result.binary_op = .test_bits;
            result.width = width;
            result.segment_override = prefixes.segment_override;
            if (width == .bits8) {
                result.byte_register = ByteRegister.fromEncoding(modrm.reg);
                if (modrm.mod == 3) result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
            }
            try appendText(&result, "test {s}, {s}", .{ rm_text, reg32Name(registerFromBits(modrm.reg)) });
            return finish(&result, bytes, cursor.offset);
        },
        0xA8, 0xA9 => {
            const width: highway.Width = if (opcode == 0xA8)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const immediate: u32 = if (width == .bits8)
                @as(u32, try readU8(&cursor))
            else if (width == .bits16)
                @as(u32, try readU16(&cursor))
            else
                try readU32(&cursor);
            var result = makeBase(address, opcode, .binary_immediate, .executable, "test");
            result.operand = .{ .reg = .eax };
            result.register = .eax;
            result.binary_op = .test_bits;
            result.width = width;
            result.immediate = immediate;
            result.isa_path = "TEST/TEST.inc";
            if (width == .bits8) result.byte_rm_register = ByteRegister.fromEncoding(0);
            try appendText(&result, "test {s}, 0x{X}", .{
                if (width == .bits8) "al" else if (width == .bits16) "ax" else "eax",
                immediate,
            });
            return finish(&result, bytes, cursor.offset);
        },
        0x04,
        0x05,
        0x0C,
        0x0D,
        0x14,
        0x15,
        0x1C,
        0x1D,
        0x24,
        0x25,
        0x2C,
        0x2D,
        0x34,
        0x35,
        0x3C,
        0x3D,
        => {
            const encoding = highway.classifyGroup1(@truncate((opcode >> 3) & 7));
            const width: highway.Width = if ((opcode & 1) == 0)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const immediate: u32 = if (width == .bits8)
                @as(u32, try readU8(&cursor))
            else if (width == .bits16)
                @as(u32, try readU16(&cursor))
            else
                try readU32(&cursor);
            var result = makeBase(address, opcode, .binary_immediate, .executable, @tagName(encoding.op));
            result.operand = .{ .reg = .eax };
            result.register = .eax;
            result.binary_op = encoding.op;
            result.width = width;
            result.immediate = immediate;
            result.locked = prefixes.locked;
            if (width == .bits8) result.byte_rm_register = ByteRegister.fromEncoding(0);
            try appendText(&result, "{s} {s}, 0x{X}", .{
                @tagName(encoding.op),
                if (width == .bits8) "al" else if (width == .bits16) "ax" else "eax",
                immediate,
            });
            return finish(&result, bytes, cursor.offset);
        },
        0xEB => {
            const rel = @as(i32, try readI8(&cursor));
            var result = makeBase(address, opcode, .jmp_rel, .executable, "jmp");
            result.control = .near_jump;
            result.transfer = highway.relativeControl(.jump, address, @intCast(cursor.offset), rel, true);
            result.target = @truncate(result.transfer.?.target);
            try appendText(&result, "jmp 0x{X:0>8}", .{result.target});
            return finish(&result, bytes, cursor.offset);
        },
        0x00...0x03, 0x08...0x0B, 0x10...0x13, 0x18...0x1B, 0x20...0x23, 0x28...0x2B, 0x30...0x33, 0x38...0x3B => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            const encoding = highway.classifyLegacyBinaryOpcode(opcode).?;
            const binary_op = encoding.op;
            const mnemonic = @tagName(binary_op);
            const width: highway.Width = if ((opcode & 1) == 0)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            var result = makeBase(address, opcode, .binary, .executable, mnemonic);
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.register = registerFromBits(modrm.reg);
            result.binary_op = binary_op;
            result.width = width;
            result.locked = prefixes.locked;
            result.segment_override = prefixes.segment_override;
            if (width == .bits8) {
                result.byte_register = ByteRegister.fromEncoding(modrm.reg);
                if (modrm.mod == 3) result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
            }
            if (encoding.direction == .register_destination) {
                try appendText(&result, "{s} {s}, {s}", .{ mnemonic, reg32Name(registerFromBits(modrm.reg)), rm_text });
            } else {
                try appendText(&result, "{s} {s}, {s}", .{ mnemonic, rm_text, reg32Name(registerFromBits(modrm.reg)) });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0x80, 0x81, 0x83 => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const encoding = highway.classifyGroup1(modrm.reg);
            const width: highway.Width = if (opcode == 0x80)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const immediate: u32 = if (opcode == 0x80 or opcode == 0x83)
                @as(u32, @bitCast(@as(i32, try readI8(&cursor))))
            else if (width == .bits16)
                try readU16(&cursor)
            else
                try readU32(&cursor);
            var result = makeBase(address, opcode, .binary_immediate, .executable, @tagName(encoding.op));
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.binary_op = encoding.op;
            result.width = width;
            result.immediate = immediate;
            result.locked = prefixes.locked;
            result.segment_override = prefixes.segment_override;
            if (width == .bits8 and modrm.mod == 3) result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
            try appendText(&result, "{s} r/m, 0x{X}", .{ @tagName(encoding.op), immediate });
            return finish(&result, bytes, cursor.offset);
        },
        0xF7 => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const width: highway.Width = if (prefixes.operand_size_override) .bits16 else .bits32;
            const is_test = modrm.reg == 0;
            const is_not = modrm.reg == 2;
            const is_neg = modrm.reg == 3;
            const is_unsigned_divide = modrm.reg == 6;
            const is_signed_divide = modrm.reg == 7;
            const test_immediate: u32 = if (!is_test)
                0
            else if (width == .bits16)
                try readU16(&cursor)
            else
                try readU32(&cursor);
            var result = makeBase(
                address,
                opcode,
                if (is_test) .binary_immediate else if (is_neg) .group3_neg else if (is_not) .group3_not else if (is_unsigned_divide) .group3_div else if (is_signed_divide) .group3_idiv else .recognized_unimplemented,
                if (is_test or is_neg or is_not or is_unsigned_divide or is_signed_divide) .executable else .recognized_unimplemented,
                if (is_test) "test" else if (is_neg) "neg" else if (is_not) "not" else if (is_unsigned_divide) "div" else if (is_signed_divide) "idiv" else "group3",
            );
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = width;
            result.locked = prefixes.locked;
            result.segment_override = prefixes.segment_override;
            if (is_test) {
                result.binary_op = .test_bits;
                result.immediate = test_immediate;
                result.isa_path = "TEST/TEST.inc";
                var rm_buf: [64]u8 = undefined;
                const rm_text = try formatRm32(&rm_buf, rm);
                try appendText(&result, "test {s}, 0x{X}", .{ rm_text, test_immediate });
            } else if (is_neg or is_not or is_unsigned_divide or is_signed_divide) {
                var rm_buf: [64]u8 = undefined;
                const rm_text = try formatRm32(&rm_buf, rm);
                const mnemonic: []const u8 = if (is_neg) "neg" else if (is_not) "not" else if (is_signed_divide) "idiv" else "div";
                if (is_unsigned_divide or is_signed_divide) result.isa_path = "DIV/DIV.inc";
                try appendText(&result, "{s} {s}", .{ mnemonic, rm_text });
            } else {
                result.isa_path = "UNKNOWN";
                result.unsupported_reason = "F7 Group3 extension is not implemented in the PE raw bridge yet";
                try appendText(&result, "group3 /{d}", .{modrm.reg});
            }
            return finish(&result, bytes, cursor.offset);
        },
        0xF6 => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const is_test = modrm.reg == 0;
            const is_not = modrm.reg == 2;
            const is_neg = modrm.reg == 3;
            if (!is_test and !is_not and !is_neg) {
                var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "group3");
                result.modrm = modrm;
                result.sib = sib;
                result.operand = rm;
                result.width = .bits8;
                result.isa_path = "UNKNOWN";
                result.unsupported_reason = "F6 Group3 extension is not implemented in the PE raw bridge yet";
                try appendText(&result, "group3 /{d}", .{modrm.reg});
                return finish(&result, bytes, cursor.offset);
            }
            const immediate = if (is_test) try cursor.readU8() else 0;
            const op: RawOp = if (is_test) .binary_immediate else if (is_neg) .group3_neg else .group3_not;
            const mnemonic: []const u8 = if (is_test) "test" else if (is_neg) "neg" else "not";
            var result = makeBase(address, opcode, op, .executable, mnemonic);
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = .bits8;
            result.locked = prefixes.locked;
            result.segment_override = prefixes.segment_override;
            if (modrm.mod == 3) result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
            if (is_test) {
                result.binary_op = .test_bits;
                result.immediate = immediate;
            }
            var rm_buf: [64]u8 = undefined;
            const rm_text = if (result.byte_rm_register) |byte_reg|
                try std.fmt.bufPrint(&rm_buf, "{s}", .{byteRegisterName(byte_reg)})
            else
                try formatRm32(&rm_buf, rm);
            if (is_test) {
                try appendText(&result, "test {s}, 0x{X}", .{ rm_text, immediate });
            } else {
                try appendText(&result, "{s} {s}", .{ mnemonic, rm_text });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3 => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const width: highway.Width = if (opcode == 0xC0 or opcode == 0xD0 or opcode == 0xD2)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const from_cl = opcode == 0xD2 or opcode == 0xD3;
            const immediate: u32 = if (opcode == 0xC0 or opcode == 0xC1)
                @as(u32, try readU8(&cursor))
            else if (opcode == 0xD0 or opcode == 0xD1)
                1
            else
                0;
            const mnemonic = switch (modrm.reg) {
                0 => "rol",
                1 => "ror",
                2 => "rcl",
                3 => "rcr",
                4, 6 => "shl",
                5 => "shr",
                7 => "sar",
            };
            var result = makeBase(address, opcode, .group2_shift, .executable, mnemonic);
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = width;
            result.immediate = immediate;
            result.shift_from_cl = from_cl;
            result.segment_override = prefixes.segment_override;
            result.locked = prefixes.locked;
            if (prefixes.locked) {
                result.op = .recognized_unimplemented;
                result.status = .recognized_unimplemented;
                result.unsupported_reason = "LOCK is not valid on x86 Group2 shifts and rotates";
            }
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            if (from_cl) {
                try appendText(&result, "{s} {s}, cl", .{ mnemonic, rm_text });
            } else {
                try appendText(&result, "{s} {s}, {d}", .{ mnemonic, rm_text, immediate });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0x88...0x8B => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            const width: highway.Width = if ((opcode & 1) == 0)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            var result = makeBase(address, opcode, .mov_rm, .executable, "mov");
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = width;
            result.register = registerFromBits(modrm.reg);
            result.segment_override = prefixes.segment_override;
            if (width == .bits8) {
                result.byte_register = ByteRegister.fromEncoding(modrm.reg);
                if (modrm.mod == 3) result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
            }
            const d = (opcode >> 1) & 1;
            if (d == 1) {
                try appendText(&result, "mov {s}, {s}", .{ reg32Name(registerFromBits(modrm.reg)), rm_text });
            } else {
                try appendText(&result, "mov {s}, {s}", .{ rm_text, reg32Name(registerFromBits(modrm.reg)) });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0xC6, 0xC7 => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const width: highway.Width = if (opcode == 0xC6)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            const immediate = if (width == .bits8)
                @as(u32, try readU8(&cursor))
            else if (width == .bits16)
                @as(u32, try readU16(&cursor))
            else
                try readU32(&cursor);
            const is_mov = modrm.reg == 0;
            var result = makeBase(
                address,
                opcode,
                if (is_mov) .mov_immediate_rm else .recognized_unimplemented,
                if (is_mov) .executable else .recognized_unimplemented,
                "mov",
            );
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = width;
            result.immediate = immediate;
            result.segment_override = prefixes.segment_override;
            if (!is_mov) {
                result.isa_path = "UNKNOWN";
                result.unsupported_reason = "C6/C7 Group11 extension is not MOV /0";
            }
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            try appendText(&result, "mov {s}, 0x{X}", .{ rm_text, immediate });
            return finish(&result, bytes, cursor.offset);
        },
        0xA0...0xA3 => {
            const target_address = try readU32(&cursor);
            const width: highway.Width = if ((opcode & 1) == 0)
                .bits8
            else if (prefixes.operand_size_override)
                .bits16
            else
                .bits32;
            var result = makeBase(address, opcode, .mov_rm, .executable, "mov");
            result.operand = .{ .mem = .{ .absolute = target_address } };
            result.register = .eax;
            result.width = width;
            result.segment_override = prefixes.segment_override;
            if (width == .bits8) result.byte_register = .{ .base = .eax };
            const text_width_register = if (width == .bits8) "al" else if (width == .bits16) "ax" else "eax";
            if ((opcode & 2) == 0) {
                try appendText(&result, "mov {s}, [0x{X:0>8}]", .{ text_width_register, target_address });
            } else {
                try appendText(&result, "mov [0x{X:0>8}], {s}", .{ target_address, text_width_register });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0x8D => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            if (modrm.mod == 3) {
                var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "lea");
                result.unsupported_reason = "LEA requires a memory addressing form";
                return finish(&result, bytes, cursor.offset);
            }
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            var result = makeBase(address, opcode, .lea, .executable, "lea");
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.register = registerFromBits(modrm.reg);
            result.width = if (prefixes.operand_size_override) .bits16 else .bits32;
            result.segment_override = prefixes.segment_override;
            try appendText(&result, "lea {s}, {s}", .{ reg32Name(result.register.?), rm_text });
            return finish(&result, bytes, cursor.offset);
        },
        0xFE => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            const info: GroupInfo = switch (modrm.reg) {
                0 => .{ .op = RawOp.group4_inc, .mnemonic = "inc", .control = ControlKind.none, .executable = true, .reason = "" },
                1 => .{ .op = RawOp.group4_dec, .mnemonic = "dec", .control = ControlKind.none, .executable = true, .reason = "" },
                else => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "group4", .control = ControlKind.none, .executable = false, .reason = "undefined Group4 extension" },
            };
            var result = makeBase(address, opcode, info.op, if (info.executable) .executable else .recognized_unimplemented, info.mnemonic);
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = .bits8;
            result.segment_override = prefixes.segment_override;
            result.locked = prefixes.locked;
            if (modrm.mod == 3) {
                result.byte_rm_register = ByteRegister.fromEncoding(modrm.rm);
                if (prefixes.locked) {
                    result.op = .recognized_unimplemented;
                    result.status = .recognized_unimplemented;
                    result.unsupported_reason = "LOCK is invalid for register INC/DEC";
                }
                try appendText(&result, "{s} {s}", .{ info.mnemonic, byteRegisterName(result.byte_rm_register.?) });
            } else {
                var rm_buf: [64]u8 = undefined;
                const rm_text = try formatRm32(&rm_buf, rm);
                try appendText(&result, "{s} {s}", .{ info.mnemonic, rm_text });
            }
            return finish(&result, bytes, cursor.offset);
        },
        0xFF => {
            const modrm = try cursor.readModRm();
            var sib: ?Sib = null;
            const rm = try parseRm32(&cursor, modrm, &sib);
            var rm_buf: [64]u8 = undefined;
            const rm_text = try formatRm32(&rm_buf, rm);
            const group_op = modrm.reg;
            const info: GroupInfo = switch (group_op) {
                0 => .{ .op = RawOp.group5_inc, .mnemonic = "inc", .control = ControlKind.none, .executable = true, .reason = "" },
                1 => .{ .op = RawOp.group5_dec, .mnemonic = "dec", .control = ControlKind.none, .executable = true, .reason = "" },
                2 => .{ .op = RawOp.group5_call, .mnemonic = "call", .control = ControlKind.near_call, .executable = true, .reason = "" },
                4 => .{ .op = RawOp.group5_jmp, .mnemonic = "jmp", .control = ControlKind.near_jump, .executable = true, .reason = "" },
                6 => .{ .op = RawOp.group5_push, .mnemonic = "push", .control = ControlKind.none, .executable = true, .reason = "" },
                3 => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "call", .control = ControlKind.near_call, .executable = false, .reason = "far CALL is decoded but not executable in the raw bridge yet" },
                5 => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "jmp", .control = ControlKind.near_jump, .executable = false, .reason = "far JMP is decoded but not executable in the raw bridge yet" },
                else => .{ .op = RawOp.recognized_unimplemented, .mnemonic = "group5", .control = ControlKind.none, .executable = false, .reason = "undefined Group5 extension" },
            };
            var result = makeBase(address, opcode, info.op, if (info.executable) .executable else .recognized_unimplemented, info.mnemonic);
            result.control = info.control;
            result.modrm = modrm;
            result.sib = sib;
            result.operand = rm;
            result.width = if (prefixes.operand_size_override) .bits16 else .bits32;
            result.segment_override = prefixes.segment_override;
            result.unsupported_reason = info.reason;
            try appendText(&result, "{s} {s}", .{ info.mnemonic, rm_text });
            return finish(&result, bytes, cursor.offset);
        },
        else => {
            var result = makeBase(address, opcode, .recognized_unimplemented, .recognized_unimplemented, "db");
            result.isa_path = "UNKNOWN";
            result.unsupported_reason = "opcode is not decoded by the PE raw bridge yet";
            try appendText(&result, "db 0x{X:0>2}", .{opcode});
            return finish(&result, bytes, cursor.offset);
        },
    }
}

pub fn validateGlobalIsaCoverage() void {
    const required = [_][]const u8{
        "ADD",
        "AND",
        "CALL",
        "CMP",
        "DEC",
        "INC",
        "JMP",
        "MOV",
        "POP",
        "PUSH",
        "RET",
        "SUB",
        "TEST",
        "XOR",
    };
    for (required) |name| {
        std.debug.assert(isa_registry.x86.findByName(name) != null);
    }
}

test "portable register arithmetic decodes through the ISA highway" {
    const add = try decodeInstruction(0x00401000, &.{ 0x01, 0xC8 });
    try std.testing.expectEqual(RawOp.binary, add.op);
    try std.testing.expectEqual(DecodeStatus.executable, add.status);
    try std.testing.expectEqual(highway.BinaryOp.add, add.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits32, add.width);

    const sbb = try decodeInstruction(0x00401002, &.{ 0x19, 0xC9 });
    try std.testing.expectEqual(RawOp.binary, sbb.op);
    try std.testing.expectEqual(highway.BinaryOp.sbb, sbb.binary_op.?);
    try std.testing.expectEqualStrings("ADC-SBB/SBB.inc", sbb.isa_path);

    const memory = try decodeInstruction(0x00401004, &.{ 0x29, 0x08 });
    try std.testing.expectEqual(RawOp.binary, memory.op);
    try std.testing.expectEqual(DecodeStatus.executable, memory.status);
    try std.testing.expectEqual(highway.BinaryOp.sub, memory.binary_op.?);

    const high_bytes = try decodeInstruction(0x00401006, &.{ 0x28, 0xE5 });
    try std.testing.expectEqual(highway.Width.bits8, high_bytes.width);
    try std.testing.expect(high_bytes.byte_register.?.high);
    try std.testing.expect(high_bytes.byte_rm_register.?.high);
}

test "raw PE decodes REP MOVS widths, segment overrides, and non-REP form" {
    const rep_dword = try decodeInstruction(0x00401000, &.{ 0xF3, 0xA5 });
    try std.testing.expectEqual(RawOp.string_movs, rep_dword.op);
    try std.testing.expectEqual(DecodeStatus.executable, rep_dword.status);
    try std.testing.expectEqual(highway.Width.bits32, rep_dword.width);
    try std.testing.expect(rep_dword.repeated);
    try std.testing.expectEqualStrings("rep movsd", rep_dword.textSlice());

    const word = try decodeInstruction(0x00401002, &.{ 0x66, 0xA5 });
    try std.testing.expectEqual(highway.Width.bits16, word.width);
    try std.testing.expect(!word.repeated);

    const source_override = try decodeInstruction(0x00401004, &.{ 0x64, 0xF2, 0xA4 });
    try std.testing.expectEqual(highway.Width.bits8, source_override.width);
    try std.testing.expectEqual(scaffold.SegmentOverride.fs, source_override.segment_override.?);
    try std.testing.expect(source_override.repeated);
}

test "raw PE decodes SCAS widths and repeat conditions" {
    const repne_byte = try decodeInstruction(0x00401000, &.{ 0xF2, 0xAE });
    try std.testing.expectEqual(RawOp.string_scas, repne_byte.op);
    try std.testing.expectEqual(highway.Width.bits8, repne_byte.width);
    try std.testing.expect(repne_byte.repeated);
    try std.testing.expect(repne_byte.repeat_not_equal);
    try std.testing.expectEqualStrings("repne scasb", repne_byte.textSlice());

    const repe_word = try decodeInstruction(0x00401002, &.{ 0xF3, 0x66, 0xAF });
    try std.testing.expectEqual(highway.Width.bits16, repe_word.width);
    try std.testing.expect(repe_word.repeated);
    try std.testing.expect(!repe_word.repeat_not_equal);
    try std.testing.expectEqualStrings("repe scasw", repe_word.textSlice());

    const single_dword = try decodeInstruction(0x00401005, &.{0xAF});
    try std.testing.expectEqual(highway.Width.bits32, single_dword.width);
    try std.testing.expect(!single_dword.repeated);
    try std.testing.expectEqualStrings("scasd", single_dword.textSlice());
}

test "raw PE decodes CLD and STD direction controls" {
    const clear = try decodeInstruction(0x00401000, &.{0xFC});
    try std.testing.expectEqual(RawOp.clear_direction_flag, clear.op);
    try std.testing.expectEqualStrings("cld", clear.textSlice());
    try std.testing.expectEqualStrings("FLAGS/CLD", clear.isa_path);

    const set = try decodeInstruction(0x00401001, &.{0xFD});
    try std.testing.expectEqual(RawOp.set_direction_flag, set.op);
    try std.testing.expectEqualStrings("std", set.textSlice());
    try std.testing.expectEqualStrings("FLAGS/STD", set.isa_path);
}

test "raw PE decodes MOVZX and MOVSX source widths separately from destinations" {
    const zero_extend_word = try decodeInstruction(0x00401000, &.{ 0x0F, 0xB7, 0x00 });
    try std.testing.expectEqual(RawOp.mov_extend, zero_extend_word.op);
    try std.testing.expectEqual(highway.Width.bits32, zero_extend_word.width);
    try std.testing.expectEqual(highway.Width.bits16, zero_extend_word.source_width);
    try std.testing.expect(!zero_extend_word.sign_extend);

    const sign_extend_byte = try decodeInstruction(0x00401003, &.{ 0x0F, 0xBE, 0xC4 });
    try std.testing.expectEqual(highway.Width.bits8, sign_extend_byte.source_width);
    try std.testing.expect(sign_extend_byte.sign_extend);
    try std.testing.expect(sign_extend_byte.byte_rm_register.?.high);

    const invalid_same_width = try decodeInstruction(0x00401006, &.{ 0x66, 0x0F, 0xBF, 0xC1 });
    try std.testing.expectEqual(DecodeStatus.recognized_unimplemented, invalid_same_width.status);
}

test "raw PE decodes accumulator XCHG register forms with operand width" {
    const xchg_esp = try decodeInstruction(0x00401000, &.{0x94});
    try std.testing.expectEqual(RawOp.xchg_eax_reg, xchg_esp.op);
    try std.testing.expectEqual(Register.esp, xchg_esp.register.?);
    try std.testing.expectEqual(highway.Width.bits32, xchg_esp.width);

    const xchg_cx = try decodeInstruction(0x00401001, &.{ 0x66, 0x91 });
    try std.testing.expectEqual(Register.ecx, xchg_cx.register.?);
    try std.testing.expectEqual(highway.Width.bits16, xchg_cx.width);
}

test "raw PE decodes PUSHF and POPF with operand-size overrides" {
    const pushfd = try decodeInstruction(0x00401000, &.{0x9C});
    try std.testing.expectEqual(RawOp.push_flags, pushfd.op);
    try std.testing.expectEqual(highway.Width.bits32, pushfd.width);
    try std.testing.expectEqualStrings("PUSH/PUSHFD.inc", pushfd.isa_path);

    const popfw = try decodeInstruction(0x00401001, &.{ 0x66, 0x9D });
    try std.testing.expectEqual(RawOp.pop_flags, popfw.op);
    try std.testing.expectEqual(highway.Width.bits16, popfw.width);

    const cpuid = try decodeInstruction(0x00401003, &.{ 0x0F, 0xA2 });
    try std.testing.expectEqual(RawOp.cpuid, cpuid.op);
    try std.testing.expectEqual(DecodeStatus.executable, cpuid.status);
    try std.testing.expectEqualStrings("CPU/CPUID.inc", cpuid.isa_path);
}

test "raw PE decodes PUSHA and POPA at both operand widths" {
    const pushad = try decodeInstruction(0x00401000, &.{0x60});
    try std.testing.expectEqual(RawOp.pusha, pushad.op);
    try std.testing.expectEqual(DecodeStatus.executable, pushad.status);
    try std.testing.expectEqual(highway.Width.bits32, pushad.width);
    try std.testing.expectEqualStrings("pushad", pushad.textSlice());

    const popa = try decodeInstruction(0x00401001, &.{ 0x66, 0x61 });
    try std.testing.expectEqual(RawOp.popa, popa.op);
    try std.testing.expectEqual(DecodeStatus.executable, popa.status);
    try std.testing.expectEqual(highway.Width.bits16, popa.width);
    try std.testing.expectEqualStrings("popa", popa.textSlice());
}

test "raw PE decodes immediate byte writes to low and high legacy registers" {
    const mov_ah = try decodeInstruction(0x00401000, &.{ 0xB4, 0x7F });
    try std.testing.expectEqual(RawOp.mov_byte_reg_imm, mov_ah.op);
    try std.testing.expectEqual(DecodeStatus.executable, mov_ah.status);
    try std.testing.expectEqual(@as(u8, 0x7F), @as(u8, @truncate(mov_ah.immediate)));
    try std.testing.expect(mov_ah.byte_register.?.high);
    try std.testing.expectEqualStrings("mov ah, 0x7F", mov_ah.textSlice());
}

test "TEST register and memory forms decode as flag-only AND" {
    const reg_test = try decodeInstruction(0x00401000, &.{ 0x85, 0xC8 });
    try std.testing.expectEqual(RawOp.binary, reg_test.op);
    try std.testing.expectEqual(DecodeStatus.executable, reg_test.status);
    try std.testing.expectEqual(highway.BinaryOp.test_bits, reg_test.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits32, reg_test.width);
    try std.testing.expectEqualStrings("TEST/TEST.inc", reg_test.isa_path);

    const byte_test = try decodeInstruction(0x00401002, &.{ 0x84, 0xE5 });
    try std.testing.expectEqual(highway.Width.bits8, byte_test.width);
    try std.testing.expect(byte_test.byte_register.?.high);
    try std.testing.expect(byte_test.byte_rm_register.?.high);

    const word_test = try decodeInstruction(0x00401004, &.{ 0x66, 0x85, 0xC8 });
    try std.testing.expectEqual(highway.Width.bits16, word_test.width);

    const group3_memory = try decodeInstruction(0x00401007, &.{ 0xF6, 0x40, 0x70, 0x02 });
    try std.testing.expectEqual(RawOp.binary_immediate, group3_memory.op);
    try std.testing.expectEqual(highway.BinaryOp.test_bits, group3_memory.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits8, group3_memory.width);
    try std.testing.expectEqual(@as(u32, 2), group3_memory.immediate);
}

test "TEST accumulator-immediate forms decode with byte word and dword widths" {
    const byte_test = try decodeInstruction(0x00401000, &.{ 0xA8, 0x80 });
    try std.testing.expectEqual(RawOp.binary_immediate, byte_test.op);
    try std.testing.expectEqual(DecodeStatus.executable, byte_test.status);
    try std.testing.expectEqual(highway.BinaryOp.test_bits, byte_test.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits8, byte_test.width);
    try std.testing.expectEqual(@as(u32, 0x80), byte_test.immediate);
    try std.testing.expectEqual(@as(u8, 2), byte_test.len);

    const word_test = try decodeInstruction(0x00401002, &.{ 0x66, 0xA9, 0x02, 0x91 });
    try std.testing.expectEqual(highway.Width.bits16, word_test.width);
    try std.testing.expectEqual(@as(u32, 0x9102), word_test.immediate);
    try std.testing.expectEqual(@as(u8, 4), word_test.len);

    const dword_test = try decodeInstruction(0x00401006, &.{ 0xA9, 0x78, 0x56, 0x34, 0x12 });
    try std.testing.expectEqual(highway.Width.bits32, dword_test.width);
    try std.testing.expectEqual(@as(u32, 0x12345678), dword_test.immediate);
    try std.testing.expectEqual(@as(u8, 5), dword_test.len);
}

test "F7 Group3 decodes NEG, NOT, DIV and IDIV and marks unsupported extensions" {
    const word_test = try decodeInstruction(0x00401000, &.{ 0x66, 0xF7, 0x45, 0x0C, 0x00, 0x01 });
    try std.testing.expectEqual(RawOp.binary_immediate, word_test.op);
    try std.testing.expectEqual(DecodeStatus.executable, word_test.status);
    try std.testing.expectEqual(highway.BinaryOp.test_bits, word_test.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits16, word_test.width);
    try std.testing.expectEqual(@as(u32, 0x100), word_test.immediate);
    try std.testing.expectEqual(@as(u8, 6), word_test.len);

    const neg_esi = try decodeInstruction(0x00401000, &.{ 0xF7, 0xDE });
    try std.testing.expectEqual(RawOp.group3_neg, neg_esi.op);
    try std.testing.expectEqual(DecodeStatus.executable, neg_esi.status);
    try std.testing.expectEqualStrings("NEG/NEG.inc", neg_esi.isa_path);

    const neg_memory = try decodeInstruction(0x00401002, &.{ 0xF7, 0x18 });
    try std.testing.expectEqual(RawOp.group3_neg, neg_memory.op);
    try std.testing.expectEqual(DecodeStatus.executable, neg_memory.status);

    const neg_word = try decodeInstruction(0x00401004, &.{ 0x66, 0xF7, 0xD8 });
    try std.testing.expectEqual(RawOp.group3_neg, neg_word.op);
    try std.testing.expectEqual(highway.Width.bits16, neg_word.width);

    const not_esi = try decodeInstruction(0x00401008, &.{ 0xF7, 0xD6 });
    try std.testing.expectEqual(RawOp.group3_not, not_esi.op);
    try std.testing.expectEqual(DecodeStatus.executable, not_esi.status);
    try std.testing.expectEqualStrings("NOT/NOT.inc", not_esi.isa_path);

    const not_word = try decodeInstruction(0x00401002, &.{ 0x66, 0xF7, 0x10 });
    try std.testing.expectEqual(RawOp.group3_not, not_word.op);
    try std.testing.expectEqual(highway.Width.bits16, not_word.width);

    const multiply = try decodeInstruction(0x00401005, &.{ 0xF7, 0xE6 });
    try std.testing.expectEqual(RawOp.recognized_unimplemented, multiply.op);
    try std.testing.expectEqual(DecodeStatus.recognized_unimplemented, multiply.status);

    const divide = try decodeInstruction(0x00401007, &.{ 0xF7, 0xF1 });
    try std.testing.expectEqual(RawOp.group3_div, divide.op);
    try std.testing.expectEqual(DecodeStatus.executable, divide.status);
    try std.testing.expectEqual(highway.Width.bits32, divide.width);

    const divide_word = try decodeInstruction(0x00401009, &.{ 0x66, 0xF7, 0xF1 });
    try std.testing.expectEqual(RawOp.group3_div, divide_word.op);
    try std.testing.expectEqual(highway.Width.bits16, divide_word.width);

    const signed_divide = try decodeInstruction(0x0040100C, &.{ 0xF7, 0xF9 });
    try std.testing.expectEqual(RawOp.group3_idiv, signed_divide.op);
    try std.testing.expectEqual(DecodeStatus.executable, signed_divide.status);
    try std.testing.expectEqual(highway.Width.bits32, signed_divide.width);
    try std.testing.expectEqualStrings("idiv", signed_divide.mnemonic);
    try std.testing.expectEqualStrings("DIV/DIV.inc", signed_divide.isa_path);

    const signed_divide_word = try decodeInstruction(0x0040100E, &.{ 0x66, 0xF7, 0xF9 });
    try std.testing.expectEqual(RawOp.group3_idiv, signed_divide_word.op);
    try std.testing.expectEqual(highway.Width.bits16, signed_divide_word.width);
}

test "F6 Group3 decodes byte NEG and NOT, including high-byte registers" {
    const neg_ah = try decodeInstruction(0x00401000, &.{ 0xF6, 0xDC });
    try std.testing.expectEqual(RawOp.group3_neg, neg_ah.op);
    try std.testing.expectEqual(DecodeStatus.executable, neg_ah.status);
    try std.testing.expectEqual(highway.Width.bits8, neg_ah.width);
    try std.testing.expect(neg_ah.byte_rm_register.?.high);
    try std.testing.expectEqualStrings("ah", neg_ah.textSlice()[4..]);
    try std.testing.expectEqualStrings("NEG/NEG.inc", neg_ah.isa_path);

    const not_cl = try decodeInstruction(0x00401002, &.{ 0xF6, 0xD1 });
    try std.testing.expectEqual(RawOp.group3_not, not_cl.op);
    try std.testing.expectEqual(DecodeStatus.executable, not_cl.status);
    try std.testing.expectEqualStrings("NOT/NOT.inc", not_cl.isa_path);

    const neg_memory = try decodeInstruction(0x00401004, &.{ 0xF6, 0x58, 0x04 });
    try std.testing.expectEqual(RawOp.group3_neg, neg_memory.op);
    try std.testing.expectEqual(DecodeStatus.executable, neg_memory.status);
    try std.testing.expectEqual(highway.Width.bits8, neg_memory.width);

    const multiply = try decodeInstruction(0x00401007, &.{ 0xF6, 0xE1 });
    try std.testing.expectEqual(RawOp.recognized_unimplemented, multiply.op);
    try std.testing.expectEqual(DecodeStatus.recognized_unimplemented, multiply.status);
}

test "LEAVE decodes with stack operand width" {
    const leave32 = try decodeInstruction(0x00401000, &.{0xC9});
    try std.testing.expectEqual(RawOp.leave, leave32.op);
    try std.testing.expectEqual(highway.Width.bits32, leave32.width);
    try std.testing.expectEqualStrings("CALL-RET/LEAVE.inc", leave32.isa_path);

    const leave16 = try decodeInstruction(0x00401001, &.{ 0x66, 0xC9 });
    try std.testing.expectEqual(RawOp.leave, leave16.op);
    try std.testing.expectEqual(highway.Width.bits16, leave16.width);
}

test "CWD and CDQ decode with accumulator width selected by operand-size prefix" {
    const cdq = try decodeInstruction(0x00401000, &.{0x99});
    try std.testing.expectEqual(RawOp.sign_extend_accumulator, cdq.op);
    try std.testing.expectEqual(DecodeStatus.executable, cdq.status);
    try std.testing.expectEqual(highway.Width.bits32, cdq.width);
    try std.testing.expectEqualStrings("cdq", cdq.mnemonic);
    try std.testing.expectEqual(@as(u8, 1), cdq.len);

    const cwd = try decodeInstruction(0x00401001, &.{ 0x66, 0x99 });
    try std.testing.expectEqual(RawOp.sign_extend_accumulator, cwd.op);
    try std.testing.expectEqual(DecodeStatus.executable, cwd.status);
    try std.testing.expectEqual(highway.Width.bits16, cwd.width);
    try std.testing.expectEqualStrings("cwd", cwd.mnemonic);
    try std.testing.expectEqual(@as(u8, 2), cwd.len);
}

test "RET immediate decodes its fixed 16-bit stack adjustment" {
    const plain = try decodeInstruction(0x00401000, &.{0xC3});
    try std.testing.expectEqual(RawOp.ret, plain.op);
    try std.testing.expectEqual(@as(u32, 0), plain.immediate);

    const cleaned = try decodeInstruction(0x00401001, &.{ 0xC2, 0x08, 0x00 });
    try std.testing.expectEqual(RawOp.ret, cleaned.op);
    try std.testing.expectEqual(DecodeStatus.executable, cleaned.status);
    try std.testing.expectEqual(@as(u32, 8), cleaned.immediate);
    try std.testing.expectEqual(@as(u8, 3), cleaned.len);
}

test "0F AF decodes two-operand signed multiply at selected width" {
    const dword = try decodeInstruction(0x00401000, &.{ 0x0F, 0xAF, 0xC1 });
    try std.testing.expectEqual(RawOp.imul_rm, dword.op);
    try std.testing.expectEqual(DecodeStatus.executable, dword.status);
    try std.testing.expectEqual(Register.eax, dword.register.?);
    try std.testing.expectEqual(highway.Width.bits32, dword.width);

    const word = try decodeInstruction(0x00401003, &.{ 0x66, 0x0F, 0xAF, 0xC1 });
    try std.testing.expectEqual(RawOp.imul_rm, word.op);
    try std.testing.expectEqual(highway.Width.bits16, word.width);
}

test "69 and 6B decode three-operand signed multiply and sign-extend imm8" {
    const dword = try decodeInstruction(0x00401000, &.{ 0x6B, 0xC1, 0xFE });
    try std.testing.expectEqual(RawOp.imul_immediate, dword.op);
    try std.testing.expectEqual(DecodeStatus.executable, dword.status);
    try std.testing.expectEqual(Register.eax, dword.register.?);
    try std.testing.expectEqual(Rm32{ .reg = .ecx }, dword.operand.?);
    try std.testing.expectEqual(highway.Width.bits32, dword.width);
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFE), dword.immediate);

    const word = try decodeInstruction(0x00401003, &.{ 0x66, 0x69, 0xC1, 0xFE, 0xFF });
    try std.testing.expectEqual(RawOp.imul_immediate, word.op);
    try std.testing.expectEqual(highway.Width.bits16, word.width);
    try std.testing.expectEqual(@as(u32, 0xFFFE), word.immediate);
}

test "accumulator-immediate ALU opcodes decode operation and operand width" {
    const add_dword = try decodeInstruction(0x00401000, &.{ 0x05, 0x34, 0x12, 0x00, 0x00 });
    try std.testing.expectEqual(RawOp.binary_immediate, add_dword.op);
    try std.testing.expectEqual(highway.BinaryOp.add, add_dword.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits32, add_dword.width);
    try std.testing.expectEqual(@as(u32, 0x1234), add_dword.immediate);

    const sub_byte = try decodeInstruction(0x00401005, &.{ 0x2C, 0x07 });
    try std.testing.expectEqual(highway.BinaryOp.sub, sub_byte.binary_op.?);
    try std.testing.expectEqual(highway.Width.bits8, sub_byte.width);
    try std.testing.expectEqual(@as(u32, 7), sub_byte.immediate);
}

test "FS segment prefixes remain attached to explicit memory operands" {
    const push_exception_list = try decodeInstruction(0x00401000, &.{ 0x64, 0xFF, 0x35, 0, 0, 0, 0 });
    try std.testing.expectEqual(RawOp.group5_push, push_exception_list.op);
    try std.testing.expectEqual(SegmentOverride.fs, push_exception_list.segment_override.?);

    const set_exception_list = try decodeInstruction(0x00401007, &.{ 0x64, 0xA3, 0, 0, 0, 0 });
    try std.testing.expectEqual(RawOp.mov_rm, set_exception_list.op);
    try std.testing.expectEqual(SegmentOverride.fs, set_exception_list.segment_override.?);
}

test "C6 and C7 decode MOV immediate destination widths" {
    const byte_mov = try decodeInstruction(0x00401000, &.{ 0xC6, 0x45, 0xFC, 0x7A });
    try std.testing.expectEqual(RawOp.mov_immediate_rm, byte_mov.op);
    try std.testing.expectEqual(highway.Width.bits8, byte_mov.width);
    try std.testing.expectEqual(@as(u32, 0x7A), byte_mov.immediate);

    const dword_mov = try decodeInstruction(0x00401004, &.{ 0xC7, 0x45, 0xFC, 0xFE, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(RawOp.mov_immediate_rm, dword_mov.op);
    try std.testing.expectEqual(highway.Width.bits32, dword_mov.width);
    try std.testing.expectEqual(std.math.maxInt(u32) - 1, dword_mov.immediate);
}

test "accumulator MOV moffs forms decode with direction and width" {
    const load32 = try decodeInstruction(0x00401000, &.{ 0xA1, 0x00, 0x20, 0x40, 0x00 });
    try std.testing.expectEqual(RawOp.mov_rm, load32.op);
    try std.testing.expectEqual(DecodeStatus.executable, load32.status);
    try std.testing.expectEqual(highway.Width.bits32, load32.width);
    try std.testing.expectEqualStrings("mov eax, [0x00402000]", load32.textSlice());
    switch (load32.operand.?) {
        .mem => |mem| try std.testing.expectEqual(@as(u32, 0x00402000), mem.absolute.?),
        .reg => return error.ExpectedMemoryOperand,
    }

    const store8 = try decodeInstruction(0x00401005, &.{ 0xA2, 0x01, 0x20, 0x40, 0x00 });
    try std.testing.expectEqual(RawOp.mov_rm, store8.op);
    try std.testing.expectEqual(highway.Width.bits8, store8.width);
    try std.testing.expectEqualStrings("mov [0x00402001], al", store8.textSlice());
}

test "short conditional branches retain their condition and signed target" {
    const branch = try decodeInstruction(0x00401000, &.{ 0x74, 0xFE });
    try std.testing.expectEqual(RawOp.jcc_rel, branch.op);
    try std.testing.expectEqual(DecodeStatus.executable, branch.status);
    try std.testing.expectEqual(ControlKind.conditional_jump, branch.control);
    try std.testing.expectEqual(@as(u4, 4), branch.condition);
    try std.testing.expectEqual(@as(u32, 0x00401000), branch.target);
    try std.testing.expectEqualStrings("je 0x00401000", branch.textSlice());
}

test "LEA decodes a SIB effective address without a memory access" {
    const lea_inst = try decodeInstruction(0x00401000, &.{ 0x8D, 0x74, 0x24, 0x10 });
    try std.testing.expectEqual(RawOp.lea, lea_inst.op);
    try std.testing.expectEqual(DecodeStatus.executable, lea_inst.status);
    try std.testing.expectEqual(Register.esi, lea_inst.register.?);
    try std.testing.expectEqualStrings("lea esi, [esp+0x10]", lea_inst.textSlice());
}

test "Group1 immediates and LOCK decode through shared classification" {
    const locked = try decodeInstruction(0x00402000, &.{ 0xF0, 0x83, 0x28, 0x01 });
    try std.testing.expectEqual(RawOp.binary_immediate, locked.op);
    try std.testing.expectEqual(highway.BinaryOp.sub, locked.binary_op.?);
    try std.testing.expect(locked.locked);
    try std.testing.expectEqual(@as(u32, 1), locked.immediate);
}

test "Group2 decodes immediate, CL, and signed arithmetic shifts" {
    const shl = try decodeInstruction(0x00401000, &.{ 0xC1, 0xE0, 0x08 });
    try std.testing.expectEqual(RawOp.group2_shift, shl.op);
    try std.testing.expectEqual(DecodeStatus.executable, shl.status);
    try std.testing.expectEqualStrings("shl eax, 8", shl.textSlice());
    try std.testing.expectEqual(@as(u32, 8), shl.immediate);
    try std.testing.expect(!shl.shift_from_cl);

    const sar = try decodeInstruction(0x00401003, &.{ 0xC1, 0x7D, 0x08, 0x08 });
    try std.testing.expectEqual(RawOp.group2_shift, sar.op);
    try std.testing.expectEqualStrings("sar [ebp+0x8], 8", sar.textSlice());
    try std.testing.expectEqual(@as(u3, 7), sar.modrm.?.reg);

    const rcl = try decodeInstruction(0x00401007, &.{ 0xD3, 0xD0 });
    try std.testing.expectEqual(RawOp.group2_shift, rcl.op);
    try std.testing.expectEqualStrings("rcl eax, cl", rcl.textSlice());
    try std.testing.expect(rcl.shift_from_cl);
}

test "SETcc decodes condition codes and byte register or memory destinations" {
    const set_equal = try decodeInstruction(0x00401000, &.{ 0x0F, 0x94, 0xC0 });
    try std.testing.expectEqual(RawOp.setcc, set_equal.op);
    try std.testing.expectEqual(DecodeStatus.executable, set_equal.status);
    try std.testing.expectEqual(@as(u4, 4), set_equal.condition);
    try std.testing.expectEqualStrings("sete al", set_equal.textSlice());

    const set_not_equal = try decodeInstruction(0x00401003, &.{ 0x0F, 0x95, 0x45, 0xFC });
    try std.testing.expectEqual(RawOp.setcc, set_not_equal.op);
    try std.testing.expectEqualStrings("setne [ebp-0x4]", set_not_equal.textSlice());
    try std.testing.expectEqual(highway.Width.bits8, set_not_equal.width);
}

test "near conditional branches decode two-byte rel32 encodings" {
    const branch = try decodeInstruction(0x00401000, &.{ 0x0F, 0x84, 0x05, 0, 0, 0 });
    try std.testing.expectEqual(RawOp.jcc_rel, branch.op);
    try std.testing.expectEqual(ControlKind.conditional_jump, branch.control);
    try std.testing.expectEqual(@as(u4, 4), branch.condition);
    try std.testing.expectEqual(@as(u32, 0x0040100B), branch.target);
    try std.testing.expectEqual(@as(u8, 6), branch.len);
}

test "legacy INC and DEC register opcodes retain operand width" {
    const increment = try decodeInstruction(0x00401000, &.{0x40});
    try std.testing.expectEqual(RawOp.inc_reg, increment.op);
    try std.testing.expectEqual(Register.eax, increment.register.?);
    try std.testing.expectEqual(highway.Width.bits32, increment.width);

    const decrement = try decodeInstruction(0x00401001, &.{ 0x66, 0x4F });
    try std.testing.expectEqual(RawOp.dec_reg, decrement.op);
    try std.testing.expectEqual(Register.edi, decrement.register.?);
    try std.testing.expectEqual(highway.Width.bits16, decrement.width);
}

test "Group5 INC and DEC memory operands decode as executable" {
    const increment = try decodeInstruction(0x00401000, &.{ 0xFF, 0x46, 0x08 });
    try std.testing.expectEqual(RawOp.group5_inc, increment.op);
    try std.testing.expectEqual(DecodeStatus.executable, increment.status);
    try std.testing.expectEqual(highway.Width.bits32, increment.width);
    try std.testing.expectEqualStrings("inc [esi+0x8]", increment.textSlice());

    const decrement = try decodeInstruction(0x00401003, &.{ 0x66, 0xFF, 0x4D, 0xFC });
    try std.testing.expectEqual(RawOp.group5_dec, decrement.op);
    try std.testing.expectEqual(DecodeStatus.executable, decrement.status);
    try std.testing.expectEqual(highway.Width.bits16, decrement.width);
}

test "Group4 byte INC and DEC decode high-byte registers and memory" {
    const decrement = try decodeInstruction(0x00401000, &.{ 0xFE, 0xCC });
    try std.testing.expectEqual(RawOp.group4_dec, decrement.op);
    try std.testing.expectEqual(DecodeStatus.executable, decrement.status);
    try std.testing.expectEqual(highway.Width.bits8, decrement.width);
    try std.testing.expectEqualStrings("dec ah", decrement.textSlice());
    try std.testing.expect(decrement.byte_rm_register.?.high);

    const increment = try decodeInstruction(0x00401002, &.{ 0xFE, 0x46, 0x08 });
    try std.testing.expectEqual(RawOp.group4_inc, increment.op);
    try std.testing.expectEqual(DecodeStatus.executable, increment.status);
    try std.testing.expectEqual(highway.Width.bits8, increment.width);
    try std.testing.expectEqualStrings("inc [esi+0x8]", increment.textSlice());
}

test "decodes Group5 absolute indirect JMP through global ISA table" {
    validateGlobalIsaCoverage();
    const bytes = [_]u8{ 0xFF, 0x25, 0x00, 0x20, 0x40, 0x00 };
    const inst = try decodeInstruction(0x0041F7A2, &bytes);
    try std.testing.expectEqual(RawOp.group5_jmp, inst.op);
    try std.testing.expectEqual(@as(u8, 6), inst.len);
    try std.testing.expectEqualStrings("jmp", inst.mnemonic);
    try std.testing.expectEqualStrings("JMP/JMP.inc", inst.isa_path);
    try std.testing.expectEqualStrings("jmp [0x00402000]", inst.textSlice());
    switch (inst.operand.?) {
        .mem => |mem| try std.testing.expectEqual(@as(u32, 0x00402000), mem.absolute.?),
        .reg => return error.ExpectedMemoryOperand,
    }
}

test "decodes Group5 absolute indirect CALL and PUSH" {
    const call_bytes = [_]u8{ 0xFF, 0x15, 0x08, 0x20, 0x40, 0x00 };
    const call = try decodeInstruction(0x00401000, &call_bytes);
    try std.testing.expectEqual(RawOp.group5_call, call.op);
    try std.testing.expectEqualStrings("CALL-RET/CALL.inc", call.isa_path);

    const push_bytes = [_]u8{ 0xFF, 0x35, 0x0C, 0x20, 0x40, 0x00 };
    const push = try decodeInstruction(0x00401006, &push_bytes);
    try std.testing.expectEqual(RawOp.group5_push, push.op);
    try std.testing.expectEqualStrings("PUSH/PUSH.inc", push.isa_path);
}

test "x87 PE startup subset decodes memory and register forms with full lengths" {
    const fld_qword = try decodeInstruction(0x1000, &.{ 0xDD, 0x05, 0x70, 0xC4, 0x00, 0x10 });
    try std.testing.expectEqual(RawOp.x87, fld_qword.op);
    try std.testing.expectEqual(DecodeStatus.executable, fld_qword.status);
    try std.testing.expectEqual(@as(u8, 6), fld_qword.len);
    try std.testing.expectEqualStrings("fld", fld_qword.mnemonic);
    try std.testing.expectEqual(@as(u3, 0), fld_qword.modrm.?.reg);

    const fdiv = try decodeInstruction(0x1006, &.{ 0xDC, 0x75, 0xF0 });
    try std.testing.expectEqual(RawOp.x87, fdiv.op);
    try std.testing.expectEqual(DecodeStatus.executable, fdiv.status);
    try std.testing.expectEqual(@as(u8, 3), fdiv.len);
    try std.testing.expectEqualStrings("fdiv", fdiv.mnemonic);

    const fnstsw_ax = try decodeInstruction(0x1009, &.{ 0xDF, 0xE0 });
    try std.testing.expectEqual(RawOp.x87, fnstsw_ax.op);
    try std.testing.expectEqual(DecodeStatus.executable, fnstsw_ax.status);
    try std.testing.expectEqualStrings("fnstsw", fnstsw_ax.mnemonic);

    const unimplemented = try decodeInstruction(0x100B, &.{ 0xD8, 0xC0 });
    try std.testing.expectEqual(RawOp.recognized_unimplemented, unimplemented.op);
    try std.testing.expectEqual(DecodeStatus.recognized_unimplemented, unimplemented.status);
    try std.testing.expectEqual(@as(u8, 2), unimplemented.len);

    const fwait = try decodeInstruction(0x100D, &.{0x9B});
    try std.testing.expectEqual(RawOp.nop, fwait.op);
    try std.testing.expectEqual(DecodeStatus.executable, fwait.status);
    try std.testing.expectEqual(@as(u8, 1), fwait.len);
    try std.testing.expectEqualStrings("fwait", fwait.mnemonic);

    const fnstcw = try decodeInstruction(0x100E, &.{ 0xD9, 0x7D, 0x20 });
    try std.testing.expectEqual(RawOp.x87, fnstcw.op);
    try std.testing.expectEqual(DecodeStatus.executable, fnstcw.status);
    try std.testing.expectEqual(@as(u8, 3), fnstcw.len);
    try std.testing.expectEqualStrings("fnstcw", fnstcw.mnemonic);
}

test "SAHF decodes as an executable flag transfer" {
    const sahf = try decodeInstruction(0x1000, &.{0x9E});
    try std.testing.expectEqual(RawOp.sahf, sahf.op);
    try std.testing.expectEqual(DecodeStatus.executable, sahf.status);
    try std.testing.expectEqual(@as(u8, 1), sahf.len);
    try std.testing.expectEqualStrings("sahf", sahf.mnemonic);
}

test "operand-size override MOV immediate consumes a 16-bit immediate" {
    const decoded = try decodeInstruction(0x00401000, &.{ 0x66, 0xB8, 0x01, 0x00, 0xF6, 0xC2, 0x08 });
    try std.testing.expectEqual(RawOp.mov_reg_imm, decoded.op);
    try std.testing.expectEqual(DecodeStatus.executable, decoded.status);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);
    try std.testing.expectEqual(highway.Width.bits16, decoded.width);
    try std.testing.expectEqual(@as(u32, 1), decoded.immediate);
    try std.testing.expectEqualStrings("ax", reg16Name(decoded.register.?));
}
