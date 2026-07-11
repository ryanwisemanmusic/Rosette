// DOWN_CONVERT/VPMOVUSDB.inc
// Source contract: VPMOVUSDB — Down convert 32-bit unsigned integers to packed unsigned bytes using unsigned saturation.

semantic = """
KL := VL/32
FOR j := 0 TO KL-1
    i := j * 8
    m := j * 32
    IF k1[j] OR *no writemask*
        THEN DEST[i+7:i] := SaturateUnsignedDoubleWordToByte(SRC[m+31:m])
        ELSE IF *zeroing* DEST[i+7:i] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL/4] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DOWN_CONVERT/VPMOVUSDB.inc"
x86_handler = "x86_vpmovusdb"
neon_lowering = "arm64_vpmovusdb"
lowering_kind = "neon_vector"

name = "VPMOVUSDB"
aliases = []
category = "simd_int_down_convert"
feature = "avx512f"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 11 /r", form = "VPMOVUSDB xmm1/m32{k1}{z}, xmm2", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 11 /r", form = "VPMOVUSDB xmm1/m64{k1}{z}, ymm2", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 11 /r", form = "VPMOVUSDB xmm1/m128{k1}{z}, zmm2", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-53, Type E6 Class Exception Conditions",
  "#UD if EVEX.vvvv != 1111B"
]

semantic_general = """
Down convert 32-bit unsigned integer elements from the source operand into packed unsigned bytes using unsigned saturation.
"""

handler = "x86_vpmovusdb"
jit_lowering = "arm64_vpmovusdb"
fallback = "zig_lane_loop_vpmovusdb"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVUSDB is an AVX512F down-convert operation.
"""

neon_flag_model = """
No x86 flags modified by VPMOVUSDB.
"""

neon_assembly = """
// NEON lowering: VPMOVUSDB down-convert stub (simd_int_down_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
