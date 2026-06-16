CMOVcc — Conditional Move

Opcode	            Instruction	        Op/En	64-Bit Mode	Compat/Leg Mode	Description
0F 47 /r	        CMOVA r16, r/m16	RM	    Valid	    Valid	        Move if above (CF=0 and ZF=0).
0F 47 /r	        CMOVA r32, r/m32	RM	    Valid	    Valid	        Move if above (CF=0 and ZF=0).
REX.W + 0F 47 /r	CMOVA r64, r/m64	RM	    Valid	    N.E.	        Move if above (CF=0 and ZF=0).
0F 43 /r	        CMOVAE r16, r/m16	RM	    Valid	    Valid	        Move if above or equal (CF=0).
0F 43 /r	        CMOVAE r32, r/m32	RM	    Valid	    Valid	        Move if above or equal (CF=0).
REX.W + 0F 43 /r	CMOVAE r64, r/m64	RM	    Valid	    N.E.	        Move if above or equal (CF=0).
0F 42 /r	        CMOVB r16, r/m16	RM	    Valid	    Valid	        Move if below (CF=1).
0F 42 /r	        CMOVB r32, r/m32	RM	    Valid	    Valid	        Move if below (CF=1).
REX.W + 0F 42 /r	CMOVB r64, r/m64	RM	    Valid	    N.E.	        Move if below (CF=1).
0F 46 /r	        CMOVBE r16, r/m16	RM	    Valid	    Valid	        Move if below or equal (CF=1 or ZF=1).
0F 46 /r	        CMOVBE r32, r/m32	RM	    Valid	    Valid	        Move if below or equal (CF=1 or ZF=1).
REX.W + 0F 46 /r	CMOVBE r64, r/m64	RM	    Valid	    N.E.	        Move if below or equal (CF=1 or ZF=1).
0F 42 /r	        CMOVC r16, r/m16	RM	    Valid	    Valid	        Move if carry (CF=1).
0F 42 /r	        CMOVC r32, r/m32	RM	    Valid	    Valid	        Move if carry (CF=1).
REX.W + 0F 42 /r	CMOVC r64, r/m64	RM	    Valid	    N.E.	        Move if carry (CF=1).
0F 44 /r	        CMOVE r16, r/m16	RM	    Valid	    Valid	        Move if equal (ZF=1).
0F 44 /r	        CMOVE r32, r/m32	RM	    Valid	    Valid	        Move if equal (ZF=1).
REX.W + 0F 44 /r	CMOVE r64, r/m64	RM	    Valid	    N.E.	        Move if equal (ZF=1).
0F 4F /r	        CMOVG r16, r/m16	RM	    Valid	    Valid	        Move if greater (ZF=0 and SF=OF).
0F 4F /r	        CMOVG r32, r/m32	RM	    Valid	    Valid	        Move if greater (ZF=0 and SF=OF).
REX.W + 0F 4F /r	CMOVG r64, r/m64	RM	    V/N.E.	    N/A	            Move if greater (ZF=0 and SF=OF).
0F 4D /r	        CMOVGE r16, r/m16	RM	    Valid	    Valid	        Move if greater or equal (SF=OF).
0F 4D /r	        CMOVGE r32, r/m32	RM	    Valid	    Valid	        Move if greater or equal (SF=OF).
REX.W + 0F 4D /r	CMOVGE r64, r/m64	RM	    Valid	    N.E.	        Move if greater or equal (SF=OF).
0F 4C /r	        CMOVL r16, r/m16	RM	    Valid	    Valid	        Move if less (SF≠ OF).
0F 4C /r	        CMOVL r32, r/m32	RM	    Valid	    Valid	        Move if less (SF≠ OF).
REX.W + 0F 4C /r	CMOVL r64, r/m64	RM	    Valid	    N.E.	        Move if less (SF≠ OF).
0F 4E /r	        CMOVLE r16, r/m16	RM	    Valid	    Valid	        Move if less or equal (ZF=1 or SF≠ OF).
0F 4E /r	        CMOVLE r32, r/m32	RM	    Valid	    Valid	        Move if less or equal (ZF=1 or SF≠ OF).
REX.W + 0F 4E /r	CMOVLE r64, r/m64	RM	    Valid	    N.E.	        Move if less or equal (ZF=1 or SF≠ OF).
0F 46 /r	        CMOVNA r16, r/m16	RM	    Valid	    Valid	        Move if not above (CF=1 or ZF=1).
0F 46 /r	        CMOVNA r32, r/m32	RM	    Valid	    Valid	        Move if not above (CF=1 or ZF=1).
REX.W + 0F 46 /r	CMOVNA r64, r/m64	RM	    Valid	    N.E.	        Move if not above (CF=1 or ZF=1).
0F 42 /r	        CMOVNAE r16, r/m16	RM	    Valid	    Valid	        Move if not above or equal (CF=1).
0F 42 /r	        CMOVNAE r32, r/m32	RM	    Valid	    Valid	        Move if not above or equal (CF=1).
REX.W + 0F 42 /r	CMOVNAE r64, r/m64	RM	    Valid	    N.E.	        Move if not above or equal (CF=1).
0F 43 /r	        CMOVNB r16, r/m16	RM	    Valid	    Valid	        Move if not below (CF=0).
0F 43 /r	        CMOVNB r32, r/m32	RM	    Valid	    Valid	        Move if not below (CF=0).
REX.W + 0F 43 /r	CMOVNB r64, r/m64	RM	    Valid	    N.E.	        Move if not below (CF=0).
0F 47 /r	        CMOVNBE r16, r/m16	RM	    Valid	    Valid	        Move if not below or equal (CF=0 and ZF=0).
0F 47 /r	        CMOVNBE r32, r/m32	RM	    Valid	    Valid	        Move if not below or equal (CF=0 and ZF=0).
REX.W + 0F 47 /r	CMOVNBE r64, r/m64	RM	    Valid	    N.E.	        Move if not below or equal (CF=0 and ZF=0).
0F 43 /r	        CMOVNC r16, r/m16	RM	    Valid	    Valid	        Move if not carry (CF=0).
0F 43 /r	        CMOVNC r32, r/m32	RM	    Valid	    Valid	        Move if not carry (CF=0).
REX.W + 0F 43 /r	CMOVNC r64, r/m64	RM	    Valid	    N.E.	        Move if not carry (CF=0).
0F 45 /r	        CMOVNE r16, r/m16	RM	    Valid	    Valid	        Move if not equal (ZF=0).
0F 45 /r	        CMOVNE r32, r/m32	RM	    Valid	    Valid	        Move if not equal (ZF=0).
REX.W + 0F 45 /r	CMOVNE r64, r/m64	RM	    Valid	    N.E.	        Move if not equal (ZF=0).
0F 4E /r	        CMOVNG r16, r/m16	RM	    Valid	    Valid	        Move if not greater (ZF=1 or SF≠ OF).
0F 4E /r	        CMOVNG r32, r/m32	RM	    Valid	    Valid	        Move if not greater (ZF=1 or SF≠ OF).
REX.W + 0F 4E /r	CMOVNG r64, r/m64	RM	    Valid	    N.E.	        Move if not greater (ZF=1 or SF≠ OF).
0F 4C /r	        CMOVNGE r16, r/m16	RM	    Valid	    Valid	        Move if not greater or equal (SF≠ OF).
0F 4C /r	        CMOVNGE r32, r/m32	RM	    Valid	    Valid	        Move if not greater or equal (SF≠ OF).
REX.W + 0F 4C /r	CMOVNGE r64, r/m64	RM	    Valid	    N.E.	        Move if not greater or equal (SF≠ OF).
0F 4D /r	        CMOVNL r16, r/m16	RM	    Valid	    Valid	        Move if not less (SF=OF).
0F 4D /r	        CMOVNL r32, r/m32	RM	    Valid	    Valid	        Move if not less (SF=OF).
REX.W + 0F 4D /r	CMOVNL r64, r/m64	RM	    Valid	    N.E.	        Move if not less (SF=OF).
0F 4F /r	        CMOVNLE r16, r/m16	RM	    Valid	    Valid	        Move if not less or equal (ZF=0 and SF=OF).
0F 4F /r	        CMOVNLE r32, r/m32	RM	    Valid	    Valid	        Move if not less or equal (ZF=0 and SF=OF).
REX.W + 0F 4F /r	CMOVNLE r64, r/m64	RM	    Valid	    N.E.	        Move if not less or equal (ZF=0 and SF=OF).
0F 41 /r	        CMOVNO r16, r/m16	RM	    Valid	    Valid	        Move if not overflow (OF=0).
0F 41 /r	        CMOVNO r32, r/m32	RM	    Valid	    Valid	        Move if not overflow (OF=0).
REX.W + 0F 41 /r	CMOVNO r64, r/m64	RM	    Valid	    N.E.	        Move if not overflow (OF=0).
0F 4B /r	        CMOVNP r16, r/m16	RM	    Valid	    Valid	        Move if not parity (PF=0).
0F 4B /r	        CMOVNP r32, r/m32	RM	    Valid	    Valid	        Move if not parity (PF=0).
REX.W + 0F 4B /r	CMOVNP r64, r/m64	RM	    Valid	    N.E.	        Move if not parity (PF=0).
0F 49 /r	        CMOVNS r16, r/m16	RM	    Valid	    Valid	        Move if not sign (SF=0).
0F 49 /r	        CMOVNS r32, r/m32	RM	    Valid	    Valid	        Move if not sign (SF=0).
REX.W + 0F 49 /r	CMOVNS r64, r/m64	RM	    Valid	    N.E.	        Move if not sign (SF=0).
0F 45 /r	        CMOVNZ r16, r/m16	RM	    Valid	    Valid	        Move if not zero (ZF=0).
0F 45 /r	        CMOVNZ r32, r/m32	RM	    Valid	    Valid	        Move if not zero (ZF=0).
REX.W + 0F 45 /r	CMOVNZ r64, r/m64	RM	    Valid	    N.E.	        Move if not zero (ZF=0).
0F 40 /r	        CMOVO r16, r/m16	RM	    Valid	    Valid	        Move if overflow (OF=1).
0F 40 /r	        CMOVO r32, r/m32	RM	    Valid	    Valid	        Move if overflow (OF=1).
REX.W + 0F 40 /r	CMOVO r64, r/m64	RM	    Valid	    N.E.	        Move if overflow (OF=1).
0F 4A /r	        CMOVP r16, r/m16	RM	    Valid	    Valid	        Move if parity (PF=1).
0F 4A /r	        CMOVP r32, r/m32	RM	    Valid	    Valid	        Move if parity (PF=1).
REX.W + 0F 4A /r	CMOVP r64, r/m64	RM	    Valid	    N.E.	        Move if parity (PF=1).
0F 4A /r	        CMOVPE r16, r/m16	RM	    Valid	    Valid	        Move if parity even (PF=1).
0F 4A /r	        CMOVPE r32, r/m32	RM	    Valid	    Valid	        Move if parity even (PF=1).
REX.W + 0F 4A /r	CMOVPE r64, r/m64	RM	    Valid	    N.E.	        Move if parity even (PF=1).
0F 4B /r	        CMOVPO r16, r/m16	RM	    Valid	    Valid	        Move if parity odd (PF=0).
0F 4B /r	        CMOVPO r32, r/m32	RM	    Valid	    Valid	        Move if parity odd (PF=0).
REX.W + 0F 4B /r	CMOVPO r64, r/m64	RM	    Valid	    N.E.	        Move if parity odd (PF=0).
0F 48 /r	        CMOVS r16, r/m16	RM	    Valid	    Valid	        Move if sign (SF=1).
0F 48 /r	        CMOVS r32, r/m32	RM	    Valid	    Valid	        Move if sign (SF=1).
REX.W + 0F 48 /r	CMOVS r64, r/m64	RM	    Valid	    N.E.	        Move if sign (SF=1).
0F 44 /r	        CMOVZ r16, r/m16	RM	    Valid	    Valid	        Move if zero (ZF=1).
0F 44 /r	        CMOVZ r32, r/m32	RM	    Valid	    Valid	        Move if zero (ZF=1).
REX.W + 0F 44 /r	CMOVZ r64, r/m64	RM	    Valid	    N.E.	        Move if zero (ZF=1).

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r, w)	ModRM:r/m (r)	N/A	        N/A

Description:

Each of the CMOVcc instructions performs a move operation if the status flags in the EFLAGS register (CF, OF, PF, SF, and ZF) are in a specified state (or condition). A condition code (cc) is associated with each instruction to indicate the condition being tested for. If the condition is not satisfied, a move is not performed and execution continues with the instruction following the CMOVcc instruction.

Specifically, CMOVcc loads data from its source operand into a temporary register unconditionally (regardless of the condition code and the status flags in the EFLAGS register). If the condition code associated with the instruction (cc) is satisfied, the data in the temporary register is then copied into the instruction's destination operand.

These instructions can move 16-bit, 32-bit or 64-bit values from memory to a general-purpose register or from one general-purpose register to another. Conditional moves of 8-bit register operands are not supported.

The condition for each CMOVcc mnemonic is given in the description column of the above table. The terms “less” and “greater” are used for comparisons of signed integers and the terms “above” and “below” are used for unsigned integers.

Because a particular state of the status flags can sometimes be interpreted in two ways, two mnemonics are defined for some opcodes. For example, the CMOVA (conditional move if above) instruction and the CMOVNBE (conditional move if not below or equal) instruction are alternate mnemonics for the opcode 0F 47H.

The CMOVcc instructions were introduced in P6 family processors; however, these instructions may not be supported by all IA-32 processors. Software can determine if the CMOVcc instructions are supported by checking the processor’s feature information with the CPUID instruction (see “CPUID—CPU Identification” in this chapter).

In 64-bit mode, the instruction’s default operation size is 32 bits. Use of the REX.R prefix permits access to additional registers (R8-R15). Use of the REX.W prefix promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

temp := SRC
IF condition TRUE
    THEN DEST := temp;
ELSE IF (OperandSize = 32 and IA-32e mode active)
    THEN DEST[63:32] := 0;
FI;

Flags Affected:

None.

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
#PF(fault-code):
	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If the LOCK prefix is used.


FCMOVcc — Floating-Point Conditional Move

Opcode1

Instruction	                    64-Bit Mode	Compat/ 1 Leg Mode	Description
DA C0+i	FCMOVB ST(0), ST(i)	    Valid	    Valid	            Move if below (CF=1).
DA C8+i	FCMOVE ST(0), ST(i)	    Valid	    Valid	            Move if equal (ZF=1).
DA D0+i	FCMOVBE ST(0), ST(i)	Valid	    Valid	            Move if below or equal (CF=1 or ZF=1).
DA D8+i	FCMOVU ST(0), ST(i)	    Valid	    Valid	            Move if unordered (PF=1).
DB C0+i	FCMOVNB ST(0), ST(i)	Valid	    Valid	            Move if not below (CF=0).
DB C8+i	FCMOVNE ST(0), ST(i)	Valid	    Valid	            Move if not equal (ZF=0).
DB D0+i	FCMOVNBE ST(0), ST(i)	Valid	    Valid	            Move if not below or equal (CF=0 and ZF=0).
DB D8+i	FCMOVNU ST(0), ST(i)	Valid	    Valid	            Move if not unordered (PF=0).

1. See IA-32 Architecture Compatibility section below.

Description:

Tests the status flags in the EFLAGS register and moves the source operand (second operand) to the destination operand (first operand) if the given test condition is true. The condition for each mnemonic os given in the Description column above and in Chapter 8 in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1. The source operand is always in the ST(i) register and the destination operand is always ST(0).

The FCMOVcc instructions are useful for optimizing small IF constructions. They also help eliminate branching overhead for IF operations and the possibility of branch mispredictions by the processor.

A processor may not support the FCMOVcc instructions. Software can check if the FCMOVcc instructions are supported by checking the processor’s feature information with the CPUID instruction (see “COMISS—Compare Scalar Ordered Single Precision Floating-Point Values and Set EFLAGS” in this chapter). If both the CMOV and FPU feature bits are set, the FCMOVcc instructions are supported.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

IA-32 Architecture Compatibility:

The FCMOVcc instructions were introduced to the IA-32 Architecture in the P6 family processors and are not available in earlier IA-32 processors.

Operation:

IF condition TRUE
    THEN ST(0) := ST(i);
FI;

FPU Flags Affected:

C1	Set to 0 if stack underflow occurred.
C0, C2, C3	Undefined.

Floating-Point Exceptions:

#IS:
	Stack underflow occurred.

Integer Flags Affected:

None.

Protected Mode Exceptions:

#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
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


VMASKMOV — Conditional SIMD Packed Loads and Stores

Opcode/Instruction	                                    Op/En	64/32-bit Mode	CPUID Feature Flag	Description
VEX.128.66.0F38.W0 2C /r VMASKMOVPS xmm1, xmm2, m128	RV M	V/V	            AVX	                Conditionally load packed single-precision values from m128 using mask in xmm2 and store in xmm1.
VEX.256.66.0F38.W0 2C /r VMASKMOVPS ymm1, ymm2, m256	RV M	V/V	            AVX	                Conditionally load packed single-precision values from m256 using mask in ymm2 and store in ymm1.
VEX.128.66.0F38.W0 2D /r VMASKMOVPD xmm1, xmm2, m128	RV M	V/V	            AVX	                Conditionally load packed double precision values from m128 using mask in xmm2 and store in xmm1.
VEX.256.66.0F38.W0 2D /r VMASKMOVPD ymm1, ymm2, m256	RV M	V/V	            AVX	                Conditionally load packed double precision values from m256 using mask in ymm2 and store in ymm1.
VEX.128.66.0F38.W0 2E /r VMASKMOVPS m128, xmm1, xmm2	MV R	V/V	            AVX	                Conditionally store packed single-precision values from xmm2 using mask in xmm1.
VEX.256.66.0F38.W0 2E /r VMASKMOVPS m256, ymm1, ymm2	MV R	V/V	            AVX	                Conditionally store packed single-precision values from ymm2 using mask in ymm1.
VEX.128.66.0F38.W0 2F /r VMASKMOVPD m128, xmm1, xmm2	MV R	V/V	            AVX	                Conditionally store packed double precision values from xmm2 using mask in xmm1.
VEX.256.66.0F38.W0 2F /r VMASKMOVPD m256, ymm1, ymm2	MV R	V/V	            AVX	                Conditionally store packed double precision values from ymm2 using mask in ymm1.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	    Operand 4
RVM 	ModRM:reg (w)	VEX.vvvv (r)	ModRM:r/m (r)	N/A
MVR	    ModRM:r/m (w)	VEX.vvvv (r)	ModRM:reg (r)	N/A

Description:

Conditionally moves packed data elements from the second source operand into the corresponding data element of the destination operand, depending on the mask bits associated with each data element. The mask bits are specified in the first source operand.

The mask bit for each data element is the most significant bit of that element in the first source operand. If a mask is 1, the corresponding data element is copied from the second source operand to the destination operand. If the mask is 0, the corresponding data element is set to zero in the load form of these instructions, and unmodified in the store form.

The second source operand is a memory address for the load form of these instruction. The destination operand is a memory address for the store form of these instructions. The other operands are both XMM registers (for VEX.128 version) or YMM registers (for VEX.256 version).

Faults occur only due to mask-bit required memory accesses that caused the faults. Faults will not occur due to referencing any memory location if the corresponding mask bit for that memory location is 0. For example, no faults will be detected if the mask bits are all zero.

Unlike previous MASKMOV instructions (MASKMOVQ and MASKMOVDQU), a nontemporal hint is not applied to these instructions.

Instruction behavior on alignment check reporting with mask bits of less than all 1s are the same as with mask bits of all 1s.

VMASKMOV should not be used to access memory mapped I/O and un-cached memory as the access and the ordering of the individual loads or stores it does is implementation specific.

In cases where mask bits indicate data should not be loaded or stored paging A and D bits will be set in an implementation dependent way. However, A and D bits are always set for pages where data is actually loaded/stored.

Note: for load forms, the first source (the mask) is encoded in VEX.vvvv; the second source is encoded in rm_field, and the destination register is encoded in reg_field.

Note: for store forms, the first source (the mask) is encoded in VEX.vvvv; the second source register is encoded in reg_field, and the destination memory location is encoded in rm_field.

Operation:

VMASKMOVPS -128-bit load:

DEST[31:0] := IF (SRC1[31]) Load_32(mem) ELSE 0
DEST[63:32] := IF (SRC1[63]) Load_32(mem + 4) ELSE 0
DEST[95:64] := IF (SRC1[95]) Load_32(mem + 8) ELSE 0
DEST[127:97] := IF (SRC1[127]) Load_32(mem + 12) ELSE 0
DEST[MAXVL-1:128] := 0

VMASKMOVPS - 256-bit load:

DEST[31:0] := IF (SRC1[31]) Load_32(mem) ELSE 0
DEST[63:32] := IF (SRC1[63]) Load_32(mem + 4) ELSE 0
DEST[95:64] := IF (SRC1[95]) Load_32(mem + 8) ELSE 0
DEST[127:96] := IF (SRC1[127]) Load_32(mem + 12) ELSE 0
DEST[159:128] := IF (SRC1[159]) Load_32(mem + 16) ELSE 0
DEST[191:160] := IF (SRC1[191]) Load_32(mem + 20) ELSE 0
DEST[223:192] := IF (SRC1[223]) Load_32(mem + 24) ELSE 0
DEST[255:224] := IF (SRC1[255]) Load_32(mem + 28) ELSE 0

VMASKMOVPD - 128-bit load:

DEST[63:0] := IF (SRC1[63]) Load_64(mem) ELSE 0
DEST[127:64] := IF (SRC1[127]) Load_64(mem + 16) ELSE 0
DEST[MAXVL-1:128] := 0

VMASKMOVPD - 256-bit load:

DEST[63:0] := IF (SRC1[63]) Load_64(mem) ELSE 0
DEST[127:64] := IF (SRC1[127]) Load_64(mem + 8) ELSE 0
DEST[195:128] := IF (SRC1[191]) Load_64(mem + 16) ELSE 0
DEST[255:196] := IF (SRC1[255]) Load_64(mem + 24) ELSE 0

VMASKMOVPS - 128-bit store:

IF (SRC1[31]) DEST[31:0] := SRC2[31:0]
IF (SRC1[63]) DEST[63:32] := SRC2[63:32]
IF (SRC1[95]) DEST[95:64] := SRC2[95:64]
IF (SRC1[127]) DEST[127:96] := SRC2[127:96]

VMASKMOVPS - 256-bit store:

IF (SRC1[31]) DEST[31:0] := SRC2[31:0]
IF (SRC1[63]) DEST[63:32] := SRC2[63:32]
IF (SRC1[95]) DEST[95:64] := SRC2[95:64]
IF (SRC1[127]) DEST[127:96] := SRC2[127:96]
IF (SRC1[159]) DEST[159:128] :=SRC2[159:128]
IF (SRC1[191]) DEST[191:160] := SRC2[191:160]
IF (SRC1[223]) DEST[223:192] := SRC2[223:192]
IF (SRC1[255]) DEST[255:224] := SRC2[255:224]

VMASKMOVPD - 128-bit store:

IF (SRC1[63]) DEST[63:0] := SRC2[63:0]
IF (SRC1[127]) DEST[127:64] := SRC2[127:64]

VMASKMOVPD - 256-bit store:

IF (SRC1[63]) DEST[63:0] := SRC2[63:0]
IF (SRC1[127]) DEST[127:64] := SRC2[127:64]
IF (SRC1[191]) DEST[191:128] := SRC2[191:128]
IF (SRC1[255]) DEST[255:192] := SRC2[255:192]

Intel C/C++ Compiler Intrinsic Equivalent:

__m256 _mm256_maskload_ps(float const *a, __m256i mask)
void _mm256_maskstore_ps(float *a, __m256i mask, __m256 b)
__m256d _mm256_maskload_pd(double *a, __m256i mask);
void _mm256_maskstore_pd(double *a, __m256i mask, __m256d b);
__m128 _mm_maskload_ps(float const *a, __m128i mask)
void _mm_maskstore_ps(float *a, __m128i mask, __m128 b)
__m128d _mm_maskload_pd(double const *a, __m128i mask);
void _mm_maskstore_pd(double *a, __m128i mask, __m128d b);

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-23, “Type 6 Class Exception Conditions” (No AC# reported for any mask bit combinations).

Additionally:

#UD	If VEX.W = 1.




VPMASKMOV — Conditional SIMD Integer Packed Loads and Stores

Opcode/Instruction	Op/En	64/32 -bit Mode	CPUID Feature Flag	Description
VEX.128.66.0F38.W0 8C /r VPMASKMOVD xmm1, xmm2, m128	RVM	V/V	AVX2	Conditionally load dword values from m128 using mask in xmm2 and store in xmm1.
VEX.256.66.0F38.W0 8C /r VPMASKMOVD ymm1, ymm2, m256	RVM	V/V	AVX2	Conditionally load dword values from m256 using mask in ymm2 and store in ymm1.
VEX.128.66.0F38.W1 8C /r VPMASKMOVQ xmm1, xmm2, m128	RVM	V/V	AVX2	Conditionally load qword values from m128 using mask in xmm2 and store in xmm1.
VEX.256.66.0F38.W1 8C /r VPMASKMOVQ ymm1, ymm2, m256	RVM	V/V	AVX2	Conditionally load qword values from m256 using mask in ymm2 and store in ymm1.
VEX.128.66.0F38.W0 8E /r VPMASKMOVD m128, xmm1, xmm2	MVR	V/V	AVX2	Conditionally store dword values from xmm2 using mask in xmm1.
VEX.256.66.0F38.W0 8E /r VPMASKMOVD m256, ymm1, ymm2	MVR	V/V	AVX2	Conditionally store dword values from ymm2 using mask in ymm1.
VEX.128.66.0F38.W1 8E /r VPMASKMOVQ m128, xmm1, xmm2	MVR	V/V	AVX2	Conditionally store qword values from xmm2 using mask in xmm1.
VEX.256.66.0F38.W1 8E /r VPMASKMOVQ m256, ymm1, ymm2	MVR	V/V	AVX2	Conditionally store qword values from ymm2 using mask in ymm1.
Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
RVM	ModRM:reg (w)	VEX.vvvv (r)	ModRM:r/m (r)	N/A
MVR	ModRM:r/m (w)	VEX.vvvv (r)	ModRM:reg (r)	N/A

Description:

Conditionally moves packed data elements from the second source operand into the corresponding data element of the destination operand, depending on the mask bits associated with each data element. The mask bits are specified in the first source operand.

The mask bit for each data element is the most significant bit of that element in the first source operand. If a mask is 1, the corresponding data element is copied from the second source operand to the destination operand. If the mask is 0, the corresponding data element is set to zero in the load form of these instructions, and unmodified in the store form.

The second source operand is a memory address for the load form of these instructions. The destination operand is a memory address for the store form of these instructions. The other operands are either XMM registers (for VEX.128 version) or YMM registers (for VEX.256 version).

Faults occur only due to mask-bit required memory accesses that caused the faults. Faults will not occur due to referencing any memory location if the corresponding mask bit for that memory location is 0. For example, no faults will be detected if the mask bits are all zero.

Unlike previous MASKMOV instructions (MASKMOVQ and MASKMOVDQU), a nontemporal hint is not applied to these instructions.

Instruction behavior on alignment check reporting with mask bits of less than all 1s are the same as with mask bits of all 1s.

VMASKMOV should not be used to access memory mapped I/O as the ordering of the individual loads or stores it does is implementation specific.

In cases where mask bits indicate data should not be loaded or stored paging A and D bits will be set in an implementation dependent way. However, A and D bits are always set for pages where data is actually loaded/stored.

Note: for load forms, the first source (the mask) is encoded in VEX.vvvv; the second source is encoded in rm_field, and the destination register is encoded in reg_field.

Note: for store forms, the first source (the mask) is encoded in VEX.vvvv; the second source register is encoded in reg_field, and the destination memory location is encoded in rm_field.

Operation:

VPMASKMOVD - 256-bit load:

DEST[31:0] := IF (SRC1[31]) Load_32(mem) ELSE 0
DEST[63:32] := IF (SRC1[63]) Load_32(mem + 4) ELSE 0
DEST[95:64] := IF (SRC1[95]) Load_32(mem + 8) ELSE 0
DEST[127:96] := IF (SRC1[127]) Load_32(mem + 12) ELSE 0
DEST[159:128] := IF (SRC1[159]) Load_32(mem + 16) ELSE 0
DEST[191:160] := IF (SRC1[191]) Load_32(mem + 20) ELSE 0
DEST[223:192] := IF (SRC1[223]) Load_32(mem + 24) ELSE 0
DEST[255:224] := IF (SRC1[255]) Load_32(mem + 28) ELSE 0

VPMASKMOVD -128-bit load:

DEST[31:0] := IF (SRC1[31]) Load_32(mem) ELSE 0
DEST[63:32] := IF (SRC1[63]) Load_32(mem + 4) ELSE 0
DEST[95:64] := IF (SRC1[95]) Load_32(mem + 8) ELSE 0
DEST[127:97] := IF (SRC1[127]) Load_32(mem + 12) ELSE 0
DEST[MAXVL-1:128] := 0

VPMASKMOVQ - 256-bit load:

DEST[63:0] := IF (SRC1[63]) Load_64(mem) ELSE 0
DEST[127:64] := IF (SRC1[127]) Load_64(mem + 8) ELSE 0
DEST[195:128] := IF (SRC1[191]) Load_64(mem + 16) ELSE 0
DEST[255:196] := IF (SRC1[255]) Load_64(mem + 24) ELSE 0

VPMASKMOVQ - 128-bit load:

DEST[63:0] := IF (SRC1[63]) Load_64(mem) ELSE 0
DEST[127:64] := IF (SRC1[127]) Load_64(mem + 16) ELSE 0
DEST[MAXVL-1:128] := 0

VPMASKMOVD - 256-bit store:

IF (SRC1[31]) DEST[31:0] := SRC2[31:0]
IF (SRC1[63]) DEST[63:32] := SRC2[63:32]
IF (SRC1[95]) DEST[95:64] := SRC2[95:64]
IF (SRC1[127]) DEST[127:96] := SRC2[127:96]
IF (SRC1[159]) DEST[159:128] :=SRC2[159:128]
IF (SRC1[191]) DEST[191:160] := SRC2[191:160]
IF (SRC1[223]) DEST[223:192] := SRC2[223:192]
IF (SRC1[255]) DEST[255:224] := SRC2[255:224]

VPMASKMOVD - 128-bit store:

IF (SRC1[31]) DEST[31:0] := SRC2[31:0]
IF (SRC1[63]) DEST[63:32] := SRC2[63:32]
IF (SRC1[95]) DEST[95:64] := SRC2[95:64]
IF (SRC1[127]) DEST[127:96] := SRC2[127:96]

VPMASKMOVQ - 256-bit store:

IF (SRC1[63]) DEST[63:0] := SRC2[63:0]
IF (SRC1[127]) DEST[127:64] :=SRC2[127:64]
IF (SRC1[191]) DEST[191:128] := SRC2[191:128]
IF (SRC1[255]) DEST[255:192] := SRC2[255:192]

VPMASKMOVQ - 128-bit store:

IF (SRC1[63]) DEST[63:0] := SRC2[63:0]
IF (SRC1[127]) DEST[127:64] :=SRC2[127:64]

Intel C/C++ Compiler Intrinsic Equivalent:

VPMASKMOVD: __m256i _mm256_maskload_epi32(int const *a, __m256i mask)
VPMASKMOVD: void _mm256_maskstore_epi32(int *a, __m256i mask, __m256i b)
VPMASKMOVQ: __m256i _mm256_maskload_epi64(__int64 const *a, __m256i mask);
VPMASKMOVQ: void _mm256_maskstore_epi64(__int64 *a, __m256i mask, __m256d b);
VPMASKMOVD: __m128i _mm_maskload_epi32(int const *a, __m128i mask)
VPMASKMOVD: void _mm_maskstore_epi32(int *a, __m128i mask, __m128 b)
VPMASKMOVQ: __m128i _mm_maskload_epi64(__int cont *a, __m128i mask);
VPMASKMOVQ: void _mm_maskstore_epi64(__int64 *a, __m128i mask, __m128i b);

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-23, “Type 6 Class Exception Conditions” (No AC# reported for any mask bit combinations).



