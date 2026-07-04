// DIV/VDIVSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/DIV/VDIVSH.inc.
// Source contract: VDIVSH — Divide Scalar FP16 Values.

semantic = """
xmm1.fp16[0] := SRC1.fp16[0] / SRC2.fp16[0]
SRC1[127:16] -> xmm1[127:16]
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DIV/VDIVSH.inc"
x86_handler = "x86_vdivsh"
neon_lowering = "arm64_vdivsh"
lowering_kind = "arm64_scalar"

name = "VDIVSH"
aliases = []
category = "simd_scalar_div"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 5E /r", form = "VDIVSH xmm1{k1}{z}, xmm2, xmm3/m16{er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Invalid"
]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Divide low FP16 value in xmm2 by low FP16 value in xmm3/m16, store in xmm1.
"""

handler = "x86_vdivsh"
jit_lowering = "arm64_vdivsh"
fallback = "zig_vdivsh"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VDIVSH is a scalar AVX512-FP16 divide.
"""

neon_flag_model = """
No x86 flags modified by VDIVSH.
"""

neon_assembly = """
// NEON lowering: VDIVSH divide stub (avx512_fp16_divide)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
