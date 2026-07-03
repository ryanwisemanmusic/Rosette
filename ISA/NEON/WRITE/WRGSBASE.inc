// WRITE/WRGSBASE.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/WRGSBASE.inc.
// Source contract: WRGSBASE — Write GS Segment Base.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/WRGSBASE.inc"
x86_handler = "x86_wrgsbase"
neon_lowering = "arm64_sysreg_write"
lowering_kind = "arm64_documented_contract"

name = "WRGSBASE"
aliases = []
category = "system"
feature = "FSGSBASE"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { M = { operand1 = "ModRM:r/m (r)" } }

simd_fp_exceptions = []

semantic_general = """
WRGSBASE writes the GS segment base address.
"""

handler = "x86_wrgsbase"
jit_lowering = "arm64_sysreg_write"
fallback = "zig_wrgsbase"

neon_register_model = "WRGSBASE is a 64-bit mode only system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRGSBASE stub"

neon_notes = [
  "WRGSBASE is x86-specific; ARM64 uses MSR writes.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
