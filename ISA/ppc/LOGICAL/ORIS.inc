// LOGICAL/ORIS.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "UIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "oris"
mnemonic = "oris"
category = "integer_logical"
operation = "rA = rS | (UIMM << 16)"

form = "D"
primary_opcode = 25
opcode_pattern = "0x64000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x64000000", form = "oris [RA], [RS], [UIMM]", op_en = "D" }
]

reads = ["GPR[RS]", "UIMM"]
writes = ["GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rA <- (rS) | (UIMM || 0x0000)
"""

handler = "ppc_oris"
jit_lowering = "arm64_ppc_oris"

