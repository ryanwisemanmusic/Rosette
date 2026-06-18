// INTERRUPT/INT1.inc
// ARM64/NEON mirror generated from ISA/x86/INTERRUPT/INT1.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INTERRUPT/INT1.inc"
x86_handler = "x86_int1"
neon_lowering = "arm64_debug_trap"
lowering_kind = "arm64_documented_contract"

name = "INT1"
aliases = ["ICEBP"]
category = "interrupt"
feature = "system"
element_type = "system"
element_size = 0

encodings = [
  { opcode = "F1", form = "INT1", op_en = "ZO", feature = "system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

reads = ["IDTR", "CS", "RIP", "RFLAGS", "RSP"]
writes = ["CS", "RIP", "RFLAGS", "RSP"]
flags_read = ["IF", "TF", "AC"]
flags_written = ["IF", "TF", "AC"]
implicit_operands = ["IDT", "stack", "debug_exception"]

semantic_general = """
Generates a debug exception (#DB). The ICEBP mnemonic is an alternate name for opcode F1.
"""

handler = "x86_int1"
jit_lowering = "arm64_debug_trap"
fallback = "zig_int1"

neon_register_model = """
INT1 changes control flow through debug-exception delivery. ARM64 lowering must enter Rosette's debug/interrupt dispatcher.
"""

neon_flag_model = """
Debug-trap delivery follows the interrupt-gate flag side effects selected by the emulated IDT descriptor.
"""

neon_assembly = """
// ARM64 lowering: branch to Rosette debug trap dispatcher
bl rosette_x86_debug_trap
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
