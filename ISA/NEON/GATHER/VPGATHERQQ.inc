// GATHER/VPGATHERQQ.inc
// ARM64/NEON mirror generated from ISA/x86/GATHER/VPGATHERQQ.inc.
// Source contract: VPGATHERQQ — avx512_gather.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VPGATHERQQ.inc"
x86_handler = "x86_vpgatherqq"
neon_lowering = "arm64_vpgatherqq"
lowering_kind = "arm64_documented_contract"

name = "VPGATHERQQ"
aliases = []
category = "avx512_gather"
feature = "avx512f"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F38.W1 91 /r", form = "VPGATHERQQ xmm1, vm32x, xmm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38.W1 91 /r", form = "VPGATHERQQ ymm1, vm32x, ymm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.128.66.0F38.W1 91 /vsib", form = "VPGATHERQQ xmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.66.0F38.W1 91 /vsib", form = "VPGATHERQQ ymm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.66.0F38.W1 91 /vsib", form = "VPGATHERQQ zmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Qword Integers with Signed Qword Indices.
"""

handler = "x86_vpgatherqq"
jit_lowering = "arm64_vpgatherqq"
fallback = "zig_vpgatherqq"

neon_register_model = """
VPGATHERQQ is a gather instruction.
"""

neon_flag_model = """
VPGATHERQQ does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPGATHERQQ stub (avx512_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
