// INSERT/VINSERTI128.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/VINSERTI128.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTI128: Insert a 128-bit integer lane from an XMM source register or memory into a YMM destination at a specified 128-bit position.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTI128.inc"
x86_handler = "x86_vinserti128"
neon_lowering = "arm64_neon_insert_i128"
lowering_kind = "arm64_documented_contract"

// INSERT/VINSERTI128.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTI128.inc.
// Source contract: VINSERTI128 — Insert 128-bit Integer Lane.

name = "VINSERTI128"
aliases = []
category = "simd_insertion"
feature = "AVX2"
element_type = "u8_bits"
element_size = 128

encodings = [
  { opcode = "VEX.256.66.0F3A 38 /r ib", form = "VINSERTI128 ymm1, ymm2, xmm3/m128, imm8", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { ymm = 2 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "VEX encoded instruction uses Type 4 class exception conditions"
]

semantic_vex_256 = """
// imm8[0] selects the 128-bit lane position in DEST
// VINSERTI128 is the integer equivalent of VINSERTF128
// imm8[0] = 0: DEST[127:0] = SRC2[127:0]; DEST[255:128] = SRC1[255:128]
// imm8[0] = 1: DEST[255:128] = SRC2[127:0]; DEST[127:0] = SRC1[127:0]
if imm8[0] == 0:
    DEST[127:0]   = SRC2[127:0];
    DEST[255:128] = SRC1[255:128];
else:
    DEST[255:128] = SRC2[127:0];
    DEST[127:0]   = SRC1[127:0];
DEST[MAXVL-1:256] = 0;
"""

handler = "x86_vinserti128"
jit_lowering = "arm64_neon_insert_i128"
fallback = "zig_lane_insert_128"

neon_register_model = """
x86 ymm registers are mapped into ARM64 vector temporaries. The 128-bit integer lane insertion is performed identically to VINSERTF128, selecting between halves of the 256-bit vector.
"""

neon_flag_model = """
No x86 flags are modified by VINSERTI128.
"""

neon_assembly = """
// VINSERTI128: insert 128-bit integer lane at position imm8[0]
// ARM64: vector extract or subregister insert
// imm8[0] == 0: vD_lo = vN; vD_hi = vM_hi
// imm8[0] == 1: vD_lo = vM_lo; vD_hi = vN
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
