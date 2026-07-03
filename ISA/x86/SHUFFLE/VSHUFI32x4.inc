// SHUFFLE/VSHUFI32x4.inc
// VSHUFI32x4 — Shuffle Packed Doubleword Values at 128-Bit Granularity (AVX512F/VL).

name = "VSHUFI32x4"
category = "shuffle"
feature = "AVX512F+AVX512VL"
element_type = "i32"

encodings = [
  { opcode = "EVEX.256.66.0F3A.W0 43 /r ib", form = "VSHUFI32x4 ymm1{k1}{z}, ymm2, ymm3/m256/m32bcst, imm8", op_en = "A", feature = "AVX512F AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W0 43 /r ib", form = "VSHUFI32x4 zmm1{k1}{z}, zmm2, zmm3/m512/m32bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" } }

reads = ["SRC1", "SRC2", "imm8"]
writes = ["DEST"]
flags_read = []
flags_written = []

semantic = """
Select2(SRC, control): TMP := SRC[127:0] if control[0]=0 else SRC[255:128]. Select4(SRC, control): select 128-bit lane by control bits. For VL=256: DEST[127:0]=Select2(SRC1,imm8[0]); DEST[255:128]=Select2(SRC2,imm8[1]). For VL=512: DEST[127:0]=Select4(SRC1,imm8[1:0]); DEST[255:128]=Select4(SRC1,imm8[3:2]); DEST[383:256]=Select4(SRC2,imm8[5:4]); DEST[511:384]=Select4(SRC2,imm8[7:6]). Writemask granularity 32-bit.
"""

exceptions = ["#UD if EVEX.L'L = 0 (128-bit not supported)", "See Type E4NF class exception conditions"]

handler = "x86_vshufi32x4"
jit_lowering = "arm64_neon_lane_shuffle"

neon_register_model = "VSHUFI32x4 is an AVX512F/VL lane shuffle instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VSHUFI32x4 stub"
neon_notes = ["VSHUFI32x4 shuffles 128-bit lanes of doubleword integer values.", "EVEX.L'L must be 0 (128-bit) is #UD; 256-bit and 512-bit only."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
