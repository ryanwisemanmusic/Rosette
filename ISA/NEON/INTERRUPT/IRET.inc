// INTERRUPT/IRET.inc
// ARM64/NEON mirror generated from ISA/x86/INTERRUPT/IRET.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INTERRUPT/IRET.inc"
x86_handler = "x86_iret"
neon_lowering = "arm64_iret"
lowering_kind = "arm64_documented_contract"

// INTERRUPT/IRET.inc
// Source contract: IRET/IRETD/IRETQ — Interrupt Return.

name = "IRET"
aliases = ["IRETD", "IRETQ"]
category = "interrupt"
feature = "system"
element_type = "system"
element_size = 0

encodings = [
  { opcode = "CF", form = "IRET", op_en = "ZO", feature = "system", vector_length = 0, encoding = "legacy" },
  { opcode = "CF", form = "IRETD", op_en = "ZO", feature = "system", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + CF", form = "IRETQ", op_en = "ZO", feature = "system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

reads = ["CS", "RIP", "RFLAGS", "RSP"]
writes = ["CS", "RIP", "RFLAGS", "RSP"]
flags_read = ["NT", "VM", "IOPL", "IF", "RF"]
flags_written = ["NT", "IF", "RF", "TF", "AC", "VM", "IOPL", "VIP", "VIF"]
implicit_operands = ["stack", "TSS"]

semantic_general = """
Returns program control from an exception or interrupt handler. Pops return address, code segment selector, and EFLAGS image from the stack, then resumes execution of the interrupted program.
"""

handler = "x86_iret"
jit_lowering = "arm64_iret"
fallback = "zig_iret"

neon_register_model = """
IRET is a system interrupt return instruction.
"""

neon_flag_model = """
IRET restores EFLAGS/RFLAGS from the stack image.
"""

neon_assembly = """
// NEON lowering: IRET stub (system interrupt return)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
