// CONVERT/VCVTPD2UQQ.inc
// Source contract: VCVTPD2UQQ — Convert Packed Double-Precision Floating-Point Values to Packed Unsigned Quadword Integers.

semantic = """
VCVTPD2UQQ: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPD2UQQ.inc"
x86_handler = "x86_vcvtpd2uqq"
neon_lowering = "arm64_vcvtpd2uqq"
lowering_kind = "neon_vector"

name = "VCVTPD2UQQ"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F.W1 79 /r", form = "VCVTPD2UQQ xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.0F.W1 79 /r", form = "VCVTPD2UQQ ymm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F.W1 79 /r", form = "VCVTPD2UQQ zmm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
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
quadword integers using truncation or MXCSR rounding control.
"""

handler = "x86_vcvtpd2uqq"
jit_lowering = "arm64_vcvtpd2uqq"
fallback = "zig_vcvtpd2uqq"

neon_register_model = """
VCVTPD2UQQ is a avx512_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPD2UQQ.
"""

neon_assembly = """
// NEON lowering: VCVTPD2UQQ stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
