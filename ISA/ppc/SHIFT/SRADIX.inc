// SHIFT/SRADIX.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XS", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "N/A" },
]

source_isa = "ppc"
name = "sradix"
mnemonic = "sradi"
category = "integer_shift"
operation = "rA = rS >> SH arithmetic, XER.CA set"

form = "XS"
primary_opcode = 31
opcode_pattern = "0x7c000674"
opcode_mask = "0xfc0007fc"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000674", form = "sradi[Rc] [RA], [RS], [SH]", op_en = "XS" }
]

reads = ["GPR[RS]", "SH"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)", "XER.CA"]
special_registers = ["none"]

semantic = """
rA <- (rS) >>si SH
XER.CA <- (rS < 0) and any 1 bits shifted out
"""

handler = "ppc_sradix"
jit_lowering = "arm64_ppc_sradix"

