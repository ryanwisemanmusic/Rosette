// PERFORM/VREDUCEPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/PERFORM/VREDUCEPH.inc.
// Source contract: VREDUCEPH — Perform Reduction Transformation on Packed FP16 Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VREDUCEPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_arithmetic.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PERFORM/VREDUCEPH.inc"
x86_handler = "x86_vreduceph"
neon_lowering = "arm64_vreduceph"
lowering_kind = "arm64_documented_contract"

name = "VREDUCEPH"
aliases = []
category = "simd_arithmetic"
feature = "AVX512_FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.NP.0F3A.W0 56 /r ib", form = "VREDUCEPH xmm1{k1}{z}, xmm2/m128/m16bcst, imm8", op_en = "A", feature = "AVX512-FP16 AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.NP.0F3A.W0 56 /r ib", form = "VREDUCEPH ymm1{k1}{z}, ymm2/m256/m16bcst, imm8", op_en = "A", feature = "AVX512-FP16 AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.NP.0F3A.W0 56 /r ib", form = "VREDUCEPH zmm1{k1}{z}, zmm2/m512/m16bcst {sae}, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Precision"]
other_exceptions = [
  "See Table 2-46, Type E2 Class Exception Conditions.",
  "#UD if EVEX.vvvv != 1111B."
]

semantic_evex_128 = """
(KL, VL) = (8, 128)
FOR j := 0 TO KL-1
    i := j * 16
    IF k1[j] OR *no controlmask*
        THEN
            DEST[i+15:i] := REDUCE(SRC[i+15:i], imm8)
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := SRC[i+15:i]
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
    IF k1[j] OR *no controlmask*
        THEN
            DEST[i+15:i] := REDUCE(SRC[i+15:i], imm8)
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := SRC[i+15:i]
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
    IF k1[j] OR *no controlmask*
        THEN
            DEST[i+15:i] := REDUCE(SRC[i+15:i], imm8)
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := SRC[i+15:i]
                ELSE DEST[i+15:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vreduceph"
jit_lowering = "arm64_vreduceph"
fallback = "zig_lane_loop_reduce_f16"

neon_register_model = """
x86 xmm/ymm/zmm f16 lanes are mapped into ARM64 vector temporaries. VREDUCEPH performs a per-lane reduction transformation on packed FP16 values, controlled by imm8. Broadcast from 16-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VREDUCEPH.
"""

neon_assembly = """
// NEON lowering: per-lane reduction using the REDUCE primitive controlled by imm8.
// The imm8 operand specifies the reduction class and magnitude.
// For broadcast: replicate 16-bit value across all lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VREDUCEPH uses opmask register k1 as element selector; EVEX.z enables zeroing-masking.",
  "The imm8 operand controls the reduction exponent magnitude and the range/truncation behavior.",
  "#UD is raised if EVEX.vvvv != 1111B.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
