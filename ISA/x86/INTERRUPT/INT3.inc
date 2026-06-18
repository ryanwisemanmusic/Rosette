// INTERRUPT/INT3.inc
// Source contract: INT3 — Breakpoint Trap.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INTERRUPT/INT3.inc"
x86_handler = "x86_int3"
neon_lowering = "arm64_breakpoint_trap"
lowering_kind = "arm64_documented_contract"

name = "INT3"
aliases = []
category = "interrupt"
feature = "system"
element_type = "system"
element_size = 0

encodings = [
  { opcode = "CC", form = "INT3", op_en = "ZO", feature = "system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

reads = ["IDTR", "CS", "RIP", "RFLAGS", "RSP"]
writes = ["CS", "RIP", "RFLAGS", "RSP"]
flags_read = ["IF", "TF", "AC"]
flags_written = ["IF", "TF", "AC"]
implicit_operands = ["IDT", "stack", "breakpoint_exception"]

semantic_general = """
Generates a breakpoint exception (#BP) using the one-byte CC encoding intended for software breakpoints.
"""

handler = "x86_int3"
jit_lowering = "arm64_breakpoint_trap"
fallback = "zig_int3"

neon_register_model = """
INT3 changes control flow through breakpoint delivery. ARM64 lowering must enter Rosette's breakpoint/interrupt dispatcher.
"""

neon_flag_model = """
Breakpoint delivery follows the interrupt-gate flag side effects selected by the emulated IDT descriptor.
"""

neon_assembly = """
// ARM64 lowering: branch to Rosette breakpoint dispatcher
bl rosette_x86_breakpoint_trap
"""

neon_notes = [
  "INT3 is one byte so debuggers can patch over any first instruction byte without overwriting the rest of the instruction."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
