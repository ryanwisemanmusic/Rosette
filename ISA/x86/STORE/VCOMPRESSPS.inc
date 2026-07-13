// STORE/VCOMPRESSPS.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/VCOMPRESSPS.inc"
x86_handler = "x86_vcompressps"
neon_lowering = "arm64_vcompressps"
lowering_kind = "arm64_documented_contract"

name = "VCOMPRESSPS"
category = "compress_store"
feature = "AVX512F"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 8A /r", form = "VCOMPRESSPS xmm1/m128{k1}{z}, xmm2", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 8A /r", form = "VCOMPRESSPS ymm1/m256{k1}{z}, ymm2", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 8A /r", form = "VCOMPRESSPS zmm1/m512{k1}{z}, zmm2", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
VCOMPRESSPS: Compress (store) packed single precision float values from source to destination using writemask k1. Contiguous vector written starting from low element.
"""

handler = "x86_vcompressps"
jit_lowering = "arm64_vcompressps"
fallback = "zig_lane_loop"

neon_register_model = "x86 ZMM/YMM/XMM registers mapped to ARM64 SIMD vector registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: compress + store"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
