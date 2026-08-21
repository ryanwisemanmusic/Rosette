// ROTATE/RLDICRX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "MD", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "ME" },
]

source_isa = "ppc"
name = "rldicrx"
mnemonic = "rldicr"
category = "integer_rotate"
operation = "rA = ROTL64(rS, SH) & MASK(0, ME)"

form = "MD"
primary_opcode = 30
opcode_pattern = "0x78000004"
opcode_mask = "0xfc00001c"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x78000004", form = "rldicr[Rc] [RA], [RS], [SH], [ME]", op_en = "MD" }
]

reads = ["GPR[RS]", "SH", "ME"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
r <- ROTL64((rS), SH)
m <- MASK(0, ME)
rA <- r & m
"""

handler = "ppc_rldicrx"
jit_lowering = "arm64_ppc_rldicrx"

