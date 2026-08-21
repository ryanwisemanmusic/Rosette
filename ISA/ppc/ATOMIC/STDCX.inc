// ATOMIC/STDCX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "stdcx"
mnemonic = "stdcx."
category = "memory_atomic"
operation = "conditionally store rS to MEM64[(rA|0) + rB]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c0001ad"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c0001ad", form = "stdcx. [RS], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["CR0"]
special_registers = ["reservation (address + valid bit)"]

semantic = """
EA <- (rA|0) + (rB)
if RESERVE and RESERVE_ADDR = EA then
  MEM(EA, 8) <- (rS)
  CR0 <- 0b001 || XER.SO
else
  CR0 <- 0b000 || XER.SO
RESERVE <- 0
"""

handler = "ppc_stdcx"
jit_lowering = "arm64_ppc_stdcx"

