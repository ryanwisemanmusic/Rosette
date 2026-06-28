FRSTOR — Restore x87 FPU State

Opcode		Mode	Leg Mode	Description
DD /4				            Load FPU state from m94byte or m108byte.

Description:

Loads the FPU state (operating environment and register stack) from the memory area specified with the source operand. This state data is typically written to the specified memory location by a previous FSAVE/FNSAVE instruction.

The FPU operating environment consists of the FPU control word, status word, tag word, instruction pointer, data pointer, and last opcode. Figures 8-9 through 8-12 in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1, show the layout in memory of the stored environment, depending on the operating mode of the processor (protected or real) and the current operand-size attribute (16-bit or 32-bit). In virtual-8086 mode, the real mode layouts are used. The contents of the FPU register stack are stored in the 80 bytes immediately following the operating environment image.

The FRSTOR instruction should be executed in the same operating mode as the corresponding FSAVE/FNSAVE instruction.

If one or more unmasked exception bits are set in the new FPU status word, a floating-point exception will be generated upon execution of the next floating-point instruction (except for the no-wait floating-point instructions, see the section titled “Software Exception Handling” in Chapter 8 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1). To avoid raising exceptions when loading a new operating environment, clear all the exception flags in the FPU status word that is being loaded.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

FPUControlWord := SRC[FPUControlWord];
FPUStatusWord := SRC[FPUStatusWord];
FPUTagWord := SRC[FPUTagWord];
FPUDataPointer := SRC[FPUDataPointer];
FPUInstructionPointer := SRC[FPUInstructionPointer];
FPULastInstructionOpcode := SRC[FPULastInstructionOpcode];
ST(0) := SRC[ST(0)];
ST(1) := SRC[ST(1)];
ST(2) := SRC[ST(2)];
ST(3) := SRC[ST(3)];
ST(4) := SRC[ST(4)];
ST(5) := SRC[ST(5)];
ST(6) := SRC[ST(6)];
ST(7) := SRC[ST(7)];

FPU Flags Affected:

The C0, C1, C2, C3 flags are loaded.

Floating-Point Exceptions:

None; however, if an unmasked exception is loaded in the status word, it is generated upon execution of the next “waiting” floating-point instruction.

Protected Mode Exceptions:

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register is used to access memory and it contains a NULL segment selector.
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
#PF(fault-code):
	If a page fault occurs.
#AC(0):
	If alignment checking is enabled and an unaligned memory reference is made while the current privilege level is 3.
#UD:
	If the LOCK prefix is used.


FXRSTOR — Restore x87 FPU, MMX, XMM, and MXCSR State

Opcode/Instruction	                        Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
NP 0F AE /1 FXRSTOR m512byte	            M	    Valid	        Valid	            Restore the x87 FPU, MMX, XMM, and MXCSR register state from m512byte.
NP REX.W + 0F AE /1 FXRSTOR64 m512byte	    M	    Valid	        N.E.	            Restore the x87 FPU, MMX, XMM, and MXCSR register state from m512byte.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r)	N/A	        N/A	        N/A

Description:

Reloads the x87 FPU, MMX technology, XMM, and MXCSR registers from the 512-byte memory image specified in the source operand. This data should have been written to memory previously using the FXSAVE instruction, and in the same format as required by the operating modes. The first byte of the data should be located on a 16-byte boundary. There are three distinct layouts of the FXSAVE state map: one for legacy and compatibility mode, a second format for 64-bit mode FXSAVE/FXRSTOR with REX.W=0, and the third format is for 64-bit mode with FXSAVE64/FXRSTOR64. Table 3-43 shows the layout of the legacy/compatibility mode state information in memory and describes the fields in the memory image for the FXRSTOR and FXSAVE instructions. Table 3-46 shows the layout of the 64-bit mode state information when REX.W is set (FXSAVE64/FXRSTOR64). Table 3-47 shows the layout of the 64-bit mode state information when REX.W is clear (FXSAVE/FXRSTOR).

The state image referenced with an FXRSTOR instruction must have been saved using an FXSAVE instruction or be in the same format as required by Table 3-43, Table 3-46, or Table 3-47. Referencing a state image saved with an FSAVE, FNSAVE instruction or incompatible field layout will result in an incorrect state restoration.

The FXRSTOR instruction does not flush pending x87 FPU exceptions. To check and raise exceptions when loading x87 FPU state information with the FXRSTOR instruction, use an FWAIT instruction after the FXRSTOR instruction.

If the OSFXSR bit in control register CR4 is not set, the FXRSTOR instruction may not restore the states of the XMM and MXCSR registers. This behavior is implementation dependent.

If the MXCSR state contains an unmasked exception with a corresponding status flag also set, loading the register with the FXRSTOR instruction will not result in a SIMD floating-point error condition being generated. Only the next occurrence of this unmasked exception will result in the exception being generated.

Bits 16 through 32 of the MXCSR register are defined as reserved and should be set to 0. Attempting to write a 1 in any of these bits from the saved state image will result in a general protection exception (#GP) being generated.

Bytes 464:511 of an FXSAVE image are available for software use. FXRSTOR ignores the content of bytes 464:511 in an FXSAVE state image.

Operation:

IF 64-Bit Mode
    THEN
        (x87 FPU, MMX, XMM15-XMM0, MXCSR)
                Load(SRC);
    ELSE
            (x87 FPU, MMX, XMM7-XMM0, MXCSR) := Load(SRC);
FI;

x87 FPU and SIMD Floating-Point Exceptions:

None.

Protected Mode Exceptions:

#GP(0):
	For an illegal memory operand effective address in the CS, DS, ES, FS or GS segments.
    If a memory operand is not aligned on a 16-byte boundary, regardless of segment. (See alignment check exception [#AC] below.)
    For an attempt to set reserved bits in MXCSR.
#SS(0):
	For an illegal address in the SS segment.
#PF(fault-code):
	For a page fault.
#NM:
	If CR0.TS[bit 3] = 1.
    If CR0.EM[bit 2] = 1.
#UD:
	If CPUID.01H:EDX.FXSR[bit 24] = 0.
    If instruction is preceded by a LOCK prefix.
#AC:
	If this exception is disabled a general protection exception (#GP) is signaled if the memory operand is not aligned on a 16-byte boundary, as described above. If the alignment check exception (#AC) is enabled (and the CPL is 3), signaling of #AC is not guaranteed and may vary with implementation, as follows. In all implementations where #AC is not signaled, a general protection exception is signaled in its place. In addition, the width of the alignment check may also vary with implementation. For instance, for a given implementation, an alignment check exception might be signaled for a 2-byte misalignment, whereas a general protection exception might be signaled for all other misalignments (4-, 8-, or 16-byte misalignments).
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If a memory operand is not aligned on a 16-byte boundary, regardless of segment.
    If any part of the operand lies outside the effective address space from 0 to FFFFH.
    For an attempt to set reserved bits in MXCSR.
#NM:
	If CR0.TS[bit 3] = 1.
    If CR0.EM[bit 2] = 1.
#UD:
	If CPUID.01H:EDX.FXSR[bit 24] = 0.
    If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

Same exceptions as in real address mode.

#PF(fault-code):
	For a page fault.
#AC:
	For unaligned memory reference.
#UD:
	If the LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions ¶

#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#GP(0):
	If the memory address is in a non-canonical form.
    If memory operand is not aligned on a 16-byte boundary, regardless of segment.
    For an attempt to set reserved bits in MXCSR.
#PF(fault-code):
	For a page fault.
#NM:
	If CR0.TS[bit 3] = 1.
    If CR0.EM[bit 2] = 1.
#UD:
	If CPUID.01H:EDX.FXSR[bit 24] = 0.
    If instruction is preceded by a LOCK prefix.
#AC:
	If this exception is disabled a general protection exception (#GP) is signaled if the memory operand is not aligned on a 16-byte boundary, as described above. If the alignment check exception (#AC) is enabled (and the CPL is 3), signaling of #AC is not guaranteed and may vary with implementation, as follows. In all implementations where #AC is not signaled, a general protection exception is signaled in its place. In addition, the width of the alignment check may also vary with implementation. For instance, for a given implementation, an alignment check exception might be signaled for a 2-byte misalignment, whereas a general protection exception might be signaled for all other misalignments (4-, 8-, or 16-byte misalignments).


RSTORSSP — Restore Saved Shadow Stack Pointer

Opcode/Instruction	                                    Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
F3 0F 01 /5 (mod!=11, /5, memory only) RSTORSSP m64	    M	    V/V	                    CET_SS	            Restore SSP.

Instruction Operand Encoding:

Op/En	Operand 1	        Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r, w)	N/A	        N/A	        N/A

Description:

Restores SSP from the shadow-stack-restore token pointed to by m64. If the SSP restore was successful then the instruction replaces the shadow-stack-restore token with a previous-ssp token. The instruction sets the CF flag to indicate whether the SSP address recorded in the shadow-stack-restore token that was processed was 4 byte aligned, i.e., whether an alignment hole was created when the restore-shadow-stack token was pushed on this shadow stack.

Following RSTORSSP if a restore-shadow-stack token needs to be saved on the previous shadow stack, use the SAVEPREVSSP instruction.

If pushing a restore-shadow-stack token on the previous shadow stack is not required, the previous-ssp token can be popped using the INCSSPQ instruction. If the CF flag was set to indicate presence of an alignment hole, an additional INCSSPD instruction is needed to advance the SSP past the alignment hole.

Operation:

IF CPL = 3
        IF (CR4.CET & IA32_U_CET.SH_STK_EN) = 0
            THEN #UD; FI;
ELSE
        IF (CR4.CET & IA32_S_CET.SH_STK_EN) = 0
            THEN #UD; FI;
FI;
SSP_LA = Linear_Address(mem operand)
IF SSP_LA not aligned to 8 bytes
        THEN #GP(0); FI;
previous_ssp_token = SSP | (IA32_EFER.LMA AND CS.L) | 0x02
Start Atomic Execution
restore_ssp_token = Locked shadow_stack_load 8 bytes from SSP_LA
fault = 0
IF ((restore_ssp_token & 0x03) != (IA32_EFER.LMA & CS.L))
        THEN fault = 1; FI; (* If L flag in token does not match IA32_EFER.LMA & CS.L or bit 1 is not 0 *)
IF ((IA32_EFER.LMA AND CS.L) = 0 AND restore_ssp_token[63:32] != 0)
        THEN fault = 1; FI; (* If compatibility/legacy mode and SSP to be restored not below 4G *)
TMP = restore_ssp_token & ~0x01
TMP = (TMP - 8)
TMP = TMP & ~0x07
IF TMP != SSP_LA
        THEN fault = 1; FI; (* If address in token does not match the requested top of stack *)
TMP = (fault == 0) ? previous_ssp_token : restore_ssp_token
shadow_stack_store 8 bytes of TMP to SSP_LA and release lock
End Atomic Execution
IF fault == 1
    THEN #CP(RSTORSSP); FI;
SSP = SSP_LA
// Set the CF if the SSP in the restore token was 4 byte aligned, i.e., there is an alignment hole
RFLAGS.CF = (restore_ssp_token & 0x04) ? 1 : 0;
RFLAGS.ZF,PF,AF,OF,SF := 0;

Flags Affected:

CF is set to indicate if the shadow stack pointer in the restore token was 4 byte aligned, else it is cleared. ZF, PF, AF, OF, and SF are cleared.

C/C++ Compiler Intrinsic Equivalent:

RSTORSSP void _rstorssp(void *);
Protected Mode Exceptions ¶

#UD:
	If the LOCK prefix is used.
    If CR4.CET = 0.
    IF CPL = 3 and IA32_U_CET.SH_STK_EN = 0.
    IF CPL < 3 and IA32_S_CET.SH_STK_EN = 0.
#GP(0):
	If linear address of memory operand not 8 byte aligned.
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If destination is located in a non-writeable segment.
    If the DS, ES, FS, or GS register is used to access memory and it contains a NULL segment selector.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#CP(rstorssp):
	If L bit in token does not match (IA32_EFER.LMA & CS.L).
    If address in token does not match linear address of memory operand.
    If in 32-bit or compatibility mode and the address in token is not below 4G.
#PF(fault-code):
	If a page fault occurs.

Real-Address Mode Exceptions:

#UD:
	The RSTORSSP instruction is not recognized in real-address mode.

Virtual-8086 Mode Exceptions:

#UD:
	The RSTORSSP instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

Same as protected mode exceptions.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CR4.CET = 0.
    If CPL = 3 and IA32_U_CET.SH_STK_EN = 0.
    If CPL < 3 and IA32_S_CET.SH_STK_EN = 0.
#GP(0):
	If linear address of memory operand not 8 byte aligned.
    If a memory address is in a non-canonical form.
#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#CP(rstorssp):
	If L bit in token does not match (IA32_EFER.LMA & CS.L).
    If address in token does not match linear address of memory operand.
#PF(fault-code):
	If a page fault occurs.

XRSTOR — Restore Processor Extended States

Opcode / Instruction	            Op/En	64/32 bit Mode Support	    CPUID Feature Flag	    Description
NP 0F AE /5 XRSTOR mem	            M	    V/V	                        XSAVE	                Restore state components specified by EDX:EAX from mem.
NP REX.W + 0F AE /5 XRSTOR64 mem	M	    V/N.E.	                    XSAVE	                Restore state components specified by EDX:EAX from mem.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r)	N/A	        N/A	        N/A

Description:

Performs a full or partial restore of processor state components from the XSAVE area located at the memory address specified by the source operand. The implicit EDX:EAX register pair specifies a 64-bit instruction mask. The specific state components restored correspond to the bits set in the requested-feature bitmap (RFBM), which is the logical-AND of EDX:EAX and XCR0.

The format of the XSAVE area is detailed in Section 13.4, “XSAVE Area,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1. Like FXRSTOR and FXSAVE, the memory format used for x87 state depends on a REX.W prefix; see Section 13.5.1, “x87 State” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1.

Section 13.8, “Operation of XRSTOR,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1 provides a detailed description of the operation of the XRSTOR instruction. The following items provide a highlevel outline:

Execution of XRSTOR may take one of two forms: standard and compacted. Bit 63 of the XCOMP_BV field in the XSAVE header determines which form is used: value 0 specifies the standard form, while value 1 specifies the compacted form.
If RFBM[i] = 0, XRSTOR does not update state component i.1
If RFBM[i] = 1 and bit i is clear in the XSTATE_BV field in the XSAVE header, XRSTOR initializes state component i.
If RFBM[i] = 1 and XSTATE_BV[i] = 1, XRSTOR loads state component i from the XSAVE area.
The standard form of XRSTOR treats MXCSR (which is part of state component 1 — SSE) differently from the XMM registers. If either form attempts to load MXCSR with an illegal value, a general-protection exception (#GP) occurs.
XRSTOR loads the internal value XRSTOR_INFO, which may be used to optimize a subsequent execution of XSAVEOPT or XSAVES.
Immediately following an execution of XRSTOR, the processor tracks as in-use (not in initial configuration) any state component i for which RFBM[i] = 1 and XSTATE_BV[i] = 1; it tracks as modified any state component i for which RFBM[i] = 0.
Use of a source operand not aligned to 64-byte boundary (for 64-bit and 32-bit modes) results in a general-protection (#GP) exception. In 64-bit mode, the upper 32 bits of RDX and RAX are ignored.

See Section 13.6, “Processor Tracking of XSAVE-Managed State,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1 for discussion of the bitmaps XINUSE and XMODIFIED and of the quantity XRSTOR_INFO.

1. There is an exception if RFBM[1] = 0 and RFBM[2] = 1. In this case, the standard form of XRSTOR will load MXCSR from memory, even though MXCSR is part of state component 1 — SSE. The compacted form of XRSTOR does not make this exception.

Operation:

RFBM := XCR0 AND EDX:EAX; /* bitwise logical AND */
COMPMASK := XCOMP_BV field from XSAVE header;
RSTORMASK := XSTATE_BV field from XSAVE header;
IF COMPMASK[63] = 0
    THEN
        /* Standard form of XRSTOR */
        TO_BE_RESTORED := RFBM AND RSTORMASK;
        TO_BE_INITIALIZED := RFBM AND NOT RSTORMASK;
        IF TO_BE_RESTORED[0] = 1
            THEN
                XINUSE[0] := 1;
                load x87 state from legacy region of XSAVE area;
        ELSIF TO_BE_INITIALIZED[0] = 1
            THEN
                XINUSE[0] := 0;
                initialize x87 state;
        FI;
        IF RFBM[1] = 1 OR RFBM[2] = 1
            THEN load MXCSR from legacy region of XSAVE area;
        FI;
        IF TO_BE_RESTORED[1] = 1
            THEN
                XINUSE[1] := 1;
                load XMM registers from legacy region of XSAVE area; // this step does not load MXCSR
        ELSIF TO_BE_INITIALIZED[1] = 1
            THEN
                XINUSE[1] := 0;
                set all XMM registers to 0; // this step does not initialize MXCSR
        FI;
        FOR i := 2 TO 62
            IF TO_BE_RESTORED[i] = 1
                THEN
                    XINUSE[i] := 1;
                    load XSAVE state component i at offset n from base of XSAVE area;
                        // n enumerated by CPUID(EAX=0DH,ECX=i):EBX)
            ELSIF TO_BE_INITIALIZED[i] = 1
                THEN
                    XINUSE[i] := 0;
                    initialize XSAVE state component i;
            FI;
        ENDFOR;
    ELSE
        /* Compacted form of XRSTOR */
        IF CPUID.(EAX=0DH,ECX=1):EAX.XSAVEC[bit 1] = 0
            THEN /* compacted form not supported */
                #GP(0);
        FI;
        FORMAT = COMPMASK AND 7FFFFFFF_FFFFFFFFH;
        RESTORE_FEATURES = FORMAT AND RFBM;
        TO_BE_RESTORED := RESTORE_FEATURES AND RSTORMASK;
        FORCE_INIT := RFBM AND NOT FORMAT;
        TO_BE_INITIALIZED = (RFBM AND NOT RSTORMASK) OR FORCE_INIT;
        IF TO_BE_RESTORED[0] = 1
            THEN
                XINUSE[0] := 1;
                load x87 state from legacy region of XSAVE area;
        ELSIF TO_BE_INITIALIZED[0] = 1
            THEN
                XINUSE[0] := 0;
                initialize x87 state;
        FI;
        IF TO_BE_RESTORED[1] = 1
            THEN
                XINUSE[1] := 1;
                load SSE state from legacy region of XSAVE area; // this step loads the XMM registers and MXCSR
        ELSIF TO_BE_INITIALIZED[1] = 1
            THEN
                set all XMM registers to 0;
                XINUSE[1] := 0;
                MXCSR := 1F80H;
        FI;
        NEXT_FEATURE_OFFSET = 576;
                                // Legacy area and XSAVE header consume 576 bytes
        FOR i := 2 TO 62
            IF FORMAT[i] = 1
                THEN
                    IF TO_BE_RESTORED[i] = 1
                        THEN
                            XINUSE[i] := 1;
                            load XSAVE state component i at offset NEXT_FEATURE_OFFSET from base of XSAVE area;
                    FI;
                    NEXT_FEATURE_OFFSET = NEXT_FEATURE_OFFSET + n (n enumerated by CPUID(EAX=0DH,ECX=i):EAX);
            FI;
            IF TO_BE_INITIALIZED[i] = 1
                THEN
                    XINUSE[i] := 0;
                    initialize XSAVE state component i;
            FI;
        ENDFOR;
FI;
XMODIFIED := NOT RFBM;
IF in VMX non-root operation
    THEN VMXNR := 1;
    ELSE VMXNR := 0;
FI;
LAXA := linear address of XSAVE area;
XRSTOR_INFO := CPL,VMXNR,LAXA,COMPMASK;

Flags Affected:

None.

Intel C/C++ Compiler Intrinsic Equivalent:

XRSTOR void _xrstor( void * , unsigned __int64);
XRSTOR void _xrstor64( void * , unsigned __int64);
Protected Mode Exceptions ¶

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If a memory operand is not aligned on a 64-byte boundary, regardless of segment.
    If bit 63 of the XCOMP_BV field of the XSAVE header is 1 and CPUID.(EAX=0DH,ECX=1):EAX.XSAVEC[bit 1] = 0.
    If the standard form is executed and a bit in XCR0 is 0 and the corresponding bit in the XSTATE_BV field of the XSAVE header is 1.
    If the standard form is executed and bytes 23:8 of the XSAVE header are not all zero.
    If the compacted form is executed and a bit in XCR0 is 0 and the corresponding bit in the XCOMP_BV field of the XSAVE header is 1.
    If the compacted form is executed and a bit in the XCOMP_BV field in the XSAVE header is 0 and the corresponding bit in the XSTATE_BV field is 1.
    If the compacted form is executed and bytes 63:16 of the XSAVE header are not all zero.
    If attempting to write any reserved bits of the MXCSR register with 1.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code):
	If a page fault occurs.
#NM:
	If CR0.TS[bit 3] = 1.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.
#AC:
	If this exception is disabled a general protection exception (#GP) is signaled if the memory operand is not aligned on a 64-byte boundary, as described above. If the alignment check exception (#AC) is enabled (and the CPL is 3), signaling of #AC is not guaranteed and may vary with implementation, as follows. In all implementations where #AC is not signaled, a general protection exception is signaled in its place. In addition, the width of the alignment check may also vary with implementation. For instance, for a given implementation, an alignment check exception might be signaled for a 2-byte misalignment, whereas a general protection exception might be signaled for all other misalignments (4-, 8-, or 16-byte misalignments).

Real-Address Mode Exceptions:

#GP:
	If a memory operand is not aligned on a 64-byte boundary, regardless of segment.
    If any part of the operand lies outside the effective address space from 0 to FFFFH.
    If bit 63 of the XCOMP_BV field of the XSAVE header is 1 and CPUID.(EAX=0DH,ECX=1):EAX.XSAVEC[bit 1] = 0.
    If the standard form is executed and a bit in XCR0 is 0 and the corresponding bit in the XSTATE_BV field of the XSAVE header is 1.
    If the standard form is executed and bytes 23:8 of the XSAVE header are not all zero.
    If the compacted form is executed and a bit in XCR0 is 0 and the corresponding bit in the XCOMP_BV field of the XSAVE header is 1.
    If the compacted form is executed and a bit in the XCOMP_BV field in the XSAVE header is 0 and the corresponding bit in the XSTATE_BV field is 1.
    If the compacted form is executed and bytes 63:16 of the XSAVE header are not all zero.
    If attempting to write any reserved bits of the MXCSR register with 1.
#NM:
	If CR0.TS[bit 3] = 1.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#GP(0):
	If a memory address is in a non-canonical form.
    If a memory operand is not aligned on a 64-byte boundary, regardless of segment.
    If bit 63 of the XCOMP_BV field of the XSAVE header is 1 and CPUID.(EAX=0DH,ECX=1):EAX.XSAVEC[bit 1] = 0.
    If the standard form is executed and a bit in XCR0 is 0 and the corresponding bit in the XSTATE_BV field of the XSAVE header is 1.
    If the standard form is executed and bytes 23:8 of the XSAVE header are not all zero.
    If the compacted form is executed and a bit in XCR0 is 0 and the corresponding bit in the XCOMP_BV field of the XSAVE header is 1.
    If the compacted form is executed and a bit in the XCOMP_BV field in the XSAVE header is 0 and the corresponding bit in the XSTATE_BV field is 1.
    If the compacted form is executed and bytes 63:16 of the XSAVE header are not all zero.
    If attempting to write any reserved bits of the MXCSR register with 1.
#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#PF(fault-code):
	If a page fault occurs.
#NM:
	If CR0.TS[bit 3] = 1.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.
#AC:
	If this exception is disabled a general protection exception (#GP) is signaled if the memory operand is not aligned on a 64-byte boundary, as described above. If the alignment check exception (#AC) is enabled (and the CPL is 3), signaling of #AC is not guaranteed and may vary with implementation, as follows. In all implementations where #AC is not signaled, a general protection exception is signaled in its place. In addition, the width of the alignment check may also vary with implementation. For instance, for a given implementation, an alignment check exception might be signaled for a 2-byte misalignment, whereas a general protection exception might be signaled for all other misalignments (4-, 8-, or 16-byte misalignments).


XRSTORS — Restore Processor Extended States Supervisor

Opcode / Instruction	                Op/En	64/32 bit Mode Support	CPUID Feature Flag	    Description
NP 0F C7 /3 XRSTORS mem	                M	    V/V	                    XSS	                    Restore state components specified by EDX:EAX from mem.
NP REX.W + 0F C7 /3 XRSTORS64 mem	    M	    V/N.E.	                XSS	                    Restore state components specified by EDX:EAX from mem.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r)	N/A	        N/A	        N/A

Description:

Performs a full or partial restore of processor state components from the XSAVE area located at the memory address specified by the source operand. The implicit EDX:EAX register pair specifies a 64-bit instruction mask. The specific state components restored correspond to the bits set in the requested-feature bitmap (RFBM), which is the logical-AND of EDX:EAX and the logical-OR of XCR0 with the IA32_XSS MSR. XRSTORS may be executed only if CPL = 0.

The format of the XSAVE area is detailed in Section 13.4, “XSAVE Area,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1. Like FXRSTOR and FXSAVE, the memory format used for x87 state depends on a REX.W prefix; see Section 13.5.1, “x87 State” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1.

Section 13.12, “Operation of XRSTORS,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1 provides a detailed description of the operation of the XRSTOR instruction. The following items provide a high-level outline:

Execution of XRSTORS is similar to that of the compacted form of XRSTOR; XRSTORS cannot restore from an XSAVE area in which the extended region is in the standard format (see Section 13.4.3, “Extended Region of an XSAVE Area” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1).
XRSTORS differs from XRSTOR in that it can restore state components corresponding to bits set in the IA32_XSS MSR.
If RFBM[i] = 0, XRSTORS does not update state component i.
If RFBM[i] = 1 and bit i is clear in the XSTATE_BV field in the XSAVE header, XRSTORS initializes state component i.
If RFBM[i] = 1 and XSTATE_BV[i] = 1, XRSTORS loads state component i from the XSAVE area.
If XRSTORS attempts to load MXCSR with an illegal value, a general-protection exception (#GP) occurs.
XRSTORS loads the internal value XRSTOR_INFO, which may be used to optimize a subsequent execution of XSAVEOPT or XSAVES.
Immediately following an execution of XRSTORS, the processor tracks as in-use (not in initial configuration) any state component i for which RFBM[i] = 1 and XSTATE_BV[i] = 1; it tracks as modified any state component i for which RFBM[i] = 0.
Use of a source operand not aligned to 64-byte boundary (for 64-bit and 32-bit modes) results in a general-protection (#GP) exception. In 64-bit mode, the upper 32 bits of RDX and RAX are ignored.

See Section 13.6, “Processor Tracking of XSAVE-Managed State,” of Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1 for discussion of the bitmaps XINUSE and XMODIFIED and of the quantity XRSTOR_INFO.

Operation:

RFBM := (XCR0 OR IA32_XSS) AND EDX:EAX;
                            /* bitwise logical OR and AND */
COMPMASK := XCOMP_BV field from XSAVE header;
RSTORMASK := XSTATE_BV field from XSAVE header;
FORMAT = COMPMASK AND 7FFFFFFF_FFFFFFFFH;
RESTORE_FEATURES = FORMAT AND RFBM;
TO_BE_RESTORED := RESTORE_FEATURES AND RSTORMASK;
FORCE_INIT := RFBM AND NOT FORMAT;
TO_BE_INITIALIZED = (RFBM AND NOT RSTORMASK) OR FORCE_INIT;
IF TO_BE_RESTORED[0] = 1
    THEN
        XINUSE[0] := 1;
        load x87 state from legacy region of XSAVE area;
ELSIF TO_BE_INITIALIZED[0] = 1
    THEN
        XINUSE[0] := 0;
        initialize x87 state;
FI;
IF TO_BE_RESTORED[1] = 1
    THEN
        XINUSE[1] := 1;
        load SSE state from legacy region of XSAVE area; // this step loads the XMM registers and MXCSR
ELSIF TO_BE_INITIALIZED[1] = 1
    THEN
        set all XMM registers to 0;
        XINUSE[1] := 0;
        MXCSR := 1F80H;
FI;
NEXT_FEATURE_OFFSET = 576;
                        // Legacy area and XSAVE header consume 576 bytes
FOR i := 2 TO 62
    IF FORMAT[i] = 1
        THEN
            IF TO_BE_RESTORED[i] = 1
                THEN
                    XINUSE[i] := 1;
                    load XSAVE state component i at offset NEXT_FEATURE_OFFSET from base of XSAVE area;
            FI;
            NEXT_FEATURE_OFFSET = NEXT_FEATURE_OFFSET + n (n enumerated by CPUID(EAX=0DH,ECX=i):EAX);
    FI;
    IF TO_BE_INITIALIZED[i] = 1
        THEN
            XINUSE[i] := 0;
            initialize XSAVE state component i;
    FI;
ENDFOR;
XMODIFIED := NOT RFBM;
IF in VMX non-root operation
    THEN VMXNR := 1;
    ELSE VMXNR := 0;
FI;
LAXA := linear address of XSAVE area;
XRSTOR_INFO := CPL,VMXNR,LAXA,COMPMASK;
Flags Affected ¶

None.

Intel C/C++ Compiler Intrinsic Equivalent:

XRSTORS void _xrstors( void * , unsigned __int64);
XRSTORS64 void _xrstors64( void * , unsigned __int64);
Protected Mode Exceptions ¶

#GP(0):
	If CPL > 0.
    If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If a memory operand is not aligned on a 64-byte boundary, regardless of segment.
    If bit 63 of the XCOMP_BV field of the XSAVE header is 0.
    If a bit in XCR0|IA32_XSS is 0 and the corresponding bit in the XCOMP_BV field of the XSAVE header is 1.
    If a bit in the XCOMP_BV field in the XSAVE header is 0 and the corresponding bit in the XSTATE_BV field is 1.
    If bytes 63:16 of the XSAVE header are not all zero.
    If attempting to write any reserved bits of the MXCSR register with 1.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF(fault-code):
	If a page fault occurs.
#NM:
	If CR0.TS[bit 3] = 1.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0 or CPUID.(EAX=0DH,ECX=1):EAX.XSS[bit 3] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If a memory operand is not aligned on a 64-byte boundary, regardless of segment.
    If any part of the operand lies outside the effective address space from 0 to FFFFH.
    If bit 63 of the XCOMP_BV field of the XSAVE header is 0.
    If a bit in XCR0|IA32_XSS is 0 and the corresponding bit in the XCOMP_BV field of the XSAVE header is 1.
    If a bit in the XCOMP_BV field in the XSAVE header is 0 and the corresponding bit in the XSTATE_BV field is 1.
    If bytes 63:16 of the XSAVE header are not all zero.
    If attempting to write any reserved bits of the MXCSR register with 1.

#NM:
	If CR0.TS[bit 3] = 1.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0 or CPUID.(EAX=0DH,ECX=1):EAX.XSS[bit 3] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#GP(0):
	If CPL > 0.
    If a memory address is in a non-canonical form.
    If a memory operand is not aligned on a 64-byte boundary, regardless of segment.
    If bit 63 of the XCOMP_BV field of the XSAVE header is 0.
    If a bit in XCR0|IA32_XSS is 0 and the corresponding bit in the XCOMP_BV field of the XSAVE header is 1.
    If a bit in the XCOMP_BV field in the XSAVE header is 0 and the corresponding bit in the XSTATE_BV field is 1.
    If bytes 63:16 of the XSAVE header are not all zero.
    If attempting to write any reserved bits of the MXCSR register with 1.
#SS(0):
	If a memory address referencing the SS segment is in a non-canonical form.
#PF(fault-code):
	If a page fault occurs.
#NM:
	If CR0.TS[bit 3] = 1.
#UD:
	If CPUID.01H:ECX.XSAVE[bit 26] = 0 or CPUID.(EAX=0DH,ECX=1):EAX.XSS[bit 3] = 0.
    If CR4.OSXSAVE[bit 18] = 0.
    If the LOCK prefix is used.
