KNOTW/KNOTB/KNOTQ/KNOTD — NOT Mask Register

Opcode/Instruction	                Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.L0.0F.W0 44 /r KNOTW k1, k2	    RR	    V/V	                    AVX512F	            Bitwise NOT of 16 bits mask k2.
VEX.L0.66.0F.W0 44 /r KNOTB k1, k2	RR	    V/V	                    AVX512DQ	        Bitwise NOT of 8 bits mask k2.
VEX.L0.0F.W1 44 /r KNOTQ k1, k2	    RR	    V/V	                    AVX512BW	        Bitwise NOT of 64 bits mask k2.
VEX.L0.66.0F.W1 44 /r KNOTD k1, k2	RR	    V/V	                    AVX512BW	        Bitwise NOT of 32 bits mask k2.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2
RR	    ModRM:reg (w)	ModRM:r/m (r, ModRM:[7:6] must be 11b)

Description:

Performs a bitwise NOT of vector mask k2 and writes the result into vector mask k1.

Operation:

KNOTW:

DEST[15:0] := BITWISE NOT SRC[15:0]
DEST[MAX_KL-1:16] := 0

KNOTB:

DEST[7:0] := BITWISE NOT SRC[7:0]
DEST[MAX_KL-1:8] := 0

KNOTQ:

DEST[63:0] := BITWISE NOT SRC[63:0]
DEST[MAX_KL-1:64] := 0

KNOTD:

DEST[31:0] := BITWISE NOT SRC[31:0]
DEST[MAX_KL-1:32] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

KNOTW __mmask16 _mm512_knot(__mmask16 a);

Flags Affected:

None.

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-63, “TYPE K20 Exception Definition (VEX-Encoded OpMask Instructions w/o Memory Arg).”


NOT — One's Complement Negation

Opcode	        Instruction	Op/En	64-Bit Mode	Compat/Leg Mode	Description
F6 /2	        NOT r/m8	M	    Valid	    Valid	        Reverse each bit of r/m8.
REX + F6 /2	    NOT r/m81	M	    Valid	    N.E.	        Reverse each bit of r/m8.
F7 /2	        NOT r/m16	M	    Valid	    Valid	        Reverse each bit of r/m16.
F7 /2	        NOT r/m32	M	    Valid	    Valid	        Reverse each bit of r/m32.
REX.W + F7 /2	NOT r/m64	M	    Valid	    N.E.	        Reverse each bit of r/m64.
1. In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r, w)	N/A	        N/A	        N/A

Description:

Performs a bitwise NOT operation (each 1 is set to 0, and each 0 is set to 1) on the destination operand and stores the result in the destination operand location. The destination operand can be a register or a memory location.

This instruction can be used with a LOCK prefix to allow the instruction to be executed atomically.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

DEST := NOT DEST;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the destination operand points to a non-writable segment.
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register contains a NULL segment selector.
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

Same as for protected mode exceptions.

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