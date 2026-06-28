// GATHER/VPGATHERQD.inc
// ARM64/NEON mirror generated from ISA/x86/GATHER/VPGATHERQD.inc.
// Source contract: VPGATHERQD — avx512_gather.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "GATHER/VPGATHERQD.inc"
x86_handler = "x86_vpgatherqd"
neon_lowering = "arm64_vpgatherqd"
lowering_kind = "arm64_documented_contract"

name = "VPGATHERQD"
aliases = []
category = "avx512_gather"
feature = "avx512f"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 91 /r", form = "VPGATHERQD xmm1, vm32x, xmm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38.W0 91 /r", form = "VPGATHERQD ymm1, vm32x, ymm2", op_en = "A", feature = "avx2", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.128.66.0F38.W0 91 /vsib", form = "VPGATHERQD xmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.66.0F38.W0 91 /vsib", form = "VPGATHERQD ymm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.66.0F38.W0 91 /vsib", form = "VPGATHERQD zmm1 {k1}, vm32x", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Gather Packed Dword Integers with Signed Qword Indices.
"""

handler = "x86_vpgatherqd"
jit_lowering = "arm64_vpgatherqd"
fallback = "zig_vpgatherqd"

neon_register_model = """
VPGATHERQD is a gather instruction.
"""

neon_flag_model = """
VPGATHERQD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPGATHERQD stub (avx512_gather)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
