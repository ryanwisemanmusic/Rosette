// ROTATE/RLWNMX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "M", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "GPR[RB]", operand_4 = "MB" },
]

source_isa = "ppc"
name = "rlwnmx"
mnemonic = "rlwnm"
category = "integer_rotate"
operation = "rA = ROTL32(rS, rB) & MASK(MB, ME)"

form = "M"
primary_opcode = 23
opcode_pattern = "0x5c000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x5c000000", form = "rlwnm[Rc] [RA], [RS], [RB], [MB], [ME]", op_en = "M" }
]

reads = ["GPR[RS]", "GPR[RB]", "MB", "ME"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
n <- (rB)[59:63]
r <- ROTL32((rS)[32:63], n)
m <- MASK(MB+32, ME+32)
rA <- r & m
"""

handler = "ppc_rlwnmx"
jit_lowering = "arm64_ppc_rlwnmx"

