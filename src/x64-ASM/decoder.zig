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

pub const RFL_CF = flags.RFL_CF;
pub const RFL_ZF = flags.RFL_ZF;
pub const RFL_SF = flags.RFL_SF;
pub const RFL_OF = flags.RFL_OF;

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
    xchg_mem32_reg32,
    xchg_mem64_reg64,
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
    addr: u64 = 0,
    imm: u64 = 0,
    len: u8 = 0,
    sib_has_index: bool = false,
    sib_index_reg: RegId = .al_ax_eax_rax,
    sib_scale: u2 = 0,
    sib_has_base: bool = false,
    sib_base_reg: RegId = .al_ax_eax_rax,
    rip_relative: bool = false,
    has_0x67: bool = false,
    is_reg_form: bool = false,
    cond: Condition = .e,
    xmm_dst: u8 = 0,
    xmm_src: u8 = 0,
    xmm_src2: u8 = 0,
    vector_256: bool = false,
};

test "shared CRC32C accumulator follows x86 byte order" {
    try std.testing.expectEqual(@as(u32, 0x93AD_1061), crc32cAccumulator(0, 'a', .bits8));
}
