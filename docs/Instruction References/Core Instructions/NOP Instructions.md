FNOP — No Operation

Opcode		Mode	Leg Mode	Description
D9 D0				            No operation is performed.

Description:

Performs no FPU operation. This instruction takes up space in the instruction stream but does not affect the FPU or machine context, except the EIP register and the FPU Instruction Pointer.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

FPU Flags Affected:

C0, C1, C2, C3	undefined.

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



NOP — No Operation

Opcode	    Instruction	Op/En	64-Bit Mode	Compat/Leg Mode	Description
NP 90	    NOP	        ZO	    Valid	    Valid	        One byte no-operation instruction.
NP 0F 1F /0	NOP r/m16	M	    Valid	    Valid	        Multi-byte no-operation instruction.
NP 0F 1F /0	NOP r/m32	M	    Valid	    Valid	        Multi-byte no-operation instruction.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
ZO	    N/A	            N/A	        N/A	        N/A
M	    ModRM:r/m (r)	N/A     	N/A	        N/A

Description:

This instruction performs no operation. It is a one-byte or multi-byte NOP that takes up space in the instruction stream but does not impact machine context, except for the EIP register.

The multi-byte form of NOP is available on processors with model encoding:

CPUID.01H.EAX[Bytes 11:8] = 0110B or 1111B
The multi-byte NOP instruction does not alter the content of a register and will not issue a memory operation. The instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

The one-byte NOP instruction is an alias mnemonic for the XCHG (E)AX, (E)AX instruction.
The multi-byte NOP instruction performs no operation on supported processors and generates undefined opcode
exception on processors that do not support the multi-byte NOP instruction.
The memory operand form of the instruction allows software to create a byte sequence of “no operation” as one
instruction. For situations where multiple-byte NOPs are needed, the recommended operations (32-bit mode and
64-bit mode) are:

Length	    Assembly	                                Byte Sequence (Hex)
2 bytes	    66 NOP	                                    66 90H
3 bytes	    NOP DWORD PTR [EAX]	                        0F 1F 00H
4 bytes	    NOP DWORD PTR [EAX + 00H]	                0F 1F 40 00H
5 bytes	    NOP DWORD PTR [EAX + EAX*1 + 00H]	        0F 1F 44 00 00H
6 bytes	    66 NOP DWORD PTR [EAX + EAX*1 + 00H]	    66 0F 1F 44 00 00H
7 bytes	    NOP DWORD PTR [EAX + 00000000H]	            0F 1F 80 00 00 00 00H
8 bytes	    NOP DWORD PTR [EAX + EAX*1 + 00000000H]	    0F 1F 84 00 00 00 00 00H
9 bytes	    66 NOP DWORD PTR [EAX + EAX*1 + 00000000H]	66 0F 1F 84 00 00 00 00 00H


Table 4-12. Recommended Multi-Byte Sequence of NOP Instruction

Flags Affected:

None.

Exceptions (All Operating Modes):

#UD:
    If the LOCK prefix is used.

