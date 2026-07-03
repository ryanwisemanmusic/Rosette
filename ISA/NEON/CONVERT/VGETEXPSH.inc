// CONVERT/VGETEXPSH.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VGETEXPSH.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VGETEXPSH: preserve the operation and form-specific semantic blocks.
Category: avx512_fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPSH.inc"
x86_handler = "x86_vgetexpsh"
neon_lowering = "arm64_vgetexpsh"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPSH"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LIG.66.MAP5.W0 43 /r", form = "VGETEXPSH xmm1{k1}{z}, xmm2/m16, {er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "evex" }
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
Extract exponent of the low half-precision FP16 element as FP16.
The exponent is extracted as a biased FP16 value.
"""

handler = "x86_vgetexpsh"
jit_lowering = "arm64_vgetexpsh"
fallback = "zig_vgetexpsh"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VGETEXPSH is an AVX512-FP16 scalar extract-exponent conversion.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPSH.
"""

neon_assembly = """
// NEON lowering: VGETEXPSH conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
