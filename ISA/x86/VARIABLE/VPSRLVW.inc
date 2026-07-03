// VARIABLE/VPSRLVW.inc
// VPSRLVW — Variable Bit Shift Right Logical (Word).

name = "VPSRLVW"
category = "shift"
feature = "AVX512BW"
element_type = "i16"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 10 /r", form = "VPSRLVW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "B", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 10 /r", form = "VPSRLVW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "B", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 10 /r", form = "VPSRLVW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "B", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = { B = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)" } }

reads = ["SRC1", "SRC2"]
writes = ["DEST"]
flags_read = []
flags_written = []

semantic = """
(KL, VL) = (8, 128), (16, 256), (32, 512). For each word: DEST[i+15:i] := ZeroExtend(SRC1[i+15:i] >> SRC2[i+15:i]). If shift count > 15, result is 0. Writemask k1 controls update per element.
"""

exceptions = ["See Type E4.nb class exception conditions"]

handler = "x86_vpsrlvw"
jit_lowering = "arm64_neon_shift_right_logical"

neon_register_model = "VPSRLVW is an AVX512BW variable word logical shift. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSRLVW stub"
neon_notes = ["VPSRLVW logically shifts each word right by a per-element variable count.", "ARM64: USHL for unsigned shift."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
