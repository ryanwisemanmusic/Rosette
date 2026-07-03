// VARIABLE/VPSLLVQ.inc
// VPSLLVQ — Variable Bit Shift Left Logical (Quadword).

name = "VPSLLVQ"
category = "shift"
feature = "AVX2"
element_type = "i64"

encodings = [
  { opcode = "VEX.128.66.0F38.W1 47 /r", form = "VPSLLVQ xmm1, xmm2, xmm3/m128", op_en = "A", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W1 47 /r", form = "VPSLLVQ ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W1 47 /r", form = "VPSLLVQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 47 /r", form = "VPSLLVQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 47 /r", form = "VPSLLVQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

reads = ["SRC1", "SRC2"]
writes = ["DEST"]
flags_read = []
flags_written = []

semantic = """
(KL, VL) = (2, 128), (4, 256), (8, 512). For each qword: DEST[i+63:i] := ZeroExtend(SRC1[i+63:i] << SRC2[i+63:i]) with broadcast support. If shift count > 63, result is 0.
"""

exceptions = ["VEX: Type 4 class exception conditions", "EVEX: Type E4 class exception conditions"]

handler = "x86_vpsllvq"
jit_lowering = "arm64_neon_shift_left"

neon_register_model = "VPSLLVQ is an AVX2/AVX512F variable qword shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSLLVQ stub"
neon_notes = ["VPSLLVQ shifts each qword element by a per-element variable count from SRC2.", "ARM64: SSHL/USHL for variable shifts."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
