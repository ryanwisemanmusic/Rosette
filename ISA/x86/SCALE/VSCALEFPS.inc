// SCALE/VSCALEFPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFPS.inc.
// Source contract: VSCALEFPS — Packed Float32 Scale.

semantic = """
KL := VL/32
FOR j := 0 TO KL-1
    IF k1[j] OR *no writemask*
        THEN DEST.f32[j] := SRC1.f32[j] * 2^floor(SRC2.f32[j])
        ELSE IF *zeroing* DEST.f32[j] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFPS.inc"
x86_handler = "x86_vscalefps"
neon_lowering = "arm64_vscalefps"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFPS"
aliases = []
category = "simd_arithmetic"
feature = "avx512f"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 2C /r", form = "VSCALEFPS xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "A", feature = "avx512f_avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 2C /r", form = "VSCALEFPS ymm1{k1}{z}, ymm2, xmm3/m256/m32bcst", op_en = "A", feature = "avx512f_avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 2C /r", form = "VSCALEFPS zmm1{k1}{z}, zmm2, xmm3/m512/m32bcst{er}", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
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
Scale packed float32 values in xmm2 by powers of two computed from the corresponding elements in xmm3/m128/m32bcst.
"""

handler = "x86_vscalefps"
jit_lowering = "arm64_vscalefps"
fallback = "zig_lane_loop"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VSCALEFPS is a packed AVX512F float32 scale.
"""

neon_flag_model = """
No x86 flags modified by VSCALEFPS.
"""

neon_assembly = """
// NEON lowering: VSCALEFPS packed scale stub (simd_arithmetic)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
