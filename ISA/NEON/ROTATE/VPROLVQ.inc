// ROTATE/VPROLVQ.inc
// ARM64/NEON mirror generated from ISA/x86/ROTATE/VPROLVQ.inc.
name = "VPROLVQ"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROTATE/VPROLVQ.inc"
x86_handler = "x86_vprolvq"
neon_lowering = "arm64_vprolvq"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.128.66.0F38.W1 15 /r", form = "VPROLVQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 15 /r", form = "VPROLVQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 15 /r", form = "VPROLVQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]
operand_encoding = { B = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Type E4 class exception conditions"]
semantic_general = "Variable bit rotate left of quadword elements by per-element count."
handler = "x86_vprolvq"
jit_lowering = "arm64_vprolvq"
fallback = "zig_vprolvq"
neon_register_model = "VPROLVQ is an AVX512F/VL SIMD rotate instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLVQ stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
