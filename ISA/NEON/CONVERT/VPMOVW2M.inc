// CONVERT/VPMOVW2M.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VPMOVW2M.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VPMOVW2M: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVW2M.inc"
x86_handler = "x86_vpmovw2m"
neon_lowering = "arm64_vpmovw2m"
lowering_kind = "arm64_documented_contract"

name = "VPMOVW2M"
aliases = []
category = "avx512_convert"
feature = "avx512bw"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 29 /r", form = "VPMOVW2M k1, xmm2", op_en = "A", feature = "avx512bw+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 29 /r", form = "VPMOVW2M k1, ymm2", op_en = "A", feature = "avx512bw+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 29 /r", form = "VPMOVW2M k1, zmm2", op_en = "A", feature = "avx512bw", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Move word mask: copy the most significant bit of each word element in the
source vector to the corresponding bit in the destination mask register.
"""

handler = "x86_vpmovw2m"
jit_lowering = "arm64_vpmovw2m"
fallback = "zig_vpmovw2m"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVW2M is an AVX512BW vector-to-mask conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVW2M.
"""

neon_assembly = """
// NEON lowering: VPMOVW2M conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
