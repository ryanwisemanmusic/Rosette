// SHIFT/PSRLD.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHIFT/PSRLD.inc"
x86_handler = "x86_psrld"
neon_lowering = "arm64_psrld"
lowering_kind = "neon_documented_contract"

name = "PSRLD"
category = "packed_shift"
feature = "MMX_SSE2_AVX_AVX512"
element_type = "integer"
legacy_width = 128

encodings = [
  { opcode = "NP 0F D2 /r", form = "PSRLD mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F D2 /r", form = "PSRLD xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "NP 0F 72 /2 ib", form = "PSRLD mm, imm8", op_en = "B", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F 72 /2 ib", form = "PSRLD xmm1, imm8", op_en = "B", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG D2 /r", form = "VPSRLD xmm1, xmm2, xmm3/m128", op_en = "C", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.128.66.0F.WIG 72 /2 ib", form = "VPSRLD xmm1, xmm2, imm8", op_en = "D", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG D2 /r", form = "VPSRLD ymm1, ymm2, xmm3/m128", op_en = "C", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 72 /2 ib", form = "VPSRLD ymm1, ymm2, imm8", op_en = "D", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.W0 D2 /r", form = "VPSRLD xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "G", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W0 D2 /r", form = "VPSRLD ymm1{k1}{z}, ymm2, xmm3/m128", op_en = "G", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W0 D2 /r", form = "VPSRLD zmm1{k1}{z}, zmm2, xmm3/m128", op_en = "G", feature = "AVX512F", vector_length = 512, encoding = "evex" },
  { opcode = "EVEX.128.66.0F.W0 72 /2 ib", form = "VPSRLD xmm1{k1}{z}, xmm2/m128/m32bcst, imm8", op_en = "F", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W0 72 /2 ib", form = "VPSRLD ymm1{k1}{z}, ymm2/m256/m32bcst, imm8", op_en = "F", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W0 72 /2 ib", form = "VPSRLD zmm1{k1}{z}, zmm2/m512/m32bcst, imm8", op_en = "F", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_general = """
PSRLD: Shift packed doublewords right logical by count.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_psrld"
jit_lowering = "arm64_psrld"

neon_register_model = "x86 SIMD registers mapped to ARM64 vectors."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: USHR or immediate logical shift right"
neon_notes = ["ARM64/NEON lowering mirror for x86 PSRLD."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
