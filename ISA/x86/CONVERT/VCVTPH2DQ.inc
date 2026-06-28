// CONVERT/VCVTPH2DQ.inc
// Source contract: VCVTPH2DQ — Convert Packed Half-Precision Floating-Point Values to Packed Signed Doubleword Integers.

semantic = """
VCVTPH2DQ: preserve the operation and form-specific semantic blocks.
Category: avx512fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPH2DQ.inc"
x86_handler = "x86_vcvtph2dq"
neon_lowering = "arm64_vcvtph2dq"
lowering_kind = "neon_vector"

name = "VCVTPH2DQ"
aliases = []
category = "avx512fp16_convert"
feature = "avx512fp16"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.MAP5.W0 5B /r", form = "VCVTPH2DQ xmm1{k1}{z}, xmm2/m64/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.256.66.MAP5.W0 5B /r", form = "VCVTPH2DQ ymm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.512.66.MAP5.W0 5B /r", form = "VCVTPH2DQ zmm1{k1}{z}, ymm2/m256/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m16bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = ["Invalid"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Convert packed half-precision floating-point values to packed signed
doubleword integers using MXCSR rounding control.
"""

handler = "x86_vcvtph2dq"
jit_lowering = "arm64_vcvtph2dq"
fallback = "zig_vcvtph2dq"

neon_register_model = """
VCVTPH2DQ is a avx512fp16_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPH2DQ.
"""

neon_assembly = """
// NEON lowering: VCVTPH2DQ stub (avx512fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
