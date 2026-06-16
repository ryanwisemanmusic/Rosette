LZCNT — Count the Number of Leading Zero Bits

Opcode/Instruction	                Op/En	64/32-bit Mode	CPUID Feature Flag	Description
F3 0F BD /r LZCNT r16, r/m16	    RM	    V/V	            LZCNT	            Count the number of leading zero bits in r/m16, return result in r16.
F3 0F BD /r LZCNT r32, r/m32	    RM	    V/V	            LZCNT	            Count the number of leading zero bits in r/m32, return result in r32.
F3 REX.W 0F BD /r LZCNT r64, r/m64	RM	    V/N.E.	        LZCNT	            Count the number of leading zero bits in r/m64, return result in r64.
Instruction Operand Encoding ¶

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (w)	ModRM:r/m (r)	N/A	        N/A

Description:

Counts the number of leading most significant zero bits in a source operand (second operand) returning the result into a destination (first operand).

LZCNT differs from BSR. For example, LZCNT will produce the operand size when the input operand is zero. It should be noted that on processors that do not support LZCNT, the instruction byte encoding is executed as BSR.

In 64-bit mode 64-bit operand size requires REX.W=1.

Operation:

temp := OperandSize - 1
DEST := 0
WHILE (temp >= 0) AND (Bit(SRC, temp) = 0)
DO
    temp := temp - 1
    DEST := DEST+ 1
OD
IF DEST = OperandSize
    CF := 1
ELSE
    CF := 0
FI
IF DEST = 0
    ZF := 1
ELSE
    ZF := 0
FI

Flags Affected:

ZF flag is set to 1 in case of zero output (most significant bit of the source is set), and to 0 otherwise, CF flag is set to 1 if input was zero and cleared otherwise. OF, SF, PF, and AF flags are undefined.

Intel C/C++ Compiler Intrinsic Equivalent:

LZCNT unsigned __int32 _lzcnt_u32(unsigned __int32 src);
LZCNT unsigned __int64 _lzcnt_u64(unsigned __int64 src);

Protected Mode Exceptions:

#GP(0):
	For an illegal memory operand effective address in the CS, DS, ES, FS or GS segments.
    If the DS, ES, FS, or GS register is used to access memory and it contains a null segment selector.
#SS(0):
	For an illegal address in the SS segment.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If LOCK prefix is used.

Real-Address Mode Exceptions:

#GP(0):
	If any part of the operand lies outside of the effective address space from 0 to 0FFFFH.
#SS(0):
	For an illegal address in the SS segment.
#UD:
	If LOCK prefix is used.

Virtual 8086 Mode Exceptions:

#GP(0):
	If any part of the operand lies outside of the effective address space from 0 to 0FFFFH.
#SS(0):
	For an illegal address in the SS segment.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in Protected Mode.

64-Bit Mode Exceptions:

#GP(0):
	If the memory address is in a non-canonical form.
#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If LOCK prefix is used.



TZCNT — Count the Number of Trailing Zero Bits

Opcode/Instruction	                Op/En	64/32-bit Mode	CPUID Feature Flag	Description
F3 0F BC /r TZCNT r16, r/m16	    A	    V/V	            BMI1	            Count the number of trailing zero bits in r/m16, return result in r16.
F3 0F BC /r TZCNT r32, r/m32	    A	    V/V	            BMI1	            Count the number of trailing zero bits in r/m32, return result in r32.
F3 REX.W 0F BC /r TZCNT r64, r/m64	A	    V/N.E.	        BMI1	            Count the number of trailing zero bits in r/m64, return result in r64.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
A	    ModRM:reg (w)	ModRM:r/m (r)	N/A         N/A

Description:

TZCNT counts the number of trailing least significant zero bits in source operand (second operand) and returns the result in destination operand (first operand). TZCNT is an extension of the BSF instruction. The key difference between TZCNT and BSF instruction is that TZCNT provides operand size as output when source operand is zero while in the case of BSF instruction, if source operand is zero, the content of destination operand are undefined. On processors that do not support TZCNT, the instruction byte encoding is executed as BSF.

Operation:

temp := 0
DEST := 0
DO WHILE ( (temp < OperandSize) and (SRC[ temp] = 0) )
    temp := temp +1
    DEST := DEST+ 1
OD
IF DEST = OperandSize
    CF := 1
ELSE
    CF := 0
FI
IF DEST = 0
    ZF := 1
ELSE
    ZF := 0
FI

Flags Affected:

ZF is set to 1 in case of zero output (least significant bit of the source is set), and to 0 otherwise, CF is set to 1 if the input was zero and cleared otherwise. OF, SF, PF, and AF flags are undefined.

Intel C/C++ Compiler Intrinsic Equivalent:

TZCNT unsigned __int32 _tzcnt_u32(unsigned __int32 src);
TZCNT unsigned __int64 _tzcnt_u64(unsigned __int64 src);

Protected Mode Exceptions:

#GP(0):
	For an illegal memory operand effective address in the CS, DS, ES, FS or GS segments.
    If the DS, ES, FS, or GS register is used to access memory and it contains a null segment selector.
#SS(0):
	For an illegal address in the SS segment.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If LOCK prefix is used.

Real-Address Mode Exceptions:

#GP(0):
	If any part of the operand lies outside of the effective address space from 0 to 0FFFFH.
#SS(0):
	For an illegal address in the SS segment.
#UD:
	If LOCK prefix is used.

Virtual 8086 Mode Exceptions:

#GP(0):
	If any part of the operand lies outside of the effective address space from 0 to 0FFFFH.
#SS(0):
	For an illegal address in the SS segment.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in Protected Mode.

64-Bit Mode Exceptions:

#GP(0):
	If the memory address is in a non-canonical form.
#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If LOCK prefix is used.


VPLZCNTD/VPLZCNTQ — Count the Number of Leading Zero Bits for Packed Dword, Packed Qword Values

Opcode/Instruction	                                                Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
EVEX.128.66.0F38.W0 44 /r VPLZCNTD xmm1 {k1}{z}, xmm2/m128/m32bcst	A	    V/V	                    AVX512VL AVX512CD	Count the number of leading zero bits in each dword element of xmm2/m128/m32bcst using writemask k1.
EVEX.256.66.0F38.W0 44 /r VPLZCNTD ymm1 {k1}{z}, ymm2/m256/m32bcst	A	    V/V	                    AVX512VL AVX512CD	Count the number of leading zero bits in each dword element of ymm2/m256/m32bcst using writemask k1.
EVEX.512.66.0F38.W0 44 /r VPLZCNTD zmm1 {k1}{z}, zmm2/m512/m32bcst	A	    V/V	                    AVX512CD	        Count the number of leading zero bits in each dword element of zmm2/m512/m32bcst using writemask k1.
EVEX.128.66.0F38.W1 44 /r VPLZCNTQ xmm1 {k1}{z}, xmm2/m128/m64bcst	A	    V/V	                    AVX512VL AVX512CD	Count the number of leading zero bits in each qword element of xmm2/m128/m64bcst using writemask k1.
EVEX.256.66.0F38.W1 44 /r VPLZCNTQ ymm1 {k1}{z}, ymm2/m256/m64bcst	A	    V/V	                    AVX512VL AVX512CD	Count the number of leading zero bits in each qword element of ymm2/m256/m64bcst using writemask k1.
EVEX.512.66.0F38.W1 44 /r VPLZCNTQ zmm1 {k1}{z}, zmm2/m512/m64bcst	A	    V/V                     AVX512CD	        Count the number of leading zero bits in each qword element of zmm2/m512/m64bcst using writemask k1.

Instruction Operand Encoding:

Op/En	Tuple Type	Operand 1	    Operand 2	    Operand 3	Operand 4
A	    Full	    ModRM:reg (w)	ModRM:r/m (r)	N/A	        N/A

Description:

Counts the number of leading most significant zero bits in each dword or qword element of the source operand (the second operand) and stores the results in the destination register (the first operand) according to the writemask. If an element is zero, the result for that element is the operand size of the element.

EVEX.512 encoded version: The source operand is a ZMM register, a 512-bit memory location, or a 512-bit vector broadcasted from a 32/64-bit memory location. The destination operand is a ZMM register, conditionally updated using writemask k1.

EVEX.256 encoded version: The source operand is a YMM register, a 256-bit memory location, or a 256-bit vector broadcasted from a 32/64-bit memory location. The destination operand is a YMM register, conditionally updated using writemask k1.

EVEX.128 encoded version: The source operand is a XMM register, a 128-bit memory location, or a 128-bit vector broadcasted from a 32/64-bit memory location. The destination operand is a XMM register, conditionally updated using writemask k1.

EVEX.vvvv is reserved and must be 1111b otherwise instructions will #UD.

Operation:

VPLZCNTD:

(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j*32
    IF MaskBit(j) OR *no writemask*
        THEN
                temp := 32
                DEST[i+31:i] := 0
                WHILE (temp > 0) AND (SRC[i+temp-1] = 0)
                DO
                    temp := temp – 1
                    DEST[i+31:i] := DEST[i+31:i] + 1
                OD
        ELSE
            IF *merging-masking*
                THEN *DEST[i+31:i] remains unchanged*
                ELSE DEST[i+31:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0

VPLZCNTQ:

(KL, VL) = (2, 128), (4, 256), (8, 512)
FOR j := 0 TO KL-1
    i := j*64
    IF MaskBit(j) OR *no writemask*
        THEN
                temp := 64
                DEST[i+63:i] := 0
                WHILE (temp > 0) AND (SRC[i+temp-1] = 0)
                DO
                    temp := temp – 1
                    DEST[i+63:i] := DEST[i+63:i] + 1
                OD
        ELSE
            IF *merging-masking*
                THEN *DEST[i+63:i] remains unchanged*
                ELSE DEST[i+63:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VPLZCNTD __m512i _mm512_lzcnt_epi32(__m512i a);
VPLZCNTD __m512i _mm512_mask_lzcnt_epi32(__m512i s, __mmask16 m, __m512i a);
VPLZCNTD __m512i _mm512_maskz_lzcnt_epi32( __mmask16 m, __m512i a);
VPLZCNTQ __m512i _mm512_lzcnt_epi64(__m512i a);
VPLZCNTQ __m512i _mm512_mask_lzcnt_epi64(__m512i s, __mmask8 m, __m512i a);
VPLZCNTQ __m512i _mm512_maskz_lzcnt_epi64(__mmask8 m, __m512i a);
VPLZCNTD __m256i _mm256_lzcnt_epi32(__m256i a);
VPLZCNTD __m256i _mm256_mask_lzcnt_epi32(__m256i s, __mmask8 m, __m256i a);
VPLZCNTD __m256i _mm256_maskz_lzcnt_epi32( __mmask8 m, __m256i a);
VPLZCNTQ __m256i _mm256_lzcnt_epi64(__m256i a);
VPLZCNTQ __m256i _mm256_mask_lzcnt_epi64(__m256i s, __mmask8 m, __m256i a);
VPLZCNTQ __m256i _mm256_maskz_lzcnt_epi64(__mmask8 m, __m256i a);
VPLZCNTD __m128i _mm_lzcnt_epi32(__m128i a);
VPLZCNTD __m128i _mm_mask_lzcnt_epi32(__m128i s, __mmask8 m, __m128i a);
VPLZCNTD __m128i _mm_maskz_lzcnt_epi32( __mmask8 m, __m128i a);
VPLZCNTQ __m128i _mm_lzcnt_epi64(__m128i a);
VPLZCNTQ __m128i _mm_mask_lzcnt_epi64(__m128i s, __mmask8 m, __m128i a);
VPLZCNTQ __m128i _mm_maskz_lzcnt_epi64(__mmask8 m, __m128i a);

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

EVEX-encoded instruction, see Table 2-49, “Type E4 Class Exception Conditions.”



