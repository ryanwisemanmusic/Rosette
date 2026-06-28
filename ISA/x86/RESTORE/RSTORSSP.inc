// RESTORE/RSTORSSP.inc
// Source contract: RSTORSSP — Restore Saved Shadow Stack Pointer (CET_SS).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESTORE/RSTORSSP.inc"
x86_handler = "x86_rstorssp"
neon_lowering = "arm64_rstorssp"
lowering_kind = "arm64_documented_contract"

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
Restore the current shadow stack pointer (SSP) from the restore-shadow-stack
token located at the 8-byte aligned memory operand. If validation succeeds,
the SSP is updated; CF is cleared on success, set on failure.
"""

handler = "x86_rstorssp"
jit_lowering = "arm64_rstorssp"
fallback = "zig_rstorssp"

neon_register_model = """
RSTORSSP manages CET shadow stack tokens. ARM64 has no hardware shadow
stack; software emulation required.
"""

neon_flag_model = """
CF cleared on successful restore, set on validation failure.
"""

neon_assembly = """
// NEON lowering: software-emulated CET shadow stack token restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "#UD if CET not enabled or LOCK prefix used.",
  "#GP if memory operand not 8-byte aligned or token validation fails.",
  "#SS if memory operand address in non-canonical form or stack segment limit exceeded.",
  "Not recognized in real-address or virtual-8086 mode."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
