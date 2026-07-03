// PAND/VPANDD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PAND/VPANDD.inc"
x86_handler = "x86_vpandd"
neon_lowering = "arm64_vpandd"
lowering_kind = "arm64_documented_contract"
name = "VPANDD"
aliases = []
category = "bitwise_logical"
feature = "AVX512F"
encodings = [
  { opcode = "EVEX.128.66.0F.W0 DB /r", form = "VPANDD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "EVEX" },
  { opcode = "EVEX.256.66.0F.W0 DB /r", form = "VPANDD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "EVEX" },
  { opcode = "EVEX.512.66.0F.W0 DB /r", form = "VPANDD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "EVEX" }
]
operand_encoding = { C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["EVEX: See Table 2-49, Type E4 Class Exception Conditions"]
semantic_general = "Bitwise AND of packed doubleword integers with masking and broadcast support."
handler = "x86_vpandd"
jit_lowering = "arm64_vpandd"
fallback = "zig_vpandd"
neon_register_model = "VPANDD is an x86 packed integer logical AND (dword). NEON lowering via bitwise AND with masking."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPANDD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
