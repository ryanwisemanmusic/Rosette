// READ/RDSEED.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDSEED.inc.
// Source contract: RDSEED — Read Random Seed.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDSEED.inc"
x86_handler = "x86_rdseed"
neon_lowering = "arm64_rndrrs_read"
lowering_kind = "arm64_documented_contract"

name = "RDSEED"
aliases = []
category = "system"
feature = "RDSEED"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { RM = { operand1 = "ModRM:r/m (w)" } }

simd_fp_exceptions = []

semantic_general = """
RDSEED reads a hardware-generated random seed into a GPR.
"""

handler = "x86_rdseed"
jit_lowering = "arm64_rndrrs_read"
fallback = "zig_rdseed"

neon_register_model = "RDSEED reads hardware random seed. No NEON register effect."
neon_flag_model = "CF=1 on success, CF=0 on no seed data available."
neon_assembly = "// NEON lowering: RDSEED stub — reads random seed via arm64 RNDRRS"

neon_notes = [
  "RDSEED is x86-specific; ARM64 uses RNDRRS for hardware random seed.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
