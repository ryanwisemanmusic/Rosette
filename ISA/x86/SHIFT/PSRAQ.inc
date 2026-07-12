// SHIFT/PSRAQ.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSRAQ.inc"
x86_handler = "x86_psraq"
neon_lowering = "arm64_psraq"
lowering_kind = "arm64_documented_contract"

name = "PSRAQ"
category = "packed_shift"
feature = "AVX512F"
element_type = "integer"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F.W1 E2 /r", form = "VPSRAQ xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "G", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W1 E2 /r", form = "VPSRAQ ymm1{k1}{z}, ymm2, xmm3/m128", op_en = "G", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W1 E2 /r", form = "VPSRAQ zmm1{k1}{z}, zmm2, xmm3/m128", op_en = "G", feature = "AVX512F", vector_length = 512, encoding = "evex" },
  { opcode = "EVEX.128.66.0F.W1 72 /4 ib", form = "VPSRAQ xmm1{k1}{z}, xmm2/m128/m64bcst, imm8", op_en = "F", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W1 72 /4 ib", form = "VPSRAQ ymm1{k1}{z}, ymm2/m256/m64bcst, imm8", op_en = "F", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W1 72 /4 ib", form = "VPSRAQ zmm1{k1}{z}, zmm2/m512/m64bcst, imm8", op_en = "F", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  F = ["EVEX.vvvv (w)", "ModRM:r/m (r)", "imm8"],
  G = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
VPSRAQ: Shift packed quadwords right arithmetic by count. If count > 63, each element filled with sign bit.
"""

handler = "x86_psraq"
jit_lowering = "arm64_psraq"
fallback = "zig_lane_loop"

neon_register_model = "x86 ZMM/YMM/XMM registers mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: SSHR #imm or SRSHR"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
