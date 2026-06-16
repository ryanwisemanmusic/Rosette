const cpu_state = @import("cpu_state.zig");
const flags = @import("flags.zig");

pub const OperandSize = flags.OperandSize;
pub const Condition = flags.Condition;
pub const RegId = cpu_state.RegId;
pub const Regs = cpu_state.Regs;

pub const RFL_CF = flags.RFL_CF;
pub const RFL_ZF = flags.RFL_ZF;
pub const RFL_SF = flags.RFL_SF;
pub const RFL_OF = flags.RFL_OF;

pub const applySub = flags.applySub;
pub const applyAdd = flags.applyAdd;
pub const applyIncDec = flags.applyIncDec;
pub const applyLogic = flags.applyLogic;
pub const evalCond = flags.evalCond;
pub const regVal = cpu_state.regVal;
pub const setReg = cpu_state.setReg;

pub const Op = enum(u8) {
    invalid,
    nop,
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
    // sub (reg, r/m) d=1
    sub_reg8_mem8,
    sub_reg16_mem16,
    sub_reg32_mem32,
    sub_reg64_mem64,
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
    // logical and/xor
    and_reg8_reg8,
    and_reg16_reg16,
    and_reg32_reg32,
    and_reg64_reg64,
    and_reg8_imm8,
    and_reg16_imm8,
    and_reg32_imm8,
    and_reg64_imm8,
    xor_reg8_reg8,
    xor_reg16_reg16,
    xor_reg32_reg32,
    xor_reg64_reg64,
    xor_reg8_imm8,
    // test
    test_reg8_reg8,
    test_reg16_reg16,
    test_reg32_reg32,
    test_reg64_reg64,
    test_reg8_imm8,
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
    lea_reg_mem,
    setcc_reg8,
    // conditional / unconditional jumps
    jmp_rel8,
    jcc_rel8,
    jmp_mem64,
    jmp_reg64,
    // syscall
    syscall,
    call_mem64,
    call_reg64,
    hlt,
};

pub const DecodedInsn = struct {
    op: Op = .invalid,
    size: OperandSize = .bits32,
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
};
