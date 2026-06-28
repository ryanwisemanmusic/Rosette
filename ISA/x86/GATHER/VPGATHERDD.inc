// GATHER/VPGATHERDD.inc
// Source contract: VPGATHERDD — Gather Packed Dword Values Using Signed Dword Indices.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VPGATHERDD.inc"
x86_handler = "x86_vpgatherdd"
neon_lowering = "arm64_vpgatherdd"
lowering_kind = "arm64_documented_contract"

name = "VPGATHERDD"
aliases = []
category = "avx2_gather"
feature = "avx2"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 90 /r", form = "VPGATHERDD xmm1, vm32x, xmm2", op_en = "A", feature = "avx2", vector_length = 128, encoding = "vex" }
  { opcode = "VEX.256.66.0F38.W0 90 /r", form = "VPGATHERDD ymm1, vm32y, ymm2", op_en = "A", feature = "avx2", vector_length = 256, encoding = "vex" }
  { opcode = "EVEX.128.66.0F38.W0 90 /vsib", form = "VPGATHERDD xmm1 {k1}, vm32x", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F38.W0 90 /vsib", form = "VPGATHERDD ymm1 {k1}, vm32y", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F38.W0 90 /vsib", form = "VPGATHERDD zmm1 {k1}, vm32z", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Dword Values Using Signed Dword Indices.
"""

handler = "x86_vpgatherdd"
jit_lowering = "arm64_vpgatherdd"
fallback = "zig_vpgatherdd"

neon_register_model = """
VPGATHERDD is a avx2_gather instruction.
"""

neon_flag_model = """
VPGATHERDD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPGATHERDD stub (avx2_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
