// SCALE/VSCALEFPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFPD.inc.
// Source contract: VSCALEFPD — Packed Float64 Scale.

semantic = """
KL := VL/64
FOR j := 0 TO KL-1
    IF k1[j] OR *no writemask*
        THEN DEST.f64[j] := SRC1.f64[j] * 2^floor(SRC2.f64[j])
        ELSE IF *zeroing* DEST.f64[j] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFPD.inc"
x86_handler = "x86_vscalefpd"
neon_lowering = "arm64_vscalefpd"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFPD"
aliases = []
category = "simd_arithmetic"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 2C /r", form = "VSCALEFPD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "A", feature = "avx512f_avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 2C /r", form = "VSCALEFPD ymm1{k1}{z}, ymm2, xmm3/m256/m64bcst", op_en = "A", feature = "avx512f_avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 2C /r", form = "VSCALEFPD zmm1{k1}{z}, zmm2, xmm3/m512/m64bcst{er}", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
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
Scale packed float64 values in xmm2 by powers of two computed from the corresponding elements in xmm3/m128/m64bcst.
"""

handler = "x86_vscalefpd"
jit_lowering = "arm64_vscalefpd"
fallback = "zig_lane_loop"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VSCALEFPD is a packed AVX512F float64 scale.
"""

neon_flag_model = """
No x86 flags modified by VSCALEFPD.
"""

neon_assembly = """
// NEON lowering: VSCALEFPD packed scale stub (simd_arithmetic)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
