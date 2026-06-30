// LOGICAL_NAND/VPTESTNMB.inc
// Source contract: VPTESTNMB — Logical NAND of Packed Byte Integers and Set Mask.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_NAND/VPTESTNMB.inc"
x86_handler = "x86_vptestnmb"
neon_lowering = "arm64_vptestnmb"
lowering_kind = "arm64_documented_contract"

name = "VPTESTNMB"
aliases = []
category = "mask_generation_logical_nand"
feature = "avx512bw"

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 26 /r", form = "VPTESTNMB k2 {k1}, xmm2, xmm3/m128", op_en = "A", feature = "avx512vl,avx512bw", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 26 /r", form = "VPTESTNMB k2 {k1}, ymm2, ymm3/m256", op_en = "A", feature = "avx512vl,avx512bw", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 26 /r", form = "VPTESTNMB k2 {k1}, zmm2, zmm3/m512", op_en = "A", feature = "avx512f,avx512bw", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"]
}

lanes = { byte = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "See Exceptions Type E4.nb in Table 2-49, Type E4 Class Exception Conditions."
]

semantic_general = """
Bitwise NAND of packed byte integers in SRC1 and SRC2; set mask k2 to reflect zero/non-zero status of each element result.
DEST[j] := (SRC1[i+7:i] BITWISE AND SRC2[i+7:i] == 0) ? 1 : 0
"""

handler = "x86_vptestnmb"
jit_lowering = "arm64_vptestnmb"
fallback = "zig_vptestnmb"

neon_register_model = """
VPTESTNMB is an AVX512 mask generation instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: VPTESTNMB stub (byte NAND to mask)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
