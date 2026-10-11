const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const Cond = process.Cond;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const Op = process.Op;
const RFL_AF = __ProcessInternals._RFL_AF;
const RFL_CF = __ProcessInternals._RFL_CF;
const RFL_OF = __ProcessInternals._RFL_OF;
const RFL_PF = __ProcessInternals._RFL_PF;
const RFL_SF = __ProcessInternals._RFL_SF;
const RFL_ZF = __ProcessInternals._RFL_ZF;
const RegId = process.RegId;
const SYS_arch_prctl = __ProcessInternals._SYS_arch_prctl;
const SYS_gettid = __ProcessInternals._SYS_gettid;
const SYS_open = __ProcessInternals._SYS_open;
const Size = process.Size;
const WindowsExecutableRange = process.WindowsExecutableRange;
const blockJitRuntimeFallbackReason = __ProcessInternals._blockJitRuntimeFallbackReason;
const block_jit = __ProcessInternals._block_jit;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const std = __ProcessInternals._std;
const testing = std.testing;
const tso_memory = __ProcessInternals._tso_memory;
const x64_decoder = __ProcessInternals._x64_decoder;
const x64_syscalls = __ProcessInternals._x64_syscalls;
const ElfState = process.ElfState;
const decodeInsn = __ProcessInternals._decodeInsn;

test "decode 0x66 0xB8 (mov ax, imm16)" {
    const bytes = [_]u8{ 0x66, 0xB8, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits16, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
}

test "decode 0xB8 (mov eax, imm32)" {
    const bytes = [_]u8{ 0xB8, 0x78, 0x56, 0x34, 0x12 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(@as(u64, 0x12345678), d.imm);
}

test "decode 0x48 0xB8 (mov rax, imm64)" {
    const bytes = [_]u8{ 0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
}

test "decode 0x8A 0x04 0x25 <addr> (mov al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x8A, 0x04, 0x25, 0x81, 0x26, 0x01, 0x01 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg8_mem8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(@as(u64, 0x01012681), d.addr);
}

test "decode 0x88 0x04 0x25 <addr> (mov byte [abs], al)" {
    var bytes: [7]u8 = [_]u8{ 0x88, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_mem8_reg8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
}

test "decode 0x02 0x04 0x25 (add al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x02, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.add_reg8_mem8, d.op);
}

test "decode 0xF6 0x24 0x25 (mul byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0xF6, 0x24, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_mem8, d.op);
}

test "decode 0xF7 0xE3 (mul ebx)" {
    var bytes: [2]u8 = [_]u8{ 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg32, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.src_reg);
}

test "decode 0x48 0xF7 0xE3 (mul rbx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg64, d.op);
}

test "decode 0x99 (cdq)" {
    var bytes: [1]u8 = [_]u8{0x99};
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cdq, d.op);
}

test "decode 0x48 0x99 (cqo)" {
    var bytes: [2]u8 = [_]u8{ 0x48, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cqo, d.op);
}

test "decode 0x98 sign-extension variants" {
    try testing.expectEqual(Op.cwde, decodeInsn(&[_]u8{0x98}).op);
    try testing.expectEqual(Op.cbw, decodeInsn(&[_]u8{ 0x66, 0x98 }).op);
    try testing.expectEqual(Op.cdqe, decodeInsn(&[_]u8{ 0x48, 0x98 }).op);
}

test "decode 0x0F 0xB7 (movzx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xB7, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movzx_reg32_mem16, d.op);
}

test "decode 0x0F 0xBF (movsx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xBF, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsx_reg32_mem16, d.op);
}

test "decode 0x0F 0x05 (syscall)" {
    var bytes: [2]u8 = [_]u8{ 0x0F, 0x05 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.syscall, d.op);
}

test "execute gettid syscall shim" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = SYS_gettid;
    state.execute(.{ .op = .syscall, .len = 2 });
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect(!state.terminated);
}

test "invalid LOCK prefix terminates as an invalid instruction" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rip = 0x1234;
    state.execute(.{ .op = .add_reg64_reg64, .lock = true, .is_reg_form = true });
    try testing.expect(state.terminated);
    try testing.expect(state.faulted);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rip);
    try testing.expectEqual(exit_diagnostics.TerminationReason.invalid_instruction, state.termination_reason);
}

test "decode call ret and extended stack forms" {
    var call_bytes: [5]u8 = [_]u8{ 0xE8, 0x64, 0x01, 0x00, 0x00 };
    var d = decodeInsn(&call_bytes);
    try testing.expectEqual(Op.call_rel32, d.op);
    try testing.expectEqual(@as(u8, 5), d.len);
    try testing.expectEqual(@as(u64, 0x164), d.imm);

    d = decodeInsn(&[_]u8{0xC3});
    try testing.expectEqual(Op.ret, d.op);

    d = decodeInsn(&[_]u8{ 0xC2, 0x34, 0x12 });
    try testing.expectEqual(Op.ret, d.op);
    try testing.expectEqual(@as(u8, 3), d.len);
    try testing.expectEqual(@as(u64, 0x1234), d.imm);

    var ret_state = ElfState.init(testing.allocator);
    defer ret_state.deinit();
    const stack = MEM_BASE + 0x1000;
    const return_target = MEM_BASE + 0x2000;
    ret_state.write64(stack, return_target);
    ret_state.regs.rsp = stack;
    ret_state.execute(d);
    try testing.expectEqual(return_target, ret_state.regs.rip);
    try testing.expectEqual(stack + 8 + 0x1234, ret_state.regs.rsp);

    d = decodeInsn(&[_]u8{ 0x41, 0x54 });
    try testing.expectEqual(Op.push_reg, d.op);
    try testing.expectEqual(RegId.r12b_r12w_r12d_r12, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x41, 0x5F });
    try testing.expectEqual(Op.pop_reg, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
}

test "block JIT fallback ledger distinguishes missing templates from native slow paths" {
    const missing_native_template: block_jit.FallbackReason = .missing_native_template;
    const native_ret = block_jit.Insn{
        .rip = 0x1000,
        .len = 1,
        .decoded = .{ .op = .ret },
        .segment = .ds,
    };
    try testing.expectEqual(.native_slow_path, blockJitRuntimeFallbackReason(native_ret));

    const missing_template = block_jit.Insn{
        .rip = 0x1000,
        .len = 1,
        .decoded = .{ .op = .invalid },
        .segment = .ds,
    };
    try testing.expectEqual(missing_native_template, blockJitRuntimeFallbackReason(missing_template));

    const policy_fallback = block_jit.Insn{
        .rip = 0x1000,
        .len = 5,
        .decoded = .{ .op = .call_rel32 },
        .segment = .ds,
        .force_fallback = true,
        .fallback_reason = .hook_observation,
    };
    try testing.expectEqual(.hook_observation, blockJitRuntimeFallbackReason(policy_fallback));
}

test "decode REX-aware arithmetic and move-extension registers" {
    var d = decodeInsn(&[_]u8{ 0x45, 0x6B, 0xFF, 0x04 });
    try testing.expectEqual(Op.imul_reg32_reg32_imm8, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x49, 0x69, 0xCD, 0xD0, 0x00, 0x00, 0x00 });
    try testing.expectEqual(Op.imul_reg64_reg64_imm32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(@as(u8, 7), d.len);
    try testing.expectEqual(@as(u64, 0xD0), d.imm);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.dst_reg);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r13b_r13w_r13d_r13, .bits64, 1);
    state.execute(d);
    try testing.expectEqual(@as(u64, 0xD0), state.regs.rcx);

    d = decodeInsn(&[_]u8{ 0x41, 0xF7, 0xFD });
    try testing.expectEqual(Op.idiv_reg32, d.op);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xAF, 0xC5 });
    try testing.expectEqual(Op.imul_reg64_reg64, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x4C, 0x0F, 0xB6, 0xEE });
    try testing.expectEqual(Op.movzx_reg32_mem8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.dst_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.src_reg);
    try testing.expect(!d.src_high8);
    try testing.expect(d.is_reg_form);
}

test "decode and execute legacy high-byte MOVZX and MOVSX sources" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    var d = decodeInsn(&[_]u8{ 0x0F, 0xB6, 0xD7 }); // movzx edx, bh
    try testing.expectEqual(Op.movzx_reg32_mem8, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.src_reg);
    try testing.expect(d.src_high8);
    state.regs.rbx = 0x0000_0000_0000_5500;
    state.execute(d);
    try testing.expectEqual(@as(u64, 0x55), state.regs.rdx);

    d = decodeInsn(&[_]u8{ 0x0F, 0xBE, 0xD7 }); // movsx edx, bh
    try testing.expectEqual(Op.movsx_reg32_mem8, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.src_reg);
    try testing.expect(d.src_high8);
    state.regs.rbx = 0x0000_0000_0000_8000;
    state.execute(d);
    try testing.expectEqual(@as(u64, 0x0000_0000_FFFF_FF80), state.regs.rdx);
}

test "decode and execute shlq cl r14" {
    const d = decodeInsn(&[_]u8{ 0x49, 0xD3, 0xE6 });
    try testing.expectEqual(Op.shl_reg_cl, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r14b_r14w_r14d_r14, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r14b_r14w_r14d_r14, .bits64, 1);
    state.setReg(.cl_cx_ecx_rcx, .bits8, 7);
    state.execute(d);

    try testing.expectEqual(@as(u64, 128), state.regs.r14);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
    try testing.expect((state.regs.rflags & RFL_SF) == 0);
}

test "decode and execute LAHF and SAHF" {
    const lahf = decodeInsn(&[_]u8{0x9F});
    try testing.expectEqual(Op.lahf, lahf.op);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xAABB_CCDD_EEFF_0011;
    state.regs.rflags = RFL_CF | RFL_AF | RFL_SF | RFL_OF | (1 << 10) | 0x02;
    state.execute(lahf);
    try testing.expectEqual(@as(u8, 0x93), @as(u8, @truncate(state.regs.rax >> 8)));
    try testing.expectEqual(@as(u64, 0xAABB_CCDD_EEFF_9311), state.regs.rax);

    const sahf = decodeInsn(&[_]u8{0x9E});
    try testing.expectEqual(Op.sahf, sahf.op);
    state.regs.rax = (state.regs.rax & 0xFFFF_FFFF_FFFF_00FF) | (@as(u64, 0x44) << 8);
    state.execute(sahf);
    try testing.expectEqual(
        RFL_ZF | RFL_PF | RFL_OF | (1 << 10) | 0x02,
        state.regs.rflags,
    );
}

test "decode and execute shlq imm r9" {
    const d = decodeInsn(&[_]u8{ 0x49, 0xC1, 0xE1, 0x04 });
    try testing.expectEqual(Op.shl_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r9b_r9w_r9d_r9, d.dst_reg);
    try testing.expectEqual(@as(u64, 4), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.r9b_r9w_r9d_r9, .bits64, 3);
    state.execute(d);

    try testing.expectEqual(@as(u64, 48), state.regs.r9);
}

test "decode and execute shr implicit one ecx" {
    const d = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try testing.expectEqual(Op.shr_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.dst_reg);
    try testing.expectEqual(@as(u64, 1), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.cl_cx_ecx_rcx, .bits32, 8);
    state.execute(d);

    try testing.expectEqual(@as(u64, 4), state.regs.rcx);
}

test "CS218 short backward jump consumes its displacement byte" {
    const d = decodeInsn(&[_]u8{ 0xEB, 0xDF });
    try testing.expectEqual(Op.jmp_rel8, d.op);
    try testing.expectEqual(@as(u8, 2), d.len);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -33))), d.imm);
}

test "decode and execute sarq imm rsi" {
    const d = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try testing.expectEqual(Op.sar_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.dst_reg);
    try testing.expectEqual(@as(u64, 3), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.dh_si_esi_rsi, .bits64, @as(u64, @bitCast(@as(i64, -16))));
    state.execute(d);

    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rsi);
    try testing.expect((state.regs.rflags & RFL_SF) != 0);
}

test "decode and execute adcq imm rbx" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x83, 0xD3, 0x00 });
    try testing.expectEqual(Op.adc_reg64_imm8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.bl_bx_ebx_rbx, .bits64, 5);
    state.regs.rflags |= RFL_CF;
    state.execute(d);

    try testing.expectEqual(@as(u64, 6), state.regs.rbx);
    try testing.expect((state.regs.rflags & RFL_CF) == 0);
}

test "decode and execute negl esi" {
    const d = decodeInsn(&[_]u8{ 0xF7, 0xDE });
    try testing.expectEqual(Op.neg_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.dst_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.dh_si_esi_rsi, .bits32, 5);
    state.execute(d);

    try testing.expectEqual(@as(u64, 0xFFFF_FFFB), state.regs.rsi);
    try testing.expect((state.regs.rflags & RFL_CF) != 0);
    try testing.expect((state.regs.rflags & RFL_SF) != 0);
}

test "decode and execute cmovae rbx rcx" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x43, 0xD9 });
    try testing.expectEqual(Op.cmovcc_reg_reg, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expectEqual(Cond.ae, d.cond);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setReg(.bl_bx_ebx_rbx, .bits64, 0);
    state.setReg(.cl_cx_ecx_rcx, .bits64, 42);
    state.regs.rflags &= ~RFL_CF;
    state.execute(d);
    try testing.expectEqual(@as(u64, 42), state.regs.rbx);
}

test "decode lock add byte rip-relative immediate" {
    const d = decodeInsn(&[_]u8{ 0xF0, 0x80, 0x05, 0x28, 0x14, 0x17, 0x00, 0x01 });
    try testing.expectEqual(Op.add_mem8_imm8, d.op);
    try testing.expectEqual(Size.bits8, d.size);
    try testing.expect(d.rip_relative);
    try testing.expectEqual(@as(u64, 0x171428), d.addr);
    try testing.expectEqual(@as(u64, 1), d.imm);
}

test "decode and execute addb immediate to dl" {
    const d = decodeInsn(&[_]u8{ 0x80, 0xC2, 0x0A });
    try testing.expectEqual(Op.add_reg8_imm8, d.op);
    try testing.expectEqual(Size.bits8, d.size);
    try testing.expectEqual(RegId.dl_dx_edx_rdx, d.dst_reg);
    try testing.expectEqual(@as(u64, 10), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rdx = 0x1234_5605;
    state.execute(d);

    try testing.expectEqual(@as(u64, 0x1234_560f), state.regs.rdx);
}

test "decode and execute orl immediate SIB memory" {
    const d = decodeInsn(&[_]u8{ 0x81, 0x4C, 0x31, 0x08, 0x00, 0x20, 0x00, 0x00 });
    try testing.expectEqual(Op.or_mem32_imm32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expect(d.sib_has_base);
    try testing.expect(d.sib_has_index);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.sib_base_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.sib_index_reg);
    try testing.expectEqual(@as(u64, 8), d.addr);
    try testing.expectEqual(@as(u64, 0x2000), d.imm);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rcx = 8;
    state.regs.rsi = MEM_BASE;
    var resolved = d;
    state.sibAddr(&resolved);
    state.write32(resolved.addr, 0x40);
    state.execute(resolved);

    try testing.expectEqual(@as(u32, 0x2040), state.read32(resolved.addr));
}

test "decode and execute sbb eax eax carry mask" {
    const d = decodeInsn(&[_]u8{ 0x19, 0xC0 });
    try testing.expectEqual(Op.sbb_reg32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0;
    state.regs.rflags |= RFL_CF;
    state.execute(d);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rax);
}

test "Xenia reference-count bytes keep a live object across concurrent interpreted and translated workers" {
    // Real Retain/Release instruction bytes, with a counted fake destructor.
    // The table owns one permanent reference, so no worker may reach zero.
    const program = [_]u8{
        0xe8, 0x0f, 0, 0, 0, // call Retain at +20
        0xe8, 0x0f, 0, 0, 0, // call Release at +25
        0x49, 0xff, 0xcf, // dec r15
        0x0f, 0x85, 0xed, 0xff, 0xff, 0xff, // jne loop
        0xf4,
        0xf0, 0xff, 0x41, 0x18, 0xc3, // lock inc dword [rcx+0x18]; ret
        0xf0, 0xff, 0x49, 0x18, 0x75, 0x03, // lock dec [rcx+0x18]; jne ret
        0x83, 0xc2, 0x01, 0xc3, // add edx,1 (premature delete); ret
    };
    try testing.expect(decodeInsn(program[20..]).lock);
    try testing.expect(decodeInsn(program[25..]).lock);
    const Worker = struct {
        state: *ElfState,
        ready: *std.atomic.Value(u32),
        fn run(self: *@This()) void {
            _ = self.ready.fetchAdd(1, .seq_cst);
            while (self.ready.load(.seq_cst) != 4) std.atomic.spinLoopHint();
            self.state.runWithLimit(2_000_000);
        }
    };
    const shared = try testing.allocator.alloc(u8, 0x80000);
    defer testing.allocator.free(shared);
    // Include mixed lanes: real interpreter atomic helpers must interoperate
    // with the ARM translator's host atomics on the same reference word.
    for ([_]u8{ 0, 2, 4 }) |native_workers| {
        @memset(shared, 0);
        @memcpy(shared[0x1000..][0..program.len], &program);
        std.mem.writeInt(u32, shared[0x20018..][0..4], 1, .little);
        var ready = std.atomic.Value(u32).init(0);
        var states: [4]ElfState = undefined;
        var owned_memory: [4][]u8 = undefined;
        for (&states, &owned_memory, 0..) |*state, *owned, i| {
            state.* = ElfState.initWithMemory(testing.allocator, 0x80000);
            owned.* = state.mem;
            state.mem = shared;
            state.windows_runtime_enabled = true;
            state.regs = .{};
            state.regs.rip = MEM_BASE + 0x1000;
            state.regs.rcx = MEM_BASE + 0x20000;
            state.regs.rsp = MEM_BASE + 0x30000 + i * 0x8000;
            state.regs.r15 = 20_000;
            state.block_jit_enabled = i < native_workers;
            state.block_jit_hot_threshold = 2;
        }
        defer for (&states, owned_memory) |*state, owned| {
            state.mem = owned;
            state.deinit();
        };
        var workers: [4]Worker = undefined;
        var threads: [4]std.Thread = undefined;
        var started: usize = 0;
        defer for (threads[0..started]) |thread| thread.join();
        // A host thread creation failure must also release the ready barrier.
        errdefer ready.store(4, .seq_cst);
        for (&workers, &states, &threads) |*worker, *state, *thread| {
            worker.* = .{ .state = state, .ready = &ready };
            thread.* = try std.Thread.spawn(.{}, Worker.run, .{worker});
            started += 1;
        }
        for (threads) |thread| thread.join();
        started = 0;
        try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, shared[0x20018..][0..4], .little));
        for (&states, 0..) |*state, i| {
            try testing.expect(state.terminated and !state.faulted);
            try testing.expectEqual(@as(u64, 0), state.regs.rdx);
            if (i < native_workers) try testing.expect(state.block_jit.?.instructions_retired > 100);
        }
    }
}

test "decode lock cmpxchg memory and setne memory" {
    var d = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB1, 0x0D, 0x8C, 0x07, 0x0C, 0x00 });
    try testing.expectEqual(Op.cmpxchg_mem32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expect(d.rip_relative);

    d = decodeInsn(&[_]u8{ 0x0F, 0x95, 0x45, 0xC8 });
    try testing.expectEqual(Op.setcc_mem8, d.op);
    try testing.expectEqual(Cond.ne, d.cond);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.ch_bp_ebp_rbp, d.sib_base_reg);
}

test "decode lock cmpxchg byte and word atomics" {
    const byte_memory = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB0, 0x11 });
    try testing.expectEqual(Op.cmpxchg_mem8_reg8, byte_memory.op);
    try testing.expectEqual(Size.bits8, byte_memory.size);
    try testing.expectEqual(RegId.dl_dx_edx_rdx, byte_memory.src_reg);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_memory.sib_base_reg);

    const word_memory = decodeInsn(&[_]u8{ 0xF0, 0x66, 0x0F, 0xB1, 0x11 });
    try testing.expectEqual(Op.cmpxchg_mem16_reg16, word_memory.op);
    try testing.expectEqual(Size.bits16, word_memory.size);

    const byte_register = decodeInsn(&[_]u8{ 0x0F, 0xB0, 0xD1 });
    try testing.expectEqual(Op.cmpxchg_reg8_reg8, byte_register.op);
    try testing.expect(byte_register.is_reg_form);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_register.dst_reg);
}

test "locked cmpxchg8b preserves legal unaligned operands" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const address = MEM_BASE + 1;
    const expected: u64 = 0x1122_3344_5566_7788;
    const desired: u64 = 0x99AA_BBCC_DDEE_FF00;
    state.write64(address, expected);
    state.regs.rax = expected & 0xFFFF_FFFF;
    state.regs.rdx = expected >> 32;
    state.regs.rbx = desired & 0xFFFF_FFFF;
    state.regs.rcx = desired >> 32;
    state.execute(.{ .op = .cmpxchg8b_mem, .size = .bits64, .addr = address, .lock = true });
    try testing.expectEqual(desired, state.read64(address));
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
}

test "execute cmpxchg memory success path" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 0);
    state.setReg(.al_ax_eax_rax, .bits32, 0);
    state.setReg(.cl_cx_ecx_rcx, .bits32, 1);
    state.execute(.{
        .op = .cmpxchg_mem32_reg32,
        .size = .bits32,
        .src_reg = .cl_cx_ecx_rcx,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 1), state.read32(addr));
    try testing.expect((state.regs.rflags & RFL_ZF) != 0);
}

test "locked atomics only fall back for their own protected pages" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const protected_page = state.mem_base + 0x40000;
    state.noteGuestPageProtection(protected_page, 0x1000, 0x02, "test", 0);

    // A protected page elsewhere in the process must not disable native
    // atomics for an accessible guest operand.
    const accessible_address = state.mem_base + 0x20000;
    try testing.expect(state.atomicMemoryOperand(accessible_address, .bits64) != null);
    try testing.expect(state.atomicMemoryCompareExchange128(accessible_address, 0, 1) != null);

    // The actual watched page and an access that crosses into it retain the
    // fault-aware interpreter route.
    try testing.expect(state.atomicMemoryOperand(protected_page, .bits32) == null);
    try testing.expect(state.atomicMemoryOperand(protected_page - 4, .bits64) == null);
    try testing.expect(state.atomicMemoryCompareExchange128(protected_page, 0, 1) == null);
}

test "parallel locked update preserves protected-page fault handling atomically" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const address = state.mem_base + 0x50000;
    state.write32(address, 5);
    state.noteGuestPageProtection(address, 0x1000, 0x02, "test", 0);
    state.parallel_guest_execution = true;

    state.execute(.{
        .op = .inc_mem32,
        .size = .bits32,
        .addr = address,
        .lock = true,
    });

    // The direct atomic is refused for a read-only watched page. The
    // serialized slow path computes the architectural result, withholds the
    // protected store, and leaves the normal step-boundary exception record.
    try testing.expectEqual(@as(u32, 5), state.read32(address));
    try testing.expect(state.guest_access_violation_pending);
    try testing.expect(state.guest_access_violation.is_write);
}

test "decode and execute xchg memory eax" {
    const d = decodeInsn(&[_]u8{ 0x87, 0x07 });
    try testing.expectEqual(Op.xchg_mem32_reg32, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.bh_di_edi_rdi, d.sib_base_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 2);
    state.setReg(.al_ax_eax_rax, .bits32, 7);
    state.execute(.{
        .op = .xchg_mem32_reg32,
        .size = .bits32,
        .src_reg = .al_ax_eax_rax,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 7), state.read32(addr));
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
}

test "decode xchg memory rax preserves 64-bit operand size" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x87, 0x07 });
    try testing.expectEqual(Op.xchg_mem64_reg64, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
}

test "decode and execute byte xchg memory and high-byte register forms" {
    const memory_decoded = decodeInsn(&[_]u8{ 0x86, 0x07 });
    try testing.expectEqual(Op.xchg_mem8_reg8, memory_decoded.op);
    try testing.expectEqual(Size.bits8, memory_decoded.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, memory_decoded.src_reg);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const address = MEM_BASE + 0x100;
    state.regs.rdi = address;
    state.regs.rax = 0x77;
    state.write8(address, 0x35);
    var memory_insn = memory_decoded;
    memory_insn.addr = address;
    memory_insn.sib_has_base = false;
    state.execute(memory_insn);
    try testing.expectEqual(@as(u8, 0x77), state.read8(address));
    try testing.expectEqual(@as(u8, 0x35), @as(u8, @truncate(state.regs.rax)));

    const register_decoded = decodeInsn(&[_]u8{ 0x86, 0xE0 }); // xchg al, ah
    try testing.expectEqual(Op.xchg_reg8_reg8, register_decoded.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, register_decoded.dst_reg);
    // High-byte aliases use the base GPR id plus src_high8; the enum member
    // ah_sp_esp_rsp names RSP, not AH.
    try testing.expectEqual(RegId.al_ax_eax_rax, register_decoded.src_reg);
    try testing.expect(register_decoded.src_high8);
    state.regs.rax = 0x1122;
    state.execute(register_decoded);
    try testing.expectEqual(@as(u64, 0x2211), state.regs.rax);
}

test "decode and execute lock xadd memory ecx" {
    const d = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xC1, 0x0D, 0x46, 0xAA, 0x0B, 0x00 });
    try testing.expectEqual(Op.xadd_mem32_reg32, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.src_reg);
    try testing.expect(d.rip_relative);
    try testing.expectEqual(@as(u64, 0x0BAA46), d.addr);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const addr = MEM_BASE;
    state.write32(addr, 41);
    state.setReg(.cl_cx_ecx_rcx, .bits32, 1);
    state.execute(.{
        .op = .xadd_mem32_reg32,
        .size = .bits32,
        .src_reg = .cl_cx_ecx_rcx,
        .addr = addr,
    });
    try testing.expectEqual(@as(u32, 42), state.read32(addr));
    try testing.expectEqual(@as(u64, 41), state.regs.rcx);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "decode and execute xorps zero then movaps store" {
    const zero = decodeInsn(&[_]u8{ 0x0F, 0x57, 0xC0 });
    try testing.expectEqual(Op.xorps_xmm_xmm, zero.op);
    try testing.expectEqual(@as(u8, 0), zero.xmm_dst);
    try testing.expectEqual(@as(u8, 0), zero.xmm_src);

    const load_unaligned = decodeInsn(&[_]u8{ 0x0F, 0x10, 0x06 });
    try testing.expectEqual(Op.movups_xmm_mem, load_unaligned.op);
    try testing.expect(load_unaligned.sib_has_base);
    try testing.expectEqual(RegId.dh_si_esi_rsi, load_unaligned.sib_base_reg);

    const store = decodeInsn(&[_]u8{ 0x0F, 0x29, 0x43, 0x10 });
    try testing.expectEqual(Op.movaps_mem_xmm, store.op);
    try testing.expect(store.sib_has_base);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, store.sib_base_reg);
    try testing.expectEqual(@as(u64, 0x10), store.addr);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.xmm[0] = [_]u8{0xAA} ** 16;
    state.execute(zero);
    state.execute(.{
        .op = .movaps_mem_xmm,
        .addr = MEM_BASE,
        .xmm_src = 0,
    });
    const stored = state.readMem128(MEM_BASE);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), stored[0..]);
}

test "wide guest snapshots and writes forward without draining the TSO buffer" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.parallel_guest_execution = true;

    var buffer: tso_memory.StoreBuffer = .{};
    const prior_mode = tso_memory.setCoordinatedGuestAccess(true);
    defer _ = tso_memory.setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = tso_memory.setActiveStoreBuffer(&buffer);
    defer _ = tso_memory.setActiveStoreBuffer(prior_buffer);
    defer _ = buffer.drain();

    // The 16-byte access straddles a 64-byte cache-line boundary. Each
    // executor-local store remains buffered, and both 8-byte lanes must
    // forward into vector and owned-runtime snapshots without publication.
    const address = MEM_BASE + 0x3F8;
    const low: u64 = 0x1122_3344_AABB_CCDD;
    const high: u64 = 0x8877_6655_DDEE_FF00;
    state.write64(address, low);
    state.write64(address + 8, high);
    try testing.expectEqual(@as(usize, 2), buffer.pendingCount());

    var expected: [16]u8 = undefined;
    std.mem.writeInt(u64, expected[0..8], low, .little);
    std.mem.writeInt(u64, expected[8..16], high, .little);
    const wide_readback = state.readMem128(address);
    try testing.expectEqualSlices(u8, &expected, &wide_readback);
    try testing.expectEqual(@as(usize, 2), buffer.pendingCount());

    var snapshot: [16]u8 = undefined;
    try testing.expect(state.copyFromGuest(&snapshot, address));
    try testing.expectEqualSlices(u8, &expected, &snapshot);
    try testing.expectEqual(@as(usize, 2), buffer.pendingCount());

    // Vector stores use two width-matched lanes even if the host copy of the
    // register is byte-aligned. Data writes retain TSO buffering; the
    // corresponding backing bytes stay untouched until an explicit drain.
    const vector_address = MEM_BASE + 0x600;
    const vector = [_]u8{0xA5} ** 16;
    state.writeMem128(vector_address, vector);
    try testing.expectEqual(@as(usize, 4), buffer.pendingCount());
    const vector_offset: usize = @intCast(state.addrToOffset(vector_address).?);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), state.mem[vector_offset..][0..16]);
    const vector_readback = state.readMem128(vector_address);
    try testing.expectEqualSlices(u8, &vector, &vector_readback);
    try testing.expectEqual(@as(usize, 4), buffer.pendingCount());

    // A bulk fill also emits bounded ordered stores without a pre-write drain.
    const fill_address = MEM_BASE + 0x800;
    try testing.expect(state.fillGuestMemory(fill_address, 16, 0x5A));
    try testing.expectEqual(@as(usize, 6), buffer.pendingCount());
    try testing.expectEqual(@as(u8, 0x5A), state.read8(fill_address));
    const fill_offset: usize = @intCast(state.addrToOffset(fill_address).?);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), state.mem[fill_offset..][0..16]);
}

test "a runtime scalar probe forwards buffered bytes without draining the queue" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.parallel_guest_execution = true;

    var buffer: tso_memory.StoreBuffer = .{};
    const prior_mode = tso_memory.setCoordinatedGuestAccess(true);
    defer _ = tso_memory.setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = tso_memory.setActiveStoreBuffer(&buffer);
    defer _ = tso_memory.setActiveStoreBuffer(prior_buffer);
    defer _ = buffer.drain();

    const address = MEM_BASE + 0xA00;
    const value: u64 = 0xD4C3_B2A1_8877_6655;
    state.write64(address, value);
    const backing_offset: usize = @intCast(state.addrToOffset(address).?);
    try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.mem[backing_offset..][0..8], .little));
    try testing.expectEqual(@as(?u64, value), state.readHostU64(address));
    try testing.expectEqual(@as(usize, 1), buffer.pendingCount());
    try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.mem[backing_offset..][0..8], .little));
}

test "decode and execute shared bit scan instructions" {
    const bsr = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBD, 0xC0 });
    try testing.expectEqual(Op.bsr_reg_reg, bsr.op);
    try testing.expectEqual(Size.bits64, bsr.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, bsr.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, bsr.src_reg);
    try testing.expectEqual(@as(u8, 4), bsr.len);

    const lzcnt = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xBD, 0xC3 });
    try testing.expectEqual(Op.lzcnt_reg_reg, lzcnt.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, lzcnt.src_reg);
    try testing.expectEqual(@as(u8, 5), lzcnt.len);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0x8000_0000_0000_0000;
    state.execute(bsr);
    try testing.expectEqual(@as(u64, 63), state.regs.rax);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "decode and execute shared population count" {
    const exact_fbo_failure = decodeInsn(&[_]u8{ 0xF3, 0x0F, 0xB8, 0xC0, 0x5D, 0xC3 });
    try testing.expectEqual(Op.popcnt_reg_reg, exact_fbo_failure.op);
    try testing.expectEqual(Size.bits32, exact_fbo_failure.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, exact_fbo_failure.dst_reg);
    try testing.expectEqual(RegId.al_ax_eax_rax, exact_fbo_failure.src_reg);
    try testing.expectEqual(@as(u8, 4), exact_fbo_failure.len);

    const memory_16 = decodeInsn(&[_]u8{ 0x66, 0xF3, 0x0F, 0xB8, 0x48, 0x08 });
    try testing.expectEqual(Op.popcnt_reg_mem, memory_16.op);
    try testing.expectEqual(Size.bits16, memory_16.size);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_16.dst_reg);
    try testing.expectEqual(@as(u64, 8), memory_16.addr);

    try testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0x0F, 0xB8, 0xC0 }).op);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xFFFF_FFFF_0000_000B;
    state.regs.rflags = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF | (1 << 10);
    state.execute(exact_fbo_failure);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expectEqual(@as(u32, 1 << 10), state.regs.rflags & (RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF | (1 << 10)));
}

test "decode and execute shared byte swap" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xC8 });
    try testing.expectEqual(Op.bswap_reg, decoded.op);
    try testing.expectEqual(Size.bits32, decoded.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
    try testing.expectEqual(@as(u8, 2), decoded.len);

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rax = 0xFFFF_FFFF_1234_5678;
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 0x7856_3412), state.regs.rax);
}

test "decode 0x48 0x63 0xDB (movsxd rbx, ebx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0x63, 0xDB };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsxd_reg64_reg32, d.op);
}

test "decode movsxd r64 memory SIB form" {
    const d = decodeInsn(&[_]u8{ 0x48, 0x63, 0x04, 0x81 });
    try testing.expectEqual(Op.movsxd_reg64_mem32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expect(d.sib_has_index);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.sib_index_reg);
    try testing.expect(d.sib_has_base);
    try testing.expectEqual(RegId.cl_cx_ecx_rcx, d.sib_base_reg);
    try testing.expectEqual(@as(u2, 2), d.sib_scale);
}

test "decode 0x48 0xC7 0xC3 (mov rbx, imm32)" {
    var bytes: [7]u8 = [_]u8{ 0x48, 0xC7, 0xC3, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
}

test "decode 0x48 0xC7 memory immediate sign extends to 64 bits" {
    const d = decodeInsn(&[_]u8{ 0x48, 0xC7, 0x00, 0xFF, 0xFF, 0xFF, 0xFF });
    try testing.expectEqual(Op.mov_mem64_imm32, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(@as(u64, std.math.maxInt(u64)), d.imm);
}

test "decode 0x66 0x99 (cwd)" {
    var bytes: [2]u8 = [_]u8{ 0x66, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cwd, d.op);
}

test "mul byte [mem] and check result" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Place operands: bNum1=34 at vaddr 0x100267c, bNum3=19 at 0x100267e
    state.write8(0x100267c, 34); // bNum1
    state.write8(0x100267e, 19); // bNum3

    // Set RIP and decode "mov al, byte [bNum1]" + "mul byte [bNum3]" + "mov word [result], ax"
    state.regs.rip = 0x1001160;
    state.regs.rax = 0;

    // Manually execute mov al, [bNum1]
    state.regs.rip = 0x1001160;
    var decoded = decodeInsn(&[_]u8{ 0x8A, 0x04, 0x25, 0x7C, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mov_reg8_mem8, decoded.op);
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 34), state.regs.rax & 0xFF);

    // Execute mul byte [bNum3]
    decoded = decodeInsn(&[_]u8{ 0xF6, 0x24, 0x25, 0x7E, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mul_mem8, decoded.op);
    state.execute(decoded);
    // 34 * 19 = 646 = 0x286
    try testing.expectEqual(@as(u64, 0x286), state.regs.rax & 0xFFFF);
}

test "CS218 AST03 base-12 digit sequence decodes and executes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rdx = '9';
    state.regs.rbx = 0;

    const copy_digit = decodeInsn(&[_]u8{ 0x88, 0xD3 }); // mov bl, dl
    try testing.expectEqual(Op.mov_reg8_reg8, copy_digit.op);
    state.execute(copy_digit);

    const normalize_digit = decodeInsn(&[_]u8{ 0x80, 0xEB, 0x30 }); // sub bl, '0'
    try testing.expectEqual(Op.sub_reg8_imm8, normalize_digit.op);
    state.execute(normalize_digit);

    try testing.expectEqual(@as(u64, 9), state.regs.rbx);
}

test "shared MOV layer executes reverse direction and legacy high bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rdx = 0x5A;
    const reverse = decodeInsn(&[_]u8{ 0x8A, 0xDA }); // mov bl, dl
    try testing.expectEqual(Op.mov_reg8_reg8, reverse.op);
    state.execute(reverse);
    try testing.expectEqual(@as(u64, 0x5A), state.regs.rbx);

    state.regs.rax = 0x1234;
    const high_immediate = decodeInsn(&[_]u8{ 0xB4, 0xAB }); // mov ah, 0xab
    try testing.expect(high_immediate.dst_high8);
    state.execute(high_immediate);
    try testing.expectEqual(@as(u64, 0xAB34), state.regs.rax);

    state.regs.rsp = 0xFF00;
    const rex_low_immediate = decodeInsn(&[_]u8{ 0x40, 0xB4, 0x7C }); // mov spl, 0x7c
    try testing.expect(!rex_low_immediate.dst_high8);
    state.execute(rex_low_immediate);
    try testing.expectEqual(@as(u64, 0xFF7C), state.regs.rsp);
}

test "SETcc writes legacy high-byte destinations" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const setb_ah = decodeInsn(&[_]u8{ 0x0F, 0x92, 0xC4 }); // setb ah
    try testing.expectEqual(Op.setcc_reg8, setb_ah.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, setb_ah.dst_reg);
    try testing.expect(setb_ah.dst_high8);

    state.regs.rax = 0x1234;
    state.regs.rflags = RFL_CF;
    state.execute(setb_ah);
    try testing.expectEqual(@as(u64, 0x0134), state.regs.rax);

    state.regs.rax = 0xFF34;
    state.regs.rflags = 0;
    state.execute(setb_ah);
    try testing.expectEqual(@as(u64, 0x0034), state.regs.rax);
}

test "group-one byte immediate preserves legacy high-byte register aliases" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rax = 0xABFF;
    state.regs.rsp = 0x143FE42F8;
    const and_ah = decodeInsn(&[_]u8{ 0x80, 0xE4, 0x45 }); // and ah, 0x45
    try testing.expectEqual(Op.and_reg8_imm8, and_ah.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, and_ah.dst_reg);
    try testing.expect(and_ah.dst_high8);
    state.execute(and_ah);

    try testing.expectEqual(@as(u64, 0x01FF), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x143FE42F8), state.regs.rsp);
}

test "FS override participates in decoded long-mode memory addresses" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.regs.rip = MEM_BASE + 0x1000;
    state.regs.rax = 0x200;
    state.regs.segments.fs.base = MEM_BASE;
    state.write8(state.regs.rip, 0x64);
    state.write8(state.regs.rip + 1, 0x8A);
    state.write8(state.regs.rip + 2, 0x00); // mov al, fs:[rax]
    state.write8(MEM_BASE + 0x200, 0x7A);

    const decoded = state.decodeAt() orelse return error.ExpectedInstruction;
    try testing.expectEqual(x64_decoder.Segment.fs, decoded.segment);
    try testing.expectEqual(@as(u64, MEM_BASE + 0x200), decoded.addr);
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 0x27A), state.regs.rax);
}

test "PE image decode generation tracks executable writes but ignores data writes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const code = MEM_BASE + 0x1000;
    state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{
        .{ .guest_base = code, .length = 0x100 },
    });
    state.windows_runtime_enabled = true;

    const initial_generation = state.windows_image_code_generation;
    state.write8(MEM_BASE + 0x4000, 0xAA);
    try testing.expectEqual(initial_generation, state.windows_image_code_generation);

    state.write8(code + 0x20, 0xCC);
    try testing.expectEqual(initial_generation + 1, state.windows_image_code_generation);

    // A write that straddles the section boundary still invalidates the
    // cache: at least one instruction byte in the executable range changed.
    state.write16(code + 0xFF, 0x1234);
    try testing.expectEqual(initial_generation + 2, state.windows_image_code_generation);
}

test "in parallel mode an executable write still moves the generation translated code checks" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const code = MEM_BASE + 0x1000;
    state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{
        .{ .guest_base = code, .length = 0x100 },
    });
    state.windows_runtime_enabled = true;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    // Parallel mode used to freeze this counter and compare bytes instead;
    // a translated block's native chain link trusts the counter alone.
    const initial_generation = state.windows_image_code_generation;
    try testing.expectEqual(@as(?u64, initial_generation), state.windowsImageCodeGenerationFor(code, 4));
    state.write8(MEM_BASE + 0x4000, 0xAA);
    try testing.expectEqual(initial_generation, state.windows_image_code_generation);
    state.write8(code + 0x20, 0xCC);
    try testing.expectEqual(initial_generation + 1, state.windows_image_code_generation);
    try testing.expectEqual(@as(?u64, initial_generation + 1), state.windowsImageCodeGenerationFor(code, 4));
}

test "a buffered executable write publishes bytes before its decode generation" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const code = MEM_BASE + 0x1A00;
    state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{
        .{ .guest_base = code, .length = 0x100 },
    });
    state.windows_runtime_enabled = true;
    state.windows_fatal_point_terminate = false;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    state.write8(code, 0xB8); // MOV EAX, imm32.
    state.write32(code + 1, 1);
    state.regs.rip = code;
    try testing.expectEqual(@as(u64, 1), (state.decodeAt() orelse return error.ExpectedInstruction).imm);

    var buffer: tso_memory.StoreBuffer = .{};
    const prior_mode = tso_memory.setCoordinatedGuestAccess(true);
    defer _ = tso_memory.setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = tso_memory.setActiveStoreBuffer(&buffer);
    defer _ = tso_memory.setActiveStoreBuffer(prior_buffer);

    const generation = state.windowsImageCodeGenerationFor(code, 5).?;
    const backing_offset: usize = @intCast(state.addrToOffset(code + 1).?);
    try testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, state.mem[backing_offset..][0..4], .little));

    // write32 enqueues the bytes first. The executable-write boundary must
    // drain them before releasing the generation that makes other decoders
    // trust the newly published instruction.
    state.write32(code + 1, 2);
    try testing.expect(buffer.isEmpty());
    try testing.expectEqual(generation + 1, state.windowsImageCodeGenerationFor(code, 5).?);
    try testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, state.mem[backing_offset..][0..4], .little));
    try testing.expectEqual(@as(u64, 2), (state.decodeAt() orelse return error.ExpectedInstruction).imm);
}

test "parallel worker-local decode cache avoids shared lookup and observes changed bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const code = MEM_BASE + 0x1800;
    state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{
        .{ .guest_base = code, .length = 0x100 },
    });
    state.windows_runtime_enabled = true;
    state.windows_fatal_point_terminate = false;
    state.write8(code, 0xB8); // MOV EAX, imm32.
    state.write32(code + 1, 1);
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    state.regs.rip = code;
    try testing.expectEqual(@as(u64, 1), (state.decodeAt() orelse return error.ExpectedInstruction).imm);
    try testing.expectEqual(@as(u64, 1), (state.decodeAt() orelse return error.ExpectedInstruction).imm);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheWorkerLocalHits());

    // The private tier must keep the exact-byte validation used by the
    // shared tier. A write after cache fill declines the stale local decode;
    // after the shared refill, the new bytes can be cached locally.
    state.write32(code + 1, 2);
    try testing.expectEqual(@as(u64, 2), (state.decodeAt() orelse return error.ExpectedInstruction).imm);
    try testing.expectEqual(@as(u64, 1), state.decodeCacheWorkerLocalHits());
    try testing.expectEqual(@as(u64, 2), (state.decodeAt() orelse return error.ExpectedInstruction).imm);
    try testing.expectEqual(@as(u64, 2), state.decodeCacheWorkerLocalHits());
}

test "arch_prctl sets and reads architectural FS and GS bases" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.invokeLinuxSyscall(SYS_arch_prctl, 0x1002, MEM_BASE + 0x5000, 0, 0, 0, 0);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, MEM_BASE + 0x5000), state.regs.segments.fs.base);

    const output = MEM_BASE + 0x80;
    state.invokeLinuxSyscall(SYS_arch_prctl, 0x1003, output, 0, 0, 0, 0);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, MEM_BASE + 0x5000), state.read64(output));
    try testing.expect(!state.terminated);
    try testing.expect(!state.faulted);
}

test "CS218 file input syscall 2 is handled without terminating the guest" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const path_addr = MEM_BASE;
    const missing_path = "rosette-cs218-file-that-does-not-exist.txt\x00";
    const path_off: usize = @intCast(path_addr - state.mem_base);
    @memcpy(state.mem[path_off..][0..missing_path.len], missing_path);

    state.invokeLinuxSyscall(SYS_open, path_addr, 0, 0, 0, 0, 0);

    try testing.expect(!state.terminated);
    try testing.expect(!state.faulted);
    try testing.expectEqual(x64_syscalls.errnoValue(.no_entry), state.regs.rax);
}

test "cmp reg32 imm8 treats negative 32-bit values as signed negative" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, -2588))));
    state.execute(.{
        .op = .cmp_reg32_imm8,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0,
        .len = 3,
    });

    try testing.expect((state.regs.rflags & RFL_SF) != 0);
    try testing.expect((state.regs.rflags & RFL_OF) == 0);
    try testing.expect(ElfState.evalCond(state.regs.rflags, .l));
    try testing.expect(!ElfState.evalCond(state.regs.rflags, .ge));
}

test "accumulator immediate operations use scalar Group-1 semantics" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.setReg(.al_ax_eax_rax, .bits32, 0x4C);
    state.execute(.{
        .op = .and_accum_imm,
        .size = .bits32,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0x1FF800,
        .len = 5,
    });
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect((state.regs.rflags & RFL_ZF) != 0);

    state.setReg(.al_ax_eax_rax, .bits32, 1);
    state.execute(.{
        .op = .cmp_accum_imm,
        .size = .bits32,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0,
        .len = 5,
    });
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect((state.regs.rflags & RFL_ZF) == 0);
}

test "VEX arithmetic uses NDS operands and advances the guest RIP" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const write_f32 = struct {
        fn at(vector: *[16]u8, lane: usize, value: f32) void {
            std.mem.writeInt(u32, vector[lane * 4 ..][0..4], @bitCast(value), .little);
        }
    }.at;
    for (0..4) |lane| {
        write_f32(&state.xmm[0], lane, @floatFromInt(lane + 1));
        write_f32(&state.xmm[1], lane, @floatFromInt((lane + 1) * 10));
    }
    state.regs.rip = MEM_BASE + 0x400;
    const start = state.regs.rip;
    state.execute(.{
        .op = .vsubps,
        .xmm_dst = 2,
        .xmm_src = 0,
        .xmm_src2 = 1,
        .is_reg_form = true,
        .len = 4,
    });

    try testing.expectEqual(start + 4, state.regs.rip);
    try testing.expectEqual(@as(f32, -9), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[2][0..4], .little))));
    try testing.expectEqual(@as(f32, -36), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[2][12..16], .little))));
    try testing.expect(!state.terminated);
}

test "VEX FMA suffix selects the architectural accumulator" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const write_f32 = struct {
        fn at(vector: *[16]u8, value: f32) void {
            std.mem.writeInt(u32, vector[0..4], @bitCast(value), .little);
        }
    }.at;
    write_f32(&state.xmm[0], 2);
    write_f32(&state.xmm[1], 3);
    write_f32(&state.xmm[2], 4);
    state.regs.rip = MEM_BASE + 0x500;

    state.execute(.{
        .op = .vfmadd132ps,
        .xmm_dst = 2,
        .xmm_src = 0,
        .xmm_src2 = 1,
        .is_reg_form = true,
        .len = 5,
    });

    // VFMADD132PS: dst = (dst * SRC2) + SRC1 = (4 * 3) + 2.
    try testing.expectEqual(@as(f32, 14), @as(f32, @bitCast(std.mem.readInt(u32, state.xmm[2][0..4], .little))));
    try testing.expectEqual(MEM_BASE + 0x505, state.regs.rip);
    try testing.expect(!state.terminated);
}

test "VTEST sign flags ignore floating payload bits in the PE interpreter" {
    var state = ElfState.initWithMemory(std.testing.allocator, 0x8000);
    defer state.deinit();
    for ([_]Op{ .vptest, .vtestps, .vtestpd }) |op| {
        for ([_]bool{ false, true }) |wide| {
            for (0..3) |case| {
                state.xmm[1] = @splat(1);
                state.xmm[2] = @splat(1);
                state.ymm_hi[1] = @splat(1);
                state.ymm_hi[2] = @splat(1);
                const sign_byte: usize = if (op == .vtestpd) 7 else 3;
                const lhs = if (wide) &state.ymm_hi[1] else &state.xmm[1];
                const rhs = if (wide) &state.ymm_hi[2] else &state.xmm[2];
                if (case != 0) rhs[sign_byte] = 0x81;
                if (case == 2) lhs[sign_byte] = 0x81;
                state.regs.rflags = 0x202 | RFL_CF | RFL_ZF | RFL_OF | RFL_SF | RFL_AF | RFL_PF;
                state.executeVectorTest(.{ .op = op, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = true, .vector_256 = wide });
                const expected_zf = op != .vptest and case != 2;
                const expected_cf = case != 1;
                const expected: u32 = 0x202 | (if (expected_zf) RFL_ZF else @as(u32, 0)) | (if (expected_cf) RFL_CF else @as(u32, 0));
                try std.testing.expectEqual(expected, state.regs.rflags);
            }
        }
    }
}

test "unsupported vector operations terminate instead of changing flags" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.regs.rip = MEM_BASE + 0x600;
    state.execute(.{ .op = .vscalefps, .len = 6 });
    try testing.expect(state.terminated);
    try testing.expect(state.faulted);
    try testing.expectEqual(exit_diagnostics.TerminationReason.unimplemented_instruction, state.termination_reason);
    try testing.expectEqual(MEM_BASE + 0x600, state.regs.rip);
}
