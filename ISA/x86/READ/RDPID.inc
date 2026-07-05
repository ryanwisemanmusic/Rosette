// READ/RDPID.inc
// RDPID — Read Processor ID.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDPID.inc"
x86_handler = "x86_rdpid"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDPID"
category = "system_register_read"
feature = "RDPID"
element_type = "gpr"

encodings = [
  { opcode = "F3 0F C7 /7", form = "RDPID r32", op_en = "R", feature = "RDPID", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 0F C7 /7", form = "RDPID r64", op_en = "R", feature = "RDPID", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { R = { operand1 = "ModRM:r/m (w)" } }

reads = ["IA32_TSC_AUX"]
writes = ["DST"]
flags_read = []
flags_written = []

semantic = """
DST := IA32_TSC_AUX;
"""

exceptions = [
  "#UD if CPUID.(EAX=07H, ECX=0):ECX.RDPID[bit 22] = 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_rdpid"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDPID reads the IA32_TSC_AUX MSR. No ARM64 NEON equivalent."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDPID stub"
neon_notes = ["RDPID reads the IA32_TSC_AUX MSR into the destination register.", "Provides OS-visible processor ID without serialization."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
