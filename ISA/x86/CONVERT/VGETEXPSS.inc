// CONVERT/VGETEXPSS.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VGETEXPSS.inc.
// Source contract: VGETEXPSS — Convert Exponents of Scalar SP FP Value to SP FP Value.

semantic = """
IF k1[0] OR *no writemask*
    THEN DEST[31:0] := ConvertExpSPFP(SRC2[31:0])
    ELSE *zeroing-masking* DEST[31:0] := 0
FI
DEST[127:32] := SRC1[127:32]
DEST[MAXVL-1:128] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPSS.inc"
x86_handler = "x86_vgetexpss"
neon_lowering = "arm64_vgetexpss"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPSS"
aliases = []
category = "simd_convert"
feature = "avx512f"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W0 43 /r", form = "VGETEXPSS xmm1{k1}{z}, xmm2, xmm3/m32{sae}", op_en = "A", feature = "avx512f", vector_length = 128, encoding = "evex" }
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
Extract unbiased exponent from low scalar SP FP element, or convert denormal input to negative integer, then convert to SP FP.
"""

handler = "x86_vgetexpss"
jit_lowering = "arm64_vgetexpss"
fallback = "zig_scalar_getexp_f32"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VGETEXPSS is a scalar AVX512 exponent extraction.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPSS.
"""

neon_assembly = """
// NEON lowering: VGETEXPSS scalar SP exponent extraction stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
