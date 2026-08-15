// SHIFT/PSRAW.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSRAW.inc"
x86_handler = "x86_psraw"
neon_lowering = "arm64_psraw"
lowering_kind = "neon_documented_contract"

name = "PSRAW"
category = "packed_shift"
feature = "MMX_SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NP 0F E1 /r", form = "PSRAW mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F E1 /r", form = "PSRAW xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "NP 0F 71 /4 ib", form = "PSRAW mm, imm8", op_en = "B", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F 71 /4 ib", form = "PSRAW xmm1, imm8", op_en = "B", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG E1 /r", form = "VPSRAW xmm1, xmm2, xmm3/m128", op_en = "C", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.128.66.0F.WIG 71 /4 ib", form = "VPSRAW xmm1, xmm2, imm8", op_en = "D", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG E1 /r", form = "VPSRAW ymm1, ymm2, xmm3/m128", op_en = "C", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 71 /4 ib", form = "VPSRAW ymm1, ymm2, imm8", op_en = "D", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG E1 /r", form = "VPSRAW xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "G", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG E1 /r", form = "VPSRAW ymm1{k1}{z}, ymm2, xmm3/m128", op_en = "G", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG E1 /r", form = "VPSRAW zmm1{k1}{z}, zmm2, xmm3/m128", op_en = "G", feature = "AVX512BW", vector_length = 512, encoding = "evex" },
  { opcode = "EVEX.128.66.0F.WIG 71 /4 ib", form = "VPSRAW xmm1{k1}{z}, xmm2/m128, imm8", op_en = "E", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 71 /4 ib", form = "VPSRAW ymm1{k1}{z}, ymm2/m256, imm8", op_en = "E", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 71 /4 ib", form = "VPSRAW zmm1{k1}{z}, zmm2/m512, imm8", op_en = "E", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
PSRAW: Shift packed words right arithmetic by count.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_psraw"
jit_lowering = "arm64_psraw"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: SSHR or immediate arithmetic shift right"
neon_notes = ["ARM64/NEON lowering mirror for x86 PSRAW."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
