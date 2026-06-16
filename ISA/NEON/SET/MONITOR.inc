// SET/MONITOR.inc
// ARM64/NEON mirror generated from ISA/x86/SET/MONITOR.inc.

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
simd_fp_exceptions = [],

semantic_general = """
Sets up a linear address range to be monitored by the MONITOR/MWAIT pair for address writes.
"""

handler = "x86_monitor"
jit_lowering = "arm64_monitor"
fallback = "zig_monitor"

neon_register_model = """
MONITOR is a monitoring instruction. No ARM64-specific registers modified.
"""

neon_flag_model = """
No x86 flags modified by MONITOR.
"""

neon_assembly = """
// NEON lowering: monitor stub (not supported on ARM64)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
