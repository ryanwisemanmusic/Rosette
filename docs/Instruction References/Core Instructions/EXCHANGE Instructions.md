FXCH — Exchange Register Contents

Opcode	Instruction	    64-Bit Mode	Compat/Leg Mode	Description
D9 C8+i	FXCH ST(i)	    Valid	    Valid	        Exchange the contents of ST(0) and ST(i).
D9 C9	FXCH	        Valid	    Valid	        Exchange the contents of ST(0) and ST(1).

Description:

Exchanges the contents of registers ST(0) and ST(i). If no source operand is specified, the contents of ST(0) and ST(1) are exchanged.

This instruction provides a simple means of moving values in the FPU register stack to the top of the stack [ST(0)], so that they can be operated on by those floating-point instructions that can only operate on values in ST(0). For example, the following instruction sequence takes the square root of the third register from the top of the register stack:

FXCH ST(3);

FSQRT;

FXCH ST(3);

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

IF (Number-of-operands) is 1
    THEN
        temp := ST(0);
        ST(0) := SRC;
        SRC := temp;
    ELSE
        temp := ST(0);
        ST(0) := ST(1);
        ST(1) := temp;
FI;

FPU Flags Affected:

C1	Set to 0.
C0, C2, C3	Undefined.

Floating-Point Exceptions:

#IS	Stack underflow occurred.

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




XADD — Exchange and Add

Opcode	            Instruction	        Op/En	64-Bit Mode	Compat/Leg Mode	Description
0F C0 /r	        XADD r/m8, r8	    MR	    Valid	    Valid	        Exchange r8 and r/m8; load sum into r/m8.
REX + 0F C0 /r	    XADD r/m8*, r8*	    MR	    Valid	    N.E.	        Exchange r8 and r/m8; load sum into r/m8.
0F C1 /r	        XADD r/m16, r16	    MR	    Valid	    Valid	        Exchange r16 and r/m16; load sum into r/m16.
0F C1 /r	        XADD r/m32, r32	    MR	    Valid	    Valid	        Exchange r32 and r/m32; load sum into r/m32.
REX.W + 0F C1 /r	XADD r/m64, r64	    MR	    Valid	    N.E.	        Exchange r64 and r/m64; load sum into r/m64.
* In 64-bit mode, r/m8 cannot been coded to access the following byte registers if a REX prefix isused: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	        Operand 3	Operand 4
MR	    ModRM:r/m (r, w)	ModRM:reg (r, w)	N/A	        N/A

Description:

Exchanges the first operand (destination operand) with the second operand (source operand), then loads the sum of the two values into the destination operand. The destination operand can be a register or a memory location; the source operand is a register.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

This instruction can be used with a LOCK prefix to allow the instruction to be executed atomically.

IA-32 Architecture Compatibility:

IA-32 processors earlier than the Intel486 processor do not recognize this instruction. If this instruction is used, you should provide an equivalent code sequence that runs on earlier processors.

Operation:

TEMP := SRC + DEST;
SRC := DEST;
DEST := TEMP;

Flags Affected:

The CF, PF, AF, SF, ZF, and OF flags are set according to the result of the addition, which is stored in the destination operand.

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


XCHG — Exchange Register/Memory With Register

Opcode	        Instruction	        Op/En	64-Bit Mode	Compat/Leg Mode	Description
90+rw	        XCHG AX, r16	    O	    Valid	    Valid	        Exchange r16 with AX.
90+rw	        XCHG r16, AX	    O	    Valid	    Valid	        Exchange AX with r16.
90+rd	        XCHG EAX, r32	    O	    Valid	    Valid	        Exchange r32 with EAX.
REX.W + 90+rd	XCHG RAX, r64	    O	    Valid	    N.E.	        Exchange r64 with RAX.
90+rd	        XCHG r32, EAX	    O	    Valid	    Valid	        Exchange EAX with r32.
REX.W + 90+rd	XCHG r64, RAX	    O	    Valid	    N.E.	        Exchange RAX with r64.
86 /r	        XCHG r/m8, r8	    MR	    Valid	    Valid	        Exchange r8 (byte register) with byte from r/m8.
REX + 86 /r	    XCHG r/m8*, r8*	    MR	    Valid	    N.E.	        Exchange r8 (byte register) with byte from r/m8.
86 /r	        XCHG r8, r/m8	    RM	    Valid	    Valid	        Exchange byte from r/m8 with r8 (byte register).
REX + 86 /r	    XCHG r8*, r/m8*	    RM	    Valid	    N.E.	        Exchange byte from r/m8 with r8 (byte register).
87 /r	        XCHG r/m16, r16	    MR	    Valid	    Valid	        Exchange r16 with word from r/m16.
87 /r	        XCHG r16, r/m16	    RM	    Valid	    Valid	        Exchange word from r/m16 with r16.
87 /r	        XCHG r/m32, r32	    MR	    Valid	    Valid	        Exchange r32 with doubleword from r/m32.
REX.W + 87 /r	XCHG r/m64, r64	    MR	    Valid	    N.E.	        Exchange r64 with quadword from r/m64.
87 /r	        XCHG r32, r/m32	    RM	    Valid	    Valid	        Exchange doubleword from r/m32 with r32.
REX.W + 87 /r	XCHG r64, r/m64	    RM	    Valid	    N.E.	        Exchange quadword from r/m64 with r64.
* In 64-bit mode, r/m8 cannot been coded to access the following byte registers if a REX prefix isused: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	        Operand 3	Operand 4
O	    AX/EAX/RAX (r, w)	opcode + rd (r, w)	N/A	        N/A
O	    opcode + rd (r, w)	AX/EAX/RAX (r, w)	N/A	        N/A
MR	    ModRM:r/m (r, w)	ModRM:reg (r)	    N/A     	N/A
RM	    ModRM:reg (w)	    ModRM:r/m (r)	    N/A	        N/A

Description:

Exchanges the contents of the destination (first) and source (second) operands. The operands can be two general-purpose registers or a register and a memory location. If a memory operand is referenced, the processor’s locking protocol is automatically implemented for the duration of the exchange operation, regardless of the presence or absence of the LOCK prefix or of the value of the IOPL. (See the LOCK prefix description in this chapter for more information on the locking protocol.)

This instruction is useful for implementing semaphores or similar data structures for process synchronization. (See “Bus Locking” in Chapter 9 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A, for more information on bus locking.)

The XCHG instruction can also be used instead of the BSWAP instruction for 16-bit operands.

In 64-bit mode, the instruction’s default operation size is 32 bits. Using a REX prefix in the form of REX.R permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bits. See the summary chart at the beginning of this section for encoding data and limits.

XCHG (E)AX, (E)AX (encoded instruction byte is 90H) is an alias for NOP regardless of data size prefixes, including REX.W.

Operation:

TEMP := DEST;
DEST := SRC;
SRC := TEMP;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If either operand is in a non-writable segment.
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
