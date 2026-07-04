// INSERT/VINSERTF128.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/VINSERTF128.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF128: Insert a 128-bit floating-point lane from an XMM source register or memory into a YMM destination at a specified 128-bit position.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF128.inc"
x86_handler = "x86_vinsertf128"
neon_lowering = "arm64_neon_insert_128_lane"
lowering_kind = "arm64_documented_contract"

// INSERT/VINSERTF128.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF128.inc.
// Source contract: VINSERTF128 — Insert 128-bit Floating-Point Lane.

name = "VINSERTF128"
aliases = []
category = "simd_insertion"
feature = "AVX"
element_type = "f32_bits"
element_size = 128

encodings = [
  { opcode = "VEX.256.66.0F3A 18 /r ib", form = "VINSERTF128 ymm1, ymm2, xmm3/m128, imm8", op_en = "B", feature = "AVX", vector_length = 256, encoding = "vex" }
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

handler = "x86_vinsertf128"
jit_lowering = "arm64_neon_insert_128_lane"
fallback = "zig_lane_insert_128"

neon_register_model = """
x86 ymm registers are mapped into ARM64 vector temporaries. The 128-bit lane insertion selects one half of the 256-bit destination from SRC2, leaving the other half from SRC1. ARM64 uses vector extract (extr) or subregister moves to implement this.
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF128.
"""

neon_assembly = """
// VINSERTF128: insert 128-bit lane at imm8[0] position
// ARM64: use vector extract or subregister insert
// imm8[0] == 0: vD = VECTOR_SET_LANE(vD, 0, vN[127:0])
// imm8[0] == 1: vD = VECTOR_SET_LANE(vD, 1, vN[127:0])
mov vT.16b, vN.16b
// lane selection controlled by imm8 branching
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
