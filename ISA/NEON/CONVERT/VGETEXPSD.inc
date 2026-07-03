// CONVERT/VGETEXPSD.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VGETEXPSD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VGETEXPSD: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPSD.inc"
x86_handler = "x86_vgetexpsd"
neon_lowering = "arm64_vgetexpsd"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPSD"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LIG.66.0F38.W1 43 /r", form = "VGETEXPSD xmm1{k1}{z}, xmm2/m64, {er}", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact", "Overflow", "Underflow"]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Extract exponent of the low double-precision FP64 element as FP64.
The exponent is extracted as a biased FP64 value.
"""

handler = "x86_vgetexpsd"
jit_lowering = "arm64_vgetexpsd"
fallback = "zig_vgetexpsd"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VGETEXPSD is an AVX512 scalar extract-exponent conversion.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPSD.
"""

neon_assembly = """
// NEON lowering: VGETEXPSD conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
