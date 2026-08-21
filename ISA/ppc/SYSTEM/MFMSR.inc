// SYSTEM/MFMSR.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RD]", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "mfmsr"
mnemonic = "mfmsr"
category = "system_supervisor"
operation = "mfmsr: supervisor / machine-state operation"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0000a6"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0000a6", form = "mfmsr [RD]", op_en = "X" }
]

reads = ["none"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
mfmsr manipulates supervisor state (MSR, segment registers, or the TLB). Rosette models it against the Xbox 360 kernel view of machine state rather than real hardware.
"""

handler = "ppc_mfmsr"
jit_lowering = "arm64_ppc_mfmsr"

