// COMPUTE/VP2INTERSECT.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/VP2INTERSECT.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VP2INTERSECT: preserve the operation and form-specific semantic blocks.
Category: simd_int.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/VP2INTERSECT.inc"
x86_handler = "x86_vp2intersect"
neon_lowering = "arm64_no_neon_equivalent"
lowering_kind = "unsupported"

name = "VP2INTERSECT"
aliases = ["VP2INTERSECTD", "VP2INTERSECTQ"]
category = "simd_int"
feature = "AVX512F"
element_type = "u32_u64"

encodings = [
  { opcode = "EVEX.NDS.128.F2.0F38.W0 68 /r", form = "VP2INTERSECTD k1+1, xmm2, xmm3/m128/m32bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.256.F2.0F38.W0 68 /r", form = "VP2INTERSECTD k1+1, ymm2, ymm3/m256/m32bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.512.F2.0F38.W0 68 /r", form = "VP2INTERSECTD k1+1, zmm2, zmm3/m512/m32bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.128.F2.0F38.W1 68 /r", form = "VP2INTERSECTQ k1+1, xmm2, xmm3/m128/m64bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.256.F2.0F38.W1 68 /r", form = "VP2INTERSECTQ k1+1, ymm2, ymm3/m256/m64bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.512.F2.0F38.W1 68 /r", form = "VP2INTERSECTQ k1+1, zmm2, zmm3/m512/m64bcst", op_en = "A", feature = "AVX512F", writes_mask = true }
]

flags_written = []

handler = "x86_vp2intersect"
jit_lowering = "arm64_no_neon_equivalent"

neon_register_model = """
No NEON equivalent. VP2INTERSECT writes a pair of mask registers; ARM64 NEON has no direct match.
"""

neon_flag_model = """
No NEON equivalent; must trap or fall back to software emulation.
"""

neon_assembly = """
// No NEON equivalent. emulated via software routine.
bl rosette_vp2intersect_emulated
"""

neon_notes = [
  "VP2INTERSECT has no direct ARM64 NEON equivalent (zen=0 in NEON).",
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "Emulation via scratch register pair and software fallback."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
