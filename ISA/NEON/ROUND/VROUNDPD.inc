// ROUND/VROUNDPD.inc
// ARM64/NEON mirror generated from ISA/x86/ROUND/VROUNDPD.inc.
// Source contract: VROUNDPD — simd_round.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROUND/VROUNDPD.inc"
x86_handler = "x86_vroundpd"
neon_lowering = "arm64_vroundpd"
lowering_kind = "arm64_documented_contract"

name = "VROUNDPD"
aliases = []
category = "simd_round"
feature = "avx"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F3A 09 /r ib", form = "VROUNDPD xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F3A 09 /r ib", form = "VROUNDPD ymm1, ymm2/m256, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Round Packed Double-Precision Floating-Point Values.
"""

handler = "x86_vroundpd"
jit_lowering = "arm64_vroundpd"
fallback = "zig_vroundpd"

neon_register_model = """
VROUNDPD is a simd_round instruction.
"""

neon_flag_model = """
VROUNDPD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VROUNDPD stub (simd_round)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

