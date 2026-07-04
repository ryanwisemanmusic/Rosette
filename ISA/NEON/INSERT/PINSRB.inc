// INSERT/PINSRB.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/PINSRB.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRB: Insert a byte integer value from a GPR or memory into an XMM register at a specified byte position.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRB.inc"
x86_handler = "x86_pinsrb"
neon_lowering = "arm64_neon_insert_byte"
lowering_kind = "arm64_documented_contract"

// INSERT/PINSRB.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRB.inc.
// Source contract: PINSRB/VPINSRB — Insert Byte.

name = "PINSRB"
aliases = ["VPINSRB"]
category = "simd_insertion"
feature = "SSE4.1_AVX_AVX512F"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "66 0F 3A 20 /r ib", form = "PINSRB xmm1, r32/m8, imm8", op_en = "A", feature = "SSE4.1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W0 20 /r ib", form = "VPINSRB xmm1, xmm2, r32/m8, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W0 20 /r ib", form = "VPINSRB xmm1{k1}{z}, xmm2, r32/m8, imm8", op_en = "B", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8 (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
// imm8[3:0] selects the byte position (0-15) in DEST
// The low byte of SRC is written to DEST[imm8[3:0]*8+7 : imm8[3:0]*8]
// Other bytes in DEST are unchanged
// When SRC is a GPR, only the low 8 bits (byte) are used
// DEST[127:0] = MERGE(DEST[127:0], SRC[7:0] AT POSITION imm8[3:0])
DEST[DEST_BYTE_SELECT] := SRC[7:0];
DEST[127:0] unchanged for other byte lanes;
"""

semantic_vex_128 = """
// VEX form: SRC1 is the first source register; SRC2 is the GPR/memory source
// imm8[3:0] selects the byte position in the result
DEST := SRC1;
DEST[DEST_BYTE_SELECT] := SRC2[7:0];
"""

semantic_evex = """
// EVEX form adds writemask k1 and zero-masking {z}
// Byte positions not covered by writemask are either merged from SRC1 or zeroed
DEST := SRC1;
DEST[DEST_BYTE_SELECT] := SRC2[7:0];
"""

handler = "x86_pinsrb"
jit_lowering = "arm64_neon_insert_byte"
fallback = "zig_lane_insert_byte"

neon_register_model = """
x86 xmm registers are mapped into ARM64 vector temporaries. The byte insertion is performed using ARM64 INS (element insert) with B element size. The GPR source is moved into a temporary scalar register before insertion.
"""

neon_flag_model = """
No x86 flags are modified by PINSRB/VPINSRB.
"""

neon_assembly = """
ins vD.b[imm4], wN
// ARM64 NEON: insert byte from general-purpose register wN into vD at byte index imm4
// imm4 corresponds to x86 imm8[3:0] (0-15 byte position)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
