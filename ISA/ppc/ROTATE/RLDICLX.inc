// ROTATE/RLDICLX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "MD", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "MB" },
]

source_isa = "ppc"
name = "rldiclx"
mnemonic = "rldicl"
category = "integer_rotate"
operation = "rA = ROTL64(rS, SH) & MASK(MB, 63)"

form = "MD"
primary_opcode = 30
opcode_pattern = "0x78000000"
opcode_mask = "0xfc00001c"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x78000000", form = "rldicl[Rc] [RA], [RS], [SH], [MB]", op_en = "MD" }
]

reads = ["GPR[RS]", "SH", "MB"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
r <- ROTL64((rS), SH)
m <- MASK(MB, 63)
rA <- r & m
"""

handler = "ppc_rldiclx"
jit_lowering = "arm64_ppc_rldiclx"

