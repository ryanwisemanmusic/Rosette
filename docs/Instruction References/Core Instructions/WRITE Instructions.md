PTWRITE — Write Data to a Processor Trace Packet

Opcode/Instruction	                Op/En	64/32 bit Mode Support	CPUID Feature Flag	    Description
F3 REX.W 0F AE /4 PTWRITE r64/m64	RM	    V/N.E	                PTWRITE	                Reads the data from r64/m64 to encode into a PTW packet if dependencies are met (see details below).
F3 0F AE /4 PTWRITE r32/m32	        RM	    V/V	                    PTWRITE	                Reads the data from r32/m32 to encode into a PTW packet if dependencies are met (see details below).

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
RM	    ModRM:rm (r)	N/A	        N/A	        N/A

Description:

This instruction reads data in the source operand and sends it to the Intel Processor Trace hardware to be encoded in a PTW packet if TriggerEn, ContextEn, FilterEn, and PTWEn are all set to 1. For more details on these values, see Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3C, Section 33.2.2, “Software Trace Instrumentation with PTWRITE.” The size of data is 64-bit if using REX.W in 64-bit mode, otherwise 32-bits of data are copied from the source operand.

Note: The instruction will #UD if prefix 66H is used.

Operation:

IF (IA32_RTIT_STATUS.TriggerEn & IA32_RTIT_STATUS.ContextEn & IA32_RTIT_STATUS.FilterEn & IA32_RTIT_CTL.PTWEn) = 1
    PTW.PayloadBytes := Encoded payload size;
    PTW.IP := IA32_RTIT_CTL.FUPonPTW
    IF IA32_RTIT_CTL.FUPonPTW = 1
        Insert FUP packet with IP of PTWRITE;
    FI;
FI;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If a memory operand effective address is outside the CS, DS, ES, FS or GS segments.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If an unaligned memory reference is made while the current privilege level is 3 and alignment checking is enabled.
#UD:
	If CPUID.(EAX=14H, ECX=0H):EBX.PTWRITE [Bit 4] = 0.
    If LOCK prefix is used.
    If 66H prefix is used.

Real-Address Mode Exceptions:

#GP(0):
	If any part of the operand lies outside of the effective address space from 0 to 0FFFFH.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#UD:
	If CPUID.(EAX=14H, ECX=0H):EBX.PTWRITE [Bit 4] = 0.
    If LOCK prefix is used.
    If 66H prefix is used.

Virtual 8086 Mode Exceptions:

#GP(0):
	If any part of the operand lies outside of the effective address space from 0 to 0FFFFH.
#SS(0):
	If a memory operand effective address is outside the SS segment limit.
#PF	(fault-code):
    For a page fault.
#AC(0):
	If an unaligned memory reference is made while alignment checking is enabled.
#UD:
	If CPUID.(EAX=14H, ECX=0H):EBX.PTWRITE [Bit 4] = 0.
    If LOCK prefix is used.
    If 66H prefix is used.

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
	If CPUID.(EAX=14H, ECX=0H):EBX.PTWRITE [Bit 4] = 0.
    If LOCK prefix is used.
    If 66H prefix is used.



WBINVD — Write Back and Invalidate Cache

Opcode	    Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
0F 09	    WBINVD	        ZO	    Valid	        Valid	            Write back and flush Internal caches; initiate writing-back and flushing of external caches.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Writes back all modified cache lines in the processor’s internal cache to main memory and invalidates (flushes) the internal caches. The instruction then issues a special-function bus cycle that directs external caches to also write back modified data and another bus cycle to indicate that the external caches should be invalidated.

After executing this instruction, the processor does not wait for the external caches to complete their write-back and flushing operations before proceeding with instruction execution. It is the responsibility of hardware to respond to the cache write-back and flush signals. The amount of time or cycles for WBINVD to complete will vary due to size and other factors of different cache hierarchies. As a consequence, the use of the WBINVD instruction can have an impact on logical processor interrupt/event response time. Additional information of WBINVD behavior in a cache hierarchy with hierarchical sharing topology can be found in Chapter 2 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A.

The WBINVD instruction is a privileged instruction. When the processor is running in protected mode, the CPL of a program or procedure must be 0 to execute this instruction. This instruction is also a serializing instruction (see “Serializing Instructions” in Chapter 9 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A).

In situations where cache coherency with main memory is not a concern, software can use the INVD instruction.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

IA-32 Architecture Compatibility:

The WBINVD instruction is implementation dependent, and its function may be implemented differently on future Intel 64 and IA-32 processors. The instruction is not supported on IA-32 processors earlier than the Intel486 processor.

Operation:

WriteBack(InternalCaches);
Flush(InternalCaches);
SignalWriteBack(ExternalCaches);
SignalFlush(ExternalCaches);
Continue; (* Continue execution *)

Intel C/C++ Compiler Intrinsic Equivalent:

WBINVD void _wbinvd(void);

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	WBINVD cannot be executed at the virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



WBNOINVD — Write Back and Do Not Invalidate Cache

Opcode / Instruction	Op/En	64/32 bit Mode Support	CPUID Feature Flag	    Description
F3 0F 09 WBNOINVD	    ZO	    V/V                 	WBNOINVD	            Write back and do not flush internal caches; initiate writing-back without flushing of external caches.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	    N/A	        N/A	        N/A	        N/A

Description:

The WBNOINVD instruction writes back all modified cache lines in the processor’s internal cache to main memory but does not invalidate (flush) the internal caches.

After executing this instruction, the processor does not wait for the external caches to complete their write-back operation before proceeding with instruction execution. It is the responsibility of hardware to respond to the cache write-back signal. The amount of time or cycles for WBNOINVD to complete will vary due to size and other factors of different cache hierarchies. As a consequence, the use of the WBNOINVD instruction can have an impact on logical processor interrupt/event response time.

The WBNOINVD instruction is a privileged instruction. When the processor is running in protected mode, the CPL of a program or procedure must be 0 to execute this instruction. This instruction is also a serializing instruction (see “Serializing Instructions” in Chapter 9 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A).

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

WriteBack(InternalCaches);
Continue; (* Continue execution *)

Intel C/C++ Compiler Intrinsic Equivalent:

WBNOINVD void _wbnoinvd(void);

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	WBNOINVD cannot be executed at the virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



WRFSBASE/WRGSBASE — Write FS/GS Segment Base

Opcode/Instruction	                Op/En	64/32-bit Mode	CPUID Feature Flag	    Description
F3 0F AE /2 WRFSBASE r32	        M	    V/I	            FSGSBASE	            Load the FS base address with the 32-bit value in the source register.
F3 REX.W 0F AE /2 WRFSBASE r64	    M	    V/I	            FSGSBASE	            Load the FS base address with the 64-bit value in the source register.
F3 0F AE /3 WRGSBASE r32	        M	    V/I	            FSGSBASE	            Load the GS base address with the 32-bit value in the source register.
F3 REX.W 0F AE /3 WRGSBASE r64	    M	    V/I	            FSGSBASE	            Load the GS base address with the 64-bit value in the source register.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r)	N/A	        N/A	        N/A

Description:

Loads the FS or GS segment base address with the general-purpose register indicated by the modR/M:r/m field.

The source operand may be either a 32-bit or a 64-bit general-purpose register. The REX.W prefix indicates the operand size is 64 bits. If no REX.W prefix is used, the operand size is 32 bits; the upper 32 bits of the source register are ignored and upper 32 bits of the base address (for FS or GS) are cleared.

This instruction is supported only in 64-bit mode.

Operation:

FS/GS segment base address := SRC;

Flags Affected:

None.

C/C++ Compiler Intrinsic Equivalent:

WRFSBASE void _writefsbase_u32( unsigned int );
WRFSBASE _writefsbase_u64( unsigned __int64 );
WRGSBASE void _writegsbase_u32( unsigned int );
WRGSBASE _writegsbase_u64( unsigned __int64 );

Protected Mode Exceptions:

#UD:
	The WRFSBASE and WRGSBASE instructions are not recognized in protected mode.

Real-Address Mode Exceptions:

#UD:
	The WRFSBASE and WRGSBASE instructions are not recognized in real-address mode.

Virtual-8086 Mode Exceptions:

#UD:
	The WRFSBASE and WRGSBASE instructions are not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

#UD:
	The WRFSBASE and WRGSBASE instructions are not recognized in compatibility mode.

64-Bit Mode Exceptions:

#UD:
	If the LOCK prefix is used.
    If CR4.FSGSBASE[bit 16] = 0.
    If CPUID.07H.0H:EBX.FSGSBASE[bit 0] = 0
#GP(0):
	If the source register contains a non-canonical address.



WRMSR — Write to Model Specific Register

Opcode	Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
0F 30	WRMSR	        ZO	    Valid	        Valid	            Write the value in EDX:EAX to MSR specified by ECX.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Writes the contents of registers EDX:EAX into the 64-bit model specific register (MSR) specified in the ECX register. (On processors that support the Intel 64 architecture, the high-order 32 bits of RCX are ignored.) The contents of the EDX register are copied to high-order 32 bits of the selected MSR and the contents of the EAX register are copied to low-order 32 bits of the MSR. (On processors that support the Intel 64 architecture, the high-order 32 bits of each of RAX and RDX are ignored.) Undefined or reserved bits in an MSR should be set to values previously read.

This instruction must be executed at privilege level 0 or in real-address mode; otherwise, a general protection exception #GP(0) is generated. Specifying a reserved or unimplemented MSR address in ECX will also cause a general protection exception. The processor will also generate a general protection exception if software attempts to write to bits in a reserved MSR.

When the WRMSR instruction is used to write to an MTRR, the TLBs are invalidated. This includes global entries (see “Translation Lookaside Buffers (TLBs)” in Chapter 3 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A).

MSRs control functions for testability, execution tracing, performance-monitoring and machine check errors. Chapter 2, “Model-Specific Registers (MSRs),” of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 4, lists all MSRs that can be written with this instruction and their addresses. Note that each processor family has its own set of MSRs.

The WRMSR instruction is a serializing instruction (see “Serializing Instructions” in Chapter 9 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A). Note that WRMSR to the IA32_TSC_DEADLINE MSR (MSR index 6E0H) and the X2APIC MSRs (MSR indices 802H to 83FH) are not serializing.

The CPUID instruction should be used to determine whether MSRs are supported (CPUID.01H:EDX[5] = 1) before using this instruction.

IA-32 Architecture Compatibility:

The MSRs and the ability to read them with the WRMSR instruction were introduced into the IA-32 architecture with the Pentium processor. Execution of this instruction by an IA-32 processor earlier than the Pentium processor results in an invalid opcode exception #UD.

Operation:

MSR[ECX] := EDX:EAX;

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
    If the value in ECX specifies a reserved or unimplemented MSR address.
    If the value in EDX:EAX sets bits that are reserved in the MSR specified by ECX.
    If the source register contains a non-canonical address and ECX specifies one of the following MSRs: IA32_DS_AREA, IA32_FS_BASE, IA32_GS_BASE, IA32_KERNEL_GS_BASE, IA32_L-STAR, IA32_SYSENTER_EIP, IA32_SYSENTER_ESP.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If the value in ECX specifies a reserved or unimplemented MSR address.
    If the value in EDX:EAX sets bits that are reserved in the MSR specified by ECX.
    If the source register contains a non-canonical address and ECX specifies one of the following MSRs: IA32_DS_AREA, IA32_FS_BASE, IA32_GS_BASE, IA32_KERNEL_GS_BASE, IA32_L-STAR, IA32_SYSENTER_EIP, IA32_SYSENTER_ESP.
#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	The WRMSR instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.




WRPKRU — Write Data to User Page Key Register

Opcode/Instruction	    Op/En	64/32bit Mode Support	CPUID Feature Flag	    Description
NP 0F 01 EF WRPKRU	    ZO	    V/V	                    OSPKE	                Writes EAX into PKRU.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Writes the value of EAX into PKRU. ECX and EDX must be 0 when WRPKRU is executed; otherwise, a general-protection exception (#GP) occurs.

WRPKRU can be executed only if CR4.PKE = 1; otherwise, an invalid-opcode exception (#UD) occurs. Software can discover the value of CR4.PKE by examining CPUID.(EAX=07H,ECX=0H):ECX.OSPKE [bit 4].

On processors that support the Intel 64 Architecture, the high-order 32-bits of RCX, RDX, and RAX are ignored.

WRPKRU will never execute speculatively. Memory accesses affected by PKRU register will not execute (even speculatively) until all prior executions of WRPKRU have completed execution and updated the PKRU register.

Operation:

IF (ECX = 0 AND EDX = 0)
    THEN PKRU := EAX;
    ELSE #GP(0);
FI;

Flags Affected:

None.

C/C++ Compiler Intrinsic Equivalent:

WRPKRU void _wrpkru(uint32_t);

Protected Mode Exceptions:

#GP(0):
	If ECX ≠ 0.
    If EDX ≠ 0.
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
