// FULL_PERMUTE/VPERMT2PD.inc
// ARM64/NEON translation mirror generated from ISA/x86/FULL_PERMUTE/VPERMT2PD.inc.
// Source contract: VPERMT2PD — Full Permute of Doubles From Two Tables Overwriting One Table.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VPERMT2PD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_permute.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FULL_PERMUTE/VPERMT2PD.inc"
x86_handler = "x86_vpermt2pd"
neon_lowering = "arm64_vpermt2pd"
lowering_kind = "neon_vector"

name = "VPERMT2PD"
aliases = []
category = "simd_permute"
feature = "AVX512F_AVX512VL"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 7F /r", form = "VPERMT2PD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.0F38.W1 7F /r", form = "VPERMT2PD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F38.W1 7F /r", form = "VPERMT2PD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  B = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-50, Type E4NF Class Exception Conditions."
]

semantic_evex_128 = """
(KL, VL) = (2, 128)
FOR j := 0 TO KL-1
    i := j * 64
    IF k1[j] OR *no controlmask*
        THEN
            temp := SRC2[i+63:i]
            IF temp[63] = 0
                THEN DEST[i+63:i] := SRC1[(temp[0]*64)+63:(temp[0]*64)]
                ELSE DEST[i+63:i] := SRC3[(temp[0]*64)+63:(temp[0]*64)]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+63:i] := DEST[i+63:i]
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
            temp := SRC2[i+63:i]
            IF temp[63] = 0
                THEN DEST[i+63:i] := SRC1[(temp[1:0]*64)+63:(temp[1:0]*64)]
                ELSE DEST[i+63:i] := SRC3[(temp[1:0]*64)+63:(temp[1:0]*64)]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+63:i] := DEST[i+63:i]
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
            temp := SRC2[i+63:i]
            IF temp[63] = 0
                THEN DEST[i+63:i] := SRC1[(temp[2:0]*64)+63:(temp[2:0]*64)]
                ELSE DEST[i+63:i] := SRC3[(temp[2:0]*64)+63:(temp[2:0]*64)]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+63:i] := DEST[i+63:i]
                ELSE DEST[i+63:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vpermt2pd"
jit_lowering = "arm64_vpermt2pd"
fallback = "zig_lane_loop_permute_f64"

neon_register_model = """
x86 xmm/ymm/zmm f64 lanes are mapped into ARM64 vector temporaries. VPERMT2PD performs a per-lane permute using the index in SRC2 (EVEX.vvvv) to select f64 lanes from two tables: SRC1 (ModRM:reg, overwritten) and SRC3 (ModRM:r/m). The msb of each 64-bit index selects between SRC1 (0) and SRC3 (1). Broadcast from 64-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VPERMT2PD.
"""

neon_assembly = """
// NEON lowering: tbl vD.16b, {vT0.16b, vT1.16b}, vIDX.16b
// For 64-bit lanes, use ARM64 tbl with scaled index bytes.
// Unlike VPERMI2PD, the index comes from SRC2 (not the destination) and SRC1 provides the first table.
// Broadcast: replicate 64-bit value across all lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VPERMT2PD uses the MSB of each 64-bit index element (from SRC2) to select between SRC1 and SRC3 table entries.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "m64bcst broadcast supported when operand is memory."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
