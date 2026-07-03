// CONVERT/VGETEXPSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VGETEXPSD.inc.
// Source contract: VGETEXPSD — Convert Exponents of Scalar DP FP Value to DP FP Value.

semantic = """
IF k1[0] OR *no writemask*
    THEN DEST[63:0] := ConvertExpDPFP(SRC2[63:0])
    ELSE *zeroing-masking* DEST[63:0] := 0
FI
DEST[127:64] := SRC1[127:64]
DEST[MAXVL-1:128] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPSD.inc"
x86_handler = "x86_vgetexpsd"
neon_lowering = "arm64_vgetexpsd"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPSD"
aliases = []
category = "simd_convert"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W1 43 /r", form = "VGETEXPSD xmm1{k1}{z}, xmm2, xmm3/m64{sae}", op_en = "A", feature = "avx512f", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Invalid",
  "Denormal"
]
other_exceptions = [
  "See Table 2-47, Type E3 Class Exception Conditions"
]

semantic_general = """
Extract unbiased exponent from low scalar DP FP element, or convert denormal input to negative integer, then convert to DP FP.
"""

handler = "x86_vgetexpsd"
jit_lowering = "arm64_vgetexpsd"
fallback = "zig_scalar_getexp_f64"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VGETEXPSD is a scalar AVX512 exponent extraction.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPSD.
"""

neon_assembly = """
// NEON lowering: VGETEXPSD scalar exponent extraction stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
