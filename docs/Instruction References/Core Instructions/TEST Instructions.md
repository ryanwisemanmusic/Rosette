FTST — TEST

Opcode		Mode	Leg Mode	Description
D9 E4				            Compare ST(0) with 0.0.

Description:

Compares the value in the ST(0) register with 0.0 and sets the condition code flags C0, C2, and C3 in the FPU status word according to the results (see table below).

Condition	C3	C2	C0
ST(0) > 0.0	0	0	0
ST(0) < 0.0	0	0	1
ST(0) = 0.0	1	0	0
Unordered	1	1	1
Table 3-40. FTST Results
This instruction performs an “unordered comparison.” An unordered comparison also checks the class of the numbers being compared (see “FXAM—Examine Floating-Point” in this chapter). If the value in register ST(0) is a NaN or is in an undefined format, the condition flags are set to “unordered” and the invalid operation exception is generated.

The sign of zero is ignored, so that (– 0.0 := +0.0).

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

CASE (relation of operands) OF
    Not comparable:
        C3, C2, C0 := 111;
    ST(0) > 0.0:
        C3, C2, C0 := 000;
    ST(0) < 0.0:
        C3, C2, C0 := 001;
    ST(0) = 0.0:
        C3, C2, C0 := 100;
ESAC;

FPU Flags Affected:

C1:
	Set to 0.
C0, C2, C3:
	See Table 3-40.

Floating-Point Exceptions:

#IS:
	Stack underflow occurred.
#IA:
	The source operand is a NaN value or is in an unsupported format.
#D:
	The source operand is a denormal value.

Protected Mode Exceptions:

#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#MF:
	If there is a pending x87 FPU exception.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.


KTESTW/KTESTB/KTESTQ/KTESTD — Packed Bit Test Masks and Set Flags

Opcode/Instruction	                    Op En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.L0.0F.W0 99 /r KTESTW k1, k2	    RR	    V/V	                    AVX512DQ	        Set ZF and CF depending on sign bit AND and ANDN of 16 bits mask register sources.
VEX.L0.66.0F.W0 99 /r KTESTB k1, k2	    RR	    V/V	                    AVX512DQ	        Set ZF and CF depending on sign bit AND and ANDN of 8 bits mask register sources.
VEX.L0.0F.W1 99 /r KTESTQ k1, k2	    RR	    V/V	                    AVX512BW	        Set ZF and CF depending on sign bit AND and ANDN of 64 bits mask register sources.
VEX.L0.66.0F.W1 99 /r KTESTD k1, k2	    RR	    V/V	                    AVX512BW	        Set ZF and CF depending on sign bit AND and ANDN of 32 bits mask register sources.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2
RR	    ModRM:reg (r)	ModRM:r/m (r, ModRM:[7:6] must be 11b)

Description:

Performs a bitwise comparison of the bits of the first source operand and corresponding bits in the second source operand. If the AND operation produces all zeros, the ZF is set else the ZF is clear. If the bitwise AND operation of the inverted first source operand with the second source operand produces all zeros the CF is set else the CF is clear. Only the EFLAGS register is updated.

Note: In VEX-encoded versions, VEX.vvvv is reserved and must be 1111b, otherwise instructions will #UD.

Operation:

KTESTW:

TEMP[15:0] := SRC2[15:0] AND SRC1[15:0]
IF (TEMP[15:0] = = 0)
    THEN ZF :=1;
    ELSE ZF := 0;
FI;
TEMP[15:0] := SRC2[15:0] AND NOT SRC1[15:0]
IF (TEMP[15:0] = = 0)
    THEN CF :=1;
    ELSE CF := 0;
FI;
AF := OF := PF := SF := 0;

KTESTB:

TEMP[7:0] := SRC2[7:0] AND SRC1[7:0]
IF (TEMP[7:0] = = 0)
    THEN ZF :=1;
    ELSE ZF := 0;
FI;
TEMP[7:0] := SRC2[7:0] AND NOT SRC1[7:0]
IF (TEMP[7:0] = = 0)
    THEN CF :=1;
    ELSE CF := 0;
FI;
AF := OF := PF := SF := 0;

KTESTQ:

TEMP[63:0] := SRC2[63:0] AND SRC1[63:0]
IF (TEMP[63:0] = = 0)
    THEN ZF :=1;
    ELSE ZF := 0;
FI;
TEMP[63:0] := SRC2[63:0] AND NOT SRC1[63:0]
IF (TEMP[63:0] = = 0)
    THEN CF :=1;
    ELSE CF := 0;
FI;
AF := OF := PF := SF := 0;

KTESTD:

TEMP[31:0] := SRC2[31:0] AND SRC1[31:0]
IF (TEMP[31:0] = = 0)
    THEN ZF :=1;
    ELSE ZF := 0;
FI;
TEMP[31:0] := SRC2[31:0] AND NOT SRC1[31:0]
IF (TEMP[31:0] = = 0)
    THEN CF :=1;
    ELSE CF := 0;
FI;
AF := OF := PF := SF := 0;

Intel C/C++ Compiler Intrinsic Equivalent:

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-63, “TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg).”


PTEST — Logical Compare

Opcode/Instruction	                                Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
66 0F 38 17 /r PTEST xmm1, xmm2/m128	            RM	    V/V	                    SSE4_1	            Set ZF if xmm2/m128 AND xmm1 result is all 0s. Set CF if xmm2/m128 AND NOT xmm1 result is all 0s.
VEX.128.66.0F38.WIG 17 /r VPTEST xmm1, xmm2/m128	RM	    V/V	                    AVX	                Set ZF and CF depending on bitwise AND and ANDN of sources.
VEX.256.66.0F38.WIG 17 /r VPTEST ymm1, ymm2/m256	RM	    V/V	                    AVX	                Set ZF and CF depending on bitwise AND and ANDN of sources.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r)	ModRM:r/m (r)	N/A	        N/A

Description:

PTEST and VPTEST set the ZF flag if all bits in the result are 0 of the bitwise AND of the first source operand (first operand) and the second source operand (second operand). VPTEST sets the CF flag if all bits in the result are 0 of the bitwise AND of the second source operand (second operand) and the logical NOT of the destination operand.

The first source register is specified by the ModR/M reg field.

128-bit versions: The first source register is an XMM register. The second source register can be an XMM register or a 128-bit memory location. The destination register is not modified.

VEX.256 encoded version: The first source register is a YMM register. The second source register can be a YMM register or a 256-bit memory location. The destination register is not modified.

Note: In VEX-encoded versions, VEX.vvvv is reserved and must be 1111b, otherwise instructions will #UD.

Operation:

(V)PTEST (128-bit Version):

IF (SRC[127:0] BITWISE AND DEST[127:0] = 0)
    THEN ZF := 1;
    ELSE ZF := 0;
IF (SRC[127:0] BITWISE AND NOT DEST[127:0] = 0)
    THEN CF := 1;
    ELSE CF := 0;
DEST (unmodified)
AF := OF := PF := SF := 0;

VPTEST (VEX.256 Encoded Version):

IF (SRC[255:0] BITWISE AND DEST[255:0] = 0) THEN ZF := 1;
    ELSE ZF := 0;
IF (SRC[255:0] BITWISE AND NOT DEST[255:0] = 0) THEN CF := 1;
    ELSE CF := 0;
DEST (unmodified)
AF := OF := PF := SF := 0;

Intel C/C++ Compiler Intrinsic Equivalent:

PTEST int _mm_testz_si128 (__m128i s1, __m128i s2);
PTEST int _mm_testc_si128 (__m128i s1, __m128i s2);
PTEST int _mm_testnzc_si128 (__m128i s1, __m128i s2);
VPTEST int _mm256_testz_si256 (__m256i s1, __m256i s2);
VPTEST int _mm256_testc_si256 (__m256i s1, __m256i s2);
VPTEST int _mm256_testnzc_si256 (__m256i s1, __m256i s2);
VPTEST int _mm_testz_si128 (__m128i s1, __m128i s2);
VPTEST int _mm_testc_si128 (__m128i s1, __m128i s2);
VPTEST int _mm_testnzc_si128 (__m128i s1, __m128i s2);

Flags Affected:

The OF, AF, PF, SF flags are cleared and the ZF, CF flags are set according to the operation.

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-21, “Type 4 Class Exception Conditions,” additionally:

#UD:
	If VEX.vvvv ≠ 1111B.


TEST — Logical Compare

Opcode	            Instruction	        Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
A8 ib	            TEST AL, imm8	    I	    Valid	        Valid	            AND imm8 with AL; set SF, ZF, PF according to result.
A9 iw	            TEST AX, imm16	    I	    Valid	        Valid	            AND imm16 with AX; set SF, ZF, PF according to result.
A9 id	            TEST EAX, imm32	    I	    Valid	        Valid	            AND imm32 with EAX; set SF, ZF, PF according to result.
REX.W + A9 id	    TEST RAX, imm32	    I	    Valid	        N.E.	            AND imm32 sign-extended to 64-bits with RAX; set SF, ZF, PF according to result.
F6 /0 ib	        TEST r/m8, imm8	    MI	    Valid	        Valid	            AND imm8 with r/m8; set SF, ZF, PF according to result.
REX + F6 /0 ib	    TEST r/m81, imm8	MI	    Valid	        N.E.	            AND imm8 with r/m8; set SF, ZF, PF according to result.
F7 /0 iw	        TEST r/m16, imm16	MI	    Valid	        Valid	            AND imm16 with r/m16; set SF, ZF, PF according to result.
F7 /0 id	        TEST r/m32, imm32	MI	    Valid	        Valid	            AND imm32 with r/m32; set SF, ZF, PF according to result.
REX.W + F7 /0 id	TEST r/m64, imm32	MI	    Valid	        N.E.	            AND imm32 sign-extended to 64-bits with r/m64; set SF, ZF, PF according to result.
84 /r	            TEST r/m8, r8	    MR	    Valid	        Valid	            AND r8 with r/m8; set SF, ZF, PF according to result.
REX + 84 /r	        TEST r/m81, r81	    MR	    Valid	        N.E.	            AND r8 with r/m8; set SF, ZF, PF according to result.
85 /r	            TEST r/m16, r16	    MR	    Valid	        Valid	            AND r16 with r/m16; set SF, ZF, PF according to result.
85 /r	            TEST r/m32, r32	    MR	    Valid	        Valid	            AND r32 with r/m32; set SF, ZF, PF according to result.
REX.W + 85 /r	    TEST r/m64, r64	    MR	    Valid	        N.E.	            AND r64 with r/m64; set SF, ZF, PF according to result.

1. In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
I	    AL/AX/EAX/RAX	imm8/16/32	    N/A	        N/A
MI	    ModRM:r/m (r)	imm8/16/32	    N/A     	N/A
MR	    ModRM:r/m (r)	ModRM:reg (r)	N/A     	N/A

Description:

Computes the bit-wise logical AND of first operand (source 1 operand) and the second operand (source 2 operand) and sets the SF, ZF, and PF status flags according to the result. The result is then discarded.

In 64-bit mode, using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

TEMP := SRC1 AND SRC2;
SF := MSB(TEMP);
IF TEMP = 0
    THEN ZF := 1;
    ELSE ZF := 0;
FI:
PF := BitwiseXNOR(TEMP[0:7]);
CF := 0;
OF := 0;
(* AF is undefined *)

Flags Affected:

The OF and CF flags are set to 0. The SF, ZF, and PF flags are set according to the result (see the “Operation” section above). The state of the AF flag is undefined.

Protected Mode Exceptions:

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register contains a NULL segment selector.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code):
	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS:
	If a memory operand effective address is outside the SS segment limit.
#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code)	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made.
#UD:
	If the LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#GP(0):
	If the memory address is in a non-canonical form.
#PF(fault-code)	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If the LOCK prefix is used.




TESTUI — Determine User Interrupt Flag

Opcode/Instruction	    Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
F3 0F 01 ED TESTUI	    ZO	    V/I	                    UINTR	            Copies the current value of UIF into EFLAGS.CF.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	    N/A	        N/A	        N/A	        N/A

TESTUI copies the current value of the user interrupt flag (UIF) into EFLAGS.CF. This instruction can be executed regardless of CPL.

TESTUI may be executed normally inside a transactional region.

Operation:

CF := UIF;
ZF := AF := OF := PF := SF := 0;

Flags Affected:

The ZF, OF, AF, PF, SF flags are cleared and the CF flags to the value of the user interrupt flag.

Protected Mode Exceptions:

#UD:
	The TESTUI instruction is not recognized in protected mode.

Real-Address Mode Exceptions:

#UD:
	The TESTUI instruction is not recognized in real-address mode.

Virtual-8086 Mode Exceptions:

#UD:
	The TESTUI instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

#UD:
	The TESTUI instruction is not recognized in compatibility mode.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If executed inside an enclave.
    If CR4.UINTR = 0.
    If CPUID.07H.0H:EDX.UINTR[bit 5] = 0.


VFPCLASSPD — Tests Types of Packed Float64 Values

Opcode/Instruction	                                                        Op/En	64/32 Bit Mode Support	CPUID Feature Flag	Description
EVEX.128.66.0F3A.W1 66 /r ib VFPCLASSPD k2 {k1}, xmm2/m128/m64bcst, imm8	A	    V/V	                    AVX512VL AVX512DQ	Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.
EVEX.256.66.0F3A.W1 66 /r ib VFPCLASSPD k2 {k1}, ymm2/m256/m64bcst, imm8	A	    V/V	                    AVX512VL AVX512DQ	Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.
EVEX.512.66.0F3A.W1 66 /r ib VFPCLASSPD k2 {k1}, zmm2/m512/m64bcst, imm8	A	    V/V	                    AVX512DQ	        Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.

Instruction Operand Encoding:

Op/En	Tuple Type	Operand 1	    Operand 2	Operand 3	Operand 4
A	    Full	    ModRM:reg (w)	ModRM:r/m (r)	N/A	    N/A

Description:

The FPCLASSPD instruction checks the packed double precision floating-point values for special categories, specified by the set bits in the imm8 byte. Each set bit in imm8 specifies a category of floating-point values that the input data element is classified against. The classified results of all specified categories of an input value are ORed together to form the final boolean result for the input element. The result of each element is written to the corresponding bit in a mask register k2 according to the writemask k1. Bits [MAX_KL-1:8/4/2] of the destination are cleared.

The classification categories specified by imm8 are shown in Figure 5-13. The classification test for each category is listed in Table 5-14.

Classifier Checks for Checks for Checks for Checks for Checks for Checks for Checks for Checks for QNaN +0 0 +INF INF Denormal Negative finite SNaN

The source operand is a ZMM/YMM/XMM register, a 512/256/128-bit memory location, or a 512/256/128-bit vector broadcasted from a 64-bit memory location.

EVEX.vvvv is reserved and must be 1111b otherwise instructions will #UD.

Operation:

CheckFPClassDP (tsrc[63:0], imm8[7:0]){
    //* Start checking the source operand for special type *//
    NegNum :=tsrc[63];
    IF (tsrc[62:52]=07FFh) Then ExpAllOnes := 1; FI;
    IF (tsrc[62:52]=0h) Then ExpAllZeros := 1;
    IF (ExpAllZeros AND MXCSR.DAZ) Then
        MantAllZeros := 1;
    ELSIF (tsrc[51:0]=0h) Then
        MantAllZeros := 1;
    FI;
    ZeroNumber := ExpAllZeros AND MantAllZeros
    SignalingBit := tsrc[51];
    sNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND NOT(SignalingBit); // sNaN
    qNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND SignalingBit; // qNaN
    Pzero_res := NOT(NegNum) AND ExpAllZeros AND MantAllZeros; // +0
    Nzero_res := NegNum AND ExpAllZeros AND MantAllZeros; // -0
    PInf_res := NOT(NegNum) AND ExpAllOnes AND MantAllZeros; // +Inf
    NInf_res := NegNum AND ExpAllOnes AND MantAllZeros; // -Inf
    Denorm_res := ExpAllZeros AND NOT(MantAllZeros); // denorm
    FinNeg_res := NegNum AND NOT(ExpAllOnes) AND NOT(ZeroNumber); // -finite
    bResult = ( imm8[0] AND qNaN_res ) OR (imm8[1] AND Pzero_res ) OR
            ( imm8[2] AND Nzero_res ) OR ( imm8[3] AND PInf_res ) OR
            ( imm8[4] AND NInf_res ) OR ( imm8[5] AND Denorm_res ) OR
            ( imm8[6] AND FinNeg_res ) OR ( imm8[7] AND sNaN_res );
    Return bResult;
} //* end of CheckFPClassDP() *//

VFPCLASSPD (EVEX Encoded versions):

(KL, VL) = (2, 128), (4, 256), (8, 512)
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no writemask*
        THEN
            IF (EVEX.b == 1) AND (SRC *is memory*)
                THEN
                    DEST[j] := CheckFPClassDP(SRC1[63:0], imm8[7:0]);
                ELSE
                    DEST[j] := CheckFPClassDP(SRC1[i+63:i], imm8[7:0]);
            FI;
        ELSE DEST[j] := 0
                        ; zeroing-masking only
    FI;
ENDFOR
DEST[MAX_KL-1:KL] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VFPCLASSPD __mmask8 _mm512_fpclass_pd_mask( __m512d a, int c);
VFPCLASSPD __mmask8 _mm512_mask_fpclass_pd_mask( __mmask8 m, __m512d a, int c)
VFPCLASSPD __mmask8 _mm256_fpclass_pd_mask( __m256d a, int c)
VFPCLASSPD __mmask8 _mm256_mask_fpclass_pd_mask( __mmask8 m, __m256d a, int c)
VFPCLASSPD __mmask8 _mm_fpclass_pd_mask( __m128d a, int c)
VFPCLASSPD __mmask8 _mm_mask_fpclass_pd_mask( __mmask8 m, __m128d a, int c)

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-49, “Type E4 Class Exception Conditions.”

Additionally:

#UD:
	If EVEX.vvvv != 1111B.



VFPCLASSPH — Test Types of Packed FP16 Values

Opcode/Instruction	                                                        Op/En	64/32 Bit Mode Support	CPUID Feature Flag	    Description
EVEX.128.NP.0F3A.W0 66 /r /ib VFPCLASSPH k1{k2}, xmm1/m128/m16bcst, imm8	A	    V/V	                    AVX512-FP16 AVX512VL	Test the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bitforeachofthesecategorytests. Themasked test results are OR-ed together to form a mask result.
EVEX.256.NP.0F3A.W0 66 /r /ib VFPCLASSPH k1{k2}, ymm1/m256/m16bcst, imm8	A	    V/V	                    AVX512-FP16 AVX512VL	Test the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bitforeachofthesecategorytests. Themasked test results are OR-ed together to form a mask result.
EVEX.512.NP.0F3A.W0 66 /r /ib VFPCLASSPH k1{k2}, zmm1/m512/m16bcst, imm8	A	    V/V	                    AVX512-FP16	            Test the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bitforeachofthesecategorytests. Themasked test results are OR-ed together to form a mask result.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	    Operand 2	    Operand 3	Operand 4
A	    Full	ModRM:reg (w)	ModRM:r/m (r)	imm8 (r)	N/A

Description:

This instruction checks the packed FP16 values in the source operand for special categories, specified by the set bits in the imm8 byte. Each set bit in imm8 specifies a category of floating-point values that the input data element is classified against; see Table 5-9 for the categories. The classified results of all specified categories of an input value are ORed together to form the final boolean result for the input element. The result is written to the corresponding bits in the destination mask register according to the writemask.

Bits	    Category	Classifier
imm8[0]	    QNAN	    Checks for QNAN
imm8[1]	    PosZero	    Checks +0
imm8[2]	    NegZero	    Checks for -0
imm8[3]	    PosINF	    Checks for +∞
imm8[4]	    NegINF	    Checks for −∞
imm8[5]	    Denormal	Checks for Denormal
imm8[6]	    Negative	Checks for Negative finite
imm8[7]	    SNAN	    Checks for SNAN

Table 5-9. Classifier Operations for VFPCLASSPH/VFPCLASSSH

Operation:

def check_fp_class_fp16(tsrc, imm8):
    negative := tsrc[15]
    exponent_all_ones := (tsrc[14:10] == 0x1F)
    exponent_all_zeros := (tsrc[14:10] == 0)
    mantissa_all_zeros := (tsrc[9:0] == 0)
    zero := exponent_all_zeros and mantissa_all_zeros
    signaling_bit := tsrc[9]
    snan := exponent_all_ones and not(mantissa_all_zeros) and not(signaling_bit)
    qnan := exponent_all_ones and not(mantissa_all_zeros) and signaling_bit
    positive_zero := not(negative) and zero
    negative_zero := negative and zero
    positive_infinity := not(negative) and exponent_all_ones and mantissa_all_zeros
    negative_infinity := negative and exponent_all_ones and mantissa_all_zeros
    denormal := exponent_all_zeros and not(mantissa_all_zeros)
    finite_negative := negative and not(exponent_all_ones) and not(zero)
    return (imm8[0] and qnan) OR
        (imm8[1] and positive_zero) OR
        (imm8[2] and negative_zero) OR
        (imm8[3] and positive_infinity) OR
        (imm8[4] and negative_infinity) OR
        (imm8[5] and denormal) OR
        (imm8[6] and finite_negative) OR
        (imm8[7] and snan)
        
VFPCLASSPH dest{k2}, src, imm8:

VL = 128, 256 or 512
KL := VL/16
FOR i := 0 to KL-1:
    IF k2[i] or *no writemask*:
        IF SRC is memory and (EVEX.b = 1):
            tsrc := SRC.fp16[0]
        ELSE:
            tsrc := SRC.fp16[i]
        DEST.bit[i] := check_fp_class_fp16(tsrc, imm8)
    ELSE:
        DEST.bit[i] := 0
DEST[MAXKL-1:kl] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VFPCLASSPH __mmask8 _mm_fpclass_ph_mask (__m128h a, int imm8);
VFPCLASSPH __mmask8 _mm_mask_fpclass_ph_mask (__mmask8 k1, __m128h a, int imm8);
VFPCLASSPH __mmask16 _mm256_fpclass_ph_mask (__m256h a, int imm8);
VFPCLASSPH __mmask16 _mm256_mask_fpclass_ph_mask (__mmask16 k1, __m256h a, int imm8);
VFPCLASSPH __mmask32 _mm512_fpclass_ph_mask (__m512h a, int imm8);
VFPCLASSPH __mmask32 _mm512_mask_fpclass_ph_mask (__mmask32 k1, __m512h a, int imm8);

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

EVEX-encoded instructions, see Table 2-49, “Type E4 Class Exception Conditions.”



FPCLASSPS — Tests Types of Packed Float32 Values

Opcode/Instruction	                                                        Op/En	64/32 Bit Mode Support	CPUID Feature Flag	Description
EVEX.128.66.0F3A.W0 66 /r ib VFPCLASSPS k2 {k1}, xmm2/m128/m32bcst, imm8	A	    V/V	A                   VX512VL AVX512DQ	Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.
EVEX.256.66.0F3A.W0 66 /r ib VFPCLASSPS k2 {k1}, ymm2/m256/m32bcst, imm8	A	    V/V	                    AVX512VL AVX512DQ	Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.
EVEX.512.66.0F3A.W0 66 /r ib VFPCLASSPS k2 {k1}, zmm2/m512/m32bcst, imm8	A	    V/V	                    AVX512DQ	        Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.

Instruction Operand Encoding:

Op/En	Tuple Type	Operand 1	    Operand 2	    Operand 3	Operand 4
A	    Full	    ModRM:reg (w)	ModRM:r/m (r)	N/A	        N/A

Description:

The FPCLASSPS instruction checks the packed single-precision floating-point values for special categories, specified by the set bits in the imm8 byte. Each set bit in imm8 specifies a category of floating-point values that the input data element is classified against. The classified results of all specified categories of an input value are ORed together to form the final boolean result for the input element. The result of each element is written to the corresponding bit in a mask register k2 according to the writemask k1. Bits [MAX_KL-1:16/8/4] of the destination are cleared.

The classification categories specified by imm8 are shown in Figure 5-13. The classification test for each category is listed in Table 5-14.

The source operand is a ZMM/YMM/XMM register, a 512/256/128-bit memory location, or a 512/256/128-bit vector broadcasted from a 32-bit memory location.

EVEX.vvvv is reserved and must be 1111b otherwise instructions will #UD.

Operation:

CheckFPClassSP (tsrc[31:0], imm8[7:0]){
    //* Start checking the source operand for special type *//
    NegNum :=tsrc[31];
    IF (tsrc[30:23]=0FFh) Then ExpAllOnes := 1; FI;
    IF (tsrc[30:23]=0h) Then ExpAllZeros := 1;
    IF (ExpAllZeros AND MXCSR.DAZ) Then
        MantAllZeros := 1;
    ELSIF (tsrc[22:0]=0h) Then
        MantAllZeros := 1;
    FI;
    ZeroNumber= ExpAllZeros AND MantAllZeros
    SignalingBit= tsrc[22];
    sNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND NOT(SignalingBit); // sNaN
    qNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND SignalingBit; // qNaN
    Pzero_res := NOT(NegNum) AND ExpAllZeros AND MantAllZeros; // +0
    Nzero_res := NegNum AND ExpAllZeros AND MantAllZeros; // -0
    PInf_res := NOT(NegNum) AND ExpAllOnes AND MantAllZeros; // +Inf
    NInf_res := NegNum AND ExpAllOnes AND MantAllZeros; // -Inf
    Denorm_res := ExpAllZeros AND NOT(MantAllZeros); // denorm
    FinNeg_res := NegNum AND NOT(ExpAllOnes) AND NOT(ZeroNumber); // -finite
    bResult = ( imm8[0] AND qNaN_res ) OR (imm8[1] AND Pzero_res ) OR
            ( imm8[2] AND Nzero_res ) OR ( imm8[3] AND PInf_res ) OR
            ( imm8[4] AND NInf_res ) OR ( imm8[5] AND Denorm_res ) OR
            ( imm8[6] AND FinNeg_res ) OR ( imm8[7] AND sNaN_res );
    Return bResult;
} //* end of CheckSPClassSP() *//

VFPCLASSPS (EVEX encoded versions):

(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no writemask*
        THEN
            IF (EVEX.b == 1) AND (SRC *is memory*)
                THEN
                    DEST[j] := CheckFPClassDP(SRC1[31:0], imm8[7:0]);
                ELSE
                    DEST[j] := CheckFPClassDP(SRC1[i+31:i], imm8[7:0]);
            FI;
        ELSE DEST[j] := 0 ; zeroing-masking only
    FI;
ENDFOR
DEST[MAX_KL-1:KL] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VFPCLASSPS __mmask16 _mm512_fpclass_ps_mask( __m512 a, int c);
VFPCLASSPS __mmask16 _mm512_mask_fpclass_ps_mask( __mmask16 m, __m512 a, int c)
VFPCLASSPS __mmask8 _mm256_fpclass_ps_mask( __m256 a, int c)
VFPCLASSPS __mmask8 _mm256_mask_fpclass_ps_mask( __mmask8 m, __m256 a, int c)
VFPCLASSPS __mmask8 _mm_fpclass_ps_mask( __m128 a, int c)
VFPCLASSPS __mmask8 _mm_mask_fpclass_ps_mask( __mmask8 m, __m128 a, int c)

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-49, “Type E4 Class Exception Conditions.”

Additionally:

#UD:
	If EVEX.vvvv != 1111B.

VFPCLASSSD — Tests Type of a Scalar Float64 Value

Opcode/Instruction	                                                Op/En	64/32 Bit Mode Support	CPUID Feature Flag	Description
EVEX.LLIG.66.0F3A.W1 67 /r ib VFPCLASSSD k2 {k1}, xmm2/m64, imm8	A	    V/V	                    AVX512DQ	        Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.

Instruction Operand Encoding:

Op/En	Tuple Type	    Operand 1	    Operand 2	    Operand 3	Operand 4
A	    Tuple1 Scalar	ModRM:reg (w)	ModRM:r/m (r)	N/A	        N/A

Description:

The FPCLASSSD instruction checks the low double precision floating-point value in the source operand for special categories, specified by the set bits in the imm8 byte. Each set bit in imm8 specifies a category of floating-point values that the input data element is classified against. The classified results of all specified categories of an input value are ORed together to form the final boolean result for the input element. The result is written to the low bit in a mask register k2 according to the writemask k1. Bits MAX_KL-1: 1 of the destination are cleared.

The classification categories specified by imm8 are shown in Figure 5-13. The classification test for each category is listed in Table 5-14.

EVEX.vvvv is reserved and must be 1111b otherwise instructions will #UD.

Operation:

CheckFPClassDP (tsrc[63:0], imm8[7:0]){
    NegNum :=tsrc[63];
    IF (tsrc[62:52]=07FFh) Then ExpAllOnes := 1; FI;
    IF (tsrc[62:52]=0h) Then ExpAllZeros := 1;
    IF (ExpAllZeros AND MXCSR.DAZ) Then
        MantAllZeros := 1;
    ELSIF (tsrc[51:0]=0h) Then
        MantAllZeros := 1;
    FI;
    ZeroNumber := ExpAllZeros AND MantAllZeros
    SignalingBit := tsrc[51];
    sNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND NOT(SignalingBit); // sNaN
    qNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND SignalingBit; // qNaN
    Pzero_res := NOT(NegNum) AND ExpAllZeros AND MantAllZeros; // +0
    Nzero_res := NegNum AND ExpAllZeros AND MantAllZeros; // -0
    PInf_res := NOT(NegNum) AND ExpAllOnes AND MantAllZeros; // +Inf
    NInf_res := NegNum AND ExpAllOnes AND MantAllZeros; // -Inf
    Denorm_res := ExpAllZeros AND NOT(MantAllZeros); // denorm
    FinNeg_res := NegNum AND NOT(ExpAllOnes) AND NOT(ZeroNumber); // -finite
    bResult = ( imm8[0] AND qNaN_res ) OR (imm8[1] AND Pzero_res ) OR
            ( imm8[2] AND Nzero_res ) OR ( imm8[3] AND PInf_res ) OR
            ( imm8[4] AND NInf_res ) OR ( imm8[5] AND Denorm_res ) OR
            ( imm8[6] AND FinNeg_res ) OR ( imm8[7] AND sNaN_res );
    Return bResult;
} //* end of CheckFPClassDP() *//

VFPCLASSSD (EVEX encoded version):

IF k1[0] OR *no writemask*
    THEN DEST[0] :=
        CheckFPClassDP(SRC1[63:0], imm8[7:0])
    ELSE DEST[0] := 0 ; zeroing-masking only
FI;
DEST[MAX_KL-1:1] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VFPCLASSSD __mmask8 _mm_fpclass_sd_mask( __m128d a, int c)
VFPCLASSSD __mmask8 _mm_mask_fpclass_sd_mask( __mmask8 m, __m128d a, int c)

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-53, “Type E6 Class Exception Conditions.”

Additionally:

#UD	If EVEX.vvvv != 1111B.

VFPCLASSSH — Test Types of Scalar FP16 Values

Opcode/Instruction	                                                Op/En	64/32 Bit Mode Support	CPUID Feature Flag	Description
EVEX.LLIG.NP.0F3A.W0 67 /r /ib VFPCLASSSH k1{k2}, xmm1/m16, imm8	A	    V/V	                    AVX512-FP16	        Test the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	    Operand 2	    Operand 3	Operand 4
A	    Scalar	ModRM:reg (w)	ModRM:r/m (r)	imm8 (r)	N/A

Description:

This instruction checks the low FP16 value in the source operand for special categories, specified by the set bits in the imm8 byte. Each set bit in imm8 specifies a category of floating-point values that the input data element is classified against; see Table 5-9 for the categories. The classified results of all specified categories of an input value are ORed together to form the final boolean result for the input element. The result is written to the low bit in the destination mask register according to the writemask. The other bits in the destination mask register are zeroed.

Operation:

VFPCLASSSH dest{k2}, src, imm8:

IF k2[0] or *no writemask*:
    DEST.bit[0] := check_fp_class_fp16(src.fp16[0], imm8)
        // see VFPCLASSPH
ELSE:
    DEST.bit[0] := 0
DEST[MAXKL-1:1] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VFPCLASSSH __mmask8 _mm_fpclass_sh_mask (__m128h a, int imm8);
VFPCLASSSH __mmask8 _mm_mask_fpclass_sh_mask (__mmask8 k1, __m128h a, int imm8);

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

EVEX-encoded instructions, see Table 2-58, “Type E10 Class Exception Conditions.”


VFPCLASSSS — Tests Type of a Scalar Float32 Value

Opcode/Instruction	                                            Op/En	64/32 Bit Mode Support	CPUID Feature Flag	Description
EVEX.LLIG.66.0F3A.W0 67 /r VFPCLASSSS k2 {k1}, xmm2/m32, imm8	A	    V/V	                    AVX512DQ	        Tests the input for the following categories: NaN, +0, -0, +Infinity, -Infinity, denormal, finite negative. The immediate field provides a mask bit for each of these category tests. The masked test results are OR-ed together to form a mask result.

Instruction Operand Encoding:

Op/En	Tuple Type	    Operand 1	    Operand 2	    Operand 3	Operand 4
A	    Tuple1 Scalar	ModRM:reg (w)	ModRM:r/m (r)	N/A	        N/A

Description:

The FPCLASSSS instruction checks the low single-precision floating-point value in the source operand for special categories, specified by the set bits in the imm8 byte. Each set bit in imm8 specifies a category of floating-point values that the input data element is classified against. The classified results of all specified categories of an input value are ORed together to form the final boolean result for the input element. The result is written to the low bit in a mask register k2 according to the writemask k1. Bits MAX_KL-1: 1 of the destination are cleared.

The classification categories specified by imm8 are shown in Figure 5-13. The classification test for each category is listed in Table 5-14.

EVEX.vvvv is reserved and must be 1111b otherwise instructions will #UD.

Operation:

CheckFPClassSP (tsrc[31:0], imm8[7:0]){
    //* Start checking the source operand for special type *//
    NegNum :=tsrc[31];
    IF (tsrc[30:23]=0FFh) Then ExpAllOnes := 1; FI;
    IF (tsrc[30:23]=0h) Then ExpAllZeros := 1;
    IF (ExpAllZeros AND MXCSR.DAZ) Then
        MantAllZeros := 1;
    ELSIF (tsrc[22:0]=0h) Then
        MantAllZeros := 1;
    FI;
    ZeroNumber= ExpAllZeros AND MantAllZeros
    SignalingBit= tsrc[22];
    sNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND NOT(SignalingBit); // sNaN
    qNaN_res := ExpAllOnes AND NOT(MantAllZeros) AND SignalingBit; // qNaN
    Pzero_res := NOT(NegNum) AND ExpAllZeros AND MantAllZeros; // +0
    Nzero_res := NegNum AND ExpAllZeros AND MantAllZeros; // -0
    PInf_res := NOT(NegNum) AND ExpAllOnes AND MantAllZeros; // +Inf
    NInf_res := NegNum AND ExpAllOnes AND MantAllZeros; // -Inf
    Denorm_res := ExpAllZeros AND NOT(MantAllZeros); // denorm
    FinNeg_res := NegNum AND NOT(ExpAllOnes) AND NOT(ZeroNumber); // -finite
    bResult = ( imm8[0] AND qNaN_res ) OR (imm8[1] AND Pzero_res ) OR
            ( imm8[2] AND Nzero_res ) OR ( imm8[3] AND PInf_res ) OR
            ( imm8[4] AND NInf_res ) OR ( imm8[5] AND Denorm_res ) OR
            ( imm8[6] AND FinNeg_res ) OR ( imm8[7] AND sNaN_res );
    Return bResult;
} //* end of CheckSPClassSP() *//

VFPCLASSSS (EVEX encoded version):

IF k1[0] OR *no writemask*
    THEN DEST[0] :=
        CheckFPClassSP(SRC1[31:0], imm8[7:0])
    ELSE DEST[0] := 0 ; zeroing-masking only
FI;
DEST[MAX_KL-1:1] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VFPCLASSSS __mmask8 _mm_fpclass_ss_mask( __m128 a, int c)
VFPCLASSSS __mmask8 _mm_mask_fpclass_ss_mask( __mmask8 m, __m128 a, int c)

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-53, “Type E6 Class Exception Conditions.”

Additionally:

#UD:
	If EVEX.vvvv != 1111B.




VTESTPD/VTESTPS — Packed Bit Test

Opcode/Instruction	                                Op /En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.128.66.0F38.W0 0E /r VTESTPS xmm1, xmm2/m128	RM	    V/V	                    AVX	                Set ZF and CF depending on sign bit AND and ANDN of packed single-precision floating-point sources.
VEX.256.66.0F38.W0 0E /r VTESTPS ymm1, ymm2/m256	RM	    V/V	                    AVX	                Set ZF and CF depending on sign bit AND and ANDN of packed single-precision floating-point sources.
VEX.128.66.0F38.W0 0F /r VTESTPD xmm1, xmm2/m128	RM	    V/V	                    AVX	                Set ZF and CF depending on sign bit AND and ANDN of packed double precision floating-point sources.
VEX.256.66.0F38.W0 0F /r VTESTPD ymm1, ymm2/m256	RM	    V/V	                    AVX	                Set ZF and CF depending on sign bit AND and ANDN of packed double precision floating-point sources.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r)	ModRM:r/m (r)	N/A	        N/A

Description:

VTESTPS performs a bitwise comparison of all the sign bits of the packed single-precision elements in the first source operation and corresponding sign bits in the second source operand. If the AND of the source sign bits with the dest sign bits produces all zeros, the ZF is set else the ZF is clear. If the AND of the source sign bits with the inverted dest sign bits produces all zeros the CF is set else the CF is clear. An attempt to execute VTESTPS with VEX.W=1 will cause #UD.

VTESTPD performs a bitwise comparison of all the sign bits of the double precision elements in the first source operation and corresponding sign bits in the second source operand. If the AND of the source sign bits with the dest sign bits produces all zeros, the ZF is set else the ZF is clear. If the AND the source sign bits with the inverted dest sign bits produces all zeros the CF is set else the CF is clear. An attempt to execute VTESTPS with VEX.W=1 will cause #UD.

The first source register is specified by the ModR/M reg field.

128-bit version: The first source register is an XMM register. The second source register can be an XMM register or a 128-bit memory location. The destination register is not modified.

VEX.256 encoded version: The first source register is a YMM register. The second source register can be a YMM register or a 256-bit memory location. The destination register is not modified.

Note: In VEX-encoded versions, VEX.vvvv is reserved and must be 1111b, otherwise instructions will #UD.

Operation:

VTESTPS (128-bit version):

TEMP[127:0] := SRC[127:0] AND DEST[127:0]
IF (TEMP[31] = TEMP[63] = TEMP[95] = TEMP[127] = 0)
    THEN ZF := 1;
    ELSE ZF := 0;
TEMP[127:0] := SRC[127:0] AND NOT DEST[127:0]
IF (TEMP[31] = TEMP[63] = TEMP[95] = TEMP[127] = 0)
    THEN CF := 1;
    ELSE CF := 0;
DEST (unmodified)
AF := OF := PF := SF := 0;

VTESTPS (VEX.256 encoded version):

TEMP[255:0] := SRC[255:0] AND DEST[255:0]
IF (TEMP[31] = TEMP[63] = TEMP[95] = TEMP[127]= TEMP[160] =TEMP[191] = TEMP[224] = TEMP[255] = 0)
    THEN ZF := 1;
    ELSE ZF := 0;
TEMP[255:0] := SRC[255:0] AND NOT DEST[255:0]
IF (TEMP[31] = TEMP[63] = TEMP[95] = TEMP[127]= TEMP[160] =TEMP[191] = TEMP[224] = TEMP[255] = 0)
    THEN CF := 1;
    ELSE CF := 0;
DEST (unmodified)
AF := OF := PF := SF := 0;

VTESTPD (128-bit version):

TEMP[127:0] := SRC[127:0] AND DEST[127:0]
IF ( TEMP[63] = TEMP[127] = 0)
    THEN ZF := 1;
    ELSE ZF := 0;
TEMP[127:0] := SRC[127:0] AND NOT DEST[127:0]
IF ( TEMP[63] = TEMP[127] = 0)
    THEN CF := 1;
    ELSE CF := 0;
DEST (unmodified)
AF := OF := PF := SF := 0;

VTESTPD (VEX.256 encoded version):

TEMP[255:0] := SRC[255:0] AND DEST[255:0]
IF (TEMP[63] = TEMP[127] = TEMP[191] = TEMP[255] = 0)
    THEN ZF := 1;
    ELSE ZF := 0;
TEMP[255:0] := SRC[255:0] AND NOT DEST[255:0]
IF (TEMP[63] = TEMP[127] = TEMP[191] = TEMP[255] = 0)
    THEN CF := 1;
    ELSE CF := 0;
DEST (unmodified)
AF := OF := PF := SF := 0;

Intel C/C++ Compiler Intrinsic Equivalent:

VTESTPS int _mm256_testz_ps (__m256 s1, __m256 s2);
int _mm256_testc_ps (__m256 s1, __m256 s2);
int _mm256_testnzc_ps (__m256 s1, __m128 s2);
int _mm_testz_ps (__m128 s1, __m128 s2);
int _mm_testc_ps (__m128 s1, __m128 s2);
int _mm_testnzc_ps (__m128 s1, __m128 s2);
VTESTPD int _mm256_testz_pd (__m256d s1, __m256d s2);
int _mm256_testc_pd (__m256d s1, __m256d s2);
int _mm256_testnzc_pd (__m256d s1, __m256d s2);
int _mm_testz_pd (__m128d s1, __m128d s2);
int _mm_testc_pd (__m128d s1, __m128d s2);
int _mm_testnzc_pd (__m128d s1, __m128d s2);

Flags Affected:

The OF, AF, PF, SF flags are cleared and the ZF, CF flags are set according to the operation.

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-21, “Type 4 Class Exception Conditions.”

Additionally:

#UD:
	If VEX.vvvv ≠ 1111B.
    If VEX.W = 1 for VTESTPS or VTESTPD.


XTEST — Test if in Transactional Execution

Opcode/Instruction	Op/En	64/32bit Mode Support	CPUID Feature Flag	Description
NP 0F 01 D6 XTEST	ZO	    V/V	                    HLE or RTM	        Test if executing in a transactional region.

Instruction Operand Encoding:

Op/En	Operand 1	Operand2	Operand3	Operand4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

The XTEST instruction queries the transactional execution status. If the instruction executes inside a transactionally executing RTM region or a transactionally executing HLE region, then the ZF flag is cleared, else it is set.

Operation:

XTEST:

IF (RTM_ACTIVE = 1 OR HLE_ACTIVE = 1)
    THEN
        ZF := 0
    ELSE
        ZF := 1
FI;

Flags Affected:

The ZF flag is cleared if the instruction is executed transactionally; otherwise it is set to 1. The CF, OF, SF, PF, and AF, flags are cleared.

Intel C/C++ Compiler Intrinsic Equivalent:

XTEST int _xtest( void );

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

#UD:
	CPUID.(EAX=7, ECX=0):EBX.HLE[bit 4] = 0 and CPUID.(EAX=7, ECX=0):EBX.RTM[bit 11] = 0.
    If LOCK prefix is used.
