https://www.felixcloutier.com/x86/
ADC — Add With Carry
Opcode	            Instruction	        Op/En	64-bit Mode     Compat/Leg Mode     Description
14 ib	            ADC AL, imm8	    I	    Valid           Valid	            Add with carry imm8 to AL.
15 iw	            ADC AX, imm16	    I	    Valid           Valid	            Add with carry imm16 to AX.
15 id	            ADC EAX, imm32	    I	    Valid           Valid	            Add with carry imm32 to EAX.
REX.W + 15 id	    ADC RAX, imm32	    I	    Valid           N.E.	            Add with carry imm32 sign extended to 64-bits to RAX.
80 /2 ib	        ADC r/m8, imm8	    MI	    Valid           Valid	            Add with carry imm8 to r/m8.
REX + 80 /2 ib	    ADC r/m8*, imm8	    MI	    Valid           N.E.	            Add with carry imm8 to r/m8.
81 /2 iw	        ADC r/m16, imm16    MI	    Valid           Valid	            Add with carry imm16 to r/m16.
81 /2 id	        ADC r/m32, imm32    MI	    Valid           Valid	            Add with CF imm32 to r/m32.
REX.W + 81 /2 id	ADC r/m64, imm32	MI	    Valid           N.E.	            Add with CF imm32 sign extended to 64-bits to r/m64.
83 /2 ib	        ADC r/m16, imm8	    MI	    Valid	        Valid	            Add with CF sign-extended imm8 to r/m16.
83 /2 ib	        ADC r/m32, imm8	    MI	    Valid	        Valid	            Add with CF sign-extended imm8 into r/m32.
REX.W + 83 /2 ib	ADC r/m64, imm8	    MI	    Valid	        N.E.	            Add with CF sign-extended imm8 into r/m64.
10 /r	            ADC r/m8, r8	    MR	    Valid	        Valid	            Add with carry byte register to r/m8.
REX + 10 /r	        ADC r/m8*, r8*	    MR	    Valid	        N.E.	            Add with carry byte register to r/m64.
11 /r	            ADC r/m16, r16	    MR	    Valid	        Valid	            Add with carry r16 to r/m16.
11 /r	            ADC r/m32, r32	    MR	    Valid	        Valid	            Add with CF r32 to r/m32.
REX.W + 11 /r	    ADC r/m64, r64	    MR	    Valid	        N.E.	            Add with CF r64 to r/m64.
12 /r	            ADC r8, r/m8	    RM	    Valid	        Valid	            Add with carry r/m8 to byte register.
REX + 12 /r	        ADC r8*, r/m8*	    RM	    Valid	        N.E.	            Add with carry r/m64 to byte register.
13 /r	            ADC r16, r/m16	    RM	    Valid	        Valid	            Add with carry r/m16 to r16.
13 /r	            ADC r32, r/m32	    RM	    Valid	        Valid	            Add with CF r/m32 to r32.
REX.W + 13 /r	    ADC r64, r/m64	    RM	    Valid	        N.E.	            Add with CF r/m64 to r64.

*In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	        N/A
MR	    ModRM:r/m (r, w)	ModRM:reg (r)	N/A	        N/A
MI	    ModRM:r/m (r, w)	imm8/16/32	    N/A	        N/A
I	    AL/AX/EAX/RAX	    imm8/16/32	    N/A	        N/A

Description:

Adds the destination operand (first operand), the source operand (second operand), and the carry (CF) flag and stores the result in the destination operand. The destination operand can be a register or a memory location; the source operand can be an immediate, a register, or a memory location. (However, two memory operands cannot be used in one instruction.) The state of the CF flag represents a carry from a previous addition. When an immediate value is used as an operand, it is sign-extended to the length of the destination operand format.

The ADC instruction does not distinguish between signed or unsigned operands. Instead, the processor evaluates the result for both data types and sets the OF and CF flags to indicate a carry in the signed or unsigned result, respectively. The SF flag indicates the sign of the signed result.

The ADC instruction is usually executed as part of a multibyte or multiword addition in which an ADD instruction is followed by an ADC instruction.

This instruction can be used with a LOCK prefix to allow the instruction to be executed atomically.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

DEST := DEST + SRC + CF;
Intel C/C++ Compiler Intrinsic Equivalent ¶

ADC extern unsigned char _addcarry_u8(unsigned char c_in, unsigned char src1, unsigned char src2, unsigned char *sum_out);
ADC extern unsigned char _addcarry_u16(unsigned char c_in, unsigned short src1, unsigned short src2, unsigned short *sum_out);
ADC extern unsigned char _addcarry_u32(unsigned char c_in, unsigned int src1, unsigned char int, unsigned int *sum_out);
ADC extern unsigned char _addcarry_u64(unsigned char c_in, unsigned __int64 src1, unsigned __int64 src2, unsigned __int64 *sum_out);

Flags Affected:

The OF, SF, ZF, AF, CF, and PF flags are set according to the result.

Protected Mode Exceptions:

#GP(0)	If the destination is located in a non-writable segment.
If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
If the DS, ES, FS, or GS register is used to access memory and it contains a NULL segment selector.
#SS(0)	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code)	If a page fault occurs.
#AC(0)	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD	If the LOCK prefix is used but the destination is not a memory operand.

Real-Address Mode Exceptions:

#GP	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS	If a memory operand effective address is outside the SS segment limit.
#UD	If the LOCK prefix is used but the destination is not a memory operand.

Virtual-8086 Mode Exceptions:

#GP(0)	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS(0)	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code)	If a page fault occurs.
#AC(0)	If alignment checking is enabled and an unaligned memory reference is made.
#UD	If the LOCK prefix is used but the destination is not a memory operand.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#SS(0)	If a memory address referencing the SS segment is in a non-canonical form.
#GP(0)	If the memory address is in a non-canonical form.
#PF(fault-code)	If a page fault occurs.
#AC(0)	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD	If the LOCK prefix is used but the destination is not a memory operand.




ADCX — Unsigned Integer Addition of Two Operands With Carry Flag
Opcode/Instruction	                    Op/En	64/32bit Mode Support	CPUID Feature Flag	    Description
66 0F 38 F6 /r ADCX r32, r/m32	        M	    V/V	                        ADX	                Unsigned addition of r32 with CF, r/m32 to r32, writes CF.
66 REX.w 0F 38 F6 /r ADCX r64, r/m64	RM	    V/N.E.	                    ADX	                Unsigned addition of r64 with CF, r/m64 to r64, writes CF.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	        N/A

Description:

Performs an unsigned addition of the destination operand (first operand), the source operand (second operand) and the carry-flag (CF) and stores the result in the destination operand. The destination operand is a general-purpose register, whereas the source operand can be a general-purpose register or memory location. The state of CF can represent a carry from a previous addition. The instruction sets the CF flag with the carry generated by the unsigned addition of the operands.

The ADCX instruction is executed in the context of multi-precision addition, where we add a series of operands with a carry-chain. At the beginning of a chain of additions, we need to make sure the CF is in a desired initial state. Often, this initial state needs to be 0, which can be achieved with an instruction to zero the CF (e.g. XOR).

This instruction is supported in real mode and virtual-8086 mode. The operand size is always 32 bits if not in 64-bit mode.

In 64-bit mode, the default operation size is 32 bits. Using a REX Prefix in the form of REX.R permits access to additional registers (R8-15). Using REX Prefix in the form of REX.W promotes operation to 64 bits.

ADCX executes normally either inside or outside a transaction region.

Note: ADCX defines the OF flag differently than the ADD/ADC instructions as defined in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 2A.

Operation:

IF OperandSize is 64-bit
    THEN CF:DEST[63:0] := DEST[63:0] + SRC[63:0] + CF;
    ELSE CF:DEST[31:0] := DEST[31:0] + SRC[31:0] + CF;
FI;

Flags Affected:

CF is updated based on result. OF, SF, ZF, AF, and PF flags are unmodified.

Intel C/C++ Compiler Intrinsic Equivalent:

unsigned char _addcarryx_u32 (unsigned char c_in, unsigned int src1, unsigned int src2, unsigned int *sum_out);
unsigned char _addcarryx_u64 (unsigned char c_in, unsigned __int64 src1, unsigned __int64 src2, unsigned __int64 *sum_out);

SIMD Floating-Point Exceptions:

None.

Protected Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    For an illegal address in the SS segment.
#GP(0):	
    For an illegal memory operand effective address in the CS, DS, ES, FS or GS segments.
    If the DS, ES, FS, or GS register is used to access memory and it contains a null segment selector.
#PF(fault-code):	
    For a page fault.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.

Real-Address Mode Exceptions:

#UD:
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    For an illegal address in the SS segment.
#GP(0):	
    If any part of the operand lies outside the effective address space from 0 to FFFFH.

Virtual-8086 Mode Exceptions:

#UD:	
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    For an illegal address in the SS segment.
#GP(0):	
    If any part of the operand lies outside the effective address space from 0 to FFFFH.
#PF(fault-code):	
    For a page fault.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#UD:	
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):
    If a memory address referencing the SS segment is in a non-canonical form.
#GP(0):	
    If the memory address is in a non-canonical form.
#PF(fault-code):	
    For a page fault.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.



ADD — Add
Opcode	            Instruction	        Op/En	64-bit Mode	    Compat/Leg Mode	    Description
04 ib	            ADD AL, imm8	    I	    Valid	        Valid	            Add imm8 to AL.
05 iw	            ADD AX, imm16	    I	    Valid	        Valid	            Add imm16 to AX.
05 id	            ADD EAX, imm32	    I	    Valid	        Valid	            Add imm32 to EAX.
REX.W + 05 id	    ADD RAX, imm32	    I	    Valid	        N.E.	            Add imm32 sign-extended to 64-bits to RAX.
80 /0 ib	        ADD r/m8, imm8	    MI	    Valid	        Valid	            Add imm8 to r/m8.
REX + 80 /0 ib	    ADD r/m8*, imm8	    MI	    Valid	        N.E.	            Add sign-extended imm8 to r/m8.
81 /0 iw	        ADD r/m16, imm16	MI	    Valid	        Valid	            Add imm16 to r/m16.
81 /0 id	        ADD r/m32, imm32	MI	    Valid	        Valid	            Add imm32 to r/m32.
REX.W + 81 /0 id	ADD r/m64, imm32	MI	    Valid	        N.E.	            Add imm32 sign-extended to 64-bits to r/m64.
83 /0 ib	        ADD r/m16, imm8	    MI	    Valid	        Valid	            Add sign-extended imm8 to r/m16.
83 /0 ib	        ADD r/m32, imm8	    MI	    Valid	        Valid	            Add sign-extended imm8 to r/m32.
REX.W + 83 /0 ib	ADD r/m64, imm8	    MI	    Valid	        N.E.	            Add sign-extended imm8 to r/m64.
00 /r	            ADD r/m8, r8	    MR	    Valid	        Valid	            Add r8 to r/m8.
REX + 00 /r	        ADD r/m8*, r8*	    MR	    Valid	        N.E.	            Add r8 to r/m8.
01 /r	            ADD r/m16, r16	    MR	    Valid	        Valid	            Add r16 to r/m16.
01 /r	            ADD r/m32, r32	    MR	    Valid	        Valid	            Add r32 to r/m32.
REX.W + 01 /r	    ADD r/m64, r64	    MR	    Valid	        N.E.	            Add r64 to r/m64.
02 /r	            ADD r8, r/m8	    RM	    Valid	        Valid	            Add r/m8 to r8.
REX + 02 /r	        ADD r8*, r/m8*	    RM	    Valid	        N.E.	            Add r/m8 to r8.
03 /r	            ADD r16, r/m16	    RM	    Valid	        Valid	            Add r/m16 to r16.
03 /r	            ADD r32, r/m32	    RM	    Valid	        Valid	            Add r/m32 to r32.
REX.W + 03 /r	    ADD r64, r/m64	    RM	    Valid	        N.E.	            Add r/m64 to r64.
*In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	        N/A
MR	    ModRM:r/m (r, w)	ModRM:reg (r)	N/A	        N/A
MI	    ModRM:r/m (r, w)	imm8/16/32	    N/A	        N/A
I	    AL/AX/EAX/RAX	    imm8/16/32	    N/A	        N/A

Description:

Adds the destination operand (first operand) and the source operand (second operand) and then stores the result in the destination operand. The destination operand can be a register or a memory location; the source operand can be an immediate, a register, or a memory location. (However, two memory operands cannot be used in one instruction.) When an immediate value is used as an operand, it is sign-extended to the length of the destination operand format.

The ADD instruction performs integer addition. It evaluates the result for both signed and unsigned integer operands and sets the OF and CF flags to indicate a carry (overflow) in the signed or unsigned result, respectively. The SF flag indicates the sign of the signed result.

This instruction can be used with a LOCK prefix to allow the instruction to be executed atomically.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

DEST := DEST + SRC;
Flags Affected ¶

The OF, SF, ZF, AF, CF, and PF flags are set according to the result.

Protected Mode Exceptions:

#GP(0):	
    If the destination is located in a non-writable segment.
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register is used to access memory and it contains a NULL segment selector.
#SS(0):	
    If a memory operand effective address is outside the SS segment limit.
#PF(fault-code):	
    If a page fault occurs.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:	
    If the LOCK prefix is used but the destination is not a memory operand.

Real-Address Mode Exceptions:

#GP:	
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS:	
    If a memory operand effective address is outside the SS segment limit.
#UD:	
    If the LOCK prefix is used but the destination is not a memory operand.

Virtual-8086 Mode Exceptions:

#GP(0):	
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS(0):	
    If a memory operand effective address is outside the SS segment limit.
#PF(fault-code):	
    If a page fault occurs.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made.
#UD:	
    If the LOCK prefix is used but the destination is not a memory operand.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#SS(0):	
    If a memory address referencing the SS segment is in a non-canonical form.
#GP(0):	
    If the memory address is in a non-canonical form.
#PF(fault-code):	
    If a page fault occurs.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:	
    If the LOCK prefix is used but the destination is not a memory operand.



ADDPD — Add Packed Double Precision Floating-Point Values
Opcode/Instruction	                                                        Op / En	    64/32 bit Mode Support	CPUID Feature Flag	    Description
66 0F 58 /r ADDPD xmm1, xmm2/m128	                                        A	        V/V	                    SSE2	                Add packed double precision floating-point values from xmm2/mem to xmm1 and store result in xmm1.
VEX.128.66.0F.WIG 58 /r VADDPD xmm1,xmm2, xmm3/m128	                        B	        V/V	                    AVX	                    Add packed double precision floating-point values from xmm3/mem to xmm2 and store result in xmm1.
VEX.256.66.0F.WIG 58 /r VADDPD ymm1, ymm2, ymm3/m256	                    B	        V/V	                    AVX	                    Add packed double precision floating-point values from ymm3/mem to ymm2 and store result in ymm1.
EVEX.128.66.0F.W1 58 /r VADDPD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst	    C	        V/V	                    AVX512VL AVX512F	    Add packed double precision floating-point values from xmm3/m128/m64bcst to xmm2 and store result in xmm1 with writemask k1.
EVEX.256.66.0F.W1 58 /r VADDPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst	    C	        V/V	                    AVX512VL AVX512F	    Add packed double precision floating-point values from ymm3/m256/m64bcst to ymm2 and store result in ymm1 with writemask k1.
EVEX.512.66.0F.W1 58 /r VADDPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{er}	C	        V/V	                    AVX512F	                Add packed double precision floating-point values from zmm3/m512/m64bcst to zmm2 and store result in zmm1 with writemask k1.

Instruction Operand Encoding:

Op/En	Tuple Type	Operand 1	        Operand 2	    Operand 3	    Operand 4
A	    N/A	        ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
B	    N/A	        ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A
C	    Full	    ModRM:reg (w)	    EVEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds two, four or eight packed double precision floating-point values from the first source operand to the second source operand, and stores the packed double precision floating-point result in the destination operand.

EVEX encoded versions: The first source operand is a ZMM/YMM/XMM register. The second source operand can be a ZMM/YMM/XMM register, a 512/256/128-bit memory location or a 512/256/128-bit vector broadcasted from a 64-bit memory location. The destination operand is a ZMM/YMM/XMM register conditionally updated with writemask k1.

VEX.256 encoded version: The first source operand is a YMM register. The second source operand can be a YMM register or a 256-bit memory location. The destination operand is a YMM register. The upper bits (MAXVL-1:256) of the corresponding ZMM register destination are zeroed.

VEX.128 encoded version: the first source operand is a XMM register. The second source operand is an XMM register or 128-bit memory location. The destination operand is an XMM register. The upper bits (MAXVL-1:128) of the corresponding ZMM register destination are zeroed.

128-bit Legacy SSE version: The second source can be an XMM register or an 128-bit memory location. The destination is not distinct from the first source XMM register and the upper Bits (MAXVL-1:128) of the corresponding ZMM register destination are unmodified.

Operation :

VADDPD (EVEX Encoded Versions) When SRC2 Operand is a Vector Register:

(KL, VL) = (2, 128), (4, 256), (8, 512)
IF (VL = 512) AND (EVEX.b = 1)
    THEN
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(EVEX.RC);
    ELSE
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(MXCSR.RC);
FI;
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no writemask*
        THEN DEST[i+63:i] := SRC1[i+63:i] + SRC2[i+63:i]
        ELSE
            IF *merging-masking* ; merging-masking
                THEN *DEST[i+63:i] remains unchanged*
                ELSE ; zeroing-masking
                    DEST[i+63:i] := 0
            FI
    FI;
ENDFOR
DEST[MAXVL-1:VL] := 0

VADDPD (EVEX Encoded Versions) When SRC2 Operand is a Memory Source:

(KL, VL) = (2, 128), (4, 256), (8, 512)
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no writemask*
        THEN
            IF (EVEX.b = 1)
                THEN
                    DEST[i+63:i] := SRC1[i+63:i] + SRC2[63:0]
                ELSE
                    DEST[i+63:i] := SRC1[i+63:i] + SRC2[i+63:i]
            FI;
        ELSE
            IF *merging-masking* ; merging-masking
                THEN *DEST[i+63:i] remains unchanged*
                ELSE ; zeroing-masking
                    DEST[i+63:i] := 0
            FI
    FI;
ENDFOR
DEST[MAXVL-1:VL] := 0

VADDPD (VEX.256 Encoded Version):

DEST[63:0] := SRC1[63:0] + SRC2[63:0]
DEST[127:64] := SRC1[127:64] + SRC2[127:64]
DEST[191:128] := SRC1[191:128] + SRC2[191:128]
DEST[255:192] := SRC1[255:192] + SRC2[255:192]
DEST[MAXVL-1:256] := 0
.

VADDPD (VEX.128 Encoded Version):

DEST[63:0] := SRC1[63:0] + SRC2[63:0]
DEST[127:64] := SRC1[127:64] + SRC2[127:64]
DEST[MAXVL-1:128] := 0
ADDPD (128-bit Legacy SSE Version) ¶

DEST[63:0] := DEST[63:0] + SRC[63:0]
DEST[127:64] := DEST[127:64] + SRC[127:64]
DEST[MAXVL-1:128] (Unmodified)

Intel C/C++ Compiler Intrinsic Equivalent:

VADDPD __m512d _mm512_add_pd (__m512d a, __m512d b);
VADDPD __m512d _mm512_mask_add_pd (__m512d s, __mmask8 k, __m512d a, __m512d b);
VADDPD __m512d _mm512_maskz_add_pd (__mmask8 k, __m512d a, __m512d b);
VADDPD __m256d _mm256_mask_add_pd (__m256d s, __mmask8 k, __m256d a, __m256d b);
VADDPD __m256d _mm256_maskz_add_pd (__mmask8 k, __m256d a, __m256d b);
VADDPD __m128d _mm_mask_add_pd (__m128d s, __mmask8 k, __m128d a, __m128d b);
VADDPD __m128d _mm_maskz_add_pd (__mmask8 k, __m128d a, __m128d b);
VADDPD __m512d _mm512_add_round_pd (__m512d a, __m512d b, int);
VADDPD __m512d _mm512_mask_add_round_pd (__m512d s, __mmask8 k, __m512d a, __m512d b, int);
VADDPD __m512d _mm512_maskz_add_round_pd (__mmask8 k, __m512d a, __m512d b, int);
ADDPD __m256d _mm256_add_pd (__m256d a, __m256d b);
ADDPD __m128d _mm_add_pd (__m128d a, __m128d b);

SIMD Floating-Point Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

VEX-encoded instruction, see Table 2-19, “Type 2 Class Exception Conditions.”

EVEX-encoded instruction, see Table 2-46, “Type E2 Class Exception Conditions.”




ADDPS — Add Packed Single Precision Floating-Point Values

Opcode/Instruction	                                                    Op / En	    64/32 bit Mode Support	CPUID Feature Flag	    Description
NP 0F 58 /r ADDPS xmm1, xmm2/m128	                                    A	        V/V	                    SSE	                    Add packed single precision floating-point values from xmm2/m128 to xmm1 and store result in xmm1.
VEX.128.0F.WIG 58 /r VADDPS xmm1,xmm2, xmm3/m128	                    B	        V/V	                    AVX	                    Add packed single precision floating-point values from xmm3/m128 to xmm2 and store result in xmm1.
VEX.256.0F.WIG 58 /r VADDPS ymm1, ymm2, ymm3/m256	                    B	        V/V	                    AVX	                    Add packed single precision floating-point values from ymm3/m256 to ymm2 and store result in ymm1.
EVEX.128.0F.W0 58 /r VADDPS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst	    C	        V/V	                    AVX512VL AVX512F	    Add packed single precision floating-point values from xmm3/m128/m32bcst to xmm2 and store result in xmm1 with writemask k1.
EVEX.256.0F.W0 58 /r VADDPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst	    C	        V/V	                    AVX512VL AVX512F	    Add packed single precision floating-point values from ymm3/m256/m32bcst to ymm2 and store result in ymm1 with writemask k1.
EVEX.512.0F.W0 58 /r VADDPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst {er}	C	        V/V	                    AVX512F	                Add packed single precision floating-point values from zmm3/m512/m32bcst to zmm2 and store result in zmm1 with writemask k1.

Instruction Operand Encoding:

Op/En	Tuple Type	Operand 1	        Operand 2	    Operand 3	    Operand 4
A	    N/A	        ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
B	    N/A	        ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A
C	    Full	    ModRM:reg (w)	    EVEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds four, eight or sixteen packed single precision floating-point values from the first source operand with the second source operand, and stores the packed single precision floating-point result in the destination operand.

EVEX encoded versions: The first source operand is a ZMM/YMM/XMM register. The second source operand can be a ZMM/YMM/XMM register, a 512/256/128-bit memory location or a 512/256/128-bit vector broadcasted from a 32-bit memory location. The destination operand is a ZMM/YMM/XMM register conditionally updated with writemask k1.

VEX.256 encoded version: The first source operand is a YMM register. The second source operand can be a YMM register or a 256-bit memory location. The destination operand is a YMM register. The upper bits (MAXVL-1:256) of the corresponding ZMM register destination are zeroed.

VEX.128 encoded version: the first source operand is a XMM register. The second source operand is an XMM register or 128-bit memory location. The destination operand is an XMM register. The upper bits (MAXVL-1:128) of the corresponding ZMM register destination are zeroed.

128-bit Legacy SSE version: The second source can be an XMM register or an 128-bit memory location. The destination is not distinct from the first source XMM register and the upper Bits (MAXVL-1:128) of the corresponding ZMM register destination are unmodified.

Operation:

VADDPS (EVEX Encoded Versions) When SRC2 Operand is a Register:

(KL, VL) = (4, 128), (8, 256), (16, 512)
IF (VL = 512) AND (EVEX.b = 1)
    THEN
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(EVEX.RC);
    ELSE
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(MXCSR.RC);
FI;
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no writemask*
        THEN DEST[i+31:i] := SRC1[i+31:i] + SRC2[i+31:i]
        ELSE
            IF *merging-masking* ; merging-masking
                THEN *DEST[i+31:i] remains unchanged*
                ELSE ; zeroing-masking
                    DEST[i+31:i] := 0
            FI
    FI;
ENDFOR;
DEST[MAXVL-1:VL] := 0

VADDPS (EVEX Encoded Versions) When SRC2 Operand is a Memory Source:

(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no writemask*
        THEN
            IF (EVEX.b = 1)
                THEN
                    DEST[i+31:i] :=
                        SRC1[i+31:i] + SRC2[31:0]
                ELSE
                    DEST[i+31:i] :=
                        SRC1[i+31:i] + SRC2[i+31:i]
            FI;
        ELSE
            IF *merging-masking*
                            ; merging-masking
                THEN *DEST[i+31:i]
                        remains unchanged*
                ELSE
                            ; zeroing-masking
                    DEST[i+31:i] :=
                        0
            FI
    FI;
ENDFOR;
DEST[MAXVL-1:VL] := 0

VADDPS (VEX.256 Encoded Version):

DEST[31:0] := SRC1[31:0] + SRC2[31:0]
DEST[63:32] := SRC1[63:32] + SRC2[63:32]
DEST[95:64] := SRC1[95:64] + SRC2[95:64]
DEST[127:96] := SRC1[127:96] + SRC2[127:96]
DEST[159:128] := SRC1[159:128] + SRC2[159:128]
DEST[191:160]:= SRC1[191:160] + SRC2[191:160]
DEST[223:192] := SRC1[223:192] + SRC2[223:192]
DEST[255:224] := SRC1[255:224] + SRC2[255:224].
DEST[MAXVL-1:256] := 0

VADDPS (VEX.128 Encoded Version):

DEST[31:0] := SRC1[31:0] + SRC2[31:0]
DEST[63:32] := SRC1[63:32] + SRC2[63:32]
DEST[95:64] := SRC1[95:64] + SRC2[95:64]
DEST[127:96] := SRC1[127:96] + SRC2[127:96]
DEST[MAXVL-1:128] := 0

ADDPS (128-bit Legacy SSE Version):

DEST[31:0] := SRC1[31:0] + SRC2[31:0]
DEST[63:32] := SRC1[63:32] + SRC2[63:32]
DEST[95:64] := SRC1[95:64] + SRC2[95:64]
DEST[127:96] := SRC1[127:96] + SRC2[127:96]
DEST[MAXVL-1:128] (Unmodified)

Intel C/C++ Compiler Intrinsic Equivalent:

VADDPS __m512 _mm512_add_ps (__m512 a, __m512 b);
VADDPS __m512 _mm512_mask_add_ps (__m512 s, __mmask16 k, __m512 a, __m512 b);
VADDPS __m512 _mm512_maskz_add_ps (__mmask16 k, __m512 a, __m512 b);
VADDPS __m256 _mm256_mask_add_ps (__m256 s, __mmask8 k, __m256 a, __m256 b);
VADDPS __m256 _mm256_maskz_add_ps (__mmask8 k, __m256 a, __m256 b);
VADDPS __m128 _mm_mask_add_ps (__m128d s, __mmask8 k, __m128 a, __m128 b);
VADDPS __m128 _mm_maskz_add_ps (__mmask8 k, __m128 a, __m128 b);
VADDPS __m512 _mm512_add_round_ps (__m512 a, __m512 b, int);
VADDPS __m512 _mm512_mask_add_round_ps (__m512 s, __mmask16 k, __m512 a, __m512 b, int);
VADDPS __m512 _mm512_maskz_add_round_ps (__mmask16 k, __m512 a, __m512 b, int);
ADDPS __m256 _mm256_add_ps (__m256 a, __m256 b);
ADDPS __m128 _mm_add_ps (__m128 a, __m128 b);

SIMD Floating-Point Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

VEX-encoded instruction, see Table 2-19, “Type 2 Class Exception Conditions.”

EVEX-encoded instruction, see Table 2-46, “Type E2 Class Exception Conditions.”



ADDSD — Add Scalar Double Precision Floating-Point Values

Opcode/Instruction	                                                Op / En	    64/32 bit Mode Support	CPUID Feature Flag	Description
F2 0F 58 /r ADDSD xmm1, xmm2/m64	                                A	        V/V	                    SSE2	            Add the low double precision floating-point value from xmm2/mem to xmm1 and store the result in xmm1.
VEX.LIG.F2.0F.WIG 58 /r VADDSD xmm1, xmm2, xmm3/m64	                B	        V/V	                    AVX	                Add the low double precision floating-point value from xmm3/mem to xmm2 and store the result in xmm1.
EVEX.LLIG.F2.0F.W1 58 /r VADDSD xmm1 {k1}{z}, xmm2, xmm3/m64{er}	C	        V/V	                    AVX512F	            Add the low double precision floating-point value from xmm3/m64 to xmm2 and store the result in xmm1 with writemask k1.

Instruction Operand Encoding:

Op/En	Tuple Type	    Operand 1	        Operand 2	    Operand 3	    Operand 4
A	    N/A	            ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
B	    N/A	            ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A
C	    Tuple1 Scalar	ModRM:reg (w)	    EVEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds the low double precision floating-point values from the second source operand and the first source operand and stores the double precision floating-point result in the destination operand.

The second source operand can be an XMM register or a 64-bit memory location. The first source and destination operands are XMM registers.

128-bit Legacy SSE version: The first source and destination operands are the same. Bits (MAXVL-1:64) of the corresponding destination register remain unchanged.

EVEX and VEX.128 encoded version: The first source operand is encoded by EVEX.vvvv/VEX.vvvv. Bits (127:64) of the XMM register destination are copied from corresponding bits in the first source operand. Bits (MAXVL-1:128) of the destination register are zeroed.

EVEX version: The low quadword element of the destination is updated according to the writemask.

Software should ensure VADDSD is encoded with VEX.L=0. Encoding VADDSD with VEX.L=1 may encounter unpredictable behavior across different processor generations.

Operation:

VADDSD (EVEX Encoded Version):

IF (EVEX.b = 1) AND SRC2 *is a register*
    THEN
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(EVEX.RC);
    ELSE
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(MXCSR.RC);
FI;
IF k1[0] or *no writemask*
    THEN DEST[63:0] := SRC1[63:0] + SRC2[63:0]
    ELSE
        IF *merging-masking* ; merging-masking
            THEN *DEST[63:0] remains unchanged*
            ELSE ; zeroing-masking
                THEN DEST[63:0] := 0
        FI;
FI;
DEST[127:64] := SRC1[127:64]
DEST[MAXVL-1:128] := 0

VADDSD (VEX.128 Encoded Version):

DEST[63:0] := SRC1[63:0] + SRC2[63:0]
DEST[127:64] := SRC1[127:64]
DEST[MAXVL-1:128] := 0

ADDSD (128-bit Legacy SSE Version):

DEST[63:0] := DEST[63:0] + SRC[63:0]
DEST[MAXVL-1:64] (Unmodified)
Intel C/C++ Compiler Intrinsic Equivalent:

VADDSD __m128d _mm_mask_add_sd (__m128d s, __mmask8 k, __m128d a, __m128d b);
VADDSD __m128d _mm_maskz_add_sd (__mmask8 k, __m128d a, __m128d b);
VADDSD __m128d _mm_add_round_sd (__m128d a, __m128d b, int);
VADDSD __m128d _mm_mask_add_round_sd (__m128d s, __mmask8 k, __m128d a, __m128d b, int);
VADDSD __m128d _mm_maskz_add_round_sd (__mmask8 k, __m128d a, __m128d b, int);
ADDSD __m128d _mm_add_sd (__m128d a, __m128d b);

SIMD Floating-Point Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

VEX-encoded instruction, see Table 2-20, “Type 3 Class Exception Conditions.”

EVEX-encoded instruction, see Table 2-47, “Type E3 Class Exception Conditions.”



ADDSS — Add Scalar Single Precision Floating-Point Values

Opcode/Instruction	                                                Op / En	    64/32 bit Mode Support	CPUID Feature Flag	Description
F3 0F 58 /r ADDSS xmm1, xmm2/m32	                                A	        V/V	                    SSE	                Add the low single precision floating-point value from xmm2/mem to xmm1 and store the result in xmm1.
VEX.LIG.F3.0F.WIG 58 /r VADDSS xmm1,xmm2, xmm3/m32	                B	        V/V	                    AVX	                Add the low single precision floating-point value from xmm3/mem to xmm2 and store the result in xmm1.
EVEX.LLIG.F3.0F.W0 58 /r VADDSS xmm1{k1}{z}, xmm2, xmm3/m32{er}	    C	        V/V	                    AVX512F	            Add the low single precision floating-point value from xmm3/m32 to xmm2 and store the result in xmm1with writemask k1.
Instruction Operand Encoding ¶

Op/En	Tuple Type	        Operand 1	        Operand 2	    Operand 3	    Operand 4
A	    N/A	                ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
B	    N/A	                ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A
C	    Tuple1 Scalar	    ModRM:reg (w)	    EVEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds the low single precision floating-point values from the second source operand and the first source operand, and stores the double precision floating-point result in the destination operand.

The second source operand can be an XMM register or a 64-bit memory location. The first source and destination operands are XMM registers.

128-bit Legacy SSE version: The first source and destination operands are the same. Bits (MAXVL-1:32) of the corresponding the destination register remain unchanged.

EVEX and VEX.128 encoded version: The first source operand is encoded by EVEX.vvvv/VEX.vvvv. Bits (127:32) of the XMM register destination are copied from corresponding bits in the first source operand. Bits (MAXVL-1:128) of the destination register are zeroed.

EVEX version: The low doubleword element of the destination is updated according to the writemask.

Software should ensure VADDSS is encoded with VEX.L=0. Encoding VADDSS with VEX.L=1 may encounter unpredictable behavior across different processor generations.

Operation:

VADDSS (EVEX Encoded Versions):

IF (EVEX.b = 1) AND SRC2 *is a register*
    THEN
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(EVEX.RC);
    ELSE
        SET_ROUNDING_MODE_FOR_THIS_INSTRUCTION(MXCSR.RC);
FI;
IF k1[0] or *no writemask*
    THEN DEST[31:0] := SRC1[31:0] + SRC2[31:0]
    ELSE
        IF *merging-masking* ; merging-masking
            THEN *DEST[31:0] remains unchanged*
            ELSE ; zeroing-masking
                THEN DEST[31:0] := 0
        FI;
FI;
DEST[127:32] := SRC1[127:32]
DEST[MAXVL-1:128] := 0

VADDSS DEST, SRC1, SRC2 (VEX.128 Encoded Version):

DEST[31:0] := SRC1[31:0] + SRC2[31:0]
DEST[127:32] := SRC1[127:32]
DEST[MAXVL-1:128] := 0
ADDSS DEST, SRC (128-bit Legacy SSE Version) ¶

DEST[31:0] := DEST[31:0] + SRC[31:0]
DEST[MAXVL-1:32] (Unmodified)

Intel C/C++ Compiler Intrinsic Equivalent:

VADDSS __m128 _mm_mask_add_ss (__m128 s, __mmask8 k, __m128 a, __m128 b);
VADDSS __m128 _mm_maskz_add_ss (__mmask8 k, __m128 a, __m128 b);
VADDSS __m128 _mm_add_round_ss (__m128 a, __m128 b, int);
VADDSS __m128 _mm_mask_add_round_ss (__m128 s, __mmask8 k, __m128 a, __m128 b, int);
VADDSS __m128 _mm_maskz_add_round_ss (__mmask8 k, __m128 a, __m128 b, int);
ADDSS __m128 _mm_add_ss (__m128 a, __m128 b);

SIMD Floating-Point Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

VEX-encoded instruction, see Table 2-20, “Type 3 Class Exception Conditions.”

EVEX-encoded instruction, see Table 2-47, “Type E3 Class Exception Conditions.”




ADDSUBPD — Packed Double Precision Floating-Point Add/Subtract

Opcode/Instruction	                                        Op/En	64/32-bit Mode	CPUID Feature Flag	Description
66 0F D0 /r ADDSUBPD xmm1, xmm2/m128	                    RM	    V/V	            SSE3	            Add/subtract double precision floating-point values from xmm2/m128 to xmm1.
VEX.128.66.0F.WIG D0 /r VADDSUBPD xmm1, xmm2, xmm3/m128	    RVM	    V/V	            AVX	                Add/subtract packed double precision floating-point values from xmm3/mem to xmm2 and stores result in xmm1.
VEX.256.66.0F.WIG D0 /r VADDSUBPD ymm1, ymm2, ymm3/m256	    RVM	    V/V	            AVX	                Add / subtract packed double precision floating-point values from ymm3/mem to ymm2 and stores result in ymm1.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	    Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
RVM	    ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds odd-numbered double precision floating-point values of the first source operand (second operand) with the corresponding double precision floating-point values from the second source operand (third operand); stores the result in the odd-numbered values of the destination operand (first operand). Subtracts the even-numbered double precision floating-point values from the second source operand from the corresponding double precision floating values in the first source operand; stores the result into the even-numbered values of the destination operand.

In 64-bit mode, using a REX prefix in the form of REX.R permits this instruction to access additional registers (XMM8-XMM15).

128-bit Legacy SSE version: The second source can be an XMM register or an 128-bit memory location. The destination is not distinct from the first source XMM register and the upper bits (MAXVL-1:128) of the corresponding YMM register destination are unmodified. See Figure 3-3.

VEX.128 encoded version: the first source operand is an XMM register or 128-bit memory location. The destination operand is an XMM register. The upper bits (MAXVL-1:128) of the corresponding YMM register destination are zeroed.

VEX.256 encoded version: The first source operand is a YMM register. The second source operand can be a YMM register or a 256-bit memory location. The destination operand is a YMM register.

ADDSUBPD xmm1, xmm2/m128 Diagram
            [127:64]                                [63:0]                  xmm2/m128
                |                                       |
                v                                       v
xmm1[127:64] + xmm2/m128[127:64]        xmm1[63:0] - xmm2/m128[63:0]        RESULT:
                                                                            xmm1
            [127:64]                                [63:0]

Figure 3-3. ADDSUBPD—Packed Double Precision Floating-Point Add/Subtract


Operation:

ADDSUBPD (128-bit Legacy SSE Version):

DEST[63:0] := DEST[63:0] - SRC[63:0]
DEST[127:64] := DEST[127:64] + SRC[127:64]
DEST[MAXVL-1:128] (Unmodified)

VADDSUBPD (VEX.128 Encoded Version):

DEST[63:0] := SRC1[63:0] - SRC2[63:0]
DEST[127:64] := SRC1[127:64] + SRC2[127:64]
DEST[MAXVL-1:128] := 0

VADDSUBPD (VEX.256 Encoded Version):

DEST[63:0] := SRC1[63:0] - SRC2[63:0]
DEST[127:64] := SRC1[127:64] + SRC2[127:64]
DEST[191:128] := SRC1[191:128] - SRC2[191:128]
DEST[255:192] := SRC1[255:192] + SRC2[255:192]

Intel C/C++ Compiler Intrinsic Equivalent:

ADDSUBPD __m128d _mm_addsub_pd(__m128d a, __m128d b)
VADDSUBPD __m256d _mm256_addsub_pd (__m256d a, __m256d b)

Exceptions:

When the source operand is a memory operand, it must be aligned on a 16-byte boundary or a general-protection exception (#GP) will be generated.

SIMD Floating-Point Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

See Table 2-19, “Type 2 Class Exception Conditions.”




ADDSUBPS — Packed Single Precision Floating-Point Add/Subtract

Opcode/Instruction	                                        Op/En	64/32-bit Mode	CPUID Feature Flag	    Description
F2 0F D0 /r ADDSUBPS xmm1, xmm2/m128	                    RM	    V/V	            SSE3	                Add/subtract single precision floating-point values from xmm2/m128 to xmm1.
VEX.128.F2.0F.WIG D0 /r VADDSUBPS xmm1, xmm2, xmm3/m128	    RVM	    V/V	            AVX	                    Add/subtract single precision floating-point values from xmm3/mem to xmm2 and stores result in xmm1.
VEX.256.F2.0F.WIG D0 /r VADDSUBPS ymm1, ymm2, ymm3/m256	    RVM	    V/V	            AVX	                    Add / subtract single precision floating-point values from ymm3/mem to ymm2 and stores result in ymm1.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	    Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
RVM	    ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds odd-numbered single precision floating-point values of the first source operand (second operand) with the corresponding single precision floating-point values from the second source operand (third operand); stores the result in the odd-numbered values of the destination operand (first operand). Subtracts the even-numbered single precision floating-point values from the second source operand from the corresponding single precision floating values in the first source operand; stores the result into the even-numbered values of the destination operand.

In 64-bit mode, using a REX prefix in the form of REX.R permits this instruction to access additional registers (XMM8-XMM15).

128-bit Legacy SSE version: The second source can be an XMM register or an 128-bit memory location. The destination is not distinct from the first source XMM register and the upper bits (MAXVL-1:128) of the corresponding YMM register destination are unmodified. See Figure 3-4.

VEX.128 encoded version: the first source operand is an XMM register or 128-bit memory location. The destination operand is an XMM register. The upper bits (MAXVL-1:128) of the corresponding YMM register destination are zeroed.

VEX.256 encoded version: The first source operand is a YMM register. The second source operand can be a YMM register or a 256-bit memory location. The destination operand is a YMM register.

ADDSUBPS xmm1, xmm2/m128 Diagram
INPUT: xmm2/m128
[127:96]
[95:64]
[63:32]
[31:0]

RESULT: xmm1
xmm1[127:96] + xmm2/m128[127:96]        : Maintains [127:96]
xmm1[95:64] - xmm2/m128[95:64]          : Maintains [95:64]
xmm1[63:32] + xmm2/m128[63:32]          : Maintains [63:32]
xmm1[31:0] - xmm2/m128[31:0]            : Maintains [31:0]

Figure 3-4. ADDSUBPS—Packed Single Precision Floating-Point Add/Subtract

Operation:

ADDSUBPS (128-bit Legacy SSE Version):

DEST[31:0] := DEST[31:0] - SRC[31:0]
DEST[63:32] := DEST[63:32] + SRC[63:32]
DEST[95:64] := DEST[95:64] - SRC[95:64]
DEST[127:96] := DEST[127:96] + SRC[127:96]
DEST[MAXVL-1:128] (Unmodified)

VADDSUBPS (VEX.128 Encoded Version):

DEST[31:0] := SRC1[31:0] - SRC2[31:0]
DEST[63:32] := SRC1[63:32] + SRC2[63:32]
DEST[95:64] := SRC1[95:64] - SRC2[95:64]
DEST[127:96] := SRC1[127:96] + SRC2[127:96]
DEST[MAXVL-1:128] := 0

VADDSUBPS (VEX.256 Encoded Version):

DEST[31:0] := SRC1[31:0] - SRC2[31:0]
DEST[63:32] := SRC1[63:32] + SRC2[63:32]
DEST[95:64] := SRC1[95:64] - SRC2[95:64]
DEST[127:96] := SRC1[127:96] + SRC2[127:96]
DEST[159:128] := SRC1[159:128] - SRC2[159:128]
DEST[191:160] := SRC1[191:160] + SRC2[191:160]
DEST[223:192] := SRC1[223:192] - SRC2[223:192]
DEST[255:224] := SRC1[255:224] + SRC2[255:224]

Intel C/C++ Compiler Intrinsic Equivalent:

ADDSUBPS __m128 _mm_addsub_ps(__m128 a, __m128 b)
VADDSUBPS __m256 _mm256_addsub_ps (__m256 a, __m256 b)

Exceptions:

When the source operand is a memory operand, the operand must be aligned on a 16-byte boundary or a general-protection exception (#GP) will be generated.

SIMD Floating-Point Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

See Table 2-19, “Type 2 Class Exception Conditions.”




ADOX — Unsigned Integer Addition of Two Operands With Overflow Flag

Opcode/Instruction	                    Op/En	64/32bit Mode Support	CPUID Feature Flag	Description
F3 0F 38 F6 /r ADOX r32, r/m32	        RM	    V/V	                    ADX	                Unsigned addition of r32 with OF, r/m32 to r32, writes OF.
F3 REX.w 0F 38 F6 /r ADOX r64, r/m64	RM	    V/N.E.	                ADX	                Unsigned addition of r64 with OF, r/m64 to r64, writes OF.
Instruction Operand Encoding ¶

Op/En	Operand 1	        Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	        N/A

Description:

Performs an unsigned addition of the destination operand (first operand), the source operand (second operand) and the overflow-flag (OF) and stores the result in the destination operand. The destination operand is a general-purpose register, whereas the source operand can be a general-purpose register or memory location. The state of OF represents a carry from a previous addition. The instruction sets the OF flag with the carry generated by the unsigned addition of the operands.

The ADOX instruction is executed in the context of multi-precision addition, where we add a series of operands with a carry-chain. At the beginning of a chain of additions, we execute an instruction to zero the OF (e.g. XOR).

This instruction is supported in real mode and virtual-8086 mode. The operand size is always 32 bits if not in 64-bit mode.

In 64-bit mode, the default operation size is 32 bits. Using a REX Prefix in the form of REX.R permits access to additional registers (R8-15). Using REX Prefix in the form of REX.W promotes operation to 64-bits.

ADOX executes normally either inside or outside a transaction region.

Note: ADOX defines the CF and OF flags differently than the ADD/ADC instructions as defined in Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 2A.

Operation:

IF OperandSize is 64-bit
    THEN OF:DEST[63:0] := DEST[63:0] + SRC[63:0] + OF;
    ELSE OF:DEST[31:0] := DEST[31:0] + SRC[31:0] + OF;
FI;
Flags Affected ¶

OF is updated based on result. CF, SF, ZF, AF, and PF flags are unmodified.

Intel C/C++ Compiler Intrinsic Equivalent:

unsigned char _addcarryx_u32 (unsigned char c_in, unsigned int src1, unsigned int src2, unsigned int *sum_out);
unsigned char _addcarryx_u64 (unsigned char c_in, unsigned __int64 src1, unsigned __int64 src2, unsigned __int64 *sum_out);

SIMD Floating-Point Exceptions:

None.

Protected Mode Exceptions:

#UD:	
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    For an illegal address in the SS segment.
#GP(0):	
    For an illegal memory operand effective address in the CS, DS, ES, FS or GS segments.
    If the DS, ES, FS, or GS register is used to access memory and it contains a null segment selector.
#PF(fault-code):	
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.

Real-Address Mode Exceptions:

#UD:	
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    For an illegal address in the SS segment.
#GP(0):	
    If any part of the operand lies outside the effective address space from 0 to FFFFH.

Virtual-8086 Mode Exceptions:

#UD:	
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    For an illegal address in the SS segment.
#GP(0):	
    If any part of the operand lies outside the effective address space from 0 to FFFFH.
#PF(fault-code):
	For a page fault.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#UD:	
    If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.ADX[bit 19] = 0.
#SS(0):	
    If a memory address referencing the SS segment is in a non-canonical form.
#GP(0):	
    If the memory address is in a non-canonical form.
#PF(fault-code):	
    For a page fault.
#AC(0):	
    If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.



FADD/FADDP/FIADD — Add

Opcode	Instruction	        64-Bit Mode	    Compat/Leg Mode	    Description
D8 /0	FADD m32fp	        Valid	        Valid	            Add m32fp to ST(0) and store result in ST(0).
DC /0	FADD m64fp	        Valid	        Valid	            Add m64fp to ST(0) and store result in ST(0).
D8 C0+i	FADD ST(0), ST(i)	Valid	        Valid	            Add ST(0) to ST(i) and store result in ST(0).
DC C0+i	FADD ST(i), ST(0)	Valid	        Valid	            Add ST(i) to ST(0) and store result in ST(i).
DE C0+i	FADDP ST(i), ST(0)	Valid	        Valid	            Add ST(0) to ST(i), store result in ST(i), and pop the register stack.
DE C1	FADDP	            Valid	        Valid	            Add ST(0) to ST(1), store result in ST(1), and pop the register stack.
DA /0	FIADD m32int	    Valid	        Valid	            Add m32int to ST(0) and store result in ST(0).
DE /0	FIADD m16int	    Valid	        Valid	            Add m16int to ST(0) and store result in ST(0).

Description:

Adds the destination and source operands and stores the sum in the destination location. The destination operand is always an FPU register; the source operand can be a register or a memory location. Source operands in memory can be in single precision or double precision floating-point format or in word or doubleword integer format.

The no-operand version of the instruction adds the contents of the ST(0) register to the ST(1) register. The one-operand version adds the contents of a memory location (either a floating-point or an integer value) to the contents of the ST(0) register. The two-operand version, adds the contents of the ST(0) register to the ST(i) register or vice versa. The value in ST(0) can be doubled by coding:

FADD ST(0), ST(0);

The FADDP instructions perform the additional operation of popping the FPU register stack after storing the result. To pop the register stack, the processor marks the ST(0) register as empty and increments the stack pointer (TOP) by 1. (The no-operand version of the floating-point add instructions always results in the register stack being popped. In some assemblers, the mnemonic for this instruction is FADD rather than FADDP.)

The FIADD instructions convert an integer source operand to double extended-precision floating-point format before performing the addition.

The table on the following page shows the results obtained when adding various classes of numbers, assuming that neither overflow nor underflow occurs.

When the sum of two operands with opposite signs is 0, the result is +0, except for the round toward −∞ mode, in which case the result is −0. When the source operand is an integer 0, it is treated as a +0.

When both operand are infinities of the same sign, the result is ∞ of the expected sign. If both operands are infinities of opposite signs, an invalid-operation exception is generated. See Table 3-18.


Operation:

IF Instruction = FIADD
    THEN
        DEST := DEST + ConvertToDoubleExtendedPrecisionFP(SRC);
    ELSE (* Source operand is floating-point value *)
        DEST := DEST + SRC;
FI;
IF Instruction = FADDP
    THEN
        PopRegisterStack;
FI;

FPU Flags Affected:

C1	Set to 0 if stack underflow occurred.
Set if result was rounded up; cleared otherwise.
C0, C2, C3	Undefined.

Floating-Point Exceptions:

#IS:
	Stack underflow occurred.
#IA:
	Operand is an SNaN value or unsupported format.
    Operands are infinities of unlike sign.
#D:
	Source operand is a denormal value.
#U:
	Result is too small for destination format.
#O:
	Result is too large for destination format.
#P:
	Value cannot be represented exactly in destination format.

Protected Mode Exceptions:

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register contains a NULL segment selector.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
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
#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#PF(fault-code):
	If a page fault occurs.
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
#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#MF:
	If there is a pending x87 FPU exception.
#PF(fault-code):
	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If the LOCK prefix is used.



HADDPD — Packed Double Precision Floating-Point Horizontal Add

Opcode/Instruction	                                    Op/En	64/32-bit Mode	CPUID Feature Flag	Description
66 0F 7C /r HADDPD xmm1, xmm2/m128	                    RM	    V/V	            SSE3	            Horizontal add packed double precision floating-point values from xmm2/m128 to xmm1.
VEX.128.66.0F.WIG 7C /r VHADDPD xmm1,xmm2, xmm3/m128	RVM	    V/V	            AVX	                Horizontal add packed double precision floating-point values from xmm2 and xmm3/mem.
VEX.256.66.0F.WIG 7C /r VHADDPD ymm1, ymm2, ymm3/m256	RVM	    V/V	            AVX	                Horizontal add packed double precision floating-point values from ymm2 and ymm3/mem.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	    Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
RVM	    ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds the double precision floating-point values in the high and low quadwords of the destination operand and stores the result in the low quadword of the destination operand.

Adds the double precision floating-point values in the high and low quadwords of the source operand and stores the result in the high quadword of the destination operand.

In 64-bit mode, use of the REX.R prefix permits this instruction to access additional registers (XMM8-XMM15).

128-bit Legacy SSE version: The second source can be an XMM register or an 128-bit memory location. The destination is not distinct from the first source XMM register and the upper bits (MAXVL-1:128) of the corresponding YMM register destination are unmodified.

VEX.128 encoded version: the first source operand is an XMM register or 128-bit memory location. The destination operand is an XMM register. The upper bits (MAXVL-1:128) of the corresponding YMM register destination are zeroed.

VEX.256 encoded version: The first source operand is a YMM register. The second source operand can be a YMM register or a 256-bit memory location. The destination operand is a YMM register.

Operation:

HADDPD (128-bit Legacy SSE Version):

DEST[63:0] := SRC1[127:64] + SRC1[63:0]
DEST[127:64] := SRC2[127:64] + SRC2[63:0]
DEST[MAXVL-1:128] (Unmodified)

VHADDPD (VEX.128 Encoded Version):

DEST[63:0] := SRC1[127:64] + SRC1[63:0]
DEST[127:64] := SRC2[127:64] + SRC2[63:0]
DEST[MAXVL-1:128] := 0

VHADDPD (VEX.256 Encoded Version):

DEST[63:0] := SRC1[127:64] + SRC1[63:0]
DEST[127:64] := SRC2[127:64] + SRC2[63:0]
DEST[191:128] := SRC1[255:192] + SRC1[191:128]
DEST[255:192] := SRC2[255:192] + SRC2[191:128]

Intel C/C++ Compiler Intrinsic Equivalent:

VHADDPD __m256d _mm256_hadd_pd (__m256d a, __m256d b);
HADDPD __m128d _mm_hadd_pd (__m128d a, __m128d b);

Exceptions:

When the source operand is a memory operand, the operand must be aligned on a 16-byte boundary or a general-protection exception (#GP) will be generated.

Numeric Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

See Table 2-19, “Type 2 Class Exception Conditions.”




HADDPS — Packed Single Precision Floating-Point Horizontal Add

Opcode/Instruction	                                    Op/En	64/32-bit Mode	CPUID Feature Flag	Description
F2 0F 7C /r HADDPS xmm1, xmm2/m128	                    RM	    V/V         	SSE3	            Horizontal add packed single precision floating-point values from xmm2/m128 to xmm1.
VEX.128.F2.0F.WIG 7C /r VHADDPS xmm1, xmm2, xmm3/m128	RVM	    V/V	            AVX	                Horizontal add packed single precision floating-point values from xmm2 and xmm3/mem.
VEX.256.F2.0F.WIG 7C /r VHADDPS ymm1, ymm2, ymm3/m256	RVM	    V/V	            AVX	                Horizontal add packed single precision floating-point values from ymm2 and ymm3/mem.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	    Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	            N/A
RVM	    ModRM:reg (w)	    VEX.vvvv (r)	ModRM:r/m (r)	N/A

Description:

Adds the single precision floating-point values in the first and second dwords of the destination operand and stores the result in the first dword of the destination operand.

Adds single precision floating-point values in the third and fourth dword of the destination operand and stores the result in the second dword of the destination operand.

Adds single precision floating-point values in the first and second dword of the source operand and stores the result in the third dword of the destination operand.

Adds single precision floating-point values in the third and fourth dword of the source operand and stores the result in the fourth dword of the destination operand.

In 64-bit mode, use of the REX.R prefix permits this instruction to access additional registers (XMM8-XMM15).

See Figure 3-19 for HADDPS; see Figure 3-20 for VHADDPS.

128-bit Legacy SSE version: The second source can be an XMM register or an 128-bit memory location. The destination is not distinct from the first source XMM register and the upper bits (MAXVL-1:128) of the corresponding YMM register destination are unmodified.

VEX.128 encoded version: the first source operand is an XMM register or 128-bit memory location. The destination operand is an XMM register. The upper bits (MAXVL-1:128) of the corresponding YMM register destination are zeroed.

VEX.256 encoded version: The first source operand is a YMM register. The second source operand can be a YMM register or a 256-bit memory location. The destination operand is a YMM register.

Operation:

HADDPS (128-bit Legacy SSE Version):

DEST[31:0] := SRC1[63:32] + SRC1[31:0]
DEST[63:32] := SRC1[127:96] + SRC1[95:64]
DEST[95:64] := SRC2[63:32] + SRC2[31:0]
DEST[127:96] := SRC2[127:96] + SRC2[95:64]
DEST[MAXVL-1:128] (Unmodified)

VHADDPS (VEX.128 Encoded Version):

DEST[31:0] := SRC1[63:32] + SRC1[31:0]
DEST[63:32] := SRC1[127:96] + SRC1[95:64]
DEST[95:64] := SRC2[63:32] + SRC2[31:0]
DEST[127:96] := SRC2[127:96] + SRC2[95:64]
DEST[MAXVL-1:128] := 0

VHADDPS (VEX.256 Encoded Version):

DEST[31:0] := SRC1[63:32] + SRC1[31:0]
DEST[63:32] := SRC1[127:96] + SRC1[95:64]
DEST[95:64] := SRC2[63:32] + SRC2[31:0]
DEST[127:96] := SRC2[127:96] + SRC2[95:64]
DEST[159:128] := SRC1[191:160] + SRC1[159:128]
DEST[191:160] := SRC1[255:224] + SRC1[223:192]
DEST[223:192] := SRC2[191:160] + SRC2[159:128]
DEST[255:224] := SRC2[255:224] + SRC2[223:192]

Intel C/C++ Compiler Intrinsic Equivalent:

HADDPS __m128 _mm_hadd_ps (__m128 a, __m128 b);
VHADDPS __m256 _mm256_hadd_ps (__m256 a, __m256 b);

Exceptions:

When the source operand is a memory operand, the operand must be aligned on a 16-byte boundary or a general-protection exception (#GP) will be generated.

Numeric Exceptions:

Overflow, Underflow, Invalid, Precision, Denormal.

Other Exceptions:

See Table 2-19, “Type 2 Class Exception Conditions.”



KADDW/KADDB/KADDQ/KADDD — ADD Two Masks

Opcode/Instruction	                        Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.L1.0F.W0 4A /r KADDW k1, k2, k3	        RVR	    V/V	                    AVX512DQ	        Add 16 bits masks in k2 and k3 and place result in k1.
VEX.L1.66.0F.W0 4A /r KADDB k1, k2, k3	    RVR	    V/V	                    AVX512DQ	        Add 8 bits masks in k2 and k3 and place result in k1.
VEX.L1.0F.W1 4A /r KADDQ k1, k2, k3	        RVR	    V/V	                    AVX512BW	        Add 64 bits masks in k2 and k3 and place result in k1.
VEX.L1.66.0F.W1 4A /r KADDD k1, k2, k3	    RVR	    V/V	                    AVX512BW	        Add 32 bits masks in k2 and k3 and place result in k1.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3
RVR	    ModRM:reg (w)	VEX.1vvv (r)	ModRM:r/m (r, ModRM:[7:6] must be 11b)

Description:

Adds the vector mask k2 and the vector mask k3, and writes the result into vector mask k1.

Operation:

KADDW:

DEST[15:0] := SRC1[15:0] + SRC2[15:0]
DEST[MAX_KL-1:16] := 0

KADDB:

DEST[7:0] := SRC1[7:0] + SRC2[7:0]
DEST[MAX_KL-1:8] := 0

KADDQ:

DEST[63:0] := SRC1[63:0] + SRC2[63:0]
DEST[MAX_KL-1:64] := 0

KADDD:

DEST[31:0] := SRC1[31:0] + SRC2[31:0]
DEST[MAX_KL-1:32] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

KADDW __mmask16 _kadd_mask16 (__mmask16 a, __mmask16 b);
KADDB __mmask8 _kadd_mask8 (__mmask8 a, __mmask8 b);
KADDQ __mmask64 _kadd_mask64 (__mmask64 a, __mmask64 b);
KADDD __mmask32 _kadd_mask32 (__mmask32 a, __mmask32 b);

Flags Affected:

None.

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-63, “TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg).”


