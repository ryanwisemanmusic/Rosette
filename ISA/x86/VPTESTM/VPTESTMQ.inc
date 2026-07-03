// VPTESTM/VPTESTMQ.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VPTESTM/VPTESTMQ.inc"
x86_handler = "x86_vptestmq"
neon_lowering = "arm64_vptestmq"
lowering_kind = "arm64_documented_contract"
name = "VPTESTMQ"
aliases = []
category = "test_and_set_mask"
feature = "AVX512F"
encodings = [
  { opcode = "EVEX.128.66.0F38.W1 27 /r", form = "VPTESTMQ k2 {k1}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "EVEX" },
  { opcode = "EVEX.256.66.0F38.W1 27 /r", form = "VPTESTMQ k2 {k1}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "EVEX" },
  { opcode = "EVEX.512.66.0F38.W1 27 /r", form = "VPTESTMQ k2 {k1}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "EVEX" }
]
operand_encoding = { B = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["EVEX: See Table 2-49, Type E4 Class Exception Conditions"]
semantic_general = "Bitwise AND of packed quadword integers, set mask if result element is non-zero. Supports broadcast."
handler = "x86_vptestmq"
jit_lowering = "arm64_vptestmq"
fallback = "zig_vptestmq"
neon_register_model = "VPTESTMQ is an x86 mask-test operation. NEON lowering via AND+mask."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPTESTMQ stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
