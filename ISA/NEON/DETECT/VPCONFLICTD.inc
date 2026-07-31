// Mirror: DETECT/VPCONFLICTD.inc

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
  { opcode = "EVEX.128.66.0F38.W0 C4 /r", form = "VPCONFLICTD xmm1 {k1}{z}, xmm2/m128/m32bcst", op_en = "A", vector_length = 128 },
  { opcode = "EVEX.256.66.0F38.W0 C4 /r", form = "VPCONFLICTD ymm1 {k1}{z}, ymm2/m256/m32bcst", op_en = "A", vector_length = 256 },
  { opcode = "EVEX.512.66.0F38.W0 C4 /r", form = "VPCONFLICTD zmm1 {k1}{z}, zmm2/m512/m32bcst", op_en = "A", vector_length = 512 }
]


neon_register_model = """
VPCONFLICTD is an AVX512CD conflict detection instruction. No ARM64 NEON equivalent; handled via documented contract.
"""
neon_flag_model = """
None.
"""
neon_assembly = """
// NEON lowering: VPCONFLICTD stub (AVX512 dword conflict detection)
"""
semantic_general = """
Test each dword element of the source operand for equality with all other elements closer to the least significant element.
Each element's comparison results form a bit vector, zero extended and written to destination according to writemask.
"""
flags_written = []

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
