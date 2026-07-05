// SCALE/VSCALEFSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFSD.inc.
// Source contract: VSCALEFSD — Scalar Float64 Scale.

semantic = """
DEST.f64[0] := SRC1.f64[0] * 2^floor(SRC2.f64[0])
DEST.f64[1] := SRC1.f64[1]
DEST[MAXVL-1:128] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFSD.inc"
x86_handler = "x86_vscalefsd"
neon_lowering = "arm64_vscalefsd"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFSD"
aliases = []
category = "simd_arithmetic_scalar"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W1 2D /r", form = "VSCALEFSD xmm1{k1}{z}, xmm2, xmm3/m64{er}", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = [
  "Overflow",
  "Underflow",
  "Invalid",
  "Precision",
  "Denormal"
]
other_exceptions = [
  "EVEX-encoded instructions, see Table 2-46, Type E2 Class Exception Conditions"
]

semantic_general = """
Scale low float64 value in xmm2 by power of two computed from low float64 value in xmm3/m64, store in xmm1.
"""

handler = "x86_vscalefsd"
jit_lowering = "arm64_vscalefsd"
fallback = "zig_vscalefsd"

neon_register_model = """
x86 XMM mapped to ARM64 Vn. VSCALEFSD is a scalar AVX512F float64 scale.
"""

neon_flag_model = """
No x86 flags modified by VSCALEFSD.
"""

neon_assembly = """
// NEON lowering: VSCALEFSD scalar scale stub (avx512f_scale)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
