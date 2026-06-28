// CONVERT/VCVTPD2PH.inc
// Source contract: VCVTPD2PH — Convert Packed Double-Precision Floating-Point Values to Packed Half-Precision Floating-Point Values.

semantic = """
VCVTPD2PH: preserve the operation and form-specific semantic blocks.
Category: avx512fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPD2PH.inc"
x86_handler = "x86_vcvtpd2ph"
neon_lowering = "arm64_vcvtpd2ph"
lowering_kind = "neon_vector"

name = "VCVTPD2PH"
aliases = []
category = "avx512fp16_convert"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP5.W1 5A /r", form = "VCVTPD2PH xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.MAP5.W1 5A /r", form = "VCVTPD2PH xmm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.MAP5.W1 5A /r", form = "VCVTPD2PH xmm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact", "Overflow", "Underflow"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Convert packed double-precision floating-point values to packed half-precision
floating-point values. The result is written to the lower elements of the
destination XMM register with rounding control via MXCSR or EVEX.RC.
"""

handler = "x86_vcvtpd2ph"
jit_lowering = "arm64_vcvtpd2ph"
fallback = "zig_vcvtpd2ph"

neon_register_model = """
VCVTPD2PH is a avx512fp16_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPD2PH.
"""

neon_assembly = """
// NEON lowering: VCVTPD2PH stub (avx512fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
