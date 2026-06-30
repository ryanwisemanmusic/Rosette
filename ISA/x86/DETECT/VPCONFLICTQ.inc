// DETECT/VPCONFLICTQ.inc
// Source contract: VPCONFLICTQ — Detect Conflicts Within a Vector of Packed Qword Values.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DETECT/VPCONFLICTQ.inc"
x86_handler = "x86_vpconflictq"
neon_lowering = "arm64_vpconflictq"
lowering_kind = "arm64_documented_contract"

name = "VPCONFLICTQ"
aliases = []
category = "vector_conflict_detection"
feature = "avx512cd"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 C4 /r", form = "VPCONFLICTQ xmm1 {k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512vl,avx512cd", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 C4 /r", form = "VPCONFLICTQ ymm1 {k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512vl,avx512cd", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 C4 /r", form = "VPCONFLICTQ zmm1 {k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512cd", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { qword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-50, Type E4NF Class Exception Conditions."
]

semantic_general = """
Test each qword element of the source operand for equality with all other elements closer to the least significant element.
Each element's comparison results form a bit vector, zero extended and written to destination according to writemask.
"""

handler = "x86_vpconflictq"
jit_lowering = "arm64_vpconflictq"
fallback = "zig_vpconflictq"

neon_register_model = """
VPCONFLICTQ is an AVX512CD conflict detection instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: VPCONFLICTQ stub (AVX512 qword conflict detection)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
