MONITOR — Set Up Monitor Address

Opcode	    Instruction	    Op/En	64-Bit Mode	Compat/Leg Mode	Description
0F 01 C8	MONITOR	        ZO	    Valid	    Valid	        Sets up a linear address range to be monitored by hardware and activates the monitor. The address range should be a write-back memory caching type. The address is DS:RAX/EAX/AX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

The MONITOR instruction arms address monitoring hardware using an address specified in EAX (the address range that the monitoring hardware checks for store operations can be determined by using CPUID). A store to an address within the specified address range triggers the monitoring hardware. The state of monitor hardware is used by MWAIT.

The address is specified in RAX/EAX/AX and the size is based on the effective address size of the encoded instruction. By default, the DS segment is used to create a linear address that is monitored. Segment overrides can be used.

ECX and EDX are also used. They communicate other information to MONITOR. ECX specifies optional extensions. EDX specifies optional hints; it does not change the architectural behavior of the instruction. For the Pentium 4 processor (family 15, model 3), no extensions or hints are defined. Undefined hints in EDX are ignored by the processor; undefined extensions in ECX raises a general protection fault.

The address range must use memory of the write-back type. Only write-back memory will correctly trigger the monitoring hardware. Additional information on determining what address range to use in order to prevent false wake-ups is described in Chapter 9, “Multiple-Processor Management‚” of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A.

The MONITOR instruction is ordered as a load operation with respect to other memory transactions. The instruction is subject to the permission checking and faults associated with a byte load. Like a load, MONITOR sets the A-bit but not the D-bit in page tables.

CPUID.01H:ECX.MONITOR[bit 3] indicates the availability of MONITOR and MWAIT in the processor. When set, MONITOR may be executed only at privilege level 0 (use at any other privilege level results in an invalid-opcode exception). The operating system or system BIOS may disable this instruction by using the IA32_MISC_ENABLE MSR; disabling MONITOR clears the CPUID feature flag and causes execution to generate an invalid-opcode exception.

The instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

MONITOR sets up an address range for the monitor hardware using the content of EAX (RAX in 64-bit mode) as an effective address
and puts the monitor hardware in armed state. Always use memory of the write-back caching type. A store to the specified address
range will trigger the monitor hardware. The content of ECX and EDX are used to communicate other information to the monitor
hardware.

Intel C/C++ Compiler Intrinsic Equivalent:

MONITOR void _mm_monitor(void const *p, unsigned extensions,unsigned hints)

Numeric Exceptions:

None.

Protected Mode Exceptions:

#GP(0):
	If the value in EAX is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register is used to access memory and it contains a NULL segment selector.
    If ECX ≠ 0.
#SS(0):
	If the value in EAX is outside the SS segment limit.
#PF(fault-code):
	For a page fault.
#UD:
	If CPUID.01H:ECX.MONITOR[bit 3] = 0.
    If current privilege level is not 0.

Real Address Mode Exceptions:

#GP:
	If the CS, DS, ES, FS, or GS register is used to access memory and the value in EAX is outside of the effective address space from 0 to FFFFH.
    If ECX ≠ 0.
#SS:
	If the SS register is used to access memory and the value in EAX is outside of the effective address space from 0 to FFFFH.
#UD:
	If CPUID.01H:ECX.MONITOR[bit 3] = 0.

Virtual 8086 Mode Exceptions:

#UD:
	The MONITOR instruction is not recognized in virtual-8086 mode (even if CPUID.01H:ECX.MONITOR[bit 3] = 1).

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#GP(0):
	If the linear address of the operand in the CS, DS, ES, FS, or GS segment is in a non-canonical form.
    If RCX ≠ 0.
#SS(0):
	If the SS register is used to access memory and the value in EAX is in a non-canonical form.
#PF(fault-code):
	For a page fault.
#UD:
	If the current privilege level is not 0.
    If CPUID.01H:ECX.MONITOR[bit 3] = 0.

SETcc — Set Byte on Condition

Opcode	    Instruction	    Op/En	64-Bit Mode	Compat/Leg Mode	Description
0F 97	    SETA r/m8	    M	    Valid	    Valid	        Set byte if above (CF=0 and ZF=0).
REX + 0F 97	SETA r/m81	    M	    Valid	    N.E.	        Set byte if above (CF=0 and ZF=0).
0F 93	    SETAE r/m8	    M	    Valid	    Valid	        Set byte if above or equal (CF=0).
REX + 0F 93	SETAE r/m81	    M	    Valid	    N.E.	        Set byte if above or equal (CF=0).
0F 92	    SETB r/m8	    M	    Valid	    Valid	        Set byte if below (CF=1).
REX + 0F 92	SETB r/m81	    M	    Valid	    N.E.	        Set byte if below (CF=1).
0F 96	    SETBE r/m8	    M	    Valid	    Valid	        Set byte if below or equal (CF=1 or ZF=1).
REX + 0F 96	SETBE r/m81	    M	    Valid	    N.E.	        Set byte if below or equal (CF=1 or ZF=1).
0F 92	    SETC r/m8	    M	    Valid	    Valid	        Set byte if carry (CF=1).
REX + 0F 92	SETC r/m81	    M	    Valid	    N.E.	        Set byte if carry (CF=1).
0F 94	    SETE r/m8	    M	    Valid	    Valid	        Set byte if equal (ZF=1).
REX + 0F 94	SETE r/m81	    M	    Valid	    N.E.	        Set byte if equal (ZF=1).
0F 9F	    SETG r/m8	    M	    Valid	    Valid	        Set byte if greater (ZF=0 and SF=OF).
REX + 0F 9F	SETG r/m81	    M	    Valid	    N.E.	        Set byte if greater (ZF=0 and SF=OF).
0F 9D	    SETGE r/m8	    M	    Valid	    Valid	        Set byte if greater or equal (SF=OF).
REX + 0F 9D	SETGE r/m81	    M	    Valid	    N.E.	        Set byte if greater or equal (SF=OF).
0F 9C	    SETL r/m8	    M	    Valid	    Valid	        Set byte if less (SF≠ OF).
REX + 0F 9C	SETL r/m81	    M	    Valid	    N.E.	        Set byte if less (SF≠ OF).
0F 9E	    SETLE r/m8	    M	    Valid	    Valid	        Set byte if less or equal (ZF=1 or SF≠ OF).
REX + 0F 9E	SETLE r/m81	    M	    Valid	    N.E.	        Set byte if less or equal (ZF=1 or SF≠ OF).
0F 96	    SETNA r/m8	    M	    Valid	    Valid	        Set byte if not above (CF=1 or ZF=1).
REX + 0F 96	SETNA r/m81	    M	    Valid	    N.E.	        Set byte if not above (CF=1 or ZF=1).
0F 92	    SETNAE r/m8	    M	    Valid	    Valid	        Set byte if not above or equal (CF=1).
REX + 0F 92	SETNAE r/m81	M	    Valid	    N.E.	        Set byte if not above or equal (CF=1).
0F 93	    SETNB r/m8	    M	    Valid	    Valid	        Set byte if not below (CF=0).
REX + 0F 93	SETNB r/m81	    M	    Valid	    N.E.	        Set byte if not below (CF=0).
0F 97	    SETNBE r/m8	    M	    Valid	    Valid	        Set byte if not below or equal (CF=0 and ZF=0).
REX + 0F 97	SETNBE r/m81	M	    Valid	    N.E.	        Set byte if not below or equal (CF=0 and ZF=0).
0F 93	    SETNC r/m8	    M	    Valid	    Valid	        Set byte if not carry (CF=0).
REX + 0F 93	SETNC r/m81 	M	    Valid	    N.E.	        Set byte if not carry (CF=0).
0F 95	    SETNE r/m8	    M	    Valid	    Valid	        Set byte if not equal (ZF=0).
REX + 0F 95	SETNE r/m81	    M	    Valid	    N.E.	        Set byte if not equal (ZF=0).
0F 9E	    SETNG r/m8	    M	    Valid	    Valid	        Set byte if not greater (ZF=1 or SF≠ OF)
REX + 0F 9E	SETNG r/m81	    M	    Valid	    N.E.	        Set byte if not greater (ZF=1 or SF≠ OF).
0F 9C	    SETNGE r/m8	    M	    Valid	    Valid	        Set byte if not greater or equal (SF≠ OF).
REX + 0F 9C	SETNGE r/m81	M	    Valid	    N.E.	        Set byte if not greater or equal (SF≠ OF).
0F 9D	    SETNL r/m8	    M	    Valid	    Valid	        Set byte if not less (SF=OF).
REX + 0F 9D	SETNL r/m81	    M	    Valid	    N.E.	        Set byte if not less (SF=OF).
0F 9F	    SETNLE r/m8	    M	    Valid	    Valid	        Set byte if not less or equal (ZF=0 and SF=OF).
REX + 0F 9F	SETNLE r/m81	M	    Valid	    N.E.	        Set byte if not less or equal (ZF=0 and SF=OF).
0F 91	    SETNO r/m8	    M	    Valid	    Valid	        Set byte if not overflow (OF=0).
REX + 0F 91	SETNO r/m81	    M	    Valid	    N.E.	        Set byte if not overflow (OF=0).
0F 9B	    SETNP r/m8	    M	    Valid	    Valid	        Set byte if not parity (PF=0).
REX + 0F 9B	SETNP r/m81	    M	    Valid	    N.E.	        Set byte if not parity (PF=0).
0F 99	    SETNS r/m8	    M	    Valid	    Valid	        Set byte if not sign (SF=0).
REX + 0F 99	SETNS r/m81	    M	    Valid	    N.E.	        Set byte if not sign (SF=0).
0F 95	    SETNZ r/m8	    M	    Valid	    Valid	        Set byte if not zero (ZF=0).
REX + 0F 95	SETNZ r/m81	    M	    Valid	    N.E.	        Set byte if not zero (ZF=0).
0F 90	    SETO r/m8	    M	    Valid	    Valid	        Set byte if overflow (OF=1)
REX + 0F 90	SETO r/m81	    M	    Valid	    N.E.	        Set byte if overflow (OF=1).
0F 9A	    SETP r/m8	    M	    Valid	    Valid	        Set byte if parity (PF=1).
REX + 0F 9A	SETP r/m81	    M	    Valid	    N.E.	        Set byte if parity (PF=1).
0F 9A	    SETPE r/m8	    M	    Valid	    Valid	        Set byte if parity even (PF=1).
REX + 0F 9A	SETPE r/m81	    M	    Valid	    N.E.	        Set byte if parity even (PF=1).
0F 9B	    SETPO r/m8	    M	    Valid	    Valid	        Set byte if parity odd (PF=0).
REX + 0F 9B	SETPO r/m81	    M	    Valid	    N.E.	        Set byte if parity odd (PF=0).
0F 98	    SETS r/m8	    M	    Valid	    Valid	        Set byte if sign (SF=1).
REX + 0F 98	SETS r/m81	    M	    Valid	    N.E.	        Set byte if sign (SF=1).
0F 94	    SETZ r/m8	    M	    Valid	    Valid	        Set byte if zero (ZF=1).
REX + 0F 94	SETZ r/m81	    M	    Valid	    N.E.	        Set byte if zero (ZF=1).
1. In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (w)	N/A	        N/A     	N/A

Description:

Sets the destination operand to 0 or 1 depending on the settings of the status flags (CF, SF, OF, ZF, and PF) in the EFLAGS register. The destination operand points to a byte register or a byte in memory. The condition code suffix (cc) indicates the condition being tested for.

The terms “above” and “below” are associated with the CF flag and refer to the relationship between two unsigned integer values. The terms “greater” and “less” are associated with the SF and OF flags and refer to the relationship between two signed integer values.

Many of the SETcc instruction opcodes have alternate mnemonics. For example, SETG (set byte if greater) and SETNLE (set if not less or equal) have the same opcode and test for the same condition: ZF equals 0 and SF equals OF. These alternate mnemonics are provided to make code more intelligible. Appendix B, “EFLAGS Condition Codes,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1, shows the alternate mnemonics for various test conditions.

Some languages represent a logical one as an integer with all bits set. This representation can be obtained by choosing the logically opposite condition for the SETcc instruction, then decrementing the result. For example, to test for overflow, use the SETNO instruction, then decrement the result.

The reg field of the ModR/M byte is not used for the SETCC instruction and those opcode bits are ignored by the processor.

In IA-64 mode, the operand size is fixed at 8 bits. Use of REX prefix enable uniform addressing to additional byte registers. Otherwise, this instruction’s operation is the same as in legacy mode and compatibility mode.

Operation:

IF condition
    THEN DEST := 1;
    ELSE DEST := 0;
FI;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the destination is located in a non-writable segment.
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register contains a NULL segment selector.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code):
	If a page fault occurs.
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
#UD:
	If the LOCK prefix is used.



TAC — Set AC Flag in EFLAGS Register

Opcode/Instruction	Op / En	64/32 bit Mode Support	CPUID Feature Flag	Description
NP 0F 01 CB STAC	ZO	    V/V	                    SMAP	            Set the AC flag in the EFLAGS register.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	    N/A	            N/A	        N/A

Description:

Sets the AC flag bit in EFLAGS register. This may enable alignment checking of user-mode data accesses. This allows explicit supervisor-mode data accesses to user-mode pages even if the SMAP bit is set in the CR4 register.

This instruction's operation is the same in non-64-bit modes and 64-bit mode. Attempts to execute STAC when CPL > 0 cause #UD.

Operation:

EFLAGS.AC := 1;

Flags Affected:

AC set. Other flags are unaffected.

Protected Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If the CPL > 0.
    If CPUID.(EAX=07H, ECX=0H):EBX.SMAP[bit 20] = 0.

Real-Address Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.SMAP[bit 20] = 0.

Virtual-8086 Mode Exceptions:

#UD:
	The STAC instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If the CPL > 0.
    If CPUID.(EAX=07H, ECX=0H):EBX.SMAP[bit 20] = 0.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If the CPL > 0.
    If CPUID.(EAX=07H, ECX=0H):EBX.SMAP[bit 20] = 0.


STC — Set Carry Flag

Opcode	Instruction	Op/En	64-Bit Mode	Compat/Leg Mode	Description
F9	    STC	        ZO	    Valid	    Valid	        Set CF flag.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Sets the CF flag in the EFLAGS register. Operation is the same in all modes.

Operation:

CF := 1;

Flags Affected:

The CF flag is set. The OF, ZF, SF, AF, and PF flags are unaffected.

Exceptions (All Operating Modes):

#UD:
    If the LOCK prefix is used.



STD — Set Direction Flag

Opcode	Instruction	Op/En	64-bit Mode	Compat/Leg Mode	Description
FD	    STD	        ZO	    Valid	    Valid	        Set DF flag.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Sets the DF flag in the EFLAGS register. When the DF flag is set to 1, string operations decrement the index registers (ESI and/or EDI). Operation is the same in all modes.

Operation:

DF := 1;

Flags Affected:

The DF flag is set. The CF, OF, ZF, SF, AF, and PF flags are unaffected.

Exceptions (All Operating Modes):

#UD:
 If the LOCK prefix is used.



STI — Set Interrupt Flag

Opcode	Instruction	Op/En	64-Bit Mode	Compat/Leg Mode	Description
FB	    STI	        ZO	    Valid	    Valid	        Set interrupt flag; external, maskable interrupts enabled at the end of the next instruction.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A     	N/A	        N/A

Description:

In most cases, STI sets the interrupt flag (IF) in the EFLAGS register. This allows the processor to respond to maskable hardware interrupts.

If IF = 0, maskable hardware interrupts remain inhibited on the instruction boundary following an execution of STI. (The delayed effect of this instruction is provided to allow interrupts to be enabled just before returning from a procedure or subroutine. For instance, if an STI instruction is followed by an RET instruction, the RET instruction is allowed to execute before external interrupts are recognized. No interrupts can be recognized if an execution of CLI immediately follow such an execution of STI.) The inhibition ends after delivery of another event (e.g., exception) or the execution of the next instruction.

The IF flag and the STI and CLI instructions do not prohibit the generation of exceptions and nonmaskable interrupts (NMIs). However, NMIs (and system-management interrupts) may be inhibited on the instruction boundary following an execution of STI that begins with IF = 0.

Operation is different in two modes defined as follows:

PVI mode (protected-mode virtual interrupts): 
    CR0.PE = 1, EFLAGS.VM = 0, CPL = 3, and CR4.PVI = 1;
VME mode (virtual-8086 mode extensions): 
    CR0.PE = 1, EFLAGS.VM = 1, and CR4.VME = 1.
    If IOPL < 3, EFLAGS.VIP = 1, and either VME mode or PVI mode is active, STI sets the VIF flag in the EFLAGS register, leaving IF unaffected.

Table 4-19 indicates the action of the STI instruction depending on the processor operating mode, IOPL, CPL, and EFLAGS.VIP.

Mode	                    IOPL	CPL	EFLAGS.VIP	STI Result
Real-address mode	        X	    X	X	        IF = 1
Protected, not PVI	        ≥ CPL	X	X	        IF = 1
Protected, not PVI	        < CPL	X	X	        #GP fault
Protected, PVI enabled	    3	    X	X	        IF = 1
Protected, PVI enabled	    0–2	    X	0	        VIF = 1 (IF unchanged)
Protected, PVI enabled	    0–2	    X	1	        #GP fault
Virtual-8086, not VME	    3	    X	X	        IF = 1
Virtual-8086, not VME	    0–2	    X	X	        #GP fault
Virtual-8086, VME enabled	3	    X	X	        IF = 1
Virtual-8086, VME enabled	0–2	    X	0	        VIF = 1 (IF unchanged)
Virtual-8086, VME enabled	0–2	    X	1	        #GP fault
1	#GP fault
Table 4-19. Decision Table for STI Results
1. X = This setting has no effect on instruction operation.
2. For this table, “protected mode” applies whenever CR0.PE = 1 and EFLAGS.VM = 0; it includes compatibility mode and 64-bit mode.

3. PVI mode and virtual-8086 mode each imply CPL = 3.

Operation:

IF CR0.PE = 0 (* Executing in real-address mode *)
    THEN IF := 1; (* Set Interrupt Flag *)
    ELSE
        IF IOPL ≥ CPL (* CPL = 3 if EFLAGS.VM = 1 *)
            THEN IF := 1; (* Set Interrupt Flag *)
            ELSE
                IF VME mode OR PVI mode
                    THEN
                        IF EFLAGS.VIP = 0
                            THEN VIF := 1; (* Set Virtual Interrupt Flag *)
                            ELSE #GP(0);
                        FI;
                    ELSE #GP(0);
                FI;
        FI;
FI;

Flags Affected:

Either the IF flag or the VIF flag is set to 1. Other flags are unaffected.

Protected Mode Exceptions:

#GP(0):
	If CPL is greater than IOPL and PVI mode is not active.
    If CPL is greater than IOPL and EFLAGS.VIP = 1.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	If IOPL is less than 3 and VME mode is not active.
    If IOPL is less than 3 and EFLAGS.VIP = 1.
#UD:
	If the LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.




STUI — Set User Interrupt Flag

Opcode/Instruction	Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
F3 0F 01 EF STUI	ZO	    V/I	                    UINTR	            Set user interrupt flag.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	    N/A	        N/A	        N/A     	N/A

Description:

STUI sets the user interrupt flag (UIF). Its effect takes place immediately; a user interrupt may be delivered on the instruction boundary following STUI. (This is in contrast with STI, whose effect is delayed by one instruction).

An execution of STUI inside a transactional region causes a transactional abort; the abort loads EAX as it would have had it been due to an execution of STI.

Operation:

UIF := 1;

Flags Affected:

None.

Protected Mode Exceptions:

#UD:
	The STUI instruction is not recognized in protected mode.

Real-Address Mode Exceptions:

#UD:
	The STUI instruction is not recognized in real-address mode.

Virtual-8086 Mode Exceptions:

#UD:
	The STUI instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

#UD:
	The STUI instruction is not recognized in compatibility mode.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If executed inside an enclave.
    If CR4.UINTR = 0.
    If CPUID.07H.0H:EDX.UINTR[bit 5] = 0.


UMONITOR — User Level Set Up Monitor Address

Opcode / Instruction	            Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
F3 0F AE /6 UMONITOR r16/r32/r64	A	    V/V	                    WAITPKG	            Sets up a linear address range to be monitored by hardware and activates the monitor. The address range should be a write-back memory caching type. The address is contained in r16/r32/r64.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	    Operand 2	Operand 3	Operand 4
A	    N/A	    ModRM:r/m (r)	N/A	        N/A	        N/A

Description:

The UMONITOR instruction arms address monitoring hardware using an address specified in the source register (the address range that the monitoring hardware checks for store operations can be determined by using the CPUID monitor leaf function, EAX=05H). A store to an address within the specified address range triggers the monitoring hardware. The state of monitor hardware is used by UMWAIT.

The content of the source register is an effective address. By default, the DS segment is used to create a linear address that is monitored. Segment overrides can be used. The address range must use memory of the write-back type. Only write-back memory is guaranteed to correctly trigger the monitoring hardware. Additional information on determining what address range to use in order to prevent false wake-ups is described in Chapter 9, “MultipleProcessor Management‚” of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A.

1. The Mod field of the ModR/M byte must have value 11B.
The UMONITOR instruction is ordered as a load operation with respect to other memory transactions. The instruction is subject to the permission checking and faults associated with a byte load. Like a load, UMONITOR sets the A-bit but not the D-bit in page tables.

UMONITOR and UMWAIT are available when CPUID.7.0:ECX.WAITPKG[bit 5] is enumerated as 1. UMONITOR and UMWAIT may be executed at any privilege level. Except for the width of the source register, the instruction’s operation is the same in non-64-bit modes and in 64-bit mode.

UMONITOR does not interoperate with the legacy MWAIT instruction. If UMONITOR was executed prior to executing MWAIT and following the most recent execution of the legacy MONITOR instruction, MWAIT will not enter an optimized state. Execution will continue to the instruction following MWAIT.

The UMONITOR instruction causes a transactional abort when used inside a transactional region.

The width of the source register (16b, 32b or 64b) is determined by the effective addressing width, which is affected in the standard way by the machine mode settings and 67 prefix.

Operation:

UMONITOR sets up an address range for the monitor hardware using the content of source register as an effective
address and puts the monitor hardware in armed state. A store to the specified address range will trigger the
monitor hardware.

Intel C/C++ Compiler Intrinsic Equivalent:

UMONITOR void _umonitor(void *address);

Numeric Exceptions:

None.

Protected Mode Exceptions:

#GP(0):
	If the specified segment is not SS and the source register is outside the specified segment limit.
    If the specified segment register contains a NULL segment selector.
#SS(0):
	If the specified segment is SS and the source register is outside the SS segment limit.
#PF(fault-code):
	For a page fault.
#UD:
	If CPUID.7.0:ECX.WAITPKG[bit 5]=0.

Real Address Mode Exceptions:

#GP:
	If the specified segment is not SS and the source register is outside of the effective address space from 0 to FFFFH.
#SS:
	If the specified segment is SS and the source register is outside of the effective address space from 0 to FFFFH.
#UD:
	If CPUID.7.0:ECX.WAITPKG[bit 5]=0.

Virtual 8086 Mode Exceptions:

Same exceptions as in real address mode; additionally:

#PF(fault-code):
	For a page fault.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#GP(0):
	If the specified segment is not SS and the linear address is in non-canonical form.
#SS(0):
	If the specified segment is SS and the source register is in non-canonical form.
#PF(fault-code):
	For a page fault.
#UD:
	If CPUID.7.0:ECX.WAITPKG[bit 5]=0.




XSETBV — Set Extended Control Register

Opcode	    Instruction	Op/En	64-Bit Mode	Compat/Leg Mode	Description
NP 0F 01 D1	XSETBV	    ZO	    Valid	    Valid	        Write the value in EDX:EAX to the XCR specified by ECX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Writes the contents of registers EDX:EAX into the 64-bit extended control register (XCR) specified in the ECX register. (On processors that support the Intel 64 architecture, the high-order 32 bits of RCX are ignored.) The contents of the EDX register are copied to high-order 32 bits of the selected XCR and the contents of the EAX register are copied to low-order 32 bits of the XCR. (On processors that support the Intel 64 architecture, the high-order 32 bits of each of RAX and RDX are ignored.) Undefined or reserved bits in an XCR should be set to values previously read.

This instruction must be executed at privilege level 0 or in real-address mode; otherwise, a general protection exception #GP(0) is generated. Specifying a reserved or unimplemented XCR in ECX will also cause a general protection exception. The processor will also generate a general protection exception if software attempts to write to reserved bits in an XCR.

Currently, only XCR0 is supported. Thus, all other values of ECX are reserved and will cause a #GP(0). Note that bit 0 of XCR0 (corresponding to x87 state) must be set to 1; the instruction will cause a #GP(0) if an attempt is made to clear this bit. In addition, the instruction causes a #GP(0) if an attempt is made to set XCR0[2] (AVX state) while clearing XCR0[1] (SSE state); it is necessary to set both bits to use AVX instructions; Section 13.3, “Enabling the XSAVE Feature Set and XSAVE-Enabled Features,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1.

Operation:

XCR[ECX] := EDX:EAX;

Flags Affected:

None.

Intel C/C++ Compiler Intrinsic Equivalent:

XSETBV void _xsetbv( unsigned int, unsigned __int64);
Protected Mode Exceptions ¶

#GP(0):
	If the current privilege level is not 0.
    If an invalid XCR is specified in ECX.
    If the value in EDX:EAX sets bits that are reserved in the XCR specified by ECX.
    If an attempt is made to clear bit 0 of XCR0.
    If an attempt is made to set XCR0[2:1] to 10b.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If an invalid XCR is specified in ECX.
    If the value in EDX:EAX sets bits that are reserved in the XCR specified by ECX.
    If an attempt is made to clear bit 0 of XCR0.
    If an attempt is made to set XCR0[2:1] to 10b.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	The XSETBV instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.