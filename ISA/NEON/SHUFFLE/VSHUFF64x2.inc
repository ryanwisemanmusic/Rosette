// SHUFFLE/VSHUFF64x2.inc
// ARM64/NEON mirror generated from ISA/x86/SHUFFLE/VSHUFF64x2.inc.
name = "VSHUFF64x2"
category = "shuffle"
feature = "AVX512F+AVX512VL"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VSHUFF64x2.inc"
x86_handler = "x86_vshuff64x2"
neon_lowering = "arm64_vshuff64x2"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.256.66.0F3A.W1 23 /r ib", form = "VSHUFF64x2 ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "A", feature = "AVX512F AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W1 23 /r ib", form = "VSHUFF64x2 zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]
operand_encoding = { A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#UD if EVEX.L'L = 0", "See Type E4NF class exception conditions"]
semantic_general = "Shuffle 128-bit packed double-precision floating-point lanes selected by imm8."
handler = "x86_vshuff64x2"
jit_lowering = "arm64_vshuff64x2"
fallback = "zig_vshuff64x2"
neon_register_model = "VSHUFF64x2 is an AVX512F/VL lane shuffle instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VSHUFF64x2 stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
