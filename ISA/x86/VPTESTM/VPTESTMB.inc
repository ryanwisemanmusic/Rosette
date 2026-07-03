// VPTESTM/VPTESTMB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "VPTESTM/VPTESTMB.inc"
x86_handler = "x86_vptestmb"
neon_lowering = "arm64_vptestmb"
lowering_kind = "arm64_documented_contract"
name = "VPTESTMB"
aliases = []
category = "test_and_set_mask"
feature = "AVX512BW"
encodings = [
  { opcode = "EVEX.128.66.0F38.W0 26 /r", form = "VPTESTMB k2 {k1}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "EVEX" },
  { opcode = "EVEX.256.66.0F38.W0 26 /r", form = "VPTESTMB k2 {k1}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "EVEX" },
  { opcode = "EVEX.512.66.0F38.W0 26 /r", form = "VPTESTMB k2 {k1}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512BW", vector_length = 512, encoding = "EVEX" }
]
operand_encoding = { A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "N/A"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["EVEX: See Type E4.nb in Table 2-49"]
semantic_general = "Bitwise AND of packed byte integers, set mask if result element is non-zero. Zeroing-masking only."
handler = "x86_vptestmb"
jit_lowering = "arm64_vptestmb"
fallback = "zig_vptestmb"
neon_register_model = "VPTESTMB is an x86 mask-test operation. NEON lowering via AND+mask."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPTESTMB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
