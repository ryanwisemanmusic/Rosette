// READ/RDTSC.inc
// RDTSC — Read Time-Stamp Counter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDTSC.inc"
x86_handler = "x86_rdtsc"
neon_lowering = "arm64_documented_contract"
lowering_kind = "arm64_documented_contract"

name = "RDTSC"
category = "system_register_read"
element_type = "u32"

encodings = [
  { opcode = "0F 31", form = "RDTSC", op_en = "ZO", vector_length = 0, encoding = "legacy" }
]

operand_encoding = { ZO = [] }

reads = ["TSC"]
writes = ["EDX:EAX"]
flags_read = []
flags_written = []

semantic = """
EDX:EAX := TSC;
"""

exceptions = [
  "#GP(0) if CR4.TSD = 1 and CPL > 0",
  "#UD if the LOCK prefix is used"
]

handler = "x86_rdtsc"
jit_lowering = "arm64_sysreg_read"

neon_register_model = "RDTSC reads the x86 time-stamp counter. No ARM64 NEON equivalent."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDTSC stub"
neon_notes = ["RDTSC reads the TSC MSR into EDX:EAX.", "Non-serializing; use RDTSCP or LFENCE;RDTSC for ordering.", "CR4.TSD controls user-mode access."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
