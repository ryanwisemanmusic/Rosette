// ROTATE/RLDCLX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "MDS", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "GPR[RB]", operand_4 = "MB" },
]

source_isa = "ppc"
name = "rldclx"
mnemonic = "rldcl"
category = "integer_rotate"
operation = "rA = ROTL64(rS, rB) & MASK(MB, 63)"

form = "MDS"
primary_opcode = 30
opcode_pattern = "0x78000010"
opcode_mask = "0xfc00001e"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x78000010", form = "rldcl[Rc] [RA], [RS], [RB], [MB]", op_en = "MDS" }
]

reads = ["GPR[RS]", "GPR[RB]", "MB"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
n <- (rB)[58:63]
r <- ROTL64((rS), n)
m <- MASK(MB, 63)
rA <- r & m
"""

handler = "ppc_rldclx"
jit_lowering = "arm64_ppc_rldclx"

