// INSERT/PINSRQ.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/PINSRQ.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PINSRQ: Insert a quadword integer value from a GPR or memory into an XMM register at a specified qword position (64-bit mode only).
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/PINSRQ.inc"
x86_handler = "x86_pinsrq"
neon_lowering = "arm64_neon_insert_qword"
lowering_kind = "arm64_documented_contract"

// INSERT/PINSRQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/PINSRQ.inc.
// Source contract: PINSRQ/VPINSRQ — Insert Quadword.

name = "PINSRQ"
aliases = ["VPINSRQ"]
category = "simd_insertion"
feature = "SSE4.1_AVX_AVX512F"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "66 REX.W 0F 3A 22 /r ib", form = "PINSRQ xmm1, r64/m64, imm8", op_en = "A", feature = "SSE4.1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W1 22 /r ib", form = "VPINSRQ xmm1, xmm2, r64/m64, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W1 22 /r ib", form = "VPINSRQ xmm1{k1}{z}, xmm2, r64/m64, imm8", op_en = "B", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8 (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 2 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
// imm8[0] selects the qword position (0-1) in DEST
// The 64-bit value from SRC is written to DEST[imm8[0]*64+63 : imm8[0]*64]
// Other qwords in DEST are unchanged
// Only encodable in 64-bit mode (REX.W prefix required)
DEST[DEST_QWORD_SELECT] := SRC[63:0];
DEST[127:0] unchanged for other qword lanes;
"""

semantic_vex_128 = """
// VEX form: SRC1 is the first source register; SRC2 is the GPR/memory source
// imm8[0] selects the qword position in the result
DEST := SRC1;
DEST[DEST_QWORD_SELECT] := SRC2[63:0];
"""

semantic_evex = """
// EVEX form adds writemask k1 and zero-masking {z}
DEST := SRC1;
DEST[DEST_QWORD_SELECT] := SRC2[63:0];
"""

handler = "x86_pinsrq"
jit_lowering = "arm64_neon_insert_qword"
fallback = "zig_lane_insert_qword"

neon_register_model = """
x86 xmm registers are mapped into ARM64 vector temporaries. The quadword insertion is performed using ARM64 INS (element insert) with D element size. The GPR source requires a 64-bit register (xN).
"""

neon_flag_model = """
No x86 flags are modified by PINSRQ/VPINSRQ.
"""

neon_assembly = """
ins vD.d[imm1], xN
// ARM64 NEON: insert 64-bit value from general-purpose register xN into vD at 64-bit lane index imm1
// imm1 corresponds to x86 imm8[0] (0-1 qword position)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
