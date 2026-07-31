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
const cmp_pcmpeqb = @import("CMP/PCMPEQB.zig");
const cmp_pcmpeqw = @import("CMP/PCMPEQW.zig");
const cmp_pcmpeqd = @import("CMP/PCMPEQD.zig");
const cmp_pcmpeqq = @import("CMP/PCMPEQQ.zig");
const cmp_pcmpgtb = @import("CMP/PCMPGTB.zig");
const cmp_pcmpgtw = @import("CMP/PCMPGTW.zig");
const cmp_pcmpgtd = @import("CMP/PCMPGTD.zig");
const cmp_pcmpgtq = @import("CMP/PCMPGTQ.zig");
const cmp_vcmpph = @import("CMP/VCMPPH.zig");
const cmp_vcmpsh = @import("CMP/VCMPSH.zig");
const cmp_vcomish = @import("CMP/VCOMISH.zig");
const cmp_vpcmpb = @import("CMP/VPCMPB.zig");
const cmp_vpcmpub = @import("CMP/VPCMPUB.zig");
const cmp_vpcmpd = @import("CMP/VPCMPD.zig");
const cmp_vpcmpud = @import("CMP/VPCMPUD.zig");
const cmp_vpcmpq = @import("CMP/VPCMPQ.zig");
const cmp_vpcmpuq = @import("CMP/VPCMPUQ.zig");
const cmp_vpcmpw = @import("CMP/VPCMPW.zig");
const cmp_vpcmpuw = @import("CMP/VPCMPUW.zig");
const div_div = @import("DIV/DIV.zig");
const div_divpd = @import("DIV/DIVPD.zig");
const div_divps = @import("DIV/DIVPS.zig");
const div_divsd = @import("DIV/DIVSD.zig");
const div_divss = @import("DIV/DIVSS.zig");
const div_idiv = @import("DIV/IDIV.zig");
const div_fdiv = @import("DIV/fdiv.zig");
const div_fdivp = @import("DIV/fdivp.zig");
const div_fidiv = @import("DIV/fidiv.zig");
const div_vdivph = @import("DIV/VDIVPH.zig");
const div_vdivsh = @import("DIV/VDIVSH.zig");
const down_convert_vpmovdb = @import("DOWN_CONVERT/VPMOVDB.zig");
const down_convert_vpmovsdb = @import("DOWN_CONVERT/VPMOVSDB.zig");
const down_convert_vpmovusdb = @import("DOWN_CONVERT/VPMOVUSDB.zig");
const down_convert_vpmovdw = @import("DOWN_CONVERT/VPMOVDW.zig");
const down_convert_vpmovsdw = @import("DOWN_CONVERT/VPMOVSDW.zig");
const down_convert_vpmovusdw = @import("DOWN_CONVERT/VPMOVUSDW.zig");
const down_convert_vpmovqb = @import("DOWN_CONVERT/VPMOVQB.zig");
const down_convert_vpmovsqb = @import("DOWN_CONVERT/VPMOVSQB.zig");
const down_convert_vpmovusqb = @import("DOWN_CONVERT/VPMOVUSQB.zig");
const down_convert_vpmovqd = @import("DOWN_CONVERT/VPMOVQD.zig");
const down_convert_vpmovsqd = @import("DOWN_CONVERT/VPMOVSQD.zig");
const down_convert_vpmovusqd = @import("DOWN_CONVERT/VPMOVUSQD.zig");
const down_convert_vpmovqw = @import("DOWN_CONVERT/VPMOVQW.zig");
const down_convert_vpmovsqw = @import("DOWN_CONVERT/VPMOVSQW.zig");
const down_convert_vpmovusqw = @import("DOWN_CONVERT/VPMOVUSQW.zig");
const down_convert_vpmovwb = @import("DOWN_CONVERT/VPMOVWB.zig");
const down_convert_vpmovswb = @import("DOWN_CONVERT/VPMOVSWB.zig");
const down_convert_vpmovuswb = @import("DOWN_CONVERT/VPMOVUSWB.zig");
const fix_up_vfixupimmpd = @import("FIX_UP/VFIXUPIMMPD.zig");
const fix_up_vfixupimmps = @import("FIX_UP/VFIXUPIMMPS.zig");
const fix_up_vfixupimmsd = @import("FIX_UP/VFIXUPIMMSD.zig");
const fix_up_vfixupimmss = @import("FIX_UP/VFIXUPIMMSS.zig");
const full_permute_vpermI2b = @import("FULL_PERMUTE/VPERMI2B.zig");
const full_permute_vpermI2d = @import("FULL_PERMUTE/VPERMI2D.zig");
const full_permute_vpermI2pd = @import("FULL_PERMUTE/VPERMI2PD.zig");
const full_permute_vpermI2ps = @import("FULL_PERMUTE/VPERMI2PS.zig");
const full_permute_vpermI2q = @import("FULL_PERMUTE/VPERMI2Q.zig");
const full_permute_vpermI2w = @import("FULL_PERMUTE/VPERMI2W.zig");
const full_permute_vpermt2b = @import("FULL_PERMUTE/VPERMT2B.zig");
const full_permute_vpermt2d = @import("FULL_PERMUTE/VPERMT2D.zig");
const full_permute_vpermt2pd = @import("FULL_PERMUTE/VPERMT2PD.zig");
const full_permute_vpermt2ps = @import("FULL_PERMUTE/VPERMT2PS.zig");
const full_permute_vpermt2q = @import("FULL_PERMUTE/VPERMT2Q.zig");
const full_permute_vpermt2w = @import("FULL_PERMUTE/VPERMT2W.zig");
const fused_vfmadd132pd = @import("FUSED/VFMADD132PD.zig");
const fused_vfmadd132ph = @import("FUSED/VFMADD132PH.zig");
const fused_vfmadd132ps = @import("FUSED/VFMADD132PS.zig");
const fused_vfmadd132sd = @import("FUSED/VFMADD132SD.zig");
const fused_vfmadd132sh = @import("FUSED/VFMADD132SH.zig");
const fused_vfmadd132ss = @import("FUSED/VFMADD132SS.zig");
const fused_vfmadd213pd = @import("FUSED/VFMADD213PD.zig");
const fused_vfmadd213ph = @import("FUSED/VFMADD213PH.zig");
const fused_vfmadd213ps = @import("FUSED/VFMADD213PS.zig");
const fused_vfmadd213sd = @import("FUSED/VFMADD213SD.zig");
const fused_vfmadd213sh = @import("FUSED/VFMADD213SH.zig");
const fused_vfmadd213ss = @import("FUSED/VFMADD213SS.zig");
const fused_vfmadd231pd = @import("FUSED/VFMADD231PD.zig");
const fused_vfmadd231ph = @import("FUSED/VFMADD231PH.zig");
const fused_vfmadd231ps = @import("FUSED/VFMADD231PS.zig");
const fused_vfmadd231sd = @import("FUSED/VFMADD231SD.zig");
const fused_vfmadd231sh = @import("FUSED/VFMADD231SH.zig");
const fused_vfmadd231ss = @import("FUSED/VFMADD231SS.zig");
const fused_vfmaddrnd231pd = @import("FUSED/VFMADDRND231PD.zig");
const fused_vfmaddsub132pd = @import("FUSED/VFMADDSUB132PD.zig");
const fused_vfmaddsub132ph = @import("FUSED/VFMADDSUB132PH.zig");
const fused_vfmaddsub132ps = @import("FUSED/VFMADDSUB132PS.zig");
const fused_vfmaddsub213pd = @import("FUSED/VFMADDSUB213PD.zig");
const fused_vfmaddsub213ph = @import("FUSED/VFMADDSUB213PH.zig");
const fused_vfmaddsub213ps = @import("FUSED/VFMADDSUB213PS.zig");
const fused_vfmaddsub231pd = @import("FUSED/VFMADDSUB231PD.zig");
const fused_vfmaddsub231ph = @import("FUSED/VFMADDSUB231PH.zig");
const fused_vfmaddsub231ps = @import("FUSED/VFMADDSUB231PS.zig");
const fused_vfmsub132pd = @import("FUSED/VFMSUB132PD.zig");
const fused_vfmsub132ph = @import("FUSED/VFMSUB132PH.zig");
const fused_vfmsub132ps = @import("FUSED/VFMSUB132PS.zig");
const fused_vfmsub132sd = @import("FUSED/VFMSUB132SD.zig");
const fused_vfmsub132sh = @import("FUSED/VFMSUB132SH.zig");
const fused_vfmsub132ss = @import("FUSED/VFMSUB132SS.zig");
const fused_vfmsub213pd = @import("FUSED/VFMSUB213PD.zig");
const fused_vfmsub213ph = @import("FUSED/VFMSUB213PH.zig");
const fused_vfmsub213ps = @import("FUSED/VFMSUB213PS.zig");
const fused_vfmsub213sd = @import("FUSED/VFMSUB213SD.zig");
const fused_vfmsub213sh = @import("FUSED/VFMSUB213SH.zig");
const fused_vfmsub213ss = @import("FUSED/VFMSUB213SS.zig");
const fused_vfmsub231pd = @import("FUSED/VFMSUB231PD.zig");
const fused_vfmsub231ph = @import("FUSED/VFMSUB231PH.zig");
const fused_vfmsub231ps = @import("FUSED/VFMSUB231PS.zig");
const fused_vfmsub231sd = @import("FUSED/VFMSUB231SD.zig");
const fused_vfmsub231sh = @import("FUSED/VFMSUB231SH.zig");
const fused_vfmsub231ss = @import("FUSED/VFMSUB231SS.zig");
const fused_vfmsubadd132pd = @import("FUSED/VFMSUBADD132PD.zig");
const fused_vfmsubadd132ph = @import("FUSED/VFMSUBADD132PH.zig");
const fused_vfmsubadd132ps = @import("FUSED/VFMSUBADD132PS.zig");
const fused_vfmsubadd213pd = @import("FUSED/VFMSUBADD213PD.zig");
const fused_vfmsubadd213ph = @import("FUSED/VFMSUBADD213PH.zig");
const fused_vfmsubadd213ps = @import("FUSED/VFMSUBADD213PS.zig");
const fused_vfmsubadd231pd = @import("FUSED/VFMSUBADD231PD.zig");
const fused_vfmsubadd231ph = @import("FUSED/VFMSUBADD231PH.zig");
const fused_vfmsubadd231ps = @import("FUSED/VFMSUBADD231PS.zig");
const fused_vfnmadd132pd = @import("FUSED/VFNMADD132PD.zig");
const fused_vfnmadd132ph = @import("FUSED/VFNMADD132PH.zig");
const fused_vfnmadd132ps = @import("FUSED/VFNMADD132PS.zig");
const fused_vfnmadd132sd = @import("FUSED/VFNMADD132SD.zig");
const fused_vfnmadd132sh = @import("FUSED/VFNMADD132SH.zig");
const fused_vfnmadd132ss = @import("FUSED/VFNMADD132SS.zig");
const fused_vfnmadd213pd = @import("FUSED/VFNMADD213PD.zig");
const fused_vfnmadd213ph = @import("FUSED/VFNMADD213PH.zig");
const fused_vfnmadd213ps = @import("FUSED/VFNMADD213PS.zig");
const fused_vfnmadd213sd = @import("FUSED/VFNMADD213SD.zig");
const fused_vfnmadd213sh = @import("FUSED/VFNMADD213SH.zig");
const fused_vfnmadd213ss = @import("FUSED/VFNMADD213SS.zig");
const fused_vfnmadd231pd = @import("FUSED/VFNMADD231PD.zig");
const fused_vfnmadd231ph = @import("FUSED/VFNMADD231PH.zig");
const fused_vfnmadd231ps = @import("FUSED/VFNMADD231PS.zig");
const fused_vfnmadd231sd = @import("FUSED/VFNMADD231SD.zig");
const fused_vfnmadd231sh = @import("FUSED/VFNMADD231SH.zig");
const fused_vfnmadd231ss = @import("FUSED/VFNMADD231SS.zig");
const fused_vfnmsub132pd = @import("FUSED/VFNMSUB132PD.zig");
const fused_vfnmsub132ph = @import("FUSED/VFNMSUB132PH.zig");
const fused_vfnmsub132ps = @import("FUSED/VFNMSUB132PS.zig");
const fused_vfnmsub132sd = @import("FUSED/VFNMSUB132SD.zig");
const fused_vfnmsub132sh = @import("FUSED/VFNMSUB132SH.zig");
const fused_vfnmsub132ss = @import("FUSED/VFNMSUB132SS.zig");
const fused_vfnmsub213pd = @import("FUSED/VFNMSUB213PD.zig");
const fused_vfnmsub213ph = @import("FUSED/VFNMSUB213PH.zig");
const fused_vfnmsub213ps = @import("FUSED/VFNMSUB213PS.zig");
const fused_vfnmsub213sd = @import("FUSED/VFNMSUB213SD.zig");
const fused_vfnmsub213sh = @import("FUSED/VFNMSUB213SH.zig");
const fused_vfnmsub213ss = @import("FUSED/VFNMSUB213SS.zig");
const fused_vfnmsub231pd = @import("FUSED/VFNMSUB231PD.zig");
const fused_vfnmsub231ph = @import("FUSED/VFNMSUB231PH.zig");
const fused_vfnmsub231ps = @import("FUSED/VFNMSUB231PS.zig");
const fused_vfnmsub231sd = @import("FUSED/VFNMSUB231SD.zig");
const fused_vfnmsub231sh = @import("FUSED/VFNMSUB231SH.zig");
const fused_vfnmsub231ss = @import("FUSED/VFNMSUB231SS.zig");
const inc_dec_dec = @import("INC-DEC/DEC.zig");
const inc_dec_inc = @import("INC-DEC/INC.zig");
const input_in = @import("INPUT/IN.zig");
const input_ins = @import("INPUT/INS.zig");
const input_insb = @import("INPUT/INSB.zig");
const input_insw = @import("INPUT/INSW.zig");
const input_insd = @import("INPUT/INSD.zig");
const insert_insertps = @import("INSERT/INSERTPS.zig");
const insert_pinsrb = @import("INSERT/PINSRB.zig");
const insert_pinsrd = @import("INSERT/PINSRD.zig");
const insert_pinsrq = @import("INSERT/PINSRQ.zig");
const insert_pinsrw = @import("INSERT/PINSRW.zig");
const insert_vinsertf128 = @import("INSERT/VINSERTF128.zig");
const insert_vinsertf32x4 = @import("INSERT/VINSERTF32X4.zig");
const insert_vinsertf64x2 = @import("INSERT/VINSERTF64X2.zig");
const insert_vinsertf32x8 = @import("INSERT/VINSERTF32X8.zig");
const insert_vinsertf64x4 = @import("INSERT/VINSERTF64X4.zig");
const insert_vinserti128 = @import("INSERT/VINSERTI128.zig");
const insert_vinserti32x4 = @import("INSERT/VINSERTI32X4.zig");
const insert_vinserti64x2 = @import("INSERT/VINSERTI64X2.zig");
const insert_vinserti32x8 = @import("INSERT/VINSERTI32X8.zig");
const insert_vinserti64x4 = @import("INSERT/VINSERTI64X4.zig");
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
const mov_kmovw = @import("MOV/KMOVW.zig");
const mov_kmovb = @import("MOV/KMOVB.zig");
const mov_kmovq = @import("MOV/KMOVQ.zig");
const mov_kmovd = @import("MOV/KMOVD.zig");
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
const mov_pmovmskb = @import("MOV/PMOVMSKB.zig");
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
const mov_vmovsh = @import("MOV/VMOVSH.zig");
const mov_vmovshdup = @import("MOV/VMOVSHDUP.zig");
const mov_vmovsldup = @import("MOV/VMOVSLDUP.zig");
const mov_vmovss = @import("MOV/VMOVSS.zig");
const mov_vmovupd = @import("MOV/VMOVUPD.zig");
const mov_vmovups = @import("MOV/VMOVUPS.zig");
const mov_vmovw = @import("MOV/VMOVW.zig");
const mul_imul = @import("MUL/IMUL.zig");
const mul_mul = @import("MUL/MUL.zig");
const mul_mulpd = @import("MUL/MULPD.zig");
const mul_mulps = @import("MUL/MULPS.zig");
const mul_mulsd = @import("MUL/MULSD.zig");
const mul_mulss = @import("MUL/MULSS.zig");
const mul_mulx = @import("MUL/MULX.zig");
const mul_fmul = @import("MUL/FMUL.zig");
const mul_fmulp = @import("MUL/FMULP.zig");
const mul_fimul = @import("MUL/FIMUL.zig");
const mul_pclmulqdq = @import("MUL/PCLMULQDQ.zig");
const mul_pmaddubsw = @import("MUL/PMADDUBSW.zig");
const mul_pmaddwd = @import("MUL/PMADDWD.zig");
const mul_pmulhrsw = @import("MUL/PMULHRSW.zig");
const mul_pmulhuw = @import("MUL/PMULHUW.zig");
const mul_pmulhw = @import("MUL/PMULHW.zig");
const mul_pmulld = @import("MUL/PMULLD.zig");
const mul_pmullq = @import("MUL/PMULLQ.zig");
const mul_pmullw = @import("MUL/PMULLW.zig");
const mul_pmuludq = @import("MUL/PMULUDQ.zig");
const mul_vfcmulcph = @import("MUL/VFCMULCPH.zig");
const mul_vfmulcph = @import("MUL/VFMULCPH.zig");
const mul_vfcmulcsh = @import("MUL/VFCMULCSH.zig");
const mul_vfmulcsh = @import("MUL/VFMULCSH.zig");
const mul_vmulph = @import("MUL/VMULPH.zig");
const mul_vmulsh = @import("MUL/VMULSH.zig");
const mul_vpdpbusd = @import("MUL/VPDPBUSD.zig");
const mul_vpdpbusds = @import("MUL/VPDPBUSDS.zig");
const mul_vpdpwssd = @import("MUL/VPDPWSSD.zig");
const mul_vpdpwssds = @import("MUL/VPDPWSSDS.zig");
const mul_vpmadd52huq = @import("MUL/VPMADD52HUQ.zig");
const mul_vpmadd52luq = @import("MUL/VPMADD52LUQ.zig");
const or_or = @import("OR/OR.zig");
const or_orpd = @import("OR/ORPD.zig");
const or_orps = @import("OR/ORPS.zig");
const output_out = @import("OUTPUT/OUT.zig");
const output_outs = @import("OUTPUT/OUTS.zig");
const output_outsb = @import("OUTPUT/OUTSB.zig");
const output_outsw = @import("OUTPUT/OUTSW.zig");
const output_outsd = @import("OUTPUT/OUTSD.zig");
const pack_packssdw = @import("PACK/PACKSSDW.zig");
const pack_packsswb = @import("PACK/PACKSSWB.zig");
const pack_packusdw = @import("PACK/PACKUSDW.zig");
const pack_packuswb = @import("PACK/PACKUSWB.zig");
const pack_palignr = @import("PACK/PALIGNR.zig");
const pack_pcmpestri = @import("PACK/PCMPESTRI.zig");
const pack_pcmpestrm = @import("PACK/PCMPESTRM.zig");
const pack_pcmpistri = @import("PACK/PCMPISTRI.zig");
const pack_pcmpistrm = @import("PACK/PCMPISTRM.zig");
const pack_phminposuw = @import("PACK/PHMINPOSUW.zig");
const pack_pmovsxbd = @import("PACK/PMOVSXBD.zig");
const pack_pmovsxbq = @import("PACK/PMOVSXBQ.zig");
const pack_pmovsxbw = @import("PACK/PMOVSXBW.zig");
const pack_pmovsxdq = @import("PACK/PMOVSXDQ.zig");
const pack_pmovsxwd = @import("PACK/PMOVSXWD.zig");
const pack_pmovsxwq = @import("PACK/PMOVSXWQ.zig");
const pack_pmovzxbd = @import("PACK/PMOVZXBD.zig");
const pack_pmovzxbq = @import("PACK/PMOVZXBQ.zig");
const pack_pmovzxbw = @import("PACK/PMOVZXBW.zig");
const pack_pmovzxdq = @import("PACK/PMOVZXDQ.zig");
const pack_pmovzxwd = @import("PACK/PMOVZXWD.zig");
const pack_pmovzxwq = @import("PACK/PMOVZXWQ.zig");
const pack_pmuldq = @import("PACK/PMULDQ.zig");
const pack_pshufb = @import("PACK/PSHUFB.zig");
const pack_psignb = @import("PACK/PSIGNB.zig");
const pack_psignd = @import("PACK/PSIGND.zig");
const pack_psignw = @import("PACK/PSIGNW.zig");
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
const scale_fscale = @import("SCALE/FSCALE.zig");
const scale_vscalefpd = @import("SCALE/VSCALEFPD.zig");
const scale_vscalefph = @import("SCALE/VSCALEFPH.zig");
const scale_vscalefps = @import("SCALE/VSCALEFPS.zig");
const scale_vscalefsd = @import("SCALE/VSCALEFSD.zig");
const scale_vscalefsh = @import("SCALE/VSCALEFSH.zig");
const scale_vscalefss = @import("SCALE/VSCALEFSS.zig");
const swap_swapgs = @import("SWAP/SWAPGS.zig");
const sub_sub = @import("SUB/SUB.zig");
const sub_subpd = @import("SUB/SUBPD.zig");
const sub_subps = @import("SUB/SUBPS.zig");
const sub_subsd = @import("SUB/SUBSD.zig");
const sub_subss = @import("SUB/SUBSS.zig");
const sub_fsub = @import("SUB/FSUB.zig");
const sub_fsubp = @import("SUB/FSUBP.zig");
const sub_fisub = @import("SUB/FISUB.zig");
const sub_hsubpd = @import("SUB/HSUBPD.zig");
const sub_hsubps = @import("SUB/HSUBPS.zig");
const sub_phsubw = @import("SUB/PHSUBW.zig");
const sub_phsubd = @import("SUB/PHSUBD.zig");
const sub_phsubsw = @import("SUB/PHSUBSW.zig");
const sub_psubb = @import("SUB/PSUBB.zig");
const sub_psubw = @import("SUB/PSUBW.zig");
const sub_psubd = @import("SUB/PSUBD.zig");
const sub_psubq = @import("SUB/PSUBQ.zig");
const sub_psubsb = @import("SUB/PSUBSB.zig");
const sub_psubsw = @import("SUB/PSUBSW.zig");
const sub_psubusb = @import("SUB/PSUBUSB.zig");
const sub_psubusw = @import("SUB/PSUBUSW.zig");
const sub_sbb = @import("SUB/SBB.zig");
const sub_vsubph = @import("SUB/VSUBPH.zig");
const sub_vsubsh = @import("SUB/VSUBSH.zig");
const test_test = @import("TEST/TEST.zig");
const test_testui = @import("TEST/TESTUI.zig");
const test_ftst = @import("TEST/FTST.zig");
const test_ktestw = @import("TEST/KTESTW.zig");
const test_ktestb = @import("TEST/KTESTB.zig");
const test_ktestq = @import("TEST/KTESTQ.zig");
const test_ktestd = @import("TEST/KTESTD.zig");
const test_ptest = @import("TEST/PTEST.zig");
const test_vfpclasspd = @import("TEST/VFPCLASSPD.zig");
const test_vfpclassph = @import("TEST/VFPCLASSPH.zig");
const test_vfpclassps = @import("TEST/VFPCLASSPS.zig");
const test_vfpclasssd = @import("TEST/VFPCLASSSD.zig");
const test_vfpclasssh = @import("TEST/VFPCLASSSH.zig");
const test_vfpclassss = @import("TEST/VFPCLASSSS.zig");
const test_vtestpd = @import("TEST/VTESTPD.zig");
const test_vtestps = @import("TEST/VTESTPS.zig");
const test_xtest = @import("TEST/XTEST.zig");
const unpack_kunpckbw = @import("UNPACK/KUNPCKBW.zig");
const unpack_kunpckwd = @import("UNPACK/KUNPCKWD.zig");
const unpack_kunpckdq = @import("UNPACK/KUNPCKDQ.zig");
const unpack_punpckhbw = @import("UNPACK/PUNPCKHBW.zig");
const unpack_punpckhwd = @import("UNPACK/PUNPCKHWD.zig");
const unpack_punpckhdq = @import("UNPACK/PUNPCKHDQ.zig");
const unpack_punpckhqdq = @import("UNPACK/PUNPCKHQDQ.zig");
const unpack_punpcklbw = @import("UNPACK/PUNPCKLBW.zig");
const unpack_punpcklwd = @import("UNPACK/PUNPCKLWD.zig");
const unpack_punpckldq = @import("UNPACK/PUNPCKLDQ.zig");
const unpack_punpcklqdq = @import("UNPACK/PUNPCKLQDQ.zig");
const unpack_unpckhpd = @import("UNPACK/UNPCKHPD.zig");
const unpack_unpckhps = @import("UNPACK/UNPCKHPS.zig");
const unpack_unpcklpd = @import("UNPACK/UNPCKLPD.zig");
const unpack_unpcklps = @import("UNPACK/UNPCKLPS.zig");
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
const shuffle_vpunpckldq = @import("SHUFFLE/VPUNPCKLDQ.zig");
const shuffle_vpermilpd = @import("SHUFFLE/VPERMILPD.zig");
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
const shift_kshiftlb = @import("SHIFT/KSHIFTLB.zig");
const shift_kshiftld = @import("SHIFT/KSHIFTLD.zig");
const shift_kshiftlq = @import("SHIFT/KSHIFTLQ.zig");
const shift_kshiftlw = @import("SHIFT/KSHIFTLW.zig");
const shift_kshiftrb = @import("SHIFT/KSHIFTRB.zig");
const shift_kshiftrd = @import("SHIFT/KSHIFTRD.zig");
const shift_kshiftrq = @import("SHIFT/KSHIFTRQ.zig");
const shift_kshiftrw = @import("SHIFT/KSHIFTRW.zig");
const shift_pslld = @import("SHIFT/PSLLD.zig");
const shift_pslldq = @import("SHIFT/PSLLDQ.zig");
const shift_psllq = @import("SHIFT/PSLLQ.zig");
const shift_psllw = @import("SHIFT/PSLLW.zig");
const shift_psraq = @import("SHIFT/PSRAQ.zig");
const shift_psrad = @import("SHIFT/PSRAD.zig");
const shift_psraw = @import("SHIFT/PSRAW.zig");
const shift_psrld = @import("SHIFT/PSRLD.zig");
const shift_psrldq = @import("SHIFT/PSRLDQ.zig");
const shift_psrlq = @import("SHIFT/PSRLQ.zig");
const shift_psrlw = @import("SHIFT/PSRLW.zig");
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
const min_max_maxpd = @import("MIN-MAX/MAXPD.zig");
const min_max_maxps = @import("MIN-MAX/MAXPS.zig");
const min_max_minpd = @import("MIN-MAX/MINPD.zig");
const min_max_minps = @import("MIN-MAX/MINPS.zig");
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
const perform_vreducepd = @import("PERFORM/VREDUCEPD.zig");
const perform_vreduceph = @import("PERFORM/VREDUCEPH.zig");
const perform_vreduceps = @import("PERFORM/VREDUCEPS.zig");
const perform_vreducesd = @import("PERFORM/VREDUCESD.zig");
const perform_vreducesh = @import("PERFORM/VREDUCESH.zig");
const perform_vreducess = @import("PERFORM/VREDUCESS.zig");
const permute_vperm2f128 = @import("PERMUTE/VPERM2F128.zig");
const permute_vperm2i128 = @import("PERMUTE/VPERM2I128.zig");
const permute_vpermb = @import("PERMUTE/VPERMB.zig");
const permute_vpermd = @import("PERMUTE/VPERMD.zig");
const permute_vpermw = @import("PERMUTE/VPERMW.zig");
const permute_vpermilpd = @import("PERMUTE/VPERMILPD.zig");
const permute_vpermilps = @import("PERMUTE/VPERMILPS.zig");
const permute_vpermpd = @import("PERMUTE/VPERMPD.zig");
const permute_vpermps = @import("PERMUTE/VPERMPS.zig");
const permute_vpermq = @import("PERMUTE/VPERMQ.zig");
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
const range_vrangepd = @import("RANGE/VRANGEPD.zig");
const range_vrangeps = @import("RANGE/VRANGEPS.zig");
const range_vrangesd = @import("RANGE/VRANGESD.zig");
const range_vrangess = @import("RANGE/VRANGESS.zig");
const read_rdfsbase = @import("READ/RDFSBASE.zig");
const read_rdgsbase = @import("READ/RDGSBASE.zig");
const read_rdmsr = @import("READ/RDMSR.zig");
const read_rdpid = @import("READ/RDPID.zig");
const read_rdpkru = @import("READ/RDPKRU.zig");
const read_rdpmc = @import("READ/RDPMC.zig");
const read_rdrand = @import("READ/RDRAND.zig");
const read_rdseed = @import("READ/RDSEED.zig");
const read_rdtsc = @import("READ/RDTSC.zig");
const read_rdtscp = @import("READ/RDTSCP.zig");
const release_tilerelease = @import("RELEASE/TILERELEASE.zig");
const reset_hreset = @import("RESET/HRESET.zig");
const resume_rsm = @import("RESUME/RSM.zig");
const ret_maxsd = @import("RET/MAXSD.zig");
const ret_maxss = @import("RET/MAXSS.zig");
const ret_minsd = @import("RET/MINSD.zig");
const ret_minss = @import("RET/MINSS.zig");
const ret_vmaxph = @import("RET/VMAXPH.zig");
const ret_vmaxsh = @import("RET/VMAXSH.zig");
const ret_vminph = @import("RET/VMINPH.zig");
const ret_vminsh = @import("RET/VMINSH.zig");
const ret_vpopcntb = @import("RET/VPOPCNTB.zig");
const ret_vpopcntw = @import("RET/VPOPCNTW.zig");
const ret_vpopcntd = @import("RET/VPOPCNTD.zig");
const ret_vpopcntq = @import("RET/VPOPCNTQ.zig");
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
const store_fbstp = @import("STORE/FBSTP.zig");
const store_fist = @import("STORE/FIST.zig");
const store_fistp = @import("STORE/FISTP.zig");
const store_fisttp = @import("STORE/FISTTP.zig");
const store_fst = @import("STORE/FST.zig");
const store_fstcw = @import("STORE/FSTCW.zig");
const store_fstenv = @import("STORE/FSTENV.zig");
const store_fstp = @import("STORE/FSTP.zig");
const store_fstsw = @import("STORE/FSTSW.zig");
const store_maskmovdqu = @import("STORE/MASKMOVDQU.zig");
const store_maskmovq = @import("STORE/MASKMOVQ.zig");
const store_sahf = @import("STORE/SAHF.zig");
const store_sfence = @import("STORE/SFENCE.zig");
const store_sgdt = @import("STORE/SGDT.zig");
const store_sldt = @import("STORE/SLDT.zig");
const store_smsw = @import("STORE/SMSW.zig");
const store_stmxcsr = @import("STORE/STMXCSR.zig");
const store_stos = @import("STORE/STOS.zig");
const store_str = @import("STORE/STR.zig");
const store_sttilecfg = @import("STORE/STTILECFG.zig");
const store_tilestored = @import("STORE/TILESTORED.zig");
const store_vcompresspd = @import("STORE/VCOMPRESSPD.zig");
const store_vcompressps = @import("STORE/VCOMPRESSPS.zig");
const store_vpcompressb = @import("STORE/VPCOMPRESSB.zig");
const store_vpcompressd = @import("STORE/VPCOMPRESSD.zig");
const store_vpcompressq = @import("STORE/VPCOMPRESSQ.zig");
const store_vpcompressw = @import("STORE/VPCOMPRESSW.zig");

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

const arithmetic_vpaddb = @import("ARITHMETIC/vpaddb.zig");
const arithmetic_vpaddd = @import("ARITHMETIC/vpaddd.zig");
const arithmetic_vpaddq = @import("ARITHMETIC/vpaddq.zig");
const arithmetic_vpaddw = @import("ARITHMETIC/vpaddw.zig");
const atomic_cmpxchg = @import("ATOMIC/cmpxchg.zig");
const atomic_cmpxchg8b = @import("ATOMIC/cmpxchg8b.zig");
const atomic_cmpxchg16b = @import("ATOMIC/cmpxchg16b.zig");
const horizontal_vphaddd = @import("HORIZONTAL/vphaddd.zig");
const horizontal_vphaddsw = @import("HORIZONTAL/vphaddsw.zig");
const horizontal_vphaddw = @import("HORIZONTAL/vphaddw.zig");
const insert_extract_vpextrb = @import("INSERT_EXTRACT/vpextrb.zig");
const insert_extract_vpextrd = @import("INSERT_EXTRACT/vpextrd.zig");
const insert_extract_vpextrq = @import("INSERT_EXTRACT/vpextrq.zig");
const insert_extract_vpextrw = @import("INSERT_EXTRACT/vpextrw.zig");
const insert_extract_vextractf128 = @import("INSERT_EXTRACT/vextractf128.zig");
const round_vroundpd = @import("ROUND/vroundpd.zig");
const round_vroundps = @import("ROUND/vroundps.zig");
const round_vroundsd = @import("ROUND/vroundsd.zig");
const round_vroundss = @import("ROUND/vroundss.zig");
const shuffle_vpshufd = @import("SHUFFLE/vpshufd.zig");
const unordered_vucomiss = @import("UNORDERED/vucomiss.zig");

pub const mirror_tables = blk: {
    @setEvalBranchQuota(5000);
    break :blk [_]MirrorTable{
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
        mirror(add_fadd.family, add_fadd.path, add_fadd.source),
        mirror(add_faddp.family, add_faddp.path, add_faddp.source),
        mirror(add_fiadd.family, add_fiadd.path, add_fiadd.source),
        mirror(add_haddpd.family, add_haddpd.path, add_haddpd.source),
        mirror(add_haddps.family, add_haddps.path, add_haddps.source),
        mirror(add_kaddb.family, add_kaddb.path, add_kaddb.source),
        mirror(add_kaddd.family, add_kaddd.path, add_kaddd.source),
        mirror(add_kaddq.family, add_kaddq.path, add_kaddq.source),
        mirror(add_kaddw.family, add_kaddw.path, add_kaddw.source),
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
        mirror(cmp_pcmpeqb.family, cmp_pcmpeqb.path, cmp_pcmpeqb.source),
        mirror(cmp_pcmpeqw.family, cmp_pcmpeqw.path, cmp_pcmpeqw.source),
        mirror(cmp_pcmpeqd.family, cmp_pcmpeqd.path, cmp_pcmpeqd.source),
        mirror(cmp_pcmpeqq.family, cmp_pcmpeqq.path, cmp_pcmpeqq.source),
        mirror(cmp_pcmpgtb.family, cmp_pcmpgtb.path, cmp_pcmpgtb.source),
        mirror(cmp_pcmpgtw.family, cmp_pcmpgtw.path, cmp_pcmpgtw.source),
        mirror(cmp_pcmpgtd.family, cmp_pcmpgtd.path, cmp_pcmpgtd.source),
        mirror(cmp_pcmpgtq.family, cmp_pcmpgtq.path, cmp_pcmpgtq.source),
        mirror(cmp_vcmpph.family, cmp_vcmpph.path, cmp_vcmpph.source),
        mirror(cmp_vcmpsh.family, cmp_vcmpsh.path, cmp_vcmpsh.source),
        mirror(cmp_vcomish.family, cmp_vcomish.path, cmp_vcomish.source),
        mirror(cmp_vpcmpb.family, cmp_vpcmpb.path, cmp_vpcmpb.source),
        mirror(cmp_vpcmpub.family, cmp_vpcmpub.path, cmp_vpcmpub.source),
        mirror(cmp_vpcmpd.family, cmp_vpcmpd.path, cmp_vpcmpd.source),
        mirror(cmp_vpcmpud.family, cmp_vpcmpud.path, cmp_vpcmpud.source),
        mirror(cmp_vpcmpq.family, cmp_vpcmpq.path, cmp_vpcmpq.source),
        mirror(cmp_vpcmpuq.family, cmp_vpcmpuq.path, cmp_vpcmpuq.source),
        mirror(cmp_vpcmpw.family, cmp_vpcmpw.path, cmp_vpcmpw.source),
        mirror(cmp_vpcmpuw.family, cmp_vpcmpuw.path, cmp_vpcmpuw.source),
        mirror(div_div.family, div_div.path, div_div.source),
        mirror(div_divpd.family, div_divpd.path, div_divpd.source),
        mirror(div_divps.family, div_divps.path, div_divps.source),
        mirror(div_divsd.family, div_divsd.path, div_divsd.source),
        mirror(div_divss.family, div_divss.path, div_divss.source),
        mirror(div_idiv.family, div_idiv.path, div_idiv.source),
        mirror(div_fdiv.family, div_fdiv.path, div_fdiv.source),
        mirror(div_fdivp.family, div_fdivp.path, div_fdivp.source),
        mirror(div_fidiv.family, div_fidiv.path, div_fidiv.source),
        mirror(div_vdivph.family, div_vdivph.path, div_vdivph.source),
        mirror(div_vdivsh.family, div_vdivsh.path, div_vdivsh.source),
        mirror(down_convert_vpmovdb.family, down_convert_vpmovdb.path, down_convert_vpmovdb.source),
        mirror(down_convert_vpmovsdb.family, down_convert_vpmovsdb.path, down_convert_vpmovsdb.source),
        mirror(down_convert_vpmovusdb.family, down_convert_vpmovusdb.path, down_convert_vpmovusdb.source),
        mirror(down_convert_vpmovdw.family, down_convert_vpmovdw.path, down_convert_vpmovdw.source),
        mirror(down_convert_vpmovsdw.family, down_convert_vpmovsdw.path, down_convert_vpmovsdw.source),
        mirror(down_convert_vpmovusdw.family, down_convert_vpmovusdw.path, down_convert_vpmovusdw.source),
        mirror(down_convert_vpmovqb.family, down_convert_vpmovqb.path, down_convert_vpmovqb.source),
        mirror(down_convert_vpmovsqb.family, down_convert_vpmovsqb.path, down_convert_vpmovsqb.source),
        mirror(down_convert_vpmovusqb.family, down_convert_vpmovusqb.path, down_convert_vpmovusqb.source),
        mirror(down_convert_vpmovqd.family, down_convert_vpmovqd.path, down_convert_vpmovqd.source),
        mirror(down_convert_vpmovsqd.family, down_convert_vpmovsqd.path, down_convert_vpmovsqd.source),
        mirror(down_convert_vpmovusqd.family, down_convert_vpmovusqd.path, down_convert_vpmovusqd.source),
        mirror(down_convert_vpmovqw.family, down_convert_vpmovqw.path, down_convert_vpmovqw.source),
        mirror(down_convert_vpmovsqw.family, down_convert_vpmovsqw.path, down_convert_vpmovsqw.source),
        mirror(down_convert_vpmovusqw.family, down_convert_vpmovusqw.path, down_convert_vpmovusqw.source),
        mirror(down_convert_vpmovwb.family, down_convert_vpmovwb.path, down_convert_vpmovwb.source),
        mirror(down_convert_vpmovswb.family, down_convert_vpmovswb.path, down_convert_vpmovswb.source),
        mirror(down_convert_vpmovuswb.family, down_convert_vpmovuswb.path, down_convert_vpmovuswb.source),
        mirror(fix_up_vfixupimmpd.family, fix_up_vfixupimmpd.path, fix_up_vfixupimmpd.source),
        mirror(fix_up_vfixupimmps.family, fix_up_vfixupimmps.path, fix_up_vfixupimmps.source),
        mirror(fix_up_vfixupimmsd.family, fix_up_vfixupimmsd.path, fix_up_vfixupimmsd.source),
        mirror(fix_up_vfixupimmss.family, fix_up_vfixupimmss.path, fix_up_vfixupimmss.source),
        mirror(full_permute_vpermI2b.family, full_permute_vpermI2b.path, full_permute_vpermI2b.source),
        mirror(full_permute_vpermI2d.family, full_permute_vpermI2d.path, full_permute_vpermI2d.source),
        mirror(full_permute_vpermI2pd.family, full_permute_vpermI2pd.path, full_permute_vpermI2pd.source),
        mirror(full_permute_vpermI2ps.family, full_permute_vpermI2ps.path, full_permute_vpermI2ps.source),
        mirror(full_permute_vpermI2q.family, full_permute_vpermI2q.path, full_permute_vpermI2q.source),
        mirror(full_permute_vpermI2w.family, full_permute_vpermI2w.path, full_permute_vpermI2w.source),
        mirror(full_permute_vpermt2b.family, full_permute_vpermt2b.path, full_permute_vpermt2b.source),
        mirror(full_permute_vpermt2d.family, full_permute_vpermt2d.path, full_permute_vpermt2d.source),
        mirror(full_permute_vpermt2pd.family, full_permute_vpermt2pd.path, full_permute_vpermt2pd.source),
        mirror(full_permute_vpermt2ps.family, full_permute_vpermt2ps.path, full_permute_vpermt2ps.source),
        mirror(full_permute_vpermt2q.family, full_permute_vpermt2q.path, full_permute_vpermt2q.source),
        mirror(full_permute_vpermt2w.family, full_permute_vpermt2w.path, full_permute_vpermt2w.source),
        mirror(fused_vfmadd132pd.family, fused_vfmadd132pd.path, fused_vfmadd132pd.source),
        mirror(fused_vfmadd132ph.family, fused_vfmadd132ph.path, fused_vfmadd132ph.source),
        mirror(fused_vfmadd132ps.family, fused_vfmadd132ps.path, fused_vfmadd132ps.source),
        mirror(fused_vfmadd132sd.family, fused_vfmadd132sd.path, fused_vfmadd132sd.source),
        mirror(fused_vfmadd132sh.family, fused_vfmadd132sh.path, fused_vfmadd132sh.source),
        mirror(fused_vfmadd132ss.family, fused_vfmadd132ss.path, fused_vfmadd132ss.source),
        mirror(fused_vfmadd213pd.family, fused_vfmadd213pd.path, fused_vfmadd213pd.source),
        mirror(fused_vfmadd213ph.family, fused_vfmadd213ph.path, fused_vfmadd213ph.source),
        mirror(fused_vfmadd213ps.family, fused_vfmadd213ps.path, fused_vfmadd213ps.source),
        mirror(fused_vfmadd213sd.family, fused_vfmadd213sd.path, fused_vfmadd213sd.source),
        mirror(fused_vfmadd213sh.family, fused_vfmadd213sh.path, fused_vfmadd213sh.source),
        mirror(fused_vfmadd213ss.family, fused_vfmadd213ss.path, fused_vfmadd213ss.source),
        mirror(fused_vfmadd231pd.family, fused_vfmadd231pd.path, fused_vfmadd231pd.source),
        mirror(fused_vfmadd231ph.family, fused_vfmadd231ph.path, fused_vfmadd231ph.source),
        mirror(fused_vfmadd231ps.family, fused_vfmadd231ps.path, fused_vfmadd231ps.source),
        mirror(fused_vfmadd231sd.family, fused_vfmadd231sd.path, fused_vfmadd231sd.source),
        mirror(fused_vfmadd231sh.family, fused_vfmadd231sh.path, fused_vfmadd231sh.source),
        mirror(fused_vfmadd231ss.family, fused_vfmadd231ss.path, fused_vfmadd231ss.source),
        mirror(fused_vfmaddrnd231pd.family, fused_vfmaddrnd231pd.path, fused_vfmaddrnd231pd.source),
        mirror(fused_vfmaddsub132pd.family, fused_vfmaddsub132pd.path, fused_vfmaddsub132pd.source),
        mirror(fused_vfmaddsub132ph.family, fused_vfmaddsub132ph.path, fused_vfmaddsub132ph.source),
        mirror(fused_vfmaddsub132ps.family, fused_vfmaddsub132ps.path, fused_vfmaddsub132ps.source),
        mirror(fused_vfmaddsub213pd.family, fused_vfmaddsub213pd.path, fused_vfmaddsub213pd.source),
        mirror(fused_vfmaddsub213ph.family, fused_vfmaddsub213ph.path, fused_vfmaddsub213ph.source),
        mirror(fused_vfmaddsub213ps.family, fused_vfmaddsub213ps.path, fused_vfmaddsub213ps.source),
        mirror(fused_vfmaddsub231pd.family, fused_vfmaddsub231pd.path, fused_vfmaddsub231pd.source),
        mirror(fused_vfmaddsub231ph.family, fused_vfmaddsub231ph.path, fused_vfmaddsub231ph.source),
        mirror(fused_vfmaddsub231ps.family, fused_vfmaddsub231ps.path, fused_vfmaddsub231ps.source),
        mirror(fused_vfmsub132pd.family, fused_vfmsub132pd.path, fused_vfmsub132pd.source),
        mirror(fused_vfmsub132ph.family, fused_vfmsub132ph.path, fused_vfmsub132ph.source),
        mirror(fused_vfmsub132ps.family, fused_vfmsub132ps.path, fused_vfmsub132ps.source),
        mirror(fused_vfmsub132sd.family, fused_vfmsub132sd.path, fused_vfmsub132sd.source),
        mirror(fused_vfmsub132sh.family, fused_vfmsub132sh.path, fused_vfmsub132sh.source),
        mirror(fused_vfmsub132ss.family, fused_vfmsub132ss.path, fused_vfmsub132ss.source),
        mirror(fused_vfmsub213pd.family, fused_vfmsub213pd.path, fused_vfmsub213pd.source),
        mirror(fused_vfmsub213ph.family, fused_vfmsub213ph.path, fused_vfmsub213ph.source),
        mirror(fused_vfmsub213ps.family, fused_vfmsub213ps.path, fused_vfmsub213ps.source),
        mirror(fused_vfmsub213sd.family, fused_vfmsub213sd.path, fused_vfmsub213sd.source),
        mirror(fused_vfmsub213sh.family, fused_vfmsub213sh.path, fused_vfmsub213sh.source),
        mirror(fused_vfmsub213ss.family, fused_vfmsub213ss.path, fused_vfmsub213ss.source),
        mirror(fused_vfmsub231pd.family, fused_vfmsub231pd.path, fused_vfmsub231pd.source),
        mirror(fused_vfmsub231ph.family, fused_vfmsub231ph.path, fused_vfmsub231ph.source),
        mirror(fused_vfmsub231ps.family, fused_vfmsub231ps.path, fused_vfmsub231ps.source),
        mirror(fused_vfmsub231sd.family, fused_vfmsub231sd.path, fused_vfmsub231sd.source),
        mirror(fused_vfmsub231sh.family, fused_vfmsub231sh.path, fused_vfmsub231sh.source),
        mirror(fused_vfmsub231ss.family, fused_vfmsub231ss.path, fused_vfmsub231ss.source),
        mirror(fused_vfmsubadd132pd.family, fused_vfmsubadd132pd.path, fused_vfmsubadd132pd.source),
        mirror(fused_vfmsubadd132ph.family, fused_vfmsubadd132ph.path, fused_vfmsubadd132ph.source),
        mirror(fused_vfmsubadd132ps.family, fused_vfmsubadd132ps.path, fused_vfmsubadd132ps.source),
        mirror(fused_vfmsubadd213pd.family, fused_vfmsubadd213pd.path, fused_vfmsubadd213pd.source),
        mirror(fused_vfmsubadd213ph.family, fused_vfmsubadd213ph.path, fused_vfmsubadd213ph.source),
        mirror(fused_vfmsubadd213ps.family, fused_vfmsubadd213ps.path, fused_vfmsubadd213ps.source),
        mirror(fused_vfmsubadd231pd.family, fused_vfmsubadd231pd.path, fused_vfmsubadd231pd.source),
        mirror(fused_vfmsubadd231ph.family, fused_vfmsubadd231ph.path, fused_vfmsubadd231ph.source),
        mirror(fused_vfmsubadd231ps.family, fused_vfmsubadd231ps.path, fused_vfmsubadd231ps.source),
        mirror(fused_vfnmadd132pd.family, fused_vfnmadd132pd.path, fused_vfnmadd132pd.source),
        mirror(fused_vfnmadd132ph.family, fused_vfnmadd132ph.path, fused_vfnmadd132ph.source),
        mirror(fused_vfnmadd132ps.family, fused_vfnmadd132ps.path, fused_vfnmadd132ps.source),
        mirror(fused_vfnmadd132sd.family, fused_vfnmadd132sd.path, fused_vfnmadd132sd.source),
        mirror(fused_vfnmadd132sh.family, fused_vfnmadd132sh.path, fused_vfnmadd132sh.source),
        mirror(fused_vfnmadd132ss.family, fused_vfnmadd132ss.path, fused_vfnmadd132ss.source),
        mirror(fused_vfnmadd213pd.family, fused_vfnmadd213pd.path, fused_vfnmadd213pd.source),
        mirror(fused_vfnmadd213ph.family, fused_vfnmadd213ph.path, fused_vfnmadd213ph.source),
        mirror(fused_vfnmadd213ps.family, fused_vfnmadd213ps.path, fused_vfnmadd213ps.source),
        mirror(fused_vfnmadd213sd.family, fused_vfnmadd213sd.path, fused_vfnmadd213sd.source),
        mirror(fused_vfnmadd213sh.family, fused_vfnmadd213sh.path, fused_vfnmadd213sh.source),
        mirror(fused_vfnmadd213ss.family, fused_vfnmadd213ss.path, fused_vfnmadd213ss.source),
        mirror(fused_vfnmadd231pd.family, fused_vfnmadd231pd.path, fused_vfnmadd231pd.source),
        mirror(fused_vfnmadd231ph.family, fused_vfnmadd231ph.path, fused_vfnmadd231ph.source),
        mirror(fused_vfnmadd231ps.family, fused_vfnmadd231ps.path, fused_vfnmadd231ps.source),
        mirror(fused_vfnmadd231sd.family, fused_vfnmadd231sd.path, fused_vfnmadd231sd.source),
        mirror(fused_vfnmadd231sh.family, fused_vfnmadd231sh.path, fused_vfnmadd231sh.source),
        mirror(fused_vfnmadd231ss.family, fused_vfnmadd231ss.path, fused_vfnmadd231ss.source),
        mirror(fused_vfnmsub132pd.family, fused_vfnmsub132pd.path, fused_vfnmsub132pd.source),
        mirror(fused_vfnmsub132ph.family, fused_vfnmsub132ph.path, fused_vfnmsub132ph.source),
        mirror(fused_vfnmsub132ps.family, fused_vfnmsub132ps.path, fused_vfnmsub132ps.source),
        mirror(fused_vfnmsub132sd.family, fused_vfnmsub132sd.path, fused_vfnmsub132sd.source),
        mirror(fused_vfnmsub132sh.family, fused_vfnmsub132sh.path, fused_vfnmsub132sh.source),
        mirror(fused_vfnmsub132ss.family, fused_vfnmsub132ss.path, fused_vfnmsub132ss.source),
        mirror(fused_vfnmsub213pd.family, fused_vfnmsub213pd.path, fused_vfnmsub213pd.source),
        mirror(fused_vfnmsub213ph.family, fused_vfnmsub213ph.path, fused_vfnmsub213ph.source),
        mirror(fused_vfnmsub213ps.family, fused_vfnmsub213ps.path, fused_vfnmsub213ps.source),
        mirror(fused_vfnmsub213sd.family, fused_vfnmsub213sd.path, fused_vfnmsub213sd.source),
        mirror(fused_vfnmsub213sh.family, fused_vfnmsub213sh.path, fused_vfnmsub213sh.source),
        mirror(fused_vfnmsub213ss.family, fused_vfnmsub213ss.path, fused_vfnmsub213ss.source),
        mirror(fused_vfnmsub231pd.family, fused_vfnmsub231pd.path, fused_vfnmsub231pd.source),
        mirror(fused_vfnmsub231ph.family, fused_vfnmsub231ph.path, fused_vfnmsub231ph.source),
        mirror(fused_vfnmsub231ps.family, fused_vfnmsub231ps.path, fused_vfnmsub231ps.source),
        mirror(fused_vfnmsub231sd.family, fused_vfnmsub231sd.path, fused_vfnmsub231sd.source),
        mirror(fused_vfnmsub231sh.family, fused_vfnmsub231sh.path, fused_vfnmsub231sh.source),
        mirror(fused_vfnmsub231ss.family, fused_vfnmsub231ss.path, fused_vfnmsub231ss.source),
        mirror(inc_dec_dec.family, inc_dec_dec.path, inc_dec_dec.source),
        mirror(inc_dec_inc.family, inc_dec_inc.path, inc_dec_inc.source),
        mirror(input_in.family, input_in.path, input_in.source),
        mirror(input_ins.family, input_ins.path, input_ins.source),
        mirror(input_insb.family, input_insb.path, input_insb.source),
        mirror(input_insw.family, input_insw.path, input_insw.source),
        mirror(input_insd.family, input_insd.path, input_insd.source),
        mirror(insert_insertps.family, insert_insertps.path, insert_insertps.source),
        mirror(insert_pinsrb.family, insert_pinsrb.path, insert_pinsrb.source),
        mirror(insert_pinsrd.family, insert_pinsrd.path, insert_pinsrd.source),
        mirror(insert_pinsrq.family, insert_pinsrq.path, insert_pinsrq.source),
        mirror(insert_pinsrw.family, insert_pinsrw.path, insert_pinsrw.source),
        mirror(insert_vinsertf128.family, insert_vinsertf128.path, insert_vinsertf128.source),
        mirror(insert_vinsertf32x4.family, insert_vinsertf32x4.path, insert_vinsertf32x4.source),
        mirror(insert_vinsertf64x2.family, insert_vinsertf64x2.path, insert_vinsertf64x2.source),
        mirror(insert_vinsertf32x8.family, insert_vinsertf32x8.path, insert_vinsertf32x8.source),
        mirror(insert_vinsertf64x4.family, insert_vinsertf64x4.path, insert_vinsertf64x4.source),
        mirror(insert_vinserti128.family, insert_vinserti128.path, insert_vinserti128.source),
        mirror(insert_vinserti32x4.family, insert_vinserti32x4.path, insert_vinserti32x4.source),
        mirror(insert_vinserti64x2.family, insert_vinserti64x2.path, insert_vinserti64x2.source),
        mirror(insert_vinserti32x8.family, insert_vinserti32x8.path, insert_vinserti32x8.source),
        mirror(insert_vinserti64x4.family, insert_vinserti64x4.path, insert_vinserti64x4.source),
        mirror(interrupt_int.family, interrupt_int.path, interrupt_int.source),
        mirror(interrupt_int1.family, interrupt_int1.path, interrupt_int1.source),
        mirror(interrupt_int3.family, interrupt_int3.path, interrupt_int3.source),
        mirror(interrupt_into.family, interrupt_into.path, interrupt_into.source),
        mirror(interrupt_iret.family, interrupt_iret.path, interrupt_iret.source),
        mirror(interrupt_sidt.family, interrupt_sidt.path, interrupt_sidt.source),
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
        mirror(kand_kandw.family, kand_kandw.path, kand_kandw.source),
        mirror(kand_kandb.family, kand_kandb.path, kand_kandb.source),
        mirror(kand_kandq.family, kand_kandq.path, kand_kandq.source),
        mirror(kand_kandd.family, kand_kandd.path, kand_kandd.source),
        mirror(kortest_kortestw.family, kortest_kortestw.path, kortest_kortestw.source),
        mirror(kortest_kortestb.family, kortest_kortestb.path, kortest_kortestb.source),
        mirror(kortest_kortestq.family, kortest_kortestq.path, kortest_kortestq.source),
        mirror(kortest_kortestd.family, kortest_kortestd.path, kortest_kortestd.source),
        mirror(kxor_kxorw.family, kxor_kxorw.path, kxor_kxorw.source),
        mirror(kxor_kxorb.family, kxor_kxorb.path, kxor_kxorb.source),
        mirror(kxor_kxorq.family, kxor_kxorq.path, kxor_kxorq.source),
        mirror(kxor_kxord.family, kxor_kxord.path, kxor_kxord.source),
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
        mirror(align_valignd.family, align_valignd.path, align_valignd.source),
        mirror(align_valignq.family, align_valignq.path, align_valignq.source),
        mirror(average_pavgb.family, average_pavgb.path, average_pavgb.source),
        mirror(average_pavgw.family, average_pavgw.path, average_pavgw.source),
        mirror(begin_xbegin.family, begin_xbegin.path, begin_xbegin.source),
        mirror(bitwise_vpternlogd.family, bitwise_vpternlogd.path, bitwise_vpternlogd.source),
        mirror(bitwise_vpternlogq.family, bitwise_vpternlogq.path, bitwise_vpternlogq.source),
        mirror(broadcast_vpbroadcastmb2q.family, broadcast_vpbroadcastmb2q.path, broadcast_vpbroadcastmb2q.source),
        mirror(broadcast_vpbroadcastmw2d.family, broadcast_vpbroadcastmw2d.path, broadcast_vpbroadcastmw2d.source),
        mirror(concatenate_vpshldd.family, concatenate_vpshldd.path, concatenate_vpshldd.source),
        mirror(concatenate_vpshldq.family, concatenate_vpshldq.path, concatenate_vpshldq.source),
        mirror(concatenate_vpshldvd.family, concatenate_vpshldvd.path, concatenate_vpshldvd.source),
        mirror(concatenate_vpshldvq.family, concatenate_vpshldvq.path, concatenate_vpshldvq.source),
        mirror(concatenate_vpshldvw.family, concatenate_vpshldvw.path, concatenate_vpshldvw.source),
        mirror(concatenate_vpshldw.family, concatenate_vpshldw.path, concatenate_vpshldw.source),
        mirror(concatenate_vpshrdd.family, concatenate_vpshrdd.path, concatenate_vpshrdd.source),
        mirror(concatenate_vpshrdq.family, concatenate_vpshrdq.path, concatenate_vpshrdq.source),
        mirror(concatenate_vpshrdvd.family, concatenate_vpshrdvd.path, concatenate_vpshrdvd.source),
        mirror(concatenate_vpshrdvq.family, concatenate_vpshrdvq.path, concatenate_vpshrdvq.source),
        mirror(concatenate_vpshrdvw.family, concatenate_vpshrdvw.path, concatenate_vpshrdvw.source),
        mirror(concatenate_vpshrdw.family, concatenate_vpshrdw.path, concatenate_vpshrdw.source),
        mirror(conditional_cmova.family, conditional_cmova.path, conditional_cmova.source),
        mirror(conditional_cmovae.family, conditional_cmovae.path, conditional_cmovae.source),
        mirror(conditional_cmovb.family, conditional_cmovb.path, conditional_cmovb.source),
        mirror(conditional_cmovbe.family, conditional_cmovbe.path, conditional_cmovbe.source),
        mirror(conditional_cmovc.family, conditional_cmovc.path, conditional_cmovc.source),
        mirror(conditional_cmove.family, conditional_cmove.path, conditional_cmove.source),
        mirror(conditional_cmovg.family, conditional_cmovg.path, conditional_cmovg.source),
        mirror(conditional_cmovge.family, conditional_cmovge.path, conditional_cmovge.source),
        mirror(conditional_cmovl.family, conditional_cmovl.path, conditional_cmovl.source),
        mirror(conditional_cmovle.family, conditional_cmovle.path, conditional_cmovle.source),
        mirror(conditional_cmovna.family, conditional_cmovna.path, conditional_cmovna.source),
        mirror(conditional_cmovnae.family, conditional_cmovnae.path, conditional_cmovnae.source),
        mirror(conditional_cmovnb.family, conditional_cmovnb.path, conditional_cmovnb.source),
        mirror(conditional_cmovnbe.family, conditional_cmovnbe.path, conditional_cmovnbe.source),
        mirror(conditional_cmovnc.family, conditional_cmovnc.path, conditional_cmovnc.source),
        mirror(conditional_cmovne.family, conditional_cmovne.path, conditional_cmovne.source),
        mirror(conditional_cmovng.family, conditional_cmovng.path, conditional_cmovng.source),
        mirror(conditional_cmovnge.family, conditional_cmovnge.path, conditional_cmovnge.source),
        mirror(conditional_cmovnl.family, conditional_cmovnl.path, conditional_cmovnl.source),
        mirror(conditional_cmovnle.family, conditional_cmovnle.path, conditional_cmovnle.source),
        mirror(conditional_cmovno.family, conditional_cmovno.path, conditional_cmovno.source),
        mirror(conditional_cmovnp.family, conditional_cmovnp.path, conditional_cmovnp.source),
        mirror(conditional_cmovns.family, conditional_cmovns.path, conditional_cmovns.source),
        mirror(conditional_cmovnz.family, conditional_cmovnz.path, conditional_cmovnz.source),
        mirror(conditional_cmovo.family, conditional_cmovo.path, conditional_cmovo.source),
        mirror(conditional_cmovp.family, conditional_cmovp.path, conditional_cmovp.source),
        mirror(conditional_cmovpe.family, conditional_cmovpe.path, conditional_cmovpe.source),
        mirror(conditional_cmovpo.family, conditional_cmovpo.path, conditional_cmovpo.source),
        mirror(conditional_cmovs.family, conditional_cmovs.path, conditional_cmovs.source),
        mirror(conditional_cmovz.family, conditional_cmovz.path, conditional_cmovz.source),
        mirror(conditional_fcmovb.family, conditional_fcmovb.path, conditional_fcmovb.source),
        mirror(conditional_fcmove.family, conditional_fcmove.path, conditional_fcmove.source),
        mirror(conditional_fcmovbe.family, conditional_fcmovbe.path, conditional_fcmovbe.source),
        mirror(conditional_fcmovu.family, conditional_fcmovu.path, conditional_fcmovu.source),
        mirror(conditional_fcmovnb.family, conditional_fcmovnb.path, conditional_fcmovnb.source),
        mirror(conditional_fcmovne.family, conditional_fcmovne.path, conditional_fcmovne.source),
        mirror(conditional_fcmovnbe.family, conditional_fcmovnbe.path, conditional_fcmovnbe.source),
        mirror(conditional_fcmovnu.family, conditional_fcmovnu.path, conditional_fcmovnu.source),
        mirror(conditional_vmaskmovps.family, conditional_vmaskmovps.path, conditional_vmaskmovps.source),
        mirror(conditional_vmaskmovpd.family, conditional_vmaskmovpd.path, conditional_vmaskmovpd.source),
        mirror(conditional_vpmaskmovd.family, conditional_vpmaskmovd.path, conditional_vpmaskmovd.source),
        mirror(conditional_vpmaskmovq.family, conditional_vpmaskmovq.path, conditional_vpmaskmovq.source),
        mirror(convert_cbw.family, convert_cbw.path, convert_cbw.source),
        mirror(convert_cwde.family, convert_cwde.path, convert_cwde.source),
        mirror(convert_cdqe.family, convert_cdqe.path, convert_cdqe.source),
        mirror(convert_cwd.family, convert_cwd.path, convert_cwd.source),
        mirror(convert_cdq.family, convert_cdq.path, convert_cdq.source),
        mirror(convert_cqo.family, convert_cqo.path, convert_cqo.source),
        mirror(convert_cvtdq2pd.family, convert_cvtdq2pd.path, convert_cvtdq2pd.source),
        mirror(convert_cvtdq2ps.family, convert_cvtdq2ps.path, convert_cvtdq2ps.source),
        mirror(convert_cvtpd2dq.family, convert_cvtpd2dq.path, convert_cvtpd2dq.source),
        mirror(convert_cvtpd2pi.family, convert_cvtpd2pi.path, convert_cvtpd2pi.source),
        mirror(convert_cvtpd2ps.family, convert_cvtpd2ps.path, convert_cvtpd2ps.source),
        mirror(convert_cvtpi2pd.family, convert_cvtpi2pd.path, convert_cvtpi2pd.source),
        mirror(convert_cvtpi2ps.family, convert_cvtpi2ps.path, convert_cvtpi2ps.source),
        mirror(convert_cvtps2dq.family, convert_cvtps2dq.path, convert_cvtps2dq.source),
        mirror(convert_cvtps2pd.family, convert_cvtps2pd.path, convert_cvtps2pd.source),
        mirror(convert_cvtps2pi.family, convert_cvtps2pi.path, convert_cvtps2pi.source),
        mirror(convert_cvtsd2si.family, convert_cvtsd2si.path, convert_cvtsd2si.source),
        mirror(convert_cvtsd2ss.family, convert_cvtsd2ss.path, convert_cvtsd2ss.source),
        mirror(convert_cvtsi2sd.family, convert_cvtsi2sd.path, convert_cvtsi2sd.source),
        mirror(convert_cvtsi2ss.family, convert_cvtsi2ss.path, convert_cvtsi2ss.source),
        mirror(convert_cvtss2sd.family, convert_cvtss2sd.path, convert_cvtss2sd.source),
        mirror(convert_cvtss2si.family, convert_cvtss2si.path, convert_cvtss2si.source),
        mirror(convert_cvttpd2dq.family, convert_cvttpd2dq.path, convert_cvttpd2dq.source),
        mirror(convert_cvttpd2pi.family, convert_cvttpd2pi.path, convert_cvttpd2pi.source),
        mirror(convert_cvttps2dq.family, convert_cvttps2dq.path, convert_cvttps2dq.source),
        mirror(convert_cvttps2pi.family, convert_cvttps2pi.path, convert_cvttps2pi.source),
        mirror(convert_cvttsd2si.family, convert_cvttsd2si.path, convert_cvttsd2si.source),
        mirror(convert_cvttss2si.family, convert_cvttss2si.path, convert_cvttss2si.source),
        mirror(convert_vcvtne2ps2bf16.family, convert_vcvtne2ps2bf16.path, convert_vcvtne2ps2bf16.source),
        mirror(convert_vcvtneps2bf16.family, convert_vcvtneps2bf16.path, convert_vcvtneps2bf16.source),
        mirror(convert_vcvtpd2ph.family, convert_vcvtpd2ph.path, convert_vcvtpd2ph.source),
        mirror(convert_vcvtpd2qq.family, convert_vcvtpd2qq.path, convert_vcvtpd2qq.source),
        mirror(convert_vcvtpd2udq.family, convert_vcvtpd2udq.path, convert_vcvtpd2udq.source),
        mirror(convert_vcvtpd2uqq.family, convert_vcvtpd2uqq.path, convert_vcvtpd2uqq.source),
        mirror(convert_vcvtph2dq.family, convert_vcvtph2dq.path, convert_vcvtph2dq.source),
        mirror(convert_vcvtph2pd.family, convert_vcvtph2pd.path, convert_vcvtph2pd.source),
        mirror(convert_vcvtph2ps.family, convert_vcvtph2ps.path, convert_vcvtph2ps.source),
        mirror(convert_vcvtph2psx.family, convert_vcvtph2psx.path, convert_vcvtph2psx.source),
        mirror(convert_vcvtph2qq.family, convert_vcvtph2qq.path, convert_vcvtph2qq.source),
        mirror(convert_vcvtph2udq.family, convert_vcvtph2udq.path, convert_vcvtph2udq.source),
        mirror(convert_vcvtph2uqq.family, convert_vcvtph2uqq.path, convert_vcvtph2uqq.source),
        mirror(convert_vcvtph2uw.family, convert_vcvtph2uw.path, convert_vcvtph2uw.source),
        mirror(convert_vcvtph2w.family, convert_vcvtph2w.path, convert_vcvtph2w.source),
        mirror(convert_vcvtps2ph.family, convert_vcvtps2ph.path, convert_vcvtps2ph.source),
        mirror(convert_vcvtps2phx.family, convert_vcvtps2phx.path, convert_vcvtps2phx.source),
        mirror(convert_vcvtps2qq.family, convert_vcvtps2qq.path, convert_vcvtps2qq.source),
        mirror(convert_vcvtps2udq.family, convert_vcvtps2udq.path, convert_vcvtps2udq.source),
        mirror(convert_vcvtps2uqq.family, convert_vcvtps2uqq.path, convert_vcvtps2uqq.source),
        mirror(convert_vcvtqq2pd.family, convert_vcvtqq2pd.path, convert_vcvtqq2pd.source),
        mirror(convert_vcvtqq2ph.family, convert_vcvtqq2ph.path, convert_vcvtqq2ph.source),
        mirror(convert_vcvtqq2ps.family, convert_vcvtqq2ps.path, convert_vcvtqq2ps.source),
        mirror(convert_vcvtsd2sh.family, convert_vcvtsd2sh.path, convert_vcvtsd2sh.source),
        mirror(convert_vcvtsd2usi.family, convert_vcvtsd2usi.path, convert_vcvtsd2usi.source),
        mirror(convert_vcvtsh2sd.family, convert_vcvtsh2sd.path, convert_vcvtsh2sd.source),
        mirror(convert_vcvtsh2si.family, convert_vcvtsh2si.path, convert_vcvtsh2si.source),
        mirror(convert_vcvtsh2ss.family, convert_vcvtsh2ss.path, convert_vcvtsh2ss.source),
        mirror(convert_vcvtsh2usi.family, convert_vcvtsh2usi.path, convert_vcvtsh2usi.source),
        mirror(convert_vgetexppd.family, convert_vgetexppd.path, convert_vgetexppd.source),
        mirror(convert_vgetexpph.family, convert_vgetexpph.path, convert_vgetexpph.source),
        mirror(convert_vgetexpps.family, convert_vgetexpps.path, convert_vgetexpps.source),
        mirror(convert_vgetexpsd.family, convert_vgetexpsd.path, convert_vgetexpsd.source),
        mirror(convert_vgetexpsh.family, convert_vgetexpsh.path, convert_vgetexpsh.source),
        mirror(convert_vgetexpss.family, convert_vgetexpss.path, convert_vgetexpss.source),
        mirror(convert_vpmovb2m.family, convert_vpmovb2m.path, convert_vpmovb2m.source),
        mirror(convert_vpmovw2m.family, convert_vpmovw2m.path, convert_vpmovw2m.source),
        mirror(convert_vpmovd2m.family, convert_vpmovd2m.path, convert_vpmovd2m.source),
        mirror(convert_vpmovq2m.family, convert_vpmovq2m.path, convert_vpmovq2m.source),
        mirror(convert_vpmovm2b.family, convert_vpmovm2b.path, convert_vpmovm2b.source),
        mirror(convert_vpmovm2w.family, convert_vpmovm2w.path, convert_vpmovm2w.source),
        mirror(convert_vpmovm2d.family, convert_vpmovm2d.path, convert_vpmovm2d.source),
        mirror(convert_vpmovm2q.family, convert_vpmovm2q.path, convert_vpmovm2q.source),
        mirror(halt_hlt.family, halt_hlt.path, halt_hlt.source),
        mirror(loop_loop.family, loop_loop.path, loop_loop.source),
        mirror(loop_loope.family, loop_loope.path, loop_loope.source),
        mirror(loop_loopne.family, loop_loopne.path, loop_loopne.source),
        mirror(loop_pause.family, loop_pause.path, loop_pause.source),
        mirror(memory_mfence.family, memory_mfence.path, memory_mfence.source),
        mirror(mov_kmovw.family, mov_kmovw.path, mov_kmovw.source),
        mirror(mov_kmovb.family, mov_kmovb.path, mov_kmovb.source),
        mirror(mov_kmovq.family, mov_kmovq.path, mov_kmovq.source),
        mirror(mov_kmovd.family, mov_kmovd.path, mov_kmovd.source),
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
        mirror(mov_pmovmskb.family, mov_pmovmskb.path, mov_pmovmskb.source),
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
        mirror(mov_vmovsh.family, mov_vmovsh.path, mov_vmovsh.source),
        mirror(mov_vmovshdup.family, mov_vmovshdup.path, mov_vmovshdup.source),
        mirror(mov_vmovsldup.family, mov_vmovsldup.path, mov_vmovsldup.source),
        mirror(mov_vmovss.family, mov_vmovss.path, mov_vmovss.source),
        mirror(mov_vmovupd.family, mov_vmovupd.path, mov_vmovupd.source),
        mirror(mov_vmovups.family, mov_vmovups.path, mov_vmovups.source),
        mirror(mov_vmovw.family, mov_vmovw.path, mov_vmovw.source),
        mirror(mul_imul.family, mul_imul.path, mul_imul.source),
        mirror(mul_mul.family, mul_mul.path, mul_mul.source),
        mirror(mul_mulpd.family, mul_mulpd.path, mul_mulpd.source),
        mirror(mul_mulps.family, mul_mulps.path, mul_mulps.source),
        mirror(mul_mulsd.family, mul_mulsd.path, mul_mulsd.source),
        mirror(mul_mulss.family, mul_mulss.path, mul_mulss.source),
        mirror(mul_mulx.family, mul_mulx.path, mul_mulx.source),
        mirror(mul_fmul.family, mul_fmul.path, mul_fmul.source),
        mirror(mul_fmulp.family, mul_fmulp.path, mul_fmulp.source),
        mirror(mul_fimul.family, mul_fimul.path, mul_fimul.source),
        mirror(mul_pclmulqdq.family, mul_pclmulqdq.path, mul_pclmulqdq.source),
        mirror(mul_pmaddubsw.family, mul_pmaddubsw.path, mul_pmaddubsw.source),
        mirror(mul_pmaddwd.family, mul_pmaddwd.path, mul_pmaddwd.source),
        mirror(mul_pmulhrsw.family, mul_pmulhrsw.path, mul_pmulhrsw.source),
        mirror(mul_pmulhuw.family, mul_pmulhuw.path, mul_pmulhuw.source),
        mirror(mul_pmulhw.family, mul_pmulhw.path, mul_pmulhw.source),
        mirror(mul_pmulld.family, mul_pmulld.path, mul_pmulld.source),
        mirror(mul_pmullq.family, mul_pmullq.path, mul_pmullq.source),
        mirror(mul_pmullw.family, mul_pmullw.path, mul_pmullw.source),
        mirror(mul_pmuludq.family, mul_pmuludq.path, mul_pmuludq.source),
        mirror(mul_vfcmulcph.family, mul_vfcmulcph.path, mul_vfcmulcph.source),
        mirror(mul_vfmulcph.family, mul_vfmulcph.path, mul_vfmulcph.source),
        mirror(mul_vfcmulcsh.family, mul_vfcmulcsh.path, mul_vfcmulcsh.source),
        mirror(mul_vfmulcsh.family, mul_vfmulcsh.path, mul_vfmulcsh.source),
        mirror(mul_vmulph.family, mul_vmulph.path, mul_vmulph.source),
        mirror(mul_vmulsh.family, mul_vmulsh.path, mul_vmulsh.source),
        mirror(mul_vpdpbusd.family, mul_vpdpbusd.path, mul_vpdpbusd.source),
        mirror(mul_vpdpbusds.family, mul_vpdpbusds.path, mul_vpdpbusds.source),
        mirror(mul_vpdpwssd.family, mul_vpdpwssd.path, mul_vpdpwssd.source),
        mirror(mul_vpdpwssds.family, mul_vpdpwssds.path, mul_vpdpwssds.source),
        mirror(mul_vpmadd52huq.family, mul_vpmadd52huq.path, mul_vpmadd52huq.source),
        mirror(mul_vpmadd52luq.family, mul_vpmadd52luq.path, mul_vpmadd52luq.source),
        mirror(or_or.family, or_or.path, or_or.source),
        mirror(or_orpd.family, or_orpd.path, or_orpd.source),
        mirror(or_orps.family, or_orps.path, or_orps.source),
        mirror(output_out.family, output_out.path, output_out.source),
        mirror(output_outs.family, output_outs.path, output_outs.source),
        mirror(output_outsb.family, output_outsb.path, output_outsb.source),
        mirror(output_outsw.family, output_outsw.path, output_outsw.source),
        mirror(output_outsd.family, output_outsd.path, output_outsd.source),
        mirror(pack_packssdw.family, pack_packssdw.path, pack_packssdw.source),
        mirror(pack_packsswb.family, pack_packsswb.path, pack_packsswb.source),
        mirror(pack_packusdw.family, pack_packusdw.path, pack_packusdw.source),
        mirror(pack_packuswb.family, pack_packuswb.path, pack_packuswb.source),
        mirror(pack_palignr.family, pack_palignr.path, pack_palignr.source),
        mirror(pack_pcmpestri.family, pack_pcmpestri.path, pack_pcmpestri.source),
        mirror(pack_pcmpestrm.family, pack_pcmpestrm.path, pack_pcmpestrm.source),
        mirror(pack_pcmpistri.family, pack_pcmpistri.path, pack_pcmpistri.source),
        mirror(pack_pcmpistrm.family, pack_pcmpistrm.path, pack_pcmpistrm.source),
        mirror(pack_phminposuw.family, pack_phminposuw.path, pack_phminposuw.source),
        mirror(pack_pmovsxbd.family, pack_pmovsxbd.path, pack_pmovsxbd.source),
        mirror(pack_pmovsxbq.family, pack_pmovsxbq.path, pack_pmovsxbq.source),
        mirror(pack_pmovsxbw.family, pack_pmovsxbw.path, pack_pmovsxbw.source),
        mirror(pack_pmovsxdq.family, pack_pmovsxdq.path, pack_pmovsxdq.source),
        mirror(pack_pmovsxwd.family, pack_pmovsxwd.path, pack_pmovsxwd.source),
        mirror(pack_pmovsxwq.family, pack_pmovsxwq.path, pack_pmovsxwq.source),
        mirror(pack_pmovzxbd.family, pack_pmovzxbd.path, pack_pmovzxbd.source),
        mirror(pack_pmovzxbq.family, pack_pmovzxbq.path, pack_pmovzxbq.source),
        mirror(pack_pmovzxbw.family, pack_pmovzxbw.path, pack_pmovzxbw.source),
        mirror(pack_pmovzxdq.family, pack_pmovzxdq.path, pack_pmovzxdq.source),
        mirror(pack_pmovzxwd.family, pack_pmovzxwd.path, pack_pmovzxwd.source),
        mirror(pack_pmovzxwq.family, pack_pmovzxwq.path, pack_pmovzxwq.source),
        mirror(pack_pmuldq.family, pack_pmuldq.path, pack_pmuldq.source),
        mirror(pack_pshufb.family, pack_pshufb.path, pack_pshufb.source),
        mirror(pack_psignb.family, pack_psignb.path, pack_psignb.source),
        mirror(pack_psignd.family, pack_psignd.path, pack_psignd.source),
        mirror(pack_psignw.family, pack_psignw.path, pack_psignw.source),
        mirror(pop_pop.family, pop_pop.path, pop_pop.source),
        mirror(pop_popa.family, pop_popa.path, pop_popa.source),
        mirror(pop_popad.family, pop_popad.path, pop_popad.source),
        mirror(pop_popcnt.family, pop_popcnt.path, pop_popcnt.source),
        mirror(push_push.family, push_push.path, push_push.source),
        mirror(push_pusha.family, push_pusha.path, push_pusha.source),
        mirror(push_pushad.family, push_pushad.path, push_pushad.source),
        mirror(push_pushf.family, push_pushf.path, push_pushf.source),
        mirror(push_pushfd.family, push_pushfd.path, push_pushfd.source),
        mirror(push_pushfq.family, push_pushfq.path, push_pushfq.source),
        mirror(restore_frstore.family, restore_frstore.path, restore_frstore.source),
        mirror(restore_fxrstore.family, restore_fxrstore.path, restore_fxrstore.source),
        mirror(restore_rstore_ssp.family, restore_rstore_ssp.path, restore_rstore_ssp.source),
        mirror(restore_xrstore.family, restore_xrstore.path, restore_xrstore.source),
        mirror(restore_xrstors.family, restore_xrstors.path, restore_xrstors.source),
        mirror(rotate_rcl.family, rotate_rcl.path, rotate_rcl.source),
        mirror(rotate_rcr.family, rotate_rcr.path, rotate_rcr.source),
        mirror(rotate_rol.family, rotate_rol.path, rotate_rol.source),
        mirror(rotate_ror.family, rotate_ror.path, rotate_ror.source),
        mirror(rotate_rorx.family, rotate_rorx.path, rotate_rorx.source),
        mirror(rotate_vprold.family, rotate_vprold.path, rotate_vprold.source),
        mirror(rotate_vprolvd.family, rotate_vprolvd.path, rotate_vprolvd.source),
        mirror(rotate_vprolq.family, rotate_vprolq.path, rotate_vprolq.source),
        mirror(rotate_vprolvq.family, rotate_vprolvq.path, rotate_vprolvq.source),
        mirror(rotate_vprord.family, rotate_vprord.path, rotate_vprord.source),
        mirror(rotate_vprorvd.family, rotate_vprorvd.path, rotate_vprorvd.source),
        mirror(rotate_vprorq.family, rotate_vprorq.path, rotate_vprorq.source),
        mirror(rotate_vprorvq.family, rotate_vprorvq.path, rotate_vprorvq.source),
        mirror(save_fsave.family, save_fsave.path, save_fsave.source),
        mirror(save_fxsave.family, save_fxsave.path, save_fxsave.source),
        mirror(save_saveprevssp.family, save_saveprevssp.path, save_saveprevssp.source),
        mirror(scale_fscale.family, scale_fscale.path, scale_fscale.source),
        mirror(scale_vscalefpd.family, scale_vscalefpd.path, scale_vscalefpd.source),
        mirror(scale_vscalefph.family, scale_vscalefph.path, scale_vscalefph.source),
        mirror(scale_vscalefps.family, scale_vscalefps.path, scale_vscalefps.source),
        mirror(scale_vscalefsd.family, scale_vscalefsd.path, scale_vscalefsd.source),
        mirror(scale_vscalefsh.family, scale_vscalefsh.path, scale_vscalefsh.source),
        mirror(scale_vscalefss.family, scale_vscalefss.path, scale_vscalefss.source),
        mirror(swap_swapgs.family, swap_swapgs.path, swap_swapgs.source),
        mirror(sub_sub.family, sub_sub.path, sub_sub.source),
        mirror(sub_subpd.family, sub_subpd.path, sub_subpd.source),
        mirror(sub_subps.family, sub_subps.path, sub_subps.source),
        mirror(sub_subsd.family, sub_subsd.path, sub_subsd.source),
        mirror(sub_subss.family, sub_subss.path, sub_subss.source),
        mirror(sub_fsub.family, sub_fsub.path, sub_fsub.source),
        mirror(sub_fsubp.family, sub_fsubp.path, sub_fsubp.source),
        mirror(sub_fisub.family, sub_fisub.path, sub_fisub.source),
        mirror(sub_hsubpd.family, sub_hsubpd.path, sub_hsubpd.source),
        mirror(sub_hsubps.family, sub_hsubps.path, sub_hsubps.source),
        mirror(sub_phsubw.family, sub_phsubw.path, sub_phsubw.source),
        mirror(sub_phsubd.family, sub_phsubd.path, sub_phsubd.source),
        mirror(sub_phsubsw.family, sub_phsubsw.path, sub_phsubsw.source),
        mirror(sub_psubb.family, sub_psubb.path, sub_psubb.source),
        mirror(sub_psubw.family, sub_psubw.path, sub_psubw.source),
        mirror(sub_psubd.family, sub_psubd.path, sub_psubd.source),
        mirror(sub_psubq.family, sub_psubq.path, sub_psubq.source),
        mirror(sub_psubsb.family, sub_psubsb.path, sub_psubsb.source),
        mirror(sub_psubsw.family, sub_psubsw.path, sub_psubsw.source),
        mirror(sub_psubusb.family, sub_psubusb.path, sub_psubusb.source),
        mirror(sub_psubusw.family, sub_psubusw.path, sub_psubusw.source),
        mirror(sub_sbb.family, sub_sbb.path, sub_sbb.source),
        mirror(sub_vsubph.family, sub_vsubph.path, sub_vsubph.source),
        mirror(sub_vsubsh.family, sub_vsubsh.path, sub_vsubsh.source),
        mirror(test_test.family, test_test.path, test_test.source),
        mirror(test_testui.family, test_testui.path, test_testui.source),
        mirror(test_ftst.family, test_ftst.path, test_ftst.source),
        mirror(test_ktestw.family, test_ktestw.path, test_ktestw.source),
        mirror(test_ktestb.family, test_ktestb.path, test_ktestb.source),
        mirror(test_ktestq.family, test_ktestq.path, test_ktestq.source),
        mirror(test_ktestd.family, test_ktestd.path, test_ktestd.source),
        mirror(test_ptest.family, test_ptest.path, test_ptest.source),
        mirror(test_vfpclasspd.family, test_vfpclasspd.path, test_vfpclasspd.source),
        mirror(test_vfpclassph.family, test_vfpclassph.path, test_vfpclassph.source),
        mirror(test_vfpclassps.family, test_vfpclassps.path, test_vfpclassps.source),
        mirror(test_vfpclasssd.family, test_vfpclasssd.path, test_vfpclasssd.source),
        mirror(test_vfpclasssh.family, test_vfpclasssh.path, test_vfpclasssh.source),
        mirror(test_vfpclassss.family, test_vfpclassss.path, test_vfpclassss.source),
        mirror(test_vtestpd.family, test_vtestpd.path, test_vtestpd.source),
        mirror(test_vtestps.family, test_vtestps.path, test_vtestps.source),
        mirror(test_xtest.family, test_xtest.path, test_xtest.source),
        mirror(unpack_kunpckbw.family, unpack_kunpckbw.path, unpack_kunpckbw.source),
        mirror(unpack_kunpckwd.family, unpack_kunpckwd.path, unpack_kunpckwd.source),
        mirror(unpack_kunpckdq.family, unpack_kunpckdq.path, unpack_kunpckdq.source),
        mirror(unpack_punpckhbw.family, unpack_punpckhbw.path, unpack_punpckhbw.source),
        mirror(unpack_punpckhwd.family, unpack_punpckhwd.path, unpack_punpckhwd.source),
        mirror(unpack_punpckhdq.family, unpack_punpckhdq.path, unpack_punpckhdq.source),
        mirror(unpack_punpckhqdq.family, unpack_punpckhqdq.path, unpack_punpckhqdq.source),
        mirror(unpack_punpcklbw.family, unpack_punpcklbw.path, unpack_punpcklbw.source),
        mirror(unpack_punpcklwd.family, unpack_punpcklwd.path, unpack_punpcklwd.source),
        mirror(unpack_punpckldq.family, unpack_punpckldq.path, unpack_punpckldq.source),
        mirror(unpack_punpcklqdq.family, unpack_punpcklqdq.path, unpack_punpcklqdq.source),
        mirror(unpack_unpckhpd.family, unpack_unpckhpd.path, unpack_unpckhpd.source),
        mirror(unpack_unpckhps.family, unpack_unpckhps.path, unpack_unpckhps.source),
        mirror(unpack_unpcklpd.family, unpack_unpcklpd.path, unpack_unpcklpd.source),
        mirror(unpack_unpcklps.family, unpack_unpcklps.path, unpack_unpcklps.source),
        mirror(undef_ud0.family, undef_ud0.path, undef_ud0.source),
        mirror(undef_ud1.family, undef_ud1.path, undef_ud1.source),
        mirror(undef_ud2.family, undef_ud2.path, undef_ud2.source),
        mirror(unordered_ucomisd.family, unordered_ucomisd.path, unordered_ucomisd.source),
        mirror(unordered_ucomiss.family, unordered_ucomiss.path, unordered_ucomiss.source),
        mirror(unordered_vucomish.family, unordered_vucomish.path, unordered_vucomish.source),
        mirror(variable_vpsllvw.family, variable_vpsllvw.path, variable_vpsllvw.source),
        mirror(variable_vpsllvd.family, variable_vpsllvd.path, variable_vpsllvd.source),
        mirror(variable_vpsllvq.family, variable_vpsllvq.path, variable_vpsllvq.source),
        mirror(variable_vpsravw.family, variable_vpsravw.path, variable_vpsravw.source),
        mirror(variable_vpsravd.family, variable_vpsravd.path, variable_vpsravd.source),
        mirror(variable_vpsravq.family, variable_vpsravq.path, variable_vpsravq.source),
        mirror(variable_vpsrlvw.family, variable_vpsrlvw.path, variable_vpsrlvw.source),
        mirror(variable_vpsrlvd.family, variable_vpsrlvd.path, variable_vpsrlvd.source),
        mirror(variable_vpsrlvq.family, variable_vpsrlvq.path, variable_vpsrlvq.source),
        mirror(verify_verr.family, verify_verr.path, verify_verr.source),
        mirror(verify_verw.family, verify_verw.path, verify_verw.source),
        mirror(vptestm_vptestmb.family, vptestm_vptestmb.path, vptestm_vptestmb.source),
        mirror(vptestm_vptestmw.family, vptestm_vptestmw.path, vptestm_vptestmw.source),
        mirror(vptestm_vptestmd.family, vptestm_vptestmd.path, vptestm_vptestmd.source),
        mirror(vptestm_vptestmq.family, vptestm_vptestmq.path, vptestm_vptestmq.source),
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
        mirror(blend_pblendvb.family, blend_pblendvb.path, blend_pblendvb.source),
        mirror(blend_pblendw.family, blend_pblendw.path, blend_pblendw.source),
        mirror(blend_vblendmpd.family, blend_vblendmpd.path, blend_vblendmpd.source),
        mirror(blend_vblendmps.family, blend_vblendmps.path, blend_vblendmps.source),
        mirror(blend_vpblendd.family, blend_vpblendd.path, blend_vpblendd.source),
        mirror(blend_vpblendmb.family, blend_vpblendmb.path, blend_vpblendmb.source),
        mirror(blend_vpblendmw.family, blend_vpblendmw.path, blend_vpblendmw.source),
        mirror(blend_vpblendmd.family, blend_vpblendmd.path, blend_vpblendmd.source),
        mirror(blend_vpblendmq.family, blend_vpblendmq.path, blend_vpblendmq.source),
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
        mirror(cache_clwb.family, cache_clwb.path, cache_clwb.source),
        mirror(cpu_cpuid.family, cpu_cpuid.path, cpu_cpuid.source),
        mirror(sha_sha1msg1.family, sha_sha1msg1.path, sha_sha1msg1.source),
        mirror(sha_sha1msg2.family, sha_sha1msg2.path, sha_sha1msg2.source),
        mirror(sha_sha1nexte.family, sha_sha1nexte.path, sha_sha1nexte.source),
        mirror(sha_sha1rnds4.family, sha_sha1rnds4.path, sha_sha1rnds4.source),
        mirror(sha_sha256msg1.family, sha_sha256msg1.path, sha_sha256msg1.source),
        mirror(sha_sha256msg2.family, sha_sha256msg2.path, sha_sha256msg2.source),
        mirror(sha_sha256rnds2.family, sha_sha256rnds2.path, sha_sha256rnds2.source),
        mirror(shadow_incssp.family, shadow_incssp.path, shadow_incssp.source),
        mirror(terminate_endbr32.family, terminate_endbr32.path, terminate_endbr32.source),
        mirror(terminate_endbr64.family, terminate_endbr64.path, terminate_endbr64.source),
        mirror(sys_syscall.family, sys_syscall.path, sys_syscall.source),
        mirror(sys_sysenter.family, sys_sysenter.path, sys_sysenter.source),
        mirror(sys_sysexit.family, sys_sysexit.path, sys_sysexit.source),
        mirror(sys_sysret.family, sys_sysret.path, sys_sysret.source),
        mirror(shuffle_shufpd.family, shuffle_shufpd.path, shuffle_shufpd.source),
        mirror(shuffle_shufps.family, shuffle_shufps.path, shuffle_shufps.source),
        mirror(shuffle_vpshufbitqmb.family, shuffle_vpshufbitqmb.path, shuffle_vpshufbitqmb.source),
        mirror(shuffle_vpunpckldq.family, shuffle_vpunpckldq.path, shuffle_vpunpckldq.source),
        mirror(shuffle_vpermilpd.family, shuffle_vpermilpd.path, shuffle_vpermilpd.source),
        mirror(shuffle_vshuff32x4.family, shuffle_vshuff32x4.path, shuffle_vshuff32x4.source),
        mirror(shuffle_vshuff64x2.family, shuffle_vshuff64x2.path, shuffle_vshuff64x2.source),
        mirror(shuffle_vshufi32x4.family, shuffle_vshufi32x4.path, shuffle_vshufi32x4.source),
        mirror(shuffle_vshufi64x2.family, shuffle_vshufi64x2.path, shuffle_vshufi64x2.source),
        mirror(shift_sal.family, shift_sal.path, shift_sal.source),
        mirror(shift_sar.family, shift_sar.path, shift_sar.source),
        mirror(shift_shl.family, shift_shl.path, shift_shl.source),
        mirror(shift_shr.family, shift_shr.path, shift_shr.source),
        mirror(shift_shld.family, shift_shld.path, shift_shld.source),
        mirror(shift_shrd.family, shift_shrd.path, shift_shrd.source),
        mirror(shift_sarx.family, shift_sarx.path, shift_sarx.source),
        mirror(shift_shlx.family, shift_shlx.path, shift_shlx.source),
        mirror(shift_shrx.family, shift_shrx.path, shift_shrx.source),
        mirror(shift_kshiftlb.family, shift_kshiftlb.path, shift_kshiftlb.source),
        mirror(shift_kshiftld.family, shift_kshiftld.path, shift_kshiftld.source),
        mirror(shift_kshiftlq.family, shift_kshiftlq.path, shift_kshiftlq.source),
        mirror(shift_kshiftlw.family, shift_kshiftlw.path, shift_kshiftlw.source),
        mirror(shift_kshiftrb.family, shift_kshiftrb.path, shift_kshiftrb.source),
        mirror(shift_kshiftrd.family, shift_kshiftrd.path, shift_kshiftrd.source),
        mirror(shift_kshiftrq.family, shift_kshiftrq.path, shift_kshiftrq.source),
        mirror(shift_kshiftrw.family, shift_kshiftrw.path, shift_kshiftrw.source),
        mirror(shift_pslld.family, shift_pslld.path, shift_pslld.source),
        mirror(shift_pslldq.family, shift_pslldq.path, shift_pslldq.source),
        mirror(shift_psllq.family, shift_psllq.path, shift_psllq.source),
        mirror(shift_psllw.family, shift_psllw.path, shift_psllw.source),
        mirror(shift_psraq.family, shift_psraq.path, shift_psraq.source),
        mirror(shift_psrad.family, shift_psrad.path, shift_psrad.source),
        mirror(shift_psraw.family, shift_psraw.path, shift_psraw.source),
        mirror(shift_psrld.family, shift_psrld.path, shift_psrld.source),
        mirror(shift_psrldq.family, shift_psrldq.path, shift_psrldq.source),
        mirror(shift_psrlq.family, shift_psrlq.path, shift_psrlq.source),
        mirror(shift_psrlw.family, shift_psrlw.path, shift_psrlw.source),
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
        mirror(min_max_maxpd.family, min_max_maxpd.path, min_max_maxpd.source),
        mirror(min_max_maxps.family, min_max_maxps.path, min_max_maxps.source),
        mirror(min_max_minpd.family, min_max_minpd.path, min_max_minpd.source),
        mirror(min_max_minps.family, min_max_minps.path, min_max_minps.source),
        mirror(set_monitor.family, set_monitor.path, set_monitor.source),
        mirror(set_umonitor.family, set_umonitor.path, set_umonitor.source),
        mirror(set_stac.family, set_stac.path, set_stac.source),
        mirror(set_stc.family, set_stc.path, set_stc.source),
        mirror(set_std.family, set_std.path, set_std.source),
        mirror(set_sti.family, set_sti.path, set_sti.source),
        mirror(set_stui.family, set_stui.path, set_stui.source),
        mirror(set_xsetbv.family, set_xsetbv.path, set_xsetbv.source),
        mirror(set_seta.family, set_seta.path, set_seta.source),
        mirror(set_setae.family, set_setae.path, set_setae.source),
        mirror(set_setb.family, set_setb.path, set_setb.source),
        mirror(set_setbe.family, set_setbe.path, set_setbe.source),
        mirror(set_setc.family, set_setc.path, set_setc.source),
        mirror(set_sete.family, set_sete.path, set_sete.source),
        mirror(set_setg.family, set_setg.path, set_setg.source),
        mirror(set_setge.family, set_setge.path, set_setge.source),
        mirror(set_setl.family, set_setl.path, set_setl.source),
        mirror(set_setle.family, set_setle.path, set_setle.source),
        mirror(set_setna.family, set_setna.path, set_setna.source),
        mirror(set_setnae.family, set_setnae.path, set_setnae.source),
        mirror(set_setnb.family, set_setnb.path, set_setnb.source),
        mirror(set_setnbe.family, set_setnbe.path, set_setnbe.source),
        mirror(set_setnc.family, set_setnc.path, set_setnc.source),
        mirror(set_setne.family, set_setne.path, set_setne.source),
        mirror(set_setng.family, set_setng.path, set_setng.source),
        mirror(set_setnge.family, set_setnge.path, set_setnge.source),
        mirror(set_setnl.family, set_setnl.path, set_setnl.source),
        mirror(set_setnle.family, set_setnle.path, set_setnle.source),
        mirror(set_setno.family, set_setno.path, set_setno.source),
        mirror(set_setnp.family, set_setnp.path, set_setnp.source),
        mirror(set_setns.family, set_setns.path, set_setns.source),
        mirror(set_setnz.family, set_setnz.path, set_setnz.source),
        mirror(set_seto.family, set_seto.path, set_seto.source),
        mirror(set_setp.family, set_setp.path, set_setp.source),
        mirror(set_setpe.family, set_setpe.path, set_setpe.source),
        mirror(set_setpo.family, set_setpo.path, set_setpo.source),
        mirror(set_sets.family, set_sets.path, set_sets.source),
        mirror(set_setz.family, set_setz.path, set_setz.source),
        mirror(count_lzcnt.family, count_lzcnt.path, count_lzcnt.source),
        mirror(count_tzcnt.family, count_tzcnt.path, count_tzcnt.source),
        mirror(count_vplzcntd.family, count_vplzcntd.path, count_vplzcntd.source),
        mirror(count_vplzcntq.family, count_vplzcntq.path, count_vplzcntq.source),
        mirror(exchange_fxch.family, exchange_fxch.path, exchange_fxch.source),
        mirror(exchange_xadd.family, exchange_xadd.path, exchange_xadd.source),
        mirror(exchange_xchg.family, exchange_xchg.path, exchange_xchg.source),
        mirror(nop_fnop.family, nop_fnop.path, nop_fnop.source),
        mirror(nop_nop.family, nop_nop.path, nop_nop.source),
        mirror(not_not.family, not_not.path, not_not.source),
        mirror(not_knotw.family, not_knotw.path, not_knotw.source),
        mirror(not_knotb.family, not_knotb.path, not_knotb.source),
        mirror(not_knotq.family, not_knotq.path, not_knotq.source),
        mirror(not_knotd.family, not_knotd.path, not_knotd.source),
        mirror(andnot_pandn.family, andnot_pandn.path, andnot_pandn.source),
        mirror(andnot_vpandn.family, andnot_vpandn.path, andnot_vpandn.source),
        mirror(andnot_vpandnd.family, andnot_vpandnd.path, andnot_vpandnd.source),
        mirror(andnot_vpandnq.family, andnot_vpandnq.path, andnot_vpandnq.source),
        mirror(andnot_kandnw.family, andnot_kandnw.path, andnot_kandnw.source),
        mirror(andnot_kandnb.family, andnot_kandnb.path, andnot_kandnb.source),
        mirror(andnot_kandnq.family, andnot_kandnq.path, andnot_kandnq.source),
        mirror(andnot_kandnd.family, andnot_kandnd.path, andnot_kandnd.source),
        mirror(bitposition_bzhi.family, bitposition_bzhi.path, bitposition_bzhi.source),
        mirror(change_fchs.family, change_fchs.path, change_fchs.source),
        mirror(complement_cmc.family, complement_cmc.path, complement_cmc.source),
        mirror(decimal_daa.family, decimal_daa.path, decimal_daa.source),
        mirror(decimal_das.family, decimal_das.path, decimal_das.source),
        mirror(dep_pdep.family, dep_pdep.path, dep_pdep.source),
        mirror(detect_vpconflictd.family, detect_vpconflictd.path, detect_vpconflictd.source),
        mirror(detect_vpconflictq.family, detect_vpconflictq.path, detect_vpconflictq.source),
        mirror(empty_emms.family, empty_emms.path, empty_emms.source),
        mirror(end_xend.family, end_xend.path, end_xend.source),
        mirror(examine_fxam.family, examine_fxam.path, examine_fxam.source),
        mirror(expand_vpexpandb.family, expand_vpexpandb.path, expand_vpexpandb.source),
        mirror(expand_vpexpandw.family, expand_vpexpandw.path, expand_vpexpandw.source),
        mirror(free_ffree.family, free_ffree.path, free_ffree.source),
        mirror(pand_pand.family, pand_pand.path, pand_pand.source),
        mirror(pand_vpand.family, pand_vpand.path, pand_vpand.source),
        mirror(pand_vpandd.family, pand_vpandd.path, pand_vpandd.source),
        mirror(pand_vpandq.family, pand_vpandq.path, pand_vpandq.source),
        mirror(partial_fpatan.family, partial_fpatan.path, partial_fpatan.source),
        mirror(partial_fprem.family, partial_fprem.path, partial_fprem.source),
        mirror(partial_fprem1.family, partial_fprem1.path, partial_fprem1.source),
        mirror(partial_fptan.family, partial_fptan.path, partial_fptan.source),
        mirror(pause_tpause.family, pause_tpause.path, pause_tpause.source),
        mirror(perform_vreducepd.family, perform_vreducepd.path, perform_vreducepd.source),
        mirror(perform_vreduceph.family, perform_vreduceph.path, perform_vreduceph.source),
        mirror(perform_vreduceps.family, perform_vreduceps.path, perform_vreduceps.source),
        mirror(perform_vreducesd.family, perform_vreducesd.path, perform_vreducesd.source),
        mirror(perform_vreducesh.family, perform_vreducesh.path, perform_vreducesh.source),
        mirror(perform_vreducess.family, perform_vreducess.path, perform_vreducess.source),
        mirror(permute_vperm2f128.family, permute_vperm2f128.path, permute_vperm2f128.source),
        mirror(permute_vperm2i128.family, permute_vperm2i128.path, permute_vperm2i128.source),
        mirror(permute_vpermb.family, permute_vpermb.path, permute_vpermb.source),
        mirror(permute_vpermd.family, permute_vpermd.path, permute_vpermd.source),
        mirror(permute_vpermw.family, permute_vpermw.path, permute_vpermw.source),
        mirror(permute_vpermilpd.family, permute_vpermilpd.path, permute_vpermilpd.source),
        mirror(permute_vpermilps.family, permute_vpermilps.path, permute_vpermilps.source),
        mirror(permute_vpermpd.family, permute_vpermpd.path, permute_vpermpd.source),
        mirror(permute_vpermps.family, permute_vpermps.path, permute_vpermps.source),
        mirror(permute_vpermq.family, permute_vpermq.path, permute_vpermq.source),
        mirror(platform_pconfig.family, platform_pconfig.path, platform_pconfig.source),
        mirror(prefetch_prefetchw.family, prefetch_prefetchw.path, prefetch_prefetchw.source),
        mirror(prefetch_prefetcht0.family, prefetch_prefetcht0.path, prefetch_prefetcht0.source),
        mirror(prefetch_prefetcht1.family, prefetch_prefetcht1.path, prefetch_prefetcht1.source),
        mirror(prefetch_prefetcht2.family, prefetch_prefetcht2.path, prefetch_prefetcht2.source),
        mirror(prefetch_prefetchnta.family, prefetch_prefetchnta.path, prefetch_prefetchnta.source),
        mirror(pxor_pxor.family, pxor_pxor.path, pxor_pxor.source),
        mirror(pxor_vpxor.family, pxor_vpxor.path, pxor_vpxor.source),
        mirror(pxor_vpxord.family, pxor_vpxord.path, pxor_vpxord.source),
        mirror(pxor_vpxorq.family, pxor_vpxorq.path, pxor_vpxorq.source),
        mirror(range_vrangepd.family, range_vrangepd.path, range_vrangepd.source),
        mirror(range_vrangeps.family, range_vrangeps.path, range_vrangeps.source),
        mirror(range_vrangesd.family, range_vrangesd.path, range_vrangesd.source),
        mirror(range_vrangess.family, range_vrangess.path, range_vrangess.source),
        mirror(read_rdfsbase.family, read_rdfsbase.path, read_rdfsbase.source),
        mirror(read_rdgsbase.family, read_rdgsbase.path, read_rdgsbase.source),
        mirror(read_rdmsr.family, read_rdmsr.path, read_rdmsr.source),
        mirror(read_rdpid.family, read_rdpid.path, read_rdpid.source),
        mirror(read_rdpkru.family, read_rdpkru.path, read_rdpkru.source),
        mirror(read_rdpmc.family, read_rdpmc.path, read_rdpmc.source),
        mirror(read_rdrand.family, read_rdrand.path, read_rdrand.source),
        mirror(read_rdseed.family, read_rdseed.path, read_rdseed.source),
        mirror(read_rdtsc.family, read_rdtsc.path, read_rdtsc.source),
        mirror(read_rdtscp.family, read_rdtscp.path, read_rdtscp.source),
        mirror(release_tilerelease.family, release_tilerelease.path, release_tilerelease.source),
        mirror(reset_hreset.family, reset_hreset.path, reset_hreset.source),
        mirror(resume_rsm.family, resume_rsm.path, resume_rsm.source),
        mirror(ret_maxsd.family, ret_maxsd.path, ret_maxsd.source),
        mirror(ret_maxss.family, ret_maxss.path, ret_maxss.source),
        mirror(ret_minsd.family, ret_minsd.path, ret_minsd.source),
        mirror(ret_minss.family, ret_minss.path, ret_minss.source),
        mirror(ret_vmaxph.family, ret_vmaxph.path, ret_vmaxph.source),
        mirror(ret_vmaxsh.family, ret_vmaxsh.path, ret_vmaxsh.source),
        mirror(ret_vminph.family, ret_vminph.path, ret_vminph.source),
        mirror(ret_vminsh.family, ret_vminsh.path, ret_vminsh.source),
        mirror(ret_vpopcntb.family, ret_vpopcntb.path, ret_vpopcntb.source),
        mirror(ret_vpopcntw.family, ret_vpopcntw.path, ret_vpopcntw.source),
        mirror(ret_vpopcntd.family, ret_vpopcntd.path, ret_vpopcntd.source),
        mirror(ret_vpopcntq.family, ret_vpopcntq.path, ret_vpopcntq.source),
        mirror(rpl_arpl.family, rpl_arpl.path, rpl_arpl.source),
        mirror(select_vpmultishiftqb.family, select_vpmultishiftqb.path, select_vpmultishiftqb.source),
        mirror(send_senduipi.family, send_senduipi.path, send_senduipi.source),
        mirror(serialize_serialize.family, serialize_serialize.path, serialize_serialize.source),
        mirror(enqueue_enqcmd.family, enqueue_enqcmd.path, enqueue_enqcmd.source),
        mirror(extr_bextr.family, extr_bextr.path, extr_bextr.source),
        mirror(extr_extractps.family, extr_extractps.path, extr_extractps.source),
        mirror(extr_fxtract.family, extr_fxtract.path, extr_fxtract.source),
        mirror(extr_pext.family, extr_pext.path, extr_pext.source),
        mirror(lock_lock.family, lock_lock.path, lock_lock.source),
        mirror(lock_xacquire.family, lock_xacquire.path, lock_xacquire.source),
        mirror(lock_xrelease.family, lock_xrelease.path, lock_xrelease.source),
        mirror(logical_nand_vptestnmb.family, logical_nand_vptestnmb.path, logical_nand_vptestnmb.source),
        mirror(logical_nand_vptestnmw.family, logical_nand_vptestnmw.path, logical_nand_vptestnmw.source),
        mirror(logical_nand_vptestnmd.family, logical_nand_vptestnmd.path, logical_nand_vptestnmd.source),
        mirror(logical_nand_vptestnmq.family, logical_nand_vptestnmq.path, logical_nand_vptestnmq.source),
        mirror(logical_or_korw.family, logical_or_korw.path, logical_or_korw.source),
        mirror(logical_or_korb.family, logical_or_korb.path, logical_or_korb.source),
        mirror(logical_or_korq.family, logical_or_korq.path, logical_or_korq.source),
        mirror(logical_or_kord.family, logical_or_kord.path, logical_or_kord.source),
        mirror(logical_or_por.family, logical_or_por.path, logical_or_por.source),
        mirror(logical_or_vpor.family, logical_or_vpor.path, logical_or_vpor.source),
        mirror(logical_or_vpord.family, logical_or_vpord.path, logical_or_vpord.source),
        mirror(logical_or_vporq.family, logical_or_vporq.path, logical_or_vporq.source),
        mirror(logical_xnor_kxnorw.family, logical_xnor_kxnorw.path, logical_xnor_kxnorw.source),
        mirror(logical_xnor_kxnorb.family, logical_xnor_kxnorb.path, logical_xnor_kxnorb.source),
        mirror(logical_xnor_kxnorq.family, logical_xnor_kxnorq.path, logical_xnor_kxnorq.source),
        mirror(logical_xnor_kxnord.family, logical_xnor_kxnord.path, logical_xnor_kxnord.source),
        mirror(neg_neg.family, neg_neg.path, neg_neg.source),
        mirror(round_frndint.family, round_frndint.path, round_frndint.source),
        mirror(encode_encodekey128.family, encode_encodekey128.path, encode_encodekey128.source),
        mirror(galois_gf2p8affineinvqb.family, galois_gf2p8affineinvqb.path, galois_gf2p8affineinvqb.source),
        mirror(galois_gf2p8affineqb.family, galois_gf2p8affineqb.path, galois_gf2p8affineqb.source),
        mirror(galois_gf2p8mulb.family, galois_gf2p8mulb.path, galois_gf2p8mulb.source),
        mirror(inc_dec_fdecstp.family, inc_dec_fdecstp.path, inc_dec_fdecstp.source),
        mirror(inc_dec_fincstp.family, inc_dec_fincstp.path, inc_dec_fincstp.source),
        mirror(initialize_finit.family, initialize_finit.path, initialize_finit.source),
        mirror(initialize_fninit.family, initialize_fninit.path, initialize_fninit.source),
        mirror(invalidate_invd.family, invalidate_invd.path, invalidate_invd.source),
        mirror(invalidate_invlpg.family, invalidate_invlpg.path, invalidate_invlpg.source),
        mirror(invalidate_invpcid.family, invalidate_invpcid.path, invalidate_invpcid.source),
        mirror(make_enter.family, make_enter.path, make_enter.source),
        mirror(repeat_rep.family, repeat_rep.path, repeat_rep.source),
        mirror(repeat_repe.family, repeat_repe.path, repeat_repe.source),
        mirror(repeat_repne.family, repeat_repne.path, repeat_repne.source),
        mirror(scatter_vpscatterdd.family, scatter_vpscatterdd.path, scatter_vpscatterdd.source),
        mirror(scatter_vpscatterdq.family, scatter_vpscatterdq.path, scatter_vpscatterdq.source),
        mirror(scatter_vpscatterqd.family, scatter_vpscatterqd.path, scatter_vpscatterqd.source),
        mirror(scatter_vpscatterqq.family, scatter_vpscatterqq.path, scatter_vpscatterqq.source),
        mirror(scatter_vscatterdps.family, scatter_vscatterdps.path, scatter_vscatterdps.source),
        mirror(scatter_vscatterdpd.family, scatter_vscatterdpd.path, scatter_vscatterdpd.source),
        mirror(scatter_vscatterqps.family, scatter_vscatterqps.path, scatter_vscatterqps.source),
        mirror(scatter_vscatterqpd.family, scatter_vscatterqpd.path, scatter_vscatterqpd.source),
        mirror(gather_vgatherdpd.family, gather_vgatherdpd.path, gather_vgatherdpd.source),
        mirror(gather_vgatherqpd.family, gather_vgatherqpd.path, gather_vgatherqpd.source),
        mirror(gather_vgatherdps.family, gather_vgatherdps.path, gather_vgatherdps.source),
        mirror(gather_vgatherqps.family, gather_vgatherqps.path, gather_vgatherqps.source),
        mirror(gather_vpgatherdd.family, gather_vpgatherdd.path, gather_vpgatherdd.source),
        mirror(gather_vpgatherdq.family, gather_vpgatherdq.path, gather_vpgatherdq.source),
        mirror(gather_vpgatherqd.family, gather_vpgatherqd.path, gather_vpgatherqd.source),
        mirror(gather_vpgatherqq.family, gather_vpgatherqq.path, gather_vpgatherqq.source),
        mirror(get_xgetbv.family, get_xgetbv.path, get_xgetbv.source),
        mirror(square_root_fsqrt.family, square_root_fsqrt.path, square_root_fsqrt.source),
        mirror(square_root_sqrtpd.family, square_root_sqrtpd.path, square_root_sqrtpd.source),
        mirror(square_root_sqrtps.family, square_root_sqrtps.path, square_root_sqrtps.source),
        mirror(table_xlat.family, table_xlat.path, table_xlat.source),
        mirror(table_xlatb.family, table_xlatb.path, table_xlatb.source),
        mirror(trig_fcos.family, trig_fcos.path, trig_fcos.source),
        mirror(trig_fsin.family, trig_fsin.path, trig_fsin.source),
        mirror(trig_fsincos.family, trig_fsincos.path, trig_fsincos.source),
        mirror(wait_wait.family, wait_wait.path, wait_wait.source),
        mirror(wait_mwait.family, wait_mwait.path, wait_mwait.source),
        mirror(write_ptwrite.family, write_ptwrite.path, write_ptwrite.source),
        mirror(write_wbinvd.family, write_wbinvd.path, write_wbinvd.source),
        mirror(write_wbnoinvd.family, write_wbnoinvd.path, write_wbnoinvd.source),
        mirror(write_wrfsbase.family, write_wrfsbase.path, write_wrfsbase.source),
        mirror(write_wrgsbase.family, write_wrgsbase.path, write_wrgsbase.source),
        mirror(write_wrmsr.family, write_wrmsr.path, write_wrmsr.source),
        mirror(write_wrpkru.family, write_wrpkru.path, write_wrpkru.source),
        mirror(absolute_fabs.family, absolute_fabs.path, absolute_fabs.source),
        mirror(absolute_pabsb.family, absolute_pabsb.path, absolute_pabsb.source),
        mirror(absolute_pabsd.family, absolute_pabsd.path, absolute_pabsd.source),
        mirror(absolute_pabsq.family, absolute_pabsq.path, absolute_pabsq.source),
        mirror(absolute_pabsw.family, absolute_pabsw.path, absolute_pabsw.source),
        mirror(absolute_vdbpsadbw.family, absolute_vdbpsadbw.path, absolute_vdbpsadbw.source),
        mirror(accumulate_crc32.family, accumulate_crc32.path, accumulate_crc32.source),
        mirror(reverse_fdivr.family, reverse_fdivr.path, reverse_fdivr.source),
        mirror(reverse_fdivrp.family, reverse_fdivrp.path, reverse_fdivrp.source),
        mirror(reverse_fidivr.family, reverse_fidivr.path, reverse_fidivr.source),
        mirror(reverse_fsubr.family, reverse_fsubr.path, reverse_fsubr.source),
        mirror(reverse_fsubrp.family, reverse_fsubrp.path, reverse_fsubrp.source),
        mirror(reverse_fisubr.family, reverse_fisubr.path, reverse_fisubr.source),
        mirror(scan_scas.family, scan_scas.path, scan_scas.source),
        mirror(scan_scasb.family, scan_scasb.path, scan_scasb.source),
        mirror(scan_scasw.family, scan_scasw.path, scan_scasw.source),
        mirror(scan_scasd.family, scan_scasd.path, scan_scasd.source),
        mirror(scan_scasq.family, scan_scasq.path, scan_scasq.source),
        mirror(compute_f2xm1.family, compute_f2xm1.path, compute_f2xm1.source),
        mirror(compute_fyl2x.family, compute_fyl2x.path, compute_fyl2x.source),
        mirror(compute_fyl2xp1.family, compute_fyl2xp1.path, compute_fyl2xp1.source),
        mirror(compute_psadbw.family, compute_psadbw.path, compute_psadbw.source),
        mirror(compute_mpsadbw.family, compute_mpsadbw.path, compute_mpsadbw.source),
        mirror(compute_rcpps.family, compute_rcpps.path, compute_rcpps.source),
        mirror(compute_rcpss.family, compute_rcpss.path, compute_rcpss.source),
        mirror(compute_rsqrtps.family, compute_rsqrtps.path, compute_rsqrtps.source),
        mirror(compute_rsqrtss.family, compute_rsqrtss.path, compute_rsqrtss.source),
        mirror(compute_sqrtsd.family, compute_sqrtsd.path, compute_sqrtsd.source),
        mirror(compute_sqrtss.family, compute_sqrtss.path, compute_sqrtss.source),
        mirror(compute_vp2intersect.family, compute_vp2intersect.path, compute_vp2intersect.source),
        mirror(zero_tilezero.family, zero_tilezero.path, zero_tilezero.source),
        mirror(zero_vzeroall.family, zero_vzeroall.path, zero_vzeroall.source),
        mirror(zero_vzeroupper.family, zero_vzeroupper.path, zero_vzeroupper.source),
        mirror(store_fbstp.family, store_fbstp.path, store_fbstp.source),
        mirror(store_fist.family, store_fist.path, store_fist.source),
        mirror(store_fistp.family, store_fistp.path, store_fistp.source),
        mirror(store_fisttp.family, store_fisttp.path, store_fisttp.source),
        mirror(store_fst.family, store_fst.path, store_fst.source),
        mirror(store_fstcw.family, store_fstcw.path, store_fstcw.source),
        mirror(store_fstenv.family, store_fstenv.path, store_fstenv.source),
        mirror(store_fstp.family, store_fstp.path, store_fstp.source),
        mirror(store_fstsw.family, store_fstsw.path, store_fstsw.source),
        mirror(store_maskmovdqu.family, store_maskmovdqu.path, store_maskmovdqu.source),
        mirror(store_maskmovq.family, store_maskmovq.path, store_maskmovq.source),
        mirror(store_sahf.family, store_sahf.path, store_sahf.source),
        mirror(store_sfence.family, store_sfence.path, store_sfence.source),
        mirror(store_sgdt.family, store_sgdt.path, store_sgdt.source),
        mirror(store_sldt.family, store_sldt.path, store_sldt.source),
        mirror(store_smsw.family, store_smsw.path, store_smsw.source),
        mirror(store_stmxcsr.family, store_stmxcsr.path, store_stmxcsr.source),
        mirror(store_stos.family, store_stos.path, store_stos.source),
        mirror(store_str.family, store_str.path, store_str.source),
        mirror(store_sttilecfg.family, store_sttilecfg.path, store_sttilecfg.source),
        mirror(store_tilestored.family, store_tilestored.path, store_tilestored.source),
        mirror(store_vcompresspd.family, store_vcompresspd.path, store_vcompresspd.source),
        mirror(store_vcompressps.family, store_vcompressps.path, store_vcompressps.source),
        mirror(store_vpcompressb.family, store_vpcompressb.path, store_vpcompressb.source),
        mirror(store_vpcompressd.family, store_vpcompressd.path, store_vpcompressd.source),
        mirror(store_vpcompressq.family, store_vpcompressq.path, store_vpcompressq.source),
        mirror(store_vpcompressw.family, store_vpcompressw.path, store_vpcompressw.source),
        mirror(arithmetic_vpaddb.family, arithmetic_vpaddb.path, arithmetic_vpaddb.source),
        mirror(arithmetic_vpaddd.family, arithmetic_vpaddd.path, arithmetic_vpaddd.source),
        mirror(arithmetic_vpaddq.family, arithmetic_vpaddq.path, arithmetic_vpaddq.source),
        mirror(arithmetic_vpaddw.family, arithmetic_vpaddw.path, arithmetic_vpaddw.source),
        mirror(atomic_cmpxchg.family, atomic_cmpxchg.path, atomic_cmpxchg.source),
        mirror(atomic_cmpxchg8b.family, atomic_cmpxchg8b.path, atomic_cmpxchg8b.source),
        mirror(atomic_cmpxchg16b.family, atomic_cmpxchg16b.path, atomic_cmpxchg16b.source),
        mirror(horizontal_vphaddd.family, horizontal_vphaddd.path, horizontal_vphaddd.source),
        mirror(horizontal_vphaddsw.family, horizontal_vphaddsw.path, horizontal_vphaddsw.source),
        mirror(horizontal_vphaddw.family, horizontal_vphaddw.path, horizontal_vphaddw.source),
        mirror(insert_extract_vpextrb.family, insert_extract_vpextrb.path, insert_extract_vpextrb.source),
        mirror(insert_extract_vpextrd.family, insert_extract_vpextrd.path, insert_extract_vpextrd.source),
        mirror(insert_extract_vpextrq.family, insert_extract_vpextrq.path, insert_extract_vpextrq.source),
        mirror(insert_extract_vpextrw.family, insert_extract_vpextrw.path, insert_extract_vpextrw.source),
        mirror(insert_extract_vextractf128.family, insert_extract_vextractf128.path, insert_extract_vextractf128.source),
        mirror(round_vroundpd.family, round_vroundpd.path, round_vroundpd.source),
        mirror(round_vroundps.family, round_vroundps.path, round_vroundps.source),
        mirror(round_vroundsd.family, round_vroundsd.path, round_vroundsd.source),
        mirror(round_vroundss.family, round_vroundss.path, round_vroundss.source),
        mirror(shuffle_vpshufd.family, shuffle_vpshufd.path, shuffle_vpshufd.source),
        mirror(unordered_vucomiss.family, unordered_vucomiss.path, unordered_vucomiss.source),
    };
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
    for (x86.tables) |table| validateTable(table);
}

pub fn validateTable(table: x86.InstructionTable) void {
    const meta = table.metadata();
    const mirror_table = findMirror(table.path) orelse {
        runtime_abi.isa.validateMissingNeonMirror(table.path);
        return;
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
    const closer: u8 = if (opener == '[') ']' else '}';
    var lines = std.mem.splitScalar(u8, source, '\n');
    var in_block = false;
    var count: usize = 0;
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripLineComment(raw_line), " \t\r");
        if (!in_block) {
            // Only the assignment named exactly "encodings" opens the block;
            // the opener must be on the same line ("encodings = [" or "encodings = {").
            const name = assignmentName(line) orelse continue;
            if (!std.mem.eql(u8, name, "encodings")) continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const rhs = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (rhs.len == 0 or rhs[0] != opener) continue;
            in_block = true;
            // Single-line block: encodings = [{ ... }]
            if (std.mem.indexOfScalar(u8, rhs, closer) != null) {
                var i: usize = 0;
                while (i < rhs.len) : (i += 1) {
                    if (rhs[i] == '{') count += 1;
                }
                return count;
            }
            continue;
        }
        // Inside the block: a line starting with '{' is one encoding row.
        if (std.mem.startsWith(u8, line, "{")) {
            count += 1;
            continue;
        }
        // The block ends at the closer line (e.g. "]" or "}" on its own line).
        if (line.len >= 1 and line[0] == closer) break;
    }
    return if (in_block) count else null;
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
