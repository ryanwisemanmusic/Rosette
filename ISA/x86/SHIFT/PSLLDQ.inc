// SHIFT/PSLLDQ.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSLLDQ.inc"
x86_handler = "x86_pslldq"
neon_lowering = "arm64_pslldq"
lowering_kind = "arm64_documented_contract"

name = "PSLLDQ"
category = "packed_shift"
feature = "SSE2_AVX_AVX512BW"
element_type = "integer"
element_size = 128

encodings = [
  { opcode = "66 0F 73 /7 ib", form = "PSLLDQ xmm1, imm8", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG 73 /7 ib", form = "VPSLLDQ xmm1, xmm2, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 73 /7 ib", form = "VPSLLDQ ymm1, ymm2, imm8", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG 73 /7 ib", form = "VPSLLDQ xmm1, xmm2/m128, imm8", op_en = "C", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 73 /7 ib", form = "VPSLLDQ ymm1, ymm2/m256, imm8", op_en = "C", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 73 /7 ib", form = "VPSLLDQ zmm1, zmm2/m512, imm8", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (r,w)", "imm8"],
  B = ["VEX.vvvv (w)", "ModRM:r/m (r)", "imm8"],
  C = ["EVEX.vvvv (w)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
PSLLDQ/VPSLLDQ: Shift packed double quadword left by imm8 bytes while shifting in 0s. If count > 15, result is all 0s. Operates on 128-bit lanes.
"""

handler = "x86_pslldq"
jit_lowering = "arm64_pslldq"
fallback = "zig_lane_loop"

neon_register_model = "x86 XMM/YMM/ZMM registers mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: EXT or shift-left by bytes"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
