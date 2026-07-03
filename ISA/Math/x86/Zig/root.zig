const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const core = @import("../../core.zig");
const proofs = @import("../../proofs.zig");
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
const convert_vgetexppd = @import("CONVERT/VGETEXPPD.zig");
const convert_vgetexpph = @import("CONVERT/VGETEXPPH.zig");
const convert_vgetexpps = @import("CONVERT/VGETEXPPS.zig");
const convert_vgetexpsd = @import("CONVERT/VGETEXPSD.zig");
const convert_vgetexpsh = @import("CONVERT/VGETEXPSH.zig");
const convert_vgetexpss = @import("CONVERT/VGETEXPSS.zig");
const convert_vpmovb2m = @import("CONVERT/VPMOVB2M.zig");
const convert_vpmovw2m = @import("CONVERT/VPMOVW2M.zig");
const convert_vpmovd2m = @import("CONVERT/VPMOVD2M.zig");
const convert_vpmovq2m = @import("CONVERT/VPMOVQ2M.zig");
const convert_vpmovm2b = @import("CONVERT/VPMOVM2B.zig");
const convert_vpmovm2w = @import("CONVERT/VPMOVM2W.zig");
const convert_vpmovm2d = @import("CONVERT/VPMOVM2D.zig");
const convert_vpmovm2q = @import("CONVERT/VPMOVM2Q.zig");
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
const blend_pblendvb = @import("BLEND/PBLENDVB.zig");
const blend_pblendw = @import("BLEND/PBLENDW.zig");
const blend_vblendmpd = @import("BLEND/VBLENDMPD.zig");
const blend_vblendmps = @import("BLEND/VBLENDMPS.zig");
const blend_vpblendd = @import("BLEND/VPBLENDD.zig");
const blend_vpblendmb = @import("BLEND/VPBLENDMB.zig");
const blend_vpblendmw = @import("BLEND/VPBLENDMW.zig");
const blend_vpblendmd = @import("BLEND/VPBLENDMD.zig");
const blend_vpblendmq = @import("BLEND/VPBLENDMQ.zig");
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
const expand_vpexpandb = @import("EXPAND/vpexpandb.zig");
const expand_vpexpandw = @import("EXPAND/vpexpandw.zig");
const free_ffree = @import("FREE/FFREE.zig");
const pand_pand = @import("PAND/PAND.zig");
const pand_vpand = @import("PAND/VPAND.zig");
const pand_vpandd = @import("PAND/VPANDD.zig");
const pand_vpandq = @import("PAND/VPANDQ.zig");
const partial_fpatan = @import("PARTIAL/FPATAN.zig");
const partial_fprem = @import("PARTIAL/FPREM.zig");
const partial_fprem1 = @import("PARTIAL/FPREM1.zig");
const partial_fptan = @import("PARTIAL/FPTAN.zig");
const pause_tpause = @import("PAUSE/tpause.zig");
const platform_pconfig = @import("PLATFORM/PCONFIG.zig");
const prefetch_prefetchw = @import("PREFETCH/prefetchw.zig");
const prefetch_prefetcht0 = @import("PREFETCH/prefetcht0.zig");
const prefetch_prefetcht1 = @import("PREFETCH/prefetcht1.zig");
const prefetch_prefetcht2 = @import("PREFETCH/prefetcht2.zig");
const prefetch_prefetchnta = @import("PREFETCH/prefetchnta.zig");
const pxor_pxor = @import("PXOR/PXOR.zig");
const pxor_vpxor = @import("PXOR/VPXOR.zig");
const pxor_vpxord = @import("PXOR/VPXORD.zig");
const pxor_vpxorq = @import("PXOR/VPXORQ.zig");
const release_tilerelease = @import("RELEASE/tilerelease.zig");
const reset_hreset = @import("RESET/hreset.zig");
const resume_rsm = @import("RESUME/rsm.zig");
const rpl_arpl = @import("RPL/arpl.zig");
const select_vpmultishiftqb = @import("SELECT/vpmultishiftqb.zig");
const send_senduipi = @import("SEND/senduipi.zig");
const serialize_serialize = @import("SERIALIZE/serialize.zig");
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

pub const specs = blk: {
    @setEvalBranchQuota(5000);
    break :blk [_]core.InstructionMathSpec{
        spec(add_adc.meta),
        spec(add_adcx.meta),
        spec(add_add.meta),
        spec(add_addpd.meta),
        spec(add_addps.meta),
        spec(add_addsd.meta),
        spec(add_addss.meta),
        spec(add_addsubpd.meta),
        spec(add_addsubps.meta),
        spec(add_adox.meta),
        spec(add_fadd.meta),
        spec(add_faddp.meta),
        spec(add_fiadd.meta),
        spec(add_haddpd.meta),
        spec(add_haddps.meta),
        spec(add_kaddb.meta),
        spec(add_kaddd.meta),
        spec(add_kaddq.meta),
        spec(add_kaddw.meta),
        spec(ascii_aaa.meta),
        spec(ascii_aad.meta),
        spec(ascii_aam.meta),
        spec(ascii_aas.meta),
        spec(call_ret_call.meta),
        spec(call_ret_leave.meta),
        spec(call_ret_ret.meta),
        spec(cmp_cmp.meta),
        spec(cmp_cmppd.meta),
        spec(cmp_cmpps.meta),
        spec(cmp_cmpsd.meta),
        spec(cmp_cmpss.meta),
        spec(div_div.meta),
        spec(div_divpd.meta),
        spec(div_divps.meta),
        spec(div_divsd.meta),
        spec(div_divss.meta),
        spec(div_idiv.meta),
        spec(inc_dec_dec.meta),
        spec(inc_dec_inc.meta),
        spec(interrupt_int.meta),
        spec(interrupt_int1.meta),
        spec(interrupt_int3.meta),
        spec(interrupt_into.meta),
        spec(interrupt_iret.meta),
        spec(interrupt_sidt.meta),
        spec(jmp_ja.meta),
        spec(jmp_jae.meta),
        spec(jmp_jb.meta),
        spec(jmp_jbe.meta),
        spec(jmp_jc.meta),
        spec(jmp_jcxz.meta),
        spec(jmp_je.meta),
        spec(jmp_jecxz.meta),
        spec(jmp_jg.meta),
        spec(jmp_jge.meta),
        spec(jmp_jl.meta),
        spec(jmp_jle.meta),
        spec(jmp_jmp.meta),
        spec(jmp_jna.meta),
        spec(jmp_jnae.meta),
        spec(jmp_jnb.meta),
        spec(jmp_jnbe.meta),
        spec(jmp_jnc.meta),
        spec(jmp_jne.meta),
        spec(jmp_jng.meta),
        spec(jmp_jnge.meta),
        spec(jmp_jnl.meta),
        spec(jmp_jnle.meta),
        spec(jmp_jno.meta),
        spec(jmp_jnp.meta),
        spec(jmp_jns.meta),
        spec(jmp_jnz.meta),
        spec(jmp_jo.meta),
        spec(jmp_jp.meta),
        spec(jmp_jpe.meta),
        spec(jmp_jpo.meta),
        spec(jmp_jrcxz.meta),
        spec(jmp_js.meta),
        spec(jmp_jz.meta),
        spec(kand_kandw.meta),
        spec(kand_kandb.meta),
        spec(kand_kandq.meta),
        spec(kand_kandd.meta),
        spec(kortest_kortestw.meta),
        spec(kortest_kortestb.meta),
        spec(kortest_kortestq.meta),
        spec(kortest_kortestd.meta),
        spec(kxor_kxorw.meta),
        spec(kxor_kxorb.meta),
        spec(kxor_kxorq.meta),
        spec(kxor_kxord.meta),
        spec(load_lahf.meta),
        spec(load_lar.meta),
        spec(load_lddqu.meta),
        spec(load_ldmxcsr.meta),
        spec(load_lds.meta),
        spec(load_ldtilecfg.meta),
        spec(load_lea.meta),
        spec(load_les.meta),
        spec(load_lfence.meta),
        spec(load_lfs.meta),
        spec(load_lgdt.meta),
        spec(load_lgs.meta),
        spec(load_lidt.meta),
        spec(load_lldt.meta),
        spec(load_lmsw.meta),
        spec(load_loadiwkey.meta),
        spec(load_lods.meta),
        spec(load_lodsb.meta),
        spec(load_lodsd.meta),
        spec(load_lodsq.meta),
        spec(load_lodsw.meta),
        spec(load_lsl.meta),
        spec(load_lss.meta),
        spec(load_ltr.meta),
        spec(load_fbld.meta),
        spec(load_fild.meta),
        spec(load_fld.meta),
        spec(load_fld1.meta),
        spec(load_fldl2t.meta),
        spec(load_fldl2e.meta),
        spec(load_fldpi.meta),
        spec(load_fldlg2.meta),
        spec(load_fldln2.meta),
        spec(load_fldz.meta),
        spec(load_fldcw.meta),
        spec(load_fldenv.meta),
        spec(load_tileloadd.meta),
        spec(load_tileloaddt1.meta),
        spec(load_vbroadcastss.meta),
        spec(load_vbroadcastsd.meta),
        spec(load_vbroadcastf128.meta),
        spec(load_vbroadcastf32x2.meta),
        spec(load_vbroadcastf32x4.meta),
        spec(load_vbroadcastf64x2.meta),
        spec(load_vbroadcastf32x8.meta),
        spec(load_vbroadcastf64x4.meta),
        spec(load_vexpandpd.meta),
        spec(load_vexpandps.meta),
        spec(load_vpbroadcastb.meta),
        spec(load_vpbroadcastw.meta),
        spec(load_vpbroadcastd.meta),
        spec(load_vpbroadcastq.meta),
        spec(load_vbroadcasti32x2.meta),
        spec(load_vbroadcasti128.meta),
        spec(load_vbroadcasti32x4.meta),
        spec(load_vbroadcasti64x2.meta),
        spec(load_vbroadcasti32x8.meta),
        spec(load_vbroadcasti64x4.meta),
        spec(load_vpexpandd.meta),
        spec(load_vpexpandq.meta),
        spec(load_xresldtrk.meta),
        spec(load_xsusldtrk.meta),
        spec(abort_xabort.meta),
        spec(align_valignd.meta),
        spec(align_valignq.meta),
        spec(average_pavgb.meta),
        spec(average_pavgw.meta),
        spec(begin_xbegin.meta),
        spec(bitwise_vpternlogd.meta),
        spec(bitwise_vpternlogq.meta),
        spec(broadcast_vpbroadcastmb2q.meta),
        spec(broadcast_vpbroadcastmw2d.meta),
        spec(concatenate_vpshldd.meta),
        spec(concatenate_vpshldq.meta),
        spec(concatenate_vpshldvd.meta),
        spec(concatenate_vpshldvq.meta),
        spec(concatenate_vpshldvw.meta),
        spec(concatenate_vpshldw.meta),
        spec(concatenate_vpshrdd.meta),
        spec(concatenate_vpshrdq.meta),
        spec(concatenate_vpshrdvd.meta),
        spec(concatenate_vpshrdvq.meta),
        spec(concatenate_vpshrdvw.meta),
        spec(concatenate_vpshrdw.meta),
        spec(conditional_cmova.meta),
        spec(conditional_cmovae.meta),
        spec(conditional_cmovb.meta),
        spec(conditional_cmovbe.meta),
        spec(conditional_cmovc.meta),
        spec(conditional_cmove.meta),
        spec(conditional_cmovg.meta),
        spec(conditional_cmovge.meta),
        spec(conditional_cmovl.meta),
        spec(conditional_cmovle.meta),
        spec(conditional_cmovna.meta),
        spec(conditional_cmovnae.meta),
        spec(conditional_cmovnb.meta),
        spec(conditional_cmovnbe.meta),
        spec(conditional_cmovnc.meta),
        spec(conditional_cmovne.meta),
        spec(conditional_cmovng.meta),
        spec(conditional_cmovnge.meta),
        spec(conditional_cmovnl.meta),
        spec(conditional_cmovnle.meta),
        spec(conditional_cmovno.meta),
        spec(conditional_cmovnp.meta),
        spec(conditional_cmovns.meta),
        spec(conditional_cmovnz.meta),
        spec(conditional_cmovo.meta),
        spec(conditional_cmovp.meta),
        spec(conditional_cmovpe.meta),
        spec(conditional_cmovpo.meta),
        spec(conditional_cmovs.meta),
        spec(conditional_cmovz.meta),
        spec(conditional_fcmovb.meta),
        spec(conditional_fcmove.meta),
        spec(conditional_fcmovbe.meta),
        spec(conditional_fcmovu.meta),
        spec(conditional_fcmovnb.meta),
        spec(conditional_fcmovne.meta),
        spec(conditional_fcmovnbe.meta),
        spec(conditional_fcmovnu.meta),
        spec(conditional_vmaskmovps.meta),
        spec(conditional_vmaskmovpd.meta),
        spec(conditional_vpmaskmovd.meta),
        spec(conditional_vpmaskmovq.meta),
        spec(convert_cbw.meta),
        spec(convert_cwde.meta),
        spec(convert_cdqe.meta),
        spec(convert_cwd.meta),
        spec(convert_cdq.meta),
        spec(convert_cqo.meta),
        spec(convert_cvtdq2pd.meta),
        spec(convert_cvtdq2ps.meta),
        spec(convert_cvtpd2dq.meta),
        spec(convert_cvtpd2pi.meta),
        spec(convert_cvtpd2ps.meta),
        spec(convert_cvtpi2pd.meta),
        spec(convert_cvtpi2ps.meta),
        spec(convert_cvtps2dq.meta),
        spec(convert_cvtps2pd.meta),
        spec(convert_cvtps2pi.meta),
        spec(convert_cvtsd2si.meta),
        spec(convert_cvtsd2ss.meta),
        spec(convert_cvtsi2sd.meta),
        spec(convert_cvtsi2ss.meta),
        spec(convert_cvtss2sd.meta),
        spec(convert_cvtss2si.meta),
        spec(convert_cvttpd2dq.meta),
        spec(convert_cvttpd2pi.meta),
        spec(convert_cvttps2dq.meta),
        spec(convert_cvttps2pi.meta),
        spec(convert_cvttsd2si.meta),
        spec(convert_cvttss2si.meta),
        spec(convert_vcvtne2ps2bf16.meta),
        spec(convert_vcvtneps2bf16.meta),
        spec(convert_vcvtpd2ph.meta),
        spec(convert_vcvtpd2qq.meta),
        spec(convert_vcvtpd2udq.meta),
        spec(convert_vcvtpd2uqq.meta),
        spec(convert_vcvtph2dq.meta),
        spec(convert_vcvtph2pd.meta),
        spec(convert_vcvtph2ps.meta),
        spec(convert_vcvtph2psx.meta),
        spec(convert_vcvtph2qq.meta),
        spec(convert_vcvtph2udq.meta),
        spec(convert_vcvtph2uqq.meta),
        spec(convert_vcvtph2uw.meta),
        spec(convert_vcvtph2w.meta),
        spec(convert_vcvtps2ph.meta),
        spec(convert_vcvtps2phx.meta),
        spec(convert_vcvtps2qq.meta),
        spec(convert_vcvtps2udq.meta),
        spec(convert_vcvtps2uqq.meta),
        spec(convert_vcvtqq2pd.meta),
        spec(convert_vcvtqq2ph.meta),
        spec(convert_vcvtqq2ps.meta),
        spec(convert_vcvtsd2sh.meta),
        spec(convert_vcvtsd2usi.meta),
        spec(convert_vcvtsh2sd.meta),
        spec(convert_vcvtsh2si.meta),
        spec(convert_vcvtsh2ss.meta),
        spec(convert_vcvtsh2usi.meta),
        spec(convert_vgetexppd.meta),
        spec(convert_vgetexpph.meta),
        spec(convert_vgetexpps.meta),
        spec(convert_vgetexpsd.meta),
        spec(convert_vgetexpsh.meta),
        spec(convert_vgetexpss.meta),
        spec(convert_vpmovb2m.meta),
        spec(convert_vpmovw2m.meta),
        spec(convert_vpmovd2m.meta),
        spec(convert_vpmovq2m.meta),
        spec(convert_vpmovm2b.meta),
        spec(convert_vpmovm2w.meta),
        spec(convert_vpmovm2d.meta),
        spec(convert_vpmovm2q.meta),
        spec(halt_hlt.meta),
        spec(loop_loop.meta),
        spec(loop_loope.meta),
        spec(loop_loopne.meta),
        spec(loop_pause.meta),
        spec(memory_mfence.meta),
        spec(mov_mov.meta),
        spec(mov_movapd.meta),
        spec(mov_movaps.meta),
        spec(mov_movbe.meta),
        spec(mov_movd.meta),
        spec(mov_movddup.meta),
        spec(mov_movdir64b.meta),
        spec(mov_movdiri.meta),
        spec(mov_movdq2q.meta),
        spec(mov_movdqa.meta),
        spec(mov_movdqu.meta),
        spec(mov_movhlps.meta),
        spec(mov_movhpd.meta),
        spec(mov_movhps.meta),
        spec(mov_movlhps.meta),
        spec(mov_movlpd.meta),
        spec(mov_movlps.meta),
        spec(mov_movmskpd.meta),
        spec(mov_movmskps.meta),
        spec(mov_movntdq.meta),
        spec(mov_movntdqa.meta),
        spec(mov_movnti.meta),
        spec(mov_movntpd.meta),
        spec(mov_movntps.meta),
        spec(mov_movntq.meta),
        spec(mov_movq.meta),
        spec(mov_movq2dq.meta),
        spec(mov_movs.meta),
        spec(mov_movsb.meta),
        spec(mov_movsd.meta),
        spec(mov_movshdup.meta),
        spec(mov_movsldup.meta),
        spec(mov_movsq.meta),
        spec(mov_movss.meta),
        spec(mov_movsw.meta),
        spec(mov_movsx.meta),
        spec(mov_movsxd.meta),
        spec(mov_movupd.meta),
        spec(mov_movups.meta),
        spec(mov_movzx.meta),
        spec(mov_vmovapd.meta),
        spec(mov_vmovaps.meta),
        spec(mov_vmovd.meta),
        spec(mov_vmovddup.meta),
        spec(mov_vmovdqa.meta),
        spec(mov_vmovdqa32.meta),
        spec(mov_vmovdqa64.meta),
        spec(mov_vmovdqu.meta),
        spec(mov_vmovdqu16.meta),
        spec(mov_vmovdqu32.meta),
        spec(mov_vmovdqu64.meta),
        spec(mov_vmovdqu8.meta),
        spec(mov_vmovhlps.meta),
        spec(mov_vmovhpd.meta),
        spec(mov_vmovhps.meta),
        spec(mov_vmovlhps.meta),
        spec(mov_vmovlpd.meta),
        spec(mov_vmovlps.meta),
        spec(mov_vmovmskpd.meta),
        spec(mov_vmovmskps.meta),
        spec(mov_vmovntdq.meta),
        spec(mov_vmovntdqa.meta),
        spec(mov_vmovntpd.meta),
        spec(mov_vmovntps.meta),
        spec(mov_vmovq.meta),
        spec(mov_vmovsd.meta),
        spec(mov_vmovshdup.meta),
        spec(mov_vmovsldup.meta),
        spec(mov_vmovss.meta),
        spec(mov_vmovupd.meta),
        spec(mov_vmovups.meta),
        spec(mul_imul.meta),
        spec(mul_mul.meta),
        spec(mul_mulpd.meta),
        spec(mul_mulps.meta),
        spec(mul_mulsd.meta),
        spec(mul_mulss.meta),
        spec(mul_mulx.meta),
        spec(or_or.meta),
        spec(or_orpd.meta),
        spec(or_orps.meta),
        spec(output_out.meta),
        spec(output_outs.meta),
        spec(output_outsb.meta),
        spec(output_outsw.meta),
        spec(output_outsd.meta),
        spec(pop_pop.meta),
        spec(pop_popa.meta),
        spec(pop_popad.meta),
        spec(pop_popcnt.meta),
        spec(push_push.meta),
        spec(push_pusha.meta),
        spec(push_pushad.meta),
        spec(push_pushf.meta),
        spec(push_pushfd.meta),
        spec(push_pushfq.meta),
        spec(restore_frstore.meta),
        spec(restore_fxrstore.meta),
        spec(restore_rstore_ssp.meta),
        spec(restore_xrstore.meta),
        spec(restore_xrstors.meta),
        spec(rotate_rcl.meta),
        spec(rotate_rcr.meta),
        spec(rotate_rol.meta),
        spec(rotate_ror.meta),
        spec(rotate_rorx.meta),
        spec(rotate_vprold.meta),
        spec(rotate_vprolvd.meta),
        spec(rotate_vprolq.meta),
        spec(rotate_vprolvq.meta),
        spec(rotate_vprord.meta),
        spec(rotate_vprorvd.meta),
        spec(rotate_vprorq.meta),
        spec(rotate_vprorvq.meta),
        spec(save_fsave.meta),
        spec(save_fxsave.meta),
        spec(save_saveprevssp.meta),
        spec(swap_swapgs.meta),
        spec(sub_sub.meta),
        spec(sub_subpd.meta),
        spec(sub_subps.meta),
        spec(sub_subsd.meta),
        spec(sub_subss.meta),
        spec(test_test.meta),
        spec(test_testui.meta),
        spec(undef_ud0.meta),
        spec(undef_ud1.meta),
        spec(undef_ud2.meta),
        spec(unordered_ucomisd.meta),
        spec(unordered_ucomiss.meta),
        spec(unordered_vucomish.meta),
        spec(variable_vpsllvw.meta),
        spec(variable_vpsllvd.meta),
        spec(variable_vpsllvq.meta),
        spec(variable_vpsravw.meta),
        spec(variable_vpsravd.meta),
        spec(variable_vpsravq.meta),
        spec(variable_vpsrlvw.meta),
        spec(variable_vpsrlvd.meta),
        spec(variable_vpsrlvq.meta),
        spec(verify_verr.meta),
        spec(verify_verw.meta),
        spec(vptestm_vptestmb.meta),
        spec(vptestm_vptestmw.meta),
        spec(vptestm_vptestmd.meta),
        spec(vptestm_vptestmq.meta),
        spec(xor_xor.meta),
        spec(xor_xorpd.meta),
        spec(xor_xorps.meta),
        spec(and_and.meta),
        spec(and_andn.meta),
        spec(and_andps.meta),
        spec(and_andpd.meta),
        spec(and_andnps.meta),
        spec(and_andnpd.meta),
        spec(blend_blendpd.meta),
        spec(blend_blendps.meta),
        spec(blend_blendvpd.meta),
        spec(blend_blendvps.meta),
        spec(blend_pblendvb.meta),
        spec(blend_pblendw.meta),
        spec(blend_vblendmpd.meta),
        spec(blend_vblendmps.meta),
        spec(blend_vpblendd.meta),
        spec(blend_vpblendmb.meta),
        spec(blend_vpblendmw.meta),
        spec(blend_vpblendmd.meta),
        spec(blend_vpblendmq.meta),
        spec(bls_blsi.meta),
        spec(bls_blsmsk.meta),
        spec(bls_blsr.meta),
        spec(bs_bsf.meta),
        spec(bs_bsr.meta),
        spec(bs_bswap.meta),
        spec(bt_bt.meta),
        spec(bt_btc.meta),
        spec(bt_btr.meta),
        spec(bt_bts.meta),
        spec(cache_cldemote.meta),
        spec(cache_clflush.meta),
        spec(cache_clflushopt.meta),
        spec(cache_clwb.meta),
        spec(cpu_cpuid.meta),
        spec(sha_sha1msg1.meta),
        spec(sha_sha1msg2.meta),
        spec(sha_sha1nexte.meta),
        spec(sha_sha1rnds4.meta),
        spec(sha_sha256msg1.meta),
        spec(sha_sha256msg2.meta),
        spec(sha_sha256rnds2.meta),
        spec(shadow_incssp.meta),
        spec(terminate_endbr32.meta),
        spec(terminate_endbr64.meta),
        spec(sys_syscall.meta),
        spec(sys_sysenter.meta),
        spec(sys_sysexit.meta),
        spec(sys_sysret.meta),
        spec(shuffle_shufpd.meta),
        spec(shuffle_shufps.meta),
        spec(shuffle_vpshufbitqmb.meta),
        spec(shuffle_vshuff32x4.meta),
        spec(shuffle_vshuff64x2.meta),
        spec(shuffle_vshufi32x4.meta),
        spec(shuffle_vshufi64x2.meta),
        spec(shift_sal.meta),
        spec(shift_sar.meta),
        spec(shift_shl.meta),
        spec(shift_shr.meta),
        spec(shift_shld.meta),
        spec(shift_shrd.meta),
        spec(shift_sarx.meta),
        spec(shift_shlx.meta),
        spec(shift_shrx.meta),
        spec(clear_clac.meta),
        spec(clear_clc.meta),
        spec(clear_cld.meta),
        spec(clear_cli.meta),
        spec(clear_clrssbsy.meta),
        spec(clear_clts.meta),
        spec(clear_clui.meta),
        spec(clear_fclex.meta),
        spec(dot_dppd.meta),
        spec(dot_dpps.meta),
        spec(dot_tdpbf16ps.meta),
        spec(dot_tdpbssd.meta),
        spec(dot_tdpbsud.meta),
        spec(dot_tdpbusd.meta),
        spec(dot_tdpbuud.meta),
        spec(dot_vdpbf16ps.meta),
        spec(bound_bound.meta),
        spec(bound_bndcl.meta),
        spec(bound_bndcu.meta),
        spec(bound_bndcn.meta),
        spec(bound_bndldx.meta),
        spec(bound_bndmk.meta),
        spec(bound_bndmov.meta),
        spec(bound_bndstx.meta),
        spec(x87_fcom.meta),
        spec(x87_fcomp.meta),
        spec(x87_fcompp.meta),
        spec(x87_fcomi.meta),
        spec(x87_fcomip.meta),
        spec(x87_fucomi.meta),
        spec(x87_fucomip.meta),
        spec(x87_ficom.meta),
        spec(x87_ficomp.meta),
        spec(x87_fucom.meta),
        spec(x87_fucomp.meta),
        spec(x87_fucompp.meta),
        spec(aes_aesdec.meta),
        spec(aes_aesdec128kl.meta),
        spec(aes_aesdec256kl.meta),
        spec(aes_aesdeclast.meta),
        spec(aes_aesdecwide128kl.meta),
        spec(aes_aesdecwide256kl.meta),
        spec(aes_aesenc.meta),
        spec(aes_aesenc128kl.meta),
        spec(aes_aesenc256kl.meta),
        spec(aes_aesenclast.meta),
        spec(aes_aesencwide128kl.meta),
        spec(aes_aesencwide256kl.meta),
        spec(aes_aesimc.meta),
        spec(aes_aeskeygenassist.meta),
        spec(min_max_pmaxsb.meta),
        spec(min_max_pmaxsw.meta),
        spec(min_max_pmaxsd.meta),
        spec(min_max_pmaxsq.meta),
        spec(min_max_pmaxub.meta),
        spec(min_max_pmaxuw.meta),
        spec(min_max_pmaxud.meta),
        spec(min_max_pmaxuq.meta),
        spec(min_max_pminsb.meta),
        spec(min_max_pminsw.meta),
        spec(min_max_pminsd.meta),
        spec(min_max_pminsq.meta),
        spec(min_max_pminub.meta),
        spec(min_max_pminuw.meta),
        spec(min_max_pminud.meta),
        spec(min_max_pminuq.meta),
        spec(set_monitor.meta),
        spec(set_umonitor.meta),
        spec(set_stac.meta),
        spec(set_stc.meta),
        spec(set_std.meta),
        spec(set_sti.meta),
        spec(set_stui.meta),
        spec(set_xsetbv.meta),
        spec(set_seta.meta),
        spec(set_setae.meta),
        spec(set_setb.meta),
        spec(set_setbe.meta),
        spec(set_setc.meta),
        spec(set_sete.meta),
        spec(set_setg.meta),
        spec(set_setge.meta),
        spec(set_setl.meta),
        spec(set_setle.meta),
        spec(set_setna.meta),
        spec(set_setnae.meta),
        spec(set_setnb.meta),
        spec(set_setnbe.meta),
        spec(set_setnc.meta),
        spec(set_setne.meta),
        spec(set_setng.meta),
        spec(set_setnge.meta),
        spec(set_setnl.meta),
        spec(set_setnle.meta),
        spec(set_setno.meta),
        spec(set_setnp.meta),
        spec(set_setns.meta),
        spec(set_setnz.meta),
        spec(set_seto.meta),
        spec(set_setp.meta),
        spec(set_setpe.meta),
        spec(set_setpo.meta),
        spec(set_sets.meta),
        spec(set_setz.meta),
        spec(count_lzcnt.meta),
        spec(count_tzcnt.meta),
        spec(count_vplzcntd.meta),
        spec(count_vplzcntq.meta),
        spec(exchange_fxch.meta),
        spec(exchange_xadd.meta),
        spec(exchange_xchg.meta),
        spec(nop_fnop.meta),
        spec(nop_nop.meta),
        spec(not_not.meta),
        spec(not_knotw.meta),
        spec(not_knotb.meta),
        spec(not_knotq.meta),
        spec(not_knotd.meta),
        spec(andnot_pandn.meta),
        spec(andnot_vpandn.meta),
        spec(andnot_vpandnd.meta),
        spec(andnot_vpandnq.meta),
        spec(andnot_kandnw.meta),
        spec(andnot_kandnb.meta),
        spec(andnot_kandnq.meta),
        spec(andnot_kandnd.meta),
        spec(bitposition_bzhi.meta),
        spec(change_fchs.meta),
        spec(complement_cmc.meta),
        spec(decimal_daa.meta),
        spec(decimal_das.meta),
        spec(dep_pdep.meta),
        spec(detect_vpconflictd.meta),
        spec(detect_vpconflictq.meta),
        spec(empty_emms.meta),
        spec(end_xend.meta),
        spec(examine_fxam.meta),
        spec(expand_vpexpandb.meta),
        spec(expand_vpexpandw.meta),
        spec(free_ffree.meta),
        spec(pand_pand.meta),
        spec(pand_vpand.meta),
        spec(pand_vpandd.meta),
        spec(pand_vpandq.meta),
        spec(partial_fpatan.meta),
        spec(partial_fprem.meta),
        spec(partial_fprem1.meta),
        spec(partial_fptan.meta),
        spec(pause_tpause.meta),
        spec(platform_pconfig.meta),
        spec(prefetch_prefetchw.meta),
        spec(prefetch_prefetcht0.meta),
        spec(prefetch_prefetcht1.meta),
        spec(prefetch_prefetcht2.meta),
        spec(prefetch_prefetchnta.meta),
        spec(pxor_pxor.meta),
        spec(pxor_vpxor.meta),
        spec(pxor_vpxord.meta),
        spec(pxor_vpxorq.meta),
        spec(release_tilerelease.meta),
        spec(reset_hreset.meta),
        spec(resume_rsm.meta),
        spec(rpl_arpl.meta),
        spec(select_vpmultishiftqb.meta),
        spec(send_senduipi.meta),
        spec(serialize_serialize.meta),
        spec(enqueue_enqcmd.meta),
        spec(extr_bextr.meta),
        spec(extr_extractps.meta),
        spec(extr_fxtract.meta),
        spec(extr_pext.meta),
        spec(lock_lock.meta),
        spec(lock_xacquire.meta),
        spec(lock_xrelease.meta),
        spec(logical_nand_vptestnmb.meta),
        spec(logical_nand_vptestnmw.meta),
        spec(logical_nand_vptestnmd.meta),
        spec(logical_nand_vptestnmq.meta),
        spec(logical_or_korw.meta),
        spec(logical_or_korb.meta),
        spec(logical_or_korq.meta),
        spec(logical_or_kord.meta),
        spec(logical_or_por.meta),
        spec(logical_or_vpor.meta),
        spec(logical_or_vpord.meta),
        spec(logical_or_vporq.meta),
        spec(logical_xnor_kxnorw.meta),
        spec(logical_xnor_kxnorb.meta),
        spec(logical_xnor_kxnorq.meta),
        spec(logical_xnor_kxnord.meta),
        spec(neg_neg.meta),
        spec(round_frndint.meta),
        spec(encode_encodekey128.meta),
        spec(galois_gf2p8affineinvqb.meta),
        spec(galois_gf2p8affineqb.meta),
        spec(galois_gf2p8mulb.meta),
        spec(inc_dec_fdecstp.meta),
        spec(inc_dec_fincstp.meta),
        spec(initialize_finit.meta),
        spec(initialize_fninit.meta),
        spec(invalidate_invd.meta),
        spec(invalidate_invlpg.meta),
        spec(invalidate_invpcid.meta),
        spec(make_enter.meta),
        spec(repeat_rep.meta),
        spec(repeat_repe.meta),
        spec(repeat_repne.meta),
        spec(scatter_vpscatterdd.meta),
        spec(scatter_vpscatterdq.meta),
        spec(scatter_vpscatterqd.meta),
        spec(scatter_vpscatterqq.meta),
        spec(scatter_vscatterdps.meta),
        spec(scatter_vscatterdpd.meta),
        spec(scatter_vscatterqps.meta),
        spec(scatter_vscatterqpd.meta),
        spec(gather_vgatherdpd.meta),
        spec(gather_vgatherqpd.meta),
        spec(gather_vgatherdps.meta),
        spec(gather_vgatherqps.meta),
        spec(gather_vpgatherdd.meta),
        spec(gather_vpgatherdq.meta),
        spec(gather_vpgatherqd.meta),
        spec(gather_vpgatherqq.meta),
        spec(get_xgetbv.meta),
        spec(square_root_fsqrt.meta),
        spec(square_root_sqrtpd.meta),
        spec(square_root_sqrtps.meta),
        spec(table_xlat.meta),
        spec(table_xlatb.meta),
        spec(trig_fcos.meta),
        spec(trig_fsin.meta),
        spec(trig_fsincos.meta),
        spec(wait_wait.meta),
        spec(wait_mwait.meta),
        spec(write_ptwrite.meta),
        spec(write_wbinvd.meta),
        spec(write_wbnoinvd.meta),
        spec(write_wrfsbase.meta),
        spec(write_wrgsbase.meta),
        spec(write_wrmsr.meta),
        spec(write_wrpkru.meta),
        spec(absolute_fabs.meta),
        spec(absolute_pabsb.meta),
        spec(absolute_pabsd.meta),
        spec(absolute_pabsq.meta),
        spec(absolute_pabsw.meta),
        spec(absolute_vdbpsadbw.meta),
        spec(accumulate_crc32.meta),
        spec(reverse_fdivr.meta),
        spec(reverse_fdivrp.meta),
        spec(reverse_fidivr.meta),
        spec(reverse_fsubr.meta),
        spec(reverse_fsubrp.meta),
        spec(reverse_fisubr.meta),
        spec(scan_scas.meta),
        spec(scan_scasb.meta),
        spec(scan_scasw.meta),
        spec(scan_scasd.meta),
        spec(scan_scasq.meta),
        spec(compute_f2xm1.meta),
        spec(compute_fyl2x.meta),
        spec(compute_fyl2xp1.meta),
        spec(compute_psadbw.meta),
        spec(compute_mpsadbw.meta),
        spec(compute_rcpps.meta),
        spec(compute_rcpss.meta),
        spec(compute_rsqrtps.meta),
        spec(compute_rsqrtss.meta),
        spec(compute_sqrtsd.meta),
        spec(compute_sqrtss.meta),
        spec(compute_vp2intersect.meta),
        spec(zero_tilezero.meta),
        spec(zero_vzeroall.meta),
        spec(zero_vzeroupper.meta),
    };
};

pub const proof_reports = [_]proofs.ProofReport{
    add_adc.proof_report,
    add_adcx.proof_report,
    add_add.proof_report,
    add_addpd.proof_report,
    add_addps.proof_report,
    add_addsd.proof_report,
    add_addss.proof_report,
    add_addsubpd.proof_report,
    add_addsubps.proof_report,
    add_adox.proof_report,
    add_fadd.proof_report,
    add_faddp.proof_report,
    add_fiadd.proof_report,
    add_haddpd.proof_report,
    add_haddps.proof_report,
    add_kaddb.proof_report,
    add_kaddd.proof_report,
    add_kaddq.proof_report,
    add_kaddw.proof_report,
    ascii_aaa.proof_report,
    ascii_aad.proof_report,
    ascii_aam.proof_report,
    ascii_aas.proof_report,
    call_ret_call.proof_report,
    call_ret_leave.proof_report,
    call_ret_ret.proof_report,
    cmp_cmp.proof_report,
    cmp_cmppd.proof_report,
    cmp_cmpps.proof_report,
    cmp_cmpsd.proof_report,
    cmp_cmpss.proof_report,
    div_div.proof_report,
    div_divpd.proof_report,
    div_divps.proof_report,
    div_divsd.proof_report,
    div_divss.proof_report,
    div_idiv.proof_report,
    inc_dec_dec.proof_report,
    inc_dec_inc.proof_report,
    interrupt_int.proof_report,
    interrupt_int1.proof_report,
    interrupt_int3.proof_report,
    interrupt_into.proof_report,
    interrupt_iret.proof_report,
    interrupt_sidt.proof_report,
    jmp_ja.proof_report,
    jmp_jae.proof_report,
    jmp_jb.proof_report,
    jmp_jbe.proof_report,
    jmp_jc.proof_report,
    jmp_jcxz.proof_report,
    jmp_je.proof_report,
    jmp_jecxz.proof_report,
    jmp_jg.proof_report,
    jmp_jge.proof_report,
    jmp_jl.proof_report,
    jmp_jle.proof_report,
    jmp_jmp.proof_report,
    jmp_jna.proof_report,
    jmp_jnae.proof_report,
    jmp_jnb.proof_report,
    jmp_jnbe.proof_report,
    jmp_jnc.proof_report,
    jmp_jne.proof_report,
    jmp_jng.proof_report,
    jmp_jnge.proof_report,
    jmp_jnl.proof_report,
    jmp_jnle.proof_report,
    jmp_jno.proof_report,
    jmp_jnp.proof_report,
    jmp_jns.proof_report,
    jmp_jnz.proof_report,
    jmp_jo.proof_report,
    jmp_jp.proof_report,
    jmp_jpe.proof_report,
    jmp_jpo.proof_report,
    jmp_jrcxz.proof_report,
    jmp_js.proof_report,
    jmp_jz.proof_report,
    kand_kandw.proof_report,
    kand_kandb.proof_report,
    kand_kandq.proof_report,
    kand_kandd.proof_report,
    kortest_kortestw.proof_report,
    kortest_kortestb.proof_report,
    kortest_kortestq.proof_report,
    kortest_kortestd.proof_report,
    kxor_kxorw.proof_report,
    kxor_kxorb.proof_report,
    kxor_kxorq.proof_report,
    kxor_kxord.proof_report,
    load_lahf.proof_report,
    load_lar.proof_report,
    load_lddqu.proof_report,
    load_ldmxcsr.proof_report,
    load_lds.proof_report,
    load_ldtilecfg.proof_report,
    load_lea.proof_report,
    load_les.proof_report,
    load_lfence.proof_report,
    load_lfs.proof_report,
    load_lgdt.proof_report,
    load_lgs.proof_report,
    load_lidt.proof_report,
    load_lldt.proof_report,
    load_lmsw.proof_report,
    load_loadiwkey.proof_report,
    load_lods.proof_report,
    load_lodsb.proof_report,
    load_lodsd.proof_report,
    load_lodsq.proof_report,
    load_lodsw.proof_report,
    load_lsl.proof_report,
    load_lss.proof_report,
    load_ltr.proof_report,
    load_fbld.proof_report,
    load_fild.proof_report,
    load_fld.proof_report,
    load_fld1.proof_report,
    load_fldl2t.proof_report,
    load_fldl2e.proof_report,
    load_fldpi.proof_report,
    load_fldlg2.proof_report,
    load_fldln2.proof_report,
    load_fldz.proof_report,
    load_fldcw.proof_report,
    load_fldenv.proof_report,
    load_tileloadd.proof_report,
    load_tileloaddt1.proof_report,
    load_vbroadcastss.proof_report,
    load_vbroadcastsd.proof_report,
    load_vbroadcastf128.proof_report,
    load_vbroadcastf32x2.proof_report,
    load_vbroadcastf32x4.proof_report,
    load_vbroadcastf64x2.proof_report,
    load_vbroadcastf32x8.proof_report,
    load_vbroadcastf64x4.proof_report,
    load_vexpandpd.proof_report,
    load_vexpandps.proof_report,
    load_vpbroadcastb.proof_report,
    load_vpbroadcastw.proof_report,
    load_vpbroadcastd.proof_report,
    load_vpbroadcastq.proof_report,
    load_vbroadcasti32x2.proof_report,
    load_vbroadcasti128.proof_report,
    load_vbroadcasti32x4.proof_report,
    load_vbroadcasti64x2.proof_report,
    load_vbroadcasti32x8.proof_report,
    load_vbroadcasti64x4.proof_report,
    load_vpexpandd.proof_report,
    load_vpexpandq.proof_report,
    load_xresldtrk.proof_report,
    load_xsusldtrk.proof_report,
    abort_xabort.proof_report,
    align_valignd.proof_report,
    align_valignq.proof_report,
    average_pavgb.proof_report,
    average_pavgw.proof_report,
    begin_xbegin.proof_report,
    bitwise_vpternlogd.proof_report,
    bitwise_vpternlogq.proof_report,
    broadcast_vpbroadcastmb2q.proof_report,
    broadcast_vpbroadcastmw2d.proof_report,
    concatenate_vpshldd.proof_report,
    concatenate_vpshldq.proof_report,
    concatenate_vpshldvd.proof_report,
    concatenate_vpshldvq.proof_report,
    concatenate_vpshldvw.proof_report,
    concatenate_vpshldw.proof_report,
    concatenate_vpshrdd.proof_report,
    concatenate_vpshrdq.proof_report,
    concatenate_vpshrdvd.proof_report,
    concatenate_vpshrdvq.proof_report,
    concatenate_vpshrdvw.proof_report,
    concatenate_vpshrdw.proof_report,
    conditional_cmova.proof_report,
    conditional_cmovae.proof_report,
    conditional_cmovb.proof_report,
    conditional_cmovbe.proof_report,
    conditional_cmovc.proof_report,
    conditional_cmove.proof_report,
    conditional_cmovg.proof_report,
    conditional_cmovge.proof_report,
    conditional_cmovl.proof_report,
    conditional_cmovle.proof_report,
    conditional_cmovna.proof_report,
    conditional_cmovnae.proof_report,
    conditional_cmovnb.proof_report,
    conditional_cmovnbe.proof_report,
    conditional_cmovnc.proof_report,
    conditional_cmovne.proof_report,
    conditional_cmovng.proof_report,
    conditional_cmovnge.proof_report,
    conditional_cmovnl.proof_report,
    conditional_cmovnle.proof_report,
    conditional_cmovno.proof_report,
    conditional_cmovnp.proof_report,
    conditional_cmovns.proof_report,
    conditional_cmovnz.proof_report,
    conditional_cmovo.proof_report,
    conditional_cmovp.proof_report,
    conditional_cmovpe.proof_report,
    conditional_cmovpo.proof_report,
    conditional_cmovs.proof_report,
    conditional_cmovz.proof_report,
    conditional_fcmovb.proof_report,
    conditional_fcmove.proof_report,
    conditional_fcmovbe.proof_report,
    conditional_fcmovu.proof_report,
    conditional_fcmovnb.proof_report,
    conditional_fcmovne.proof_report,
    conditional_fcmovnbe.proof_report,
    conditional_fcmovnu.proof_report,
    conditional_vmaskmovps.proof_report,
    conditional_vmaskmovpd.proof_report,
    conditional_vpmaskmovd.proof_report,
    conditional_vpmaskmovq.proof_report,
    convert_cbw.proof_report,
    convert_cwde.proof_report,
    convert_cdqe.proof_report,
    convert_cwd.proof_report,
    convert_cdq.proof_report,
    convert_cqo.proof_report,
    convert_cvtdq2pd.proof_report,
    convert_cvtdq2ps.proof_report,
    convert_cvtpd2dq.proof_report,
    convert_cvtpd2pi.proof_report,
    convert_cvtpd2ps.proof_report,
    convert_cvtpi2pd.proof_report,
    convert_cvtpi2ps.proof_report,
    convert_cvtps2dq.proof_report,
    convert_cvtps2pd.proof_report,
    convert_cvtps2pi.proof_report,
    convert_cvtsd2si.proof_report,
    convert_cvtsd2ss.proof_report,
    convert_cvtsi2sd.proof_report,
    convert_cvtsi2ss.proof_report,
    convert_cvtss2sd.proof_report,
    convert_cvtss2si.proof_report,
    convert_cvttpd2dq.proof_report,
    convert_cvttpd2pi.proof_report,
    convert_cvttps2dq.proof_report,
    convert_cvttps2pi.proof_report,
    convert_cvttsd2si.proof_report,
    convert_cvttss2si.proof_report,
    convert_vcvtne2ps2bf16.proof_report,
    convert_vcvtneps2bf16.proof_report,
    convert_vcvtpd2ph.proof_report,
    convert_vcvtpd2qq.proof_report,
    convert_vcvtpd2udq.proof_report,
    convert_vcvtpd2uqq.proof_report,
    convert_vcvtph2dq.proof_report,
    convert_vcvtph2pd.proof_report,
    convert_vcvtph2ps.proof_report,
    convert_vcvtph2psx.proof_report,
    convert_vcvtph2qq.proof_report,
    convert_vcvtph2udq.proof_report,
    convert_vcvtph2uqq.proof_report,
    convert_vcvtph2uw.proof_report,
    convert_vcvtph2w.proof_report,
    convert_vcvtps2ph.proof_report,
    convert_vcvtps2phx.proof_report,
    convert_vcvtps2qq.proof_report,
    convert_vcvtps2udq.proof_report,
    convert_vcvtps2uqq.proof_report,
    convert_vcvtqq2pd.proof_report,
    convert_vcvtqq2ph.proof_report,
    convert_vcvtqq2ps.proof_report,
    convert_vcvtsd2sh.proof_report,
    convert_vcvtsd2usi.proof_report,
    convert_vcvtsh2sd.proof_report,
    convert_vcvtsh2si.proof_report,
    convert_vcvtsh2ss.proof_report,
    convert_vcvtsh2usi.proof_report,
    convert_vgetexppd.proof_report,
    convert_vgetexpph.proof_report,
    convert_vgetexpps.proof_report,
    convert_vgetexpsd.proof_report,
    convert_vgetexpsh.proof_report,
    convert_vgetexpss.proof_report,
    convert_vpmovb2m.proof_report,
    convert_vpmovw2m.proof_report,
    convert_vpmovd2m.proof_report,
    convert_vpmovq2m.proof_report,
    convert_vpmovm2b.proof_report,
    convert_vpmovm2w.proof_report,
    convert_vpmovm2d.proof_report,
    convert_vpmovm2q.proof_report,
    halt_hlt.proof_report,
    loop_loop.proof_report,
    loop_loope.proof_report,
    loop_loopne.proof_report,
    loop_pause.proof_report,
    memory_mfence.proof_report,
    mov_mov.proof_report,
    mov_movapd.proof_report,
    mov_movaps.proof_report,
    mov_movbe.proof_report,
    mov_movd.proof_report,
    mov_movddup.proof_report,
    mov_movdir64b.proof_report,
    mov_movdiri.proof_report,
    mov_movdq2q.proof_report,
    mov_movdqa.proof_report,
    mov_movdqu.proof_report,
    mov_movhlps.proof_report,
    mov_movhpd.proof_report,
    mov_movhps.proof_report,
    mov_movlhps.proof_report,
    mov_movlpd.proof_report,
    mov_movlps.proof_report,
    mov_movmskpd.proof_report,
    mov_movmskps.proof_report,
    mov_movntdq.proof_report,
    mov_movntdqa.proof_report,
    mov_movnti.proof_report,
    mov_movntpd.proof_report,
    mov_movntps.proof_report,
    mov_movntq.proof_report,
    mov_movq.proof_report,
    mov_movq2dq.proof_report,
    mov_movs.proof_report,
    mov_movsb.proof_report,
    mov_movsd.proof_report,
    mov_movshdup.proof_report,
    mov_movsldup.proof_report,
    mov_movsq.proof_report,
    mov_movss.proof_report,
    mov_movsw.proof_report,
    mov_movsx.proof_report,
    mov_movsxd.proof_report,
    mov_movupd.proof_report,
    mov_movups.proof_report,
    mov_movzx.proof_report,
    mov_vmovapd.proof_report,
    mov_vmovaps.proof_report,
    mov_vmovd.proof_report,
    mov_vmovddup.proof_report,
    mov_vmovdqa.proof_report,
    mov_vmovdqa32.proof_report,
    mov_vmovdqa64.proof_report,
    mov_vmovdqu.proof_report,
    mov_vmovdqu16.proof_report,
    mov_vmovdqu32.proof_report,
    mov_vmovdqu64.proof_report,
    mov_vmovdqu8.proof_report,
    mov_vmovhlps.proof_report,
    mov_vmovhpd.proof_report,
    mov_vmovhps.proof_report,
    mov_vmovlhps.proof_report,
    mov_vmovlpd.proof_report,
    mov_vmovlps.proof_report,
    mov_vmovmskpd.proof_report,
    mov_vmovmskps.proof_report,
    mov_vmovntdq.proof_report,
    mov_vmovntdqa.proof_report,
    mov_vmovntpd.proof_report,
    mov_vmovntps.proof_report,
    mov_vmovq.proof_report,
    mov_vmovsd.proof_report,
    mov_vmovshdup.proof_report,
    mov_vmovsldup.proof_report,
    mov_vmovss.proof_report,
    mov_vmovupd.proof_report,
    mov_vmovups.proof_report,
    mul_imul.proof_report,
    mul_mul.proof_report,
    mul_mulpd.proof_report,
    mul_mulps.proof_report,
    mul_mulsd.proof_report,
    mul_mulss.proof_report,
    mul_mulx.proof_report,
    or_or.proof_report,
    or_orpd.proof_report,
    or_orps.proof_report,
    output_out.proof_report,
    output_outs.proof_report,
    output_outsb.proof_report,
    output_outsw.proof_report,
    output_outsd.proof_report,
    pop_pop.proof_report,
    pop_popa.proof_report,
    pop_popad.proof_report,
    pop_popcnt.proof_report,
    push_push.proof_report,
    push_pusha.proof_report,
    push_pushad.proof_report,
    push_pushf.proof_report,
    push_pushfd.proof_report,
    push_pushfq.proof_report,
    restore_frstore.proof_report,
    restore_fxrstore.proof_report,
    restore_rstore_ssp.proof_report,
    restore_xrstore.proof_report,
    restore_xrstors.proof_report,
    rotate_rcl.proof_report,
    rotate_rcr.proof_report,
    rotate_rol.proof_report,
    rotate_ror.proof_report,
    rotate_rorx.proof_report,
    rotate_vprold.proof_report,
    rotate_vprolvd.proof_report,
    rotate_vprolq.proof_report,
    rotate_vprolvq.proof_report,
    rotate_vprord.proof_report,
    rotate_vprorvd.proof_report,
    rotate_vprorq.proof_report,
    rotate_vprorvq.proof_report,
    save_fsave.proof_report,
    save_fxsave.proof_report,
    save_saveprevssp.proof_report,
    swap_swapgs.proof_report,
    sub_sub.proof_report,
    sub_subpd.proof_report,
    sub_subps.proof_report,
    sub_subsd.proof_report,
    sub_subss.proof_report,
    test_test.proof_report,
    test_testui.proof_report,
    undef_ud0.proof_report,
    undef_ud1.proof_report,
    undef_ud2.proof_report,
    unordered_ucomisd.proof_report,
    unordered_ucomiss.proof_report,
    unordered_vucomish.proof_report,
    variable_vpsllvw.proof_report,
    variable_vpsllvd.proof_report,
    variable_vpsllvq.proof_report,
    variable_vpsravw.proof_report,
    variable_vpsravd.proof_report,
    variable_vpsravq.proof_report,
    variable_vpsrlvw.proof_report,
    variable_vpsrlvd.proof_report,
    variable_vpsrlvq.proof_report,
    verify_verr.proof_report,
    verify_verw.proof_report,
    vptestm_vptestmb.proof_report,
    vptestm_vptestmw.proof_report,
    vptestm_vptestmd.proof_report,
    vptestm_vptestmq.proof_report,
    xor_xor.proof_report,
    xor_xorpd.proof_report,
    xor_xorps.proof_report,
    and_and.proof_report,
    and_andn.proof_report,
    and_andps.proof_report,
    and_andpd.proof_report,
    and_andnps.proof_report,
    and_andnpd.proof_report,
    blend_blendpd.proof_report,
    blend_blendps.proof_report,
    blend_blendvpd.proof_report,
    blend_blendvps.proof_report,
    blend_pblendvb.proof_report,
    blend_pblendw.proof_report,
    blend_vblendmpd.proof_report,
    blend_vblendmps.proof_report,
    blend_vpblendd.proof_report,
    blend_vpblendmb.proof_report,
    blend_vpblendmw.proof_report,
    blend_vpblendmd.proof_report,
    blend_vpblendmq.proof_report,
    bls_blsi.proof_report,
    bls_blsmsk.proof_report,
    bls_blsr.proof_report,
    bs_bsf.proof_report,
    bs_bsr.proof_report,
    bs_bswap.proof_report,
    bt_bt.proof_report,
    bt_btc.proof_report,
    bt_btr.proof_report,
    bt_bts.proof_report,
    cache_cldemote.proof_report,
    cache_clflush.proof_report,
    cache_clflushopt.proof_report,
    cache_clwb.proof_report,
    cpu_cpuid.proof_report,
    sha_sha1msg1.proof_report,
    sha_sha1msg2.proof_report,
    sha_sha1nexte.proof_report,
    sha_sha1rnds4.proof_report,
    sha_sha256msg1.proof_report,
    sha_sha256msg2.proof_report,
    sha_sha256rnds2.proof_report,
    shadow_incssp.proof_report,
    terminate_endbr32.proof_report,
    terminate_endbr64.proof_report,
    sys_syscall.proof_report,
    sys_sysenter.proof_report,
    sys_sysexit.proof_report,
    sys_sysret.proof_report,
    shuffle_shufpd.proof_report,
    shuffle_shufps.proof_report,
    shuffle_vpshufbitqmb.proof_report,
    shuffle_vshuff32x4.proof_report,
    shuffle_vshuff64x2.proof_report,
    shuffle_vshufi32x4.proof_report,
    shuffle_vshufi64x2.proof_report,
    shift_sal.proof_report,
    shift_sar.proof_report,
    shift_shl.proof_report,
    shift_shr.proof_report,
    shift_shld.proof_report,
    shift_shrd.proof_report,
    shift_sarx.proof_report,
    shift_shlx.proof_report,
    shift_shrx.proof_report,
    clear_clac.proof_report,
    clear_clc.proof_report,
    clear_cld.proof_report,
    clear_cli.proof_report,
    clear_clrssbsy.proof_report,
    clear_clts.proof_report,
    clear_clui.proof_report,
    clear_fclex.proof_report,
    dot_dppd.proof_report,
    dot_dpps.proof_report,
    dot_tdpbf16ps.proof_report,
    dot_tdpbssd.proof_report,
    dot_tdpbsud.proof_report,
    dot_tdpbusd.proof_report,
    dot_tdpbuud.proof_report,
    dot_vdpbf16ps.proof_report,
    bound_bound.proof_report,
    bound_bndcl.proof_report,
    bound_bndcu.proof_report,
    bound_bndcn.proof_report,
    bound_bndldx.proof_report,
    bound_bndmk.proof_report,
    bound_bndmov.proof_report,
    bound_bndstx.proof_report,
    x87_fcom.proof_report,
    x87_fcomp.proof_report,
    x87_fcompp.proof_report,
    x87_fcomi.proof_report,
    x87_fcomip.proof_report,
    x87_fucomi.proof_report,
    x87_fucomip.proof_report,
    x87_ficom.proof_report,
    x87_ficomp.proof_report,
    x87_fucom.proof_report,
    x87_fucomp.proof_report,
    x87_fucompp.proof_report,
    aes_aesdec.proof_report,
    aes_aesdec128kl.proof_report,
    aes_aesdec256kl.proof_report,
    aes_aesdeclast.proof_report,
    aes_aesdecwide128kl.proof_report,
    aes_aesdecwide256kl.proof_report,
    aes_aesenc.proof_report,
    aes_aesenc128kl.proof_report,
    aes_aesenc256kl.proof_report,
    aes_aesenclast.proof_report,
    aes_aesencwide128kl.proof_report,
    aes_aesencwide256kl.proof_report,
    aes_aesimc.proof_report,
    aes_aeskeygenassist.proof_report,
    min_max_pmaxsb.proof_report,
    min_max_pmaxsw.proof_report,
    min_max_pmaxsd.proof_report,
    min_max_pmaxsq.proof_report,
    min_max_pmaxub.proof_report,
    min_max_pmaxuw.proof_report,
    min_max_pmaxud.proof_report,
    min_max_pmaxuq.proof_report,
    min_max_pminsb.proof_report,
    min_max_pminsw.proof_report,
    min_max_pminsd.proof_report,
    min_max_pminsq.proof_report,
    min_max_pminub.proof_report,
    min_max_pminuw.proof_report,
    min_max_pminud.proof_report,
    min_max_pminuq.proof_report,
    set_monitor.proof_report,
    set_umonitor.proof_report,
    set_stac.proof_report,
    set_stc.proof_report,
    set_std.proof_report,
    set_sti.proof_report,
    set_stui.proof_report,
    set_xsetbv.proof_report,
    set_seta.proof_report,
    set_setae.proof_report,
    set_setb.proof_report,
    set_setbe.proof_report,
    set_setc.proof_report,
    set_sete.proof_report,
    set_setg.proof_report,
    set_setge.proof_report,
    set_setl.proof_report,
    set_setle.proof_report,
    set_setna.proof_report,
    set_setnae.proof_report,
    set_setnb.proof_report,
    set_setnbe.proof_report,
    set_setnc.proof_report,
    set_setne.proof_report,
    set_setng.proof_report,
    set_setnge.proof_report,
    set_setnl.proof_report,
    set_setnle.proof_report,
    set_setno.proof_report,
    set_setnp.proof_report,
    set_setns.proof_report,
    set_setnz.proof_report,
    set_seto.proof_report,
    set_setp.proof_report,
    set_setpe.proof_report,
    set_setpo.proof_report,
    set_sets.proof_report,
    set_setz.proof_report,
    count_lzcnt.proof_report,
    count_tzcnt.proof_report,
    count_vplzcntd.proof_report,
    count_vplzcntq.proof_report,
    exchange_fxch.proof_report,
    exchange_xadd.proof_report,
    exchange_xchg.proof_report,
    nop_fnop.proof_report,
    nop_nop.proof_report,
    not_not.proof_report,
    not_knotw.proof_report,
    not_knotb.proof_report,
    not_knotq.proof_report,
    not_knotd.proof_report,
    andnot_pandn.proof_report,
    andnot_vpandn.proof_report,
    andnot_vpandnd.proof_report,
    andnot_vpandnq.proof_report,
    andnot_kandnw.proof_report,
    andnot_kandnb.proof_report,
    andnot_kandnq.proof_report,
    andnot_kandnd.proof_report,
    bitposition_bzhi.proof_report,
    change_fchs.proof_report,
    complement_cmc.proof_report,
    decimal_daa.proof_report,
    decimal_das.proof_report,
    dep_pdep.proof_report,
    detect_vpconflictd.proof_report,
    detect_vpconflictq.proof_report,
    empty_emms.proof_report,
    end_xend.proof_report,
    examine_fxam.proof_report,
    expand_vpexpandb.proof_report,
    expand_vpexpandw.proof_report,
    free_ffree.proof_report,
    pand_pand.proof_report,
    pand_vpand.proof_report,
    pand_vpandd.proof_report,
    pand_vpandq.proof_report,
    partial_fpatan.proof_report,
    partial_fprem.proof_report,
    partial_fprem1.proof_report,
    partial_fptan.proof_report,
    pause_tpause.proof_report,
    platform_pconfig.proof_report,
    prefetch_prefetchw.proof_report,
    prefetch_prefetcht0.proof_report,
    prefetch_prefetcht1.proof_report,
    prefetch_prefetcht2.proof_report,
    prefetch_prefetchnta.proof_report,
    pxor_pxor.proof_report,
    pxor_vpxor.proof_report,
    pxor_vpxord.proof_report,
    pxor_vpxorq.proof_report,
    release_tilerelease.proof_report,
    reset_hreset.proof_report,
    resume_rsm.proof_report,
    rpl_arpl.proof_report,
    select_vpmultishiftqb.proof_report,
    send_senduipi.proof_report,
    serialize_serialize.proof_report,
    enqueue_enqcmd.proof_report,
    extr_bextr.proof_report,
    extr_extractps.proof_report,
    extr_fxtract.proof_report,
    extr_pext.proof_report,
    lock_lock.proof_report,
    lock_xacquire.proof_report,
    lock_xrelease.proof_report,
    logical_nand_vptestnmb.proof_report,
    logical_nand_vptestnmw.proof_report,
    logical_nand_vptestnmd.proof_report,
    logical_nand_vptestnmq.proof_report,
    logical_or_korw.proof_report,
    logical_or_korb.proof_report,
    logical_or_korq.proof_report,
    logical_or_kord.proof_report,
    logical_or_por.proof_report,
    logical_or_vpor.proof_report,
    logical_or_vpord.proof_report,
    logical_or_vporq.proof_report,
    logical_xnor_kxnorw.proof_report,
    logical_xnor_kxnorb.proof_report,
    logical_xnor_kxnorq.proof_report,
    logical_xnor_kxnord.proof_report,
    neg_neg.proof_report,
    round_frndint.proof_report,
    encode_encodekey128.proof_report,
    galois_gf2p8affineinvqb.proof_report,
    galois_gf2p8affineqb.proof_report,
    galois_gf2p8mulb.proof_report,
    inc_dec_fdecstp.proof_report,
    inc_dec_fincstp.proof_report,
    initialize_finit.proof_report,
    initialize_fninit.proof_report,
    invalidate_invd.proof_report,
    invalidate_invlpg.proof_report,
    invalidate_invpcid.proof_report,
    make_enter.proof_report,
    repeat_rep.proof_report,
    repeat_repe.proof_report,
    repeat_repne.proof_report,
    scatter_vpscatterdd.proof_report,
    scatter_vpscatterdq.proof_report,
    scatter_vpscatterqd.proof_report,
    scatter_vpscatterqq.proof_report,
    scatter_vscatterdps.proof_report,
    scatter_vscatterdpd.proof_report,
    scatter_vscatterqps.proof_report,
    scatter_vscatterqpd.proof_report,
    gather_vgatherdpd.proof_report,
    gather_vgatherqpd.proof_report,
    gather_vgatherdps.proof_report,
    gather_vgatherqps.proof_report,
    gather_vpgatherdd.proof_report,
    gather_vpgatherdq.proof_report,
    gather_vpgatherqd.proof_report,
    gather_vpgatherqq.proof_report,
    get_xgetbv.proof_report,
    square_root_fsqrt.proof_report,
    square_root_sqrtpd.proof_report,
    square_root_sqrtps.proof_report,
    table_xlat.proof_report,
    table_xlatb.proof_report,
    trig_fcos.proof_report,
    trig_fsin.proof_report,
    trig_fsincos.proof_report,
    wait_wait.proof_report,
    wait_mwait.proof_report,
    write_ptwrite.proof_report,
    write_wbinvd.proof_report,
    write_wbnoinvd.proof_report,
    write_wrfsbase.proof_report,
    write_wrgsbase.proof_report,
    write_wrmsr.proof_report,
    write_wrpkru.proof_report,
    absolute_fabs.proof_report,
    absolute_pabsb.proof_report,
    absolute_pabsd.proof_report,
    absolute_pabsq.proof_report,
    absolute_pabsw.proof_report,
    absolute_vdbpsadbw.proof_report,
    accumulate_crc32.proof_report,
    reverse_fdivr.proof_report,
    reverse_fdivrp.proof_report,
    reverse_fidivr.proof_report,
    reverse_fsubr.proof_report,
    reverse_fsubrp.proof_report,
    reverse_fisubr.proof_report,
    scan_scas.proof_report,
    scan_scasb.proof_report,
    scan_scasw.proof_report,
    scan_scasd.proof_report,
    scan_scasq.proof_report,
    compute_f2xm1.proof_report,
    compute_fyl2x.proof_report,
    compute_fyl2xp1.proof_report,
    compute_psadbw.proof_report,
    compute_mpsadbw.proof_report,
    compute_rcpps.proof_report,
    compute_rcpss.proof_report,
    compute_rsqrtps.proof_report,
    compute_rsqrtss.proof_report,
    compute_sqrtsd.proof_report,
    compute_sqrtss.proof_report,
    compute_vp2intersect.proof_report,
    zero_tilezero.proof_report,
    zero_vzeroall.proof_report,
    zero_vzeroupper.proof_report,
};

pub fn tableCount() usize {
    return specs.len;
}

pub fn proofReportCount() usize {
    return proof_reports.len;
}

pub fn proofCaseCount() usize {
    var count: usize = 0;
    for (proof_reports) |report| count += report.caseCount();
    return count;
}

pub fn findByPath(path: []const u8) ?core.InstructionMathSpec {
    for (specs) |instruction_spec| {
        if (std.mem.eql(u8, instruction_spec.meta.path, path)) return instruction_spec;
    }
    return null;
}

pub fn validateAll() void {
    for (specs) |instruction_spec| validateSpec(instruction_spec);
}

pub fn exerciseAll() !void {
    for (specs) |instruction_spec| try core.exerciseSpec(instruction_spec);
    try verifyProofsAll();
}

pub fn verifyProofsAll() !void {
    for (proof_reports) |report| try proofs.verifyReport(report);
}

fn spec(meta: core.InstructionMathMeta) core.InstructionMathSpec {
    return core.specFromMeta(meta);
}

fn validateSpec(instruction_spec: core.InstructionMathSpec) void {
    runtime_abi.isa.validateMathSpec(.{
        .target_isa = @tagName(instruction_spec.meta.target_isa),
        .instruction_name = instruction_spec.meta.name,
        .path = instruction_spec.meta.path,
        .source_table_path = instruction_spec.meta.source_table_path,
        .operation = @tagName(instruction_spec.meta.operation),
        .register_model = @tagName(instruction_spec.meta.register_model),
        .flag_model = @tagName(instruction_spec.meta.flag_model),
        .edge_case_count = instruction_spec.edgeCaseCount(),
        .validates_registers = instruction_spec.validatesRegisters(),
        .validates_flags = instruction_spec.validatesFlags(),
        .validates_overflow = instruction_spec.validatesOverflow(),
        .validates_traps = instruction_spec.validatesTraps(),
    });
}

test "x86 math specs cover current ISA tables" {
    try std.testing.expectEqual(@as(usize, 580), tableCount());
    try std.testing.expectEqual(tableCount(), proofReportCount());
    try std.testing.expect(proofCaseCount() >= tableCount() * 2);
    validateAll();
    try exerciseAll();
}
