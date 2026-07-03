// VARIABLE/VPSRAVD.inc
// VPSRAVD — Variable Bit Shift Right Arithmetic (Doubleword).

name = "VPSRAVD"
category = "shift"
feature = "AVX2"
element_type = "i32"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 46 /r", form = "VPSRAVD xmm1, xmm2, xmm3/m128", op_en = "A", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 46 /r", form = "VPSRAVD ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 46 /r", form = "VPSRAVD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 46 /r", form = "VPSRAVD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 46 /r", form = "VPSRAVD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)" }, C = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

reads = ["SRC1", "SRC2"]
writes = ["DEST"]
flags_read = []
flags_written = []

semantic = """
(KL, VL) = (4, 128), (8, 256), (16, 512). For each dword: COUNT := SRC2[i+4:i]; IF COUNT < 32 THEN DEST[i+31:i] := SignExtend(SRC1[i+31:i] >> COUNT) ELSE fill with sign bit. Broadcast and writemask support.
"""

exceptions = ["VEX: Type 4 class exception conditions", "EVEX: Type E4 class exception conditions"]

handler = "x86_vpsravd"
jit_lowering = "arm64_neon_shift_right_arith"

neon_register_model = "VPSRAVD is an AVX2/AVX512F variable dword arithmetic shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRAVD stub"
neon_notes = ["VPSRAVD arithmetically shifts each dword right by a per-element variable count.", "ARM64: SSHR for arithmetic shift."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
