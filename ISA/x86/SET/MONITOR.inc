// SET/MONITOR.inc
// Source contract: MONITOR — monitoring.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/MONITOR.inc"
x86_handler = "x86_monitor"
neon_lowering = "arm64_monitor"
lowering_kind = "arm64_documented_contract"

name = "MONITOR"
aliases = []
category = "monitoring"
feature = "SSE3"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 01 C8", form = "MONITOR eax, ecx, edx", op_en = "ZO", feature = "SSE3", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Sets up a linear address range to be monitored by the MONITOR/MWAIT pair for address writes.
"""

handler = "x86_monitor"
jit_lowering = "arm64_monitor"
fallback = "zig_monitor"

neon_register_model = """
x86 GPR mapped to ARM64 xN. MONITOR is a monitoring instruction.
"""

neon_flag_model = """
No x86 flags are modified by MONITOR.
"""

neon_assembly = """
// NEON lowering: monitor stub (not supported on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
