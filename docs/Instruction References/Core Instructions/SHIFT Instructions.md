SAL/SAR/SHL/SHR — Shift

Opcode:

Instruction	                            Op/En	64-Bit Mode	Compat/Leg Mode	Description
D0 /4	SAL r/m8, 1	                    M1	    Valid	    Valid	        Multiply r/m8 by 2, once.
REX + D0 /4	SAL r/m82, 1	            M1	    Valid	    N.E.	        Multiply r/m8 by 2, once.
D2 /4	SAL r/m8, CL	                MC	    Valid	    Valid	        Multiply r/m8 by 2, CL times.
REX + D2 /4	SAL r/m82, CL	            MC	    Valid	    N.E.	        Multiply r/m8 by 2, CL times.
C0 /4 ib	SAL r/m8, imm8	            MI	    Valid	    Valid	        Multiply r/m8 by 2, imm8 times.
REX + C0 /4 ib	SAL r/m82, imm8	        MI	    Valid	    N.E.	        Multiply r/m8 by 2, imm8 times.
D1 /4	SAL r/m16, 1	                M1	    Valid	    Valid	        Multiply r/m16 by 2, once.
D3 /4	SAL r/m16, CL	                MC	    Valid	    Valid	        Multiply r/m16 by 2, CL times.
C1 /4 ib	SAL r/m16, imm8	            MI	    Valid	    Valid	        Multiply r/m16 by 2, imm8 times.
D1 /4	SAL r/m32, 1	                M1	    Valid	    Valid	        Multiply r/m32 by 2, once.
REX.W + D1 /4	SAL r/m64, 1	        M1	    Valid	    N.E.	        Multiply r/m64 by 2, once.
D3 /4	SAL r/m32, CL	                MC	    Valid	    Valid	        Multiply r/m32 by 2, CL times.
REX.W + D3 /4	SAL r/m64, CL	        MC	    Valid	    N.E.	        Multiply r/m64 by 2, CL times.
C1 /4 ib	SAL r/m32, imm8	            MI	    Valid	    Valid	        Multiply r/m32 by 2, imm8 times.
REX.W + C1 /4 ib	SAL r/m64, imm8	    MI	    Valid	    N.E.	        Multiply r/m64 by 2, imm8 times.
D0 /7	SAR r/m8, 1	                    M1	    Valid	    Valid	        Signed divide3 r/m8 by 2, once.
REX + D0 /7	SAR r/m82, 1	            M1	    Valid	    N.E.	        Signed divide3 r/m8 by 2, once.
D2 /7	SAR r/m8, CL	                MC	    Valid	    Valid	        Signed divide3 r/m8 by 2, CL times.
REX + D2 /7	SAR r/m82, CL	            MC	    Valid	    N.E.	        Signed divide3 r/m8 by 2, CL times.
C0 /7 ib	SAR r/m8, imm8	            MI	    Valid	    Valid	        Signed divide3 r/m8 by 2, imm8 times.
REX + C0 /7 ib	SAR r/m82, imm8	        MI	    Valid	    N.E.	        Signed divide3 r/m8 by 2, imm8 times.
D1 /7	SAR r/m16,1	                    M1	    Valid	    Valid	        Signed divide3 r/m16 by 2, once.
D3 /7	SAR r/m16, CL	                MC	    Valid	    Valid	        Signed divide3 r/m16 by 2, CL times.
C1 /7 ib	SAR r/m16, imm8	            MI	    Valid	    Valid	        Signed divide3 r/m16 by 2, imm8 times.
D1 /7	SAR r/m32, 1	                M1	    Valid	    Valid	        Signed divide3 r/m32 by 2, once.
REX.W + D1 /7	SAR r/m64, 1	        M1	    Valid	    N.E.	        Signed divide3 r/m64 by 2, once.
D3 /7	SAR r/m32, CL	                MC	    Valid	    Valid	        Signed divide3 r/m32 by 2, CL times.
REX.W + D3 /7	SAR r/m64, CL	        MC	    Valid	    N.E.	        Signed divide3 r/m64 by 2, CL times.
C1 /7 ib	SAR r/m32, imm8	            MI	    Valid	    Valid	        Signed divide3 r/m32 by 2, imm8 times.
REX.W + C1 /7 ib	SAR r/m64, imm8	    MI	    Valid	    N.E.	        Signed divide3 r/m64 by 2, imm8 times
D0 /4	SHL r/m8, 1	                    M1	    Valid	    Valid	        Multiply r/m8 by 2, once.
REX + D0 /4	SHL r/m82, 1	            M1	    Valid	    N.E.	        Multiply r/m8 by 2, once.
D2 /4	SHL r/m8, CL	                MC	    Valid	    Valid	        Multiply r/m8 by 2, CL times.
REX + D2 /4	SHL r/m82, CL	            MC	    Valid	    N.E.	        Multiply r/m8 by 2, CL times.
C0 /4 ib	SHL r/m8, imm8	            MI	    Valid	    Valid	        Multiply r/m8 by 2, imm8 times.
REX + C0 /4 ib	SHL r/m82, imm8	        MI	    Valid	    N.E.	        Multiply r/m8 by 2, imm8 times.
D1 /4	SHL r/m16,1	                    M1	    Valid	    Valid	        Multiply r/m16 by 2, once.
D3 /4	SHL r/m16, CL	                MC	    Valid	    Valid	        Multiply r/m16 by 2, CL times.
C1 /4 ib	SHL r/m16, imm8	            MI	    Valid	    Valid	        Multiply r/m16 by 2, imm8 times.
D1 /4	SHL r/m32,1	                    M1	    Valid	    Valid	        Multiply r/m32 by 2, once.

Opcode:

Instruction	                            Op/En	64-Bit Mode	Compat/Leg Mode	Description
REX.W + D1 /4	SHL r/m64,1	            M1	    Valid	    N.E.	        Multiply r/m64 by 2, once.
D3 /4	SHL r/m32, CL	                MC	    Valid	    Valid	        Multiply r/m32 by 2, CL times.
REX.W + D3 /4	SHL r/m64, CL	        MC	    Valid	    N.E.	        Multiply r/m64 by 2, CL times.
C1 /4 ib	SHL r/m32, imm8	            MI	    Valid	    Valid	        Multiply r/m32 by 2, imm8 times.
REX.W + C1 /4 ib	SHL r/m64, imm8	    MI	    Valid	    N.E.	        Multiply r/m64 by 2, imm8 times.

AT&T syntax note: `shlq %cl, %r14` corresponds to Intel syntax `SHL r14, CL`.
D0 /5	SHR r/m8,1	                    M1	    Valid	    Valid	        Unsigned divide r/m8 by 2, once.
REX + D0 /5	SHR r/m82, 1	            M1	    Valid	    N.E.	        Unsigned divide r/m8 by 2, once.
D2 /5	SHR r/m8, CL	                MC	    Valid	    Valid	        Unsigned divide r/m8 by 2, CL times.
REX + D2 /5	SHR r/m82, CL	            MC	    Valid	    N.E.	        Unsigned divide r/m8 by 2, CL times.
C0 /5 ib	SHR r/m8, imm8	            MI	    Valid	    Valid	        Unsigned divide r/m8 by 2, imm8 times.
REX + C0 /5 ib	SHR r/m82, imm8	        MI	    Valid	    N.E.	        Unsigned divide r/m8 by 2, imm8 times.
D1 /5	SHR r/m16, 1	                M1	    Valid	    Valid	        Unsigned divide r/m16 by 2, once.
D3 /5	SHR r/m16, CL	                MC	    Valid	    Valid	        Unsigned divide r/m16 by 2, CL times
C1 /5 ib	SHR r/m16, imm8	            MI	    Valid	    Valid	        Unsigned divide r/m16 by 2, imm8 times.
D1 /5	SHR r/m32, 1	                M1	    Valid	    Valid	        Unsigned divide r/m32 by 2, once.
REX.W + D1 /5	SHR r/m64, 1	        M1	    Valid	    N.E.	        Unsigned divide r/m64 by 2, once.
D3 /5	SHR r/m32, CL	                MC	    Valid	    Valid	        Unsigned divide r/m32 by 2, CL times.
REX.W + D3 /5	SHR r/m64, CL	        MC	    Valid	    N.E.	        Unsigned divide r/m64 by 2, CL times.
C1 /5 ib	SHR r/m32, imm8	            MI	    Valid	    Valid	        Unsigned divide r/m32 by 2, imm8 times.
REX.W + C1 /5 ib	SHR r/m64, imm8	    MI	    Valid	    N.E.	        Unsigned divide r/m64 by 2, imm8 times.

1. See the IA-32 Architecture Compatibility section below.
2. In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.
3. Not the same form of division as IDIV; rounding is toward negative infinity.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	Operand 3	Operand 4
M1	    ModRM:r/m (r, w)	1	        N/A	        N/A
MC	    ModRM:r/m (r, w)	CL	        N/A     	N/A
MI	    ModRM:r/m (r, w)	imm8	    N/A     	N/A

Description:

Shifts the bits in the first operand (destination operand) to the left or right by the number of bits specified in the second operand (count operand). Bits shifted beyond the destination operand boundary are first shifted into the CF flag, then discarded. At the end of the shift operation, the CF flag contains the last bit shifted out of the destination operand.

The destination operand can be a register or a memory location. The count operand can be an immediate value or the CL register. The count is masked to 5 bits (or 6 bits with a 64-bit operand). The count range is limited to 0 to 31 (or 63 with a 64-bit operand). A special opcode encoding is provided for a count of 1.

The shift arithmetic left (SAL) and shift logical left (SHL) instructions perform the same operation; they shift the bits in the destination operand to the left (toward more significant bit locations). For each shift count, the most significant bit of the destination operand is shifted into the CF flag, and the least significant bit is cleared (see Figure 7-7 in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1).

The shift arithmetic right (SAR) and shift logical right (SHR) instructions shift the bits of the destination operand to the right (toward less significant bit locations). For each shift count, the least significant bit of the destination operand is shifted into the CF flag, and the most significant bit is either set or cleared depending on the instruction type. The SHR instruction clears the most significant bit (see Figure 7-8 in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1); the SAR instruction sets or clears the most significant bit to correspond to the sign (most significant bit) of the original value in the destination operand. In effect, the SAR instruction fills the empty bit position’s shifted value with the sign of the unshifted value (see Figure 7-9 in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1).

The SAR and SHR instructions can be used to perform signed or unsigned division, respectively, of the destination operand by powers of 2. For example, using the SAR instruction to shift a signed integer 1 bit to the right divides the value by 2.

Using the SAR instruction to perform a division operation does not produce the same result as the IDIV instruction. The quotient from the IDIV instruction is rounded toward zero, whereas the “quotient” of the SAR instruction is rounded toward negative infinity. This difference is apparent only for negative numbers. For example, when the IDIV instruction is used to divide -9 by 4, the result is -2 with a remainder of -1. If the SAR instruction is used to shift -9 right by two bits, the result is -3 and the “remainder” is +3; however, the SAR instruction stores only the most significant bit of the remainder (in the CF flag).

The OF flag is affected only on 1-bit shifts. For left shifts, the OF flag is set to 0 if the most-significant bit of the result is the same as the CF flag (that is, the top two bits of the original operand were the same); otherwise, it is set to 1. For the SAR instruction, the OF flag is cleared for all 1-bit shifts. For the SHR instruction, the OF flag is set to the most-significant bit of the original operand.

In 64-bit mode, the instruction’s default operation size is 32 bits and the mask width for CL is 5 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64-bits and sets the mask width for CL to 6 bits. See the summary chart at the beginning of this section for encoding data and limits.

IA-32 Architecture Compatibility:

The 8086 does not mask the shift count. However, all other IA-32 processors (starting with the Intel 286 processor) do mask the shift count to 5 bits, resulting in a maximum count of 31. This masking is done in all operating modes (including the virtual-8086 mode) to reduce the maximum execution time of the instructions.

Operation:

IF OperandSize = 64
    THEN
        countMASK := 3FH;
    ELSE
        countMASK := 1FH;
FI
tempCOUNT := (COUNT AND countMASK);
tempDEST := DEST;
WHILE (tempCOUNT ≠ 0)
DO
    IF instruction is SAL or SHL
        THEN
            CF := MSB(DEST);
        ELSE (* Instruction is SAR or SHR *)
            CF := LSB(DEST);
    FI;
    IF instruction is SAL or SHL
        THEN
            DEST := DEST ∗ 2;
        ELSE
            IF instruction is SAR
                THEN
                    DEST := DEST / 2; (* Signed divide, rounding toward negative infinity *)
                ELSE (* Instruction is SHR *)
                    DEST := DEST / 2 ; (* Unsigned divide *)
            FI;
    FI;
    tempCOUNT := tempCOUNT – 1;
OD;
(* Determine overflow for the various instructions *)
IF (COUNT and countMASK) = 1
    THEN
        IF instruction is SAL or SHL
            THEN
                OF := MSB(DEST) XOR CF;
            ELSE
                IF instruction is SAR
                    THEN
                        OF := 0;
                    ELSE (* Instruction is SHR *)
                        OF := MSB(tempDEST);
                FI;
        FI;
    ELSE IF (COUNT AND countMASK) = 0
        THEN
            All flags unchanged;
        ELSE (* COUNT not 1 or 0 *)
            OF := undefined;
    FI;
FI;

Flags Affected:

The CF flag contains the value of the last bit shifted out of the destination operand; it is undefined for SHL and SHR instructions where the count is greater than or equal to the size (in bits) of the destination operand. The OF flag is affected only for 1-bit shifts (see “Description” above); otherwise, it is undefined. The SF, ZF, and PF flags are set according to the result. If the count is 0, the flags are not affected. For a non-zero count, the AF flag is undefined.

Protected Mode Exceptions:

#GP(0):
	If the destination is located in a non-writable segment.
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




SHLD — Double Precision Shift Left

Opcode*	Instruction	                        Op/En	    64-Bit Mode	Compat/Leg Mode	Description
0F A4 /r ib	SHLD r/m16, r16, imm8	        MRI	        Valid	    Valid	        Shift r/m16 to left imm8 places while shifting bits from r16 in from the right.
0F A5 /r	SHLD r/m16, r16, CL	            MRC	        Valid	    Valid	        Shift r/m16 to left CL places while shifting bits from r16 in from the right.
0F A4 /r ib	SHLD r/m32, r32, imm8	        MRI	        Valid	    Valid	        Shift r/m32 to left imm8 places while shifting bits from r32 in from the right.
REX.W + 0F A4 /r ib	SHLD r/m64, r64, imm8	MRI	        Valid	    N.E.	        Shift r/m64 to left imm8 places while shifting bits from r64 in from the right.
0F A5 /r	SHLD r/m32, r32, CL	            MRC	        Valid	    Valid	        Shift r/m32 to left CL places while shifting bits from r32 in from the right.
REX.W + 0F A5 /r	SHLD r/m64, r64, CL	    MRC	        Valid	    N.E.	        Shift r/m64 to left CL places while shifting bits from r64 in from the right.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
MRI	    ModRM:r/m (w)	ModRM:reg (r)	imm8	    N/A
MRC	    ModRM:r/m (w)	ModRM:reg (r)	CL	        N/A

Description:

The SHLD instruction is used for multi-precision shifts of 64 bits or more.

The instruction shifts the first operand (destination operand) to the left the number of bits specified by the third operand (count operand). The second operand (source operand) provides bits to shift in from the right (starting with bit 0 of the destination operand).

The destination operand can be a register or a memory location; the source operand is a register. The count operand is an unsigned integer that can be stored in an immediate byte or in the CL register. If the count operand is CL, the shift count is the logical AND of CL and a count mask. In non-64-bit modes and default 64-bit mode; only bits 0 through 4 of the count are used. This masks the count to a value between 0 and 31. If a count is greater than the operand size, the result is undefined.

If the count is 1 or greater, the CF flag is filled with the last bit shifted out of the destination operand. For a 1-bit shift, the OF flag is set if a sign change occurred; otherwise, it is cleared. If the count operand is 0, flags are not affected.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits (upgrading the count mask to 6 bits). See the summary chart at the beginning of this section for encoding data and limits.

Operation:

IF (In 64-Bit Mode and REX.W = 1)
    THEN COUNT := COUNT MOD 64;
    ELSE COUNT := COUNT MOD 32;
FI
SIZE := OperandSize;
IF COUNT = 0
    THEN
        No operation;
    ELSE
        IF COUNT > SIZE
            THEN (* Bad parameters *)
                DEST is undefined;
                CF, OF, SF, ZF, AF, PF are undefined;
            ELSE (* Perform the shift *)
                CF := BIT[DEST, SIZE – COUNT];
                (* Last bit shifted out on exit *)
                FOR i := SIZE – 1 DOWN TO COUNT
                    DO
                        Bit(DEST, i) := Bit(DEST, i – COUNT);
                    OD;
                FOR i := COUNT – 1 DOWN TO 0
                    DO
                        BIT[DEST, i] := BIT[SRC, i – COUNT + SIZE];
                    OD;
        FI;
FI;

Flags Affected:

If the count is 1 or greater, the CF flag is filled with the last bit shifted out of the destination operand and the SF, ZF, and PF flags are set according to the value of the result. For a 1-bit shift, the OF flag is set if a sign change occurred; otherwise, it is cleared. For shifts greater than 1 bit, the OF flag is undefined. If a shift occurs, the AF flag is undefined. If the count operand is 0, the flags are not affected. If the count is greater than the operand size, the flags are undefined.

Protected Mode Exceptions:

#GP(0):
	If the destination is located in a non-writable segment.
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





SARX/SHLX/SHRX — Shift Without Affecting Flags

Opcode/Instruction	                                Op/En	64/32-bit Mode	CPUID Feature Flag	Description
VEX.LZ.F3.0F38.W0 F7 /r SARX r32a, r/m32, r32b	    RMV	    V/V	            BMI2	            Shift r/m32 arithmetically right with count specified in r32b.
VEX.LZ.66.0F38.W0 F7 /r SHLX r32a, r/m32, r32b	    RMV	    V/V	            BMI2	            Shift r/m32 logically left with count specified in r32b.
VEX.LZ.F2.0F38.W0 F7 /r SHRX r32a, r/m32, r32b	    RMV	    V/V	            BMI2	            Shift r/m32 logically right with count specified in r32b.
VEX.LZ.F3.0F38.W1 F7 /r SARX r64a, r/m64, r64b	    RMV	    V/N.E.	        BMI2	            Shift r/m64 arithmetically right with count specified in r64b.
VEX.LZ.66.0F38.W1 F7 /r SHLX r64a, r/m64, r64b	    RMV	    V/N.E.	        BMI2	            Shift r/m64 logically left with count specified in r64b.
VEX.LZ.F2.0F38.W1 F7 /r SHRX r64a, r/m64, r64b	    RMV	    V/N.E.	        BMI2	            Shift r/m64 logically right with count specified in r64b.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	    Operand 4
RMV	    ModRM:reg (w)	ModRM:r/m (r)	VEX.vvvv (r)	N/A

Description:

Shifts the bits of the first source operand (the second operand) to the left or right by a COUNT value specified in the second source operand (the third operand). The result is written to the destination operand (the first operand).

The shift arithmetic right (SARX) and shift logical right (SHRX) instructions shift the bits of the destination operand to the right (toward less significant bit locations), SARX keeps and propagates the most significant bit (sign bit) while shifting.

The logical shift left (SHLX) shifts the bits of the destination operand to the left (toward more significant bit locations).

This instruction is not supported in real mode and virtual-8086 mode. The operand size is always 32 bits if not in 64-bit mode. In 64-bit mode operand size 64 requires VEX.W1. VEX.W1 is ignored in non-64-bit modes. An attempt to execute this instruction with VEX.L not equal to 0 will cause #UD.

If the value specified in the first source operand exceeds OperandSize -1, the COUNT value is masked.

SARX,SHRX, and SHLX instructions do not update flags.

Operation:

TEMP := SRC1;
IF VEX.W1 and CS.L = 1
THEN
    countMASK := 3FH;
ELSE
    countMASK := 1FH;
FI
COUNT := (SRC2 AND countMASK)
DEST[OperandSize -1] = TEMP[OperandSize -1];
DO WHILE (COUNT ≠ 0)
    IF instruction is SHLX
        THEN
            DEST[] := DEST *2;
        ELSE IF instruction is SHRX
            THEN
                DEST[] := DEST /2; //unsigned divide
        ELSE // SARX
                DEST[] := DEST /2; // signed divide, round toward negative infinity
    FI;
    COUNT := COUNT - 1;
OD

Flags Affected:

None.

Intel C/C++ Compiler Intrinsic Equivalent:

Auto-generated from high-level language.
SIMD Floating-Point Exceptions ¶

None.

Other Exceptions:

See Table 2-29, “Type 13 Class Exception Conditions.”




SHRD — Double Precision Shift Right

Opcode*	Instruction	                        Op/En	64-Bit Mode	Compat/Leg Mode	Description
0F AC /r ib	SHRD r/m16, r16, imm8	        MRI	    Valid	    Valid	        Shift r/m16 to right imm8 places while shifting bits from r16 in from the left.
0F AD /r	SHRD r/m16, r16, CL	            MRC	    Valid	    Valid	        Shift r/m16 to right CL places while shifting bits from r16 in from the left.
0F AC /r ib	SHRD r/m32, r32, imm8	        MRI	    Valid	    Valid	        Shift r/m32 to right imm8 places while shifting bits from r32 in from the left.
REX.W + 0F AC /r ib	SHRD r/m64, r64, imm8	MRI	    Valid	    N.E.	        Shift r/m64 to right imm8 places while shifting bits from r64 in from the left.
0F AD /r	SHRD r/m32, r32, CL	            MRC	    Valid	    Valid	        Shift r/m32 to right CL places while shifting bits from r32 in from the left.
REX.W + 0F AD /r	SHRD r/m64, r64, CL	    MRC	    Valid	    N.E.	        Shift r/m64 to right CL places while shifting bits from r64 in from the left.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
MRI	    ModRM:r/m (w)	ModRM:reg (r)	imm8	    N/A
MRC	    ModRM:r/m (w)	ModRM:reg (r)	CL	        N/A

Description:

The SHRD instruction is useful for multi-precision shifts of 64 bits or more.

The instruction shifts the first operand (destination operand) to the right the number of bits specified by the third operand (count operand). The second operand (source operand) provides bits to shift in from the left (starting with the most significant bit of the destination operand).

The destination operand can be a register or a memory location; the source operand is a register. The count operand is an unsigned integer that can be stored in an immediate byte or the CL register. If the count operand is CL, the shift count is the logical AND of CL and a count mask. In non-64-bit modes and default 64-bit mode, the width of the count mask is 5 bits. Only bits 0 through 4 of the count register are used (masking the count to a value between 0 and 31). If the count is greater than the operand size, the result is undefined.

If the count is 1 or greater, the CF flag is filled with the last bit shifted out of the destination operand. For a 1-bit shift, the OF flag is set if a sign change occurred; otherwise, it is cleared. If the count operand is 0, flags are not affected.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits (upgrading the count mask to 6 bits). See the summary chart at the beginning of this section for encoding data and limits.

Operation:

IF (In 64-Bit Mode and REX.W = 1)
    THEN COUNT := COUNT MOD 64;
    ELSE COUNT := COUNT MOD 32;
FI
SIZE := OperandSize;
IF COUNT = 0
    THEN
        No operation;
    ELSE
        IF COUNT > SIZE
            THEN (* Bad parameters *)
                DEST is undefined;
                CF, OF, SF, ZF, AF, PF are undefined;
            ELSE (* Perform the shift *)
                CF := BIT[DEST, COUNT – 1]; (* Last bit shifted out on exit *)
                FOR i := 0 TO SIZE – 1 – COUNT
                    DO
                        BIT[DEST, i] := BIT[DEST, i + COUNT];
                    OD;
                FOR i := SIZE – COUNT TO SIZE – 1
                    DO
                        BIT[DEST,i] := BIT[SRC, i + COUNT – SIZE];
                    OD;
        FI;
FI;

Flags Affected:

If the count is 1 or greater, the CF flag is filled with the last bit shifted out of the destination operand and the SF, ZF, and PF flags are set according to the value of the result. For a 1-bit shift, the OF flag is set if a sign change occurred; otherwise, it is cleared. For shifts greater than 1 bit, the OF flag is undefined. If a shift occurs, the AF flag is undefined. If the count operand is 0, the flags are not affected. If the count is greater than the operand size, the flags are undefined.

Protected Mode Exceptions:

#GP(0):
	If the destination is located in a non-writable segment.
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


