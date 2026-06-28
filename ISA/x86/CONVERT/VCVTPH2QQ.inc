// CONVERT/VCVTPH2QQ.inc
// Source contract: VCVTPH2QQ — Convert Packed Half-Precision Floating-Point Values to Packed Signed Quadword Integers.

semantic = """
VCVTPH2QQ: preserve the operation and form-specific semantic blocks.
Category: avx512fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPH2QQ.inc"
x86_handler = "x86_vcvtph2qq"
neon_lowering = "arm64_vcvtph2qq"
lowering_kind = "neon_vector"

name = "VCVTPH2QQ"
aliases = []
category = "avx512fp16_convert"
feature = "avx512fp16"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.MAP5.W0 7B /r", form = "VCVTPH2QQ xmm1{k1}{z}, xmm2/m32/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.256.66.MAP5.W0 7B /r", form = "VCVTPH2QQ ymm1{k1}{z}, xmm2/m64/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.512.66.MAP5.W0 7B /r", form = "VCVTPH2QQ zmm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m16bcst" }
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
quadword integers using MXCSR rounding control.
"""

handler = "x86_vcvtph2qq"
jit_lowering = "arm64_vcvtph2qq"
fallback = "zig_vcvtph2qq"

neon_register_model = """
VCVTPH2QQ is a avx512fp16_convert instruction. ARM64 NEON lowering is a documented contract.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPH2QQ.
"""

neon_assembly = """
// NEON lowering: VCVTPH2QQ stub (avx512fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
