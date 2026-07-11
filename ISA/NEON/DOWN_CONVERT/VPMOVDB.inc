// DOWN_CONVERT/VPMOVDB.inc
// ARM64/NEON mirror generated from ISA/x86/DOWN_CONVERT/VPMOVDB.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VPMOVDB: Down convert 32-bit integer elements from the source operand into packed bytes using truncation. Category: avx512_down_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DOWN_CONVERT/VPMOVDB.inc"
x86_handler = "x86_vpmovdb"
neon_lowering = "arm64_vpmovdb"
lowering_kind = "neon_vector"

name = "VPMOVDB"
aliases = []
category = "avx512_down_convert"
feature = "avx512f"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 31 /r", form = "VPMOVDB {xmm1/m32}{k1}{z}, {xmm2}", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 31 /r", form = "VPMOVDB {xmm1/m64}{k1}{z}, {ymm2}", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 31 /r", form = "VPMOVDB {xmm1/m128}{k1}{z}, {zmm2}", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Down convert 32-bit integer elements from the source operand into packed bytes using truncation.
"""

handler = "x86_vpmovdb"
jit_lowering = "arm64_vpmovdb"
fallback = "zig_vpmovdb"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVDB is an AVX512F down-convert operation.
"""

neon_flag_model = """
No x86 flags modified by VPMOVDB.
"""

neon_assembly = """
// NEON lowering: VPMOVDB down-convert stub (avx512_down_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
