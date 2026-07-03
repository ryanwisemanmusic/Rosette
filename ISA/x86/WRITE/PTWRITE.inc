// WRITE/PTWRITE.inc
// PTWRITE — Write Data to a Processor Trace Packet.

name = "PTWRITE"
category = "system"
feature = "PTWRITE"
element_type = "gpr"

encodings = [
  { opcode = "F3 REX.W 0F AE /4", form = "PTWRITE r64/m64", op_en = "RM", feature = "PTWRITE", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 0F AE /4", form = "PTWRITE r32/m32", op_en = "RM", feature = "PTWRITE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { RM = { operand1 = "ModRM:r/m (r)" } }

reads = ["SRC"]
writes = []
flags_read = []
flags_written = []

semantic = """
IF (IA32_RTIT_STATUS.TriggerEn & IA32_RTIT_STATUS.ContextEn & IA32_RTIT_STATUS.FilterEn & IA32_RTIT_CTL.PTWEn) = 1
    PTW.PayloadBytes := Encoded payload size;
    PTW.IP := IA32_RTIT_CTL.FUPonPTW;
    IF IA32_RTIT_CTL.FUPonPTW = 1
        Insert FUP packet with IP of PTWRITE;
    FI;
FI;
"""

exceptions = [
  "#UD if CPUID.(EAX=14H, ECX=0H):EBX.PTWRITE [Bit 4] = 0",
  "#UD if LOCK prefix is used",
  "#UD if 66H prefix is used"
]

handler = "x86_ptwrite"
jit_lowering = "arm64_sys_write_ptwrite"

neon_register_model = "PTWRITE is an Intel PT system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: PTWRITE stub"
neon_notes = ["PTWRITE sends source data to Intel Processor Trace hardware.", "ARM64: PTWRITE is x86-specific; no ARM64 equivalent."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
