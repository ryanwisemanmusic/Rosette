// SCATTER/VPSCATTERDD.inc
// Source contract: VPSCATTERDD — avx512_scatter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCATTER/VPSCATTERDD.inc"
x86_handler = "x86_vpscatterdd"
neon_lowering = "arm64_vpscatterdd"
lowering_kind = "arm64_documented_contract"

name = "VPSCATTERDD"
aliases = []
category = "avx512_scatter"
feature = "avx512f"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 A0 /vsib", form = "VPSCATTERDD vm32x {k1}, xmm1", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.66.0F38.W0 A0 /vsib", form = "VPSCATTERDD vm32y {k1}, ymm1", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.66.0F38.W0 A0 /vsib", form = "VPSCATTERDD vm32z {k1}, zmm1", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Scatter Packed Dword with Signed Dword Indices.
"""

handler = "x86_vpscatterdd"
jit_lowering = "arm64_vpscatterdd"
fallback = "zig_vpscatterdd"

neon_register_model = """
VPSCATTERDD is a avx512_scatter instruction.
"""

neon_flag_model = """
VPSCATTERDD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPSCATTERDD stub (avx512_scatter)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

