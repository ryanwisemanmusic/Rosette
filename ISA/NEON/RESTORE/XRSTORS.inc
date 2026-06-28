// NEON/RESTORE/XRSTORS.inc
// ARM64/NEON translation mirror generated from ISA/x86/RESTORE/XRSTORS.inc.
// Source contract: XRSTORS — Restore Processor Extended States Supervisor.

semantic = """
Restore processor extended states including supervisor state components.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "XRSTORS"
aliases = ["XRSTORS64"]
category = "system"
feature = "XSS"
element_type = "u8_u32_u64"

encodings = [
  { opcode = "NP 0F C7 /3", form = "XRSTORS mem", op_en = "M", feature = "XSS", vector_length = 0, encoding = "legacy" },
  { opcode = "NP REX.W 0F C7 /3", form = "XRSTORS64 mem", op_en = "M", feature = "XSS", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Restore supervisor extended states from memory. Requires CPL=0. Must be
64-byte aligned.
"""

neon_register_model = """
XRSTORS restores supervisor XSAVE state. ARM64 no direct equivalent.
"""

neon_flag_model = """
XRSTORS does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated supervisor XSAVE state restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
