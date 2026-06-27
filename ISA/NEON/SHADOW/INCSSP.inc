// NEON/SHADOW/INCSSP.inc
// ARM64/NEON translation mirror generated from ISA/x86/SHADOW/INCSSP.inc.
// Source contract: INCSSP — Increment Shadow Stack Pointer (CET_SS).

semantic = """
Increment shadow stack pointer (SSP) by operand_size * SRC[7:0].
Pop and discard the first and last shadow stack element in the range.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "INCSSP"
aliases = ["INCSSPD", "INCSSPQ"]
category = "system"
feature = "CET_SS"
element_type = "u32_u64"

encodings = [
  { opcode = "F3 0F AE /05", form = "INCSSPD r32", op_en = "R", feature = "CET_SS", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 REX.W 0F AE /05", form = "INCSSPQ r64", op_en = "R", feature = "CET_SS", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  R = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Increment shadow stack pointer (SSP) by operand_size * SRC[7:0].
Pop and discard the first and last shadow stack element in the range.
"""

neon_register_model = """
INCSSP manages the CET shadow stack pointer (SSP). ARM64 does not have a
hardware shadow stack; emulation via software-managed shadow stack is required.
"""

neon_flag_model = """
INCSSP does not modify flags.
"""

neon_assembly = """
// NEON lowering: software shadow stack SSP increment by (operand_size * SRC[7:0]).
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "INCSSPD operates on 32-bit operand size; INCSSPQ operates on 64-bit operand size.",
  "ARM64 NEON mirror: software-emulated CET shadow stack."
]
