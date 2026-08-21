// LOAD/LD.inc
// ARM64/NEON translation mirror generated from ISA/ppc/LOAD/LD.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "LOAD/LD.inc"
ppc_handler = "ppc_ld"
neon_lowering = "arm64_ppc_ld"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DS", operand_1 = "GPR[RD]", operand_2 = "ds", operand_3 = "GPR[RA] or 0", operand_4 = "N/A" },
]

name = "ld"
mnemonic = "ld"
category = "memory_load"
operation = "rD = EXTZ(MEM64[(rA|0) + EXTS(d)]) loaded big-endian"

form = "DS"
primary_opcode = 58
opcode_pattern = "0xe8000000"
opcode_mask = "0xfc000003"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xe8000000", form = "ld [RD], [ds]([RA0])", op_en = "DS" }
]

reads = ["ds", "GPR[RA]", "MEM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
EA <- (rA|0) + EXTS(d)
rD <- EXTZ(MEM(EA, 8))
"""

handler = "ppc_ld"
jit_lowering = "arm64_ppc_ld"


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
ldr xD, [xEA]
rev xD, xD
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

