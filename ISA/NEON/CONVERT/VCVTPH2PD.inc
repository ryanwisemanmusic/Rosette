// NEON/CONVERT/VCVTPH2PD.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTPH2PD.inc.
// Source contract: VCVTPH2PD — avx512fp16_convert.

semantic = """
VCVTPH2PD: preserve the operation and form-specific semantic blocks.
Category: avx512fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPH2PD.inc"
x86_handler = "x86_vcvtph2pd"
neon_lowering = "arm64_vcvtph2pd"
lowering_kind = "neon_vector"

name = "VCVTPH2PD"
aliases = []
category = "avx512fp16_convert"
feature = "avx512fp16"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.NP.MAP5.W0 5A /r", form = "VCVTPH2PD xmm1{k1}{z}, xmm2/m32/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.NP.MAP5.W0 5A /r", form = "VCVTPH2PD ymm1{k1}{z}, xmm2/m64/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.NP.MAP5.W0 5A /r", form = "VCVTPH2PD zmm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
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
Convert packed half-precision floating-point values to packed double-precision
floating-point values using MXCSR rounding control.
"""

handler = "x86_vcvtph2pd"
jit_lowering = "arm64_vcvtph2pd"
fallback = "zig_vcvtph2pd"

neon_register_model = """
VCVTPH2PD is a avx512fp16_convert instruction.
"""

neon_flag_model = """
No x86 flags are modified by VCVTPH2PD.
"""

neon_assembly = """
// NEON lowering: VCVTPH2PD stub (avx512fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
