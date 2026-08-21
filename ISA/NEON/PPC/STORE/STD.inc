// STORE/STD.inc
// ARM64/NEON translation mirror generated from ISA/ppc/STORE/STD.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "STORE/STD.inc"
ppc_handler = "ppc_std"
neon_lowering = "arm64_ppc_std"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DS", operand_1 = "GPR[RS]", operand_2 = "ds", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

name = "std"
mnemonic = "std"
category = "memory_store"
operation = "MEM64[(rA|0) + EXTS(d)] = rS stored big-endian"

form = "DS"
primary_opcode = 62
opcode_pattern = "0xf8000000"
opcode_mask = "0xfc000003"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xf8000000", form = "std [RS], [ds]([RA0])", op_en = "DS" }
]

reads = ["GPR[RS]", "ds", "GPR[RA]"]
writes = ["MEM"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
MEM(EA, 8) <- (rS)[0:63]
"""

handler = "ppc_std"
jit_lowering = "arm64_ppc_std"


neon_register_model = """
PowerPC architected state lives in the Rosette PPC register file: GPR0-31 and
LR/CTR/XER as 64-bit slots, FPR0-31 as IEEE doubles, VR0-127 as 128-bit lanes,
and CR as eight 4-bit fields. The lowering loads the operands it needs into
ARM64 temporaries, computes, and writes the architected slot back explicitly.
"""

neon_flag_model = """
ARM64 NZCV is repacked into the PowerPC condition contract named by
flags_written above: CR field bits are ordered LT, GT, EQ, SO, with SO copied
from XER; XER.CA and XER.OV are produced from the ARM64 carry/overflow flags.
"""

neon_assembly = """
rev xD, xD
str xS, [xEA]
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

