// FULL_PERMUTE/VPERMI2PS.inc
// VPERMI2PS — Full Permute of Singles From Two Tables Overwriting the Index (AVX512F/VL).

name = "VPERMI2PS"
category = "simd_permute"
feature = "AVX512F+AVX512VL"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 77 /r", form = "VPERMI2PS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 77 /r", form = "VPERMI2PS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 77 /r", form = "VPERMI2PS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  B = { operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
}

reads = ["SRC1", "SRC2", "SRC3"]
writes = ["DEST"]
flags_read = []
flags_written = []
implicit_operands = []

semantic = """
VPERMI2PS: PERMI2(INDEX, TABLE1, TABLE2): each element of INDEX selects a 32-bit element from TABLE1 (if INDEX element is even/within first table range) or TABLE2 (if odd/offset). The index element is replaced with the selected value. (KL, VL) = (4, 128), (8, 256), (16, 512); for each 32-bit element: DEST[i] := (TABLE1 or TABLE2)[INDEX[i][4:0]] selected by INDEX[i][4] (0=TABLE1, 1=TABLE2) with writemask. Zeroing-masking via EVEX.z.
"""

exceptions = ["See Table 2-50, Type E4NF Class Exception Conditions."]

handler = "x86_vpermI2ps"
jit_lowering = "arm64_vpermI2ps"

neon_register_model = "VPERMI2PS is an AVX512F/VL full permute instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPERMI2PS stub"
neon_notes = ["VPERMI2PS permutes 32-bit float elements from two tables using index values in the destination.", "Broadcast from 32-bit memory is supported via /m32bcst."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
