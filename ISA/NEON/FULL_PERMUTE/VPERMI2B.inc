// FULL_PERMUTE/VPERMI2B.inc
// ARM64/NEON translation mirror generated from ISA/x86/FULL_PERMUTE/VPERMI2B.inc.
// Source contract: VPERMI2B — Full Permute of Bytes From Two Tables Overwriting the Index.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VPERMI2B: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_permute.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FULL_PERMUTE/VPERMI2B.inc"
x86_handler = "x86_vpermI2b"
neon_lowering = "arm64_vpermI2b"
lowering_kind = "neon_vector"

name = "VPERMI2B"
aliases = []
category = "simd_permute"
feature = "AVX512_VBMI"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 75 /r", form = "VPERMI2B xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512VL AVX512_VBMI", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 75 /r", form = "VPERMI2B ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512VL AVX512_VBMI", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 75 /r", form = "VPERMI2B zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512_VBMI", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 16, ymm = 32, zmm = 64 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Exceptions Type E4NF.nb in Table 2-50"
]

semantic_evex_128 = """
(KL, VL) = (16, 128)
FOR j := 0 TO KL-1
    i := j * 8
    IF k1[j] OR *no controlmask*
        THEN
            temp := SRC1[i+7:i]
            IF temp[7] = 0
                THEN DEST[i+7:i] := SRC2[(temp[6:0]*8)+7:(temp[6:0]*8)]
                ELSE DEST[i+7:i] := SRC3[(temp[6:0]*8)+7:(temp[6:0]*8)]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+7:i] := DEST[i+7:i]
                ELSE DEST[i+7:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_256 = """
(KL, VL) = (32, 256)
FOR j := 0 TO KL-1
    i := j * 8
    IF k1[j] OR *no controlmask*
        THEN
            temp := SRC1[i+7:i]
            IF temp[7] = 0
                THEN DEST[i+7:i] := SRC2[(temp[6:0]*8)+7:(temp[6:0]*8)]
                ELSE DEST[i+7:i] := SRC3[(temp[6:0]*8)+7:(temp[6:0]*8)]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+7:i] := DEST[i+7:i]
                ELSE DEST[i+7:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

semantic_evex_512 = """
(KL, VL) = (64, 512)
FOR j := 0 TO KL-1
    i := j * 8
    IF k1[j] OR *no controlmask*
        THEN
            temp := SRC1[i+7:i]
            IF temp[7] = 0
                THEN DEST[i+7:i] := SRC2[(temp[6:0]*8)+7:(temp[6:0]*8)]
                ELSE DEST[i+7:i] := SRC3[(temp[6:0]*8)+7:(temp[6:0]*8)]
            FI
        ELSE
            IF *merging-masking*
                THEN DEST[i+7:i] := DEST[i+7:i]
                ELSE DEST[i+7:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vpermI2b"
jit_lowering = "arm64_vpermI2b"
fallback = "zig_lane_loop_permute_bytes"

neon_register_model = """
x86 xmm/ymm/zmm byte lanes are mapped into ARM64 vector temporaries. VPERMI2B performs a per-byte permute using the index operand (first source) to select bytes from two table operands. The msb of each index byte selects between SRC2 (0) and SRC3 (1).
"""

neon_flag_model = """
No x86 flags are modified by VPERMI2B.
"""

neon_assembly = """
// NEON lowering: tbl vD.16b, {vT0.16b, vT1.16b}, vIDX.16b
// Uses ARM64 tbl for byte-level lookup across two 16-byte table registers.
// For ymm/zmm: repeat tbl over 16-byte chunks with adjusted index offsets.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "VPERMI2B uses the MSB of each index byte to select between SRC2 and SRC3 table entries.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "No broadcast support; op_en A without broadcast."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
