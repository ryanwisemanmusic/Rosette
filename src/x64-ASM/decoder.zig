const std = @import("std");
const cpu_state = @import("cpu_state.zig");
const flags = @import("flags.zig");
const bit_test = @import("bit_test.zig");
const isa_registry = @import("isa_registry");
const runtime_abi = @import("runtime_abi_handshake");
pub const highway = @import("isa_highway");
pub const capabilities = @import("capabilities.zig");

pub const OperandSize = flags.OperandSize;
pub const Condition = flags.Condition;
pub const RegId = cpu_state.RegId;
pub const Regs = cpu_state.Regs;
pub const Segment = cpu_state.Segment;
pub const SegmentState = cpu_state.SegmentState;

pub const ExecutionMode = enum {
    long64,
    compatibility,
    protected,
};

pub const MemoryReferenceKind = enum {
    instruction_fetch,
    stack,
    explicit_data,
    string_source,
    string_destination,
};

pub const RFL_CF = flags.RFL_CF;
pub const RFL_PF = flags.RFL_PF;
pub const RFL_AF = flags.RFL_AF;
pub const RFL_ZF = flags.RFL_ZF;
pub const RFL_SF = flags.RFL_SF;
pub const RFL_OF = flags.RFL_OF;
pub const bitTestAndResetRegister = bit_test.resetRegister;
pub const bitTestMemoryOperand = bit_test.memoryOperand;

/// Prefix state shared by every legacy x86-64 instruction family. Keeping
/// this in the decoder prevents each opcode handler from growing its own
/// subtly different prefix loop.
pub const LegacyPrefixes = struct {
    len: usize = 0,
    rex: u8 = 0,
    has_rex: bool = false,
    operand_size_override: bool = false,
    address_size_override: bool = false,
    lock: bool = false,
    repeat: enum { none, repne, rep } = .none,
    segment_override: ?Segment = null,

    pub fn rexW(self: LegacyPrefixes) bool {
        return self.rex & 0x08 != 0;
    }

    pub fn rexR(self: LegacyPrefixes) bool {
        return self.rex & 0x04 != 0;
    }

    pub fn rexX(self: LegacyPrefixes) bool {
        return self.rex & 0x02 != 0;
    }

    pub fn rexB(self: LegacyPrefixes) bool {
        return self.rex & 0x01 != 0;
    }
};

pub const VexPrefix = struct {
    len: usize = 0,
    is_2byte: bool = false,
    has_66_prefix: bool = false,
    has_f2_prefix: bool = false,
    has_f3_prefix: bool = false,
    w: bool = false,
    r: bool = false,
    // Two-byte VEX has no X/B fields, so both implicit extension bits are
    // clear. Three-byte VEX decoding overwrites them from the inverted prefix
    // fields below.
    x: bool = false,
    b: bool = false,
    l: bool = false,
    vvvv: u4 = 0,
    m: u5 = 1,
};

/// EVEX prefix state (4-byte 62 [P0] [P1] [P2]) for AVX-512 instructions.
/// The EVEX prefix extends VEX with opmask registers (k0-k7), zero/merge
/// masking, broadcast/embedded rounding, and 5-bit register addressing.
pub const EvexPrefix = struct {
    len: usize = 4,
    has_66_prefix: bool = false,
    has_f2_prefix: bool = false,
    has_f3_prefix: bool = false,
    w: bool = false,
    r: bool = true,
    x: bool = true,
    b: bool = true,
    r_prime: bool = true, // R' from P0 bit 4 (high bit of ModRM.reg)
    v_prime: bool = true, // V' from P2 bit 3 (high bit of vvvv)
    vvvv: u4 = 0,
    z: bool = false, // zero-masking (P2 bit 7)
    vector_length: u2 = 0, // L'L: 0=128, 1=256, 2=512, 3=reserved
    broadcast: bool = false, // b flag (P2 bit 4)
    opmask: u3 = 0, // aaa field (P2 bits 2-0)
    m: u2 = 0, // opcode map (P0 bits 1-0): 0=0F, 1=0F38, 2=0F3A
};

pub fn decodeLegacyPrefixes(bytes: []const u8) LegacyPrefixes {
    var result = LegacyPrefixes{};
    while (result.len < bytes.len and result.len < 15) {
        const byte = bytes[result.len];
        switch (byte) {
            0x66 => result.operand_size_override = true,
            0x67 => result.address_size_override = true,
            0xF0 => result.lock = true,
            0xF2 => result.repeat = .repne,
            0xF3 => result.repeat = .rep,
            0x26 => result.segment_override = .es,
            0x2E => result.segment_override = .cs,
            0x36 => result.segment_override = .ss,
            0x3E => result.segment_override = .ds,
            0x64 => result.segment_override = .fs,
            0x65 => result.segment_override = .gs,
            0x40...0x4F => {
                result.rex = byte;
                result.has_rex = true;
            },
            else => break,
        }
        result.len += 1;
    }
    return result;
}

pub fn decodeVexPrefix(bytes: []const u8) ?VexPrefix {
    if (bytes.len == 0) return null;
    var result = VexPrefix{};
    var pos: usize = 0;

    // Check for 2-byte VEX (C5)
    if (bytes[pos] == 0xC5) {
        result.is_2byte = true;
        pos += 1;
        if (pos >= bytes.len) return null;
        const byte = bytes[pos];
        result.r = (byte & 0x80) == 0;
        result.l = (byte & 0x04) != 0;
        result.vvvv = ~@as(u4, @truncate((byte >> 3) & 0xF));
        result.m = 1; // 2-byte VEX implies m-mmmm = 1
        result.has_66_prefix = (byte & 0x03) == 1;
        result.has_f3_prefix = (byte & 0x03) == 2;
        result.has_f2_prefix = (byte & 0x03) == 3;
        result.len = 2;
        return result;
    }

    // Check for 3-byte VEX (C4)
    if (bytes[pos] == 0xC4) {
        pos += 1;
        if (pos + 1 >= bytes.len) return null;
        const byte1 = bytes[pos];
        const byte2 = bytes[pos + 1];
        result.r = (byte1 & 0x80) == 0;
        result.x = (byte1 & 0x40) == 0;
        result.b = (byte1 & 0x20) == 0;
        result.m = @as(u5, @truncate(byte1 & 0x1F));
        result.w = (byte2 & 0x80) != 0;
        result.vvvv = ~@as(u4, @truncate((byte2 >> 3) & 0xF));
        result.l = (byte2 & 0x04) != 0;
        result.has_66_prefix = (byte2 & 0x03) == 1;
        result.has_f3_prefix = (byte2 & 0x03) == 2;
        result.has_f2_prefix = (byte2 & 0x03) == 3;
        result.len = 3;
        return result;
    }

    return null;
}

/// Decode the 4-byte EVEX prefix (starting with 0x62). Returns null if the
/// bytes do not begin with a valid EVEX prefix. The returned EvexPrefix
/// carries mask/rounding/broadcast state for AVX-512 execution.
pub fn decodeEvexPrefix(bytes: []const u8) ?EvexPrefix {
    if (bytes.len < 4) return null;
    if (bytes[0] != 0x62) return null;

    var result = EvexPrefix{};

    // P0 (byte 1): R, X, B, R', 0, 0, m, m
    const p0 = bytes[1];
    result.r = (p0 & 0x80) == 0;
    result.x = (p0 & 0x40) == 0;
    result.b = (p0 & 0x20) == 0;
    result.r_prime = (p0 & 0x10) != 0;
    // bits 3-2 are reserved (must be 0)
    result.m = @truncate(p0 & 0x03);

    // P1 (byte 2): W, v, v, v, v, 1, pp, pp
    const p1 = bytes[2];
    result.w = (p1 & 0x80) != 0;
    result.vvvv = ~@as(u4, @truncate((p1 >> 3) & 0x0F));
    // bit 2 is always 1 in valid EVEX
    const pp = p1 & 0x03;
    result.has_66_prefix = pp == 1;
    result.has_f3_prefix = pp == 2;
    result.has_f2_prefix = pp == 3;

    // P2 (byte 3): z, L', L, b, V', a, a, a
    const p2 = bytes[3];
    result.z = (p2 & 0x80) != 0;
    result.vector_length = @truncate((p2 >> 5) & 0x03);
    result.broadcast = (p2 & 0x10) != 0;
    result.v_prime = (p2 & 0x08) != 0;
    result.opmask = @truncate(p2 & 0x07);

    result.len = 4;
    return result;
}

pub const RegisterOperand = struct {
    id: RegId,
    high8: bool = false,
};

pub const MemoryOperand = struct {
    displacement: u64 = 0,
    has_index: bool = false,
    index_reg: RegId = .al_ax_eax_rax,
    scale: u2 = 0,
    has_base: bool = false,
    base_reg: RegId = .al_ax_eax_rax,
    rip_relative: bool = false,
    segment: Segment = .ds,
};

pub const RmOperand = union(enum) {
    register: RegisterOperand,
    memory: MemoryOperand,
};

pub const DecodedModRm = struct {
    reg: RegisterOperand,
    rm: RmOperand,
    group: u3,
};

fn registerId(code: u8, extended: bool) RegId {
    const value: u4 = @as(u4, @truncate(code)) | if (extended) @as(u4, 8) else @as(u4, 0);
    return @enumFromInt(value);
}

/// Decodes the otherwise ambiguous 8-bit register codes 4...7. Without a
/// REX prefix they name AH/CH/DH/BH; with any REX prefix they name
/// SPL/BPL/SIL/DIL. The old decoder discarded this distinction.
pub fn decodeRegister(code: u8, extended: bool, byte_operand: bool, has_rex: bool) RegisterOperand {
    if (byte_operand and !has_rex and !extended and code >= 4 and code <= 7) {
        return .{ .id = registerId(code - 4, false), .high8 = true };
    }
    return .{ .id = registerId(code, extended) };
}

fn signExtendDisp32(raw: u32) u64 {
    const signed: i32 = @bitCast(raw);
    return @bitCast(@as(i64, signed));
}

pub fn defaultSegment(reference_kind: MemoryReferenceKind, base: ?RegId) Segment {
    return switch (reference_kind) {
        .instruction_fetch => .cs,
        .stack => .ss,
        .string_destination => .es,
        .string_source => .ds,
        .explicit_data => if (base == .ah_sp_esp_rsp or base == .ch_bp_ebp_rbp) .ss else .ds,
    };
}

pub fn selectSegment(reference_kind: MemoryReferenceKind, base: ?RegId, override: ?Segment) Segment {
    return switch (reference_kind) {
        .instruction_fetch, .stack, .string_destination => defaultSegment(reference_kind, base),
        .explicit_data, .string_source => override orelse defaultSegment(reference_kind, base),
    };
}

pub fn segmentBase(regs: *const Regs, segment: Segment, mode: ExecutionMode) u64 {
    if (mode == .long64 and segment != .fs and segment != .gs) return 0;
    return regs.segments.get(segment).base;
}

pub fn resolveMemoryAddress(regs: *const Regs, memory: MemoryOperand, instruction_end: u64, address_size: OperandSize, mode: ExecutionMode, apply_segment: bool) u64 {
    std.debug.assert(address_size == .bits32 or address_size == .bits64);
    const offset: u64 = if (address_size == .bits32) blk: {
        var value: u32 = @truncate(memory.displacement);
        if (memory.has_index) {
            const index: u32 = @truncate(regVal(regs, memory.index_reg, .bits32));
            value +%= index << @as(u5, memory.scale);
        }
        if (memory.has_base) value +%= @truncate(regVal(regs, memory.base_reg, .bits32));
        if (memory.rip_relative) value +%= @truncate(instruction_end);
        break :blk value;
    } else blk: {
        var value = memory.displacement;
        if (memory.has_index) value +%= regVal(regs, memory.index_reg, .bits64) << @as(u6, memory.scale);
        if (memory.has_base) value +%= regVal(regs, memory.base_reg, .bits64);
        if (memory.rip_relative) value +%= instruction_end;
        break :blk value;
    };
    return offset +% if (apply_segment) segmentBase(regs, memory.segment, mode) else 0;
}

fn applyDefaultSegment(memory: *MemoryOperand, prefixes: LegacyPrefixes) void {
    const base: ?RegId = if (memory.has_base) memory.base_reg else null;
    memory.segment = selectSegment(.explicit_data, base, prefixes.segment_override);
}

pub fn decodeMemoryOperand(bytes: []const u8, pos: *usize, mode: u2, rm: u3, prefixes: LegacyPrefixes) ?MemoryOperand {
    if (rm != 4) {
        var result = MemoryOperand{
            .has_base = true,
            .base_reg = registerId(rm, prefixes.rexB()),
        };
        if (mode == 0 and rm == 5) {
            if (pos.* + 4 > bytes.len) return null;
            result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
            result.has_base = false;
            result.rip_relative = true;
            pos.* += 4;
        } else if (mode == 1) {
            if (pos.* >= bytes.len) return null;
            result.displacement = @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*]))));
            pos.* += 1;
        } else if (mode == 2) {
            if (pos.* + 4 > bytes.len) return null;
            result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
            pos.* += 4;
        }
        applyDefaultSegment(&result, prefixes);
        return result;
    }

    if (pos.* >= bytes.len) return null;
    const sib = bytes[pos.*];
    pos.* += 1;
    const base: u3 = @truncate(sib);
    const index: u3 = @truncate(sib >> 3);
    var result = MemoryOperand{
        .has_index = index != 4 or prefixes.rexX(),
        .index_reg = registerId(index, prefixes.rexX()),
        .scale = @truncate(sib >> 6),
        .has_base = !(mode == 0 and base == 5),
        .base_reg = registerId(base, prefixes.rexB()),
    };
    if (mode == 0 and base == 5) {
        if (pos.* + 4 > bytes.len) return null;
        result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    } else if (mode == 1) {
        if (pos.* >= bytes.len) return null;
        result.displacement = @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*]))));
        pos.* += 1;
    } else if (mode == 2) {
        if (pos.* + 4 > bytes.len) return null;
        result.displacement = signExtendDisp32(std.mem.readInt(u32, bytes[pos.*..][0..4], .little));
        pos.* += 4;
    }
    applyDefaultSegment(&result, prefixes);
    return result;
}

/// Universally decodes the ModR/M byte and any following SIB/displacement.
/// Instruction handlers consume this structure instead of reimplementing
/// addressing rules for every mnemonic.
pub fn decodeModRm(bytes: []const u8, pos: *usize, prefixes: LegacyPrefixes, byte_operand: bool) ?DecodedModRm {
    if (pos.* >= bytes.len) return null;
    const modrm = bytes[pos.*];
    pos.* += 1;
    const mode: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);
    const reg = decodeRegister(reg_code, prefixes.rexR(), byte_operand, prefixes.has_rex);
    const rm: RmOperand = if (mode == 3)
        .{ .register = decodeRegister(rm_code, prefixes.rexB(), byte_operand, prefixes.has_rex) }
    else
        .{ .memory = decodeMemoryOperand(bytes, pos, mode, rm_code, prefixes) orelse return null };
    return .{ .reg = reg, .rm = rm, .group = reg_code };
}

pub const applySub = flags.applySub;
pub const applySbb = flags.applySbb;
pub const applyAdd = flags.applyAdd;
pub const applyIncDec = flags.applyIncDec;
pub const applyLogic = flags.applyLogic;
pub const evalCond = flags.evalCond;
pub const regVal = cpu_state.regVal;
pub const setReg = cpu_state.setReg;

pub const BitScanKind = enum { bsf, bsr, tzcnt, lzcnt };

pub const BitScanResult = struct {
    value: u64,
    write_destination: bool,
    zero_flag: bool,
    carry_flag: ?bool,
};

pub const PopulationCountResult = struct {
    value: u64,
    rflags: u32,
};

/// Implements scalar POPCNT independently of a particular loader. Intel
/// defines OF, SF, AF, CF and PF as cleared, with ZF set only for a zero source.
pub fn populationCount(size: OperandSize, raw_source: u64, initial_rflags: u32) PopulationCountResult {
    const mask: u64 = switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
    const source = raw_source & mask;
    const status_mask = flags.RFL_CF | flags.RFL_PF | flags.RFL_AF | flags.RFL_ZF | flags.RFL_SF | flags.RFL_OF;
    var rflags = initial_rflags & ~status_mask;
    if (source == 0) rflags |= flags.RFL_ZF;
    return .{ .value = @popCount(source), .rflags = rflags };
}

pub fn bitScan(size: OperandSize, kind: BitScanKind, raw_source: u64) BitScanResult {
    const width: u7 = switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
    const mask: u64 = switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
    const source = raw_source & mask;

    return switch (kind) {
        .bsf => if (source == 0)
            .{ .value = 0, .write_destination = false, .zero_flag = true, .carry_flag = null }
        else
            .{ .value = @ctz(source), .write_destination = true, .zero_flag = false, .carry_flag = null },
        .bsr => if (source == 0)
            .{ .value = 0, .write_destination = false, .zero_flag = true, .carry_flag = null }
        else
            .{ .value = 63 - @clz(source), .write_destination = true, .zero_flag = false, .carry_flag = null },
        .tzcnt => blk: {
            const value: u64 = if (source == 0) width else @ctz(source);
            break :blk .{
                .value = value,
                .write_destination = true,
                .zero_flag = value == 0,
                .carry_flag = source == 0,
            };
        },
        .lzcnt => blk: {
            const value: u64 = if (source == 0) width else width - 1 - (63 - @clz(source));
            break :blk .{
                .value = value,
                .write_destination = true,
                .zero_flag = value == 0,
                .carry_flag = source == 0,
            };
        },
    };
}

pub fn byteSwap(size: OperandSize, value: u64) u64 {
    return switch (size) {
        .bits32 => @byteSwap(@as(u32, @truncate(value))),
        .bits64 => @byteSwap(value),
        .bits8, .bits16 => unreachable,
    };
}

pub fn crc32cAccumulator(initial: u32, source: u64, size: OperandSize) u32 {
    var crc = initial;
    var value = source;
    const byte_count: u8 = switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
    var byte_index: u8 = 0;
    while (byte_index < byte_count) : (byte_index += 1) {
        crc ^= @as(u8, @truncate(value));
        value >>= 8;
        var bit_index: u4 = 0;
        while (bit_index < 8) : (bit_index += 1) {
            crc = (crc >> 1) ^ (0x82F6_3B78 & (0 -% (crc & 1)));
        }
    }
    return crc;
}

pub const Op = enum(u16) {
    invalid,
    nop,
    cmc,
    clc,
    stc,
    fild_mem16,
    fild_mem32,
    fild_mem64,
    fld_mem32,
    fld_mem64,
    fld_mem80,
    fstp_mem80,
    fstp_mem32,
    fstp_mem64,
    fld_st,
    fstp_st,
    fxch_st,
    ffree_st,
    fninit,
    fnstsw_ax,
    fnstcw_mem16,
    fldcw_mem16,
    x87_binary,
    fucomip_st,
    // mov
    mov_mem8_reg8,
    mov_mem16_reg16,
    mov_mem32_reg32,
    mov_mem64_reg64,
    mov_reg8_mem8,
    mov_reg16_mem16,
    mov_reg32_mem32,
    mov_reg64_mem64,
    mov_reg_imm,
    mov_mem8_imm8,
    mov_mem16_imm16,
    mov_mem32_imm32,
    mov_mem64_imm32,
    mov_reg8_reg8,
    mov_reg16_reg16,
    mov_reg32_reg32,
    mov_reg64_reg64,
    add_accum_imm,
    or_accum_imm,
    adc_accum_imm,
    sbb_accum_imm,
    and_accum_imm,
    sub_accum_imm,
    xor_accum_imm,
    cmp_accum_imm,
    // add (reg, r/m) d=1
    add_reg8_mem8,
    add_reg16_mem16,
    add_reg32_mem32,
    add_reg64_mem64,
    // add (r/m, reg) d=0
    add_mem8_reg8,
    add_mem16_reg16,
    add_mem32_reg32,
    add_mem64_reg64,
    // add reg, reg
    add_reg8_reg8,
    add_reg16_reg16,
    add_reg32_reg32,
    add_reg64_reg64,
    add_reg8_imm8,
    add_reg16_imm8,
    add_reg32_imm8,
    add_reg64_imm8,
    adc_reg8_imm8,
    adc_reg16_imm8,
    adc_reg32_imm8,
    adc_reg64_imm8,
    sbb_reg8_imm8,
    add_reg16_imm32,
    add_reg32_imm32,
    add_reg64_imm32,
    add_mem8_imm8,
    add_mem16_imm8,
    add_mem32_imm8,
    add_mem64_imm8,
    adc_reg8_mem8,
    sbb_reg8_mem8,
    // sub (reg, r/m) d=1
    sub_reg8_mem8,
    sub_reg16_mem16,
    sub_reg32_mem32,
    sub_reg64_mem64,
    // sub (r/m, reg) d=0
    sub_mem8_reg8,
    sub_mem16_reg16,
    sub_mem32_reg32,
    sub_mem64_reg64,
    // sub (reg, reg) mod=3
    sub_reg8_reg8,
    sub_reg16_reg16,
    sub_reg32_reg32,
    sub_reg64_reg64,
    // sub r/m, imm8 (80 /5)
    sub_mem8_imm8,
    sub_reg8_imm8,
    sub_reg16_imm8,
    sub_reg32_imm8,
    sub_reg64_imm8,
    sub_reg16_imm32,
    sub_reg32_imm32,
    sub_reg64_imm32,
    sbb_reg8_reg8,
    sbb_reg16_reg16,
    sbb_reg32_reg32,
    sbb_reg64_reg64,
    // logical and/xor
    and_reg8_reg8,
    and_reg16_reg16,
    and_reg32_reg32,
    and_reg64_reg64,
    and_reg8_mem8,
    and_reg16_mem16,
    and_reg32_mem32,
    and_reg64_mem64,
    and_mem8_reg8,
    and_mem16_reg16,
    and_mem32_reg32,
    and_mem64_reg64,
    and_reg8_imm8,
    and_reg16_imm8,
    and_reg32_imm8,
    and_reg64_imm8,
    and_reg16_imm32,
    and_reg32_imm32,
    and_reg64_imm32,
    or_reg8_reg8,
    or_reg16_reg16,
    or_reg32_reg32,
    or_reg64_reg64,
    or_reg8_mem8,
    or_reg16_mem16,
    or_reg32_mem32,
    or_reg64_mem64,
    or_mem8_reg8,
    or_mem16_reg16,
    or_mem32_reg32,
    or_mem64_reg64,
    or_reg8_imm8,
    or_reg16_imm8,
    or_reg32_imm8,
    or_reg64_imm8,
    or_mem8_imm8,
    or_mem16_imm8,
    or_mem32_imm8,
    or_mem64_imm8,
    or_mem16_imm32,
    or_mem32_imm32,
    or_mem64_imm32,
    xor_reg8_reg8,
    xor_reg16_reg16,
    xor_reg32_reg32,
    xor_reg64_reg64,
    xor_reg8_mem8,
    xor_reg16_mem16,
    xor_reg32_mem32,
    xor_reg64_mem64,
    xor_mem8_reg8,
    xor_mem16_reg16,
    xor_mem32_reg32,
    xor_mem64_reg64,
    xor_reg8_imm8,
    xor_reg16_imm8,
    xor_reg32_imm8,
    xor_reg64_imm8,
    // shifts
    rol_reg_cl,
    rol_mem_cl,
    ror_reg_cl,
    ror_mem_cl,
    shl_reg_cl,
    shl_mem_cl,
    shr_reg_cl,
    shr_mem_cl,
    sar_reg_cl,
    sar_mem_cl,
    rol_reg_imm,
    rol_mem_imm,
    ror_reg_imm,
    ror_mem_imm,
    shl_reg_imm,
    shl_mem_imm,
    shr_reg_imm,
    shr_mem_imm,
    sar_reg_imm,
    sar_mem_imm,
    // bit scans and zero counts
    bsf_reg_reg,
    bsf_reg_mem,
    bsr_reg_reg,
    bsr_reg_mem,
    tzcnt_reg_reg,
    tzcnt_reg_mem,
    lzcnt_reg_reg,
    lzcnt_reg_mem,
    popcnt_reg_reg,
    popcnt_reg_mem,
    bswap_reg,
    crc32_reg_reg,
    crc32_reg_mem,
    // test
    test_reg8_reg8,
    test_reg16_reg16,
    test_reg32_reg32,
    test_reg64_reg64,
    test_mem8_reg8,
    test_mem16_reg16,
    test_mem32_reg32,
    test_mem64_reg64,
    test_reg8_imm8,
    test_reg16_imm16,
    test_reg32_imm32,
    test_reg64_imm32,
    test_mem8_imm8,
    test_mem16_imm16,
    test_mem32_imm32,
    test_mem64_imm32,
    neg_reg8,
    neg_reg16,
    neg_reg32,
    neg_reg64,
    neg_mem8,
    neg_mem16,
    neg_mem32,
    neg_mem64,
    not_reg8,
    not_reg16,
    not_reg32,
    not_reg64,
    not_mem8,
    not_mem16,
    not_mem32,
    not_mem64,
    // cmp r/m, r
    cmp_mem8_reg8,
    cmp_mem16_reg16,
    cmp_mem32_reg32,
    cmp_mem64_reg64,
    cmp_reg8_reg8,
    cmp_reg16_reg16,
    cmp_reg32_reg32,
    cmp_reg64_reg64,
    // cmp reg, r/m (3A/3B, d=1)
    cmp_reg8_mem8,
    cmp_reg16_mem16,
    cmp_reg32_mem32,
    cmp_reg64_mem64,
    // cmp r/m, imm8 (83 /7)
    cmp_mem8_imm8,
    cmp_mem16_imm8,
    cmp_mem32_imm8,
    cmp_mem64_imm8,
    cmp_reg8_imm8,
    cmp_reg16_imm8,
    cmp_reg32_imm8,
    cmp_reg64_imm8,
    // inc/dec
    inc_mem8,
    inc_mem16,
    inc_mem32,
    inc_mem64,
    inc_reg8,
    inc_reg16,
    inc_reg32,
    inc_reg64,
    dec_mem8,
    dec_mem16,
    dec_mem32,
    dec_mem64,
    dec_reg8,
    dec_reg16,
    dec_reg32,
    dec_reg64,
    // mul/imul/div/idiv (memory)
    mul_mem8,
    mul_mem16,
    mul_mem32,
    mul_mem64,
    imul_mem8,
    imul_mem16,
    imul_mem32,
    imul_mem64,
    div_mem8,
    div_mem16,
    div_mem32,
    div_mem64,
    idiv_mem8,
    idiv_mem16,
    idiv_mem32,
    idiv_mem64,
    // mul/imul/div/idiv (register)
    mul_reg8,
    mul_reg16,
    mul_reg32,
    mul_reg64,
    imul_reg8,
    imul_reg16,
    imul_reg32,
    imul_reg64,
    div_reg8,
    div_reg16,
    div_reg32,
    div_reg64,
    idiv_reg8,
    idiv_reg16,
    idiv_reg32,
    idiv_reg64,
    // imul r, r/m (0F AF)
    imul_reg64_mem64,
    imul_reg64_reg64,
    imul_reg32_mem32,
    imul_reg32_reg32,
    // imul r, r/m, imm8 (6B)
    imul_reg64_mem64_imm8,
    imul_reg64_reg64_imm8,
    imul_reg32_mem32_imm8,
    imul_reg32_reg32_imm8,
    // stack / calls
    call_rel32,
    ret,
    push_reg,
    push_mem64,
    push_imm,
    pop_reg,
    pop_mem64,
    lods,
    // sign extend
    cbw,
    cwde,
    cdqe,
    cwd,
    cdq,
    cqo,
    // zero/sign extend loads
    movzx_reg32_mem8,
    movzx_reg32_mem16,
    movsx_reg32_mem8,
    movsx_reg32_mem16,
    movsxd_reg64_reg32,
    movsxd_reg64_mem32,
    lea_reg_mem,
    cmovcc_reg_reg,
    cmovcc_reg_mem,
    setcc_reg8,
    setcc_mem8,
    cmpxchg_mem8_reg8,
    cmpxchg_mem16_reg16,
    cmpxchg_mem32_reg32,
    cmpxchg_mem64_reg64,
    cmpxchg_reg8_reg8,
    cmpxchg_reg16_reg16,
    cmpxchg_reg32_reg32,
    cmpxchg_reg64_reg64,
    cmpxchg8b_mem,
    cmpxchg16b_mem,
    xchg_mem32_reg32,
    xchg_mem64_reg64,
    xchg_reg32_reg32,
    xchg_reg64_reg64,
    xadd_mem8_reg8,
    xadd_mem32_reg32,
    xadd_mem64_reg64,
    xorps_xmm_xmm,
    movups_xmm_xmm,
    movups_xmm_mem,
    movups_mem_xmm,
    movaps_xmm_xmm,
    movaps_xmm_mem,
    movaps_mem_xmm,
    vmovd_xmm_reg32,
    vmovd_xmm_mem32,
    vmovd_reg32_xmm,
    vmovd_mem32_xmm,
    vmovq_xmm_reg64,
    vmovq_xmm_mem64,
    vmovq_reg64_xmm,
    vmovq_mem64_xmm,
    vpinsrb_xmm_xmm_reg32,
    vpinsrb_xmm_xmm_mem8,
    vpinsrd,
    vpinsrq,
    vpinsrw,
    vinsertps,
    vpextrb,
    vpextrw,
    vpextrd,
    vpextrq,
    vextractf128,
    vpshufb,
    vphaddw,
    vphaddd,
    vphaddsw,
    vphsubw,
    vphsubd,
    vphsubsw,
    vpshufd,
    vpmuludq,
    vpblendw,
    vpunpckhbw,
    vpunpckhwd,
    vpunpckhdq,
    vpunpcklbw,
    vpunpcklwd,
    vpunpcklqdq,
    vpunpckhqdq,
    vpslld,
    vpsllq,
    vpsllw,
    vpslldq,
    vpsrld,
    vpsrlq,
    vpsrlw,
    vpsrldq,
    vpsubb,
    vpsubd,
    vpsubq,
    vpsubw,
    vpaddb,
    vpaddd,
    vpaddq,
    vpaddw,
    vpmullw,
    vpmulld_38,
    vpcmpeqb,
    vpcmpeqw,
    vpcmpeqd,
    vpcmpeqq,
    vpcmpgtb,
    vpcmpgtw,
    vpcmpgtd,
    vpcmpgtq,
    vptest,
    pmovmskb,
    vpmovmskb,
    vpmovmskb_ymm,
    vmovmskps,
    vmovmskpd,
    vmovdqu_xmm_xmm,
    vmovdqu_xmm_mem,
    vmovdqu_mem_xmm,
    vmovdqa_xmm_xmm,
    vmovdqa_xmm_mem,
    vmovdqa_mem_xmm,
    vmovups_xmm_xmm,
    vmovups_xmm_mem,
    vmovups_mem_xmm,
    vmovaps_xmm_xmm,
    vmovaps_xmm_mem,
    vmovaps_mem_xmm,
    vmovupd_xmm_xmm,
    vmovupd_xmm_mem,
    vmovupd_mem_xmm,
    vmovapd_xmm_xmm,
    vmovapd_xmm_mem,
    vmovapd_mem_xmm,
    vmovss_xmm_mem,
    vmovss_mem_xmm,
    vmovsd_xmm_mem,
    vmovsd_mem_xmm,
    vmovlps_xmm_xmm_mem64,
    vmovlps_mem64_xmm,
    vmovlpd_xmm_xmm_mem64,
    vmovlpd_mem64_xmm,
    vmovhps_xmm_xmm_mem64,
    vmovhps_mem64_xmm,
    vmovhpd_xmm_xmm_mem64,
    vmovhpd_mem64_xmm,
    vmovhlps,
    vmovlhps,
    vmovshdup,
    vmovsldup,
    vmovddup,
    vmovdqu_ymm_ymm,
    vmovdqu_ymm_mem,
    vmovdqu_mem_ymm,
    vmovdqa_ymm_ymm,
    vmovdqa_ymm_mem,
    vmovdqa_mem_ymm,
    vmovups_ymm_ymm,
    vmovups_ymm_mem,
    vmovups_mem_ymm,
    vmovaps_ymm_ymm,
    vmovaps_ymm_mem,
    vmovaps_mem_ymm,
    vmovupd_ymm_ymm,
    vmovupd_ymm_mem,
    vmovupd_mem_ymm,
    vmovapd_ymm_ymm,
    vmovapd_ymm_mem,
    vmovapd_mem_ymm,
    vzeroupper,
    vcvtsi2ss_xmm_reg,
    vcvtsi2ss_xmm_mem,
    vcvtsi2sd_xmm_reg,
    vcvtsi2sd_xmm_mem,
    vcvtss2sd,
    vcvtsd2ss,
    vsqrtps,
    vsqrtpd,
    vsqrtss,
    vsqrtsd,
    vaddss,
    vaddsd,
    vaddps,
    vaddpd,
    vmulss,
    vmulsd,
    vmulps,
    vmulpd,
    vsubss,
    vsubsd,
    vsubps,
    vsubpd,
    vdivss,
    vdivsd,
    vdivps,
    vdivpd,
    vucomiss,
    vucomisd,
    vroundss,
    vroundsd,
    vroundps,
    vroundpd,
    vcvttss2si,
    vcvttsd2si,
    vcvtss2si,
    vcvtsd2si,
    vandps,
    vandpd,
    vandnps,
    vandnpd,
    vorps,
    vorpd,
    vxorps,
    vxorpd,
    vpor,
    vpand,
    vpandn,
    vpxor,
    vpunpckldq,
    vunpcklps,
    vunpckhps,
    vunpcklpd,
    vunpckhpd,
    vpermilpd,
    // AVX arithmetic (MIN, MAX, HADD, HSUB, RCP, RSQRT)
    vminps,
    vminpd,
    vminss,
    vminsd,
    vmaxps,
    vmaxpd,
    vmaxss,
    vmaxsd,
    vhaddps,
    vhaddpd,
    vhsubps,
    vhsubpd,
    vrcpps,
    vrsqrtps,
    // AVX2 FMA (VEX.0F38 map: 132/213/231 format)
    vfmadd132ps,
    vfmadd132pd,
    vfmadd213ps,
    vfmadd213pd,
    vfmadd231ps,
    vfmadd231pd,
    vfmsub132ps,
    vfmsub132pd,
    vfmsub213ps,
    vfmsub213pd,
    vfmsub231ps,
    vfmsub231pd,
    // VEX.0F38 FMA ADDSUB/VFMSUBADD
    vfmaddsub132ps,
    vfmaddsub132pd,
    vfmaddsub213ps,
    vfmaddsub213pd,
    vfmaddsub231ps,
    vfmaddsub231pd,
    vfmsubadd132ps,
    vfmsubadd132pd,
    vfmsubadd213ps,
    vfmsubadd213pd,
    vfmsubadd231ps,
    vfmsubadd231pd,
    // SSSE3/AVX2 integer ops (VEX.0F38 map)
    vpsignb,
    vpsignw,
    vpsignd,
    vpsrlvw,
    vpsravw,
    vpsllvw,
    vpabsb,
    vpabsw,
    vpabsd,
    vpmovsxbw,
    vpmovsxbd,
    vpmovsxbq,
    vpmovsxwd,
    vpmovsxwq,
    vpmovsxdq,
    vpmovzxbw,
    vpmovzxbd,
    vpmovzxbq,
    vpmovzxwd,
    vpmovzxwq,
    vpmovzxdq,
    vpmuldq,
    vpacksswb,
    vpackuswb,
    vpackusdw,
    vpermd,
    vpminsb,
    vpminsd,
    vpminuw,
    vpminud,
    vpmaxsb,
    vpmaxsd,
    vpmaxuw,
    vpmaxud,
    vphminposuw,
    vpsrlvd,
    vpsravd,
    vpsllvd,
    vpblendvb,
    vpalignr,
    vpermps,
    // AVX SIMD compare (VCMP)
    vcmpps,
    vcmppd,
    vcmpss,
    vcmpsd,
    // AVX512/AVX COMPUTE group (SCALE, RANGE, FIXUP)
    vscalefps,
    vscalefpd,
    vrangeps,
    vrangepd,
    vfixupimmps,
    vfixupimmpd,
    // AVX512 COMPRESS/EXPAND
    vcompressps,
    vcompresspd,
    vexpandps,
    vexpandpd,
    // AVX BROADCAST
    vbroadcastss,
    vbroadcastsd,
    vbroadcastf128,
    vbroadcasti128,
    // AVX512 PERMUTE
    vpermi2d,
    vpermi2q,
    vpermi2ps,
    vpermi2pd,
    vpermt2d,
    vpermt2q,
    vpermt2ps,
    vpermt2pd,
    // AVX512 GATHER
    vgatherdps,
    vgatherdpd,
    vgatherqps,
    vgatherqpd,
    vpgatherdd,
    vpgatherdq,
    // AVX512 SCATTER
    vscatterdps,
    vscatterdpd,
    vscatterqps,
    vscatterqpd,
    vpscatterdd,
    vpscatterdq,
    // AVX512 TERNARY LOGIC
    vpternlogd,
    vpternlogq,
    // AVX512 CONVERT
    vcvtps2ph,
    vcvtph2ps,
    vcvtne2ps2bf16,
    vcvttps2dq,
    vcvtps2dq,
    vcvtdq2ps,
    vcvtps2pd,
    vcvtpd2ps,
    // AVX512 SHUFFLE
    vshuff32x4,
    vshuff64x2,
    vshufi32x4,
    vshufi64x2,
    // AVX512 ALIGN
    valignd,
    valignq,
    // AVX512 MASK
    vpmovm2d,
    vpmovd2m,
    // AVX512 MULTISHIFT / CONFLICT
    vpmultishiftqb,
    vpconflictd,
    vpconflictq,
    // bit test and reset
    btr_reg_reg,
    btr_mem_reg,
    // conditional / unconditional jumps
    jmp_rel8,
    jcc_rel8,
    jcc_rel32,
    jmp_mem64,
    jmp_reg64,
    // syscall
    syscall,
    ud2,
    cpuid,
    xgetbv,
    call_mem64,
    call_reg64,
    hlt,
};

fn canonicalMnemonic(op: Op, buffer: *[32]u8) ?[]const u8 {
    if (op == .invalid) return null;

    const tag = @tagName(op);
    const stem = tag[0 .. std.mem.indexOfScalar(u8, tag, '_') orelse tag.len];
    const canonical = if (std.mem.eql(u8, stem, "cmovcc"))
        "cmove"
    else if (std.mem.eql(u8, stem, "setcc"))
        "sete"
    else if (std.mem.eql(u8, stem, "jcc"))
        "je"
    else if (std.mem.eql(u8, stem, "ud2"))
        "UD2"
    else
        stem;

    std.debug.assert(canonical.len <= buffer.len);
    return std.ascii.upperString(buffer[0..canonical.len], canonical);
}

test "every executable x64 decoder operation has a validated ISA ABI contract" {
    runtime_abi.isa.init();
    defer runtime_abi.isa.deinit();

    const violations_before = runtime_abi.common.violationCount();
    const validations_before = runtime_abi.common.validationCount();

    for (std.enums.values(Op)) |op| {
        var mnemonic_buffer: [32]u8 = undefined;
        const mnemonic = canonicalMnemonic(op, &mnemonic_buffer) orelse continue;
        const table = isa_registry.x86.findByName(mnemonic) orelse {
            std.debug.print("decoder operation {s} has no ISA ABI contract for {s}\n", .{ @tagName(op), mnemonic });
            return error.MissingDecoderIsaContract;
        };
        table.validate();
        isa_registry.neon.validateTable(table);
    }

    try std.testing.expect(runtime_abi.common.validationCount() > validations_before);
    try std.testing.expectEqual(violations_before, runtime_abi.common.violationCount());
}

pub const CpuidResult = capabilities.CpuidResult;

pub fn emulatedCpuid(leaf: u32, subleaf: u32) CpuidResult {
    return capabilities.cpuid(.xenia, leaf, subleaf);
}

pub fn emulatedXcr0() u64 {
    return capabilities.xcr0(.xenia);
}

test "emulated CPUID exposes a coherent AVX baseline" {
    const leaf0 = emulatedCpuid(0, 0);
    try std.testing.expectEqual(@as(u32, 7), leaf0.eax);
    try std.testing.expectEqual(@as(u32, 0x756E_6547), leaf0.ebx);

    const leaf1 = emulatedCpuid(1, 0);
    try std.testing.expect(leaf1.ecx & (@as(u32, 1) << 27) != 0);
    try std.testing.expect(leaf1.ecx & (@as(u32, 1) << 28) != 0);
    try std.testing.expectEqual(@as(u64, 0x7), emulatedXcr0());
}

test "shared byte swap preserves operand width" {
    try std.testing.expectEqual(@as(u64, 0x7856_3412), byteSwap(.bits32, 0x1234_5678));
    try std.testing.expectEqual(@as(u64, 0xEFCD_AB89_6745_2301), byteSwap(.bits64, 0x0123_4567_89AB_CDEF));
}

pub const DecodedInsn = struct {
    op: Op = .invalid,
    size: OperandSize = .bits32,
    dst_size: OperandSize = .bits32,
    dst_reg: RegId = .al_ax_eax_rax,
    src_reg: RegId = .al_ax_eax_rax,
    dst_high8: bool = false,
    src_high8: bool = false,
    addr: u64 = 0,
    imm: u64 = 0,
    len: u8 = 0,
    sib_has_index: bool = false,
    sib_index_reg: RegId = .al_ax_eax_rax,
    sib_scale: u2 = 0,
    sib_has_base: bool = false,
    sib_base_reg: RegId = .al_ax_eax_rax,
    rip_relative: bool = false,
    segment: Segment = .ds,
    has_0x67: bool = false,
    is_reg_form: bool = false,
    cond: Condition = .e,
    xmm_dst: u8 = 0,
    xmm_src: u8 = 0,
    xmm_src2: u8 = 0,
    vector_256: bool = false,
    uses_imm: bool = false,
    lock: bool = false,
    // EVEX-specific fields
    opmask: u3 = 0,
    zero_mask: bool = false,
    evex_broadcast: bool = false,
    vector_512: bool = false,
};

pub fn registerOperandValue(regs: *const Regs, operand: RegisterOperand, size: OperandSize) u64 {
    if (!operand.high8) return regVal(regs, operand.id, size);
    std.debug.assert(size == .bits8);
    return (regVal(regs, operand.id, .bits16) >> 8) & 0xFF;
}

pub fn setRegisterOperand(regs: *Regs, operand: RegisterOperand, size: OperandSize, value: u64) void {
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
fn decodeVexModRm(
    bytes: []const u8,
    pos: *usize,
    vex: VexPrefix,
) ?struct {
    dst_xmm: u8,
    src_xmm: u8,
    mod: u2,
    rm_code: u3,
    addr: u64,
    is_reg_form: bool,
} {
    if (pos.* >= bytes.len) return null;
    const modrm = bytes[pos.*];
    pos.* += 1;

    const mod: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);

    const dst_xmm: u8 = (if (vex.r) @as(u8, 8) else @as(u8, 0)) | reg_code;
    const src_xmm: u8 = (if (vex.b) @as(u8, 8) else @as(u8, 0)) | rm_code;

    var addr: u64 = undefined;
    const is_reg_form = (mod == 3);

    if (!is_reg_form) {
        const has_sib = (rm_code == 4) or (mod == 0 and rm_code == 5);
        if (has_sib) {
            if (pos.* >= bytes.len) return null;
            _ = bytes[pos.*];
            pos.* += 1;
        }

        const disp_size: u4 = switch (mod) {
            0 => if (rm_code == 5 or has_sib) @as(u4, 4) else 0,
            1 => 1,
            2 => 4,
            else => unreachable,
        };
        if (pos.* + disp_size > bytes.len) return null;
        if (disp_size == 1) {
            const disp: i8 = @bitCast(bytes[pos.*]);
            addr = @as(u64, @bitCast(@as(i64, disp)));
            pos.* += 1;
        } else if (disp_size == 4) {
            const disp: i32 = std.mem.readInt(i32, bytes[pos.*..][0..4], .little);
            addr = @as(u64, @bitCast(@as(i64, disp)));
            pos.* += 4;
        } else {
            addr = 0;
        }
    }

    return .{
        .dst_xmm = dst_xmm,
        .src_xmm = src_xmm,
        .mod = mod,
        .rm_code = rm_code,
        .addr = addr,
        .is_reg_form = is_reg_form,
    };
}

/// Decode the ModR/M byte following an EVEX prefix with 5-bit register
/// addressing (R' extends dst to xmm0-xmm31, V' extends vvvv). Also handles
/// compressed 8-bit displacement scaling for EVEX instructions.
fn decodeEvexModRm(
    bytes: []const u8,
    pos: *usize,
    evex: EvexPrefix,
    element_width: u6,
) ?struct {
    dst_xmm: u8,
    src_xmm: u8,
    mod: u2,
    rm_code: u3,
    addr: u64,
    is_reg_form: bool,
} {
    if (pos.* >= bytes.len) return null;
    const modrm = bytes[pos.*];
    pos.* += 1;

    const mod: u2 = @truncate(modrm >> 6);
    const reg_code: u3 = @truncate(modrm >> 3);
    const rm_code: u3 = @truncate(modrm);

    // 5-bit destination register: {R', !R, reg_code}
    const dst_xmm: u8 = ((if (evex.r_prime) @as(u8, 16) else 0) | (if (evex.r) @as(u8, 8) else 0)) | reg_code;
    const src_xmm: u8 = (if (evex.b) @as(u8, 8) else @as(u8, 0)) | rm_code;

    var addr: u64 = undefined;
    const is_reg_form = (mod == 3);

    if (!is_reg_form) {
        // Compressed displacement (DISP8) scaling for EVEX:
        // N = element_width * vector_lanes (128-bit=16, 256-bit=32, 512-bit=64)
        // Broadcast: N = element_width
        // The Intel SDM defines the EVEX DISP8 scaling factor N as:
        // - For regular memory ops: N = total vector bytes (16/32/64)
        // - For broadcast: N = element size in bytes (2/4/8)        // N values: 16 (128-bit), 32 (256-bit), 64 (512-bit) — fits in u7
        const evex_scale: u7 = if (evex.broadcast)
            @as(u7, element_width / 8)
        else switch (evex.vector_length) {
            0 => 16,
            1 => 32,
            2 => 64,
            3 => 64, // reserved, treat as 512-bit
        };

        const has_sib = (rm_code == 4) or (mod == 0 and rm_code == 5);
        if (has_sib) {
            if (pos.* >= bytes.len) return null;
            _ = bytes[pos.*];
            pos.* += 1;
        }

        const disp_size: u4 = switch (mod) {
            0 => if (rm_code == 5 or has_sib) @as(u4, 4) else 0,
            1 => 1,
            2 => 4,
            else => unreachable,
        };
        if (pos.* + disp_size > bytes.len) return null;
        if (disp_size == 1) {
            // Compressed 8-bit displacement scaled by N
            const disp: u8 = bytes[pos.*];
            addr = @as(u64, disp) * evex_scale;
            pos.* += 1;
        } else if (disp_size == 4) {
            const disp: i32 = std.mem.readInt(i32, bytes[pos.*..][0..4], .little);
            addr = @as(u64, @bitCast(@as(i64, disp)));
            pos.* += 4;
        } else {
            addr = 0;
        }
    }

    return .{
        .dst_xmm = dst_xmm,
        .src_xmm = src_xmm,
        .mod = mod,
        .rm_code = rm_code,
        .addr = addr,
        .is_reg_form = is_reg_form,
    };
}

pub fn decodeVexInstruction(bytes: []const u8) ?DecodedInsn {
    // Check for EVEX prefix (0x62) before VEX (0xC5/0xC4)
    if (bytes.len > 0 and bytes[0] == 0x62) {
        const evex = decodeEvexPrefix(bytes) orelse return null;
        var pos = evex.len;
        if (pos >= bytes.len) return null;
        const opcode = bytes[pos];
        pos += 1;
        _ = opcode; // Reserved for EVEX Phase 2 opcode dispatch
        // Use 5-bit register decode for EVEX (r_prime + v_prime extensions)
        // with compressed displacement scaling. Default element_width=32;
        // opcode-specific handlers will override with correct element size.
        const evex_modrm = decodeEvexModRm(bytes, &pos, evex, 32) orelse return null;
        // Build a DecodedInsn with EVEX metadata; actual opcode dispatch
        // will be added in EVEX Phase 2
        return .{
            .op = .invalid,
            .size = .bits64,
            .len = @intCast(pos),
            .xmm_dst = evex_modrm.dst_xmm,
            .xmm_src = evex_modrm.src_xmm,
            .xmm_src2 = (if (evex.v_prime) @as(u8, 16) else 0) | evex.vvvv,
            .is_reg_form = evex_modrm.is_reg_form,
            .addr = evex_modrm.addr,
            .vector_256 = (evex.vector_length == 1),
            .vector_512 = (evex.vector_length == 2),
            .opmask = evex.opmask,
            .zero_mask = evex.z,
            .evex_broadcast = evex.broadcast,
        };
    }

    const vex = decodeVexPrefix(bytes) orelse return null;
    var pos = vex.len;
    if (pos >= bytes.len) return null;

    const opcode = bytes[pos];
    pos += 1;

    // Parse ModR/M (all VEX instructions have ModR/M)
    const modrm_decoded = decodeVexModRm(bytes, &pos, vex) orelse return null;

    // Determine opcode variant based on VEX prefix type (PS/PD/SS/SD)
    // The pattern: vex.has_66_prefix → PD, vex.has_f2_prefix → SD,
    // vex.has_f3_prefix → SS, none → PS
    const arith = struct {
        fn pick(v: VexPrefix, comptime ops: [4]Op) Op {
            if (v.has_f3_prefix) return ops[0];
            if (v.has_f2_prefix) return ops[1];
            if (v.has_66_prefix) return ops[2];
            return ops[3];
        }
    }.pick;

    // Dispatch by opcode, using VEX map field to select the correct
    // opcode map (1=0x0F, 2=0x0F38, 3=0x0F3A)
    switch (vex.m) {
        2 => return decodeVexMap38(vex, pos, opcode, modrm_decoded),
        3 => {
            // All VEX.0x0F3A instructions have a mandatory 8-bit immediate
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            return decodeVexMap3A(vex, pos, opcode, modrm_decoded, imm);
        },
        1 => {}, // 0x0F map — handled below
        else => return null,
    }

    // Original 0x0F map (vex.m == 1)
    switch (opcode) {
        0x10 => {
            // VMOVUPS (VEX.0F 10), VMOVUPD (VEX.66.0F 10)
            // VMOVSS (VEX.F3.0F 10), VMOVSD (VEX.F2.0F 10) — load forms
            const op = arith(vex, .{ .vmovss_xmm_mem, .vmovsd_xmm_mem, .vmovupd_xmm_mem, .vmovups_xmm_mem });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x11 => {
            // VMOVUPS (VEX.0F 11), VMOVUPD (VEX.66.0F 11)
            // VMOVSS (VEX.F3.0F 11), VMOVSD (VEX.F2.0F 11) — store forms
            const op = arith(vex, .{ .vmovss_mem_xmm, .vmovsd_mem_xmm, .vmovupd_mem_xmm, .vmovups_mem_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x12 => {
            // VMOVHLPS (VEX.0F 12, reg) / VMOVLPS (VEX.0F 12 /r) — load low
            // VMOVLPD (VEX.66.0F 12 /r) — load low double
            const op: Op = if (vex.has_66_prefix)
                (if (modrm_decoded.is_reg_form) .vmovlhps else .vmovlpd_xmm_xmm_mem64)
            else
                (if (modrm_decoded.is_reg_form) .vmovhlps else .vmovlps_xmm_xmm_mem64);
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x13 => {
            // VMOVLPS (VEX.0F 13 /r) — store low packed single
            // With 0x66 prefix: VMOVLPD (VEX.66.0F 13 /r)
            const op = arith(vex, .{ .vmovlps_mem64_xmm, .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm, .vmovlps_mem64_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x14 => {
            // VUNPCKLPS (VEX.0F 14) / VUNPCKLPD (VEX.66.0F 14)
            const op: Op = if (vex.has_66_prefix) .vunpcklpd else .vunpcklps;
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x15 => {
            // VUNPCKHPS (VEX.0F 15) / VUNPCKHPD (VEX.66.0F 15)
            const op: Op = if (vex.has_66_prefix) .vunpckhpd else .vunpckhps;
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x16 => {
            // VMOVLHPS (VEX.0F 16, reg) / VMOVHPS (VEX.0F 16 /r) — load high
            // VMOVHPD (VEX.66.0F 16 /r) — load high double
            const op: Op = if (vex.has_66_prefix)
                (if (modrm_decoded.is_reg_form) .vmovlhps else .vmovhpd_xmm_xmm_mem64)
            else
                (if (modrm_decoded.is_reg_form) .vmovlhps else .vmovhps_xmm_xmm_mem64);
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x17 => {
            // VMOVHPS (VEX.0F 17 /r) — store high packed single
            // With 0x66 prefix: VMOVHPD (VEX.66.0F 17 /r)
            const op = arith(vex, .{ .vmovhps_mem64_xmm, .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm, .vmovhps_mem64_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x28 => {
            // VMOVAPS (VEX.0F 28), VMOVAPD (VEX.66.0F 28) — load forms
            const op = arith(vex, .{ .vmovaps_xmm_mem, .vmovaps_xmm_mem, .vmovapd_xmm_mem, .vmovaps_xmm_mem });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x29 => {
            // VMOVAPS (VEX.0F 29), VMOVAPD (VEX.66.0F 29) — store forms
            const op = arith(vex, .{ .vmovaps_mem_xmm, .vmovaps_mem_xmm, .vmovapd_mem_xmm, .vmovaps_mem_xmm });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x2A => {
            // VCVTSI2SS (VEX.0F 2A), VCVTSI2SD (VEX.66.0F 2A)
            // VEX.F3.0F 2A and VEX.F2.0F 2A are also CVTSI2SS/SD
            const op = arith(vex, .{ .vcvtsi2ss_xmm_reg, .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_reg, .vcvtsi2ss_xmm_reg });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x2E => {
            // VUCOMISS (VEX.66.0F 2E) — unordered compare scalar single
            if (vex.has_66_prefix or !vex.has_f3_prefix) return decodeVexReturn(vex, pos, .vucomiss, modrm_decoded);
            return null;
        },
        0x2F => {
            // VUCOMISD (VEX.66.0F 2F) — unordered compare scalar double
            if (vex.has_66_prefix or !vex.has_f3_prefix) return decodeVexReturn(vex, pos, .vucomisd, modrm_decoded);
            return null;
        },
        0x50 => {
            // VMOVMSKPS (VEX.0F 50) / VMOVMSKPD (VEX.66.0F 50)
            const op: Op = if (vex.has_66_prefix) .vmovmskpd else .vmovmskps;
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x51 => {
            // VSQRTPS (VEX.0F 51) / VSQRTPD (VEX.66.0F 51)
            // VSQRTSS (VEX.F3.0F 51) / VSQRTSD (VEX.F2.0F 51)
            const op = arith(vex, .{ .vsqrtss, .vsqrtsd, .vsqrtpd, .vsqrtps });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x52 => {
            // VRSQRTPS (VEX.0F 52 /r) — no 0x66/PD form
            return .{
                .op = .vrsqrtps,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        0x53 => {
            // VRCPPS (VEX.0F 53 /r) — no 0x66/PD form
            return .{
                .op = .vrcpps,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        0x54 => {
            // VANDPS (VEX.0F 54) / VANDPD (VEX.66.0F 54)
            const op_sel = arith(vex, .{ .vandps, .vandps, .vandpd, .vandps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x55 => {
            // VANDNPS (VEX.0F 55) / VANDNPD (VEX.66.0F 55)
            const op_sel = arith(vex, .{ .vandnps, .vandnps, .vandnpd, .vandnps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x56 => {
            // VORPS (VEX.0F 56) / VORPD (VEX.66.0F 56)
            const op_sel = arith(vex, .{ .vorps, .vorps, .vorpd, .vorps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x57 => {
            // VXORPS (VEX.0F 57) / VXORPD (VEX.66.0F 57)
            const op_sel = arith(vex, .{ .vxorps, .vxorps, .vxorpd, .vxorps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x58 => {
            // VADDPS (VEX.0F 58) / VADDPD (VEX.66.0F 58)
            // VADDSS (VEX.F3.0F 58) / VADDSD (VEX.F2.0F 58)
            const op_sel = arith(vex, .{ .vaddss, .vaddsd, .vaddpd, .vaddps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x59 => {
            // VMULPS (VEX.0F 59) / VMULPD (VEX.66.0F 59)
            // VMULSS (VEX.F3.0F 59) / VMULSD (VEX.F2.0F 59)
            const op_sel = arith(vex, .{ .vmulss, .vmulsd, .vmulpd, .vmulps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5A => {
            // VCVTPS2PD (VEX.0F 5A) / VCVTPD2PS (VEX.66.0F 5A)
            // VCVTSS2SD (VEX.F3.0F 5A) / VCVTSD2SS (VEX.F2.0F 5A)
            const op = arith(vex, .{ .vcvtss2sd, .vcvtsd2ss, .vcvtpd2ps, .vcvtps2pd });
            return decodeVexReturn(vex, pos, op, modrm_decoded);
        },
        0x5B => {
            // VCVTDQ2PS (VEX.0F 5B) / VCVTPS2DQ (VEX.66.0F 5B)
            // VCVTQQ2PS (VEX.F3.0F 5B)
            const op_sel = arith(vex, .{ .vcvtdq2ps, .vcvtdq2ps, .vcvtps2dq, .vcvtdq2ps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5C => {
            // VSUBPS (VEX.0F 5C) / VSUBPD (VEX.66.0F 5C)
            // VSUBSS (VEX.F3.0F 5C) / VSUBSD (VEX.F2.0F 5C)
            const op_sel = arith(vex, .{ .vsubss, .vsubsd, .vsubpd, .vsubps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5D => {
            // VMINPS (VEX.0F 5D) / VMINPD (VEX.66.0F 5D)
            // VMINSS (VEX.F3.0F 5D) / VMINSD (VEX.F2.0F 5D)
            const op_sel = arith(vex, .{ .vminss, .vminsd, .vminpd, .vminps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5E => {
            // VDIVPS (VEX.0F 5E) / VDIVPD (VEX.66.0F 5E)
            // VDIVSS (VEX.F3.0F 5E) / VDIVSD (VEX.F2.0F 5E)
            const op_sel = arith(vex, .{ .vdivss, .vdivsd, .vdivpd, .vdivps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x5F => {
            // VMAXPS (VEX.0F 5F) / VMAXPD (VEX.66.0F 5F)
            // VMAXSS (VEX.F3.0F 5F) / VMAXSD (VEX.F2.0F 5F)
            const op_sel = arith(vex, .{ .vmaxss, .vmaxsd, .vmaxpd, .vmaxps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x60 => {
            // VPUNPCKLBW (VEX.66.0F 60 /r) — unpack low bytes
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklbw else return null, modrm_decoded);
        },
        0x61 => {
            // VPUNPCKLWD (VEX.66.0F 61 /r) — unpack low words
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklwd else return null, modrm_decoded);
        },
        0x62 => {
            // VPUNPCKLDQ (VEX.66.0F 62 /r) — unpack low dwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckldq else return null, modrm_decoded);
        },
        0x63 => {
            // VPACKSSWB (VEX.66.0F 63 /r) — pack with signed saturation
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpacksswb else return null, modrm_decoded);
        },
        0x64 => {
            // VPUNPCKHBW (VEX.66.0F 64 /r) — unpack high bytes
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhbw else return null, modrm_decoded);
        },
        0x65 => {
            // VPUNPCKHWD (VEX.66.0F 65 /r) — unpack high words
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhwd else return null, modrm_decoded);
        },
        0x66 => {
            // VPUNPCKHDQ (VEX.66.0F 66 /r) — unpack high dwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhdq else return null, modrm_decoded);
        },
        0x67 => {
            // VPACKUSWB (VEX.66.0F 67 /r) — pack with unsigned saturation
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpackuswb else return null, modrm_decoded);
        },
        0x68 => {
            // VPUNPCKLQDQ (VEX.66.0F 68 /r) — unpack low qwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpcklqdq else return null, modrm_decoded);
        },
        0x69 => {
            // VPUNPCKHQDQ (VEX.66.0F 69 /r) — unpack high qwords
            return decodeVexReturn(vex, pos, if (vex.has_66_prefix) .vpunpckhqdq else return null, modrm_decoded);
        },
        0x6E => {
            // VMOVD (VEX.66.0F 6E) / VMOVQ (VEX.66.REX.W 0F 6E)
            if (!vex.has_66_prefix or vex.l or vex.vvvv != 0) return null;
            return .{
                .op = if (vex.w)
                    (if (modrm_decoded.is_reg_form) .vmovq_xmm_reg64 else .vmovq_xmm_mem64)
                else
                    (if (modrm_decoded.is_reg_form) .vmovd_xmm_reg32 else .vmovd_xmm_mem32),
                .size = if (vex.w) .bits64 else .bits32,
                .len = @intCast(pos),
                .src_reg = @enumFromInt(modrm_decoded.src_xmm),
                .xmm_dst = modrm_decoded.dst_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
            };
        },
        0x6F => {
            // VMOVDQA (VEX.66.0F 6F) / VMOVDQU (VEX.F3.0F 6F)
            // With F2 prefix: VMOVDQU (VEX.F2.0F 6F is also VMOVDQU)
            if (vex.has_66_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqa_xmm_xmm else .vmovdqa_xmm_mem,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else if (vex.has_f3_prefix or vex.has_f2_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_xmm_mem,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else {
                // VMOVAPS/VMOVAPD with no prefix: F30F6F = MOVDQU
                // VEX.0F 6F is undefined — fall through
                return null;
            }
        },
        0x70 => {
            // VPSHUFD (VEX.66.0F 70 /r ib)
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            return .{
                .op = .vpshufd,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .imm = imm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        0x7C => {
            // VHADDPS (VEX.0F 7C) / VHADDPD (VEX.66.0F 7C)
            const op_sel = arith(vex, .{ .vhaddps, .vhaddps, .vhaddpd, .vhaddps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x7D => {
            // VHSUBPS (VEX.0F 7D) / VHSUBPD (VEX.66.0F 7D)
            const op_sel = arith(vex, .{ .vhsubps, .vhsubps, .vhsubpd, .vhsubps });
            return decodeVexReturn(vex, pos, op_sel, modrm_decoded);
        },
        0x7E => {
            // VMOVD (VEX.128.66.0F 7E) / VMOVQ (VEX.128.66.W1.0F 7E).
            // ModRM.reg is the XMM source; ModRM.r/m is the GPR or memory
            // destination, the reverse operand direction from opcode 6E.
            if (!vex.has_66_prefix or vex.l or vex.vvvv != 0) return null;
            return .{
                .op = if (vex.w)
                    (if (modrm_decoded.is_reg_form) .vmovq_reg64_xmm else .vmovq_mem64_xmm)
                else
                    (if (modrm_decoded.is_reg_form) .vmovd_reg32_xmm else .vmovd_mem32_xmm),
                .size = if (vex.w) .bits64 else .bits32,
                .len = @intCast(pos),
                .dst_reg = @enumFromInt(modrm_decoded.src_xmm),
                .xmm_src = modrm_decoded.dst_xmm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
            };
        },
        0x7F => {
            // VMOVDQA (VEX.66.0F 7F) / VMOVDQU (VEX.F3.0F 7F) — store forms
            if (vex.has_66_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqa_xmm_xmm else .vmovdqa_mem_xmm,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else if (vex.has_f3_prefix or vex.has_f2_prefix) {
                return .{
                    .op = if (modrm_decoded.is_reg_form) .vmovdqu_xmm_xmm else .vmovdqu_mem_xmm,
                    .size = .bits64,
                    .len = @intCast(pos),
                    .xmm_dst = modrm_decoded.dst_xmm,
                    .xmm_src = modrm_decoded.src_xmm,
                    .is_reg_form = modrm_decoded.is_reg_form,
                    .addr = modrm_decoded.addr,
                    .vector_256 = vex.l,
                };
            } else {
                return null;
            }
        },
        0xC2 => {
            // VCMPPS (VEX.0F C2) / VCMPPD (VEX.66.0F C2)
            // VCMPSS (VEX.F3.0F C2) / VCMPSD (VEX.F2.0F C2)
            // Has an immediate comparison predicate byte
            if (pos >= bytes.len) return null;
            const imm = bytes[pos];
            pos += 1;
            const op_sel = arith(vex, .{ .vcmpss, .vcmpsd, .vcmppd, .vcmpps });
            return .{
                .op = op_sel,
                .size = .bits64,
                .len = @intCast(pos),
                .xmm_dst = modrm_decoded.dst_xmm,
                .xmm_src = modrm_decoded.src_xmm,
                .imm = imm,
                .is_reg_form = modrm_decoded.is_reg_form,
                .addr = modrm_decoded.addr,
                .vector_256 = vex.l,
            };
        },
        else => return null,
    }
}

/// Helper to construct a DecodedInsn from the decoded VEX operands.
fn decodeVexReturn(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .xmm_src2 = vex.vvvv,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
    };
}

/// Helper to construct a DecodedInsn with an immediate byte.
/// Used by VEX.0F3A instructions that encode an immediate operand.
fn decodeVexReturnImm(vex: VexPrefix, pos: usize, op_enum: Op, modrm: anytype, imm: u8) ?DecodedInsn {
    return .{
        .op = op_enum,
        .size = .bits64,
        .len = @intCast(pos),
        .xmm_dst = modrm.dst_xmm,
        .xmm_src = modrm.src_xmm,
        .xmm_src2 = vex.vvvv,
        .is_reg_form = modrm.is_reg_form,
        .addr = modrm.addr,
        .vector_256 = vex.l,
        .uses_imm = true,
        .imm = imm,
    };
}

/// Decode VEX opcode map 0x38 (VEX.0F38).
/// Handles SSSE3/AVX2 3-operand integer SIMD instructions.
fn decodeVexMap38(vex: VexPrefix, pos: usize, opcode: u8, modrm: anytype) ?DecodedInsn {
    // VEX opcode map 0x38 uses the 0F 38 two-byte opcode prefix.
    // Dispatch by the third opcode byte:
    return switch (opcode) {
        0x00...0x06 => {
            // VPSHUFB (0x00), VPHADDW/D/SW (0x01-0x03), VPHSUBW/D/SW (0x04-0x06)
            return switch (opcode) {
                0x00 => decodeVexReturn(vex, pos, .vpshufb, modrm),
                0x01 => decodeVexReturn(vex, pos, .vphaddw, modrm),
                0x02 => decodeVexReturn(vex, pos, .vphaddd, modrm),
                0x03 => decodeVexReturn(vex, pos, .vphaddsw, modrm),
                0x04 => decodeVexReturn(vex, pos, .vphsubw, modrm),
                0x05 => decodeVexReturn(vex, pos, .vphsubd, modrm),
                0x06 => decodeVexReturn(vex, pos, .vphsubsw, modrm),
                else => null,
            };
        },
        0x08...0x0A => {
            // VPSIGNB/W/D (VEX.0F38 08/09/0A)
            return switch (opcode) {
                0x08 => decodeVexReturn(vex, pos, .vpsignb, modrm),
                0x09 => decodeVexReturn(vex, pos, .vpsignw, modrm),
                0x0A => decodeVexReturn(vex, pos, .vpsignd, modrm),
                else => null,
            };
        },
        0x10...0x12 => {
            // VPSRLVW (0x10), VPSRAVW (0x11), VPSLLVW (0x12)
            return switch (opcode) {
                0x10 => decodeVexReturn(vex, pos, .vpsrlvw, modrm),
                0x11 => decodeVexReturn(vex, pos, .vpsravw, modrm),
                0x12 => decodeVexReturn(vex, pos, .vpsllvw, modrm),
                else => null,
            };
        },
        0x1C...0x1E => {
            // VPABSB/W/D (VEX.0F38 1C/1D/1E)
            return switch (opcode) {
                0x1C => decodeVexReturn(vex, pos, .vpabsb, modrm),
                0x1D => decodeVexReturn(vex, pos, .vpabsw, modrm),
                0x1E => decodeVexReturn(vex, pos, .vpabsd, modrm),
                else => null,
            };
        },
        0x20...0x25 => {
            // PMOVSX variants: VEX.0F38 20-25
            return switch (opcode) {
                0x20 => decodeVexReturn(vex, pos, .vpmovsxbw, modrm),
                0x21 => decodeVexReturn(vex, pos, .vpmovsxbd, modrm),
                0x22 => decodeVexReturn(vex, pos, .vpmovsxbq, modrm),
                0x23 => decodeVexReturn(vex, pos, .vpmovsxwd, modrm),
                0x24 => decodeVexReturn(vex, pos, .vpmovsxwq, modrm),
                0x25 => decodeVexReturn(vex, pos, .vpmovsxdq, modrm),
                else => null,
            };
        },
        0x28 => decodeVexReturn(vex, pos, .vpmuldq, modrm),
        0x29 => decodeVexReturn(vex, pos, .vpcmpeqq, modrm),
        0x2A => decodeVexReturn(vex, pos, .vpmovzxbd, modrm), // VMOVNTDQA with 66
        0x2B => decodeVexReturn(vex, pos, .vpackusdw, modrm),
        0x36 => decodeVexReturn(vex, pos, .vpermd, modrm),
        0x37 => decodeVexReturn(vex, pos, .vpcmpgtq, modrm),
        0x38 => decodeVexReturn(vex, pos, .vpminsb, modrm),
        0x39 => decodeVexReturn(vex, pos, .vpminsd, modrm),
        0x3A => decodeVexReturn(vex, pos, .vpminuw, modrm),
        0x3B => decodeVexReturn(vex, pos, .vpminud, modrm),
        0x3C => decodeVexReturn(vex, pos, .vpmaxsb, modrm),
        0x3D => decodeVexReturn(vex, pos, .vpmaxsd, modrm),
        0x3E => decodeVexReturn(vex, pos, .vpmaxuw, modrm),
        0x3F => decodeVexReturn(vex, pos, .vpmaxud, modrm),
        0x40 => decodeVexReturn(vex, pos, .vpmulld_38, modrm),
        0x41 => decodeVexReturn(vex, pos, .vphminposuw, modrm),
        0x45 => decodeVexReturn(vex, pos, .vpsrlvd, modrm),
        0x46 => decodeVexReturn(vex, pos, .vpsravd, modrm),
        0x47 => decodeVexReturn(vex, pos, .vpsllvd, modrm),
        0x4C => decodeVexReturn(vex, pos, .vpblendvb, modrm),
        0x4D => decodeVexReturn(vex, pos, .vpblendw, modrm), // VEX.0F3A 0E fallback
        // VEX.0F38 FMA — PS/PD variants selected by VEX.W bit
        0x96 => decodeVexReturn(vex, pos, if (vex.w) .vfmaddsub132pd else .vfmaddsub132ps, modrm),
        0x97 => decodeVexReturn(vex, pos, if (vex.w) .vfmsubadd132pd else .vfmsubadd132ps, modrm),
        0x98 => decodeVexReturn(vex, pos, if (vex.w) .vfmadd132pd else .vfmadd132ps, modrm),
        0x9A => decodeVexReturn(vex, pos, if (vex.w) .vfmsub132pd else .vfmsub132ps, modrm),
        0xA6 => decodeVexReturn(vex, pos, if (vex.w) .vfmaddsub213pd else .vfmaddsub213ps, modrm),
        0xA7 => decodeVexReturn(vex, pos, if (vex.w) .vfmsubadd213pd else .vfmsubadd213ps, modrm),
        0xA8 => decodeVexReturn(vex, pos, if (vex.w) .vfmadd213pd else .vfmadd213ps, modrm),
        0xAA => decodeVexReturn(vex, pos, if (vex.w) .vfmsub213pd else .vfmsub213ps, modrm),
        0xB6 => decodeVexReturn(vex, pos, if (vex.w) .vfmaddsub231pd else .vfmaddsub231ps, modrm),
        0xB7 => decodeVexReturn(vex, pos, if (vex.w) .vfmsubadd231pd else .vfmsubadd231ps, modrm),
        0xB8 => decodeVexReturn(vex, pos, if (vex.w) .vfmadd231pd else .vfmadd231ps, modrm),
        0xBA => decodeVexReturn(vex, pos, if (vex.w) .vfmsub231pd else .vfmsub231ps, modrm),
        else => null,
    };
}

/// Decode VEX opcode map 0x3A (VEX.0F3A).
/// Handles VEX-encoded immediate byte instructions.
fn decodeVexMap3A(vex: VexPrefix, pos: usize, opcode: u8, modrm: anytype, imm: u8) ?DecodedInsn {
    // VEX opcode map 0x3A uses the 0F 3A two-byte opcode prefix.
    // All 0x3A instructions have an 8-bit immediate byte (already consumed
    // by the caller). The immediate controls operation selection, element
    // insertion/sign extension, or broadcast behavior.
    return switch (opcode) {
        0x0A => decodeVexReturnImm(vex, pos, .vpextrb, modrm, imm), // VPEXTRB
        0x0B => decodeVexReturnImm(vex, pos, .vpextrw, modrm, imm), // VPEXTRW
        0x0C => decodeVexReturnImm(vex, pos, .vpextrd, modrm, imm), // VPEXTRD / VEXTRACTPS
        0x0D => decodeVexReturnImm(vex, pos, .vpextrq, modrm, imm), // VPEXTRQ
        0x0E => decodeVexReturnImm(vex, pos, .vpblendw, modrm, imm), // VPBLENDW
        0x0F => decodeVexReturnImm(vex, pos, .vpalignr, modrm, imm), // VPALIGNR
        0x16 => decodeVexReturnImm(vex, pos, .vpermps, modrm, imm), // VPERMPS
        0x17 => decodeVexReturnImm(vex, pos, .vextractf128, modrm, imm), // VEXTRACTF128 (VEX.L=1)
        0x18 => decodeVexReturnImm(vex, pos, .vbroadcastss, modrm, imm), // VBROADCASTSS
        0x19 => decodeVexReturnImm(vex, pos, .vbroadcastsd, modrm, imm), // VBROADCASTSD (YMM only)
        0x1A => decodeVexReturnImm(vex, pos, .vbroadcastf128, modrm, imm), // VBROADCASTF128
        0x1B => decodeVexReturnImm(vex, pos, .vbroadcasti128, modrm, imm), // VBROADCASTI128
        0x20 => decodeVexReturnImm(vex, pos, .vpinsrb_xmm_xmm_reg32, modrm, imm), // VPINSRB
        0x21 => decodeVexReturnImm(vex, pos, .vinsertps, modrm, imm), // VEX.0F3A 21 = VINSERTPS
        0x25 => decodeVexReturnImm(vex, pos, .vpternlogd, modrm, imm), // VPTERNLOGD
        0x26 => decodeVexReturnImm(vex, pos, .vpternlogq, modrm, imm), // VPTERNLOGQ
        0x4A => decodeVexReturnImm(vex, pos, .valignd, modrm, imm), // VALIGND
        0x4B => decodeVexReturnImm(vex, pos, .valignq, modrm, imm), // VALIGNQ
        else => null,
    };
}

/// Decodes every legacy general-purpose MOV encoding that is valid in long
/// mode: ModR/M register/memory forms, opcode-embedded immediates, Group 11
/// immediates, and moffs accumulator forms. All forms share the same prefix,
/// register, SIB, and displacement machinery above.
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

test "shared CRC32C accumulator follows x86 byte order" {
    try std.testing.expectEqual(@as(u32, 0x93AD_1061), crc32cAccumulator(0, 'a', .bits8));
}

fn decodeMovForTest(bytes: []const u8) ?DecodedInsn {
    const prefixes = decodeLegacyPrefixes(bytes);
    if (prefixes.len >= bytes.len) return null;
    var pos = prefixes.len;
    const opcode = bytes[pos];
    pos += 1;
    return decodeLegacyMov(bytes, &pos, prefixes, opcode);
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

test "default segment selection follows instruction stack data and string rules" {
    try std.testing.expectEqual(Segment.cs, defaultSegment(.instruction_fetch, null));
    try std.testing.expectEqual(Segment.ss, defaultSegment(.stack, null));
    try std.testing.expectEqual(Segment.ss, defaultSegment(.explicit_data, .ah_sp_esp_rsp));
    try std.testing.expectEqual(Segment.ss, defaultSegment(.explicit_data, .ch_bp_ebp_rbp));
    try std.testing.expectEqual(Segment.ds, defaultSegment(.explicit_data, .al_ax_eax_rax));
    try std.testing.expectEqual(Segment.ds, defaultSegment(.explicit_data, .r12b_r12w_r12d_r12));
    try std.testing.expectEqual(Segment.ds, defaultSegment(.string_source, .dh_si_esi_rsi));
    try std.testing.expectEqual(Segment.es, defaultSegment(.string_destination, .bh_di_edi_rdi));

    try std.testing.expectEqual(Segment.fs, selectSegment(.explicit_data, .ch_bp_ebp_rbp, .fs));
    try std.testing.expectEqual(Segment.gs, selectSegment(.string_source, .dh_si_esi_rsi, .gs));
    try std.testing.expectEqual(Segment.es, selectSegment(.string_destination, .bh_di_edi_rdi, .fs));
    try std.testing.expectEqual(Segment.ss, selectSegment(.stack, .ah_sp_esp_rsp, .gs));
}

test "long mode effective addresses apply only FS and GS segment bases" {
    var regs = Regs{};
    regs.rbp = 0x1000;
    regs.segments.ss.base = 0x2000;
    regs.segments.fs.base = 0x3000;

    const stack_default = MemoryOperand{
        .displacement = 8,
        .has_base = true,
        .base_reg = .ch_bp_ebp_rbp,
        .segment = .ss,
    };
    try std.testing.expectEqual(@as(u64, 0x1008), resolveMemoryAddress(&regs, stack_default, 0, .bits64, .long64, true));
    try std.testing.expectEqual(@as(u64, 0x3008), resolveMemoryAddress(&regs, .{ .displacement = 8, .segment = .fs }, 0, .bits64, .long64, true));
    try std.testing.expectEqual(@as(u64, 0x3008), resolveMemoryAddress(&regs, stack_default, 0, .bits64, .protected, true));
}

test "effective address resolver wraps address-size 32 before segmentation" {
    var regs = Regs{};
    regs.rax = 0xFFFF_FFFF;
    regs.rcx = 2;
    regs.segments.fs.base = 0x1000;
    const memory = MemoryOperand{
        .displacement = 3,
        .has_base = true,
        .base_reg = .al_ax_eax_rax,
        .has_index = true,
        .index_reg = .cl_cx_ecx_rcx,
        .scale = 1,
        .segment = .fs,
    };
    try std.testing.expectEqual(@as(u64, 0x1006), resolveMemoryAddress(&regs, memory, 0, .bits32, .long64, true));
}

test "RIP relative address resolution uses the end of the instruction" {
    const regs = Regs{};
    const memory = MemoryOperand{
        .displacement = @bitCast(@as(i64, -4)),
        .rip_relative = true,
    };
    try std.testing.expectEqual(@as(u64, 0x1003), resolveMemoryAddress(&regs, memory, 0x1007, .bits64, .long64, true));
}
