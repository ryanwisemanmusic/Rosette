// NEON/RESTORE/XRSTOR.inc
// ARM64/NEON translation mirror generated from ISA/x86/RESTORE/XRSTOR.inc.
// Source contract: XRSTOR — Restore Processor Extended States.

semantic = """
Restore processor extended states from the XSAVE/XRSTOR memory layout.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "XRSTOR"
aliases = ["XRSTOR64"]
category = "system"
feature = "XSAVE"
element_type = "u8_u32_u64"

encodings = [
  { opcode = "NP 0F AE /5", form = "XRSTOR mem", op_en = "M", feature = "XSAVE", vector_length = 0, encoding = "legacy" },
  { opcode = "NP REX.W 0F AE /5", form = "XRSTOR64 mem", op_en = "M", feature = "XSAVE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Restore processor extended states from memory. Must be 64-byte aligned.
"""

neon_register_model = """
XRSTOR restores XSAVE extended state. ARM64 no direct equivalent.
"""

neon_flag_model = """
XRSTOR does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated XSAVE extended state restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
