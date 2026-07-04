// INSERT/INSERTPS.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/INSERTPS.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
INSERTPS: Insert selected scalar single-precision element from source or immediate zero into DEST at specified lane.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/INSERTPS.inc"
x86_handler = "x86_insertps"
neon_lowering = "arm64_neon_insert_ps"
lowering_kind = "arm64_documented_contract"

// INSERT/INSERTPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/INSERTPS.inc.
// Source contract: INSERTPS/VINSERTPS — Insert Scalar Single-Precision Floating-Point Value.

name = "INSERTPS"
aliases = ["VINSERTPS"]
category = "simd_insertion"
feature = "SSE4.1_AVX_AVX512F"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "NP 0F 3A 21 /r ib", form = "INSERTPS xmm1, xmm2/m32, imm8", op_en = "A", feature = "SSE4.1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W0 21 /r ib", form = "VINSERTPS xmm1, xmm2, xmm3/m32, imm8", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.W0 21 /r ib", form = "VINSERTPS xmm1{k1}{z}, xmm2, xmm3/m32, imm8", op_en = "B", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8 (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 4 }
flags_written = []
simd_fp_exceptions = ["invalid"]
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
// imm8[7:6] selects the DEST element to overwrite (0-3)
// imm8[5:4] selects the SRC element to read from (0-3), or 10b to zero the element
// imm8[3:0] are zero-mask bits: if bit j is set, DEST element j is zeroed
// When imm8[5:4] == 10b, the source value is taken as 0.0 (no memory access required even for memory operand)
// When source is memory, the 32-bit value is loaded from the effective address
// For VEX/EVEX forms: SRC1 is a register; SRC2 is the insertion source (reg or mem)
// For legacy form: DEST is also SRC1 (read-modify-write)
DEST := DEST;
// See Intel SDM for full case analysis of imm8 bits
"""

semantic_vex_128 = """
// VEX form: SRC1 is first source register (DEST before modification)
// SRC2 is the insertion source (register or memory, governed by imm8[5:4])
// Result written to DEST
DEST := SRC1;
// See Intel SDM for imm8 decoding
"""

semantic_evex = """
// EVEX form adds writemask k1 and zero-masking {z}
// Elements not selected and not covered by writemask are merged or zeroed per {z}
DEST := SRC1;
// See Intel SDM
"""

handler = "x86_insertps"
jit_lowering = "arm64_neon_insert_ps"
fallback = "zig_lane_insert_ps"

neon_register_model = """
x86 xmm registers are mapped into ARM64 vector temporaries. The INSERTPS operation selects and inserts one single-precision lane from SRC2 into DEST at a position determined by imm8[7:6], with optional zero-masking of other lanes via imm8[3:0]. ARM64 'ins' element-insert instruction handles the lane selection directly.
"""

neon_flag_model = """
No x86 flags are modified by INSERTPS/VINSERTPS.
"""

neon_assembly = """
ins vD.s[imm], vN.s[imm]
// ARM64 NEON element insert: copy single-precision lane from vN at index imm8[5:4] to vD at index imm8[7:6]
// Zero-masking (imm8[3:0]) and source-zeroing (imm8[5:4]==10b) handled via additional movi+bit instructions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
