// DOWN_CONVERT/VPMOVUSWB.inc
// Source contract: VPMOVUSWB — Down convert 16-bit unsigned integers to packed unsigned bytes using unsigned saturation.

semantic = """
KL := VL/16
FOR j := 0 TO KL-1
    i := j * 8
    m := j * 16
    IF k1[j] OR *no writemask*
        THEN DEST[i+7:i] := SaturateUnsignedWordToByte(SRC[m+15:m])
        ELSE IF *zeroing* DEST[i+7:i] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL/2] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DOWN_CONVERT/VPMOVUSWB.inc"
x86_handler = "x86_vpmovuswb"
neon_lowering = "arm64_vpmovuswb"
lowering_kind = "neon_vector"

name = "VPMOVUSWB"
aliases = []
category = "simd_int_down_convert"
feature = "avx512bw"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 10 /r", form = "VPMOVUSWB xmm1/m64{k1}{z}, xmm2", op_en = "A", feature = "avx512vl+avx512bw", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 10 /r", form = "VPMOVUSWB xmm1/m128{k1}{z}, ymm2", op_en = "A", feature = "avx512vl+avx512bw", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 10 /r", form = "VPMOVUSWB ymm1/m256{k1}{z}, zmm2", op_en = "A", feature = "avx512bw", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-53, Type E6 Class Exception Conditions",
  "#UD if EVEX.vvvv != 1111B"
]

semantic_general = """
Down convert 16-bit unsigned integer elements from the source operand into packed unsigned bytes using unsigned saturation.
"""

handler = "x86_vpmovuswb"
jit_lowering = "arm64_vpmovuswb"
fallback = "zig_lane_loop_vpmovuswb"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVUSWB is an AVX512BW down-convert operation.
"""

neon_flag_model = """
No x86 flags modified by VPMOVUSWB.
"""

neon_assembly = """
// NEON lowering: VPMOVUSWB down-convert stub (simd_int_down_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
