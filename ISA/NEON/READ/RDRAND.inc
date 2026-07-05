// READ/RDRAND.inc
// ARM64/NEON mirror generated from ISA/x86/READ/RDRAND.inc.
// Source contract: RDRAND — Read Random Number.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "READ/RDRAND.inc"
x86_handler = "x86_rdrand"
neon_lowering = "arm64_rndr_read"
lowering_kind = "arm64_documented_contract"

name = "RDRAND"
aliases = []
category = "system"
feature = "RDRAND"
element_type = "gpr"
element_size = 0

encodings = []

operand_encoding = { RM = { operand1 = "ModRM:r/m (w)" } }

simd_fp_exceptions = []

semantic_general = """
RDRAND reads a hardware-generated random number into a GPR.
"""

handler = "x86_rdrand"
jit_lowering = "arm64_rndr_read"
fallback = "zig_rdrand"

neon_register_model = "RDRAND reads hardware random data. No NEON register effect."
neon_flag_model = "CF=1 on success, CF=0 on no random data available."
neon_assembly = "// NEON lowering: RDRAND stub — reads random via arm64 RNDRRS"

neon_notes = [
  "RDRAND is x86-specific; ARM64 uses RNDR/RNDRRS for hardware random numbers.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
