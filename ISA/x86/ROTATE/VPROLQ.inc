// ROTATE/VPROLQ.inc
// VPROLQ — Bit Rotate Left (quadword immediate, AVX512F/VL).

name = "VPROLQ"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
element_type = "simd_qword"

encodings = [
  { opcode = "EVEX.128.66.0F.W1 72 /1 ib", form = "VPROLQ xmm1 {k1}{z}, xmm2/m128/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W1 72 /1 ib", form = "VPROLQ ymm1 {k1}{z}, ymm2/m256/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W1 72 /1 ib", form = "VPROLQ zmm1 {k1}{z}, zmm2/m512/m64bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = { operand1 = "VEX.vvvv (w)", operand2 = "ModRM:r/m (R)", operand3 = "imm8", operand4 = "N/A" }
}

reads = ["SRC1", "imm8"]
writes = ["DEST"]
flags_read = []
flags_written = []
implicit_operands = []

semantic = """
LEFT_ROTATE_QWORDS(SRC, COUNT_SRC): COUNT := COUNT_SRC MOD 64; DEST[63:0] := (SRC << COUNT) | (SRC >> (64 - COUNT));
(KL, VL) = (2, 128), (4, 256), (8, 512); For each qword element: DEST := LEFT_ROTATE_QWORDS(SRC, imm8) with writemask.
"""

exceptions = ["See Type E4 class exception conditions (EVEX-encoded)"]

handler = "x86_vprolq"
jit_lowering = "arm64_neon_ror_shift"

neon_register_model = "VPROLQ is an AVX512F/VL SIMD rotate-left instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLQ stub"
neon_notes = ["VPROLQ rotates each 64-bit qword element left by imm8 modulo 64.", "ARM64 lowering uses NEON shift/ror primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
