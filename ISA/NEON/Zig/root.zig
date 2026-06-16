const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const x86 = @import("../../x86/Zig/root.zig");
const add_adc = @import("ADD/ADC.zig");
const add_adcx = @import("ADD/ADCX.zig");
const add_add = @import("ADD/ADD.zig");
const add_addpd = @import("ADD/ADDPD.zig");
const add_addps = @import("ADD/ADDPS.zig");
const add_addsd = @import("ADD/ADDSD.zig");
const add_addss = @import("ADD/ADDSS.zig");
const add_addsubpd = @import("ADD/ADDSUBPD.zig");
const add_addsubps = @import("ADD/ADDSUBPS.zig");
const add_adox = @import("ADD/ADOX.zig");
const ascii_aaa = @import("ASCII/AAA.zig");
const ascii_aad = @import("ASCII/AAD.zig");
const ascii_aam = @import("ASCII/AAM.zig");
const ascii_aas = @import("ASCII/AAS.zig");
const call_ret_call = @import("CALL-RET/CALL.zig");
const call_ret_leave = @import("CALL-RET/LEAVE.zig");
const call_ret_ret = @import("CALL-RET/RET.zig");
const cmp_cmp = @import("CMP/CMP.zig");
const cmp_cmppd = @import("CMP/CMPPD.zig");
const cmp_cmpps = @import("CMP/CMPPS.zig");
const cmp_cmpsd = @import("CMP/CMPSD.zig");
const cmp_cmpss = @import("CMP/CMPSS.zig");
const div_div = @import("DIV/DIV.zig");
const div_divpd = @import("DIV/DIVPD.zig");
const div_divps = @import("DIV/DIVPS.zig");
const div_divsd = @import("DIV/DIVSD.zig");
const div_divss = @import("DIV/DIVSS.zig");
const div_idiv = @import("DIV/IDIV.zig");
const inc_dec_dec = @import("INC-DEC/DEC.zig");
const inc_dec_inc = @import("INC-DEC/INC.zig");
const jmp_ja = @import("JMP/JA.zig");
const jmp_jae = @import("JMP/JAE.zig");
const jmp_jb = @import("JMP/JB.zig");
const jmp_jbe = @import("JMP/JBE.zig");
const jmp_jc = @import("JMP/JC.zig");
const jmp_jcxz = @import("JMP/JCXZ.zig");
const jmp_je = @import("JMP/JE.zig");
const jmp_jecxz = @import("JMP/JECXZ.zig");
const jmp_jg = @import("JMP/JG.zig");
const jmp_jge = @import("JMP/JGE.zig");
const jmp_jl = @import("JMP/JL.zig");
const jmp_jle = @import("JMP/JLE.zig");
const jmp_jmp = @import("JMP/JMP.zig");
const jmp_jna = @import("JMP/JNA.zig");
const jmp_jnae = @import("JMP/JNAE.zig");
const jmp_jnb = @import("JMP/JNB.zig");
const jmp_jnbe = @import("JMP/JNBE.zig");
const jmp_jnc = @import("JMP/JNC.zig");
const jmp_jne = @import("JMP/JNE.zig");
const jmp_jng = @import("JMP/JNG.zig");
const jmp_jnge = @import("JMP/JNGE.zig");
const jmp_jnl = @import("JMP/JNL.zig");
const jmp_jnle = @import("JMP/JNLE.zig");
const jmp_jno = @import("JMP/JNO.zig");
const jmp_jnp = @import("JMP/JNP.zig");
const jmp_jns = @import("JMP/JNS.zig");
const jmp_jnz = @import("JMP/JNZ.zig");
const jmp_jo = @import("JMP/JO.zig");
const jmp_jp = @import("JMP/JP.zig");
const jmp_jpe = @import("JMP/JPE.zig");
const jmp_jpo = @import("JMP/JPO.zig");
const jmp_jrcxz = @import("JMP/JRCXZ.zig");
const jmp_js = @import("JMP/JS.zig");
const jmp_jz = @import("JMP/JZ.zig");
const load_lahf = @import("LOAD/LAHF.zig");
const load_lar = @import("LOAD/LAR.zig");
const load_lddqu = @import("LOAD/LDDQU.zig");
const load_ldmxcsr = @import("LOAD/LDMXCSR.zig");
const load_lds = @import("LOAD/LDS.zig");
const load_ldtilecfg = @import("LOAD/LDTILECFG.zig");
const load_lea = @import("LOAD/LEA.zig");
const load_les = @import("LOAD/LES.zig");
const load_lfence = @import("LOAD/LFENCE.zig");
const load_lfs = @import("LOAD/LFS.zig");
const load_lgdt = @import("LOAD/LGDT.zig");
const load_lgs = @import("LOAD/LGS.zig");
const load_lidt = @import("LOAD/LIDT.zig");
const load_lldt = @import("LOAD/LLDT.zig");
const load_lmsw = @import("LOAD/LMSW.zig");
const load_loadiwkey = @import("LOAD/LOADIWKEY.zig");
const load_lods = @import("LOAD/LODS.zig");
const load_lodsb = @import("LOAD/LODSB.zig");
const load_lodsd = @import("LOAD/LODSD.zig");
const load_lodsq = @import("LOAD/LODSQ.zig");
const load_lodsw = @import("LOAD/LODSW.zig");
const load_lsl = @import("LOAD/LSL.zig");
const load_lss = @import("LOAD/LSS.zig");
const load_ltr = @import("LOAD/LTR.zig");
const load_fbld = @import("LOAD/FBLD.zig");
const load_fild = @import("LOAD/FILD.zig");
const load_fld = @import("LOAD/FLD.zig");
const load_fld1 = @import("LOAD/FLD1.zig");
const load_fldl2t = @import("LOAD/FLDL2T.zig");
const load_fldl2e = @import("LOAD/FLDL2E.zig");
const load_fldpi = @import("LOAD/FLDPI.zig");
const load_fldlg2 = @import("LOAD/FLDLG2.zig");
const load_fldln2 = @import("LOAD/FLDLN2.zig");
const load_fldz = @import("LOAD/FLDZ.zig");
const load_fldcw = @import("LOAD/FLDCW.zig");
const load_fldenv = @import("LOAD/FLDENV.zig");
const load_tileloadd = @import("LOAD/TILELOADD.zig");
const load_tileloaddt1 = @import("LOAD/TILELOADDT1.zig");
const load_vbroadcastss = @import("LOAD/VBROADCASTSS.zig");
const load_vbroadcastsd = @import("LOAD/VBROADCASTSD.zig");
const load_vbroadcastf128 = @import("LOAD/VBROADCASTF128.zig");
const load_vbroadcastf32x2 = @import("LOAD/VBROADCASTF32X2.zig");
const load_vbroadcastf32x4 = @import("LOAD/VBROADCASTF32X4.zig");
const load_vbroadcastf64x2 = @import("LOAD/VBROADCASTF64X2.zig");
const load_vbroadcastf32x8 = @import("LOAD/VBROADCASTF32X8.zig");
const load_vbroadcastf64x4 = @import("LOAD/VBROADCASTF64X4.zig");
const load_vexpandpd = @import("LOAD/VEXPANDPD.zig");
const load_vexpandps = @import("LOAD/VEXPANDPS.zig");
const load_vpbroadcastb = @import("LOAD/VPBROADCASTB.zig");
const load_vpbroadcastw = @import("LOAD/VPBROADCASTW.zig");
const load_vpbroadcastd = @import("LOAD/VPBROADCASTD.zig");
const load_vpbroadcastq = @import("LOAD/VPBROADCASTQ.zig");
const load_vbroadcasti32x2 = @import("LOAD/VBROADCASTI32X2.zig");
const load_vbroadcasti128 = @import("LOAD/VBROADCASTI128.zig");
const load_vbroadcasti32x4 = @import("LOAD/VBROADCASTI32X4.zig");
const load_vbroadcasti64x2 = @import("LOAD/VBROADCASTI64X2.zig");
const load_vbroadcasti32x8 = @import("LOAD/VBROADCASTI32X8.zig");
const load_vbroadcasti64x4 = @import("LOAD/VBROADCASTI64X4.zig");
const load_vpexpandd = @import("LOAD/VPEXPANDD.zig");
const load_vpexpandq = @import("LOAD/VPEXPANDQ.zig");
const load_xresldtrk = @import("LOAD/XRESLDTRK.zig");
const load_xsusldtrk = @import("LOAD/XSUSLDTRK.zig");
const abort_xabort = @import("ABORT/XABORT.zig");
const begin_xbegin = @import("BEGIN/XBEGIN.zig");
const convert_cbw = @import("CONVERT/CBW.zig");
const convert_cwde = @import("CONVERT/CWDE.zig");
const convert_cdqe = @import("CONVERT/CDQE.zig");
const convert_cwd = @import("CONVERT/CWD.zig");
const convert_cdq = @import("CONVERT/CDQ.zig");
const convert_cqo = @import("CONVERT/CQO.zig");
const halt_hlt = @import("HALT/HLT.zig");
const loop_loop = @import("LOOP/LOOP.zig");
const loop_loope = @import("LOOP/LOOPE.zig");
const loop_loopne = @import("LOOP/LOOPNE.zig");
const loop_pause = @import("LOOP/PAUSE.zig");
const mov_mov = @import("MOV/MOV.zig");
const mov_movapd = @import("MOV/MOVAPD.zig");
const mov_movaps = @import("MOV/MOVAPS.zig");
const mov_movbe = @import("MOV/MOVBE.zig");
const mov_movd = @import("MOV/MOVD.zig");
const mov_movddup = @import("MOV/MOVDDUP.zig");
const mov_movdir64b = @import("MOV/MOVDIR64B.zig");
const mov_movdiri = @import("MOV/MOVDIRI.zig");
const mov_movdq2q = @import("MOV/MOVDQ2Q.zig");
const mov_movdqa = @import("MOV/MOVDQA.zig");
const mov_movdqu = @import("MOV/MOVDQU.zig");
const mov_movhlps = @import("MOV/MOVHLPS.zig");
const mov_movhpd = @import("MOV/MOVHPD.zig");
const mov_movhps = @import("MOV/MOVHPS.zig");
const mov_movlhps = @import("MOV/MOVLHPS.zig");
const mov_movlpd = @import("MOV/MOVLPD.zig");
const mov_movlps = @import("MOV/MOVLPS.zig");
const mov_movmskpd = @import("MOV/MOVMSKPD.zig");
const mov_movmskps = @import("MOV/MOVMSKPS.zig");
const mov_movntdq = @import("MOV/MOVNTDQ.zig");
const mov_movntdqa = @import("MOV/MOVNTDQA.zig");
const mov_movnti = @import("MOV/MOVNTI.zig");
const mov_movntpd = @import("MOV/MOVNTPD.zig");
const mov_movntps = @import("MOV/MOVNTPS.zig");
const mov_movntq = @import("MOV/MOVNTQ.zig");
const mov_movq = @import("MOV/MOVQ.zig");
const mov_movq2dq = @import("MOV/MOVQ2DQ.zig");
const mov_movs = @import("MOV/MOVS.zig");
const mov_movsb = @import("MOV/MOVSB.zig");
const mov_movsd = @import("MOV/MOVSD.zig");
const mov_movshdup = @import("MOV/MOVSHDUP.zig");
const mov_movsldup = @import("MOV/MOVSLDUP.zig");
const mov_movsq = @import("MOV/MOVSQ.zig");
const mov_movss = @import("MOV/MOVSS.zig");
const mov_movsw = @import("MOV/MOVSW.zig");
const mov_movsx = @import("MOV/MOVSX.zig");
const mov_movsxd = @import("MOV/MOVSXD.zig");
const mov_movupd = @import("MOV/MOVUPD.zig");
const mov_movups = @import("MOV/MOVUPS.zig");
const mov_movzx = @import("MOV/MOVZX.zig");
const mov_vmovapd = @import("MOV/VMOVAPD.zig");
const mov_vmovaps = @import("MOV/VMOVAPS.zig");
const mov_vmovd = @import("MOV/VMOVD.zig");
const mov_vmovddup = @import("MOV/VMOVDDUP.zig");
const mov_vmovdqa = @import("MOV/VMOVDQA.zig");
const mov_vmovdqa32 = @import("MOV/VMOVDQA32.zig");
const mov_vmovdqa64 = @import("MOV/VMOVDQA64.zig");
const mov_vmovdqu = @import("MOV/VMOVDQU.zig");
const mov_vmovdqu16 = @import("MOV/VMOVDQU16.zig");
const mov_vmovdqu32 = @import("MOV/VMOVDQU32.zig");
const mov_vmovdqu64 = @import("MOV/VMOVDQU64.zig");
const mov_vmovdqu8 = @import("MOV/VMOVDQU8.zig");
const mov_vmovhlps = @import("MOV/VMOVHLPS.zig");
const mov_vmovhpd = @import("MOV/VMOVHPD.zig");
const mov_vmovhps = @import("MOV/VMOVHPS.zig");
const mov_vmovlhps = @import("MOV/VMOVLHPS.zig");
const mov_vmovlpd = @import("MOV/VMOVLPD.zig");
const mov_vmovlps = @import("MOV/VMOVLPS.zig");
const mov_vmovmskpd = @import("MOV/VMOVMSKPD.zig");
const mov_vmovmskps = @import("MOV/VMOVMSKPS.zig");
const mov_vmovntdq = @import("MOV/VMOVNTDQ.zig");
const mov_vmovntdqa = @import("MOV/VMOVNTDQA.zig");
const mov_vmovntpd = @import("MOV/VMOVNTPD.zig");
const mov_vmovntps = @import("MOV/VMOVNTPS.zig");
const mov_vmovq = @import("MOV/VMOVQ.zig");
const mov_vmovsd = @import("MOV/VMOVSD.zig");
const mov_vmovshdup = @import("MOV/VMOVSHDUP.zig");
const mov_vmovsldup = @import("MOV/VMOVSLDUP.zig");
const mov_vmovss = @import("MOV/VMOVSS.zig");
const mov_vmovupd = @import("MOV/VMOVUPD.zig");
const mov_vmovups = @import("MOV/VMOVUPS.zig");
const mul_imul = @import("MUL/IMUL.zig");
const mul_mul = @import("MUL/MUL.zig");
const mul_mulpd = @import("MUL/MULPD.zig");
const mul_mulps = @import("MUL/MULPS.zig");
const mul_mulsd = @import("MUL/MULSD.zig");
const mul_mulss = @import("MUL/MULSS.zig");
const mul_mulx = @import("MUL/MULX.zig");
const or_or = @import("OR/OR.zig");
const or_orpd = @import("OR/ORPD.zig");
const or_orps = @import("OR/ORPS.zig");
const pop_pop = @import("POP/POP.zig");
const pop_popa = @import("POP/POPA.zig");
const pop_popad = @import("POP/POPAD.zig");
const pop_popcnt = @import("POP/POPCNT.zig");
const push_push = @import("PUSH/PUSH.zig");
const push_pusha = @import("PUSH/PUSHA.zig");
const push_pushad = @import("PUSH/PUSHAD.zig");
const rotate_rcl = @import("ROTATE/RCL.zig");
const rotate_rcr = @import("ROTATE/RCR.zig");
const rotate_rol = @import("ROTATE/ROL.zig");
const rotate_ror = @import("ROTATE/ROR.zig");
const sub_sub = @import("SUB/SUB.zig");
const sub_subpd = @import("SUB/SUBPD.zig");
const sub_subps = @import("SUB/SUBPS.zig");
const sub_subsd = @import("SUB/SUBSD.zig");
const sub_subss = @import("SUB/SUBSS.zig");
const test_test = @import("TEST/TEST.zig");
const test_testui = @import("TEST/TESTUI.zig");
const verify_verr = @import("VERIFY/VERR.zig");
const verify_verw = @import("VERIFY/VERW.zig");
const xor_xor = @import("XOR/XOR.zig");
const xor_xorpd = @import("XOR/XORPD.zig");
const xor_xorps = @import("XOR/XORPS.zig");
const and_and = @import("AND/AND.zig");
const and_andn = @import("AND/ANDN.zig");
const and_andps = @import("AND/ANDPS.zig");
const and_andpd = @import("AND/ANDPD.zig");
const and_andnps = @import("AND/ANDNPS.zig");
const and_andnpd = @import("AND/ANDNPD.zig");
const sys_syscall = @import("SYS/SYSCALL.zig");
const sys_sysenter = @import("SYS/SYSENTER.zig");
const sys_sysexit = @import("SYS/SYSEXIT.zig");
const sys_sysret = @import("SYS/SYSRET.zig");
const blend_blendpd = @import("BLEND/BLENDPD.zig");
const blend_blendps = @import("BLEND/BLENDPS.zig");
const blend_blendvpd = @import("BLEND/BLENDVPD.zig");
const blend_blendvps = @import("BLEND/BLENDVPS.zig");
const bls_blsi = @import("BLS/BLSI.zig");
const bls_blsmsk = @import("BLS/BLSMSK.zig");
const bls_blsr = @import("BLS/BLSR.zig");
const bs_bsf = @import("BS/BSF.zig");
const bs_bsr = @import("BS/BSR.zig");
const bs_bswap = @import("BS/BSWAP.zig");
const bt_bt = @import("BT/BT.zig");
const bt_btc = @import("BT/BTC.zig");
const bt_btr = @import("BT/BTR.zig");
const bt_bts = @import("BT/BTS.zig");
const cache_cldemote = @import("CACHE/CLDEMOTE.zig");
const cache_clflush = @import("CACHE/CLFLUSH.zig");
const cache_clflushopt = @import("CACHE/CLFLUSHOPT.zig");
const sha_sha1msg1 = @import("SHA/SHA1MSG1.zig");
const sha_sha1msg2 = @import("SHA/SHA1MSG2.zig");
const sha_sha1nexte = @import("SHA/SHA1NEXTE.zig");
const sha_sha1rnds4 = @import("SHA/SHA1RNDS4.zig");
const sha_sha256msg1 = @import("SHA/SHA256MSG1.zig");
const sha_sha256msg2 = @import("SHA/SHA256MSG2.zig");
const sha_sha256rnds2 = @import("SHA/SHA256RNDS2.zig");
const terminate_endbr32 = @import("TERMINATE/ENDBR32.zig");
const terminate_endbr64 = @import("TERMINATE/ENDBR64.zig");
const shuffle_shufpd = @import("SHUFFLE/SHUFPD.zig");
const shuffle_shufps = @import("SHUFFLE/SHUFPS.zig");
const shift_sal = @import("SHIFT/SAL.zig");
const shift_sar = @import("SHIFT/SAR.zig");
const shift_shl = @import("SHIFT/SHL.zig");
const shift_shr = @import("SHIFT/SHR.zig");
const shift_shld = @import("SHIFT/SHLD.zig");
const shift_shrd = @import("SHIFT/SHRD.zig");
const shift_sarx = @import("SHIFT/SARX.zig");
const shift_shlx = @import("SHIFT/SHLX.zig");
const shift_shrx = @import("SHIFT/SHRX.zig");
const clear_clac = @import("CLEAR/CLAC.zig");
const clear_clc = @import("CLEAR/CLC.zig");
const clear_cld = @import("CLEAR/CLD.zig");
const clear_cli = @import("CLEAR/CLI.zig");
const clear_clrssbsy = @import("CLEAR/CLRSSBSY.zig");
const clear_clts = @import("CLEAR/CLTS.zig");
const clear_clui = @import("CLEAR/CLUI.zig");
const clear_fclex = @import("CLEAR/FCLEX.zig");
const dot_dppd = @import("DOT_PRODUCT/DPPD.zig");
const dot_dpps = @import("DOT_PRODUCT/DPPS.zig");
const dot_tdpbf16ps = @import("DOT_PRODUCT/TDPBF16PS.zig");
const dot_tdpbssd = @import("DOT_PRODUCT/TDPBSSD.zig");
const dot_tdpbsud = @import("DOT_PRODUCT/TDPBSUD.zig");
const dot_tdpbusd = @import("DOT_PRODUCT/TDPBUSD.zig");
const dot_tdpbuud = @import("DOT_PRODUCT/TDPBUUD.zig");
const dot_vdpbf16ps = @import("DOT_PRODUCT/VDPBF16PS.zig");
const bound_bound = @import("BOUND/BOUND.zig");
const bound_bndcl = @import("BOUND/BNDCL.zig");
const bound_bndcu = @import("BOUND/BNDCU.zig");
const bound_bndcn = @import("BOUND/BNDCN.zig");
const bound_bndldx = @import("BOUND/BNDLDX.zig");
const bound_bndmk = @import("BOUND/BNDMK.zig");
const bound_bndmov = @import("BOUND/BNDMOV.zig");
const bound_bndstx = @import("BOUND/BNDSTX.zig");
const x87_fcom = @import("X87_FPU/FCOM.zig");
const x87_fcomp = @import("X87_FPU/FCOMP.zig");
const x87_fcompp = @import("X87_FPU/FCOMPP.zig");
const x87_fcomi = @import("X87_FPU/FCOMI.zig");
const x87_fcomip = @import("X87_FPU/FCOMIP.zig");
const x87_fucomi = @import("X87_FPU/FUCOMI.zig");
const x87_fucomip = @import("X87_FPU/FUCOMIP.zig");
const x87_ficom = @import("X87_FPU/FICOM.zig");
const x87_ficomp = @import("X87_FPU/FICOMP.zig");
const x87_fucom = @import("X87_FPU/FUCOM.zig");
const x87_fucomp = @import("X87_FPU/FUCOMP.zig");
const x87_fucompp = @import("X87_FPU/FUCOMPP.zig");
const aes_aesdec = @import("AES/AESDEC.zig");
const aes_aesdec128kl = @import("AES/AESDEC128KL.zig");
const aes_aesdec256kl = @import("AES/AESDEC256KL.zig");
const aes_aesdeclast = @import("AES/AESDECLAST.zig");
const aes_aesdecwide128kl = @import("AES/AESDECWIDE128KL.zig");
const aes_aesdecwide256kl = @import("AES/AESDECWIDE256KL.zig");
const aes_aesenc = @import("AES/AESENC.zig");
const aes_aesenc128kl = @import("AES/AESENC128KL.zig");
const aes_aesenc256kl = @import("AES/AESENC256KL.zig");
const aes_aesenclast = @import("AES/AESENCLAST.zig");
const aes_aesencwide128kl = @import("AES/AESENCWIDE128KL.zig");
const aes_aesencwide256kl = @import("AES/AESENCWIDE256KL.zig");
const aes_aesimc = @import("AES/AESIMC.zig");
const aes_aeskeygenassist = @import("AES/AESKEYGENASSIST.zig");
const min_max_pmaxsb = @import("MIN-MAX/PMAXSB.zig");
const min_max_pmaxsw = @import("MIN-MAX/PMAXSW.zig");
const min_max_pmaxsd = @import("MIN-MAX/PMAXSD.zig");
const min_max_pmaxsq = @import("MIN-MAX/PMAXSQ.zig");
const min_max_pmaxub = @import("MIN-MAX/PMAXUB.zig");
const min_max_pmaxuw = @import("MIN-MAX/PMAXUW.zig");
const min_max_pmaxud = @import("MIN-MAX/PMAXUD.zig");
const min_max_pmaxuq = @import("MIN-MAX/PMAXUQ.zig");
const min_max_pminsb = @import("MIN-MAX/PMINSB.zig");
const min_max_pminsw = @import("MIN-MAX/PMINSW.zig");
const min_max_pminsd = @import("MIN-MAX/PMINSD.zig");
const min_max_pminsq = @import("MIN-MAX/PMINSQ.zig");
const min_max_pminub = @import("MIN-MAX/PMINUB.zig");
const min_max_pminuw = @import("MIN-MAX/PMINUW.zig");
const min_max_pminud = @import("MIN-MAX/PMINUD.zig");
const min_max_pminuq = @import("MIN-MAX/PMINUQ.zig");

pub const LoweringKind = enum {
    arm64_scalar,
    neon_vector,
    neon_scalar,
    system_dispatch,
    fallback,
};

pub const MirrorTable = struct {
    path: []const u8,
    source: []const u8,

    pub fn name(self: MirrorTable) []const u8 {
        return anyStringAssignment(self.source, &[_][]const u8{ "name", "instruction" }) orelse mnemonicFromPath(self.path);
    }

    pub fn x86TablePath(self: MirrorTable) []const u8 {
        return stringAssignment(self.source, "x86_table") orelse self.path;
    }

    pub fn neonLowering(self: MirrorTable) []const u8 {
        return anyStringAssignment(self.source, &[_][]const u8{ "neon_lowering", "jit_lowering", "arm64_lowering" }) orelse "arm64_documented_contract_fallback";
    }

    pub fn encodingCount(self: MirrorTable) usize {
        return countEncodingRows(self.source);
    }

    pub fn hasSemantic(self: MirrorTable) bool {
        return hasAnyAssignment(self.source, &[_][]const u8{
            "semantic",
            "semantic_general",
            "semantic_legacy",
            "semantic_one_operand",
            "source_contract",
            "operation",
        });
    }

    pub fn hasFlags(self: MirrorTable) bool {
        return hasAnyAssignment(self.source, &[_][]const u8{
            "flags",
            "flags_read",
            "flags_written",
            "flags_affected",
            "flags_set_or_cleared",
            "flags_model",
            "mxcsr_used",
            "simd_fp_exceptions",
        });
    }

    pub fn hasNeonRegisterModel(self: MirrorTable) bool {
        return hasAnyAssignment(self.source, &[_][]const u8{ "neon_register_model", "arm64_lowering_contract" });
    }

    pub fn hasNeonFlagModel(self: MirrorTable) bool {
        return hasAnyAssignment(self.source, &[_][]const u8{ "neon_flag_model", "arm64_lowering_contract" });
    }

    pub fn hasNeonAssembly(self: MirrorTable) bool {
        return hasAnyAssignment(self.source, &[_][]const u8{ "neon_assembly", "translation", "arm64_lowering_contract" });
    }
};

pub const LoweringPlan = struct {
    x86_name: []const u8,
    x86_lowering: []const u8,
    kind: LoweringKind,
    assembly: []const u8,
    can_lower: bool = true,
};

pub const mirror_tables = [_]MirrorTable{
    mirror(add_adc.family, add_adc.path, add_adc.source),
    mirror(add_adcx.family, add_adcx.path, add_adcx.source),
    mirror(add_add.family, add_add.path, add_add.source),
    mirror(add_addpd.family, add_addpd.path, add_addpd.source),
    mirror(add_addps.family, add_addps.path, add_addps.source),
    mirror(add_addsd.family, add_addsd.path, add_addsd.source),
    mirror(add_addss.family, add_addss.path, add_addss.source),
    mirror(add_addsubpd.family, add_addsubpd.path, add_addsubpd.source),
    mirror(add_addsubps.family, add_addsubps.path, add_addsubps.source),
    mirror(add_adox.family, add_adox.path, add_adox.source),
    mirror(ascii_aaa.family, ascii_aaa.path, ascii_aaa.source),
    mirror(ascii_aad.family, ascii_aad.path, ascii_aad.source),
    mirror(ascii_aam.family, ascii_aam.path, ascii_aam.source),
    mirror(ascii_aas.family, ascii_aas.path, ascii_aas.source),
    mirror(call_ret_call.family, call_ret_call.path, call_ret_call.source),
    mirror(call_ret_leave.family, call_ret_leave.path, call_ret_leave.source),
    mirror(call_ret_ret.family, call_ret_ret.path, call_ret_ret.source),
    mirror(cmp_cmp.family, cmp_cmp.path, cmp_cmp.source),
    mirror(cmp_cmppd.family, cmp_cmppd.path, cmp_cmppd.source),
    mirror(cmp_cmpps.family, cmp_cmpps.path, cmp_cmpps.source),
    mirror(cmp_cmpsd.family, cmp_cmpsd.path, cmp_cmpsd.source),
    mirror(cmp_cmpss.family, cmp_cmpss.path, cmp_cmpss.source),
    mirror(div_div.family, div_div.path, div_div.source),
    mirror(div_divpd.family, div_divpd.path, div_divpd.source),
    mirror(div_divps.family, div_divps.path, div_divps.source),
    mirror(div_divsd.family, div_divsd.path, div_divsd.source),
    mirror(div_divss.family, div_divss.path, div_divss.source),
    mirror(div_idiv.family, div_idiv.path, div_idiv.source),
    mirror(inc_dec_dec.family, inc_dec_dec.path, inc_dec_dec.source),
    mirror(inc_dec_inc.family, inc_dec_inc.path, inc_dec_inc.source),
    mirror(jmp_ja.family, jmp_ja.path, jmp_ja.source),
    mirror(jmp_jae.family, jmp_jae.path, jmp_jae.source),
    mirror(jmp_jb.family, jmp_jb.path, jmp_jb.source),
    mirror(jmp_jbe.family, jmp_jbe.path, jmp_jbe.source),
    mirror(jmp_jc.family, jmp_jc.path, jmp_jc.source),
    mirror(jmp_jcxz.family, jmp_jcxz.path, jmp_jcxz.source),
    mirror(jmp_je.family, jmp_je.path, jmp_je.source),
    mirror(jmp_jecxz.family, jmp_jecxz.path, jmp_jecxz.source),
    mirror(jmp_jg.family, jmp_jg.path, jmp_jg.source),
    mirror(jmp_jge.family, jmp_jge.path, jmp_jge.source),
    mirror(jmp_jl.family, jmp_jl.path, jmp_jl.source),
    mirror(jmp_jle.family, jmp_jle.path, jmp_jle.source),
    mirror(jmp_jmp.family, jmp_jmp.path, jmp_jmp.source),
    mirror(jmp_jna.family, jmp_jna.path, jmp_jna.source),
    mirror(jmp_jnae.family, jmp_jnae.path, jmp_jnae.source),
    mirror(jmp_jnb.family, jmp_jnb.path, jmp_jnb.source),
    mirror(jmp_jnbe.family, jmp_jnbe.path, jmp_jnbe.source),
    mirror(jmp_jnc.family, jmp_jnc.path, jmp_jnc.source),
    mirror(jmp_jne.family, jmp_jne.path, jmp_jne.source),
    mirror(jmp_jng.family, jmp_jng.path, jmp_jng.source),
    mirror(jmp_jnge.family, jmp_jnge.path, jmp_jnge.source),
    mirror(jmp_jnl.family, jmp_jnl.path, jmp_jnl.source),
    mirror(jmp_jnle.family, jmp_jnle.path, jmp_jnle.source),
    mirror(jmp_jno.family, jmp_jno.path, jmp_jno.source),
    mirror(jmp_jnp.family, jmp_jnp.path, jmp_jnp.source),
    mirror(jmp_jns.family, jmp_jns.path, jmp_jns.source),
    mirror(jmp_jnz.family, jmp_jnz.path, jmp_jnz.source),
    mirror(jmp_jo.family, jmp_jo.path, jmp_jo.source),
    mirror(jmp_jp.family, jmp_jp.path, jmp_jp.source),
    mirror(jmp_jpe.family, jmp_jpe.path, jmp_jpe.source),
    mirror(jmp_jpo.family, jmp_jpo.path, jmp_jpo.source),
    mirror(jmp_jrcxz.family, jmp_jrcxz.path, jmp_jrcxz.source),
    mirror(jmp_js.family, jmp_js.path, jmp_js.source),
    mirror(jmp_jz.family, jmp_jz.path, jmp_jz.source),
    mirror(load_lahf.family, load_lahf.path, load_lahf.source),
    mirror(load_lar.family, load_lar.path, load_lar.source),
    mirror(load_lddqu.family, load_lddqu.path, load_lddqu.source),
    mirror(load_ldmxcsr.family, load_ldmxcsr.path, load_ldmxcsr.source),
    mirror(load_lds.family, load_lds.path, load_lds.source),
    mirror(load_ldtilecfg.family, load_ldtilecfg.path, load_ldtilecfg.source),
    mirror(load_lea.family, load_lea.path, load_lea.source),
    mirror(load_les.family, load_les.path, load_les.source),
    mirror(load_lfence.family, load_lfence.path, load_lfence.source),
    mirror(load_lfs.family, load_lfs.path, load_lfs.source),
    mirror(load_lgdt.family, load_lgdt.path, load_lgdt.source),
    mirror(load_lgs.family, load_lgs.path, load_lgs.source),
    mirror(load_lidt.family, load_lidt.path, load_lidt.source),
    mirror(load_lldt.family, load_lldt.path, load_lldt.source),
    mirror(load_lmsw.family, load_lmsw.path, load_lmsw.source),
    mirror(load_loadiwkey.family, load_loadiwkey.path, load_loadiwkey.source),
    mirror(load_lods.family, load_lods.path, load_lods.source),
    mirror(load_lodsb.family, load_lodsb.path, load_lodsb.source),
    mirror(load_lodsd.family, load_lodsd.path, load_lodsd.source),
    mirror(load_lodsq.family, load_lodsq.path, load_lodsq.source),
    mirror(load_lodsw.family, load_lodsw.path, load_lodsw.source),
    mirror(load_lsl.family, load_lsl.path, load_lsl.source),
    mirror(load_lss.family, load_lss.path, load_lss.source),
    mirror(load_ltr.family, load_ltr.path, load_ltr.source),
    mirror(load_fbld.family, load_fbld.path, load_fbld.source),
    mirror(load_fild.family, load_fild.path, load_fild.source),
    mirror(load_fld.family, load_fld.path, load_fld.source),
    mirror(load_fld1.family, load_fld1.path, load_fld1.source),
    mirror(load_fldl2t.family, load_fldl2t.path, load_fldl2t.source),
    mirror(load_fldl2e.family, load_fldl2e.path, load_fldl2e.source),
    mirror(load_fldpi.family, load_fldpi.path, load_fldpi.source),
    mirror(load_fldlg2.family, load_fldlg2.path, load_fldlg2.source),
    mirror(load_fldln2.family, load_fldln2.path, load_fldln2.source),
    mirror(load_fldz.family, load_fldz.path, load_fldz.source),
    mirror(load_fldcw.family, load_fldcw.path, load_fldcw.source),
    mirror(load_fldenv.family, load_fldenv.path, load_fldenv.source),
    mirror(load_tileloadd.family, load_tileloadd.path, load_tileloadd.source),
    mirror(load_tileloaddt1.family, load_tileloaddt1.path, load_tileloaddt1.source),
    mirror(load_vbroadcastss.family, load_vbroadcastss.path, load_vbroadcastss.source),
    mirror(load_vbroadcastsd.family, load_vbroadcastsd.path, load_vbroadcastsd.source),
    mirror(load_vbroadcastf128.family, load_vbroadcastf128.path, load_vbroadcastf128.source),
    mirror(load_vbroadcastf32x2.family, load_vbroadcastf32x2.path, load_vbroadcastf32x2.source),
    mirror(load_vbroadcastf32x4.family, load_vbroadcastf32x4.path, load_vbroadcastf32x4.source),
    mirror(load_vbroadcastf64x2.family, load_vbroadcastf64x2.path, load_vbroadcastf64x2.source),
    mirror(load_vbroadcastf32x8.family, load_vbroadcastf32x8.path, load_vbroadcastf32x8.source),
    mirror(load_vbroadcastf64x4.family, load_vbroadcastf64x4.path, load_vbroadcastf64x4.source),
    mirror(load_vexpandpd.family, load_vexpandpd.path, load_vexpandpd.source),
    mirror(load_vexpandps.family, load_vexpandps.path, load_vexpandps.source),
    mirror(load_vpbroadcastb.family, load_vpbroadcastb.path, load_vpbroadcastb.source),
    mirror(load_vpbroadcastw.family, load_vpbroadcastw.path, load_vpbroadcastw.source),
    mirror(load_vpbroadcastd.family, load_vpbroadcastd.path, load_vpbroadcastd.source),
    mirror(load_vpbroadcastq.family, load_vpbroadcastq.path, load_vpbroadcastq.source),
    mirror(load_vbroadcasti32x2.family, load_vbroadcasti32x2.path, load_vbroadcasti32x2.source),
    mirror(load_vbroadcasti128.family, load_vbroadcasti128.path, load_vbroadcasti128.source),
    mirror(load_vbroadcasti32x4.family, load_vbroadcasti32x4.path, load_vbroadcasti32x4.source),
    mirror(load_vbroadcasti64x2.family, load_vbroadcasti64x2.path, load_vbroadcasti64x2.source),
    mirror(load_vbroadcasti32x8.family, load_vbroadcasti32x8.path, load_vbroadcasti32x8.source),
    mirror(load_vbroadcasti64x4.family, load_vbroadcasti64x4.path, load_vbroadcasti64x4.source),
    mirror(load_vpexpandd.family, load_vpexpandd.path, load_vpexpandd.source),
    mirror(load_vpexpandq.family, load_vpexpandq.path, load_vpexpandq.source),
    mirror(load_xresldtrk.family, load_xresldtrk.path, load_xresldtrk.source),
    mirror(load_xsusldtrk.family, load_xsusldtrk.path, load_xsusldtrk.source),
    mirror(abort_xabort.family, abort_xabort.path, abort_xabort.source),
    mirror(begin_xbegin.family, begin_xbegin.path, begin_xbegin.source),
    mirror(convert_cbw.family, convert_cbw.path, convert_cbw.source),
    mirror(convert_cwde.family, convert_cwde.path, convert_cwde.source),
    mirror(convert_cdqe.family, convert_cdqe.path, convert_cdqe.source),
    mirror(convert_cwd.family, convert_cwd.path, convert_cwd.source),
    mirror(convert_cdq.family, convert_cdq.path, convert_cdq.source),
    mirror(convert_cqo.family, convert_cqo.path, convert_cqo.source),
    mirror(halt_hlt.family, halt_hlt.path, halt_hlt.source),
    mirror(loop_loop.family, loop_loop.path, loop_loop.source),
    mirror(loop_loope.family, loop_loope.path, loop_loope.source),
    mirror(loop_loopne.family, loop_loopne.path, loop_loopne.source),
    mirror(loop_pause.family, loop_pause.path, loop_pause.source),
    mirror(mov_mov.family, mov_mov.path, mov_mov.source),
    mirror(mov_movapd.family, mov_movapd.path, mov_movapd.source),
    mirror(mov_movaps.family, mov_movaps.path, mov_movaps.source),
    mirror(mov_movbe.family, mov_movbe.path, mov_movbe.source),
    mirror(mov_movd.family, mov_movd.path, mov_movd.source),
    mirror(mov_movddup.family, mov_movddup.path, mov_movddup.source),
    mirror(mov_movdir64b.family, mov_movdir64b.path, mov_movdir64b.source),
    mirror(mov_movdiri.family, mov_movdiri.path, mov_movdiri.source),
    mirror(mov_movdq2q.family, mov_movdq2q.path, mov_movdq2q.source),
    mirror(mov_movdqa.family, mov_movdqa.path, mov_movdqa.source),
    mirror(mov_movdqu.family, mov_movdqu.path, mov_movdqu.source),
    mirror(mov_movhlps.family, mov_movhlps.path, mov_movhlps.source),
    mirror(mov_movhpd.family, mov_movhpd.path, mov_movhpd.source),
    mirror(mov_movhps.family, mov_movhps.path, mov_movhps.source),
    mirror(mov_movlhps.family, mov_movlhps.path, mov_movlhps.source),
    mirror(mov_movlpd.family, mov_movlpd.path, mov_movlpd.source),
    mirror(mov_movlps.family, mov_movlps.path, mov_movlps.source),
    mirror(mov_movmskpd.family, mov_movmskpd.path, mov_movmskpd.source),
    mirror(mov_movmskps.family, mov_movmskps.path, mov_movmskps.source),
    mirror(mov_movntdq.family, mov_movntdq.path, mov_movntdq.source),
    mirror(mov_movntdqa.family, mov_movntdqa.path, mov_movntdqa.source),
    mirror(mov_movnti.family, mov_movnti.path, mov_movnti.source),
    mirror(mov_movntpd.family, mov_movntpd.path, mov_movntpd.source),
    mirror(mov_movntps.family, mov_movntps.path, mov_movntps.source),
    mirror(mov_movntq.family, mov_movntq.path, mov_movntq.source),
    mirror(mov_movq.family, mov_movq.path, mov_movq.source),
    mirror(mov_movq2dq.family, mov_movq2dq.path, mov_movq2dq.source),
    mirror(mov_movs.family, mov_movs.path, mov_movs.source),
    mirror(mov_movsb.family, mov_movsb.path, mov_movsb.source),
    mirror(mov_movsd.family, mov_movsd.path, mov_movsd.source),
    mirror(mov_movshdup.family, mov_movshdup.path, mov_movshdup.source),
    mirror(mov_movsldup.family, mov_movsldup.path, mov_movsldup.source),
    mirror(mov_movsq.family, mov_movsq.path, mov_movsq.source),
    mirror(mov_movss.family, mov_movss.path, mov_movss.source),
    mirror(mov_movsw.family, mov_movsw.path, mov_movsw.source),
    mirror(mov_movsx.family, mov_movsx.path, mov_movsx.source),
    mirror(mov_movsxd.family, mov_movsxd.path, mov_movsxd.source),
    mirror(mov_movupd.family, mov_movupd.path, mov_movupd.source),
    mirror(mov_movups.family, mov_movups.path, mov_movups.source),
    mirror(mov_movzx.family, mov_movzx.path, mov_movzx.source),
    mirror(mov_vmovapd.family, mov_vmovapd.path, mov_vmovapd.source),
    mirror(mov_vmovaps.family, mov_vmovaps.path, mov_vmovaps.source),
    mirror(mov_vmovd.family, mov_vmovd.path, mov_vmovd.source),
    mirror(mov_vmovddup.family, mov_vmovddup.path, mov_vmovddup.source),
    mirror(mov_vmovdqa.family, mov_vmovdqa.path, mov_vmovdqa.source),
    mirror(mov_vmovdqa32.family, mov_vmovdqa32.path, mov_vmovdqa32.source),
    mirror(mov_vmovdqa64.family, mov_vmovdqa64.path, mov_vmovdqa64.source),
    mirror(mov_vmovdqu.family, mov_vmovdqu.path, mov_vmovdqu.source),
    mirror(mov_vmovdqu16.family, mov_vmovdqu16.path, mov_vmovdqu16.source),
    mirror(mov_vmovdqu32.family, mov_vmovdqu32.path, mov_vmovdqu32.source),
    mirror(mov_vmovdqu64.family, mov_vmovdqu64.path, mov_vmovdqu64.source),
    mirror(mov_vmovdqu8.family, mov_vmovdqu8.path, mov_vmovdqu8.source),
    mirror(mov_vmovhlps.family, mov_vmovhlps.path, mov_vmovhlps.source),
    mirror(mov_vmovhpd.family, mov_vmovhpd.path, mov_vmovhpd.source),
    mirror(mov_vmovhps.family, mov_vmovhps.path, mov_vmovhps.source),
    mirror(mov_vmovlhps.family, mov_vmovlhps.path, mov_vmovlhps.source),
    mirror(mov_vmovlpd.family, mov_vmovlpd.path, mov_vmovlpd.source),
    mirror(mov_vmovlps.family, mov_vmovlps.path, mov_vmovlps.source),
    mirror(mov_vmovmskpd.family, mov_vmovmskpd.path, mov_vmovmskpd.source),
    mirror(mov_vmovmskps.family, mov_vmovmskps.path, mov_vmovmskps.source),
    mirror(mov_vmovntdq.family, mov_vmovntdq.path, mov_vmovntdq.source),
    mirror(mov_vmovntdqa.family, mov_vmovntdqa.path, mov_vmovntdqa.source),
    mirror(mov_vmovntpd.family, mov_vmovntpd.path, mov_vmovntpd.source),
    mirror(mov_vmovntps.family, mov_vmovntps.path, mov_vmovntps.source),
    mirror(mov_vmovq.family, mov_vmovq.path, mov_vmovq.source),
    mirror(mov_vmovsd.family, mov_vmovsd.path, mov_vmovsd.source),
    mirror(mov_vmovshdup.family, mov_vmovshdup.path, mov_vmovshdup.source),
    mirror(mov_vmovsldup.family, mov_vmovsldup.path, mov_vmovsldup.source),
    mirror(mov_vmovss.family, mov_vmovss.path, mov_vmovss.source),
    mirror(mov_vmovupd.family, mov_vmovupd.path, mov_vmovupd.source),
    mirror(mov_vmovups.family, mov_vmovups.path, mov_vmovups.source),
    mirror(mul_imul.family, mul_imul.path, mul_imul.source),
    mirror(mul_mul.family, mul_mul.path, mul_mul.source),
    mirror(mul_mulpd.family, mul_mulpd.path, mul_mulpd.source),
    mirror(mul_mulps.family, mul_mulps.path, mul_mulps.source),
    mirror(mul_mulsd.family, mul_mulsd.path, mul_mulsd.source),
    mirror(mul_mulss.family, mul_mulss.path, mul_mulss.source),
    mirror(mul_mulx.family, mul_mulx.path, mul_mulx.source),
    mirror(or_or.family, or_or.path, or_or.source),
    mirror(or_orpd.family, or_orpd.path, or_orpd.source),
    mirror(or_orps.family, or_orps.path, or_orps.source),
    mirror(pop_pop.family, pop_pop.path, pop_pop.source),
    mirror(pop_popa.family, pop_popa.path, pop_popa.source),
    mirror(pop_popad.family, pop_popad.path, pop_popad.source),
    mirror(pop_popcnt.family, pop_popcnt.path, pop_popcnt.source),
    mirror(push_push.family, push_push.path, push_push.source),
    mirror(push_pusha.family, push_pusha.path, push_pusha.source),
    mirror(push_pushad.family, push_pushad.path, push_pushad.source),
    mirror(rotate_rcl.family, rotate_rcl.path, rotate_rcl.source),
    mirror(rotate_rcr.family, rotate_rcr.path, rotate_rcr.source),
    mirror(rotate_rol.family, rotate_rol.path, rotate_rol.source),
    mirror(rotate_ror.family, rotate_ror.path, rotate_ror.source),
    mirror(sub_sub.family, sub_sub.path, sub_sub.source),
    mirror(sub_subpd.family, sub_subpd.path, sub_subpd.source),
    mirror(sub_subps.family, sub_subps.path, sub_subps.source),
    mirror(sub_subsd.family, sub_subsd.path, sub_subsd.source),
    mirror(sub_subss.family, sub_subss.path, sub_subss.source),
    mirror(test_test.family, test_test.path, test_test.source),
    mirror(test_testui.family, test_testui.path, test_testui.source),
    mirror(verify_verr.family, verify_verr.path, verify_verr.source),
    mirror(verify_verw.family, verify_verw.path, verify_verw.source),
    mirror(xor_xor.family, xor_xor.path, xor_xor.source),
    mirror(xor_xorpd.family, xor_xorpd.path, xor_xorpd.source),
    mirror(xor_xorps.family, xor_xorps.path, xor_xorps.source),
    mirror(and_and.family, and_and.path, and_and.source),
    mirror(and_andn.family, and_andn.path, and_andn.source),
    mirror(and_andps.family, and_andps.path, and_andps.source),
    mirror(and_andpd.family, and_andpd.path, and_andpd.source),
    mirror(and_andnps.family, and_andnps.path, and_andnps.source),
    mirror(and_andnpd.family, and_andnpd.path, and_andnpd.source),
    mirror(blend_blendpd.family, blend_blendpd.path, blend_blendpd.source),
    mirror(blend_blendps.family, blend_blendps.path, blend_blendps.source),
    mirror(blend_blendvpd.family, blend_blendvpd.path, blend_blendvpd.source),
    mirror(blend_blendvps.family, blend_blendvps.path, blend_blendvps.source),
    mirror(bls_blsi.family, bls_blsi.path, bls_blsi.source),
    mirror(bls_blsmsk.family, bls_blsmsk.path, bls_blsmsk.source),
    mirror(bls_blsr.family, bls_blsr.path, bls_blsr.source),
    mirror(bs_bsf.family, bs_bsf.path, bs_bsf.source),
    mirror(bs_bsr.family, bs_bsr.path, bs_bsr.source),
    mirror(bs_bswap.family, bs_bswap.path, bs_bswap.source),
    mirror(bt_bt.family, bt_bt.path, bt_bt.source),
    mirror(bt_btc.family, bt_btc.path, bt_btc.source),
    mirror(bt_btr.family, bt_btr.path, bt_btr.source),
    mirror(bt_bts.family, bt_bts.path, bt_bts.source),
    mirror(cache_cldemote.family, cache_cldemote.path, cache_cldemote.source),
    mirror(cache_clflush.family, cache_clflush.path, cache_clflush.source),
    mirror(cache_clflushopt.family, cache_clflushopt.path, cache_clflushopt.source),
    mirror(sha_sha1msg1.family, sha_sha1msg1.path, sha_sha1msg1.source),
    mirror(sha_sha1msg2.family, sha_sha1msg2.path, sha_sha1msg2.source),
    mirror(sha_sha1nexte.family, sha_sha1nexte.path, sha_sha1nexte.source),
    mirror(sha_sha1rnds4.family, sha_sha1rnds4.path, sha_sha1rnds4.source),
    mirror(sha_sha256msg1.family, sha_sha256msg1.path, sha_sha256msg1.source),
    mirror(sha_sha256msg2.family, sha_sha256msg2.path, sha_sha256msg2.source),
    mirror(sha_sha256rnds2.family, sha_sha256rnds2.path, sha_sha256rnds2.source),
    mirror(terminate_endbr32.family, terminate_endbr32.path, terminate_endbr32.source),
    mirror(terminate_endbr64.family, terminate_endbr64.path, terminate_endbr64.source),
    mirror(sys_syscall.family, sys_syscall.path, sys_syscall.source),
    mirror(sys_sysenter.family, sys_sysenter.path, sys_sysenter.source),
    mirror(sys_sysexit.family, sys_sysexit.path, sys_sysexit.source),
    mirror(sys_sysret.family, sys_sysret.path, sys_sysret.source),
    mirror(shuffle_shufpd.family, shuffle_shufpd.path, shuffle_shufpd.source),
    mirror(shuffle_shufps.family, shuffle_shufps.path, shuffle_shufps.source),
    mirror(shift_sal.family, shift_sal.path, shift_sal.source),
    mirror(shift_sar.family, shift_sar.path, shift_sar.source),
    mirror(shift_shl.family, shift_shl.path, shift_shl.source),
    mirror(shift_shr.family, shift_shr.path, shift_shr.source),
    mirror(shift_shld.family, shift_shld.path, shift_shld.source),
    mirror(shift_shrd.family, shift_shrd.path, shift_shrd.source),
    mirror(shift_sarx.family, shift_sarx.path, shift_sarx.source),
    mirror(shift_shlx.family, shift_shlx.path, shift_shlx.source),
    mirror(shift_shrx.family, shift_shrx.path, shift_shrx.source),
    mirror(clear_clac.family, clear_clac.path, clear_clac.source),
    mirror(clear_clc.family, clear_clc.path, clear_clc.source),
    mirror(clear_cld.family, clear_cld.path, clear_cld.source),
    mirror(clear_cli.family, clear_cli.path, clear_cli.source),
    mirror(clear_clrssbsy.family, clear_clrssbsy.path, clear_clrssbsy.source),
    mirror(clear_clts.family, clear_clts.path, clear_clts.source),
    mirror(clear_clui.family, clear_clui.path, clear_clui.source),
    mirror(clear_fclex.family, clear_fclex.path, clear_fclex.source),
    mirror(dot_dppd.family, dot_dppd.path, dot_dppd.source),
    mirror(dot_dpps.family, dot_dpps.path, dot_dpps.source),
    mirror(dot_tdpbf16ps.family, dot_tdpbf16ps.path, dot_tdpbf16ps.source),
    mirror(dot_tdpbssd.family, dot_tdpbssd.path, dot_tdpbssd.source),
    mirror(dot_tdpbsud.family, dot_tdpbsud.path, dot_tdpbsud.source),
    mirror(dot_tdpbusd.family, dot_tdpbusd.path, dot_tdpbusd.source),
    mirror(dot_tdpbuud.family, dot_tdpbuud.path, dot_tdpbuud.source),
    mirror(dot_vdpbf16ps.family, dot_vdpbf16ps.path, dot_vdpbf16ps.source),
    mirror(bound_bound.family, bound_bound.path, bound_bound.source),
    mirror(bound_bndcl.family, bound_bndcl.path, bound_bndcl.source),
    mirror(bound_bndcu.family, bound_bndcu.path, bound_bndcu.source),
    mirror(bound_bndcn.family, bound_bndcn.path, bound_bndcn.source),
    mirror(bound_bndldx.family, bound_bndldx.path, bound_bndldx.source),
    mirror(bound_bndmk.family, bound_bndmk.path, bound_bndmk.source),
    mirror(bound_bndmov.family, bound_bndmov.path, bound_bndmov.source),
    mirror(bound_bndstx.family, bound_bndstx.path, bound_bndstx.source),
    mirror(x87_fcom.family, x87_fcom.path, x87_fcom.source),
    mirror(x87_fcomp.family, x87_fcomp.path, x87_fcomp.source),
    mirror(x87_fcompp.family, x87_fcompp.path, x87_fcompp.source),
    mirror(x87_fcomi.family, x87_fcomi.path, x87_fcomi.source),
    mirror(x87_fcomip.family, x87_fcomip.path, x87_fcomip.source),
    mirror(x87_fucomi.family, x87_fucomi.path, x87_fucomi.source),
    mirror(x87_fucomip.family, x87_fucomip.path, x87_fucomip.source),
    mirror(x87_ficom.family, x87_ficom.path, x87_ficom.source),
    mirror(x87_ficomp.family, x87_ficomp.path, x87_ficomp.source),
    mirror(x87_fucom.family, x87_fucom.path, x87_fucom.source),
    mirror(x87_fucomp.family, x87_fucomp.path, x87_fucomp.source),
    mirror(x87_fucompp.family, x87_fucompp.path, x87_fucompp.source),
    mirror(aes_aesdec.family, aes_aesdec.path, aes_aesdec.source),
    mirror(aes_aesdec128kl.family, aes_aesdec128kl.path, aes_aesdec128kl.source),
    mirror(aes_aesdec256kl.family, aes_aesdec256kl.path, aes_aesdec256kl.source),
    mirror(aes_aesdeclast.family, aes_aesdeclast.path, aes_aesdeclast.source),
    mirror(aes_aesdecwide128kl.family, aes_aesdecwide128kl.path, aes_aesdecwide128kl.source),
    mirror(aes_aesdecwide256kl.family, aes_aesdecwide256kl.path, aes_aesdecwide256kl.source),
    mirror(aes_aesenc.family, aes_aesenc.path, aes_aesenc.source),
    mirror(aes_aesenc128kl.family, aes_aesenc128kl.path, aes_aesenc128kl.source),
    mirror(aes_aesenc256kl.family, aes_aesenc256kl.path, aes_aesenc256kl.source),
    mirror(aes_aesenclast.family, aes_aesenclast.path, aes_aesenclast.source),
    mirror(aes_aesencwide128kl.family, aes_aesencwide128kl.path, aes_aesencwide128kl.source),
    mirror(aes_aesencwide256kl.family, aes_aesencwide256kl.path, aes_aesencwide256kl.source),
    mirror(aes_aesimc.family, aes_aesimc.path, aes_aesimc.source),
    mirror(aes_aeskeygenassist.family, aes_aeskeygenassist.path, aes_aeskeygenassist.source),
    mirror(min_max_pmaxsb.family, min_max_pmaxsb.path, min_max_pmaxsb.source),
    mirror(min_max_pmaxsw.family, min_max_pmaxsw.path, min_max_pmaxsw.source),
    mirror(min_max_pmaxsd.family, min_max_pmaxsd.path, min_max_pmaxsd.source),
    mirror(min_max_pmaxsq.family, min_max_pmaxsq.path, min_max_pmaxsq.source),
    mirror(min_max_pmaxub.family, min_max_pmaxub.path, min_max_pmaxub.source),
    mirror(min_max_pmaxuw.family, min_max_pmaxuw.path, min_max_pmaxuw.source),
    mirror(min_max_pmaxud.family, min_max_pmaxud.path, min_max_pmaxud.source),
    mirror(min_max_pmaxuq.family, min_max_pmaxuq.path, min_max_pmaxuq.source),
    mirror(min_max_pminsb.family, min_max_pminsb.path, min_max_pminsb.source),
    mirror(min_max_pminsw.family, min_max_pminsw.path, min_max_pminsw.source),
    mirror(min_max_pminsd.family, min_max_pminsd.path, min_max_pminsd.source),
    mirror(min_max_pminsq.family, min_max_pminsq.path, min_max_pminsq.source),
    mirror(min_max_pminub.family, min_max_pminub.path, min_max_pminub.source),
    mirror(min_max_pminuw.family, min_max_pminuw.path, min_max_pminuw.source),
    mirror(min_max_pminud.family, min_max_pminud.path, min_max_pminud.source),
    mirror(min_max_pminuq.family, min_max_pminuq.path, min_max_pminuq.source),
};

pub fn tableCount() usize {
    return mirror_tables.len;
}

pub fn findMirror(path: []const u8) ?MirrorTable {
    for (mirror_tables) |table| {
        if (std.mem.eql(u8, table.path, path)) return table;
    }
    return null;
}

pub fn planFor(table: x86.InstructionTable) LoweringPlan {
    const meta = table.metadata();
    const mapped = mappedLowering(meta.jit_lowering);
    return .{
        .x86_name = meta.name,
        .x86_lowering = meta.jit_lowering,
        .kind = mapped.kind,
        .assembly = mapped.assembly,
        .can_lower = mapped.can_lower,
    };
}

pub fn validateAll() void {
    runtime_abi.isa.validateMirrorTableCounts(x86.tableCount(), tableCount());
    for (x86.tables) |table| {
        const meta = table.metadata();
        const mirror_table = findMirror(table.path) orelse {
            runtime_abi.isa.validateMissingNeonMirror(table.path);
            continue;
        };
        runtime_abi.isa.validateNeonMirror(.{
            .x86_path = table.path,
            .neon_path = mirror_table.path,
            .declared_x86_table = mirror_table.x86TablePath(),
            .x86_name = meta.name,
            .neon_name = mirror_table.name(),
            .x86_lowering = meta.jit_lowering,
            .neon_lowering = mirror_table.neonLowering(),
            .x86_encoding_count = meta.encoding_count,
            .neon_encoding_count = mirror_table.encodingCount(),
            .x86_has_semantic = meta.has_semantic,
            .neon_has_semantic = mirror_table.hasSemantic(),
            .x86_has_flags = meta.has_flags,
            .neon_has_flags = mirror_table.hasFlags(),
            .neon_has_register_model = mirror_table.hasNeonRegisterModel(),
            .neon_has_flag_model = mirror_table.hasNeonFlagModel(),
            .neon_has_assembly = mirror_table.hasNeonAssembly(),
        });

        const plan = planFor(table);
        runtime_abi.isa.validateNeonLowering(.{
            .name = plan.x86_name,
            .jit_lowering = plan.x86_lowering,
            .kind = @tagName(plan.kind),
            .assembly = plan.assembly,
            .can_lower = plan.can_lower,
        });
    }
}

fn mirror(family: []const u8, path: []const u8, source: []const u8) MirrorTable {
    _ = family;
    return .{ .path = path, .source = source };
}

const MappedLowering = struct {
    kind: LoweringKind,
    assembly: []const u8,
    can_lower: bool = true,
};

fn mappedLowering(lowering: []const u8) MappedLowering {
    if (std.mem.eql(u8, lowering, "arm64_add_with_x86_flags")) return .{ .kind = .arm64_scalar, .assembly = "adds xD, xN, xM\nmrs xFLAGS, nzcv\nbl rosette_pack_x86_add_flags" };
    if (std.mem.eql(u8, lowering, "arm64_adc_with_x86_flags")) return .{ .kind = .arm64_scalar, .assembly = "msr nzcv, x86_carry_to_nzcv(CF)\nadcs xD, xN, xM\nmrs xFLAGS, nzcv\nbl rosette_pack_x86_adc_flags" };
    if (std.mem.eql(u8, lowering, "fallback_or_arm64_adcs_preserve_other_flags")) return .{ .kind = .arm64_scalar, .assembly = "msr nzcv, x86_carry_to_nzcv(CF)\nadcs xD, xN, xM\nbl rosette_preserve_non_cf_status_flags" };
    if (std.mem.eql(u8, lowering, "arm64_add_imm_1_preserve_cf")) return .{ .kind = .arm64_scalar, .assembly = "adds xD, xN, #1\nbl rosette_pack_x86_inc_flags_preserve_cf" };
    if (std.mem.eql(u8, lowering, "arm64_sub_imm_1_preserve_cf")) return .{ .kind = .arm64_scalar, .assembly = "subs xD, xN, #1\nbl rosette_pack_x86_dec_flags_preserve_cf" };
    if (std.mem.eql(u8, lowering, "arm64_sub")) return .{ .kind = .arm64_scalar, .assembly = "subs xD, xN, xM\nmrs xFLAGS, nzcv\nbl rosette_pack_x86_sub_flags" };
    if (std.mem.eql(u8, lowering, "arm64_signed_multiply")) return .{ .kind = .arm64_scalar, .assembly = "smull xTMP, wN, wM\nmul xLO, xN, xM\nasr xHI, xTMP, #32\nbl rosette_pack_x86_imul_flags" };
    if (std.mem.eql(u8, lowering, "arm64_unsigned_multiply")) return .{ .kind = .arm64_scalar, .assembly = "umulh xHI, xN, xM\nmul xLO, xN, xM\nbl rosette_pack_x86_mul_flags" };
    if (std.mem.eql(u8, lowering, "arm64_unsigned_divide")) return .{ .kind = .arm64_scalar, .assembly = "cbz xDIVISOR, rosette_raise_de\nudiv xQ, xDIVIDEND, xDIVISOR\nmsub xR, xQ, xDIVISOR, xDIVIDEND" };
    if (std.mem.eql(u8, lowering, "arm64_signed_divide")) return .{ .kind = .arm64_scalar, .assembly = "cbz xDIVISOR, rosette_raise_de\nsdiv xQ, xDIVIDEND, xDIVISOR\nmsub xR, xQ, xDIVISOR, xDIVIDEND" };
    if (std.mem.eql(u8, lowering, "arm64_mov_or_system_register_dispatch")) return .{ .kind = .system_dispatch, .assembly = "ldr xTMP, [xSRC]\nstr xTMP, [xDST]\nbl rosette_dispatch_system_register_move_if_needed" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fadd_ps")) return .{ .kind = .neon_vector, .assembly = "fadd vD.4s, vN.4s, vM.4s\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fadd_pd")) return .{ .kind = .neon_vector, .assembly = "fadd vD.2d, vN.2d, vM.2d\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_scalar_fadd_s")) return .{ .kind = .neon_scalar, .assembly = "fadd sD, sN, sM\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_scalar_fadd_d")) return .{ .kind = .neon_scalar, .assembly = "fadd dD, dN, dM\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fadd_fsub_by_lane_pattern")) return .{ .kind = .neon_vector, .assembly = "fadd vTMP.4s, vN.4s, vM.4s\nfsub vALT.4s, vN.4s, vM.4s\nbsl vMASK.16b, vTMP.16b, vALT.16b" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fsub_ps")) return .{ .kind = .neon_vector, .assembly = "fsub vD.4s, vN.4s, vM.4s\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fsub_pd")) return .{ .kind = .neon_vector, .assembly = "fsub vD.2d, vN.2d, vM.2d\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fsub_ss")) return .{ .kind = .neon_scalar, .assembly = "fsub sD, sN, sM\nbl rosette_merge_scalar_high_lanes\nbl rosette_apply_mxcsr_float_exceptions" };
    if (std.mem.eql(u8, lowering, "arm64_neon_fsub_sd")) return .{ .kind = .neon_scalar, .assembly = "fsub dD, dN, dM\nbl rosette_merge_scalar_high_lanes\nbl rosette_apply_mxcsr_float_exceptions" };
    return .{ .kind = .fallback, .assembly = "bl rosette_x86_instruction_fallback", .can_lower = false };
}

fn stripLineComment(line: []const u8) []const u8 {
    const idx = std.mem.indexOf(u8, line, "//") orelse return line;
    return line[0..idx];
}

fn assignmentName(line: []const u8) ?[]const u8 {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    return std.mem.trim(u8, line[0..eq], " \t\r");
}

fn stringAssignment(source: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        const name = assignmentName(line) orelse continue;
        if (!std.mem.eql(u8, name, key)) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (value.len < 2 or value[0] != '"') continue;
        const end = std.mem.indexOfScalar(u8, value[1..], '"') orelse continue;
        return value[1 .. 1 + end];
    }
    return null;
}

fn anyStringAssignment(source: []const u8, keys: []const []const u8) ?[]const u8 {
    for (keys) |key| if (stringAssignment(source, key)) |value| return value;
    return null;
}

fn hasAnyAssignment(source: []const u8, keys: []const []const u8) bool {
    for (keys) |key| if (hasAssignment(source, key)) return true;
    return false;
}

fn hasAssignment(source: []const u8, key: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        const name = assignmentName(line) orelse continue;
        if (std.mem.eql(u8, name, key)) return true;
    }
    return false;
}

fn countEncodingRows(source: []const u8) usize {
    if (countToken(source, "X86_INST(") > 0) return countToken(source, "X86_INST(");
    if (countStructuredEncodingRows(source, '[')) |count| return count;
    if (countStructuredEncodingRows(source, '{')) |count| return count;
    if (countSourceContractOpcodeRows(source)) |count| return count;
    return if (hasAnyAssignment(source, &[_][]const u8{ "semantic", "source_contract", "operation" })) 1 else 0;
}

fn countToken(source: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    while (std.mem.indexOf(u8, source[start..], needle)) |rel| {
        count += 1;
        start += rel + needle.len;
    }
    return count;
}

fn countStructuredEncodingRows(source: []const u8, opener: u8) ?usize {
    const block_start = std.mem.indexOf(u8, source, "encodings") orelse return null;
    const open_rel = std.mem.indexOfScalar(u8, source[block_start..], opener) orelse return null;
    const closer: u8 = if (opener == '[') ']' else '}';
    const body_start = block_start + open_rel + 1;
    const body_end_rel = std.mem.indexOfScalar(u8, source[body_start..], closer) orelse return null;
    const body = source[body_start .. body_start + body_end_rel];
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        if (std.mem.startsWith(u8, line, "{")) count += 1;
    }
    return count;
}

fn countSourceContractOpcodeRows(source: []const u8) ?usize {
    const key = "source_contract";
    const block_start = std.mem.indexOf(u8, source, key) orelse return null;
    const triple_rel = std.mem.indexOf(u8, source[block_start..], "\"\"\"") orelse return null;
    const body_start = block_start + triple_rel + 3;
    const body_end_rel = std.mem.indexOf(u8, source[body_start..], "\"\"\"") orelse return null;
    const body = source[body_start .. body_start + body_end_rel];
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (looksLikeOpcodeRow(line)) count += 1;
    }
    return if (count == 0) null else count;
}

fn looksLikeOpcodeRow(line: []const u8) bool {
    if (line.len == 0) return false;
    if (line[0] >= '0' and line[0] <= '9') return true;
    return std.mem.startsWith(u8, line, "REX") or
        std.mem.startsWith(u8, line, "VEX") or
        std.mem.startsWith(u8, line, "EVEX") or
        std.mem.startsWith(u8, line, "F2") or
        std.mem.startsWith(u8, line, "F3") or
        std.mem.startsWith(u8, line, "66 ");
}

fn mnemonicFromPath(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse 0;
    const start = if (path[slash] == '/') slash + 1 else slash;
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len;
    return path[start..dot];
}

test "NEON mirrors every x86 instruction table" {
    try std.testing.expectEqual(x86.tableCount(), tableCount());
    validateAll();
    const add = x86.findByName("ADD") orelse return error.MissingAdd;
    const plan = planFor(add);
    try std.testing.expectEqual(LoweringKind.arm64_scalar, plan.kind);
    try std.testing.expect(std.mem.indexOf(u8, plan.assembly, "adds") != null);
}
