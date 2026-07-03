// ROTATE/VPRORQ.inc
// VPRORQ — Bit Rotate Right (quadword immediate, AVX512F/VL).

name = "VPRORQ"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
element_type = "simd_qword"

encodings = [
  { opcode = "EVEX.128.66.0F.W1 72 /0 ib", form = "VPRORQ xmm1 {k1}{z}, xmm2/m128/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W1 72 /0 ib", form = "VPRORQ ymm1 {k1}{z}, ymm2/m256/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W1 72 /0 ib", form = "VPRORQ zmm1 {k1}{z}, zmm2/m512/m64bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
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
RIGHT_ROTATE_QWORDS(SRC, COUNT_SRC): COUNT := COUNT_SRC MOD 64; DEST[63:0] := (SRC >> COUNT) | (SRC << (64 - COUNT));
(KL, VL) = (2, 128), (4, 256), (8, 512); For each qword element: DEST := RIGHT_ROTATE_QWORDS(SRC, imm8) with writemask.
"""

exceptions = ["See Type E4 class exception conditions (EVEX-encoded)"]

handler = "x86_vprorq"
jit_lowering = "arm64_neon_ror_shift"

neon_register_model = "VPRORQ is an AVX512F/VL SIMD rotate-right instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPRORQ stub"
neon_notes = ["VPRORQ rotates each 64-bit qword element right by imm8 modulo 64.", "ARM64 lowering uses NEON shift primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
