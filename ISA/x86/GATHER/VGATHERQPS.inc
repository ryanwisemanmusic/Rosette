// GATHER/VGATHERQPS.inc
// Source contract: VGATHERQPS — Gather Packed Single Precision Floating-Point Values Using Signed Qword Indices.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VGATHERQPS.inc"
x86_handler = "x86_vgatherqps"
neon_lowering = "arm64_vgatherqps"
lowering_kind = "arm64_documented_contract"

name = "VGATHERQPS"
aliases = []
category = "avx2_gather"
feature = "avx2"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 93 /r", form = "VGATHERQPS xmm1, vm64x, xmm2", op_en = "A", feature = "avx2", vector_length = 128, encoding = "vex" }
  { opcode = "VEX.256.66.0F38.W0 93 /r", form = "VGATHERQPS xmm1, vm64y, xmm2", op_en = "A", feature = "avx2", vector_length = 256, encoding = "vex" }
  { opcode = "EVEX.128.66.0F38.W0 93 /vsib", form = "VGATHERQPS xmm1 {k1}, vm64x", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F38.W0 93 /vsib", form = "VGATHERQPS xmm1 {k1}, vm64y", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F38.W0 93 /vsib", form = "VGATHERQPS ymm1 {k1}, vm64z", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Single Precision Floating-Point Values Using Signed Qword Indices.
"""

handler = "x86_vgatherqps"
jit_lowering = "arm64_vgatherqps"
fallback = "zig_vgatherqps"

neon_register_model = """
VGATHERQPS is a avx2_gather instruction.
"""

neon_flag_model = """
VGATHERQPS does not modify flags.
"""

neon_assembly = """
// NEON lowering: VGATHERQPS stub (avx2_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
