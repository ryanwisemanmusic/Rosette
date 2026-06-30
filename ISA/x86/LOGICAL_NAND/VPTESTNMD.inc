// LOGICAL_NAND/VPTESTNMD.inc
// Source contract: VPTESTNMD — Logical NAND of Packed Doubleword Integers and Set Mask.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_NAND/VPTESTNMD.inc"
x86_handler = "x86_vptestnmd"
neon_lowering = "arm64_vptestnmd"
lowering_kind = "arm64_documented_contract"

name = "VPTESTNMD"
aliases = []
category = "mask_generation_logical_nand"
feature = "avx512f"

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 27 /r", form = "VPTESTNMD k2 {k1}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "avx512vl,avx512f", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 27 /r", form = "VPTESTNMD k2 {k1}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "avx512vl,avx512f", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 27 /r", form = "VPTESTNMD k2 {k1}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  B = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"]
}

lanes = { dword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "See Table 2-49, Type E4 Class Exception Conditions."
]

semantic_general = """
Bitwise NAND of packed doubleword integers in SRC1 and SRC2; set mask k2 to reflect zero/non-zero status of each element result.
Supports broadcast from 32-bit memory location.
"""

handler = "x86_vptestnmd"
jit_lowering = "arm64_vptestnmd"
fallback = "zig_vptestnmd"

neon_register_model = """
VPTESTNMD is an AVX512 mask generation instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: VPTESTNMD stub (dword NAND to mask)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
