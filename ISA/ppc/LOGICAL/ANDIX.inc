// LOGICAL/ANDIX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "UIMM", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "andix"
mnemonic = "andi."
category = "integer_logical"
operation = "rA = rS & UIMM, CR0 updated"

form = "D"
primary_opcode = 28
opcode_pattern = "0x70000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x70000000", form = "andi. [RA], [RS], [UIMM]", op_en = "D" }
]

reads = ["GPR[RS]", "UIMM"]
writes = ["GPR[RA]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
rA <- (rS) & (0x0000 || UIMM)
CR0 <- cmp(rA, 0)
"""

handler = "ppc_andix"
jit_lowering = "arm64_ppc_andix"

