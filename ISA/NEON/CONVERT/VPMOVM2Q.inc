// CONVERT/VPMOVM2Q.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VPMOVM2Q.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VPMOVM2Q: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVM2Q.inc"
x86_handler = "x86_vpmovm2q"
neon_lowering = "arm64_vpmovm2q"
lowering_kind = "arm64_documented_contract"

name = "VPMOVM2Q"
aliases = []
category = "avx512_convert"
feature = "avx512dq"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.F3.0F38.W1 28 /r", form = "VPMOVM2Q xmm1, k2", op_en = "A", feature = "avx512dq+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W1 28 /r", form = "VPMOVM2Q ymm1, k2", op_en = "A", feature = "avx512dq+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W1 28 /r", form = "VPMOVM2Q zmm1, k2", op_en = "A", feature = "avx512dq", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Move mask to qword vector: zero each qword element in the destination vector
except the most significant bit, which is set from the corresponding mask bit.
"""

handler = "x86_vpmovm2q"
jit_lowering = "arm64_vpmovm2q"
fallback = "zig_vpmovm2q"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVM2Q is an AVX512DQ mask-to-vector conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVM2Q.
"""

neon_assembly = """
// NEON lowering: VPMOVM2Q conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
