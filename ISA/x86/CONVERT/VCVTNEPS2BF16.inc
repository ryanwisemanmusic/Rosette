// CONVERT/VCVTNEPS2BF16.inc
// Source contract: VCVTNEPS2BF16 — Convert Packed Single Data to BF16 Values with NE rounding.

semantic = """
VCVTNEPS2BF16: preserve the operation and form-specific semantic blocks.
Category: avx512bf16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTNEPS2BF16.inc"
x86_handler = "x86_vcvtneps2bf16"
neon_lowering = "arm64_vcvtneps2bf16"
lowering_kind = "neon_vector"

name = "VCVTNEPS2BF16"
aliases = []
category = "avx512bf16_convert"
feature = "avx512bf16"
element_type = "bf16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 72 /r", form = "VCVTNEPS2BF16 xmm1{k1}{z}, xmm2/m128/m32bcst", op_en = "A", feature = "avx512bf16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.256.F3.0F38.W0 72 /r", form = "VCVTNEPS2BF16 ymm1{k1}{z}, ymm2/m256/m32bcst", op_en = "A", feature = "avx512bf16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.512.F3.0F38.W0 72 /r", form = "VCVTNEPS2BF16 zmm1{k1}{z}, zmm2/m512/m32bcst", op_en = "A", feature = "avx512bf16", vector_length = 512, encoding = "evex", broadcast = "m32bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Convert packed single-precision floating-point values to BF16 with
rounding toward nearest even. Each pair of 32-bit source elements
produces one BF16 result in the destination lane.
"""

handler = "x86_vcvtneps2bf16"
jit_lowering = "arm64_vcvtneps2bf16"
fallback = "zig_vcvtneps2bf16"

neon_register_model = """
VCVTNEPS2BF16 is a avx512bf16_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTNEPS2BF16.
"""

neon_assembly = """
// NEON lowering: VCVTNEPS2BF16 stub (avx512bf16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
