// INTERRUPT/INT.inc
// Source contract: INT — Call to Interrupt Procedure.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INTERRUPT/INT.inc"
x86_handler = "x86_int"
neon_lowering = "arm64_interrupt_trap"
lowering_kind = "arm64_documented_contract"

name = "INT"
aliases = []
category = "interrupt"
feature = "system"
element_type = "system"
element_size = 0

encodings = [
  { opcode = "CD ib", form = "INT imm8", op_en = "I", feature = "system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  I = ["imm8"]
}

reads = ["IDTR", "CS", "RIP", "RFLAGS", "RSP"]
writes = ["CS", "RIP", "RFLAGS", "RSP"]
flags_read = ["IOPL", "VM", "IF", "TF", "AC"]
flags_written = ["IF", "TF", "AC"]
implicit_operands = ["IDT", "stack", "vector_number"]

semantic_general = """
Generates a software interrupt using an 8-bit vector number. The processor selects the corresponding IDT descriptor, pushes return state, and transfers control to the interrupt handler.
"""

handler = "x86_int"
jit_lowering = "arm64_interrupt_trap"
fallback = "zig_interrupt"

neon_register_model = """
INT changes control flow through emulated IDT delivery. ARM64 lowering must enter Rosette's interrupt/exception dispatcher rather than emitting a data-processing instruction.
"""

neon_flag_model = """
Interrupt delivery clears IF, TF, and AC where architecturally required by the selected mode and gate type.
"""

neon_assembly = """
// ARM64 lowering: branch to Rosette interrupt dispatcher with vector imm8
bl rosette_x86_interrupt_dispatch
"""

neon_notes = [
  "INT is architectural control-flow and privilege-state behavior, represented as a documented contract until Rosette's OS/IDT model owns the transition."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
