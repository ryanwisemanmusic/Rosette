// BLEND/VBLENDMPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/BLEND/VBLENDMPS.inc.
// Source contract: VBLENDMPS — Blend Float32 Vectors Using an OpMask Control.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VBLENDMPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_mask_blend.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BLEND/VBLENDMPS.inc"
x86_handler = "x86_vblendmps"
neon_lowering = "arm64_neon_vblendmps"
lowering_kind = "neon_vector"

name = "VBLENDMPS"
aliases = []
category = "simd_mask_blend"
feature = "AVX512F_AVX512VL"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 65 /r", form = "VBLENDMPS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 65 /r", form = "VBLENDMPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 65 /r", form = "VBLENDMPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-49, \"Type E4 Class Exception Conditions.\""
]

semantic_evex_128 = """
(KL, VL) = (4, 128)
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no controlmask*
        THEN
            IF (EVEX.b = 1) AND (SRC2 *is memory*)
                THEN DEST[i+31:i] := SRC2[31:0]
                ELSE DEST[i+31:i] := SRC2[i+31:i]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+31:i] := SRC1[i+31:i]
                ELSE DEST[i+31:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_256 = """
(KL, VL) = (8, 256)
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no controlmask*
        THEN
            IF (EVEX.b = 1) AND (SRC2 *is memory*)
                THEN DEST[i+31:i] := SRC2[31:0]
                ELSE DEST[i+31:i] := SRC2[i+31:i]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+31:i] := SRC1[i+31:i]
                ELSE DEST[i+31:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_512 = """
(KL, VL) = (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no controlmask*
        THEN
            IF (EVEX.b = 1) AND (SRC2 *is memory*)
                THEN DEST[i+31:i] := SRC2[31:0]
                ELSE DEST[i+31:i] := SRC2[i+31:i]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+31:i] := SRC1[i+31:i]
                ELSE DEST[i+31:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vblendmps"
jit_lowering = "arm64_neon_vblendmps"
fallback = "zig_lane_loop_mask_blend_32"

neon_register_model = """
x86 xmm/ymm/zmm bit lanes are mapped into ARM64 vector temporaries. VBLENDMPS is a per-lane select using opmask register bits. The mask is applied via bsl with mask replicated from k register. Broadcast from 32-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VBLENDMPS.
"""

neon_assembly = """
// NEON lowering: bsl vD.16b, vMASK.16b, vN.16b, vM.16b
// The opmask register bits select between first and second source operands.
// For broadcast: replicate 32-bit value across all lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VBLENDMPS uses opmask register k1 as element selector; EVEX.z enables zeroing-masking.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
