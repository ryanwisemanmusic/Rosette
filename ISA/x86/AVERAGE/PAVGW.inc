// AVERAGE/PAVGW.inc
// Source contract: PAVGW/VPAVGW — Average Packed Unsigned Word Integers.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "AVERAGE/PAVGW.inc"
x86_handler = "x86_pavgw"
neon_lowering = "arm64_pavgw"
lowering_kind = "arm64_documented_contract"

name = "PAVGW"
aliases = ["VPAVGW"]
category = "simd_average"
feature = "sse"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "NP 0F E3 /r", form = "PAVGW mm1, mm2/m64", op_en = "A", feature = "sse", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F E3 /r", form = "PAVGW xmm1, xmm2/m128", op_en = "A", feature = "sse2", vector_length = 0, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG E3 /r", form = "VPAVGW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "avx", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG E3 /r", form = "VPAVGW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "avx2", vector_length = 0, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG E3 /r", form = "VPAVGW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "avx512vl+avx512bw", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG E3 /r", form = "VPAVGW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "avx512vl+avx512bw", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG E3 /r", form = "VPAVGW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "avx512bw", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r, w)", "ModRM:r/m (r)"]
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { mmx = 1, xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX-encoded instruction, see Table 2-21, Type 4 Class Exception Conditions.",
  "EVEX-encoded instruction, see Exceptions Type E4.nb in Table 2-49, Type E4 Class Exception Conditions."
]

semantic_general = """
Computes (SRC1 + SRC2 + 1) >> 1 for each packed unsigned word element with rounding.
"""

handler = "x86_pavgw"
jit_lowering = "arm64_pavgw"
fallback = "zig_pavgw"

neon_register_model = """
PAVGW is an SSE/AVX/AVX512 packed unsigned word average operation.
"""

neon_flag_model = """
PAVGW does not modify flags.
"""

neon_assembly = """
// NEON lowering: PAVGW stub (average packed unsigned words)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
