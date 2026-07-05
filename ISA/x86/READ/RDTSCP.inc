// READ/RDTSCP.inc
// RDTSCP — Read Time-Stamp Counter and Processor ID.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDTSCP.inc"
x86_handler = "x86_rdtscp"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDTSCP"
category = "system_register_read"
feature = "RDTSCP"
element_type = "u32"

encodings = [
  { opcode = "0F 01 F9", form = "RDTSCP", op_en = "ZO", feature = "RDTSCP", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["TSC", "IA32_TSC_AUX"]
writes = ["EDX:EAX", "ECX"]
flags_read = []
flags_written = []

semantic = """
EDX:EAX := TSC;
ECX := IA32_TSC_AUX;
"""

exceptions = [
  "#GP(0) if CR4.TSD = 1 and CPL > 0",
  "#UD if CPUID.80000001H:EDX.RDTSCP[bit 27] = 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_rdtscp"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDTSCP reads the TSC and IA32_TSC_AUX. No ARM64 NEON equivalent."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDTSCP stub"
neon_notes = ["RDTSCP reads TSC into EDX:EAX and IA32_TSC_AUX into ECX.", "Serializing instruction (waits for prior instructions to complete).", "CR4.TSD controls user-mode access."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
