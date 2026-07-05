// READ/RDGSBASE.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDGSBASE.inc.
// Source contract: RDGSBASE — Read GS Segment Base.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDGSBASE.inc"
x86_handler = "x86_rdgsbase"
neon_lowering = "arm64_sysreg_read"
lowering_kind = "arm64_documented_contract"

name = "RDGSBASE"
aliases = []
category = "system"
feature = "FSGSBASE"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { RM = { operand1 = "ModRM:r/m (w)" } }

simd_fp_exceptions = []

semantic_general = """
RDGSBASE reads the GS segment base address into a GPR.
"""

handler = "x86_rdgsbase"
jit_lowering = "arm64_sysreg_read"
fallback = "zig_rdgsbase"

neon_register_model = "RDGSBASE is a 64-bit mode only system instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: RDGSBASE stub — reads GS.base via arm64 TPIDR_EL0 emulation"

neon_notes = [
  "RDGSBASE is x86-specific; ARM64 uses TPIDR_EL0 for writable thread data.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
