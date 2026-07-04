// FIX_UP/VFIXUPIMMPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/FIX_UP/VFIXUPIMMPD.inc.
// Source contract: VFIXUPIMMPD — Fix Up Special Packed Float64 Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VFIXUPIMMPD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_fixup.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FIX_UP/VFIXUPIMMPD.inc"
x86_handler = "x86_vfixupimmpd"
neon_lowering = "arm64_vfixupimmpd"
lowering_kind = "neon_vector"

name = "VFIXUPIMMPD"
aliases = []
category = "simd_fixup"
feature = "AVX512F_AVX512VL"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 54 /r ib", form = "VFIXUPIMMPD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F3A.W1 54 /r ib", form = "VFIXUPIMMPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "A", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W1 54 /r ib", form = "VFIXUPIMMPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = ["Zero", "Invalid"]
other_exceptions = [
  "See Table 2-46, \"Type E2 Class Exception Conditions.\""
]

semantic_evex_128 = """
(KL, VL) = (2, 128)
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no controlmask*
        THEN
            CASE (SRC1[i+63:i] AND (FLOAT64_CLASS_SPECIAL_MASK)) OF
                QNAN: DEST[i+63:i] := FIXUP(imm8[1:0], SRC1[i+63:i], SRC2[i+63:i])
                SNAN: DEST[i+63:i] := FIXUP(imm8[3:2], SRC1[i+63:i], SRC2[i+63:i])
                -INF: DEST[i+63:i] := FIXUP(imm8[5:4], SRC1[i+63:i], SRC2[i+63:i])
                -MAX: DEST[i+63:i] := FIXUP(imm8[7:6], SRC1[i+63:i], SRC2[i+63:i])
                DEFAULT: DEST[i+63:i] := SRC1[i+63:i]
            ESAC
        ELSE
            IF *merging-masking*
                THEN DEST[i+63:i] := SRC1[i+63:i]
                ELSE DEST[i+63:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_256 = """
(KL, VL) = (4, 256)
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no controlmask*
        THEN
            CASE (SRC1[i+63:i] AND (FLOAT64_CLASS_SPECIAL_MASK)) OF
                QNAN: DEST[i+63:i] := FIXUP(imm8[1:0], SRC1[i+63:i], SRC2[i+63:i])
                SNAN: DEST[i+63:i] := FIXUP(imm8[3:2], SRC1[i+63:i], SRC2[i+63:i])
                -INF: DEST[i+63:i] := FIXUP(imm8[5:4], SRC1[i+63:i], SRC2[i+63:i])
                -MAX: DEST[i+63:i] := FIXUP(imm8[7:6], SRC1[i+63:i], SRC2[i+63:i])
                DEFAULT: DEST[i+63:i] := SRC1[i+63:i]
            ESAC
        ELSE
            IF *merging-masking*
                THEN DEST[i+63:i] := SRC1[i+63:i]
                ELSE DEST[i+63:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_512 = """
(KL, VL) = (8, 512)
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no controlmask*
        THEN
            CASE (SRC1[i+63:i] AND (FLOAT64_CLASS_SPECIAL_MASK)) OF
                QNAN: DEST[i+63:i] := FIXUP(imm8[1:0], SRC1[i+63:i], SRC2[i+63:i])
                SNAN: DEST[i+63:i] := FIXUP(imm8[3:2], SRC1[i+63:i], SRC2[i+63:i])
                -INF: DEST[i+63:i] := FIXUP(imm8[5:4], SRC1[i+63:i], SRC2[i+63:i])
                -MAX: DEST[i+63:i] := FIXUP(imm8[7:6], SRC1[i+63:i], SRC2[i+63:i])
                DEFAULT: DEST[i+63:i] := SRC1[i+63:i]
            ESAC
        ELSE
            IF *merging-masking*
                THEN DEST[i+63:i] := SRC1[i+63:i]
                ELSE DEST[i+63:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vfixupimmpd"
jit_lowering = "arm64_vfixupimmpd"
fallback = "zig_lane_loop_fixup_64"

neon_register_model = """
x86 xmm/ymm/zmm bit lanes are mapped into ARM64 vector temporaries. VFIXUPIMMPD is a per-lane fix-up using imm8 class lookup against src1 special values and selecting from src2. Broadcast from 64-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VFIXUPIMMPD.
"""

neon_assembly = """
// NEON lowering: fcsel-based fix-up of float64 lanes
// The imm8 class selectors are expanded into a chain of compare-and-select operations.
// For broadcast: replicate 64-bit value across all lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VFIXUPIMMPD uses opmask register k1 as element selector; EVEX.z enables zeroing-masking.",
  "The imm8 operand encodes four 2-bit fix-up action fields for QNaN/SNaN/-Inf/-Max classes.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
