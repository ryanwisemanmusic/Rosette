INVD — Invalidate Internal Caches

Opcode      Instruction	    Op/En	64-Bit Mode	    Compat/Leg Mode	    Description
0F 08	    INVD	        ZO	    Valid	        Valid	            Flush internal caches; initiate flushing of external caches.
1. See the IA-32 Architecture Compatibility section below.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

Invalidates (flushes) the processor’s internal caches and issues a special-function bus cycle that directs external caches to also flush themselves. Data held in internal caches is not written back to main memory.

After executing this instruction, the processor does not wait for the external caches to complete their flushing operation before proceeding with instruction execution. It is the responsibility of hardware to respond to the cache flush signal.

The INVD instruction is a privileged instruction. When the processor is running in protected mode, the CPL of a program or procedure must be 0 to execute this instruction.

The INVD instruction may be used when the cache is used as temporary memory and the cache contents need to be invalidated rather than written back to memory. When the cache is used as temporary memory, no external device should be actively writing data to main memory.

Use this instruction with care. Data cached internally and not written back to main memory will be lost. Note that any data from an external device to main memory (for example, via a PCIWrite) can be temporarily stored in the caches; these data can be lost when an INVD instruction is executed. Unless there is a specific requirement or benefit to flushing caches without writing back modified cache lines (for example, temporary memory, testing, or fault recovery where cache coherency with main memory is not a concern), software should instead use the WBINVD instruction.

On processors that support processor reserved memory, the INVD instruction cannot be executed when processor reserved memory protections are activated. See Section 36.5, “EPC and Management of EPC Pages,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3D.

Some processors prevent execution of INVD after BIOS execution is complete. They report this by enumerating CPUID.(EAX=07H,ECX=1H):EAX[bit 30] as 1. On such processors, INVD cannot be executed if bit 0 of SR_BIOS_DONE (MSR address 151H) is 1.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

IA-32 Architecture Compatibility:

The INVD instruction is implementation dependent; it may be implemented differently on different families of Intel 64 or IA-32 processors. This instruction is not supported on IA-32 processors earlier than the Intel486 processor.

Operation:

Flush(InternalCaches);
SignalFlush(ExternalCaches);
Continue (* Continue execution *)

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
    If the processor reserved memory protections are activated.
    If CPUID.(EAX=07H, ECX=1H):EAX[30] = 1 and bit 0 is set in MSR_BIOS_DONE (MSR address 151H).
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP(0):
	If CPUID.(EAX=07H, ECX=1H):EAX[30] = 1 and bit 0 is set in MSR_BIOS_DONE (MSR address 151H).
    If the processor reserved memory protections are activated.
#UD:
	If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	The INVD instruction cannot be executed in virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.


INVLPG — Invalidate TLB Entries

Opcode
            Instruction	    Op/En	    64-Bit Mode	    Compat/Leg Mode	    Description
0F 01/7			                        Valid	        Valid	            Invalidate TLB entries for page containing m.

1. See the IA-32 Architecture Compatibility section below.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	Operand 3	Operand 4
M	    ModRM:r/m (r)	N/A	        N/A	        N/A

Description:

Invalidates any translation lookaside buffer (TLB) entries specified with the source operand. The source operand is a memory address. The processor determines the page that contains that address and flushes all TLB entries for that page.1

The INVLPG instruction is a privileged instruction. When the processor is running in protected mode, the CPL must be 0 to execute this instruction.

The INVLPG instruction normally flushes TLB entries only for the specified page; however, in some cases, it may flush more entries, even the entire TLB. The instruction invalidates TLB entries associated with the current PCID and may or may not do so for TLB entries associated with other PCIDs. (If PCIDs are disabled — CR4.PCIDE = 0 — the current PCID is 000H.) The instruction also invalidates any global TLB entries for the specified page, regardless of PCID.

For more details on operations that flush the TLB, see “MOV—Move to/from Control Registers” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 2B, and Section 4.10.4.1, “Operations that Invalidate TLBs and Paging-Structure Caches,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A.

This instruction’s operation is the same in all non-64-bit modes. It also operates the same in 64-bit mode, except if the memory address is in non-canonical form. In this case, INVLPG is the same as a NOP.

IA-32 Architecture Compatibility:

The INVLPG instruction is implementation dependent, and its function may be implemented differently on different families of Intel 64 or IA-32 processors. This instruction is not supported on IA-32 processors earlier than the Intel486 processor.

Operation:

Invalidate(RelevantTLBEntries);
Continue; (* Continue execution *)

Flags Affected:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
#UD:
	Operand is a register.
    If the LOCK prefix is used.

1. If the paging structures map the linear address using a page larger than 4 KBytes and there are multiple TLB entries for that page (see Section 4.10.2.3, “Details of TLB Use,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A), the instruction invalidates all of them.

Real-Address Mode Exceptions:

#UD:
	Operand is a register.
    If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	The INVLPG instruction cannot be executed at the virtual-8086 mode.

64-Bit Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
#UD:
	Operand is a register.
    If the LOCK prefix is used.



INVPCID — Invalidate Process-Context Identifier

Opcode/Instruction	                Op/En	64/32-bit Mode	CPUID Feature Flag	    Description
66 0F 38 82 /r INVPCID r32, m128	RM	    N.E./V	        INVPCID	                Invalidates entries in the TLBs and paging-structure caches based on invalidation type in r32 and descriptor in m128.
66 0F 38 82 /r INVPCID r64, m128	RM	    V/N.E.	        INVPCID	                Invalidates entries in the TLBs and paging-structure caches based on invalidation type in r64 and descriptor in m128.

Instruction Operand Encoding:

Op/En	Operand 1	    Operand 2	    Operand 3	Operand 4
RM	    ModRM:reg (r)	ModRM:r/m (r)	N/A	        N/A

Description:

Invalidates mappings in the translation lookaside buffers (TLBs) and paging-structure caches based on process-context identifier (PCID). (See Section 4.10, “Caching Translation Information,” in the Intel 64 and IA-32 Architecture Software Developer’s Manual, Volume 3A.) Invalidation is based on the INVPCID type specified in the register operand and the INVPCID descriptor specified in the memory operand.

Outside 64-bit mode, the register operand is always 32 bits, regardless of the value of CS.D. In 64-bit mode the register operand has 64 bits.

There are four INVPCID types currently defined:

Individual-address invalidation: If the INVPCID type is 0, the logical processor invalidates mappings—except global translations—for the linear address and PCID specified in the INVPCID descriptor.1 In some cases, the instruction may invalidate global translations or mappings for other linear addresses (or other PCIDs) as well.
Single-context invalidation: If the INVPCID type is 1, the logical processor invalidates all mappings—except global translations—associated with the PCID specified in the INVPCID descriptor. In some cases, the instruction may invalidate global translations or mappings for other PCIDs as well.
All-context invalidation, including global translations: If the INVPCID type is 2, the logical processor invalidates all mappings—including global translations—associated with any PCID.
All-context invalidation: If the INVPCID type is 3, the logical processor invalidates all mappings—except global translations—associated with any PCID. In some case, the instruction may invalidate global translations as well.
The INVPCID descriptor comprises 128 bits and consists of a PCID and a linear address as shown in Figure 3-25. For INVPCID type 0, the processor uses the full 64 bits of the linear address even outside 64-bit mode; the linear address is not used for other INVPCID types.

1. If the paging structures map the linear address using a page larger than 4 KBytes and there are multiple TLB entries for that page (see Section 4.10.2.3, “Details of TLB Use,” in the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A), the instruction invalidates all of them.
If CR4.PCIDE = 0, a logical processor does not cache information for any PCID other than 000H. In this case, executions with INVPCID types 0 and 1 are allowed only if the PCID specified in the INVPCID descriptor is 000H; executions with INVPCID types 2 and 3 invalidate mappings only for PCID 000H. Note that CR4.PCIDE must be 0 outside IA-32e mode (see Section 4.10.1, “Process-Context Identifiers (PCIDs),” of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 3A).

Operation:

INVPCID_TYPE := value of register operand; // must be in the range of 0–3
INVPCID_DESC := value of memory operand;
CASE INVPCID_TYPE OF
    0:
            // individual-address invalidation
        PCID := INVPCID_DESC[11:0];
        L_ADDR := INVPCID_DESC[127:64];
        Invalidate mappings for L_ADDR associated with PCID except global translations;
        BREAK;
    1:
            // single PCID invalidation
        PCID := INVPCID_DESC[11:0];
        Invalidate all mappings associated with PCID except global translations;
        BREAK;
    2:
            // all PCID invalidation including global translations
        Invalidate all mappings for all PCIDs, including global translations;
        BREAK;
    3:
            // all PCID invalidation retaining global translations
        Invalidate all mappings for all PCIDs except global translations;
        BREAK;
ESAC;

Intel C/C++ Compiler Intrinsic Equivalent:

INVPCID void _invpcid(unsigned __int32 type, void * descriptor);

SIMD Floating-Point Exceptions:

None.

Protected Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
    If the memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.
    If the DS, ES, FS, or GS register contains an unusable segment.
    If the source operand is located in an execute-only code segment.
    If an invalid type is specified in the register operand, i.e., INVPCID_TYPE > 3.
    If bits 63:12 of INVPCID_DESC are not all zero.
    If INVPCID_TYPE is either 0 or 1 and INVPCID_DESC[11:0] is not zero.
    If INVPCID_TYPE is 0 and the linear address in INVPCID_DESC[127:64] is not canonical.
#PF(fault-code):
	If a page fault occurs in accessing the memory operand.
#SS(0):
	If the memory operand effective address is outside the SS segment limit.
    If the SS register contains an unusable segment.
#UD:
	If if CPUID.(EAX=07H, ECX=0H):EBX.INVPCID[bit 10] = 0.
    If the LOCK prefix is used.

Real-Address Mode Exceptions:

#GP:
	If an invalid type is specified in the register operand, i.e., INVPCID_TYPE > 3.
    If bits 63:12 of INVPCID_DESC are not all zero.
    If INVPCID_TYPE is either 0 or 1 and INVPCID_DESC[11:0] is not zero.
    If INVPCID_TYPE is 0 and the linear address in INVPCID_DESC[127:64] is not canonical.
#UD:
	If CPUID.(EAX=07H, ECX=0H):EBX.INVPCID[bit 10] = 0.
    If the LOCK prefix is used.

Virtual-8086 Mode Exceptions:

#GP(0):
	The INVPCID instruction is not recognized in virtual-8086 mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

#GP(0):
	If the current privilege level is not 0.
    If the memory operand is in the CS, DS, ES, FS, or GS segments and the memory address is in a non-canonical form.
    If an invalid type is specified in the register operand, i.e., INVPCID_TYPE > 3.
    If bits 63:12 of INVPCID_DESC are not all zero.
    If CR4.PCIDE=0, INVPCID_TYPE is either 0 or 1, and INVPCID_DESC[11:0] is not zero.
    If INVPCID_TYPE is 0 and the linear address in INVPCID_DESC[127:64] is not canonical.
#PF(fault-code):
	If a page fault occurs in accessing the memory operand.
#SS(0):
	If the memory destination operand is in the SS segment and the memory address is in a non-canonical form.
#UD:
	If the LOCK prefix is used.
    If CPUID.(EAX=07H, ECX=0H):EBX.INVPCID[bit 10] = 0.
