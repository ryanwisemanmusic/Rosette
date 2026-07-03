// VARIABLE/VPSRLVD.inc
// VPSRLVD — Variable Bit Shift Right Logical (Doubleword).

name = "VPSRLVD"
category = "shift"
feature = "AVX2"
element_type = "i32"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 45 /r", form = "VPSRLVD xmm1, xmm2, xmm3/m128", op_en = "A", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 45 /r", form = "VPSRLVD ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 45 /r", form = "VPSRLVD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 45 /r", form = "VPSRLVD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 45 /r", form = "VPSRLVD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

reads = ["SRC1", "SRC2"]
writes = ["DEST"]
flags_read = []
flags_written = []

semantic = """
(KL, VL) = (4, 128), (8, 256), (16, 512). For each dword: DEST[i+31:i] := ZeroExtend(SRC1[i+31:i] >> SRC2[i+31:i]) with broadcast support. If shift count > 31, result is 0.
"""

exceptions = ["VEX: Type 4 class exception conditions", "EVEX: Type E4 class exception conditions"]

handler = "x86_vpsrlvd"
jit_lowering = "arm64_neon_shift_right_logical"

neon_register_model = "VPSRLVD is an AVX2/AVX512F variable dword logical shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRLVD stub"
neon_notes = ["VPSRLVD logically shifts each dword right by a per-element variable count.", "ARM64: USHL for unsigned shift."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
