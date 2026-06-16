// SET/UMONITOR.inc
// Source contract: UMONITOR — monitoring.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/UMONITOR.inc"
x86_handler = "x86_umonitor"
neon_lowering = "arm64_umonitor"
lowering_kind = "arm64_documented_contract"

name = "UMONITOR"
aliases = []
category = "monitoring"
feature = "UINTR"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "F3 0F 01 C9", form = "UMONITOR eax, ecx, edx", op_en = "ZO", feature = "UINTR", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Sets up monitoring for user-level address range for the UMWAIT instruction.
"""

handler = "x86_umonitor"
jit_lowering = "arm64_umonitor"
fallback = "zig_umonitor"

neon_register_model = """
x86 GPR mapped to ARM64 xN. UMONITOR is a monitoring instruction.
"""

neon_flag_model = """
No x86 flags are modified by UMONITOR.
"""

neon_assembly = """
// NEON lowering: user monitor stub (not supported on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
