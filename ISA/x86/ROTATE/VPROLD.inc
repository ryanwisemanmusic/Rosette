// ROTATE/VPROLD.inc
// VPROLD — Bit Rotate Left (doubleword immediate, AVX512F/VL).

name = "VPROLD"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
element_type = "simd_dword"

encodings = [
  { opcode = "EVEX.128.66.0F.W0 72 /1 ib", form = "VPROLD xmm1 {k1}{z}, xmm2/m128/m32bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W0 72 /1 ib", form = "VPROLD ymm1 {k1}{z}, ymm2/m256/m32bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W0 72 /1 ib", form = "VPROLD zmm1 {k1}{z}, zmm2/m512/m32bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
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
LEFT_ROTATE_DWORDS(SRC, COUNT_SRC): COUNT := COUNT_SRC MOD 32; DEST[31:0] := (SRC << COUNT) | (SRC >> (32 - COUNT));
(KL, VL) = (4, 128), (8, 256), (16, 512); For each dword element: DEST := LEFT_ROTATE_DWORDS(SRC, imm8) with writemask.
"""

exceptions = ["See Type E4 class exception conditions (EVEX-encoded)"]

handler = "x86_vprold"
jit_lowering = "arm64_neon_ror_shift"

neon_register_model = "VPROLD is an AVX512F/VL SIMD rotate-left instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLD stub"
neon_notes = ["VPROLD rotates each 32-bit dword element left by imm8 modulo 32.", "ARM64 lowering uses NEON shift/ror primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
