// INSERT/PINSRD.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/PINSRD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRD: Insert a doubleword integer value from a GPR or memory into an XMM register at a specified dword position.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRD.inc"
x86_handler = "x86_pinsrd"
neon_lowering = "arm64_insert_element"
lowering_kind = "arm64_documented_contract"

// INSERT/PINSRD.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRD.inc.
// Source contract: PINSRD/VPINSRD — Insert Doubleword.

name = "PINSRD"
aliases = ["VPINSRD"]
category = "simd_insertion"
feature = "SSE4.1_AVX_AVX512F"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "66 0F 3A 22 /r ib", form = "PINSRD xmm1, r32/m32, imm8", op_en = "A", feature = "SSE4.1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W0 22 /r ib", form = "VPINSRD xmm1, xmm2, r32/m32, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W0 22 /r ib", form = "VPINSRD xmm1{k1}{z}, xmm2, r32/m32, imm8", op_en = "B", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8 (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 4 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
// imm8[1:0] selects the dword position (0-3) in DEST
// The 32-bit value from SRC is written to DEST[imm8[1:0]*32+31 : imm8[1:0]*32]
// Other dwords in DEST are unchanged
DEST[DEST_DWORD_SELECT] := SRC[31:0];
DEST[127:0] unchanged for other dword lanes;
"""

semantic_vex_128 = """
// VEX form: SRC1 is the first source register; SRC2 is the GPR/memory source
// imm8[1:0] selects the dword position in the result
DEST := SRC1;
DEST[DEST_DWORD_SELECT] := SRC2[31:0];
"""

semantic_evex = """
// EVEX form adds writemask k1 and zero-masking {z}
DEST := SRC1;
DEST[DEST_DWORD_SELECT] := SRC2[31:0];
"""

handler = "x86_pinsrd"
jit_lowering = "arm64_neon_insert_dword"
fallback = "zig_lane_insert_dword"

neon_register_model = """
x86 xmm registers are mapped into ARM64 vector temporaries. The doubleword insertion is performed using ARM64 INS (element insert) with S element size.
"""

neon_flag_model = """
No x86 flags are modified by PINSRD/VPINSRD.
"""

neon_assembly = """
ins vD.s[imm2], wN
// ARM64 NEON: insert 32-bit value from general-purpose register wN into vD at 32-bit lane index imm2
// imm2 corresponds to x86 imm8[1:0] (0-3 dword position)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
