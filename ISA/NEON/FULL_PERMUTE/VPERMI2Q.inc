// FULL_PERMUTE/VPERMI2Q.inc
// ARM64/NEON translation mirror generated from ISA/x86/FULL_PERMUTE/VPERMI2Q.inc.
// Source contract: VPERMI2Q — Full Permute of Qwords From Two Tables Overwriting the Index.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VPERMI2Q: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_permute.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FULL_PERMUTE/VPERMI2Q.inc"
x86_handler = "x86_vpermI2q"
neon_lowering = "arm64_vpermI2q"
lowering_kind = "arm64_documented_contract"

// FULL_PERMUTE/VPERMI2Q.inc
// ARM64/NEON translation mirror generated from ISA/x86/FULL_PERMUTE/VPERMI2Q.inc.
// Source contract: VPERMI2Q — Full Permute of Qwords From Two Tables Overwriting the Index.

name = "VPERMI2Q"
aliases = []
category = "simd_permute"
feature = "AVX512F_AVX512VL"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 76 /r", form = "VPERMI2Q xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.0F38.W1 76 /r", form = "VPERMI2Q ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F38.W1 76 /r", form = "VPERMI2Q zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
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
            temp := SRC1[i+63:i]
            IF temp[63] = 0
                THEN DEST[i+63:i] := SRC2[(temp[0]*64)+63:(temp[0]*64)]
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
            temp := SRC1[i+63:i]
            IF temp[63] = 0
                THEN DEST[i+63:i] := SRC2[(temp[1:0]*64)+63:(temp[1:0]*64)]
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
            temp := SRC1[i+63:i]
            IF temp[63] = 0
                THEN DEST[i+63:i] := SRC2[(temp[2:0]*64)+63:(temp[2:0]*64)]
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

handler = "x86_vpermI2q"
jit_lowering = "arm64_vpermI2q"
fallback = "zig_lane_loop_permute_qwords"

neon_register_model = """
x86 xmm/ymm/zmm qword lanes are mapped into ARM64 vector temporaries. VPERMI2Q performs a per-qword permute using the index operand (first source) to select qwords from two table operands. The msb of each index qword selects between SRC2 (0) and SRC3 (1). Broadcast from 64-bit memory is supported.
"""

neon_flag_model = """
No x86 flags are modified by VPERMI2Q.
"""

neon_assembly = """
// NEON lowering: tbl vD.16b, {vT0.16b, vT1.16b}, vIDX.16b
// Uses ARM64 tbl for byte-level lookup across two 16-byte table registers adjusted for qword indices.
// For ymm/zmm: repeat tbl over 16-byte chunks with adjusted index offsets.
// Broadcast: replicate 64-bit value across all qword lanes before permute.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VPERMI2Q uses the MSB of each index qword to select between SRC2 and SRC3 table entries.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "Broadcast supported via /m64bcst; op_en B."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
