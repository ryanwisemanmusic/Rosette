// SCALE/VSCALEFPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/VSCALEFPH.inc.
// Source contract: VSCALEFPH — Packed FP16 Scale.

semantic = """
KL := VL/16
FOR j := 0 TO KL-1
    IF k1[j] OR *no writemask*
        THEN DEST.fp16[j] := SRC1.fp16[j] * 2^floor(SRC2.fp16[j])
        ELSE IF *zeroing* DEST.fp16[j] := 0
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/VSCALEFPH.inc"
x86_handler = "x86_vscalefph"
neon_lowering = "arm64_vscalefph"
lowering_kind = "arm64_documented_contract"

name = "VSCALEFPH"
aliases = []
category = "simd_arithmetic"
feature = "avx512_fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP6.W0 2C /r", form = "VSCALEFPH xmm1{k1}{z}, xmm2, xmm3/m128/m16bcst", op_en = "A", feature = "avx512_fp16_avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.MAP6.W0 2C /r", form = "VSCALEFPH ymm1{k1}{z}, ymm2, xmm3/m256/m16bcst", op_en = "A", feature = "avx512_fp16_avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.MAP6.W0 2C /r", form = "VSCALEFPH zmm1{k1}{z}, ymm2, zmm3/m512/m16bcst{er}", op_en = "A", feature = "avx512_fp16", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = [
  "Invalid",
  "Underflow",
  "Overflow",
  "Precision",
  "Denormal",
  "Zero"
]
other_exceptions = [
  "EVEX-encoded instructions, see Table 2-46, Type E2 Class Exception Conditions"
]

semantic_general = """
Scale packed FP16 values from the first source operand by powers of two computed from the corresponding elements in the second source operand.
"""

handler = "x86_vscalefph"
jit_lowering = "arm64_vscalefph"
fallback = "zig_lane_loop_f16"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VSCALEFPH is a packed AVX512-FP16 scale.
"""

neon_flag_model = """
No x86 flags modified by VSCALEFPH.
"""

neon_assembly = """
// NEON lowering: VSCALEFPH packed scale stub (simd_arithmetic)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
