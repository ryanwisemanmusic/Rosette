// LOGICAL_OR/VPORD.inc
// Source contract: VPORD — Bitwise Logical OR of Packed Doubleword Integers.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/VPORD.inc"
x86_handler = "x86_vpord"
neon_lowering = "arm64_vpord"
lowering_kind = "arm64_documented_contract"

name = "VPORD"
aliases = []
category = "simd_logical"
feature = "avx512f"

encodings = [
  { opcode = "EVEX.128.66.0F.W0 EB /r", form = "VPORD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "avx512vl,avx512f", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W0 EB /r", form = "VPORD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "avx512vl,avx512f", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W0 EB /r", form = "VPORD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"]
}

lanes = { dword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["EVEX-encoded instruction, see Table 2-49, Type E4 Class Exception Conditions."]

semantic_general = "Bitwise OR of packed doubleword integers with writemask and broadcast support."

handler = "x86_vpord"
jit_lowering = "arm64_vpord"
fallback = "zig_vpord"

neon_register_model = "VPORD is an AVX512F bitwise OR instruction."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPORD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
