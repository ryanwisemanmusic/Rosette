// INTERRUPT/INTO.inc
// Source contract: INTO — Interrupt on Overflow.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INTERRUPT/INTO.inc"
x86_handler = "x86_into"
neon_lowering = "arm64_overflow_trap"
lowering_kind = "arm64_documented_contract"

name = "INTO"
aliases = []
category = "interrupt"
feature = "8086"
element_type = "system"
element_size = 0

encodings = [
  { opcode = "CE", form = "INTO", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy", mode64 = "invalid" }
]

operand_encoding = {
  ZO = []
}

reads = ["OF", "IDTR", "CS", "RIP", "RFLAGS", "RSP"]
writes = ["CS", "RIP", "RFLAGS", "RSP"]
flags_read = ["OF", "IF", "TF", "AC"]
flags_written = ["IF", "TF", "AC"]
implicit_operands = ["IDT", "stack", "overflow_exception"]

semantic_general = """
Generates overflow exception vector 4 when OF is set. If OF is clear, execution continues with no interrupt. INTO is invalid in 64-bit mode.
"""

handler = "x86_into"
jit_lowering = "arm64_overflow_trap"
fallback = "zig_into"

neon_register_model = """
INTO conditionally changes control flow through overflow-exception delivery. ARM64 lowering must test the emulated OF flag and dispatch vector 4 when set.
"""

neon_flag_model = """
If OF is clear, flags are unchanged. If OF is set, interrupt delivery follows the selected gate's architectural flag side effects.
"""

neon_assembly = """
// ARM64 lowering: test emulated OF, branch to Rosette overflow dispatcher when set
bl rosette_x86_overflow_trap_if_set
"""

neon_notes = [
  "INTO is not available in 64-bit mode; Rosette should raise #UD for this encoding when executing 64-bit code."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
