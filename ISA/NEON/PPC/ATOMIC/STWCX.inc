// ATOMIC/STWCX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/ATOMIC/STWCX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "ATOMIC/STWCX.inc"
ppc_handler = "ppc_stwcx"
neon_lowering = "arm64_ppc_stwcx"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "GPR[RS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

name = "stwcx"
mnemonic = "stwcx."
category = "memory_atomic"
operation = "conditionally store rS to MEM32[(rA|0) + rB]"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00012d"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00012d", form = "stwcx. [RS], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RS]", "GPR[RA]", "GPR[RB]"]
writes = ["MEM"]
flags_written = ["CR0"]
special_registers = ["reservation (address + valid bit)"]

semantic = """
EA <- (rA|0) + (rB)
if RESERVE and RESERVE_ADDR = EA then
  MEM(EA, 4) <- (rS)
  CR0 <- 0b001 || XER.SO
else
  CR0 <- 0b000 || XER.SO
RESERVE <- 0
"""

handler = "ppc_stwcx"
jit_lowering = "arm64_ppc_stwcx"


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
rev wD, wD
stlxr wT, wS, [xEA]
bl rosette_ppc_store_conditional_cr0
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

