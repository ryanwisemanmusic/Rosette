// CONVERT/VCVTPD2UDQ.inc
// Source contract: VCVTPD2UDQ — Convert Packed Double-Precision Floating-Point Values to Packed Unsigned Doubleword Integers.

semantic = """
VCVTPD2UDQ: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPD2UDQ.inc"
x86_handler = "x86_vcvtpd2udq"
neon_lowering = "arm64_vcvtpd2udq"
lowering_kind = "neon_vector"

name = "VCVTPD2UDQ"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.0F.W1 79 /r", form = "VCVTPD2UDQ xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.0F.W1 79 /r", form = "VCVTPD2UDQ xmm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.0F.W1 79 /r", form = "VCVTPD2UDQ ymm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
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
Convert packed double-precision floating-point values to packed unsigned
doubleword integers using truncation or MXCSR rounding control.
"""

handler = "x86_vcvtpd2udq"
jit_lowering = "arm64_vcvtpd2udq"
fallback = "zig_vcvtpd2udq"

neon_register_model = """
VCVTPD2UDQ is a avx512_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPD2UDQ.
"""

neon_assembly = """
// NEON lowering: VCVTPD2UDQ stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
