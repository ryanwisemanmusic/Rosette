// CONVERT/VGETEXPPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VGETEXPPH.inc.
// Source contract: VGETEXPPH — Convert Exponents of Packed FP16 Values to FP16 Values.

semantic = """
KL := VL/16
FOR i := 0 TO KL-1
    IF k1[i] OR *no writemask*
        THEN DEST.fp16[i] := getexp_fp16(SRC.fp16[i])
        ELSE IF *zeroing* DEST.fp16[i] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPPH.inc"
x86_handler = "x86_vgetexpph"
neon_lowering = "arm64_vgetexpph"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPPH"
aliases = []
category = "simd_convert"
feature = "avx512_fp16_avx512vl"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP6.W0 42 /r", form = "VGETEXPPH xmm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512_fp16_avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.MAP6.W0 42 /r", form = "VGETEXPPH ymm1{k1}{z}, ymm2/m256/m16bcst", op_en = "A", feature = "avx512_fp16_avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.MAP6.W0 42 /r", form = "VGETEXPPH zmm1{k1}{z}, zmm2/m512/m16bcst{sae}", op_en = "A", feature = "avx512_fp16", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = [
  "Invalid",
  "Denormal"
]
other_exceptions = [
  "EVEX-encoded instructions, see Table 2-46, Type E2 Class Exception Conditions"
]

semantic_general = """
Extract unbiased exponent from normalized FP16 values, or convert denormal input to negative integer, then convert to FP16.
"""

handler = "x86_vgetexpph"
jit_lowering = "arm64_vgetexpph"
fallback = "zig_lane_loop_getexp_f16"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VGETEXPPH is a packed AVX512-FP16 exponent extraction.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPPH.
"""

neon_assembly = """
// NEON lowering: VGETEXPPH exponent extraction stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
