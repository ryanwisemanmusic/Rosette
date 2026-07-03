// ROTATE/VPRORVD.inc
// ARM64/NEON mirror generated from ISA/x86/ROTATE/VPRORVD.inc.
name = "VPRORVD"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROTATE/VPRORVD.inc"
x86_handler = "x86_vprorvd"
neon_lowering = "arm64_vprorvd"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.128.66.0F38.W0 14 /r", form = "VPRORVD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 14 /r", form = "VPRORVD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 14 /r", form = "VPRORVD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]
operand_encoding = { B = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Type E4 class exception conditions"]
semantic_general = "Variable bit rotate right of doubleword elements by per-element count."
handler = "x86_vprorvd"
jit_lowering = "arm64_vprorvd"
fallback = "zig_vprorvd"
neon_register_model = "VPRORVD is an AVX512F/VL SIMD rotate instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPRORVD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
