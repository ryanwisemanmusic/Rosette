// SYSTEM/MTMSR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mtmsr"
mnemonic = "mtmsr"
category = "system_supervisor"
operation = "mtmsr: supervisor / machine-state operation"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000124"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000124", form = "mtmsr [RS]", op_en = "X" }
]

reads = ["GPR[RS]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
mtmsr manipulates supervisor state (MSR, segment registers, or the TLB). Rosette models it against the Xbox 360 kernel view of machine state rather than real hardware.
"""

handler = "ppc_mtmsr"
jit_lowering = "arm64_ppc_mtmsr"

