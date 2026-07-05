// READ/RDTSCP.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDTSCP.inc.
// Source contract: RDTSCP — Read Time-Stamp Counter and Processor ID.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDTSCP.inc"
x86_handler = "x86_rdtscp"
neon_lowering = "arm64_cntvct_read"
lowering_kind = "arm64_documented_contract"

name = "RDTSCP"
aliases = []
category = "system"
feature = "RDTSCP"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
RDTSCP reads timestamp counter into EDX:EAX and IA32_TSC_AUX into ECX.
"""

handler = "x86_rdtscp"
jit_lowering = "arm64_cntvct_read"
fallback = "zig_rdtscp"

neon_register_model = "RDTSCP reads the x86 TSC and IA32_TSC_AUX. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDTSCP stub — reads virtual count via arm64 CNTVCT_EL0 and processor ID via MPIDR_EL1"

neon_notes = [
  "RDTSCP is x86-specific; ARM64 uses CNTVCT_EL0 for virtual count and MPIDR_EL1 for processor ID.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
