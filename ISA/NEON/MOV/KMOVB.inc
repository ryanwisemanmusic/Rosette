// MOV/KMOVB.inc
// ARM64/NEON mirror generated from ISA/x86/MOV/KMOVB.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MOV/KMOVB.inc"
x86_handler = "x86_kmovb"
neon_lowering = "arm64_kmovb"
lowering_kind = "arm64_documented_contract"

// KMOVB.inc
// ARM64/NEON translation mirror generated from ISA/x86/MOV/KMOVB.inc.
// Source contract: KMOVB — Move 8-bit Mask.

name = "KMOVB"
aliases = []
category = "mask_move"
feature = "AVX512DQ"
element_type = "mask"
element_size = 8

encodings = [
  { opcode = "VEX.L1.66.0F.W0 90 /r", form = "KMOVB k1, k2", op_en = "RVR", feature = "AVX512DQ", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.66.0F.W0 90 /r", form = "KMOVB k1, m8", op_en = "RM", feature = "AVX512DQ", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.66.0F.W0 91 /r", form = "KMOVB m8, k1", op_en = "MR", feature = "AVX512DQ", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.66.0F.W0 92 /r", form = "KMOVB r32, k1", op_en = "RR", feature = "AVX512DQ", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.L1.66.0F.W0 93 /r", form = "KMOVB k1, r32", op_en = "RR", feature = "AVX512DQ", vector_length = 0, encoding = "vex" }
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
KMOVB transfers 8-bit mask values between mask registers, between mask registers and memory, or between mask registers and general-purpose registers.
"""

handler = "x86_kmovb"
jit_lowering = "arm64_kmovb"
fallback = "zig_kmovb_fallback"

neon_register_model = """
KMOVB is an x86 mask register operation (k0–k7, 8-bit). ARM64 NEON has no dedicated mask register file; lowering maps to GPR or SIMD register moves.
"""

neon_flag_model = """
No x86 flags are modified by KMOVB.
"""

neon_assembly = """
// KMOVB: move 8-bit mask between mask/GPR/memory
// ARM64: MOV or LDR/STR for 8-bit wide transfers
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "KMOVB is an AVX512DQ mask operation with no direct NEON equivalent; lowering uses GPR or SIMD register moves.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
