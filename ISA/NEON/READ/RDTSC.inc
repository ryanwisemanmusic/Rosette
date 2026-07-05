// READ/RDTSC.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDTSC.inc.
// Source contract: RDTSC — Read Time-Stamp Counter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDTSC.inc"
x86_handler = "x86_rdtsc"
neon_lowering = "arm64_cntvct_read"
lowering_kind = "arm64_documented_contract"

name = "RDTSC"
aliases = []
category = "system"
feature = "x86_system"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
RDTSC reads timestamp counter into EDX:EAX.
"""

handler = "x86_rdtsc"
jit_lowering = "arm64_cntvct_read"
fallback = "zig_rdtsc"

neon_register_model = "RDTSC reads the x86 TSC. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDTSC stub — reads virtual count via arm64 CNTVCT_EL0"

neon_notes = [
  "RDTSC is x86-specific; ARM64 uses CNTVCT_EL0 for virtual count.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
