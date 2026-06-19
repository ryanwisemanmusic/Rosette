// SCATTER/VSCATTERDPD.inc
// Source contract: VSCATTERDPD — avx512_scatter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCATTER/VSCATTERDPD.inc"
x86_handler = "x86_vscatterdpd"
neon_lowering = "arm64_vscatterdpd"
lowering_kind = "arm64_documented_contract"

name = "VSCATTERDPD"
aliases = []
category = "avx512_scatter"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 A2 /vsib", form = "VSCATTERDPD vm32x {k1}, xmm1", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.66.0F38.W1 A2 /vsib", form = "VSCATTERDPD vm32x {k1}, ymm1", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.66.0F38.W1 A2 /vsib", form = "VSCATTERDPD vm32y {k1}, zmm1", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Scatter Packed Double with Signed Dword Indices.
"""

handler = "x86_vscatterdpd"
jit_lowering = "arm64_vscatterdpd"
fallback = "zig_vscatterdpd"

neon_register_model = """
VSCATTERDPD is a avx512_scatter instruction.
"""

neon_flag_model = """
VSCATTERDPD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VSCATTERDPD stub (avx512_scatter)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

