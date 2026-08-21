// SHIFT/SLDX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sldx"
mnemonic = "sld"
category = "integer_shift"
operation = "rA = rS << (rB & 127), >=64 clears"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000036"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000036", form = "sld[Rc] [RA], [RS], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RB]"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
n <- (rB)[57:63]
rA <- if n < 64 then (rS) << n else 0
"""

handler = "ppc_sldx"
jit_lowering = "arm64_ppc_sldx"

