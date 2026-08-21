// SYSTEM/SUBFICX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "SIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "subficx"
mnemonic = "subfic"
category = "system_supervisor"
operation = "subficx: supervisor / machine-state operation"

form = "D"
primary_opcode = 8
opcode_pattern = "0x20000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x20000000", form = "subfic [RD], [RA], [SIMM]", op_en = "D" }
]

reads = ["GPR[RA]", "SIMM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
subficx manipulates supervisor state (MSR, segment registers, or the TLB). Rosette models it against the Xbox 360 kernel view of machine state rather than real hardware.
"""

handler = "ppc_subficx"
jit_lowering = "arm64_ppc_subficx"

