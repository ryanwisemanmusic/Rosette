// INSERT/PINSRW.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/PINSRW.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRW: Insert a word integer value from a GPR into an MMX or XMM register at a specified word position.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRW.inc"
x86_handler = "x86_pinsrw"
neon_lowering = "arm64_neon_insert_word"
lowering_kind = "arm64_documented_contract"

// INSERT/PINSRW.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRW.inc.
// Source contract: PINSRW/VPINSRW — Insert Word.

name = "PINSRW"
aliases = ["VPINSRW"]
category = "simd_insertion"
feature = "SSE_SSE2_AVX"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "0F C4 /r ib", form = "PINSRW mm1, r32/m16, imm8", op_en = "A", feature = "SSE", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F C4 /r ib", form = "PINSRW xmm1, r32/m16, imm8", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.W1 C4 /r ib", form = "VPINSRW xmm1, xmm2, r32/m16, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8 (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { mmx = 4, xmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Legacy SSE/SSE2 encoded instruction uses Type 4 class exception conditions",
  "VEX encoded instruction uses Type 4 class exception conditions"
]

semantic_legacy_128 = """
// imm8[2:0] selects the word position (0-7) in DEST
// For MMX form: imm8[2:0] selects word position (0-3)
// The low 16 bits of SRC are written to DEST[imm8[2:0]*16+15 : imm8[2:0]*16]
// Other words in DEST are unchanged
DEST[DEST_WORD_SELECT] := SRC[15:0];
DEST[127:0] unchanged for other word lanes;
"""

semantic_vex_128 = """
// VEX form: SRC1 is the first source register; SRC2 is the GPR/memory source
// imm8[2:0] selects the word position in the result
DEST := SRC1;
DEST[DEST_WORD_SELECT] := SRC2[15:0];
"""

handler = "x86_pinsrw"
jit_lowering = "arm64_neon_insert_word"
fallback = "zig_lane_insert_word"

neon_register_model = """
x86 mmx/xmm registers are mapped into ARM64 vector temporaries. The word insertion is performed using ARM64 INS (element insert) with H element size.
"""

neon_flag_model = """
No x86 flags are modified by PINSRW/VPINSRW.
"""

neon_assembly = """
ins vD.h[imm3], wN
// ARM64 NEON: insert 16-bit value from general-purpose register wN into vD at 16-bit lane index imm3
// imm3 corresponds to x86 imm8[2:0] (0-7 word position for XMM, 0-3 for MMX)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
