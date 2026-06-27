// NEON/SAVE/SAVEPREVSSP.inc
// ARM64/NEON translation mirror generated from ISA/x86/SAVE/SAVEPREVSSP.inc.
// Source contract: SAVEPREVSSP — Save Previous Shadow Stack Pointer (CET_SS).

semantic = """
Push a restore-shadow-stack token on the previous shadow stack.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "SAVEPREVSSP"
aliases = []
category = "system"
feature = "CET_SS"
element_type = "u64"

encodings = [
  { opcode = "F3 0F 01 EA", form = "SAVEPREVSSP", op_en = "ZO", feature = "CET_SS", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Push a restore-shadow-stack token on the previous shadow stack.
"""

neon_register_model = """
SAVEPREVSSP manages CET shadow stack tokens. ARM64 software emulation.
"""

neon_flag_model = """
SAVEPREVSSP does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated CET shadow stack token push.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
