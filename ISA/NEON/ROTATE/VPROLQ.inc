// ROTATE/VPROLQ.inc
// ARM64/NEON mirror generated from ISA/x86/ROTATE/VPROLQ.inc.
name = "VPROLQ"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROTATE/VPROLQ.inc"
x86_handler = "x86_vprolq"
neon_lowering = "arm64_vprolq"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.128.66.0F.W1 72 /1 ib", form = "VPROLQ xmm1 {k1}{z}, xmm2/m128/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W1 72 /1 ib", form = "VPROLQ ymm1 {k1}{z}, ymm2/m256/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W1 72 /1 ib", form = "VPROLQ zmm1 {k1}{z}, zmm2/m512/m64bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]
operand_encoding = { A = ["VEX.vvvv (w)", "ModRM:r/m (R)", "imm8"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Type E4 class exception conditions"]
semantic_general = "Bit rotate left of quadword elements by immediate count."
handler = "x86_vprolq"
jit_lowering = "arm64_vprolq"
fallback = "zig_vprolq"
neon_register_model = "VPROLQ is an AVX512F/VL SIMD rotate instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLQ stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
