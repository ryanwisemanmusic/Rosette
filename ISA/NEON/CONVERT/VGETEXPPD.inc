// CONVERT/VGETEXPPD.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VGETEXPPD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VGETEXPPD: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPPD.inc"
x86_handler = "x86_vgetexppd"
neon_lowering = "arm64_vgetexppd"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPPD"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 42 /r", form = "VGETEXPPD xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512f+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.0F38.W1 42 /r", form = "VGETEXPPD ymm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512f+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F38.W1 42 /r", form = "VGETEXPPD zmm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact", "Overflow", "Underflow"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Extract exponent of packed double-precision floating-point values as FP64.
The exponent is extracted as a biased FP64 value for each lane.
"""

handler = "x86_vgetexppd"
jit_lowering = "arm64_vgetexppd"
fallback = "zig_vgetexppd"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VGETEXPPD is an AVX512 extract-exponent conversion.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPPD.
"""

neon_assembly = """
// NEON lowering: VGETEXPPD conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
