// WRITE/WRFSBASE.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/WRFSBASE.inc.
// Source contract: WRFSBASE — Write FS Segment Base.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/WRFSBASE.inc"
x86_handler = "x86_wrfsbase"
neon_lowering = "arm64_sysreg_write"
lowering_kind = "arm64_documented_contract"

name = "WRFSBASE"
aliases = []
category = "system"
feature = "FSGSBASE"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { M = { operand1 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
WRFSBASE writes the FS segment base address.
"""

handler = "x86_wrfsbase"
jit_lowering = "arm64_sysreg_write"
fallback = "zig_wrfsbase"

neon_register_model = "WRFSBASE is a 64-bit mode only system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRFSBASE stub"

neon_notes = [
  "WRFSBASE is x86-specific; ARM64 uses MSR writes.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
