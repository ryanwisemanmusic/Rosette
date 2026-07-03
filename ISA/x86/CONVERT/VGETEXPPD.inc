// CONVERT/VGETEXPPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VGETEXPPD.inc.
// Source contract: VGETEXPPD — Convert Exponents of Packed DP FP Values to DP FP Values.

semantic = """
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no writemask*
        THEN DEST[i+63:i] := ConvertExpDPFP(SRC[i+63:i])
        ELSE *zeroing-masking* DEST[i+63:i] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPPD.inc"
x86_handler = "x86_vgetexppd"
neon_lowering = "arm64_vgetexppd"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPPD"
aliases = []
category = "simd_convert"
feature = "avx512f_avx512vl"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 42 /r", form = "VGETEXPPD xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512vl_avx512f", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 42 /r", form = "VGETEXPPD ymm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512vl_avx512f", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 42 /r", form = "VGETEXPPD zmm1{k1}{z}, zmm2/m512/m64bcst{sae}", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = [
  "Invalid",
  "Denormal"
]
other_exceptions = [
  "See Table 2-46, Type E2 Class Exception Conditions",
  "#UD if EVEX.vvvv != 1111B"
]

semantic_general = """
Extract unbiased exponent from normalized DP FP values, or convert denormal input to negative integer, then convert to DP FP.
"""

handler = "x86_vgetexppd"
jit_lowering = "arm64_vgetexppd"
fallback = "zig_lane_loop_getexp_f64"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VGETEXPPD is a packed AVX512 exponent extraction.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPPD.
"""

neon_assembly = """
// NEON lowering: VGETEXPPD exponent extraction stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
