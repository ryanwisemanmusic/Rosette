// SCALE/VSCALEFSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFSH.inc.
// Source contract: VSCALEFSH — Scalar FP16 Scale.

semantic = """
DEST.fp16[0] := SRC1.fp16[0] * 2^floor(SRC2.fp16[0])
DEST[127:16] := SRC1[127:16]
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFSH.inc"
x86_handler = "x86_vscalefsh"
neon_lowering = "arm64_vscalefsh"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFSH"
aliases = []
category = "simd_arithmetic_scalar"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.66.MAP6.W0 2D /r", form = "VSCALEFSH xmm1{k1}{z}, xmm2, xmm3/m16{er}", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "evex" }
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
Scale low FP16 value in xmm2 by power of two computed from low FP16 value in xmm3/m16, store in xmm1.
"""

handler = "x86_vscalefsh"
jit_lowering = "arm64_vscalefsh"
fallback = "zig_vscalefsh"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VSCALEFSH is a scalar AVX512-FP16 scale.
"""

neon_flag_model = """
No x86 flags modified by VSCALEFSH.
"""

neon_assembly = """
// NEON lowering: VSCALEFSH scalar scale stub (avx512_fp16_scale)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
