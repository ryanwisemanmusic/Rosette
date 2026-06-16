const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
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

pub const documented_reference_mnemonics = [_][]const u8{
    "AAA",
    "AAD",
    "AAM",
    "AAS",
    "ADC",
    "ADCX",
    "ADD",
    "ADDPD",
    "ADDPS",
    "ADDSD",
    "ADDSS",
    "ADDSUBPD",
    "ADDSUBPS",
    "ADOX",
    "CALL",
    "CMP",
    "CMPPD",
    "CMPPS",
    "CMPSD",
    "CMPSS",
    "DEC",
    "DIV",
    "DIVPD",
    "DIVPS",
    "DIVSD",
    "DIVSS",
    "IDIV",
    "IMUL",
    "INC",
    "JA",
    "JAE",
    "JB",
    "JBE",
    "JC",
    "JCXZ",
    "JE",
    "JECXZ",
    "JG",
    "JGE",
    "JL",
    "JLE",
    "JMP",
    "JNA",
    "JNAE",
    "JNB",
    "JNBE",
    "JNC",
    "JNE",
    "JNG",
    "JNGE",
    "JNL",
    "JNLE",
    "JNO",
    "JNP",
    "JNS",
    "JNZ",
    "JO",
    "JP",
    "JPE",
    "JPO",
    "JRCXZ",
    "JS",
    "JZ",
    "LAHF",
    "LAR",
    "LDDQU",
    "LDMXCSR",
    "LDS",
    "LDTILECFG",
    "LEA",
    "LEAVE",
    "LES",
    "LFENCE",
    "LFS",
    "LGDT",
    "LGS",
    "LIDT",
    "LLDT",
    "LMSW",
    "LOADIWKEY",
    "LODS",
    "LODSB",
    "LODSD",
    "LODSQ",
    "LODSW",
    "LSL",
    "LSS",
    "LTR",
    "FBLD",
    "FILD",
    "FLD",
    "FLD1",
    "FLDL2T",
    "FLDL2E",
    "FLDPI",
    "FLDLG2",
    "FLDLN2",
    "FLDZ",
    "FLDCW",
    "FLDENV",
    "TILELOADD",
    "TILELOADDT1",
    "VBROADCASTSS",
    "VBROADCASTSD",
    "VBROADCASTF128",
    "VBROADCASTF32X2",
    "VBROADCASTF32X4",
    "VBROADCASTF64X2",
    "VBROADCASTF32X8",
    "VBROADCASTF64X4",
    "VEXPANDPD",
    "VEXPANDPS",
    "VPBROADCASTB",
    "VPBROADCASTW",
    "VPBROADCASTD",
    "VPBROADCASTQ",
    "VBROADCASTI32X2",
    "VBROADCASTI128",
    "VBROADCASTI32X4",
    "VBROADCASTI64X2",
    "VBROADCASTI32X8",
    "VBROADCASTI64X4",
    "VERR",
    "VERW",
    "VPEXPANDD",
    "VPEXPANDQ",
    "XABORT",
    "XBEGIN",
    "XRESLDTRK",
    "XSUSLDTRK",
    "CBW",
    "CDQ",
    "CDQE",
    "CQO",
    "CWDE",
    "CWD",
    "HLT",
    "LOOP",
    "LOOPE",
    "LOOPNE",
    "MOV",
    "MOVAPD",
    "MOVAPS",
    "MOVBE",
    "MOVD",
    "MOVDDUP",
    "MOVDIR64B",
    "MOVDIRI",
    "MOVDQ2Q",
    "MOVDQA",
    "MOVDQU",
    "MOVHLPS",
    "MOVHPD",
    "MOVHPS",
    "MOVLHPS",
    "MOVLPD",
    "MOVLPS",
    "MOVMSKPD",
    "MOVMSKPS",
    "MOVNTDQ",
    "MOVNTDQA",
    "MOVNTI",
    "MOVNTPD",
    "MOVNTPS",
    "MOVNTQ",
    "MOVQ",
    "MOVQ2DQ",
    "MOVS",
    "MOVSB",
    "MOVSD",
    "MOVSHDUP",
    "MOVSLDUP",
    "MOVSQ",
    "MOVSS",
    "MOVSW",
    "MOVSX",
    "MOVSXD",
    "MOVUPD",
    "MOVUPS",
    "MOVZX",
    "MUL",
    "MULPD",
    "MULPS",
    "MULSD",
    "MULSS",
    "MULX",
    "PAUSE",
    "OR",
    "ORPD",
    "ORPS",
    "POP",
    "POPA",
    "POPAD",
    "POPCNT",
    "PUSH",
    "PUSHA",
    "PUSHAD",
    "RCL",
    "RCR",
    "RET",
    "ROL",
    "ROR",
    "SUB",
    "SUBPD",
    "SUBPS",
    "SUBSD",
    "SUBSS",
    "TEST",
    "TESTUI",
    "VMOVAPD",
    "VMOVAPS",
    "VMOVD",
    "VMOVDDUP",
    "VMOVDQA",
    "VMOVDQA32",
    "VMOVDQA64",
    "VMOVDQU",
    "VMOVDQU16",
    "VMOVDQU32",
    "VMOVDQU64",
    "VMOVDQU8",
    "VMOVHLPS",
    "VMOVHPD",
    "VMOVHPS",
    "VMOVLHPS",
    "VMOVLPD",
    "VMOVLPS",
    "VMOVMSKPD",
    "VMOVMSKPS",
    "VMOVNTDQ",
    "VMOVNTDQA",
    "VMOVNTPD",
    "VMOVNTPS",
    "VMOVQ",
    "VMOVSD",
    "VMOVSHDUP",
    "VMOVSLDUP",
    "VMOVSS",
    "VMOVUPD",
    "VMOVUPS",
    "XOR",
    "XORPD",
    "XORPS",
    "AND",
    "ANDN",
    "ANDPD",
    "ANDPS",
    "ANDNPD",
    "ANDNPS",
    "BLENDPD",
    "BLENDPS",
    "BLENDVPD",
    "BLENDVPS",
    "BLSI",
    "BLSMSK",
    "BLSR",
    "BSF",
    "BSR",
    "BSWAP",
    "BT",
    "BTC",
    "BTR",
    "BTS",
    "CLDEMOTE",
    "CLFLUSH",
    "CLFLUSHOPT",
    "ENDBR32",
    "ENDBR64",
    "SHA1MSG1",
    "SHA1MSG2",
    "SHA1NEXTE",
    "SHA1RNDS4",
    "SHA256MSG1",
    "SHA256MSG2",
    "SHA256RNDS2",
    "SYSCALL",
    "SYSENTER",
    "SYSEXIT",
    "SYSRET",
    "SHUFPD",
    "SHUFPS",
    "SAL",
    "SAR",
    "SHL",
    "SHR",
    "SHLD",
    "SHRD",
    "SARX",
    "SHLX",
    "SHRX",
    "CLAC",
    "CLC",
    "CLD",
    "CLI",
    "CLRSSBSY",
    "CLTS",
    "CLUI",
    "FCLEX",
    "DPPD",
    "DPPS",
    "TDPBF16PS",
    "TDPBSSD",
    "TDPBSUD",
    "TDPBUSD",
    "TDPBUUD",
    "VDPBF16PS",
    "BOUND",
    "BNDCL",
    "BNDCU",
    "BNDCN",
    "BNDLDX",
    "BNDMK",
    "BNDMOV",
    "BNDSTX",
    "FCOM",
    "FCOMP",
    "FCOMPP",
    "FCOMI",
    "FCOMIP",
    "FUCOMI",
    "FUCOMIP",
    "FICOM",
    "FICOMP",
    "FUCOM",
    "FUCOMP",
    "FUCOMPP",
    "AESDEC",
    "AESDEC128KL",
    "AESDEC256KL",
    "AESDECLAST",
    "AESDECWIDE128KL",
    "AESDECWIDE256KL",
    "AESENC",
    "AESENC128KL",
    "AESENC256KL",
    "AESENCLAST",
    "AESENCWIDE128KL",
    "AESENCWIDE256KL",
    "AESIMC",
    "AESKEYGENASSIST",
    "PMAXSB",
    "PMAXSW",
    "PMAXSD",
    "PMAXSQ",
    "PMAXUB",
    "PMAXUW",
    "PMAXUD",
    "PMAXUQ",
    "PMINSB",
    "PMINSW",
    "PMINSD",
    "PMINSQ",
    "PMINUB",
    "PMINUW",
    "PMINUD",
    "PMINUQ",
};

pub const TableMetadata = struct {
    name: []const u8,
    category: []const u8,
    handler: []const u8,
    jit_lowering: []const u8,
    encoding_count: usize,
    source_path: []const u8,
    has_semantic: bool,
    has_flags: bool,
};

pub const InstructionTable = struct {
    family: []const u8,
    path: []const u8,
    source: []const u8,

    pub fn metadata(self: InstructionTable) TableMetadata {
        return .{
            .name = anyStringAssignment(self.source, &[_][]const u8{ "name", "instruction" }) orelse mnemonicFromPath(self.path),
            .category = stringAssignment(self.source, "category") orelse "documented_contract",
            .handler = anyStringAssignment(self.source, &[_][]const u8{ "handler", "x86_handler" }) orelse "x86_documented_contract_handler",
            .jit_lowering = anyStringAssignment(self.source, &[_][]const u8{ "jit_lowering", "neon_lowering", "arm64_lowering" }) orelse "arm64_documented_contract_fallback",
            .encoding_count = countEncodingRows(self.source),
            .source_path = self.path,
            .has_semantic = hasAnyAssignment(self.source, &[_][]const u8{
                "semantic",
                "semantic_general",
                "semantic_legacy",
                "semantic_one_operand",
                "source_contract",
                "operation",
            }),
            .has_flags = hasAnyAssignment(self.source, &[_][]const u8{
                "flags",
                "flags_read",
                "flags_written",
                "flags_affected",
                "flags_set_or_cleared",
                "flags_model",
                "mxcsr_used",
                "simd_fp_exceptions",
            }),
        };
    }

    pub fn validate(self: InstructionTable) void {
        const meta = self.metadata();
        runtime_abi.isa.validateX86Table(.{
            .name = meta.name,
            .category = meta.category,
            .handler = meta.handler,
            .jit_lowering = meta.jit_lowering,
            .source_path = meta.source_path,
            .encoding_count = meta.encoding_count,
            .has_semantic = meta.has_semantic,
            .has_flags = meta.has_flags,
        });
    }
};

pub const tables = [_]InstructionTable{
    entry(add_adc.family, add_adc.path, add_adc.source),
    entry(add_adcx.family, add_adcx.path, add_adcx.source),
    entry(add_add.family, add_add.path, add_add.source),
    entry(add_addpd.family, add_addpd.path, add_addpd.source),
    entry(add_addps.family, add_addps.path, add_addps.source),
    entry(add_addsd.family, add_addsd.path, add_addsd.source),
    entry(add_addss.family, add_addss.path, add_addss.source),
    entry(add_addsubpd.family, add_addsubpd.path, add_addsubpd.source),
    entry(add_addsubps.family, add_addsubps.path, add_addsubps.source),
    entry(add_adox.family, add_adox.path, add_adox.source),
    entry(ascii_aaa.family, ascii_aaa.path, ascii_aaa.source),
    entry(ascii_aad.family, ascii_aad.path, ascii_aad.source),
    entry(ascii_aam.family, ascii_aam.path, ascii_aam.source),
    entry(ascii_aas.family, ascii_aas.path, ascii_aas.source),
    entry(call_ret_call.family, call_ret_call.path, call_ret_call.source),
    entry(call_ret_leave.family, call_ret_leave.path, call_ret_leave.source),
    entry(call_ret_ret.family, call_ret_ret.path, call_ret_ret.source),
    entry(cmp_cmp.family, cmp_cmp.path, cmp_cmp.source),
    entry(cmp_cmppd.family, cmp_cmppd.path, cmp_cmppd.source),
    entry(cmp_cmpps.family, cmp_cmpps.path, cmp_cmpps.source),
    entry(cmp_cmpsd.family, cmp_cmpsd.path, cmp_cmpsd.source),
    entry(cmp_cmpss.family, cmp_cmpss.path, cmp_cmpss.source),
    entry(div_div.family, div_div.path, div_div.source),
    entry(div_divpd.family, div_divpd.path, div_divpd.source),
    entry(div_divps.family, div_divps.path, div_divps.source),
    entry(div_divsd.family, div_divsd.path, div_divsd.source),
    entry(div_divss.family, div_divss.path, div_divss.source),
    entry(div_idiv.family, div_idiv.path, div_idiv.source),
    entry(inc_dec_dec.family, inc_dec_dec.path, inc_dec_dec.source),
    entry(inc_dec_inc.family, inc_dec_inc.path, inc_dec_inc.source),
    entry(jmp_ja.family, jmp_ja.path, jmp_ja.source),
    entry(jmp_jae.family, jmp_jae.path, jmp_jae.source),
    entry(jmp_jb.family, jmp_jb.path, jmp_jb.source),
    entry(jmp_jbe.family, jmp_jbe.path, jmp_jbe.source),
    entry(jmp_jc.family, jmp_jc.path, jmp_jc.source),
    entry(jmp_jcxz.family, jmp_jcxz.path, jmp_jcxz.source),
    entry(jmp_je.family, jmp_je.path, jmp_je.source),
    entry(jmp_jecxz.family, jmp_jecxz.path, jmp_jecxz.source),
    entry(jmp_jg.family, jmp_jg.path, jmp_jg.source),
    entry(jmp_jge.family, jmp_jge.path, jmp_jge.source),
    entry(jmp_jl.family, jmp_jl.path, jmp_jl.source),
    entry(jmp_jle.family, jmp_jle.path, jmp_jle.source),
    entry(jmp_jmp.family, jmp_jmp.path, jmp_jmp.source),
    entry(jmp_jna.family, jmp_jna.path, jmp_jna.source),
    entry(jmp_jnae.family, jmp_jnae.path, jmp_jnae.source),
    entry(jmp_jnb.family, jmp_jnb.path, jmp_jnb.source),
    entry(jmp_jnbe.family, jmp_jnbe.path, jmp_jnbe.source),
    entry(jmp_jnc.family, jmp_jnc.path, jmp_jnc.source),
    entry(jmp_jne.family, jmp_jne.path, jmp_jne.source),
    entry(jmp_jng.family, jmp_jng.path, jmp_jng.source),
    entry(jmp_jnge.family, jmp_jnge.path, jmp_jnge.source),
    entry(jmp_jnl.family, jmp_jnl.path, jmp_jnl.source),
    entry(jmp_jnle.family, jmp_jnle.path, jmp_jnle.source),
    entry(jmp_jno.family, jmp_jno.path, jmp_jno.source),
    entry(jmp_jnp.family, jmp_jnp.path, jmp_jnp.source),
    entry(jmp_jns.family, jmp_jns.path, jmp_jns.source),
    entry(jmp_jnz.family, jmp_jnz.path, jmp_jnz.source),
    entry(jmp_jo.family, jmp_jo.path, jmp_jo.source),
    entry(jmp_jp.family, jmp_jp.path, jmp_jp.source),
    entry(jmp_jpe.family, jmp_jpe.path, jmp_jpe.source),
    entry(jmp_jpo.family, jmp_jpo.path, jmp_jpo.source),
    entry(jmp_jrcxz.family, jmp_jrcxz.path, jmp_jrcxz.source),
    entry(jmp_js.family, jmp_js.path, jmp_js.source),
    entry(jmp_jz.family, jmp_jz.path, jmp_jz.source),
    entry(load_lahf.family, load_lahf.path, load_lahf.source),
    entry(load_lar.family, load_lar.path, load_lar.source),
    entry(load_lddqu.family, load_lddqu.path, load_lddqu.source),
    entry(load_ldmxcsr.family, load_ldmxcsr.path, load_ldmxcsr.source),
    entry(load_lds.family, load_lds.path, load_lds.source),
    entry(load_ldtilecfg.family, load_ldtilecfg.path, load_ldtilecfg.source),
    entry(load_lea.family, load_lea.path, load_lea.source),
    entry(load_les.family, load_les.path, load_les.source),
    entry(load_lfence.family, load_lfence.path, load_lfence.source),
    entry(load_lfs.family, load_lfs.path, load_lfs.source),
    entry(load_lgdt.family, load_lgdt.path, load_lgdt.source),
    entry(load_lgs.family, load_lgs.path, load_lgs.source),
    entry(load_lidt.family, load_lidt.path, load_lidt.source),
    entry(load_lldt.family, load_lldt.path, load_lldt.source),
    entry(load_lmsw.family, load_lmsw.path, load_lmsw.source),
    entry(load_loadiwkey.family, load_loadiwkey.path, load_loadiwkey.source),
    entry(load_lods.family, load_lods.path, load_lods.source),
    entry(load_lodsb.family, load_lodsb.path, load_lodsb.source),
    entry(load_lodsd.family, load_lodsd.path, load_lodsd.source),
    entry(load_lodsq.family, load_lodsq.path, load_lodsq.source),
    entry(load_lodsw.family, load_lodsw.path, load_lodsw.source),
    entry(load_lsl.family, load_lsl.path, load_lsl.source),
    entry(load_lss.family, load_lss.path, load_lss.source),
    entry(load_ltr.family, load_ltr.path, load_ltr.source),
    entry(load_fbld.family, load_fbld.path, load_fbld.source),
    entry(load_fild.family, load_fild.path, load_fild.source),
    entry(load_fld.family, load_fld.path, load_fld.source),
    entry(load_fld1.family, load_fld1.path, load_fld1.source),
    entry(load_fldl2t.family, load_fldl2t.path, load_fldl2t.source),
    entry(load_fldl2e.family, load_fldl2e.path, load_fldl2e.source),
    entry(load_fldpi.family, load_fldpi.path, load_fldpi.source),
    entry(load_fldlg2.family, load_fldlg2.path, load_fldlg2.source),
    entry(load_fldln2.family, load_fldln2.path, load_fldln2.source),
    entry(load_fldz.family, load_fldz.path, load_fldz.source),
    entry(load_fldcw.family, load_fldcw.path, load_fldcw.source),
    entry(load_fldenv.family, load_fldenv.path, load_fldenv.source),
    entry(load_tileloadd.family, load_tileloadd.path, load_tileloadd.source),
    entry(load_tileloaddt1.family, load_tileloaddt1.path, load_tileloaddt1.source),
    entry(load_vbroadcastss.family, load_vbroadcastss.path, load_vbroadcastss.source),
    entry(load_vbroadcastsd.family, load_vbroadcastsd.path, load_vbroadcastsd.source),
    entry(load_vbroadcastf128.family, load_vbroadcastf128.path, load_vbroadcastf128.source),
    entry(load_vbroadcastf32x2.family, load_vbroadcastf32x2.path, load_vbroadcastf32x2.source),
    entry(load_vbroadcastf32x4.family, load_vbroadcastf32x4.path, load_vbroadcastf32x4.source),
    entry(load_vbroadcastf64x2.family, load_vbroadcastf64x2.path, load_vbroadcastf64x2.source),
    entry(load_vbroadcastf32x8.family, load_vbroadcastf32x8.path, load_vbroadcastf32x8.source),
    entry(load_vbroadcastf64x4.family, load_vbroadcastf64x4.path, load_vbroadcastf64x4.source),
    entry(load_vexpandpd.family, load_vexpandpd.path, load_vexpandpd.source),
    entry(load_vexpandps.family, load_vexpandps.path, load_vexpandps.source),
    entry(load_vpbroadcastb.family, load_vpbroadcastb.path, load_vpbroadcastb.source),
    entry(load_vpbroadcastw.family, load_vpbroadcastw.path, load_vpbroadcastw.source),
    entry(load_vpbroadcastd.family, load_vpbroadcastd.path, load_vpbroadcastd.source),
    entry(load_vpbroadcastq.family, load_vpbroadcastq.path, load_vpbroadcastq.source),
    entry(load_vbroadcasti32x2.family, load_vbroadcasti32x2.path, load_vbroadcasti32x2.source),
    entry(load_vbroadcasti128.family, load_vbroadcasti128.path, load_vbroadcasti128.source),
    entry(load_vbroadcasti32x4.family, load_vbroadcasti32x4.path, load_vbroadcasti32x4.source),
    entry(load_vbroadcasti64x2.family, load_vbroadcasti64x2.path, load_vbroadcasti64x2.source),
    entry(load_vbroadcasti32x8.family, load_vbroadcasti32x8.path, load_vbroadcasti32x8.source),
    entry(load_vbroadcasti64x4.family, load_vbroadcasti64x4.path, load_vbroadcasti64x4.source),
    entry(verify_verr.family, verify_verr.path, verify_verr.source),
    entry(verify_verw.family, verify_verw.path, verify_verw.source),
    entry(load_vpexpandd.family, load_vpexpandd.path, load_vpexpandd.source),
    entry(load_vpexpandq.family, load_vpexpandq.path, load_vpexpandq.source),
    entry(load_xresldtrk.family, load_xresldtrk.path, load_xresldtrk.source),
    entry(load_xsusldtrk.family, load_xsusldtrk.path, load_xsusldtrk.source),
    entry(abort_xabort.family, abort_xabort.path, abort_xabort.source),
    entry(begin_xbegin.family, begin_xbegin.path, begin_xbegin.source),
    entry(convert_cbw.family, convert_cbw.path, convert_cbw.source),
    entry(convert_cwde.family, convert_cwde.path, convert_cwde.source),
    entry(convert_cdqe.family, convert_cdqe.path, convert_cdqe.source),
    entry(convert_cwd.family, convert_cwd.path, convert_cwd.source),
    entry(convert_cdq.family, convert_cdq.path, convert_cdq.source),
    entry(convert_cqo.family, convert_cqo.path, convert_cqo.source),
    entry(halt_hlt.family, halt_hlt.path, halt_hlt.source),
    entry(loop_loop.family, loop_loop.path, loop_loop.source),
    entry(loop_loope.family, loop_loope.path, loop_loope.source),
    entry(loop_loopne.family, loop_loopne.path, loop_loopne.source),
    entry(loop_pause.family, loop_pause.path, loop_pause.source),
    entry(mov_mov.family, mov_mov.path, mov_mov.source),
    entry(mov_movapd.family, mov_movapd.path, mov_movapd.source),
    entry(mov_movaps.family, mov_movaps.path, mov_movaps.source),
    entry(mov_movbe.family, mov_movbe.path, mov_movbe.source),
    entry(mov_movd.family, mov_movd.path, mov_movd.source),
    entry(mov_movddup.family, mov_movddup.path, mov_movddup.source),
    entry(mov_movdir64b.family, mov_movdir64b.path, mov_movdir64b.source),
    entry(mov_movdiri.family, mov_movdiri.path, mov_movdiri.source),
    entry(mov_movdq2q.family, mov_movdq2q.path, mov_movdq2q.source),
    entry(mov_movdqa.family, mov_movdqa.path, mov_movdqa.source),
    entry(mov_movdqu.family, mov_movdqu.path, mov_movdqu.source),
    entry(mov_movhlps.family, mov_movhlps.path, mov_movhlps.source),
    entry(mov_movhpd.family, mov_movhpd.path, mov_movhpd.source),
    entry(mov_movhps.family, mov_movhps.path, mov_movhps.source),
    entry(mov_movlhps.family, mov_movlhps.path, mov_movlhps.source),
    entry(mov_movlpd.family, mov_movlpd.path, mov_movlpd.source),
    entry(mov_movlps.family, mov_movlps.path, mov_movlps.source),
    entry(mov_movmskpd.family, mov_movmskpd.path, mov_movmskpd.source),
    entry(mov_movmskps.family, mov_movmskps.path, mov_movmskps.source),
    entry(mov_movntdq.family, mov_movntdq.path, mov_movntdq.source),
    entry(mov_movntdqa.family, mov_movntdqa.path, mov_movntdqa.source),
    entry(mov_movnti.family, mov_movnti.path, mov_movnti.source),
    entry(mov_movntpd.family, mov_movntpd.path, mov_movntpd.source),
    entry(mov_movntps.family, mov_movntps.path, mov_movntps.source),
    entry(mov_movntq.family, mov_movntq.path, mov_movntq.source),
    entry(mov_movq.family, mov_movq.path, mov_movq.source),
    entry(mov_movq2dq.family, mov_movq2dq.path, mov_movq2dq.source),
    entry(mov_movs.family, mov_movs.path, mov_movs.source),
    entry(mov_movsb.family, mov_movsb.path, mov_movsb.source),
    entry(mov_movsd.family, mov_movsd.path, mov_movsd.source),
    entry(mov_movshdup.family, mov_movshdup.path, mov_movshdup.source),
    entry(mov_movsldup.family, mov_movsldup.path, mov_movsldup.source),
    entry(mov_movsq.family, mov_movsq.path, mov_movsq.source),
    entry(mov_movss.family, mov_movss.path, mov_movss.source),
    entry(mov_movsw.family, mov_movsw.path, mov_movsw.source),
    entry(mov_movsx.family, mov_movsx.path, mov_movsx.source),
    entry(mov_movsxd.family, mov_movsxd.path, mov_movsxd.source),
    entry(mov_movupd.family, mov_movupd.path, mov_movupd.source),
    entry(mov_movups.family, mov_movups.path, mov_movups.source),
    entry(mov_movzx.family, mov_movzx.path, mov_movzx.source),
    entry(mov_vmovapd.family, mov_vmovapd.path, mov_vmovapd.source),
    entry(mov_vmovaps.family, mov_vmovaps.path, mov_vmovaps.source),
    entry(mov_vmovd.family, mov_vmovd.path, mov_vmovd.source),
    entry(mov_vmovddup.family, mov_vmovddup.path, mov_vmovddup.source),
    entry(mov_vmovdqa.family, mov_vmovdqa.path, mov_vmovdqa.source),
    entry(mov_vmovdqa32.family, mov_vmovdqa32.path, mov_vmovdqa32.source),
    entry(mov_vmovdqa64.family, mov_vmovdqa64.path, mov_vmovdqa64.source),
    entry(mov_vmovdqu.family, mov_vmovdqu.path, mov_vmovdqu.source),
    entry(mov_vmovdqu16.family, mov_vmovdqu16.path, mov_vmovdqu16.source),
    entry(mov_vmovdqu32.family, mov_vmovdqu32.path, mov_vmovdqu32.source),
    entry(mov_vmovdqu64.family, mov_vmovdqu64.path, mov_vmovdqu64.source),
    entry(mov_vmovdqu8.family, mov_vmovdqu8.path, mov_vmovdqu8.source),
    entry(mov_vmovhlps.family, mov_vmovhlps.path, mov_vmovhlps.source),
    entry(mov_vmovhpd.family, mov_vmovhpd.path, mov_vmovhpd.source),
    entry(mov_vmovhps.family, mov_vmovhps.path, mov_vmovhps.source),
    entry(mov_vmovlhps.family, mov_vmovlhps.path, mov_vmovlhps.source),
    entry(mov_vmovlpd.family, mov_vmovlpd.path, mov_vmovlpd.source),
    entry(mov_vmovlps.family, mov_vmovlps.path, mov_vmovlps.source),
    entry(mov_vmovmskpd.family, mov_vmovmskpd.path, mov_vmovmskpd.source),
    entry(mov_vmovmskps.family, mov_vmovmskps.path, mov_vmovmskps.source),
    entry(mov_vmovntdq.family, mov_vmovntdq.path, mov_vmovntdq.source),
    entry(mov_vmovntdqa.family, mov_vmovntdqa.path, mov_vmovntdqa.source),
    entry(mov_vmovntpd.family, mov_vmovntpd.path, mov_vmovntpd.source),
    entry(mov_vmovntps.family, mov_vmovntps.path, mov_vmovntps.source),
    entry(mov_vmovq.family, mov_vmovq.path, mov_vmovq.source),
    entry(mov_vmovsd.family, mov_vmovsd.path, mov_vmovsd.source),
    entry(mov_vmovshdup.family, mov_vmovshdup.path, mov_vmovshdup.source),
    entry(mov_vmovsldup.family, mov_vmovsldup.path, mov_vmovsldup.source),
    entry(mov_vmovss.family, mov_vmovss.path, mov_vmovss.source),
    entry(mov_vmovupd.family, mov_vmovupd.path, mov_vmovupd.source),
    entry(mov_vmovups.family, mov_vmovups.path, mov_vmovups.source),
    entry(mul_imul.family, mul_imul.path, mul_imul.source),
    entry(mul_mul.family, mul_mul.path, mul_mul.source),
    entry(mul_mulpd.family, mul_mulpd.path, mul_mulpd.source),
    entry(mul_mulps.family, mul_mulps.path, mul_mulps.source),
    entry(mul_mulsd.family, mul_mulsd.path, mul_mulsd.source),
    entry(mul_mulss.family, mul_mulss.path, mul_mulss.source),
    entry(mul_mulx.family, mul_mulx.path, mul_mulx.source),
    entry(or_or.family, or_or.path, or_or.source),
    entry(or_orpd.family, or_orpd.path, or_orpd.source),
    entry(or_orps.family, or_orps.path, or_orps.source),
    entry(pop_pop.family, pop_pop.path, pop_pop.source),
    entry(pop_popa.family, pop_popa.path, pop_popa.source),
    entry(pop_popad.family, pop_popad.path, pop_popad.source),
    entry(pop_popcnt.family, pop_popcnt.path, pop_popcnt.source),
    entry(push_push.family, push_push.path, push_push.source),
    entry(push_pusha.family, push_pusha.path, push_pusha.source),
    entry(push_pushad.family, push_pushad.path, push_pushad.source),
    entry(rotate_rcl.family, rotate_rcl.path, rotate_rcl.source),
    entry(rotate_rcr.family, rotate_rcr.path, rotate_rcr.source),
    entry(rotate_rol.family, rotate_rol.path, rotate_rol.source),
    entry(rotate_ror.family, rotate_ror.path, rotate_ror.source),
    entry(sub_sub.family, sub_sub.path, sub_sub.source),
    entry(sub_subpd.family, sub_subpd.path, sub_subpd.source),
    entry(sub_subps.family, sub_subps.path, sub_subps.source),
    entry(sub_subsd.family, sub_subsd.path, sub_subsd.source),
    entry(sub_subss.family, sub_subss.path, sub_subss.source),
    entry(test_test.family, test_test.path, test_test.source),
    entry(test_testui.family, test_testui.path, test_testui.source),
    entry(xor_xor.family, xor_xor.path, xor_xor.source),
    entry(xor_xorpd.family, xor_xorpd.path, xor_xorpd.source),
    entry(xor_xorps.family, xor_xorps.path, xor_xorps.source),
    entry(and_and.family, and_and.path, and_and.source),
    entry(and_andn.family, and_andn.path, and_andn.source),
    entry(and_andps.family, and_andps.path, and_andps.source),
    entry(and_andpd.family, and_andpd.path, and_andpd.source),
    entry(and_andnps.family, and_andnps.path, and_andnps.source),
    entry(and_andnpd.family, and_andnpd.path, and_andnpd.source),
    entry(blend_blendpd.family, blend_blendpd.path, blend_blendpd.source),
    entry(blend_blendps.family, blend_blendps.path, blend_blendps.source),
    entry(blend_blendvpd.family, blend_blendvpd.path, blend_blendvpd.source),
    entry(blend_blendvps.family, blend_blendvps.path, blend_blendvps.source),
    entry(bls_blsi.family, bls_blsi.path, bls_blsi.source),
    entry(bls_blsmsk.family, bls_blsmsk.path, bls_blsmsk.source),
    entry(bls_blsr.family, bls_blsr.path, bls_blsr.source),
    entry(bs_bsf.family, bs_bsf.path, bs_bsf.source),
    entry(bs_bsr.family, bs_bsr.path, bs_bsr.source),
    entry(bs_bswap.family, bs_bswap.path, bs_bswap.source),
    entry(bt_bt.family, bt_bt.path, bt_bt.source),
    entry(bt_btc.family, bt_btc.path, bt_btc.source),
    entry(bt_btr.family, bt_btr.path, bt_btr.source),
    entry(bt_bts.family, bt_bts.path, bt_bts.source),
    entry(cache_cldemote.family, cache_cldemote.path, cache_cldemote.source),
    entry(cache_clflush.family, cache_clflush.path, cache_clflush.source),
    entry(cache_clflushopt.family, cache_clflushopt.path, cache_clflushopt.source),
    entry(sha_sha1msg1.family, sha_sha1msg1.path, sha_sha1msg1.source),
    entry(sha_sha1msg2.family, sha_sha1msg2.path, sha_sha1msg2.source),
    entry(sha_sha1nexte.family, sha_sha1nexte.path, sha_sha1nexte.source),
    entry(sha_sha1rnds4.family, sha_sha1rnds4.path, sha_sha1rnds4.source),
    entry(sha_sha256msg1.family, sha_sha256msg1.path, sha_sha256msg1.source),
    entry(sha_sha256msg2.family, sha_sha256msg2.path, sha_sha256msg2.source),
    entry(sha_sha256rnds2.family, sha_sha256rnds2.path, sha_sha256rnds2.source),
    entry(terminate_endbr32.family, terminate_endbr32.path, terminate_endbr32.source),
    entry(terminate_endbr64.family, terminate_endbr64.path, terminate_endbr64.source),
    entry(sys_syscall.family, sys_syscall.path, sys_syscall.source),
    entry(sys_sysenter.family, sys_sysenter.path, sys_sysenter.source),
    entry(sys_sysexit.family, sys_sysexit.path, sys_sysexit.source),
    entry(sys_sysret.family, sys_sysret.path, sys_sysret.source),
    entry(shuffle_shufpd.family, shuffle_shufpd.path, shuffle_shufpd.source),
    entry(shuffle_shufps.family, shuffle_shufps.path, shuffle_shufps.source),
    entry(shift_sal.family, shift_sal.path, shift_sal.source),
    entry(shift_sar.family, shift_sar.path, shift_sar.source),
    entry(shift_shl.family, shift_shl.path, shift_shl.source),
    entry(shift_shr.family, shift_shr.path, shift_shr.source),
    entry(shift_shld.family, shift_shld.path, shift_shld.source),
    entry(shift_shrd.family, shift_shrd.path, shift_shrd.source),
    entry(shift_sarx.family, shift_sarx.path, shift_sarx.source),
    entry(shift_shlx.family, shift_shlx.path, shift_shlx.source),
    entry(shift_shrx.family, shift_shrx.path, shift_shrx.source),
    entry(clear_clac.family, clear_clac.path, clear_clac.source),
    entry(clear_clc.family, clear_clc.path, clear_clc.source),
    entry(clear_cld.family, clear_cld.path, clear_cld.source),
    entry(clear_cli.family, clear_cli.path, clear_cli.source),
    entry(clear_clrssbsy.family, clear_clrssbsy.path, clear_clrssbsy.source),
    entry(clear_clts.family, clear_clts.path, clear_clts.source),
    entry(clear_clui.family, clear_clui.path, clear_clui.source),
    entry(clear_fclex.family, clear_fclex.path, clear_fclex.source),
    entry(dot_dppd.family, dot_dppd.path, dot_dppd.source),
    entry(dot_dpps.family, dot_dpps.path, dot_dpps.source),
    entry(dot_tdpbf16ps.family, dot_tdpbf16ps.path, dot_tdpbf16ps.source),
    entry(dot_tdpbssd.family, dot_tdpbssd.path, dot_tdpbssd.source),
    entry(dot_tdpbsud.family, dot_tdpbsud.path, dot_tdpbsud.source),
    entry(dot_tdpbusd.family, dot_tdpbusd.path, dot_tdpbusd.source),
    entry(dot_tdpbuud.family, dot_tdpbuud.path, dot_tdpbuud.source),
    entry(dot_vdpbf16ps.family, dot_vdpbf16ps.path, dot_vdpbf16ps.source),
    entry(bound_bound.family, bound_bound.path, bound_bound.source),
    entry(bound_bndcl.family, bound_bndcl.path, bound_bndcl.source),
    entry(bound_bndcu.family, bound_bndcu.path, bound_bndcu.source),
    entry(bound_bndcn.family, bound_bndcn.path, bound_bndcn.source),
    entry(bound_bndldx.family, bound_bndldx.path, bound_bndldx.source),
    entry(bound_bndmk.family, bound_bndmk.path, bound_bndmk.source),
    entry(bound_bndmov.family, bound_bndmov.path, bound_bndmov.source),
    entry(bound_bndstx.family, bound_bndstx.path, bound_bndstx.source),
    entry(x87_fcom.family, x87_fcom.path, x87_fcom.source),
    entry(x87_fcomp.family, x87_fcomp.path, x87_fcomp.source),
    entry(x87_fcompp.family, x87_fcompp.path, x87_fcompp.source),
    entry(x87_fcomi.family, x87_fcomi.path, x87_fcomi.source),
    entry(x87_fcomip.family, x87_fcomip.path, x87_fcomip.source),
    entry(x87_fucomi.family, x87_fucomi.path, x87_fucomi.source),
    entry(x87_fucomip.family, x87_fucomip.path, x87_fucomip.source),
    entry(x87_ficom.family, x87_ficom.path, x87_ficom.source),
    entry(x87_ficomp.family, x87_ficomp.path, x87_ficomp.source),
    entry(x87_fucom.family, x87_fucom.path, x87_fucom.source),
    entry(x87_fucomp.family, x87_fucomp.path, x87_fucomp.source),
    entry(x87_fucompp.family, x87_fucompp.path, x87_fucompp.source),
    entry(aes_aesdec.family, aes_aesdec.path, aes_aesdec.source),
    entry(aes_aesdec128kl.family, aes_aesdec128kl.path, aes_aesdec128kl.source),
    entry(aes_aesdec256kl.family, aes_aesdec256kl.path, aes_aesdec256kl.source),
    entry(aes_aesdeclast.family, aes_aesdeclast.path, aes_aesdeclast.source),
    entry(aes_aesdecwide128kl.family, aes_aesdecwide128kl.path, aes_aesdecwide128kl.source),
    entry(aes_aesdecwide256kl.family, aes_aesdecwide256kl.path, aes_aesdecwide256kl.source),
    entry(aes_aesenc.family, aes_aesenc.path, aes_aesenc.source),
    entry(aes_aesenc128kl.family, aes_aesenc128kl.path, aes_aesenc128kl.source),
    entry(aes_aesenc256kl.family, aes_aesenc256kl.path, aes_aesenc256kl.source),
    entry(aes_aesenclast.family, aes_aesenclast.path, aes_aesenclast.source),
    entry(aes_aesencwide128kl.family, aes_aesencwide128kl.path, aes_aesencwide128kl.source),
    entry(aes_aesencwide256kl.family, aes_aesencwide256kl.path, aes_aesencwide256kl.source),
    entry(aes_aesimc.family, aes_aesimc.path, aes_aesimc.source),
    entry(aes_aeskeygenassist.family, aes_aeskeygenassist.path, aes_aeskeygenassist.source),
    entry(min_max_pmaxsb.family, min_max_pmaxsb.path, min_max_pmaxsb.source),
    entry(min_max_pmaxsw.family, min_max_pmaxsw.path, min_max_pmaxsw.source),
    entry(min_max_pmaxsd.family, min_max_pmaxsd.path, min_max_pmaxsd.source),
    entry(min_max_pmaxsq.family, min_max_pmaxsq.path, min_max_pmaxsq.source),
    entry(min_max_pmaxub.family, min_max_pmaxub.path, min_max_pmaxub.source),
    entry(min_max_pmaxuw.family, min_max_pmaxuw.path, min_max_pmaxuw.source),
    entry(min_max_pmaxud.family, min_max_pmaxud.path, min_max_pmaxud.source),
    entry(min_max_pmaxuq.family, min_max_pmaxuq.path, min_max_pmaxuq.source),
    entry(min_max_pminsb.family, min_max_pminsb.path, min_max_pminsb.source),
    entry(min_max_pminsw.family, min_max_pminsw.path, min_max_pminsw.source),
    entry(min_max_pminsd.family, min_max_pminsd.path, min_max_pminsd.source),
    entry(min_max_pminsq.family, min_max_pminsq.path, min_max_pminsq.source),
    entry(min_max_pminub.family, min_max_pminub.path, min_max_pminub.source),
    entry(min_max_pminuw.family, min_max_pminuw.path, min_max_pminuw.source),
    entry(min_max_pminud.family, min_max_pminud.path, min_max_pminud.source),
    entry(min_max_pminuq.family, min_max_pminuq.path, min_max_pminuq.source),
};

pub fn tableCount() usize {
    return tables.len;
}

pub fn findByName(name: []const u8) ?InstructionTable {
    for (tables) |table| {
        const meta = table.metadata();
        if (std.ascii.eqlIgnoreCase(meta.name, name)) return table;
    }
    return null;
}

pub fn validateAll() void {
    for (tables) |table| table.validate();
    validateUniqueNames();
    validateDocumentedReferences();
}

fn entry(family: []const u8, path: []const u8, source: []const u8) InstructionTable {
    return .{ .family = family, .path = path, .source = source };
}

fn validateUniqueNames() void {
    for (tables, 0..) |lhs, i| {
        const lhs_name = lhs.metadata().name;
        for (tables[i + 1 ..]) |rhs| {
            const rhs_name = rhs.metadata().name;
            if (std.ascii.eqlIgnoreCase(lhs_name, rhs_name)) {
                runtime_abi.isa.validateNoDuplicateInstruction(lhs_name, lhs.path, rhs.path);
            }
        }
    }
}

fn validateDocumentedReferences() void {
    for (documented_reference_mnemonics) |name| {
        if (findByName(name) == null) runtime_abi.isa.validateMissingNeonMirror(name);
    }
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

test "x86 ISA tables expose required metadata" {
    try std.testing.expectEqual(@as(usize, 357), tableCount());
    validateAll();
    for (documented_reference_mnemonics) |name| try std.testing.expect(findByName(name) != null);
    const add = (findByName("ADD") orelse return error.MissingAdd).metadata();
    try std.testing.expectEqualStrings("x86_add", add.handler);
    try std.testing.expect(add.encoding_count >= 1);
}
