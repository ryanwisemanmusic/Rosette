// ROTATE/VPROLVD.inc
// VPROLVD — Variable Bit Rotate Left (doubleword, AVX512F/VL).

name = "VPROLVD"
category = "bit_rotate"
feature = "AVX512VL+AVX512F"
element_type = "simd_dword"

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 15 /r", form = "VPROLVD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 15 /r", form = "VPROLVD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 15 /r", form = "VPROLVD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
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
LEFT_ROTATE_DWORDS(SRC, COUNT_SRC): COUNT := COUNT_SRC MOD 32; DEST[31:0] := (SRC << COUNT) | (SRC >> (32 - COUNT));
(KL, VL) = (4, 128), (8, 256), (16, 512); For each dword element: DEST := LEFT_ROTATE_DWORDS(SRC1[i+31:i], SRC2[i+31:i]) with writemask.
"""

exceptions = ["See Type E4 class exception conditions (EVEX-encoded)"]

handler = "x86_vprolvd"
jit_lowering = "arm64_neon_ror_shift"

neon_register_model = "VPROLVD is an AVX512F/VL variable SIMD rotate-left instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPROLVD stub"
neon_notes = ["VPROLVD rotates each 32-bit dword element left by per-element count in SRC2 modulo 32.", "ARM64 lowering uses NEON shift primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
