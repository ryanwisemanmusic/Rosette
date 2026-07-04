// FULL_PERMUTE/VPERMI2W.inc
// Full Permute of Words From Two Tables Overwriting the Index.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FULL_PERMUTE/VPERMI2W.inc"
x86_handler = "x86_vpermI2w"
neon_lowering = "arm64_vpermI2w"
lowering_kind = "neon_vector"

name = "VPERMI2W"
aliases = []
category = "simd_permute"
feature = "AVX512BW"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 75 /r", form = "VPERMI2W xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512VL AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 75 /r", form = "VPERMI2W ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512VL AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 75 /r", form = "VPERMI2W zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Exceptions Type E4NF.nb in Table 2-50"
]

semantic_evex_128 = """
(KL, VL) = (8, 128)
FOR j := 0 TO KL-1
    i := j * 16
    IF k1[j] OR *no controlmask*
        THEN DEST[i+15:i] := SRC2[SRC1[i+15:i]*16 +: 16]
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := DEST[i+15:i]
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
        THEN DEST[i+15:i] := SRC2[SRC1[i+15:i]*16 +: 16]
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := DEST[i+15:i]
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
        THEN DEST[i+15:i] := SRC2[SRC1[i+15:i]*16 +: 16]
        ELSE
            IF *merging-masking*
                THEN DEST[i+15:i] := DEST[i+15:i]
                ELSE DEST[i+15:i] := 0
            FI
    FI
ENDFOR
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_vpermI2w"
jit_lowering = "arm64_vpermI2w"
fallback = "zig_lane_loop_permute_16"

neon_register_model = """
VPERMI2W performs a full permute of word elements from two tables using indices in the destination.
"""

neon_flag_model = """
No x86 flags are modified by VPERMI2W.
"""

neon_assembly = """
// NEON lowering: VPERMI2W full permute of words from two tables overwriting the index.
"""

neon_notes = [
  "VPERMI2W uses DEST as the index table, SRC2 (EVEX.vvvv) as table 0, SRC3 (ModRM:r/m) as table 1.",
  "Index values beyond the table size may produce implementation-specific results.",
  "Writemask k1 controls element update; EVEX.z enables zeroing-masking."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
