// GATHER/VGATHERDPS.inc
// Source contract: VGATHERDPS — Gather Packed Single Precision Floating-Point Values Using Signed Dword Indices.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VGATHERDPS.inc"
x86_handler = "x86_vgatherdps"
neon_lowering = "arm64_vgatherdps"
lowering_kind = "arm64_documented_contract"

name = "VGATHERDPS"
aliases = []
category = "avx2_gather"
feature = "avx2"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 92 /r", form = "VGATHERDPS xmm1, vm32x, xmm2", op_en = "A", feature = "avx2", vector_length = 128, encoding = "vex" }
  { opcode = "VEX.256.66.0F38.W0 92 /r", form = "VGATHERDPS ymm1, vm32y, ymm2", op_en = "A", feature = "avx2", vector_length = 256, encoding = "vex" }
  { opcode = "EVEX.128.66.0F38.W0 92 /vsib", form = "VGATHERDPS xmm1 {k1}, vm32x", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F38.W0 92 /vsib", form = "VGATHERDPS ymm1 {k1}, vm32y", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F38.W0 92 /vsib", form = "VGATHERDPS zmm1 {k1}, vm32z", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Single Precision Floating-Point Values Using Signed Dword Indices.
"""

handler = "x86_vgatherdps"
jit_lowering = "arm64_vgatherdps"
fallback = "zig_vgatherdps"

neon_register_model = """
VGATHERDPS is a avx2_gather instruction.
"""

neon_flag_model = """
VGATHERDPS does not modify flags.
"""

neon_assembly = """
// NEON lowering: VGATHERDPS stub (avx2_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
