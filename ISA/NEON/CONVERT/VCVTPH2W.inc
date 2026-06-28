// NEON/CONVERT/VCVTPH2W.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTPH2W.inc.
// Source contract: VCVTPH2W — avx512fp16_convert.

semantic = """
VCVTPH2W: preserve the operation and form-specific semantic blocks.
Category: avx512fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPH2W.inc"
x86_handler = "x86_vcvtph2w"
neon_lowering = "arm64_vcvtph2w"
lowering_kind = "neon_vector"

name = "VCVTPH2W"
aliases = []
category = "avx512fp16_convert"
feature = "avx512fp16"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP5.W0 7D /r", form = "VCVTPH2W xmm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.66.MAP5.W0 7D /r", form = "VCVTPH2W ymm1{k1}{z}, ymm2/m256/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.66.MAP5.W0 7D /r", form = "VCVTPH2W zmm1{k1}{z}, zmm2/m512/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
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
word integers using MXCSR rounding control.
"""

handler = "x86_vcvtph2w"
jit_lowering = "arm64_vcvtph2w"
fallback = "zig_vcvtph2w"

neon_register_model = """
VCVTPH2W is a avx512fp16_convert instruction.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPH2W.
"""

neon_assembly = """
// NEON lowering: VCVTPH2W stub (avx512fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
