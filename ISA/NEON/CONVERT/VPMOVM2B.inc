// CONVERT/VPMOVM2B.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VPMOVM2B.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VPMOVM2B: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVM2B.inc"
x86_handler = "x86_vpmovm2b"
neon_lowering = "arm64_vpmovm2b"
lowering_kind = "arm64_documented_contract"

name = "VPMOVM2B"
aliases = []
category = "avx512_convert"
feature = "avx512bw"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 28 /r", form = "VPMOVM2B xmm1, k2", op_en = "A", feature = "avx512bw+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 28 /r", form = "VPMOVM2B ymm1, k2", op_en = "A", feature = "avx512bw+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 28 /r", form = "VPMOVM2B zmm1, k2", op_en = "A", feature = "avx512bw", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 16, ymm = 32, zmm = 64 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Move mask to byte vector: zero each byte element in the destination vector
except the most significant bit, which is set from the corresponding mask bit.
"""

handler = "x86_vpmovm2b"
jit_lowering = "arm64_vpmovm2b"
fallback = "zig_vpmovm2b"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVM2B is an AVX512BW mask-to-vector conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVM2B.
"""

neon_assembly = """
// NEON lowering: VPMOVM2B conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
