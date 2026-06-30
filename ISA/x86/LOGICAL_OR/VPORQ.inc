// LOGICAL_OR/VPORQ.inc
// Source contract: VPORQ — Bitwise Logical OR of Packed Quadword Integers.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/VPORQ.inc"
x86_handler = "x86_vporq"
neon_lowering = "arm64_vporq"
lowering_kind = "arm64_documented_contract"

name = "VPORQ"
aliases = []
category = "simd_logical"
feature = "avx512f"

encodings = [
  { opcode = "EVEX.128.66.0F.W1 EB /r", form = "VPORQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "avx512vl,avx512f", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W1 EB /r", form = "VPORQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "avx512vl,avx512f", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W1 EB /r", form = "VPORQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"]
}

lanes = { qword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["EVEX-encoded instruction, see Table 2-49, Type E4 Class Exception Conditions."]

semantic_general = "Bitwise OR of packed quadword integers with writemask and broadcast support."

handler = "x86_vporq"
jit_lowering = "arm64_vporq"
fallback = "zig_vporq"

neon_register_model = "VPORQ is an AVX512F bitwise OR instruction."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPORQ stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
