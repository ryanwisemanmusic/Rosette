// FULL_PERMUTE/VPERMI2PS.inc
// ARM64/NEON mirror generated from ISA/x86/FULL_PERMUTE/VPERMI2PS.inc.
name = "VPERMI2PS"
category = "simd_permute"
feature = "AVX512F+AVX512VL"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FULL_PERMUTE/VPERMI2PS.inc"
x86_handler = "x86_vpermI2ps"
neon_lowering = "arm64_vpermI2ps"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.128.66.0F38.W0 77 /r", form = "VPERMI2PS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 77 /r", form = "VPERMI2PS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 77 /r", form = "VPERMI2PS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]
operand_encoding = { B = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Table 2-50, Type E4NF Class Exception Conditions."]
semantic_general = "Full permute of single-precision float values from two tables, overwriting the index."
handler = "x86_vpermI2ps"
jit_lowering = "arm64_vpermI2ps"
fallback = "zig_vpermI2ps"
neon_register_model = "VPERMI2PS is an AVX512F/VL full permute instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPERMI2PS stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
