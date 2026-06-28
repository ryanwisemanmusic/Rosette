// CONVERT/VCVTPH2PSX.inc
// Source contract: VCVTPH2PSX — Convert Packed Half-Precision Floating-Point Values to Packed Single-Precision Floating-Point Values (with SAE).

semantic = """
VCVTPH2PSX: preserve the operation and form-specific semantic blocks.
Category: avx512fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPH2PSX.inc"
x86_handler = "x86_vcvtph2psx"
neon_lowering = "arm64_vcvtph2psx"
lowering_kind = "neon_vector"

name = "VCVTPH2PSX"
aliases = []
category = "avx512fp16_convert"
feature = "avx512fp16"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.MAP6.W0 13 /r", form = "VCVTPH2PSX xmm1{k1}{z}, xmm2/m64/m16bcst{sae}", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.256.66.MAP6.W0 13 /r", form = "VCVTPH2PSX ymm1{k1}{z}, xmm2/m128/m16bcst{sae}", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.512.66.MAP6.W0 13 /r", form = "VCVTPH2PSX zmm1{k1}{z}, ymm2/m256/m16bcst{sae}", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m16bcst" }
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
Convert packed half-precision floating-point values to packed single-precision
floating-point values with SAE (suppress all exceptions) rounding control.
"""

handler = "x86_vcvtph2psx"
jit_lowering = "arm64_vcvtph2psx"
fallback = "zig_vcvtph2psx"

neon_register_model = """
VCVTPH2PSX is a avx512fp16_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPH2PSX.
"""

neon_assembly = """
// NEON lowering: VCVTPH2PSX stub (avx512fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
