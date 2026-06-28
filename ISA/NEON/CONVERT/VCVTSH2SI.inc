// NEON/CONVERT/VCVTSH2SI.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTSH2SI.inc.

semantic = """
VCVTSH2SI: preserve the operation and form-specific semantic blocks.
Category: avx512_fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTSH2SI.inc"
x86_handler = "x86_vcvtsh2si"
neon_lowering = "arm64_vcvtsh2si"
lowering_kind = "arm64_documented_contract"

name = "VCVTSH2SI"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 2D /r", form = "VCVTSH2SI r32, xmm2/m16, {er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.LLIG.F3.MAP5.W1 2D /r", form = "VCVTSH2SI r64, xmm2/m16, {er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Invalid"
]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Convert the low half-precision FP16 element to a signed integer, storing in GPR.
"""

handler = "x86_vcvtsh2si"
jit_lowering = "arm64_vcvtsh2si"
fallback = "zig_vcvtsh2si"

neon_register_model = """
x86 XMM/GPR mapped to ARM64 Vn/xN. VCVTSH2SI is a scalar AVX512-FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTSH2SI.
"""

neon_assembly = """
// NEON lowering: VCVTSH2SI conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
