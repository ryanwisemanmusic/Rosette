// WRITE/WRPKRU.inc
// ARM64/NEON mirror generated from ISA/x86/WRITE/WRPKRU.inc.
// Source contract: WRPKRU — Write Data to User Page Key Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WRITE/WRPKRU.inc"
x86_handler = "x86_wrpkru"
neon_lowering = "arm64_sysreg_write"
lowering_kind = "arm64_documented_contract"

name = "WRPKRU"
aliases = []
category = "system"
feature = "OSPKE"
element_type = "none"
element_size = 0

encodings = []

operand_encoding = { ZO = [] }

simd_fp_exceptions = []

semantic_general = """
WRPKRU writes EAX into PKRU when ECX=EDX=0.
"""

handler = "x86_wrpkru"
jit_lowering = "arm64_sysreg_write"
fallback = "zig_wrpkru"

neon_register_model = "WRPKRU is a system instruction for PKRU register update. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: WRPKRU stub"

neon_notes = [
  "WRPKRU is x86-specific; no ARM64 PKRU equivalent.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
