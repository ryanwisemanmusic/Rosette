// INSERT/PINSRW.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRW.inc.
// Source contract: PINSRW/VPINSRW — Insert Word.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRW.inc"
x86_handler = "x86_pinsrw"
neon_lowering = "arm64_insert_u16_element"
lowering_kind = "arm64_documented_contract"

name = "PINSRW"
aliases = ["VPINSRW"]
category = "simd_insert"
feature = "SSE_SSE2_AVX_AVX512BW"
element_type = "s16_insert"
element_size = 16

encodings = [
  { opcode = "NP 0F C4 /r ib", form = "PINSRW mm1, r32/m16, imm8", op_en = "RMI", feature = "SSE", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F C4 /r ib", form = "PINSRW xmm1, r32/m16, imm8", op_en = "RMI", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.W0 C4 /r ib", form = "VPINSRW xmm1, xmm2, r32/m16, imm8", op_en = "RVMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG C4 /r ib", form = "VPINSRW xmm1 {k1}{z}, xmm2, r32/m16, imm8", op_en = "C", feature = "AVX512BW", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  RMI = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"],
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { mmx = 4, xmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_64 = """
DEST_SELECT := imm8 AND 0x3;
DEST[DEST_SELECT * 16 + 15 : DEST_SELECT * 16] := SRC[15:0];
DEST[63:0] unchanged except inserted word;
"""

semantic_legacy_128 = """
DEST_SELECT := imm8 AND 0x7;
DEST[DEST_SELECT * 16 + 15 : DEST_SELECT * 16] := SRC[15:0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST_SELECT := imm8 AND 0x7;
DEST[DEST_SELECT * 16 + 15 : DEST_SELECT * 16] := SRC2[15:0];
DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

semantic_evex = """
DEST_SELECT := imm8 AND 0x7;
if k1[DEST_SELECT] == 1 or no_writemask:
    DEST[DEST_SELECT * 16 + 15 : DEST_SELECT * 16] := SRC2[15:0];
    if zeroing_masking:
        for j in 0..7:
            if j != DEST_SELECT:
                DEST[j*16 + 15 : j*16] := 0;
    else:
        DEST[127:0] := SRC1[127:0];
else if zeroing_masking:
    DEST[127:0] := 0;
else:
    DEST[127:0] := SRC1[127:0];
DEST[MAXVL-1:128] := 0;
"""

handler = "x86_pinsrw"
jit_lowering = "arm64_insert_element"
fallback = "zig_insert_lane"

neon_register_model = """
x86 mmx/xmm word lanes are mapped into ARM64 vector temporaries. PINSRW inserts a 16-bit value from GPR or memory into the MMX/XMM register at a position selected by imm8[2:0] for XMM (imm8[1:0] for MMX).
"""

neon_flag_model = """
No x86 flags are modified by PINSRW/VPINSRW.
"""

neon_assembly = """
ins vD.h[idx], wN
// imm8 selects destination word lane idx
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "MMX form uses 64-bit MMX register with imm8 AND 0x3; SSE2/XMM form uses 128-bit XMM register with imm8 AND 0x7."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
