// BRANCH/BCLRX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/BRANCH/BCLRX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "BRANCH/BCLRX.inc"
ppc_handler = "ppc_bclrx"
neon_lowering = "arm64_ppc_bclrx"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XL", operand_1 = "BO", operand_2 = "BI", operand_3 = "N/A", operand_4 = "N/A" },
]

name = "bclrx"
mnemonic = "bclr"
category = "control_flow"
operation = "conditionally branch to LR"

form = "XL"
primary_opcode = 19
opcode_pattern = "0x4c000020"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x4c000020", form = "bclr[LK] [BO], [BI]", op_en = "XL" }
]

reads = ["BO", "CR[BI]"]
writes = ["none"]
flags_written = ["CTR (when BO decrements)"]
special_registers = ["LR (when LK=1)", "LR (source)", "CTR (decrement)"]

semantic = """
ctr_ok & cond_ok as in bc; NIA <- LR[0:61] || 0b00
if LK then LR <- CIA + 4
"""

handler = "ppc_bclrx"
jit_lowering = "arm64_ppc_bclrx"


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
br xLR
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

