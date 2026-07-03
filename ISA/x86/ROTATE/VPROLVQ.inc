// ROTATE/VPROLVQ.inc
// VPROLVQ — Variable Bit Rotate Left (quadword, AVX512F/VL).

name = "VPROLVQ"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
element_type = "simd_qword"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 15 /r", form = "VPROLVQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 15 /r", form = "VPROLVQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 15 /r", form = "VPROLVQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  B = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
}

reads = ["SRC1", "SRC2"]
writes = ["DEST"]
flags_read = []
flags_written = []
implicit_operands = []

semantic = """
LEFT_ROTATE_QWORDS(SRC, COUNT_SRC): COUNT := COUNT_SRC MOD 64; DEST[63:0] := (SRC << COUNT) | (SRC >> (64 - COUNT));
(KL, VL) = (2, 128), (4, 256), (8, 512); For each qword element: DEST := LEFT_ROTATE_QWORDS(SRC1[i+63:i], SRC2[i+63:i]) with writemask.
"""

exceptions = ["See Type E4 class exception conditions (EVEX-encoded)"]

handler = "x86_vprolvq"
jit_lowering = "arm64_neon_ror_shift"

neon_register_model = "VPROLVQ is an AVX512F/VL variable SIMD rotate-left instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLVQ stub"
neon_notes = ["VPROLVQ rotates each 64-bit qword element left by per-element count in SRC2 modulo 64.", "ARM64 lowering uses NEON shift primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
