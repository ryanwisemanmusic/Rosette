// DETECT/VPCONFLICTD.inc
// Source contract: VPCONFLICTD — Detect Conflicts Within a Vector of Packed Dword Values.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DETECT/VPCONFLICTD.inc"
x86_handler = "x86_vpconflictd"
neon_lowering = "arm64_vpconflictd"
lowering_kind = "arm64_documented_contract"

name = "VPCONFLICTD"
aliases = []
category = "vector_conflict_detection"
feature = "avx512cd"

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 C4 /r", form = "VPCONFLICTD xmm1 {k1}{z}, xmm2/m128/m32bcst", op_en = "A", feature = "avx512vl,avx512cd", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 C4 /r", form = "VPCONFLICTD ymm1 {k1}{z}, ymm2/m256/m32bcst", op_en = "A", feature = "avx512vl,avx512cd", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 C4 /r", form = "VPCONFLICTD zmm1 {k1}{z}, zmm2/m512/m32bcst", op_en = "A", feature = "avx512cd", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { dword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-50, Type E4NF Class Exception Conditions."
]

semantic_general = """
Test each dword element of the source operand for equality with all other elements closer to the least significant element.
Each element's comparison results form a bit vector, zero extended and written to destination according to writemask.
"""

handler = "x86_vpconflictd"
jit_lowering = "arm64_vpconflictd"
fallback = "zig_vpconflictd"

neon_register_model = """
VPCONFLICTD is an AVX512CD conflict detection instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: VPCONFLICTD stub (AVX512 dword conflict detection)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
