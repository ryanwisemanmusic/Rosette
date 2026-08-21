// ROTATE/RLWIMIX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "M", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "MB" },
]

source_isa = "ppc"
name = "rlwimix"
mnemonic = "rlwimi"
category = "integer_rotate"
operation = "rA = (ROTL32(rS, SH) & M) | (rA & ~M)"

form = "M"
primary_opcode = 20
opcode_pattern = "0x50000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x50000000", form = "rlwimi[Rc] [RA], [RS], [SH], [MB], [ME]", op_en = "M" }
]

reads = ["GPR[RS]", "SH", "MB", "ME"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
r <- ROTL32((rS)[32:63], SH)
m <- MASK(MB+32, ME+32)
rA <- (r & m) | ((rA) & ~m)
"""

handler = "ppc_rlwimix"
jit_lowering = "arm64_ppc_rlwimix"

