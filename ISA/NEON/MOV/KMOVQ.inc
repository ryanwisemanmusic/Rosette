// MOV/KMOVQ.inc
// ARM64/NEON mirror generated from ISA/x86/MOV/KMOVQ.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/KMOVQ.inc"
x86_handler = "x86_kmovq"
neon_lowering = "arm64_kmovq"
lowering_kind = "arm64_documented_contract"

// KMOVQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/KMOVQ.inc.
// Source contract: KMOVQ — Move 64-bit Mask.

name = "KMOVQ"
aliases = []
category = "mask_move"
feature = "AVX512BW"
element_type = "mask"
element_size = 64

encodings = [
  { opcode = "VEX.L1.0F.W1 90 /r", form = "KMOVQ k1, k2", op_en = "RVR", feature = "AVX512BW", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W1 90 /r", form = "KMOVQ k1, m64", op_en = "RM", feature = "AVX512BW", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W1 91 /r", form = "KMOVQ m64, k1", op_en = "MR", feature = "AVX512BW", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W1 92 /r", form = "KMOVQ r64, k1", op_en = "RR", feature = "AVX512BW", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.0F.W1 93 /r", form = "KMOVQ k1, r64", op_en = "RR", feature = "AVX512BW", vector_length = 0, encoding = "vex" }
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
KMOVQ transfers 64-bit mask values between mask registers, between mask registers and memory, or between mask registers and general-purpose registers (64-bit mode only).
"""

handler = "x86_kmovq"
jit_lowering = "arm64_kmovq"
fallback = "zig_kmovq_fallback"

neon_register_model = """
KMOVQ is an x86 mask register operation (k0–k7, 64-bit). ARM64 NEON has no dedicated mask register file; lowering maps to GPR or SIMD register moves.
"""

neon_flag_model = """
No x86 flags are modified by KMOVQ.
"""

neon_assembly = """
// KMOVQ: move 64-bit mask between mask/GPR/memory
// ARM64: MOV or LDR/STR for 64-bit wide transfers
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "KMOVQ is an AVX512BW mask operation with no direct NEON equivalent; lowering uses GPR or SIMD register moves.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
