// READ/RDFSBASE.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDFSBASE.inc.
// Source contract: RDFSBASE — Read FS Segment Base.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDFSBASE.inc"
x86_handler = "x86_rdfsbase"
neon_lowering = "arm64_sysreg_read"
lowering_kind = "arm64_documented_contract"

name = "RDFSBASE"
aliases = []
category = "system"
feature = "FSGSBASE"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { RM = { operand1 = "ModRM:r/m (w)" } }

simd_fp_exceptions = []

semantic_general = """
RDFSBASE reads the FS segment base address into a GPR.
"""

handler = "x86_rdfsbase"
jit_lowering = "arm64_sysreg_read"
fallback = "zig_rdfsbase"

neon_register_model = "RDFSBASE is a 64-bit mode only system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDFSBASE stub — reads FS.base via arm64 TPIDRRO_EL0 emulation"

neon_notes = [
  "RDFSBASE is x86-specific; ARM64 uses TPIDRRO_EL0 for read-only thread data.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
