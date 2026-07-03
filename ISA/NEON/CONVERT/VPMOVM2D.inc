// CONVERT/VPMOVM2D.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VPMOVM2D.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VPMOVM2D: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVM2D.inc"
x86_handler = "x86_vpmovm2d"
neon_lowering = "arm64_vpmovm2d"
lowering_kind = "arm64_documented_contract"

name = "VPMOVM2D"
aliases = []
category = "avx512_convert"
feature = "avx512dq"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 28 /r", form = "VPMOVM2D xmm1, k2", op_en = "A", feature = "avx512dq+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 28 /r", form = "VPMOVM2D ymm1, k2", op_en = "A", feature = "avx512dq+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 28 /r", form = "VPMOVM2D zmm1, k2", op_en = "A", feature = "avx512dq", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Move mask to dword vector: zero each dword element in the destination vector
except the most significant bit, which is set from the corresponding mask bit.
"""

handler = "x86_vpmovm2d"
jit_lowering = "arm64_vpmovm2d"
fallback = "zig_vpmovm2d"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVM2D is an AVX512DQ mask-to-vector conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVM2D.
"""

neon_assembly = """
// NEON lowering: VPMOVM2D conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
