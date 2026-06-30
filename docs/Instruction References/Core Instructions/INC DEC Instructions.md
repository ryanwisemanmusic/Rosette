FDECSTP — Decrement Stack-Top Pointer

Opcode		Mode	Leg Mode	Description
D9 F6							Decrement TOP field in FPU status word.

Description:

Subtracts one from the TOP field of the FPU status word (decrements the top-of-stack pointer). If the TOP field contains a 0, it is set to 7. The effect of this instruction is to rotate the stack by one position. The contents of the FPU data registers and tag register are not affected.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

IF TOP = 0
    THEN TOP := 7;
    ELSE TOP := TOP – 1;
FI;

FPU Flags Affected:

The C1 flag is set to 0. The C0, C2, and C3 flags are undefined.

Floating-Point Exceptions:

None.

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



FINCSTP — Increment Stack-Top Pointer

Opcode		Mode	Leg Mode	Description
D9 F7							Increment the TOP field in the FPU status register.

Description:

Adds one to the TOP field of the FPU status word (increments the top-of-stack pointer). If the TOP field contains a 7, it is set to 0. The effect of this instruction is to rotate the stack by one position. The contents of the FPU data registers and tag register are not affected. This operation is not equivalent to popping the stack, because the tag for the previous top-of-stack register is not marked empty.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

IF TOP = 7
    THEN TOP := 0;
    ELSE TOP := TOP + 1;
FI;

FPU Flags Affected:

The C1 flag is set to 0. The C0, C2, and C3 flags are undefined.

Floating-Point Exceptions:

None.

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


https://www.felixcloutier.com/x86/
INC — Increment by 1

Opcode	        Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
FE /0	        INC r/m8	    M	    Valid	        Valid	            Increment r/m byte by 1.
REX + FE /0	    INC r/m81	    M	    Valid	        N.E.	            Increment r/m byte by 1.
FF /0	        INC r/m16	    M	    Valid	        Valid	            Increment r/m word by 1.
FF /0	        INC r/m32	    M	    Valid	        Valid	            Increment r/m doubleword by 1.
REX.W + FF /0	INC r/m64	    M	    Valid	        N.E.	            Increment r/m quadword by 1.
40+ rw2	        INC r16	        O	    N.E.	        Valid	            Increment word register by 1.
40+ rd	        INC r32	        O	    N.E.	        Valid	            Increment doubleword register by 1.

1. In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.
2. 40H through 47H are REX prefixes in 64-bit mode.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
M	ModRM:r/m (r, w)	N/A	N/A	N/A
O	opcode + rd (r, w)	N/A	N/A	N/A

Description:

Adds 1 to the destination operand, while preserving the state of the CF flag. The destination operand can be a register or a memory location. This instruction allows a loop counter to be updated without disturbing the CF flag. (Use a ADD instruction with an immediate operand of 1 to perform an increment operation that does updates the CF flag.)

This instruction can be used with a LOCK prefix to allow the instruction to be executed atomically.

In 64-bit mode, INC r16 and INC r32 are not encodable (because opcodes 40H through 47H are REX prefixes). Otherwise, the instruction’s 64-bit mode default operation size is 32 bits. Use of the REX.R prefix permits access to additional registers (R8-R15). Use of the REX.W prefix promotes operation to 64 bits.

Operation:

DEST := DEST + 1;

Flags Affected:

The CF flag is not affected. The OF, SF, ZF, AF, and PF flags are set according to the result.

Protected Mode Exceptions:

#GP(0):	
    If the destination operand is located in a non-writable segment.
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register is used to access memory and it contains a NULLsegment selector.
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
#PF(fault-code)	If a page fault occurs.
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
#PF(fault-code)	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If the LOCK prefix is used but the destination is not a memory operand.




DEC — Decrement by 1

Opcode	Instruction	Op/En	64-Bit Mode	Compat/Leg Mode	Description
FE /1	DEC r/m8	M	Valid	Valid	Decrement r/m8 by 1.
REX + FE /1	DEC r/m8*	M	Valid	N.E.	Decrement r/m8 by 1.
FF /1	DEC r/m16	M	Valid	Valid	Decrement r/m16 by 1.
FF /1	DEC r/m32	M	Valid	Valid	Decrement r/m32 by 1.
REX.W + FF /1	DEC r/m64	M	Valid	N.E.	Decrement r/m64 by 1.
48+rw	DEC r16	O	N.E.	Valid	Decrement r16 by 1.
48+rd	DEC r32	O	N.E.	Valid	Decrement r32 by 1.
* In 64-bit mode, r/m8 cannot been coded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r, w)	N/A         N/A	        N/A
O	    opcode + rd (r, w)	N/A	        N/A	        N/A

Description:

Subtracts 1 from the destination operand, while preserving the state of the CF flag. The destination operand can be a register or a memory location. This instruction allows a loop counter to be updated without disturbing the CF flag. (To perform a decrement operation that updates the CF flag, use a SUB instruction with an immediate operand of 1.)

This instruction can be used with a LOCK prefix to allow the instruction to be executed atomically.

In 64-bit mode, DEC r16 and DEC r32 are not encodable (because opcodes 48H through 4FH are REX prefixes). Otherwise, the instruction’s 64-bit mode default operation size is 32 bits. Use of the REX.R prefix permits access to additional registers (R8-R15). Use of the REX.W prefix promotes operation to 64 bits.

See the summary chart at the beginning of this section for encoding data and limits.

Operation:

DEST := DEST – 1;

Flags Affected:

The CF flag is not affected. The OF, SF, ZF, AF, and PF flags are set according to the result.

Protected Mode Exceptions:

#GP(0):
	If the destination operand is located in a non-writable segment.
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
#UD	:
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