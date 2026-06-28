// NEON/CONVERT/VCVTNE2PS2BF16.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTNE2PS2BF16.inc.
// Source contract: VCVTNE2PS2BF16 — avx512bf16_convert.

semantic = """
VCVTNE2PS2BF16: preserve the operation and form-specific semantic blocks.
Category: avx512bf16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTNE2PS2BF16.inc"
x86_handler = "x86_vcvtne2ps2bf16"
neon_lowering = "arm64_vcvtne2ps2bf16"
lowering_kind = "neon_vector"

name = "VCVTNE2PS2BF16"
aliases = []
category = "avx512bf16_convert"
feature = "avx512bf16"
element_type = "bf16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.F2.0F38.W0 72 /r", form = "VCVTNE2PS2BF16 xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "avx512bf16", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.F2.0F38.W0 72 /r", form = "VCVTNE2PS2BF16 ymm1{k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "avx512bf16", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.F2.0F38.W0 72 /r", form = "VCVTNE2PS2BF16 zmm1{k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "avx512bf16", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Convert two packed single-precision floating-point values to BF16 with
rounding toward nearest even. Each 32-bit source pair produces one BF16
result in the low half of the destination lane.
"""

handler = "x86_vcvtne2ps2bf16"
jit_lowering = "arm64_vcvtne2ps2bf16"
fallback = "zig_vcvtne2ps2bf16"

neon_register_model = """
VCVTNE2PS2BF16 is a avx512bf16_convert instruction.
"""

neon_flag_model = """
No x86 flags are modified by VCVTNE2PS2BF16.
"""

neon_assembly = """
// NEON lowering: VCVTNE2PS2BF16 stub (avx512bf16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
