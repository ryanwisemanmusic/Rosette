// CONVERT/VGETEXPSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VGETEXPSH.inc.
// Source contract: VGETEXPSH — Convert Exponents of Scalar FP16 Values to FP16 Values.

semantic = """
IF k1[0] OR *no writemask*
    THEN DEST.fp16[0] := getexp_fp16(SRC2.fp16[0])
    ELSE IF *zeroing* DEST.fp16[0] := 0
FI
DEST[127:16] := SRC1[127:16]
DEST[MAXVL-1:128] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPSH.inc"
x86_handler = "x86_vgetexpsh"
neon_lowering = "arm64_vgetexpsh"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPSH"
aliases = []
category = "simd_convert"
feature = "avx512_fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.66.MAP6.W0 43 /r", form = "VGETEXPSH xmm1{k1}{z}, xmm2, xmm3/m16{sae}", op_en = "A", feature = "avx512_fp16", vector_length = 128, encoding = "evex" }
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
  "EVEX-encoded instructions, see Table 2-47, Type E3 Class Exception Conditions"
]

semantic_general = """
Extract unbiased exponent from low scalar FP16 element, or convert denormal input to negative integer, then convert to FP16.
"""

handler = "x86_vgetexpsh"
jit_lowering = "arm64_vgetexpsh"
fallback = "zig_scalar_getexp_f16"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VGETEXPSH is a scalar AVX512-FP16 exponent extraction.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPSH.
"""

neon_assembly = """
// NEON lowering: VGETEXPSH scalar FP16 exponent extraction stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
