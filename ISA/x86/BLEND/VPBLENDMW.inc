// BLEND/VPBLENDMW.inc
// ARM64/NEON translation mirror generated from ISA/x86/BLEND/VPBLENDMW.inc.
// Source contract: VPBLENDMW — Blend Word Vectors Using an OpMask Control.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VPBLENDMW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_mask_blend.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BLEND/VPBLENDMW.inc"
x86_handler = "x86_vpblendmw"
neon_lowering = "arm64_neon_vpblendmw"
lowering_kind = "neon_vector"

name = "VPBLENDMW"
aliases = []
category = "simd_mask_blend"
feature = "AVX512BW_AVX512VL"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 66 /r", form = "VPBLENDMW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 66 /r", form = "VPBLENDMW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 66 /r", form = "VPBLENDMW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-49, \"Type E4 Class Exception Conditions.\""
]

semantic_evex_128 = """
(KL, VL) = (8, 128)
FOR j := 0 TO KL-1
    i := j * 16
    IF k1[j] OR *no writemask*
        THEN DEST[i+15:i] := SRC2[i+15:i]
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := SRC1[i+15:i]
                ELSE DEST[i+15:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_256 = """
(KL, VL) = (16, 256)
FOR j := 0 TO KL-1
    i := j * 16
    IF k1[j] OR *no writemask*
        THEN DEST[i+15:i] := SRC2[i+15:i]
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := SRC1[i+15:i]
                ELSE DEST[i+15:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_512 = """
(KL, VL) = (32, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF k1[j] OR *no writemask*
        THEN DEST[i+15:i] := SRC2[i+15:i]
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := SRC1[i+15:i]
                ELSE DEST[i+15:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vpblendmw"
jit_lowering = "arm64_neon_vpblendmw"
fallback = "zig_lane_loop_mask_blend_16"

neon_register_model = """
x86 xmm/ymm/zmm bit lanes are mapped into ARM64 vector temporaries. VPBLENDMW is a per-word select using opmask register bits. The mask is applied via bsl with mask replicated from k register.
"""

neon_flag_model = """
No x86 flags are modified by VPBLENDMW.
"""

neon_assembly = """
// NEON lowering: bsl vD.16b, vMASK.16b, vN.16b, vM.16b
// The opmask register bits select between first and second source operands.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VPBLENDMW uses opmask register k1 as element selector; EVEX.z enables zeroing-masking.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
