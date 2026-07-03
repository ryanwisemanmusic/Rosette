// ROTATE/VPROLVD.inc
// ARM64/NEON mirror generated from ISA/x86/ROTATE/VPROLVD.inc.
name = "VPROLVD"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROTATE/VPROLVD.inc"
x86_handler = "x86_vprolvd"
neon_lowering = "arm64_vprolvd"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.128.66.0F38.W0 15 /r", form = "VPROLVD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 15 /r", form = "VPROLVD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 15 /r", form = "VPROLVD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]
operand_encoding = { B = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Type E4 class exception conditions"]
semantic_general = "Variable bit rotate left of doubleword elements by per-element count."
handler = "x86_vprolvd"
jit_lowering = "arm64_vprolvd"
fallback = "zig_vprolvd"
neon_register_model = "VPROLVD is an AVX512F/VL SIMD rotate instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLVD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
