// SAVE/SAVEPREVSSP.inc
// Source contract: SAVEPREVSSP — Save Previous Shadow Stack Pointer (CET_SS).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SAVE/SAVEPREVSSP.inc"
x86_handler = "x86_saveprevssp"
neon_lowering = "arm64_saveprevssp"
lowering_kind = "arm64_documented_contract"

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
Push a restore-shadow-stack token on the previous shadow stack at the next
8-byte aligned boundary. The previous SSP is obtained from the previous-ssp
token at the top of the current shadow stack.
"""

handler = "x86_saveprevssp"
jit_lowering = "arm64_saveprevssp"
fallback = "zig_saveprevssp"

neon_register_model = """
SAVEPREVSSP manages CET shadow stack tokens. ARM64 has no hardware shadow
stack; software emulation required.
"""

neon_flag_model = """
SAVEPREVSSP does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated CET shadow stack token push.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "#UD if CET not enabled or LOCK prefix used.",
  "#GP if SSP not 8-byte aligned or previous-ssp token invalid.",
  "Not recognized in real-address or virtual-8086 mode."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
