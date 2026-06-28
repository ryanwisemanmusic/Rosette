// GATHER/VPGATHERDQ.inc
// ARM64/NEON mirror generated from ISA/x86/GATHER/VPGATHERDQ.inc.
// Source contract: VPGATHERDQ — avx512_gather.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VPGATHERDQ.inc"
x86_handler = "x86_vpgatherdq"
neon_lowering = "arm64_vpgatherdq"
lowering_kind = "arm64_documented_contract"

name = "VPGATHERDQ"
aliases = []
category = "avx512_gather"
feature = "avx512f"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F38.W1 90 /r", form = "VPGATHERDQ xmm1, vm32x, xmm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38.W1 90 /r", form = "VPGATHERDQ ymm1, vm32x, ymm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.128.66.0F38.W1 90 /vsib", form = "VPGATHERDQ xmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.66.0F38.W1 90 /vsib", form = "VPGATHERDQ ymm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.66.0F38.W1 90 /vsib", form = "VPGATHERDQ zmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Qword Integers with Signed Dword Indices.
"""

handler = "x86_vpgatherdq"
jit_lowering = "arm64_vpgatherdq"
fallback = "zig_vpgatherdq"

neon_register_model = """
VPGATHERDQ is a gather instruction.
"""

neon_flag_model = """
VPGATHERDQ does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPGATHERDQ stub (avx512_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
