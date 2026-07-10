const std = @import("std");
const cpu_state = @import("cpu_state.zig");
const flags = @import("flags.zig");
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
pub const RFL_ZF = flags.RFL_ZF;
pub const RFL_SF = flags.RFL_SF;
pub const RFL_OF = flags.RFL_OF;

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
    cmpxchg_mem32_reg32,
    cmpxchg_mem64_reg64,
    cmpxchg_reg32_reg32,
    cmpxchg_reg64_reg64,
    xchg_mem32_reg32,
    xchg_mem64_reg64,
    xchg_reg32_reg32,
    xchg_reg64_reg64,
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
    vmovq_xmm_reg64,
    vmovq_xmm_mem64,
    vmovq_reg64_xmm,
    vmovq_mem64_xmm,
    vpinsrb_xmm_xmm_reg32,
    vpinsrb_xmm_xmm_mem8,
    vpshufb,
    vpcmpeqd,
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
    vpermilpd,
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
