// NEON/RESTORE/RSTORSSP.inc
// ARM64/NEON translation mirror generated from ISA/x86/RESTORE/RSTORSSP.inc.
// Source contract: RSTORSSP — Restore Saved Shadow Stack Pointer (CET_SS).

semantic = """
Restore the current shadow stack pointer from a restore-shadow-stack token.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "RSTORSSP"
aliases = []
category = "system"
feature = "CET_SS"
element_type = "u64"

encodings = [
  { opcode = "F3 0F 01 /5", form = "RSTORSSP m64", op_en = "M", feature = "CET_SS", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = ["CF"]
simd_fp_exceptions = []

semantic_general = """
Restore the current SSP from the restore-shadow-stack token at the 8-byte
aligned memory operand. CF cleared on success, set on failure.
"""

neon_register_model = """
RSTORSSP manages CET shadow stack tokens. ARM64 software emulation.
"""

neon_flag_model = """
CF cleared on success, set on validation failure.
"""

neon_assembly = """
// NEON lowering: software-emulated CET shadow stack token restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
