// VARIABLE/VPSRAVQ.inc
// VPSRAVQ — Variable Bit Shift Right Arithmetic (Quadword).

name = "VPSRAVQ"
category = "shift"
feature = "AVX512F"
element_type = "i64"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 46 /r", form = "VPSRAVQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 46 /r", form = "VPSRAVQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 46 /r", form = "VPSRAVQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = { C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

reads = ["SRC1", "SRC2"]
writes = ["DEST"]
flags_read = []
flags_written = []

semantic = """
(KL, VL) = (2, 128), (4, 256), (8, 512). For each qword: COUNT := SRC2[i+5:i]; IF COUNT < 64 THEN DEST[i+63:i] := SignExtend(SRC1[i+63:i] >> COUNT) ELSE fill with sign bit. Broadcast and writemask support.
"""

exceptions = ["See Type E4 class exception conditions"]

handler = "x86_vpsravq"
jit_lowering = "arm64_neon_shift_right_arith"

neon_register_model = "VPSRAVQ is an AVX512F variable qword arithmetic shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRAVQ stub"
neon_notes = ["VPSRAVQ arithmetically shifts each qword right by a per-element variable count.", "ARM64: SSHR for arithmetic shift."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
