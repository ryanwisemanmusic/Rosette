// PERFORM/VREDUCEPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERFORM/VREDUCEPS.inc.
// Source contract: VREDUCEPS — Perform Reduction Transformation on Packed Float32 Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VREDUCEPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCEPS.inc"
x86_handler = "x86_vreduceps"
neon_lowering = "arm64_vreduceps"
lowering_kind = "arm64_documented_contract"

name = "VREDUCEPS"
aliases = []
category = "simd_arithmetic"
feature = "AVX512DQ"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 56 /r ib", form = "VREDUCEPS xmm1 {k1}{z}, xmm2/m128/m32bcst, imm8", op_en = "A", feature = "AVX512VL AVX512DQ", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F3A.W0 56 /r ib", form = "VREDUCEPS ymm1 {k1}{z}, ymm2/m256/m32bcst, imm8", op_en = "A", feature = "AVX512VL AVX512DQ", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W0 56 /r ib", form = "VREDUCEPS zmm1 {k1}{z}, zmm2/m512/m32bcst{sae}, imm8", op_en = "A", feature = "AVX512DQ", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Precision"]
other_exceptions = [
  "See Table 2-46, Type E2 Class Exception Conditions.",
  "#UD if EVEX.vvvv != 1111B."
]

semantic_evex_128 = """
(KL, VL) = (4, 128)
FOR j := 0 TO KL-1
    i := j * 32
    IF k1[j] OR *no controlmask*
        THEN
            DEST[i+31:i] := REDUCE(SRC[i+31:i], imm8)
        ELSE
            IF *merging-masking*
                THEN DEST[i+31:i] := SRC[i+31:i]
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
            DEST[i+31:i] := REDUCE(SRC[i+31:i], imm8)
        ELSE
            IF *merging-masking*
                THEN DEST[i+31:i] := SRC[i+31:i]
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
            DEST[i+31:i] := REDUCE(SRC[i+31:i], imm8)
        ELSE
            IF *merging-masking*
                THEN DEST[i+31:i] := SRC[i+31:i]
                ELSE DEST[i+31:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vreduceps"
jit_lowering = "arm64_vreduceps"
fallback = "zig_lane_loop_reduce_f32"

neon_register_model = """
x86 xmm/ymm/zmm f32 lanes are mapped into ARM64 vector temporaries. VREDUCEPS performs a per-lane reduction transformation on packed float32 values, controlled by imm8. Broadcast from 32-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VREDUCEPS.
"""

neon_assembly = """
// NEON lowering: per-lane reduction using the REDUCE primitive controlled by imm8.
// The imm8 operand specifies the reduction class and magnitude.
// For broadcast: replicate 32-bit value across all lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VREDUCEPS uses opmask register k1 as element selector; EVEX.z enables zeroing-masking.",
  "The imm8 operand controls the reduction exponent magnitude and the range/truncation behavior.",
  "#UD is raised if EVEX.vvvv != 1111B.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
