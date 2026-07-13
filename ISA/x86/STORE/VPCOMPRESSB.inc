// STORE/VPCOMPRESSB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/VPCOMPRESSB.inc"
x86_handler = "x86_vpcompressb"
neon_lowering = "arm64_vpcompressb"
lowering_kind = "arm64_documented_contract"

name = "VPCOMPRESSB"
category = "compress_store"
feature = "AVX512_VBMI2"
element_type = "integer"
element_size = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 63 /r", form = "VPCOMPRESSB m128{k1}, xmm1", op_en = "A", feature = "AVX512_VBMI2 AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.128.66.0F38.W0 63 /r", form = "VPCOMPRESSB xmm1{k1}{z}, xmm2", op_en = "B", feature = "AVX512_VBMI2 AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 63 /r", form = "VPCOMPRESSB m256{k1}, ymm1", op_en = "A", feature = "AVX512_VBMI2 AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 63 /r", form = "VPCOMPRESSB ymm1{k1}{z}, ymm2", op_en = "B", feature = "AVX512_VBMI2 AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 63 /r", form = "VPCOMPRESSB m512{k1}, zmm1", op_en = "A", feature = "AVX512_VBMI2", vector_length = 512, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 63 /r", form = "VPCOMPRESSB zmm1{k1}{z}, zmm2", op_en = "B", feature = "AVX512_VBMI2", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"],
  B = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
VPCOMPRESSB: Compress (store) packed byte values from source to destination using writemask k1. Contiguous vector written to destination.
"""

handler = "x86_vpcompressb"
jit_lowering = "arm64_vpcompressb"
fallback = "zig_lane_loop"

neon_register_model = "x86 ZMM/YMM/XMM registers mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: compress + store bytes"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
