// SQUARE_ROOT/SQRTPD.inc
// ARM64/NEON mirror generated from ISA/x86/SQUARE_ROOT/SQRTPD.inc.
// Source contract: SQRTPD — simd_float_sqrt.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SQUARE_ROOT/SQRTPD.inc"
x86_handler = "x86_sqrtpd"
neon_lowering = "arm64_sqrtpd"
lowering_kind = "arm64_documented_contract"

name = "SQRTPD"
aliases = []
category = "simd_float_sqrt"
feature = "sse2"
element_type = "f64"
element_size = 64

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Square Root of Double Precision Floating-Point Values.
"""

handler = "x86_sqrtpd"
jit_lowering = "arm64_sqrtpd"
fallback = "zig_sqrtpd"

neon_register_model = """
SQRTPD is a simd_float_sqrt instruction.
"""

neon_flag_model = """
SQRTPD does not modify flags.
"""

neon_assembly = """
// NEON lowering: SQRTPD stub (simd_float_sqrt)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

