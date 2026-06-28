// CONVERT/VCVTPH2PS.inc
// Source contract: VCVTPH2PS — Convert Packed Half-Precision Floating-Point Values to Packed Single-Precision Floating-Point Values.

semantic = """
VCVTPH2PS: preserve the operation and form-specific semantic blocks.
Category: avx_fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPH2PS.inc"
x86_handler = "x86_vcvtph2ps"
neon_lowering = "arm64_vcvtph2ps"
lowering_kind = "neon_vector"

name = "VCVTPH2PS"
aliases = ["VCVTPH2PS"]
category = "avx_fp16_convert"
feature = "f16c_avx512fp16"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 13 /r", form = "VCVTPH2PS xmm1, xmm2/m64", op_en = "A", feature = "f16c", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 13 /r", form = "VCVTPH2PS ymm1, xmm2/m128", op_en = "A", feature = "f16c", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 13 /r", form = "VCVTPH2PS xmm1{k1}{z}, xmm2/m64/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.256.66.0F38.W0 13 /r", form = "VCVTPH2PS ymm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.512.66.0F38.W0 13 /r", form = "VCVTPH2PS zmm1{k1}{z}, ymm2/m256/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m16bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if VEX/EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Convert packed half-precision floating-point values to packed single-precision
floating-point values using MXCSR rounding control. VEX forms support F16C;
EVEX forms support AVX512-FP16 with masking and broadcast.
"""

handler = "x86_vcvtph2ps"
jit_lowering = "arm64_vcvtph2ps"
fallback = "zig_vcvtph2ps"

neon_register_model = """
VCVTPH2PS is a avx_fp16_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPH2PS.
"""

neon_assembly = """
// NEON lowering: VCVTPH2PS stub (avx_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
