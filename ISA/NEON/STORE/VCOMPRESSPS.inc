// STORE/VCOMPRESSPS.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/VCOMPRESSPS.inc"
x86_handler = "x86_vcompressps"
neon_lowering = "arm64_vcompressps"
lowering_kind = "neon_documented_contract"

name = "VCOMPRESSPS"
category = "compress_store"
feature = "SSE2_AVX_AVX512"
element_type = "f32"
legacy_width = 128

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 8A /r", form = "VCOMPRESSPS xmm1/m128{k1}{z}, xmm2", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 8A /r", form = "VCOMPRESSPS ymm1/m256{k1}{z}, ymm2", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 8A /r", form = "VCOMPRESSPS zmm1/m512{k1}{z}, zmm2", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
VCOMPRESSPS: Compress store single precision.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_vcompressps"
jit_lowering = "arm64_vcompressps"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: compress store"
neon_notes = ["ARM64/NEON lowering mirror for x86 VCOMPRESSPS."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
