// SHUFFLE/VPSHUFBITQMB.inc
// ARM64/NEON mirror generated from ISA/x86/SHUFFLE/VPSHUFBITQMB.inc.
name = "VPSHUFBITQMB"
category = "shuffle"
feature = "AVX512_BITALG"
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VPSHUFBITQMB.inc"
x86_handler = "x86_vpshufbitqmb"
neon_lowering = "arm64_vpshufbitqmb"
lowering_kind = "arm64_documented_contract"
aliases = []
encodings = [
  { opcode = "EVEX.128.66.0F38.W0 8F /r", form = "VPSHUFBITQMB k1{k2}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512_BITALG AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 8F /r", form = "VPSHUFBITQMB k1{k2}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512_BITALG AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 8F /r", form = "VPSHUFBITQMB k1{k2}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512_BITALG", vector_length = 512, encoding = "evex" }
]
operand_encoding = { A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["See Type E4NF class exception conditions"]
semantic_general = "Shuffle bits from quadword elements using byte indexes into mask register."
handler = "x86_vpshufbitqmb"
jit_lowering = "arm64_vpshufbitqmb"
fallback = "zig_vpshufbitqmb"
neon_register_model = "VPSHUFBITQMB is an AVX512_BITALG mask-output shuffle. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSHUFBITQMB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
