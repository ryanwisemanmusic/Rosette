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
const add_fadd = @import("ADD/fadd.zig");
const add_faddp = @import("ADD/faddp.zig");
const add_fiadd = @import("ADD/fiadd.zig");
const add_haddpd = @import("ADD/haddpd.zig");
const add_haddps = @import("ADD/haddps.zig");
const add_kaddb = @import("ADD/kaddb.zig");
const add_kaddd = @import("ADD/kaddd.zig");
const add_kaddq = @import("ADD/kaddq.zig");
const add_kaddw = @import("ADD/kaddw.zig");
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
const interrupt_int = @import("INTERRUPT/INT.zig");
const interrupt_int1 = @import("INTERRUPT/INT1.zig");
const interrupt_int3 = @import("INTERRUPT/INT3.zig");
const interrupt_into = @import("INTERRUPT/INTO.zig");
const interrupt_iret = @import("INTERRUPT/IRET.zig");
const interrupt_sidt = @import("INTERRUPT/SIDT.zig");
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
const kand_kandw = @import("KAND/KANDW.zig");
const kand_kandb = @import("KAND/KANDB.zig");
const kand_kandq = @import("KAND/KANDQ.zig");
const kand_kandd = @import("KAND/KANDD.zig");
const kortest_kortestw = @import("KORTEST/KORTESTW.zig");
const kortest_kortestb = @import("KORTEST/KORTESTB.zig");
const kortest_kortestq = @import("KORTEST/KORTESTQ.zig");
const kortest_kortestd = @import("KORTEST/KORTESTD.zig");
const kxor_kxorw = @import("KXOR/KXORW.zig");
const kxor_kxorb = @import("KXOR/KXORB.zig");
const kxor_kxorq = @import("KXOR/KXORQ.zig");
const kxor_kxord = @import("KXOR/KXORD.zig");
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
const align_valignd = @import("ALIGN/VALIGND.zig");
const align_valignq = @import("ALIGN/VALIGNQ.zig");
const average_pavgb = @import("AVERAGE/PAVGB.zig");
const average_pavgw = @import("AVERAGE/PAVGW.zig");
const begin_xbegin = @import("BEGIN/XBEGIN.zig");
const bitwise_vpternlogd = @import("BITWISE/VPTERNLOGD.zig");
const bitwise_vpternlogq = @import("BITWISE/VPTERNLOGQ.zig");
const broadcast_vpbroadcastmb2q = @import("BROADCAST/VPBROADCASTMB2Q.zig");
const broadcast_vpbroadcastmw2d = @import("BROADCAST/VPBROADCASTMW2D.zig");
const concatenate_vpshldd = @import("CONCATENATE/vpshldd.zig");
const concatenate_vpshldq = @import("CONCATENATE/vpshldq.zig");
const concatenate_vpshldvd = @import("CONCATENATE/vpshldvd.zig");
const concatenate_vpshldvq = @import("CONCATENATE/vpshldvq.zig");
const concatenate_vpshldvw = @import("CONCATENATE/vpshldvw.zig");
const concatenate_vpshldw = @import("CONCATENATE/vpshldw.zig");
const concatenate_vpshrdd = @import("CONCATENATE/vpshrdd.zig");
const concatenate_vpshrdq = @import("CONCATENATE/vpshrdq.zig");
const concatenate_vpshrdvd = @import("CONCATENATE/vpshrdvd.zig");
const concatenate_vpshrdvq = @import("CONCATENATE/vpshrdvq.zig");
const concatenate_vpshrdvw = @import("CONCATENATE/vpshrdvw.zig");
const concatenate_vpshrdw = @import("CONCATENATE/vpshrdw.zig");
const conditional_cmova = @import("CONDITIONAL/CMOVA.zig");
const conditional_cmovae = @import("CONDITIONAL/CMOVAE.zig");
const conditional_cmovb = @import("CONDITIONAL/CMOVB.zig");
const conditional_cmovbe = @import("CONDITIONAL/CMOVBE.zig");
const conditional_cmovc = @import("CONDITIONAL/CMOVC.zig");
const conditional_cmove = @import("CONDITIONAL/CMOVE.zig");
const conditional_cmovg = @import("CONDITIONAL/CMOVG.zig");
const conditional_cmovge = @import("CONDITIONAL/CMOVGE.zig");
const conditional_cmovl = @import("CONDITIONAL/CMOVL.zig");
const conditional_cmovle = @import("CONDITIONAL/CMOVLE.zig");
const conditional_cmovna = @import("CONDITIONAL/CMOVNA.zig");
const conditional_cmovnae = @import("CONDITIONAL/CMOVNAE.zig");
const conditional_cmovnb = @import("CONDITIONAL/CMOVNB.zig");
const conditional_cmovnbe = @import("CONDITIONAL/CMOVNBE.zig");
const conditional_cmovnc = @import("CONDITIONAL/CMOVNC.zig");
const conditional_cmovne = @import("CONDITIONAL/CMOVNE.zig");
const conditional_cmovng = @import("CONDITIONAL/CMOVNG.zig");
const conditional_cmovnge = @import("CONDITIONAL/CMOVNGE.zig");
const conditional_cmovnl = @import("CONDITIONAL/CMOVNL.zig");
const conditional_cmovnle = @import("CONDITIONAL/CMOVNLE.zig");
const conditional_cmovno = @import("CONDITIONAL/CMOVNO.zig");
const conditional_cmovnp = @import("CONDITIONAL/CMOVNP.zig");
const conditional_cmovns = @import("CONDITIONAL/CMOVNS.zig");
const conditional_cmovnz = @import("CONDITIONAL/CMOVNZ.zig");
const conditional_cmovo = @import("CONDITIONAL/CMOVO.zig");
const conditional_cmovp = @import("CONDITIONAL/CMOVP.zig");
const conditional_cmovpe = @import("CONDITIONAL/CMOVPE.zig");
const conditional_cmovpo = @import("CONDITIONAL/CMOVPO.zig");
const conditional_cmovs = @import("CONDITIONAL/CMOVS.zig");
const conditional_cmovz = @import("CONDITIONAL/CMOVZ.zig");
const conditional_fcmovb = @import("CONDITIONAL/FCMOVB.zig");
const conditional_fcmove = @import("CONDITIONAL/FCMOVE.zig");
const conditional_fcmovbe = @import("CONDITIONAL/FCMOVBE.zig");
const conditional_fcmovu = @import("CONDITIONAL/FCMOVU.zig");
const conditional_fcmovnb = @import("CONDITIONAL/FCMOVNB.zig");
const conditional_fcmovne = @import("CONDITIONAL/FCMOVNE.zig");
const conditional_fcmovnbe = @import("CONDITIONAL/FCMOVNBE.zig");
const conditional_fcmovnu = @import("CONDITIONAL/FCMOVNU.zig");
const conditional_vmaskmovps = @import("CONDITIONAL/VMASKMOVPS.zig");
const conditional_vmaskmovpd = @import("CONDITIONAL/VMASKMOVPD.zig");
const conditional_vpmaskmovd = @import("CONDITIONAL/VPMASKMOVD.zig");
const conditional_vpmaskmovq = @import("CONDITIONAL/VPMASKMOVQ.zig");
const compute_f2xm1 = @import("COMPUTE/f2xm1.zig");
const compute_fyl2x = @import("COMPUTE/fyl2x.zig");
const compute_fyl2xp1 = @import("COMPUTE/fyl2xp1.zig");
const compute_psadbw = @import("COMPUTE/psadbw.zig");
const compute_mpsadbw = @import("COMPUTE/mpsadbw.zig");
const compute_rcpps = @import("COMPUTE/rcpps.zig");
const compute_rcpss = @import("COMPUTE/rcpss.zig");
const compute_rsqrtps = @import("COMPUTE/rsqrtps.zig");
const compute_rsqrtss = @import("COMPUTE/rsqrtss.zig");
const compute_sqrtsd = @import("COMPUTE/sqrtsd.zig");
const compute_sqrtss = @import("COMPUTE/sqrtss.zig");
const compute_vp2intersect = @import("COMPUTE/vp2intersect.zig");
const convert_cbw = @import("CONVERT/CBW.zig");
const convert_cwde = @import("CONVERT/CWDE.zig");
const convert_cdqe = @import("CONVERT/CDQE.zig");
const convert_cwd = @import("CONVERT/CWD.zig");
const convert_cdq = @import("CONVERT/CDQ.zig");
const convert_cqo = @import("CONVERT/CQO.zig");
const convert_cvtdq2pd = @import("CONVERT/CVTDQ2PD.zig");
const convert_cvtdq2ps = @import("CONVERT/CVTDQ2PS.zig");
const convert_cvtpd2dq = @import("CONVERT/CVTPD2DQ.zig");
const convert_cvtpd2pi = @import("CONVERT/CVTPD2PI.zig");
const convert_cvtpd2ps = @import("CONVERT/CVTPD2PS.zig");
const convert_cvtpi2pd = @import("CONVERT/CVTPI2PD.zig");
const convert_cvtpi2ps = @import("CONVERT/CVTPI2PS.zig");
const convert_cvtps2dq = @import("CONVERT/CVTPS2DQ.zig");
const convert_cvtps2pd = @import("CONVERT/CVTPS2PD.zig");
const convert_cvtps2pi = @import("CONVERT/CVTPS2PI.zig");
const convert_cvtsd2si = @import("CONVERT/CVTSD2SI.zig");
const convert_cvtsd2ss = @import("CONVERT/CVTSD2SS.zig");
const convert_cvtsi2sd = @import("CONVERT/CVTSI2SD.zig");
const convert_cvtsi2ss = @import("CONVERT/CVTSI2SS.zig");
const convert_cvtss2sd = @import("CONVERT/CVTSS2SD.zig");
const convert_cvtss2si = @import("CONVERT/CVTSS2SI.zig");
const convert_cvttpd2dq = @import("CONVERT/CVTTPD2DQ.zig");
const convert_cvttpd2pi = @import("CONVERT/CVTTPD2PI.zig");
const convert_cvttps2dq = @import("CONVERT/CVTTPS2DQ.zig");
const convert_cvttps2pi = @import("CONVERT/CVTTPS2PI.zig");
const convert_cvttsd2si = @import("CONVERT/CVTTSD2SI.zig");
const convert_cvttss2si = @import("CONVERT/CVTTSS2SI.zig");
const convert_vcvtne2ps2bf16 = @import("CONVERT/VCVTNE2PS2BF16.zig");
const convert_vcvtneps2bf16 = @import("CONVERT/VCVTNEPS2BF16.zig");
const convert_vcvtpd2ph = @import("CONVERT/VCVTPD2PH.zig");
const convert_vcvtpd2qq = @import("CONVERT/VCVTPD2QQ.zig");
const convert_vcvtpd2udq = @import("CONVERT/VCVTPD2UDQ.zig");
const convert_vcvtpd2uqq = @import("CONVERT/VCVTPD2UQQ.zig");
const convert_vcvtph2dq = @import("CONVERT/VCVTPH2DQ.zig");
const convert_vcvtph2pd = @import("CONVERT/VCVTPH2PD.zig");
const convert_vcvtph2ps = @import("CONVERT/VCVTPH2PS.zig");
const convert_vcvtph2psx = @import("CONVERT/VCVTPH2PSX.zig");
const convert_vcvtph2qq = @import("CONVERT/VCVTPH2QQ.zig");
const convert_vcvtph2udq = @import("CONVERT/VCVTPH2UDQ.zig");
const convert_vcvtph2uqq = @import("CONVERT/VCVTPH2UQQ.zig");
const convert_vcvtph2uw = @import("CONVERT/VCVTPH2UW.zig");
const convert_vcvtph2w = @import("CONVERT/VCVTPH2W.zig");
const convert_vcvtps2ph = @import("CONVERT/VCVTPS2PH.zig");
const convert_vcvtps2phx = @import("CONVERT/VCVTPS2PHX.zig");
const convert_vcvtps2qq = @import("CONVERT/VCVTPS2QQ.zig");
const convert_vcvtps2udq = @import("CONVERT/VCVTPS2UDQ.zig");
const convert_vcvtps2uqq = @import("CONVERT/VCVTPS2UQQ.zig");
const convert_vcvtqq2pd = @import("CONVERT/VCVTQQ2PD.zig");
const convert_vcvtqq2ph = @import("CONVERT/VCVTQQ2PH.zig");
const convert_vcvtqq2ps = @import("CONVERT/VCVTQQ2PS.zig");
const convert_vcvtsd2sh = @import("CONVERT/VCVTSD2SH.zig");
const convert_vcvtsd2usi = @import("CONVERT/VCVTSD2USI.zig");
const convert_vcvtsh2sd = @import("CONVERT/VCVTSH2SD.zig");
const convert_vcvtsh2si = @import("CONVERT/VCVTSH2SI.zig");
const convert_vcvtsh2ss = @import("CONVERT/VCVTSH2SS.zig");
const convert_vcvtsh2usi = @import("CONVERT/VCVTSH2USI.zig");
const halt_hlt = @import("HALT/HLT.zig");
const loop_loop = @import("LOOP/LOOP.zig");
const loop_loope = @import("LOOP/LOOPE.zig");
const loop_loopne = @import("LOOP/LOOPNE.zig");
const loop_pause = @import("LOOP/PAUSE.zig");
const memory_mfence = @import("MEMORY/MFENCE.zig");
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
const output_out = @import("OUTPUT/OUT.zig");
const output_outs = @import("OUTPUT/OUTS.zig");
const output_outsb = @import("OUTPUT/OUTSB.zig");
const output_outsw = @import("OUTPUT/OUTSW.zig");
const output_outsd = @import("OUTPUT/OUTSD.zig");
const pop_pop = @import("POP/POP.zig");
const pop_popa = @import("POP/POPA.zig");
const pop_popad = @import("POP/POPAD.zig");
const pop_popcnt = @import("POP/POPCNT.zig");
const push_push = @import("PUSH/PUSH.zig");
const push_pusha = @import("PUSH/PUSHA.zig");
const push_pushad = @import("PUSH/PUSHAD.zig");
const push_pushf = @import("PUSH/PUSHF.zig");
const push_pushfd = @import("PUSH/PUSHFD.zig");
const push_pushfq = @import("PUSH/PUSHFQ.zig");
const restore_frstore = @import("RESTORE/frstore.zig");
const restore_fxrstore = @import("RESTORE/fxrstore.zig");
const restore_rstore_ssp = @import("RESTORE/rstore_ssp.zig");
const restore_xrstore = @import("RESTORE/xrstore.zig");
const restore_xrstors = @import("RESTORE/xrstors.zig");
const rotate_rcl = @import("ROTATE/RCL.zig");
const rotate_rcr = @import("ROTATE/RCR.zig");
const rotate_rol = @import("ROTATE/ROL.zig");
const rotate_ror = @import("ROTATE/ROR.zig");
const rotate_rorx = @import("ROTATE/RORX.zig");
const rotate_vprold = @import("ROTATE/VPROLD.zig");
const rotate_vprolvd = @import("ROTATE/VPROLVD.zig");
const rotate_vprolq = @import("ROTATE/VPROLQ.zig");
const rotate_vprolvq = @import("ROTATE/VPROLVQ.zig");
const rotate_vprord = @import("ROTATE/VPRORD.zig");
const rotate_vprorvd = @import("ROTATE/VPRORVD.zig");
const rotate_vprorq = @import("ROTATE/VPRORQ.zig");
const rotate_vprorvq = @import("ROTATE/VPRORVQ.zig");
const save_fsave = @import("SAVE/FSAVE.zig");
const save_fxsave = @import("SAVE/FXSAVE.zig");
const save_saveprevssp = @import("SAVE/SAVEPREVSSP.zig");
const swap_swapgs = @import("SWAP/SWAPGS.zig");
const sub_sub = @import("SUB/SUB.zig");
const sub_subpd = @import("SUB/SUBPD.zig");
const sub_subps = @import("SUB/SUBPS.zig");
const sub_subsd = @import("SUB/SUBSD.zig");
const sub_subss = @import("SUB/SUBSS.zig");
const test_test = @import("TEST/TEST.zig");
const test_testui = @import("TEST/TESTUI.zig");
const undef_ud0 = @import("UNDEF/UD0.zig");
const undef_ud1 = @import("UNDEF/UD1.zig");
const undef_ud2 = @import("UNDEF/UD2.zig");
const unordered_ucomisd = @import("UNORDERED/UCOMISD.zig");
const unordered_ucomiss = @import("UNORDERED/UCOMISS.zig");
const unordered_vucomish = @import("UNORDERED/VUCOMISH.zig");
const variable_vpsllvw = @import("VARIABLE/VPSLLVW.zig");
const variable_vpsllvd = @import("VARIABLE/VPSLLVD.zig");
const variable_vpsllvq = @import("VARIABLE/VPSLLVQ.zig");
const variable_vpsravw = @import("VARIABLE/VPSRAVW.zig");
const variable_vpsravd = @import("VARIABLE/VPSRAVD.zig");
const variable_vpsravq = @import("VARIABLE/VPSRAVQ.zig");
const variable_vpsrlvw = @import("VARIABLE/VPSRLVW.zig");
const variable_vpsrlvd = @import("VARIABLE/VPSRLVD.zig");
const variable_vpsrlvq = @import("VARIABLE/VPSRLVQ.zig");
const verify_verr = @import("VERIFY/VERR.zig");
const verify_verw = @import("VERIFY/VERW.zig");
const vptestm_vptestmb = @import("VPTESTM/VPTESTMB.zig");
const vptestm_vptestmw = @import("VPTESTM/VPTESTMW.zig");
const vptestm_vptestmd = @import("VPTESTM/VPTESTMD.zig");
const vptestm_vptestmq = @import("VPTESTM/VPTESTMQ.zig");
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
const cache_clwb = @import("CACHE/clwb.zig");
const cpu_cpuid = @import("CPU/CPUID.zig");
const sha_sha1msg1 = @import("SHA/SHA1MSG1.zig");
const sha_sha1msg2 = @import("SHA/SHA1MSG2.zig");
const sha_sha1nexte = @import("SHA/SHA1NEXTE.zig");
const sha_sha1rnds4 = @import("SHA/SHA1RNDS4.zig");
const sha_sha256msg1 = @import("SHA/SHA256MSG1.zig");
const sha_sha256msg2 = @import("SHA/SHA256MSG2.zig");
const sha_sha256rnds2 = @import("SHA/SHA256RNDS2.zig");
const shadow_incssp = @import("SHADOW/INCSSP.zig");
const terminate_endbr32 = @import("TERMINATE/ENDBR32.zig");
const terminate_endbr64 = @import("TERMINATE/ENDBR64.zig");
const shuffle_shufpd = @import("SHUFFLE/SHUFPD.zig");
const shuffle_shufps = @import("SHUFFLE/SHUFPS.zig");
const shuffle_vpshufbitqmb = @import("SHUFFLE/VPSHUFBITQMB.zig");
const shuffle_vshuff32x4 = @import("SHUFFLE/VSHUFF32x4.zig");
const shuffle_vshuff64x2 = @import("SHUFFLE/VSHUFF64x2.zig");
const shuffle_vshufi32x4 = @import("SHUFFLE/VSHUFI32x4.zig");
const shuffle_vshufi64x2 = @import("SHUFFLE/VSHUFI64x2.zig");
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
const set_monitor = @import("SET/MONITOR.zig");
const set_umonitor = @import("SET/UMONITOR.zig");
const set_stac = @import("SET/STAC.zig");
const set_stc = @import("SET/STC.zig");
const set_std = @import("SET/STD.zig");
const set_sti = @import("SET/STI.zig");
const set_stui = @import("SET/STUI.zig");
const set_xsetbv = @import("SET/XSETBV.zig");
const set_seta = @import("SET/SETA.zig");
const set_setae = @import("SET/SETAE.zig");
const set_setb = @import("SET/SETB.zig");
const set_setbe = @import("SET/SETBE.zig");
const set_setc = @import("SET/SETC.zig");
const set_sete = @import("SET/SETE.zig");
const set_setg = @import("SET/SETG.zig");
const set_setge = @import("SET/SETGE.zig");
const set_setl = @import("SET/SETL.zig");
const set_setle = @import("SET/SETLE.zig");
const set_setna = @import("SET/SETNA.zig");
const set_setnae = @import("SET/SETNAE.zig");
const set_setnb = @import("SET/SETNB.zig");
const set_setnbe = @import("SET/SETNBE.zig");
const set_setnc = @import("SET/SETNC.zig");
const set_setne = @import("SET/SETNE.zig");
const set_setng = @import("SET/SETNG.zig");
const set_setnge = @import("SET/SETNGE.zig");
const set_setnl = @import("SET/SETNL.zig");
const set_setnle = @import("SET/SETNLE.zig");
const set_setno = @import("SET/SETNO.zig");
const set_setnp = @import("SET/SETNP.zig");
const set_setns = @import("SET/SETNS.zig");
const set_setnz = @import("SET/SETNZ.zig");
const set_seto = @import("SET/SETO.zig");
const set_setp = @import("SET/SETP.zig");
const set_setpe = @import("SET/SETPE.zig");
const set_setpo = @import("SET/SETPO.zig");
const set_sets = @import("SET/SETS.zig");
const set_setz = @import("SET/SETZ.zig");
const count_lzcnt = @import("COUNT/LZCNT.zig");
const count_tzcnt = @import("COUNT/TZCNT.zig");
const count_vplzcntd = @import("COUNT/VPLZCNTD.zig");
const count_vplzcntq = @import("COUNT/VPLZCNTQ.zig");
const exchange_fxch = @import("EXCHANGE/FXCH.zig");
const exchange_xadd = @import("EXCHANGE/XADD.zig");
const exchange_xchg = @import("EXCHANGE/XCHG.zig");
const nop_fnop = @import("NOP/FNOP.zig");
const nop_nop = @import("NOP/NOP.zig");
const not_not = @import("NOT/NOT.zig");
const not_knotw = @import("NOT/KNOTW.zig");
const not_knotb = @import("NOT/KNOTB.zig");
const not_knotq = @import("NOT/KNOTQ.zig");
const not_knotd = @import("NOT/KNOTD.zig");
const andnot_pandn = @import("ANDNOT/PANDN.zig");
const andnot_vpandn = @import("ANDNOT/VPANDN.zig");
const andnot_vpandnd = @import("ANDNOT/VPANDND.zig");
const andnot_vpandnq = @import("ANDNOT/VPANDNQ.zig");
const andnot_kandnw = @import("ANDNOT/KANDNW.zig");
const andnot_kandnb = @import("ANDNOT/KANDNB.zig");
const andnot_kandnq = @import("ANDNOT/KANDNQ.zig");
const andnot_kandnd = @import("ANDNOT/KANDND.zig");
const bitposition_bzhi = @import("BITPOSITION/BZHI.zig");
const change_fchs = @import("CHANGE/FCHS.zig");
const complement_cmc = @import("COMPLEMENT/CMC.zig");
const decimal_daa = @import("DECIMAL/DAA.zig");
const decimal_das = @import("DECIMAL/DAS.zig");
const dep_pdep = @import("DEP/PDEP.zig");
const detect_vpconflictd = @import("DETECT/VPCONFLICTD.zig");
const detect_vpconflictq = @import("DETECT/VPCONFLICTQ.zig");
const empty_emms = @import("EMPTY/EMMS.zig");
const end_xend = @import("END/XEND.zig");
const examine_fxam = @import("EXAMINE/FXAM.zig");
const expand_vpexpandb = @import("EXPAND/VPEXPANDB.zig");
const expand_vpexpandw = @import("EXPAND/VPEXPANDW.zig");
const free_ffree = @import("FREE/FFREE.zig");
const pand_pand = @import("PAND/PAND.zig");
const pand_vpand = @import("PAND/VPAND.zig");
const pand_vpandd = @import("PAND/VPANDD.zig");
const pand_vpandq = @import("PAND/VPANDQ.zig");
const partial_fpatan = @import("PARTIAL/FPATAN.zig");
const partial_fprem = @import("PARTIAL/FPREM.zig");
const partial_fprem1 = @import("PARTIAL/FPREM1.zig");
const partial_fptan = @import("PARTIAL/FPTAN.zig");
const pause_tpause = @import("PAUSE/TPAUSE.zig");
const platform_pconfig = @import("PLATFORM/PCONFIG.zig");
const prefetch_prefetchw = @import("PREFETCH/PREFETCHW.zig");
const prefetch_prefetcht0 = @import("PREFETCH/PREFETCHT0.zig");
const prefetch_prefetcht1 = @import("PREFETCH/PREFETCHT1.zig");
const prefetch_prefetcht2 = @import("PREFETCH/PREFETCHT2.zig");
const prefetch_prefetchnta = @import("PREFETCH/PREFETCHNTA.zig");
const pxor_pxor = @import("PXOR/PXOR.zig");
const pxor_vpxor = @import("PXOR/VPXOR.zig");
const pxor_vpxord = @import("PXOR/VPXORD.zig");
const pxor_vpxorq = @import("PXOR/VPXORQ.zig");
const release_tilerelease = @import("RELEASE/TILERELEASE.zig");
const reset_hreset = @import("RESET/HRESET.zig");
const resume_rsm = @import("RESUME/RSM.zig");
const rpl_arpl = @import("RPL/ARPL.zig");
const select_vpmultishiftqb = @import("SELECT/VPMULTISHIFTQB.zig");
const send_senduipi = @import("SEND/SENDUIPI.zig");
const serialize_serialize = @import("SERIALIZE/SERIALIZE.zig");
const enqueue_enqcmd = @import("ENQUEUE/enqcmd.zig");
const extr_bextr = @import("EXTR/bextr.zig");
const extr_extractps = @import("EXTR/extractps.zig");
const extr_fxtract = @import("EXTR/fxtract.zig");
const extr_pext = @import("EXTR/pext.zig");
const lock_lock = @import("LOCK/lock.zig");
const lock_xacquire = @import("LOCK/xacquire.zig");
const lock_xrelease = @import("LOCK/xrelease.zig");
const logical_nand_vptestnmb = @import("LOGICAL_NAND/VPTESTNMB.zig");
const logical_nand_vptestnmw = @import("LOGICAL_NAND/VPTESTNMW.zig");
const logical_nand_vptestnmd = @import("LOGICAL_NAND/VPTESTNMD.zig");
const logical_nand_vptestnmq = @import("LOGICAL_NAND/VPTESTNMQ.zig");
const logical_or_korw = @import("LOGICAL_OR/KORW.zig");
const logical_or_korb = @import("LOGICAL_OR/KORB.zig");
const logical_or_korq = @import("LOGICAL_OR/KORQ.zig");
const logical_or_kord = @import("LOGICAL_OR/KORD.zig");
const logical_or_por = @import("LOGICAL_OR/POR.zig");
const logical_or_vpor = @import("LOGICAL_OR/VPOR.zig");
const logical_or_vpord = @import("LOGICAL_OR/VPORD.zig");
const logical_or_vporq = @import("LOGICAL_OR/VPORQ.zig");
const logical_xnor_kxnorw = @import("LOGICAL_XNOR/KXNORW.zig");
const logical_xnor_kxnorb = @import("LOGICAL_XNOR/KXNORB.zig");
const logical_xnor_kxnorq = @import("LOGICAL_XNOR/KXNORQ.zig");
const logical_xnor_kxnord = @import("LOGICAL_XNOR/KXNORD.zig");
const neg_neg = @import("NEG/neg.zig");
const round_frndint = @import("ROUND/frndint.zig");
const encode_encodekey128 = @import("ENCODE/encodekey128.zig");
const galois_gf2p8affineinvqb = @import("GALOIS/gf2p8affineinvqb.zig");
const galois_gf2p8affineqb = @import("GALOIS/gf2p8affineqb.zig");
const galois_gf2p8mulb = @import("GALOIS/gf2p8mulb.zig");
const inc_dec_fdecstp = @import("INC_DEC/FDECSTP.zig");
const inc_dec_fincstp = @import("INC_DEC/FINCSTP.zig");
const initialize_finit = @import("INITIALIZE/FINIT.zig");
const initialize_fninit = @import("INITIALIZE/FNINIT.zig");
const invalidate_invd = @import("INVALIDATE/invd.zig");
const invalidate_invlpg = @import("INVALIDATE/invlpg.zig");
const invalidate_invpcid = @import("INVALIDATE/invpcid.zig");
const make_enter = @import("MAKE/enter.zig");
const repeat_rep = @import("REPEAT/rep.zig");
const repeat_repe = @import("REPEAT/repe.zig");
const repeat_repne = @import("REPEAT/repne.zig");
const scatter_vpscatterdd = @import("SCATTER/vpscatterdd.zig");
const scatter_vpscatterdq = @import("SCATTER/vpscatterdq.zig");
const scatter_vpscatterqd = @import("SCATTER/vpscatterqd.zig");
const scatter_vpscatterqq = @import("SCATTER/vpscatterqq.zig");
const scatter_vscatterdps = @import("SCATTER/vscatterdps.zig");
const scatter_vscatterdpd = @import("SCATTER/vscatterdpd.zig");
const scatter_vscatterqps = @import("SCATTER/vscatterqps.zig");
const scatter_vscatterqpd = @import("SCATTER/vscatterqpd.zig");
const gather_vgatherdpd = @import("GATHER/vgatherdpd.zig");
const gather_vgatherqpd = @import("GATHER/vgatherqpd.zig");
const gather_vgatherdps = @import("GATHER/vgatherdps.zig");
const gather_vgatherqps = @import("GATHER/vgatherqps.zig");
const gather_vpgatherdd = @import("GATHER/vpgatherdd.zig");
const gather_vpgatherdq = @import("GATHER/vpgatherdq.zig");
const gather_vpgatherqd = @import("GATHER/vpgatherqd.zig");
const gather_vpgatherqq = @import("GATHER/vpgatherqq.zig");
const get_xgetbv = @import("GET/XGETBV.zig");
const square_root_fsqrt = @import("SQUARE_ROOT/fsqrt.zig");
const square_root_sqrtpd = @import("SQUARE_ROOT/sqrtpd.zig");
const square_root_sqrtps = @import("SQUARE_ROOT/sqrtps.zig");
const table_xlat = @import("TABLE/XLAT.zig");
const table_xlatb = @import("TABLE/XLATB.zig");
const trig_fcos = @import("TRIG/fcos.zig");
const trig_fsin = @import("TRIG/fsin.zig");
const trig_fsincos = @import("TRIG/fsincos.zig");
const wait_wait = @import("WAIT/wait.zig");
const wait_mwait = @import("WAIT/mwait.zig");
const write_ptwrite = @import("WRITE/PTWRITE.zig");
const write_wbinvd = @import("WRITE/WBINVD.zig");
const write_wbnoinvd = @import("WRITE/WBNOINVD.zig");
const write_wrfsbase = @import("WRITE/WRFSBASE.zig");
const write_wrgsbase = @import("WRITE/WRGSBASE.zig");
const write_wrmsr = @import("WRITE/WRMSR.zig");
const write_wrpkru = @import("WRITE/WRPKRU.zig");
const absolute_fabs = @import("ABSOLUTE/fabs.zig");
const absolute_pabsb = @import("ABSOLUTE/pabsb.zig");
const absolute_pabsd = @import("ABSOLUTE/pabsd.zig");
const absolute_pabsq = @import("ABSOLUTE/pabsq.zig");
const absolute_pabsw = @import("ABSOLUTE/pabsw.zig");
const absolute_vdbpsadbw = @import("ABSOLUTE/vdbpsadbw.zig");
const accumulate_crc32 = @import("ACCUMULATE/crc32.zig");
const reverse_fdivr = @import("REVERSE/fdivr.zig");
const reverse_fdivrp = @import("REVERSE/fdivrp.zig");
const reverse_fidivr = @import("REVERSE/fidivr.zig");
const reverse_fsubr = @import("REVERSE/fsubr.zig");
const reverse_fsubrp = @import("REVERSE/fsubrp.zig");
const reverse_fisubr = @import("REVERSE/fisubr.zig");
const scan_scas = @import("SCAN/scas.zig");
const scan_scasb = @import("SCAN/scasb.zig");
const scan_scasw = @import("SCAN/scasw.zig");
const scan_scasd = @import("SCAN/scasd.zig");
const scan_scasq = @import("SCAN/scasq.zig");
const zero_tilezero = @import("ZERO/TILEZERO.zig");
const zero_vzeroall = @import("ZERO/VZEROALL.zig");
const zero_vzeroupper = @import("ZERO/VZEROUPPER.zig");

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
    "INT",
    "INT1",
    "INT3",
    "INTO",
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
    "VMASKMOVPD",
    "VMASKMOVPS",
    "VPMASKMOVD",
    "VPMASKMOVQ",
    "VPEXPANDD",
    "VPEXPANDQ",
    "XABORT",
    "XBEGIN",
    "XRESLDTRK",
    "XSUSLDTRK",
    "CBW",
    "CDQ",
    "CDQE",
    "CMOVA",
    "CMOVAE",
    "CMOVB",
    "CMOVBE",
    "CMOVC",
    "CMOVE",
    "CMOVG",
    "CMOVGE",
    "CMOVL",
    "CMOVLE",
    "CMOVNA",
    "CMOVNAE",
    "CMOVNB",
    "CMOVNBE",
    "CMOVNC",
    "CMOVNE",
    "CMOVNG",
    "CMOVNGE",
    "CMOVNL",
    "CMOVNLE",
    "CMOVNO",
    "CMOVNP",
    "CMOVNS",
    "CMOVNZ",
    "CMOVO",
    "CMOVP",
    "CMOVPE",
    "CMOVPO",
    "CMOVS",
    "CMOVZ",
    "CQO",
    "CWDE",
    "CWD",
    "FCMOVB",
    "FCMOVBE",
    "FCMOVE",
    "FCMOVNB",
    "FCMOVNBE",
    "FCMOVNE",
    "FCMOVNU",
    "FCMOVU",
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
    "PCONFIG",
    "OR",
    "ORPD",
    "ORPS",
    "OUT",
    "OUTS",
    "OUTSB",
    "OUTSW",
    "OUTSD",
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
    "RORX",
    "VPROLD",
    "VPROLVD",
    "VPROLQ",
    "VPROLVQ",
    "VPRORD",
    "VPRORVD",
    "VPRORQ",
    "VPRORVQ",
    "SUB",
    "SUBPD",
    "SUBPS",
    "SUBSD",
    "SUBSS",
    "SWAPGS",
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
    "VPSHUFBITQMB",
    "VSHUFF32x4",
    "VSHUFF64x2",
    "VSHUFI32x4",
    "VSHUFI64x2",
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
    "MONITOR",
    "UMONITOR",
    "STAC",
    "STC",
    "STD",
    "STI",
    "STUI",
    "XSETBV",
    "SETA",
    "SETAE",
    "SETB",
    "SETBE",
    "SETC",
    "SETE",
    "SETG",
    "SETGE",
    "SETL",
    "SETLE",
    "SETNA",
    "SETNAE",
    "SETNB",
    "SETNBE",
    "SETNC",
    "SETNE",
    "SETNG",
    "SETNGE",
    "SETNL",
    "SETNLE",
    "SETNO",
    "SETNP",
    "SETNS",
    "SETNZ",
    "SETO",
    "SETP",
    "SETPE",
    "SETPO",
    "SETS",
    "SETZ",
    "LZCNT",
    "TZCNT",
    "VPLZCNTD",
    "VPLZCNTQ",
    "FXCH",
    "XADD",
    "XCHG",
    "FNOP",
    "NOP",
    "NOT",
    "KNOTW",
    "KNOTB",
    "KNOTQ",
    "KNOTD",
    "PANDN",
    "VPANDN",
    "VPANDND",
    "VPANDNQ",
    "KANDNW",
    "KANDNB",
    "KANDNQ",
    "KANDND",
    "BZHI",
    "FCHS",
    "CMC",
    "DAA",
    "DAS",
    "EMMS",
    "XEND",
    "FXAM",
    "VPEXPANDB",
    "VPEXPANDW",
    "TPAUSE",
    "PREFETCHW",
    "PREFETCHT0",
    "PREFETCHT1",
    "PREFETCHT2",
    "PREFETCHNTA",
    "TILERELEASE",
    "HRESET",
    "RSM",
    "ARPL",
    "VPMULTISHIFTQB",
    "SENDUIPI",
    "SERIALIZE",
    "ENQCMD",
    "BEXTR",
    "EXTRACTPS",
    "FXTRACT",
    "PEXT",
    "LOCK",
    "XACQUIRE",
    "XRELEASE",
    "NEG",
    "FRNDINT",
    "F2XM1",
    "FYL2X",
    "FYL2XP1",
    "MPSADBW",
    "PSADBW",
    "RCPPS",
    "RCPSS",
    "RSQRTPS",
    "RSQRTSS",
    "SQRTSD",
    "SQRTSS",
    "VP2INTERSECT",
    "PTWRITE",
    "WBINVD",
    "WBNOINVD",
    "WRFSBASE",
    "WRGSBASE",
    "WRMSR",
    "WRPKRU",
    "VPSLLVW",
    "VPSLLVD",
    "VPSLLVQ",
    "VPSRAVW",
    "VPSRAVD",
    "VPSRAVQ",
    "VPSRLVW",
    "VPSRLVD",
    "VPSRLVQ",
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
    entry(add_fadd.family, add_fadd.path, add_fadd.source),
    entry(add_faddp.family, add_faddp.path, add_faddp.source),
    entry(add_fiadd.family, add_fiadd.path, add_fiadd.source),
    entry(add_haddpd.family, add_haddpd.path, add_haddpd.source),
    entry(add_haddps.family, add_haddps.path, add_haddps.source),
    entry(add_kaddb.family, add_kaddb.path, add_kaddb.source),
    entry(add_kaddd.family, add_kaddd.path, add_kaddd.source),
    entry(add_kaddq.family, add_kaddq.path, add_kaddq.source),
    entry(add_kaddw.family, add_kaddw.path, add_kaddw.source),
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
    entry(interrupt_int.family, interrupt_int.path, interrupt_int.source),
    entry(interrupt_int1.family, interrupt_int1.path, interrupt_int1.source),
    entry(interrupt_int3.family, interrupt_int3.path, interrupt_int3.source),
    entry(interrupt_into.family, interrupt_into.path, interrupt_into.source),
    entry(interrupt_iret.family, interrupt_iret.path, interrupt_iret.source),
    entry(interrupt_sidt.family, interrupt_sidt.path, interrupt_sidt.source),
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
    entry(kand_kandw.family, kand_kandw.path, kand_kandw.source),
    entry(kand_kandb.family, kand_kandb.path, kand_kandb.source),
    entry(kand_kandq.family, kand_kandq.path, kand_kandq.source),
    entry(kand_kandd.family, kand_kandd.path, kand_kandd.source),
    entry(kortest_kortestw.family, kortest_kortestw.path, kortest_kortestw.source),
    entry(kortest_kortestb.family, kortest_kortestb.path, kortest_kortestb.source),
    entry(kortest_kortestq.family, kortest_kortestq.path, kortest_kortestq.source),
    entry(kortest_kortestd.family, kortest_kortestd.path, kortest_kortestd.source),
    entry(kxor_kxorw.family, kxor_kxorw.path, kxor_kxorw.source),
    entry(kxor_kxorb.family, kxor_kxorb.path, kxor_kxorb.source),
    entry(kxor_kxorq.family, kxor_kxorq.path, kxor_kxorq.source),
    entry(kxor_kxord.family, kxor_kxord.path, kxor_kxord.source),
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
    entry(vptestm_vptestmb.family, vptestm_vptestmb.path, vptestm_vptestmb.source),
    entry(vptestm_vptestmw.family, vptestm_vptestmw.path, vptestm_vptestmw.source),
    entry(vptestm_vptestmd.family, vptestm_vptestmd.path, vptestm_vptestmd.source),
    entry(vptestm_vptestmq.family, vptestm_vptestmq.path, vptestm_vptestmq.source),
    entry(load_vpexpandd.family, load_vpexpandd.path, load_vpexpandd.source),
    entry(load_vpexpandq.family, load_vpexpandq.path, load_vpexpandq.source),
    entry(load_xresldtrk.family, load_xresldtrk.path, load_xresldtrk.source),
    entry(load_xsusldtrk.family, load_xsusldtrk.path, load_xsusldtrk.source),
    entry(abort_xabort.family, abort_xabort.path, abort_xabort.source),
    entry(align_valignd.family, align_valignd.path, align_valignd.source),
    entry(align_valignq.family, align_valignq.path, align_valignq.source),
    entry(average_pavgb.family, average_pavgb.path, average_pavgb.source),
    entry(average_pavgw.family, average_pavgw.path, average_pavgw.source),
    entry(begin_xbegin.family, begin_xbegin.path, begin_xbegin.source),
    entry(bitwise_vpternlogd.family, bitwise_vpternlogd.path, bitwise_vpternlogd.source),
    entry(bitwise_vpternlogq.family, bitwise_vpternlogq.path, bitwise_vpternlogq.source),
    entry(broadcast_vpbroadcastmb2q.family, broadcast_vpbroadcastmb2q.path, broadcast_vpbroadcastmb2q.source),
    entry(broadcast_vpbroadcastmw2d.family, broadcast_vpbroadcastmw2d.path, broadcast_vpbroadcastmw2d.source),
    entry(concatenate_vpshldd.family, concatenate_vpshldd.path, concatenate_vpshldd.source),
    entry(concatenate_vpshldq.family, concatenate_vpshldq.path, concatenate_vpshldq.source),
    entry(concatenate_vpshldvd.family, concatenate_vpshldvd.path, concatenate_vpshldvd.source),
    entry(concatenate_vpshldvq.family, concatenate_vpshldvq.path, concatenate_vpshldvq.source),
    entry(concatenate_vpshldvw.family, concatenate_vpshldvw.path, concatenate_vpshldvw.source),
    entry(concatenate_vpshldw.family, concatenate_vpshldw.path, concatenate_vpshldw.source),
    entry(concatenate_vpshrdd.family, concatenate_vpshrdd.path, concatenate_vpshrdd.source),
    entry(concatenate_vpshrdq.family, concatenate_vpshrdq.path, concatenate_vpshrdq.source),
    entry(concatenate_vpshrdvd.family, concatenate_vpshrdvd.path, concatenate_vpshrdvd.source),
    entry(concatenate_vpshrdvq.family, concatenate_vpshrdvq.path, concatenate_vpshrdvq.source),
    entry(concatenate_vpshrdvw.family, concatenate_vpshrdvw.path, concatenate_vpshrdvw.source),
    entry(concatenate_vpshrdw.family, concatenate_vpshrdw.path, concatenate_vpshrdw.source),
    entry(conditional_cmova.family, conditional_cmova.path, conditional_cmova.source),
    entry(conditional_cmovae.family, conditional_cmovae.path, conditional_cmovae.source),
    entry(conditional_cmovb.family, conditional_cmovb.path, conditional_cmovb.source),
    entry(conditional_cmovbe.family, conditional_cmovbe.path, conditional_cmovbe.source),
    entry(conditional_cmovc.family, conditional_cmovc.path, conditional_cmovc.source),
    entry(conditional_cmove.family, conditional_cmove.path, conditional_cmove.source),
    entry(conditional_cmovg.family, conditional_cmovg.path, conditional_cmovg.source),
    entry(conditional_cmovge.family, conditional_cmovge.path, conditional_cmovge.source),
    entry(conditional_cmovl.family, conditional_cmovl.path, conditional_cmovl.source),
    entry(conditional_cmovle.family, conditional_cmovle.path, conditional_cmovle.source),
    entry(conditional_cmovna.family, conditional_cmovna.path, conditional_cmovna.source),
    entry(conditional_cmovnae.family, conditional_cmovnae.path, conditional_cmovnae.source),
    entry(conditional_cmovnb.family, conditional_cmovnb.path, conditional_cmovnb.source),
    entry(conditional_cmovnbe.family, conditional_cmovnbe.path, conditional_cmovnbe.source),
    entry(conditional_cmovnc.family, conditional_cmovnc.path, conditional_cmovnc.source),
    entry(conditional_cmovne.family, conditional_cmovne.path, conditional_cmovne.source),
    entry(conditional_cmovng.family, conditional_cmovng.path, conditional_cmovng.source),
    entry(conditional_cmovnge.family, conditional_cmovnge.path, conditional_cmovnge.source),
    entry(conditional_cmovnl.family, conditional_cmovnl.path, conditional_cmovnl.source),
    entry(conditional_cmovnle.family, conditional_cmovnle.path, conditional_cmovnle.source),
    entry(conditional_cmovno.family, conditional_cmovno.path, conditional_cmovno.source),
    entry(conditional_cmovnp.family, conditional_cmovnp.path, conditional_cmovnp.source),
    entry(conditional_cmovns.family, conditional_cmovns.path, conditional_cmovns.source),
    entry(conditional_cmovnz.family, conditional_cmovnz.path, conditional_cmovnz.source),
    entry(conditional_cmovo.family, conditional_cmovo.path, conditional_cmovo.source),
    entry(conditional_cmovp.family, conditional_cmovp.path, conditional_cmovp.source),
    entry(conditional_cmovpe.family, conditional_cmovpe.path, conditional_cmovpe.source),
    entry(conditional_cmovpo.family, conditional_cmovpo.path, conditional_cmovpo.source),
    entry(conditional_cmovs.family, conditional_cmovs.path, conditional_cmovs.source),
    entry(conditional_cmovz.family, conditional_cmovz.path, conditional_cmovz.source),
    entry(conditional_fcmovb.family, conditional_fcmovb.path, conditional_fcmovb.source),
    entry(conditional_fcmove.family, conditional_fcmove.path, conditional_fcmove.source),
    entry(conditional_fcmovbe.family, conditional_fcmovbe.path, conditional_fcmovbe.source),
    entry(conditional_fcmovu.family, conditional_fcmovu.path, conditional_fcmovu.source),
    entry(conditional_fcmovnb.family, conditional_fcmovnb.path, conditional_fcmovnb.source),
    entry(conditional_fcmovne.family, conditional_fcmovne.path, conditional_fcmovne.source),
    entry(conditional_fcmovnbe.family, conditional_fcmovnbe.path, conditional_fcmovnbe.source),
    entry(conditional_fcmovnu.family, conditional_fcmovnu.path, conditional_fcmovnu.source),
    entry(conditional_vmaskmovps.family, conditional_vmaskmovps.path, conditional_vmaskmovps.source),
    entry(conditional_vmaskmovpd.family, conditional_vmaskmovpd.path, conditional_vmaskmovpd.source),
    entry(conditional_vpmaskmovd.family, conditional_vpmaskmovd.path, conditional_vpmaskmovd.source),
    entry(conditional_vpmaskmovq.family, conditional_vpmaskmovq.path, conditional_vpmaskmovq.source),
    entry(convert_cbw.family, convert_cbw.path, convert_cbw.source),
    entry(convert_cwde.family, convert_cwde.path, convert_cwde.source),
    entry(convert_cdqe.family, convert_cdqe.path, convert_cdqe.source),
    entry(convert_cwd.family, convert_cwd.path, convert_cwd.source),
    entry(convert_cdq.family, convert_cdq.path, convert_cdq.source),
    entry(convert_cqo.family, convert_cqo.path, convert_cqo.source),
    entry(convert_cvtdq2pd.family, convert_cvtdq2pd.path, convert_cvtdq2pd.source),
    entry(convert_cvtdq2ps.family, convert_cvtdq2ps.path, convert_cvtdq2ps.source),
    entry(convert_cvtpd2dq.family, convert_cvtpd2dq.path, convert_cvtpd2dq.source),
    entry(convert_cvtpd2pi.family, convert_cvtpd2pi.path, convert_cvtpd2pi.source),
    entry(convert_cvtpd2ps.family, convert_cvtpd2ps.path, convert_cvtpd2ps.source),
    entry(convert_cvtpi2pd.family, convert_cvtpi2pd.path, convert_cvtpi2pd.source),
    entry(convert_cvtpi2ps.family, convert_cvtpi2ps.path, convert_cvtpi2ps.source),
    entry(convert_cvtps2dq.family, convert_cvtps2dq.path, convert_cvtps2dq.source),
    entry(convert_cvtps2pd.family, convert_cvtps2pd.path, convert_cvtps2pd.source),
    entry(convert_cvtps2pi.family, convert_cvtps2pi.path, convert_cvtps2pi.source),
    entry(convert_cvtsd2si.family, convert_cvtsd2si.path, convert_cvtsd2si.source),
    entry(convert_cvtsd2ss.family, convert_cvtsd2ss.path, convert_cvtsd2ss.source),
    entry(convert_cvtsi2sd.family, convert_cvtsi2sd.path, convert_cvtsi2sd.source),
    entry(convert_cvtsi2ss.family, convert_cvtsi2ss.path, convert_cvtsi2ss.source),
    entry(convert_cvtss2sd.family, convert_cvtss2sd.path, convert_cvtss2sd.source),
    entry(convert_cvtss2si.family, convert_cvtss2si.path, convert_cvtss2si.source),
    entry(convert_cvttpd2dq.family, convert_cvttpd2dq.path, convert_cvttpd2dq.source),
    entry(convert_cvttpd2pi.family, convert_cvttpd2pi.path, convert_cvttpd2pi.source),
    entry(convert_cvttps2dq.family, convert_cvttps2dq.path, convert_cvttps2dq.source),
    entry(convert_cvttps2pi.family, convert_cvttps2pi.path, convert_cvttps2pi.source),
    entry(convert_cvttsd2si.family, convert_cvttsd2si.path, convert_cvttsd2si.source),
    entry(convert_cvttss2si.family, convert_cvttss2si.path, convert_cvttss2si.source),
    entry(convert_vcvtne2ps2bf16.family, convert_vcvtne2ps2bf16.path, convert_vcvtne2ps2bf16.source),
    entry(convert_vcvtneps2bf16.family, convert_vcvtneps2bf16.path, convert_vcvtneps2bf16.source),
    entry(convert_vcvtpd2ph.family, convert_vcvtpd2ph.path, convert_vcvtpd2ph.source),
    entry(convert_vcvtpd2qq.family, convert_vcvtpd2qq.path, convert_vcvtpd2qq.source),
    entry(convert_vcvtpd2udq.family, convert_vcvtpd2udq.path, convert_vcvtpd2udq.source),
    entry(convert_vcvtpd2uqq.family, convert_vcvtpd2uqq.path, convert_vcvtpd2uqq.source),
    entry(convert_vcvtph2dq.family, convert_vcvtph2dq.path, convert_vcvtph2dq.source),
    entry(convert_vcvtph2pd.family, convert_vcvtph2pd.path, convert_vcvtph2pd.source),
    entry(convert_vcvtph2ps.family, convert_vcvtph2ps.path, convert_vcvtph2ps.source),
    entry(convert_vcvtph2psx.family, convert_vcvtph2psx.path, convert_vcvtph2psx.source),
    entry(convert_vcvtph2qq.family, convert_vcvtph2qq.path, convert_vcvtph2qq.source),
    entry(convert_vcvtph2udq.family, convert_vcvtph2udq.path, convert_vcvtph2udq.source),
    entry(convert_vcvtph2uqq.family, convert_vcvtph2uqq.path, convert_vcvtph2uqq.source),
    entry(convert_vcvtph2uw.family, convert_vcvtph2uw.path, convert_vcvtph2uw.source),
    entry(convert_vcvtph2w.family, convert_vcvtph2w.path, convert_vcvtph2w.source),
    entry(convert_vcvtps2ph.family, convert_vcvtps2ph.path, convert_vcvtps2ph.source),
    entry(convert_vcvtps2phx.family, convert_vcvtps2phx.path, convert_vcvtps2phx.source),
    entry(convert_vcvtps2qq.family, convert_vcvtps2qq.path, convert_vcvtps2qq.source),
    entry(convert_vcvtps2udq.family, convert_vcvtps2udq.path, convert_vcvtps2udq.source),
    entry(convert_vcvtps2uqq.family, convert_vcvtps2uqq.path, convert_vcvtps2uqq.source),
    entry(convert_vcvtqq2pd.family, convert_vcvtqq2pd.path, convert_vcvtqq2pd.source),
    entry(convert_vcvtqq2ph.family, convert_vcvtqq2ph.path, convert_vcvtqq2ph.source),
    entry(convert_vcvtqq2ps.family, convert_vcvtqq2ps.path, convert_vcvtqq2ps.source),
    entry(convert_vcvtsd2sh.family, convert_vcvtsd2sh.path, convert_vcvtsd2sh.source),
    entry(convert_vcvtsd2usi.family, convert_vcvtsd2usi.path, convert_vcvtsd2usi.source),
    entry(convert_vcvtsh2sd.family, convert_vcvtsh2sd.path, convert_vcvtsh2sd.source),
    entry(convert_vcvtsh2si.family, convert_vcvtsh2si.path, convert_vcvtsh2si.source),
    entry(convert_vcvtsh2ss.family, convert_vcvtsh2ss.path, convert_vcvtsh2ss.source),
    entry(convert_vcvtsh2usi.family, convert_vcvtsh2usi.path, convert_vcvtsh2usi.source),
    entry(halt_hlt.family, halt_hlt.path, halt_hlt.source),
    entry(loop_loop.family, loop_loop.path, loop_loop.source),
    entry(loop_loope.family, loop_loope.path, loop_loope.source),
    entry(loop_loopne.family, loop_loopne.path, loop_loopne.source),
    entry(loop_pause.family, loop_pause.path, loop_pause.source),
    entry(memory_mfence.family, memory_mfence.path, memory_mfence.source),
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
    entry(push_pushf.family, push_pushf.path, push_pushf.source),
    entry(push_pushfd.family, push_pushfd.path, push_pushfd.source),
    entry(push_pushfq.family, push_pushfq.path, push_pushfq.source),
    entry(restore_frstore.family, restore_frstore.path, restore_frstore.source),
    entry(restore_fxrstore.family, restore_fxrstore.path, restore_fxrstore.source),
    entry(restore_rstore_ssp.family, restore_rstore_ssp.path, restore_rstore_ssp.source),
    entry(restore_xrstore.family, restore_xrstore.path, restore_xrstore.source),
    entry(restore_xrstors.family, restore_xrstors.path, restore_xrstors.source),
    entry(rotate_rcl.family, rotate_rcl.path, rotate_rcl.source),
    entry(rotate_rcr.family, rotate_rcr.path, rotate_rcr.source),
    entry(rotate_rol.family, rotate_rol.path, rotate_rol.source),
    entry(rotate_ror.family, rotate_ror.path, rotate_ror.source),
    entry(rotate_rorx.family, rotate_rorx.path, rotate_rorx.source),
    entry(rotate_vprold.family, rotate_vprold.path, rotate_vprold.source),
    entry(rotate_vprolvd.family, rotate_vprolvd.path, rotate_vprolvd.source),
    entry(rotate_vprolq.family, rotate_vprolq.path, rotate_vprolq.source),
    entry(rotate_vprolvq.family, rotate_vprolvq.path, rotate_vprolvq.source),
    entry(rotate_vprord.family, rotate_vprord.path, rotate_vprord.source),
    entry(rotate_vprorvd.family, rotate_vprorvd.path, rotate_vprorvd.source),
    entry(rotate_vprorq.family, rotate_vprorq.path, rotate_vprorq.source),
    entry(rotate_vprorvq.family, rotate_vprorvq.path, rotate_vprorvq.source),
    entry(save_fsave.family, save_fsave.path, save_fsave.source),
    entry(save_fxsave.family, save_fxsave.path, save_fxsave.source),
    entry(save_saveprevssp.family, save_saveprevssp.path, save_saveprevssp.source),
    entry(swap_swapgs.family, swap_swapgs.path, swap_swapgs.source),
    entry(sub_sub.family, sub_sub.path, sub_sub.source),
    entry(sub_subpd.family, sub_subpd.path, sub_subpd.source),
    entry(sub_subps.family, sub_subps.path, sub_subps.source),
    entry(sub_subsd.family, sub_subsd.path, sub_subsd.source),
    entry(sub_subss.family, sub_subss.path, sub_subss.source),
    entry(test_test.family, test_test.path, test_test.source),
    entry(test_testui.family, test_testui.path, test_testui.source),
    entry(undef_ud0.family, undef_ud0.path, undef_ud0.source),
    entry(undef_ud1.family, undef_ud1.path, undef_ud1.source),
    entry(undef_ud2.family, undef_ud2.path, undef_ud2.source),
    entry(unordered_ucomisd.family, unordered_ucomisd.path, unordered_ucomisd.source),
    entry(unordered_ucomiss.family, unordered_ucomiss.path, unordered_ucomiss.source),
    entry(unordered_vucomish.family, unordered_vucomish.path, unordered_vucomish.source),
    entry(variable_vpsllvw.family, variable_vpsllvw.path, variable_vpsllvw.source),
    entry(variable_vpsllvd.family, variable_vpsllvd.path, variable_vpsllvd.source),
    entry(variable_vpsllvq.family, variable_vpsllvq.path, variable_vpsllvq.source),
    entry(variable_vpsravw.family, variable_vpsravw.path, variable_vpsravw.source),
    entry(variable_vpsravd.family, variable_vpsravd.path, variable_vpsravd.source),
    entry(variable_vpsravq.family, variable_vpsravq.path, variable_vpsravq.source),
    entry(variable_vpsrlvw.family, variable_vpsrlvw.path, variable_vpsrlvw.source),
    entry(variable_vpsrlvd.family, variable_vpsrlvd.path, variable_vpsrlvd.source),
    entry(variable_vpsrlvq.family, variable_vpsrlvq.path, variable_vpsrlvq.source),
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
    entry(cache_clwb.family, cache_clwb.path, cache_clwb.source),
    entry(cpu_cpuid.family, cpu_cpuid.path, cpu_cpuid.source),
    entry(sha_sha1msg1.family, sha_sha1msg1.path, sha_sha1msg1.source),
    entry(sha_sha1msg2.family, sha_sha1msg2.path, sha_sha1msg2.source),
    entry(sha_sha1nexte.family, sha_sha1nexte.path, sha_sha1nexte.source),
    entry(sha_sha1rnds4.family, sha_sha1rnds4.path, sha_sha1rnds4.source),
    entry(sha_sha256msg1.family, sha_sha256msg1.path, sha_sha256msg1.source),
    entry(sha_sha256msg2.family, sha_sha256msg2.path, sha_sha256msg2.source),
    entry(sha_sha256rnds2.family, sha_sha256rnds2.path, sha_sha256rnds2.source),
    entry(shadow_incssp.family, shadow_incssp.path, shadow_incssp.source),
    entry(terminate_endbr32.family, terminate_endbr32.path, terminate_endbr32.source),
    entry(terminate_endbr64.family, terminate_endbr64.path, terminate_endbr64.source),
    entry(sys_syscall.family, sys_syscall.path, sys_syscall.source),
    entry(sys_sysenter.family, sys_sysenter.path, sys_sysenter.source),
    entry(sys_sysexit.family, sys_sysexit.path, sys_sysexit.source),
    entry(sys_sysret.family, sys_sysret.path, sys_sysret.source),
    entry(shuffle_shufpd.family, shuffle_shufpd.path, shuffle_shufpd.source),
    entry(shuffle_shufps.family, shuffle_shufps.path, shuffle_shufps.source),
    entry(shuffle_vpshufbitqmb.family, shuffle_vpshufbitqmb.path, shuffle_vpshufbitqmb.source),
    entry(shuffle_vshuff32x4.family, shuffle_vshuff32x4.path, shuffle_vshuff32x4.source),
    entry(shuffle_vshuff64x2.family, shuffle_vshuff64x2.path, shuffle_vshuff64x2.source),
    entry(shuffle_vshufi32x4.family, shuffle_vshufi32x4.path, shuffle_vshufi32x4.source),
    entry(shuffle_vshufi64x2.family, shuffle_vshufi64x2.path, shuffle_vshufi64x2.source),
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
    entry(set_monitor.family, set_monitor.path, set_monitor.source),
    entry(set_umonitor.family, set_umonitor.path, set_umonitor.source),
    entry(set_stac.family, set_stac.path, set_stac.source),
    entry(set_stc.family, set_stc.path, set_stc.source),
    entry(set_std.family, set_std.path, set_std.source),
    entry(set_sti.family, set_sti.path, set_sti.source),
    entry(set_stui.family, set_stui.path, set_stui.source),
    entry(set_xsetbv.family, set_xsetbv.path, set_xsetbv.source),
    entry(set_seta.family, set_seta.path, set_seta.source),
    entry(set_setae.family, set_setae.path, set_setae.source),
    entry(set_setb.family, set_setb.path, set_setb.source),
    entry(set_setbe.family, set_setbe.path, set_setbe.source),
    entry(set_setc.family, set_setc.path, set_setc.source),
    entry(set_sete.family, set_sete.path, set_sete.source),
    entry(set_setg.family, set_setg.path, set_setg.source),
    entry(set_setge.family, set_setge.path, set_setge.source),
    entry(set_setl.family, set_setl.path, set_setl.source),
    entry(set_setle.family, set_setle.path, set_setle.source),
    entry(set_setna.family, set_setna.path, set_setna.source),
    entry(set_setnae.family, set_setnae.path, set_setnae.source),
    entry(set_setnb.family, set_setnb.path, set_setnb.source),
    entry(set_setnbe.family, set_setnbe.path, set_setnbe.source),
    entry(set_setnc.family, set_setnc.path, set_setnc.source),
    entry(set_setne.family, set_setne.path, set_setne.source),
    entry(set_setng.family, set_setng.path, set_setng.source),
    entry(set_setnge.family, set_setnge.path, set_setnge.source),
    entry(set_setnl.family, set_setnl.path, set_setnl.source),
    entry(set_setnle.family, set_setnle.path, set_setnle.source),
    entry(set_setno.family, set_setno.path, set_setno.source),
    entry(set_setnp.family, set_setnp.path, set_setnp.source),
    entry(set_setns.family, set_setns.path, set_setns.source),
    entry(set_setnz.family, set_setnz.path, set_setnz.source),
    entry(set_seto.family, set_seto.path, set_seto.source),
    entry(set_setp.family, set_setp.path, set_setp.source),
    entry(set_setpe.family, set_setpe.path, set_setpe.source),
    entry(set_setpo.family, set_setpo.path, set_setpo.source),
    entry(set_sets.family, set_sets.path, set_sets.source),
    entry(set_setz.family, set_setz.path, set_setz.source),
    entry(count_lzcnt.family, count_lzcnt.path, count_lzcnt.source),
    entry(count_tzcnt.family, count_tzcnt.path, count_tzcnt.source),
    entry(count_vplzcntd.family, count_vplzcntd.path, count_vplzcntd.source),
    entry(count_vplzcntq.family, count_vplzcntq.path, count_vplzcntq.source),
    entry(exchange_fxch.family, exchange_fxch.path, exchange_fxch.source),
    entry(exchange_xadd.family, exchange_xadd.path, exchange_xadd.source),
    entry(exchange_xchg.family, exchange_xchg.path, exchange_xchg.source),
    entry(nop_fnop.family, nop_fnop.path, nop_fnop.source),
    entry(nop_nop.family, nop_nop.path, nop_nop.source),
    entry(not_not.family, not_not.path, not_not.source),
    entry(not_knotw.family, not_knotw.path, not_knotw.source),
    entry(not_knotb.family, not_knotb.path, not_knotb.source),
    entry(not_knotq.family, not_knotq.path, not_knotq.source),
    entry(not_knotd.family, not_knotd.path, not_knotd.source),
    entry(andnot_pandn.family, andnot_pandn.path, andnot_pandn.source),
    entry(andnot_vpandn.family, andnot_vpandn.path, andnot_vpandn.source),
    entry(andnot_vpandnd.family, andnot_vpandnd.path, andnot_vpandnd.source),
    entry(andnot_vpandnq.family, andnot_vpandnq.path, andnot_vpandnq.source),
    entry(andnot_kandnw.family, andnot_kandnw.path, andnot_kandnw.source),
    entry(andnot_kandnb.family, andnot_kandnb.path, andnot_kandnb.source),
    entry(andnot_kandnq.family, andnot_kandnq.path, andnot_kandnq.source),
    entry(andnot_kandnd.family, andnot_kandnd.path, andnot_kandnd.source),
    entry(bitposition_bzhi.family, bitposition_bzhi.path, bitposition_bzhi.source),
    entry(change_fchs.family, change_fchs.path, change_fchs.source),
    entry(complement_cmc.family, complement_cmc.path, complement_cmc.source),
    entry(decimal_daa.family, decimal_daa.path, decimal_daa.source),
    entry(decimal_das.family, decimal_das.path, decimal_das.source),
    entry(dep_pdep.family, dep_pdep.path, dep_pdep.source),
    entry(detect_vpconflictd.family, detect_vpconflictd.path, detect_vpconflictd.source),
    entry(detect_vpconflictq.family, detect_vpconflictq.path, detect_vpconflictq.source),
    entry(empty_emms.family, empty_emms.path, empty_emms.source),
    entry(end_xend.family, end_xend.path, end_xend.source),
    entry(examine_fxam.family, examine_fxam.path, examine_fxam.source),
    entry(expand_vpexpandb.family, expand_vpexpandb.path, expand_vpexpandb.source),
    entry(expand_vpexpandw.family, expand_vpexpandw.path, expand_vpexpandw.source),
    entry(free_ffree.family, free_ffree.path, free_ffree.source),
    entry(pand_pand.family, pand_pand.path, pand_pand.source),
    entry(pand_vpand.family, pand_vpand.path, pand_vpand.source),
    entry(pand_vpandd.family, pand_vpandd.path, pand_vpandd.source),
    entry(pand_vpandq.family, pand_vpandq.path, pand_vpandq.source),
    entry(partial_fpatan.family, partial_fpatan.path, partial_fpatan.source),
    entry(partial_fprem.family, partial_fprem.path, partial_fprem.source),
    entry(partial_fprem1.family, partial_fprem1.path, partial_fprem1.source),
    entry(partial_fptan.family, partial_fptan.path, partial_fptan.source),
    entry(pause_tpause.family, pause_tpause.path, pause_tpause.source),
    entry(prefetch_prefetchw.family, prefetch_prefetchw.path, prefetch_prefetchw.source),
    entry(prefetch_prefetcht0.family, prefetch_prefetcht0.path, prefetch_prefetcht0.source),
    entry(prefetch_prefetcht1.family, prefetch_prefetcht1.path, prefetch_prefetcht1.source),
    entry(prefetch_prefetcht2.family, prefetch_prefetcht2.path, prefetch_prefetcht2.source),
    entry(prefetch_prefetchnta.family, prefetch_prefetchnta.path, prefetch_prefetchnta.source),
    entry(pxor_pxor.family, pxor_pxor.path, pxor_pxor.source),
    entry(pxor_vpxor.family, pxor_vpxor.path, pxor_vpxor.source),
    entry(pxor_vpxord.family, pxor_vpxord.path, pxor_vpxord.source),
    entry(pxor_vpxorq.family, pxor_vpxorq.path, pxor_vpxorq.source),
    entry(release_tilerelease.family, release_tilerelease.path, release_tilerelease.source),
    entry(reset_hreset.family, reset_hreset.path, reset_hreset.source),
    entry(resume_rsm.family, resume_rsm.path, resume_rsm.source),
    entry(rpl_arpl.family, rpl_arpl.path, rpl_arpl.source),
    entry(select_vpmultishiftqb.family, select_vpmultishiftqb.path, select_vpmultishiftqb.source),
    entry(send_senduipi.family, send_senduipi.path, send_senduipi.source),
    entry(serialize_serialize.family, serialize_serialize.path, serialize_serialize.source),
    entry(enqueue_enqcmd.family, enqueue_enqcmd.path, enqueue_enqcmd.source),
    entry(extr_bextr.family, extr_bextr.path, extr_bextr.source),
    entry(extr_extractps.family, extr_extractps.path, extr_extractps.source),
    entry(extr_fxtract.family, extr_fxtract.path, extr_fxtract.source),
    entry(extr_pext.family, extr_pext.path, extr_pext.source),
    entry(lock_lock.family, lock_lock.path, lock_lock.source),
    entry(lock_xacquire.family, lock_xacquire.path, lock_xacquire.source),
    entry(lock_xrelease.family, lock_xrelease.path, lock_xrelease.source),
    entry(logical_nand_vptestnmb.family, logical_nand_vptestnmb.path, logical_nand_vptestnmb.source),
    entry(logical_nand_vptestnmw.family, logical_nand_vptestnmw.path, logical_nand_vptestnmw.source),
    entry(logical_nand_vptestnmd.family, logical_nand_vptestnmd.path, logical_nand_vptestnmd.source),
    entry(logical_nand_vptestnmq.family, logical_nand_vptestnmq.path, logical_nand_vptestnmq.source),
    entry(logical_or_korw.family, logical_or_korw.path, logical_or_korw.source),
    entry(logical_or_korb.family, logical_or_korb.path, logical_or_korb.source),
    entry(logical_or_korq.family, logical_or_korq.path, logical_or_korq.source),
    entry(logical_or_kord.family, logical_or_kord.path, logical_or_kord.source),
    entry(logical_or_por.family, logical_or_por.path, logical_or_por.source),
    entry(logical_or_vpor.family, logical_or_vpor.path, logical_or_vpor.source),
    entry(logical_or_vpord.family, logical_or_vpord.path, logical_or_vpord.source),
    entry(logical_or_vporq.family, logical_or_vporq.path, logical_or_vporq.source),
    entry(logical_xnor_kxnorw.family, logical_xnor_kxnorw.path, logical_xnor_kxnorw.source),
    entry(logical_xnor_kxnorb.family, logical_xnor_kxnorb.path, logical_xnor_kxnorb.source),
    entry(logical_xnor_kxnorq.family, logical_xnor_kxnorq.path, logical_xnor_kxnorq.source),
    entry(logical_xnor_kxnord.family, logical_xnor_kxnord.path, logical_xnor_kxnord.source),
    entry(neg_neg.family, neg_neg.path, neg_neg.source),
    entry(round_frndint.family, round_frndint.path, round_frndint.source),
    entry(encode_encodekey128.family, encode_encodekey128.path, encode_encodekey128.source),
    entry(galois_gf2p8affineinvqb.family, galois_gf2p8affineinvqb.path, galois_gf2p8affineinvqb.source),
    entry(galois_gf2p8affineqb.family, galois_gf2p8affineqb.path, galois_gf2p8affineqb.source),
    entry(galois_gf2p8mulb.family, galois_gf2p8mulb.path, galois_gf2p8mulb.source),
    entry(inc_dec_fdecstp.family, inc_dec_fdecstp.path, inc_dec_fdecstp.source),
    entry(inc_dec_fincstp.family, inc_dec_fincstp.path, inc_dec_fincstp.source),
    entry(initialize_finit.family, initialize_finit.path, initialize_finit.source),
    entry(initialize_fninit.family, initialize_fninit.path, initialize_fninit.source),
    entry(invalidate_invd.family, invalidate_invd.path, invalidate_invd.source),
    entry(invalidate_invlpg.family, invalidate_invlpg.path, invalidate_invlpg.source),
    entry(invalidate_invpcid.family, invalidate_invpcid.path, invalidate_invpcid.source),
    entry(make_enter.family, make_enter.path, make_enter.source),
    entry(repeat_rep.family, repeat_rep.path, repeat_rep.source),
    entry(repeat_repe.family, repeat_repe.path, repeat_repe.source),
    entry(repeat_repne.family, repeat_repne.path, repeat_repne.source),
    entry(scatter_vpscatterdd.family, scatter_vpscatterdd.path, scatter_vpscatterdd.source),
    entry(scatter_vpscatterdq.family, scatter_vpscatterdq.path, scatter_vpscatterdq.source),
    entry(scatter_vpscatterqd.family, scatter_vpscatterqd.path, scatter_vpscatterqd.source),
    entry(scatter_vpscatterqq.family, scatter_vpscatterqq.path, scatter_vpscatterqq.source),
    entry(scatter_vscatterdps.family, scatter_vscatterdps.path, scatter_vscatterdps.source),
    entry(scatter_vscatterdpd.family, scatter_vscatterdpd.path, scatter_vscatterdpd.source),
    entry(scatter_vscatterqps.family, scatter_vscatterqps.path, scatter_vscatterqps.source),
    entry(scatter_vscatterqpd.family, scatter_vscatterqpd.path, scatter_vscatterqpd.source),
    entry(gather_vgatherdpd.family, gather_vgatherdpd.path, gather_vgatherdpd.source),
    entry(gather_vgatherqpd.family, gather_vgatherqpd.path, gather_vgatherqpd.source),
    entry(gather_vgatherdps.family, gather_vgatherdps.path, gather_vgatherdps.source),
    entry(gather_vgatherqps.family, gather_vgatherqps.path, gather_vgatherqps.source),
    entry(gather_vpgatherdd.family, gather_vpgatherdd.path, gather_vpgatherdd.source),
    entry(gather_vpgatherdq.family, gather_vpgatherdq.path, gather_vpgatherdq.source),
    entry(gather_vpgatherqd.family, gather_vpgatherqd.path, gather_vpgatherqd.source),
    entry(gather_vpgatherqq.family, gather_vpgatherqq.path, gather_vpgatherqq.source),
    entry(get_xgetbv.family, get_xgetbv.path, get_xgetbv.source),
    entry(square_root_fsqrt.family, square_root_fsqrt.path, square_root_fsqrt.source),
    entry(square_root_sqrtpd.family, square_root_sqrtpd.path, square_root_sqrtpd.source),
    entry(square_root_sqrtps.family, square_root_sqrtps.path, square_root_sqrtps.source),
    entry(table_xlat.family, table_xlat.path, table_xlat.source),
    entry(table_xlatb.family, table_xlatb.path, table_xlatb.source),
    entry(trig_fcos.family, trig_fcos.path, trig_fcos.source),
    entry(trig_fsin.family, trig_fsin.path, trig_fsin.source),
    entry(trig_fsincos.family, trig_fsincos.path, trig_fsincos.source),
    entry(wait_wait.family, wait_wait.path, wait_wait.source),
    entry(wait_mwait.family, wait_mwait.path, wait_mwait.source),
    entry(write_ptwrite.family, write_ptwrite.path, write_ptwrite.source),
    entry(write_wbinvd.family, write_wbinvd.path, write_wbinvd.source),
    entry(write_wbnoinvd.family, write_wbnoinvd.path, write_wbnoinvd.source),
    entry(write_wrfsbase.family, write_wrfsbase.path, write_wrfsbase.source),
    entry(write_wrgsbase.family, write_wrgsbase.path, write_wrgsbase.source),
    entry(write_wrmsr.family, write_wrmsr.path, write_wrmsr.source),
    entry(write_wrpkru.family, write_wrpkru.path, write_wrpkru.source),
    entry(absolute_fabs.family, absolute_fabs.path, absolute_fabs.source),
    entry(absolute_pabsb.family, absolute_pabsb.path, absolute_pabsb.source),
    entry(absolute_pabsd.family, absolute_pabsd.path, absolute_pabsd.source),
    entry(absolute_pabsq.family, absolute_pabsq.path, absolute_pabsq.source),
    entry(absolute_pabsw.family, absolute_pabsw.path, absolute_pabsw.source),
    entry(absolute_vdbpsadbw.family, absolute_vdbpsadbw.path, absolute_vdbpsadbw.source),
    entry(accumulate_crc32.family, accumulate_crc32.path, accumulate_crc32.source),
    entry(reverse_fdivr.family, reverse_fdivr.path, reverse_fdivr.source),
    entry(reverse_fdivrp.family, reverse_fdivrp.path, reverse_fdivrp.source),
    entry(reverse_fidivr.family, reverse_fidivr.path, reverse_fidivr.source),
    entry(reverse_fsubr.family, reverse_fsubr.path, reverse_fsubr.source),
    entry(reverse_fsubrp.family, reverse_fsubrp.path, reverse_fsubrp.source),
    entry(reverse_fisubr.family, reverse_fisubr.path, reverse_fisubr.source),
    entry(scan_scas.family, scan_scas.path, scan_scas.source),
    entry(scan_scasb.family, scan_scasb.path, scan_scasb.source),
    entry(scan_scasw.family, scan_scasw.path, scan_scasw.source),
    entry(scan_scasd.family, scan_scasd.path, scan_scasd.source),
    entry(scan_scasq.family, scan_scasq.path, scan_scasq.source),
    entry(compute_f2xm1.family, compute_f2xm1.path, compute_f2xm1.source),
    entry(compute_fyl2x.family, compute_fyl2x.path, compute_fyl2x.source),
    entry(compute_fyl2xp1.family, compute_fyl2xp1.path, compute_fyl2xp1.source),
    entry(compute_psadbw.family, compute_psadbw.path, compute_psadbw.source),
    entry(compute_mpsadbw.family, compute_mpsadbw.path, compute_mpsadbw.source),
    entry(compute_rcpps.family, compute_rcpps.path, compute_rcpps.source),
    entry(compute_rcpss.family, compute_rcpss.path, compute_rcpss.source),
    entry(compute_rsqrtps.family, compute_rsqrtps.path, compute_rsqrtps.source),
    entry(compute_rsqrtss.family, compute_rsqrtss.path, compute_rsqrtss.source),
    entry(compute_sqrtsd.family, compute_sqrtsd.path, compute_sqrtsd.source),
    entry(compute_sqrtss.family, compute_sqrtss.path, compute_sqrtss.source),
    entry(compute_vp2intersect.family, compute_vp2intersect.path, compute_vp2intersect.source),
    entry(zero_tilezero.family, zero_tilezero.path, zero_tilezero.source),
    entry(zero_vzeroall.family, zero_vzeroall.path, zero_vzeroall.source),
    entry(zero_vzeroupper.family, zero_vzeroupper.path, zero_vzeroupper.source),
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
    try std.testing.expectEqual(@as(usize, 596), tableCount());
    validateAll();
    for (documented_reference_mnemonics) |name| try std.testing.expect(findByName(name) != null);
    const add = (findByName("ADD") orelse return error.MissingAdd).metadata();
    try std.testing.expectEqualStrings("x86_add", add.handler);
    try std.testing.expect(add.encoding_count >= 1);
}
