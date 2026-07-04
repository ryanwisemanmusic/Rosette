// MOV/KMOVW.inc
// ARM64/NEON mirror generated from ISA/x86/MOV/KMOVW.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/KMOVW.inc"
x86_handler = "x86_kmovw"
neon_lowering = "arm64_kmovw"
lowering_kind = "arm64_documented_contract"

// KMOVW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/KMOVW.inc.
// Source contract: KMOVW — Move 16-bit Mask.

name = "KMOVW"
aliases = []
category = "mask_move"
feature = "AVX512F"
element_type = "mask"
element_size = 16

encodings = [
  { opcode = "VEX.L1.0F.W0 90 /r", form = "KMOVW k1, k2", op_en = "RVR", feature = "AVX512F", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W0 90 /r", form = "KMOVW k1, m16", op_en = "RM", feature = "AVX512F", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W0 91 /r", form = "KMOVW m16, k1", op_en = "MR", feature = "AVX512F", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W0 92 /r", form = "KMOVW r32, k1", op_en = "RR", feature = "AVX512F", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W0 93 /r", form = "KMOVW k1, r32", op_en = "RR", feature = "AVX512F", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  MR = ["ModRM:r/m (w)", "ModRM:reg (r)"],
  RR = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = {}
flags_written = []
simd_fp_exceptions = []
other_exceptions = ["See individual encoding exception classes"]

semantic = """
KMOVW transfers 16-bit mask values between mask registers, between mask registers and memory, or between mask registers and general-purpose registers.
"""

handler = "x86_kmovw"
jit_lowering = "arm64_kmovw"
fallback = "zig_kmovw_fallback"

neon_register_model = """
KMOVW is an x86 mask register operation (k0–k7, 16-bit). ARM64 NEON has no dedicated mask register file; lowering maps to GPR or SIMD register moves.
"""

neon_flag_model = """
No x86 flags are modified by KMOVW.
"""

neon_assembly = """
// KMOVW: move 16-bit mask between mask/GPR/memory
// ARM64: MOV or LDR/STR for 16-bit wide transfers
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "KMOVW is an AVX512F mask operation with no direct NEON equivalent; lowering uses GPR or SIMD register moves.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
