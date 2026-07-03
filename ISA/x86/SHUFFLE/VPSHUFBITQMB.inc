// SHUFFLE/VPSHUFBITQMB.inc
// VPSHUFBITQMB — Shuffle Bits From Quadword Elements Using Byte Indexes Into Mask (AVX512_BITALG).

name = "VPSHUFBITQMB"
category = "shuffle"
feature = "AVX512_BITALG"
element_type = "mask"

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 8F /r", form = "VPSHUFBITQMB k1{k2}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512_BITALG AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 8F /r", form = "VPSHUFBITQMB k1{k2}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512_BITALG AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 8F /r", form = "VPSHUFBITQMB k1{k2}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512_BITALG", vector_length = 512, encoding = "evex" }
]

operand_encoding = { A = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" } }

reads = ["SRC1", "SRC2"]
writes = ["k1"]
flags_read = []
flags_written = []

semantic = """
(KL, VL) = (16, 128), (32, 256), (64, 512). For each qword i and byte j: m = SRC2.qword[i].byte[j] & 0x3F; k1[i*8+j] = SRC1.qword[i].bit[m]. Zeroing writemask via k2.
"""

exceptions = ["See Type E4NF class exception conditions"]

handler = "x86_vpshufbitqmb"
jit_lowering = "arm64_neon_bit_shuffle"

neon_register_model = "VPSHUFBITQMB is an AVX512_BITALG mask-output shuffle instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPSHUFBITQMB stub"
neon_notes = ["VPSHUFBITQMB gathers bits from source using 6-bit control per byte element.", "ARM64 lowering uses NEON bit-selection primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
