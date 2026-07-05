RDFSBASE/RDGSBASE — Read FS/GS Segment Base

Opcode/Instruction	                Op/En	64/32-bit Mode	CPUID Feature Flag	Description
F3 0F AE /0 RDFSBASE r32	        M	    V/I	            FSGSBASE	        Load the 32-bit destination register with the FS base address.
F3 REX.W 0F AE /0 RDFSBASE r64	    M	    V/I	            FSGSBASE	        Load the 64-bit destination register with the FS base address.
F3 0F AE /1 RDGSBASE r32	        M	    V/I	            FSGSBASE	        Load the 32-bit destination register with the GS base address.
F3 REX.W 0F AE /1 RDGSBASE r64	    M	    V/I	            FSGSBASE	        Load the 64-bit destination register with the GS base address.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (w)	N/A	        N/A	        N/A

Description:

Loads the general-purpose register indicated by the ModR/M:r/m field with the FS or GS segment base address.

The destination operand may be either a 32-bit or a 64-bit general-purpose register. The REX.W prefix indicates the operand size is 64 bits. If no REX.W prefix is used, the operand size is 32 bits; the upper 32 bits of the source base address (for FS or GS) are ignored and upper 32 bits of the destination register are cleared.

This instruction is supported only in 64-bit mode.

Operation:

DEST := FS/GS segment base address;

Flags Affected:

None.

C/C++ Compiler Intrinsic Equivalent:

RDFSBASE unsigned int _readfsbase_u32(void );
RDFSBASE unsigned __int64 _readfsbase_u64(void );
RDGSBASE unsigned int _readgsbase_u32(void );
RDGSBASE unsigned __int64 _readgsbase_u64(void );

Protected Mode Exceptions:

#UD:
	The RDFSBASE and RDGSBASE instructions are not recognized in protected mode.

Real-Address Mode Exceptions:

#UD:
    The RDFSBASE and RDGSBASE instructions are not recognized in real-address mode.

Virtual-8086 Mode Exceptions:

#UD:
	The RDFSBASE and RDGSBASE instructions are not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

#UD:
	The RDFSBASE and RDGSBASE instructions are not recognized in compatibility mode.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CR4.FSGSBASE[bit 16] = 0.
    If CPUID.07H.0H:EBX.FSGSBASE[bit 0] = 0.



RDMSR — Read From Model Specific Register

Opcode1

Instruction	Op/En	    64-Bit Mode	    Compat/Leg Mode	    Description
0F 32			        Valid	        Valid	            Read MSR specified by ECX into EDX:EAX.

1. See the IA-32 Architecture Compatibility section below.


Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Reads the contents of a 64-bit model specific register (MSR) specified in the ECX register into registers EDX:EAX. (On processors that support the Intel 64 architecture, the high-order 32 bits of RCX are ignored.) The EDX register is loaded with the high-order 32 bits of the MSR and the EAX register is loaded with the low-order 32 bits. (On processors that support the Intel 64 architecture, the high-order 32 bits of each of RAX and RDX are cleared.) If fewer than 64 bits are implemented in the MSR being read, the values returned to EDX:EAX in unimplemented bit locations are undefined.

This instruction must be executed at privilege level 0 or in real-address mode; otherwise, a general protection exception #GP(0) will be generated. Specifying a reserved or unimplemented MSR address in ECX will also cause a general protection exception.

The MSRs control functions for testability, execution tracing, performance-monitoring, and machine check errors. Chapter 2, “Model-Specific Registers (MSRs)” of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 4, lists all the MSRs that can be read with this instruction and their addresses. Note that each processor family has its own set of MSRs.

The CPUID instruction should be used to determine whether MSRs are supported (CPUID.01H:EDX[5] = 1) before using this instruction.

IA-32 Architecture Compatibility:

The MSRs and the ability to read them with the RDMSR instruction were introduced into the IA-32 Architecture with the Pentium processor. Execution of this instruction by an IA-32 processor earlier than the Pentium processor results in an invalid opcode exception #UD.

See “Changes to Instruction Behavior in VMX Non-Root Operation” in Chapter 26 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3C, for more information about the behavior of this instruction in VMX non-root operation.

Operation:

EDX:EAX := MSR[ECX];

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
If the value in ECX specifies a reserved or unimplemented MSR address.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP	If the value in ECX specifies a reserved or unimplemented MSR address.
#UD	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0)	The RDMSR instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.


RDPID — Read Processor ID

Opcode/Instruction	        Op/En	64/32-bit Mode	CPUID Feature Flag	Description
F3 0F C7 /7 RDPID r32	    R	    N.E./V	        RDPID	            Read IA32_TSC_AUX into r32.
F3 0F C7 /7 RDPID r64	    R	    V/N.E.	        RDPID	            Read IA32_TSC_AUX into r64.

Instruction Operand Encoding:

1.ModRM.MOD = 011B required

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
R	    ModRM:r/m (w)	N/A	        N/A	        N/A

Description:

Reads the value of the IA32_TSC_AUX MSR (address C0000103H) into the destination register. The value of CS.D and operand-size prefixes (66H and REX.W) do not affect the behavior of the RDPID instruction.

Operation:

DEST := IA32_TSC_AUX

Flags Affected:

None.

Protected Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.7H.0:ECX.RDPID[bit 22] = 0.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



RDPKRU — Read Protection Key Rights for User Pages

Opcode*	        Instruction	    Op/En	64/32bit Mode Support	CPUID Feature Flag	Description
NP 0F 01 EE	    RDPKRU	        ZO	    V/V	                    OSPKE	            Reads PKRU into EAX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Reads the value of PKRU into EAX and clears EDX. ECX must be 0 when RDPKRU is executed; otherwise, a general-protection exception (#GP) occurs.

RDPKRU can be executed only if CR4.PKE = 1; otherwise, an invalid-opcode exception (#UD) occurs. Software can discover the value of CR4.PKE by examining CPUID.(EAX=07H,ECX=0H):ECX.OSPKE [bit 4].

On processors that support the Intel 64 Architecture, the high-order 32-bits of RCX are ignored and the high-order 32-bits of RDX and RAX are cleared.

Operation:

IF (ECX = 0)
    THEN
        EAX := PKRU;
        EDX := 0;
    ELSE #GP(0);
FI;

Flags Affected:

None.

C/C++ Compiler Intrinsic Equivalent:

RDPKRU uint32_t _rdpkru_u32(void);

Protected Mode Exceptions:

#GP(0):
	If ECX ≠ 0.
#UD:
	If the LOCK prefix is used.
    If CR4.PKE = 0.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.


RDPMC — Read Performance-Monitoring Counters

Opcode*	Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
0F 33	RDPMC	        ZO	    Valid	        Valid	            Read performance-monitoring counter specified by ECX into EDX:EAX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Reads the contents of the performance monitoring counter (PMC) specified in ECX register into registers EDX:EAX. (On processors that support the Intel 64 architecture, the high-order 32 bits of RCX are ignored.) The EDX register is loaded with the high-order 32 bits of the PMC and the EAX register is loaded with the low-order 32 bits. (On processors that support the Intel 64 architecture, the high-order 32 bits of each of RAX and RDX are cleared.) If fewer than 64 bits are implemented in the PMC being read, unimplemented bits returned to EDX:EAX will have value zero.

The width of PMCs on processors supporting architectural performance monitoring (CPUID.0AH:EAX[7:0] ≠ 0) are reported by CPUID.0AH:EAX[23:16]. On processors that do not support architectural performance monitoring (CPUID.0AH:EAX[7:0]=0), the width of general-purpose performance PMCs is 40 bits, while the widths of special-purpose PMCs are implementation specific.

Use of ECX to specify a PMC depends on whether the processor supports architectural performance monitoring:

If the processor does not support architectural performance monitoring (CPUID.0AH:EAX[7:0]=0), ECX[30:0] specifies the index of the PMC to be read. Setting ECX[31] selects “fast” read mode if supported. In this mode, RDPMC returns bits 31:0 of the PMC in EAX while clearing EDX to zero.
If the processor does support architectural performance monitoring (CPUID.0AH:EAX[7:0] ≠ 0), ECX[31:16] specifies type of PMC while ECX[15:0] specifies the index of the PMC to be read within that type. The following PMC types are currently defined:
General-purpose counters use type 0. The index x (to read IA32_PMCx) must be less than the value enumerated by CPUID.0AH.EAX[15:8] (thus ECX[15:8] must be zero).
General-purpose counters use type 0. The index x (to read IA32_PMCx) must be less than the value enumerated by CPUID.0AH.EAX[15:8] (thus ECX[15:8] must be zero).
Fixed-function counters use type 4000H. The index x (to read IA32_FIXED_CTRx) can be used if either CPUID.0AH.EDX[4:0] > x or CPUID.0AH.ECX[x] = 1 (thus ECX[15:5] must be 0).
Fixed-function counters use type 4000H. The index x (to read IA32_FIXED_CTRx) can be used if either CPUID.0AH.EDX[4:0] > x or CPUID.0AH.ECX[x] = 1 (thus ECX[15:5] must be 0).
Performance metrics use type 2000H. This type can be used only if IA32_PERF_CAPABILITIES.PERF_MET-RICS_AVAILABLE[bit 15]=1. For this type, the index in ECX[15:0] is implementation specific.
Performance metrics use type 2000H. This type can be used only if IA32_PERF_CAPABILITIES.PERF_MET-RICS_AVAILABLE[bit 15]=1. For this type, the index in ECX[15:0] is implementation specific.
Specifying an unsupported PMC encoding will cause a general protection exception #GP(0). For PMC details see Chapter 20, “Performance Monitoring,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3B.

When in protected or virtual 8086 mode, the Performance-monitoring Counters Enabled (PCE) flag in register CR4 restricts the use of the RDPMC instruction. When the PCE flag is set, the RDPMC instruction can be executed at any privilege level; when the flag is clear, the instruction can only be executed at privilege level 0. (When in real-address mode, the RDPMC instruction is always enabled.) The PMCs can also be read with the RDMSR instruction, when executing at privilege level 0.

The RDPMC instruction is not a serializing instruction; that is, it does not imply that all the events caused by the preceding instructions have been completed or that events caused by subsequent instructions have not begun. If an exact event count is desired, software must insert a serializing instruction (such as the CPUID instruction) before and/or after the RDPMC instruction.

Performing back-to-back fast reads are not guaranteed to be monotonic. To guarantee monotonicity on back-to-back reads, a serializing instruction must be placed between the two RDPMC instructions.

The RDPMC instruction can execute in 16-bit addressing mode or virtual-8086 mode; however, the full contents of the ECX register are used to select the PMC, and the event count is stored in the full EAX and EDX registers. The

RDPMC instruction was introduced into the IA-32 Architecture in the Pentium Pro processor and the Pentium processor with MMX technology. The earlier Pentium processors have PMCs, but they must be read with the RDMSR instruction.

Operation:

MSCB = Most Significant Counter Bit (* Model-specific *)
IF (((CR4.PCE = 1) or (CPL = 0) or (CR0.PE = 0)) and (ECX indicates a supported counter))
    THEN
        EAX := counter[31:0];
        EDX := ZeroExtend(counter[MSCB:32]);
    ELSE (* ECX is not valid or CR4.PCE is 0 and CPL is 1, 2, or 3 and CR0.PE is 1 *)
        #GP(0);
FI;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0 and the PCE flag in the CR4 register is clear.
    If an invalid performance counter index is specified.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If an invalid performance counter index is specified.
#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	If the PCE flag in the CR4 register is clear.
    If an invalid performance counter index is specified.
#UD:
	If the LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#GP(0):
	If the current privilege level is not 0 and the PCE flag in the CR4 register is clear.
    If an invalid performance counter index is specified.
#UD:
	If the LOCK prefix is used.





RDRAND — Read Random Number

Opcode*/Instruction	                Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
NFx 0F C7 /6 RDRAND r16	            M	    V/V	                    RDRAND	            Read a 16-bit random number and store in the destination register.
NFx 0F C7 /6 RDRAND r32	            M	    V/V	                    RDRAND	            Read a 32-bit random number and store in the destination register.
NFx REX.W + 0F C7 /6 RDRAND r64	    M	    V/I	                    RDRAND	            Read a 64-bit random number and store in the destination register.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (w)	N/A	        N/A	        N/A

Description:

Loads a hardware generated random value and store it in the destination register. The size of the random value is determined by the destination register size and operating mode. The Carry Flag indicates whether a random value is available at the time the instruction is executed. CF=1 indicates that the data in the destination is valid. Otherwise CF=0 and the data in the destination operand will be returned as zeros for the specified width. All other flags are forced to 0 in either situation. Software must check the state of CF=1 for determining if a valid random value has been returned, otherwise it is expected to loop and retry execution of RDRAND (see Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1, Section 7.3.17, “Random Number Generator Instructions”).

This instruction is available at all privilege levels.

In 64-bit mode, the instruction's default operand size is 32 bits. Using a REX prefix in the form of REX.B permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bit operands. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

IF HW_RND_GEN.ready = 1
    THEN
        CASE of
            operand size is 64: DEST[63:0] := HW_RND_GEN.data;
            operand size is 32: DEST[31:0] := HW_RND_GEN.data;
            operand size is 16: DEST[15:0] := HW_RND_GEN.data;
        ESAC
        CF := 1;
    ELSE
        CASE of
            operand size is 64: DEST[63:0] := 0;
            operand size is 32: DEST[31:0] := 0;
            operand size is 16: DEST[15:0] := 0;
        ESAC
        CF := 0;
FI
OF, SF, ZF, AF, PF := 0;

Flags Affected:

The CF flag is set according to the result (see the “Operation” section above). The OF, SF, ZF, AF, and PF flags are set to 0.

Intel C/C++ Compiler Intrinsic Equivalent:

RDRAND int _rdrand16_step( unsigned short * );
RDRAND int _rdrand32_step( unsigned int * );
RDRAND int _rdrand64_step( unsigned __int64 *);

Protected Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.01H:ECX.RDRAND[bit 30] = 0.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.




RDSEED — Read Random SEED

Opcode/Instruction	                Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
NFx 0F C7 /7 RDSEED r16	            M	    V/V	                    RDSEED	            Read a 16-bit NIST SP800-90B & C compliant random value and store in the destination register.
NFx 0F C7 /7 RDSEED r32	            M	    V/V	                    RDSEED	            Read a 32-bit NIST SP800-90B & C compliant random value and store in the destination register.
NFx REX.W + 0F C7 /7 RDSEED r64	    M	    V/I	                    RDSEED	            Read a 64-bit NIST SP800-90B & C compliant random value and store in the destination register.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (w)	N/A	        N/A	        N/A

Description:

Loads a hardware generated random value and store it in the destination register. The random value is generated from an Enhanced NRBG (Non Deterministic Random Bit Generator) that is compliant to NIST SP800-90B and NIST SP800-90C in the XOR construction mode. The size of the random value is determined by the destination register size and operating mode. The Carry Flag indicates whether a random value is available at the time the instruction is executed. CF=1 indicates that the data in the destination is valid. Otherwise CF=0 and the data in the destination operand will be returned as zeros for the specified width. All other flags are forced to 0 in either situation. Software must check the state of CF=1 for determining if a valid random seed value has been returned, otherwise it is expected to loop and retry execution of RDSEED (see Section 1.2).

The RDSEED instruction is available at all privilege levels. The RDSEED instruction executes normally either inside or outside a transaction region.

In 64-bit mode, the instruction's default operand size is 32 bits. Using a REX prefix in the form of REX.B permits access to additional registers (R8-R15). Using a REX prefix in the form of REX.W promotes operation to 64 bit operands. See the summary chart at the beginning of this section for encoding data and limits.

Operation:

IF HW_NRND_GEN.ready = 1
    THEN
        CASE of
            operand size is 64: DEST[63:0] := HW_NRND_GEN.data;
            operand size is 32: DEST[31:0] := HW_NRND_GEN.data;
            operand size is 16: DEST[15:0] := HW_NRND_GEN.data;
        ESAC;
        CF := 1;
    ELSE
        CASE of
            operand size is 64: DEST[63:0] := 0;
            operand size is 32: DEST[31:0] := 0;
            operand size is 16: DEST[15:0] := 0;
        ESAC;
        CF := 0;
FI;
OF, SF, ZF, AF, PF := 0;

Flags Affected:

The CF flag is set according to the result (see the “Operation” section above). The OF, SF, ZF, AF, and PF flags are set to 0.

C/C++ Compiler Intrinsic Equivalent:

RDSEED int _rdseed16_step( unsigned short * );
RDSEED int _rdseed32_step( unsigned int * );
RDSEED int _rdseed64_step( unsigned __int64 *);

Protected Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.RDSEED[bit 18] = 0.

Real-Address Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.RDSEED[bit 18] = 0.

Virtual-8086 Mode Exceptions:

#UD	If the LOCK prefix is used.
If CPUID.(EAX=07H, ECX=0H):EBX.RDSEED[bit 18] = 0.

Compatibility Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.RDSEED[bit 18] = 0.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.RDSEED[bit 18] = 0.


RDTSC — Read Time-Stamp Counter

Opcode*	Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
0F 31	RDTSC	        ZO	    Valid	        Valid	            Read time-stamp counter into EDX:EAX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Reads the current value of the processor’s time-stamp counter (a 64-bit MSR) into the EDX:EAX registers. The EDX register is loaded with the high-order 32 bits of the MSR and the EAX register is loaded with the low-order 32 bits. (On processors that support the Intel 64 architecture, the high-order 32 bits of each of RAX and RDX are cleared.)

The processor monotonically increments the time-stamp counter MSR every clock cycle and resets it to 0 whenever the processor is reset. See “Time Stamp Counter” in Chapter 18 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3B, for specific details of the time stamp counter behavior.

The time stamp disable (TSD) flag in register CR4 restricts the use of the RDTSC instruction as follows. When the flag is clear, the RDTSC instruction can be executed at any privilege level; when the flag is set, the instruction can only be executed at privilege level 0.

The time-stamp counter can also be read with the RDMSR instruction, when executing at privilege level 0.

The RDTSC instruction is not a serializing instruction. It does not necessarily wait until all previous instructions have been executed before reading the counter. Similarly, subsequent instructions may begin execution before the read operation is performed. The following items may guide software seeking to order executions of RDTSC:

If software requires RDTSC to be executed only after all previous instructions have executed and all previous loads are globally visible,1 it can execute LFENCE immediately before RDTSC.
If software requires RDTSC to be executed only after all previous instructions have executed and all previous loads and stores are globally visible, it can execute the sequence MFENCE;LFENCE immediately before RDTSC.
If software requires RDTSC to be executed prior to execution of any subsequent instruction (including any memory accesses), it can execute the sequence LFENCE immediately after RDTSC.
This instruction was introduced by the Pentium processor.

See “Changes to Instruction Behavior in VMX Non-Root Operation” in Chapter 26 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3C, for more information about the behavior of this instruction in VMX non-root operation.

1. A load is considered to become globally visible when the value to be loaded is determined.

Operation:

IF (CR4.TSD = 0) or (CPL = 0) or (CR0.PE = 0)
    THEN EDX:EAX := TimeStampCounter;
    ELSE (* CR4.TSD = 1 and (CPL = 1, 2, or 3) and CR0.PE = 1 *)
        #GP(0);
FI;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the TSD flag in register CR4 is set and the CPL is greater than 0.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#UD	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	If the TSD flag in register CR4 is set.
#UD:
	If the LOCK prefix is used.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



RDTSCP — Read Time-Stamp Counter and Processor ID

Opcode*	    Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
0F 01 F9	RDTSCP	        ZO	    Valid	        Valid	            Read 64-bit time-stamp counter and IA32_TSC_AUX value into EDX:EAX and ECX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Reads the current value of the processor’s time-stamp counter (a 64-bit MSR) into the EDX:EAX registers and also reads the value of the IA32_TSC_AUX MSR (address C0000103H) into the ECX register. The EDX register is loaded with the high-order 32 bits of the IA32_TSC MSR; the EAX register is loaded with the low-order 32 bits of the IA32_TSC MSR; and the ECX register is loaded with the low-order 32-bits of IA32_TSC_AUX MSR. On processors that support the Intel 64 architecture, the high-order 32 bits of each of RAX, RDX, and RCX are cleared.

The processor monotonically increments the time-stamp counter MSR every clock cycle and resets it to 0 whenever the processor is reset. See “Time Stamp Counter” in Chapter 18 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3B, for specific details of the time stamp counter behavior.

The time stamp disable (TSD) flag in register CR4 restricts the use of the RDTSCP instruction as follows. When the flag is clear, the RDTSCP instruction can be executed at any privilege level; when the flag is set, the instruction can only be executed at privilege level 0.

The RDTSCP instruction is not a serializing instruction, but it does wait until all previous instructions have executed and all previous loads are globally visible.1 But it does not wait for previous stores to be globally visible, and subsequent instructions may begin execution before the read operation is performed. The following items may guide software seeking to order executions of RDTSCP:

If software requires RDTSCP to be executed only after all previous stores are globally visible, it can execute MFENCE immediately before RDTSCP.
If software requires RDTSCP to be executed prior to execution of any subsequent instruction (including any memory accesses), it can execute LFENCE immediately after RDTSCP.
See “Changes to Instruction Behavior in VMX Non-Root Operation” in Chapter 26 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3C, for more information about the behavior of this instruction in VMX non-root operation.

1. A load is considered to become globally visible when the value to be loaded is determined.

Operation:

IF (CR4.TSD = 0) or (CPL = 0) or (CR0.PE = 0)
    THEN
        EDX:EAX := TimeStampCounter;
        ECX := IA32_TSC_AUX[31:0];
    ELSE (* CR4.TSD = 1 and (CPL = 1, 2, or 3) and CR0.PE = 1 *)
        #GP(0);
FI;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the TSD flag in register CR4 is set and the CPL is greater than 0.
#UD:
	If the LOCK prefix is used.
    If CPUID.80000001H:EDX.RDTSCP[bit 27] = 0.

Real-Address Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CPUID.80000001H:EDX.RDTSCP[bit 27] = 0.

Virtual-8086 Mode Exceptions:

#GP(0):
	If the TSD flag in register CR4 is set.
#UD:
	If the LOCK prefix is used.
    If CPUID.80000001H:EDX.RDTSCP[bit 27] = 0.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.
