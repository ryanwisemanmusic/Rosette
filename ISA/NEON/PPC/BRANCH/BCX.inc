// BRANCH/BCX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/BRANCH/BCX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "BRANCH/BCX.inc"
ppc_handler = "ppc_bcx"
neon_lowering = "arm64_ppc_bcx"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "B", operand_1 = "BO", operand_2 = "BI", operand_3 = "BD", operand_4 = "N/A" },
]

name = "bcx"
mnemonic = "bc"
category = "control_flow"
operation = "conditionally branch to BD using BO/BI and CTR"

form = "B"
primary_opcode = 16
opcode_pattern = "0x40000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x40000000", form = "bc[LK][AA] [BO], [BI], [BD]", op_en = "B" }
]

reads = ["BO", "CR[BI]", "BD"]
writes = ["none"]
flags_written = ["CTR (when BO decrements)"]
special_registers = ["LR (when LK=1)", "CTR (decrement)"]

semantic = """
if not BO[2] then CTR <- CTR - 1
ctr_ok <- BO[2] | ((CTR != 0) ^ BO[3])
cond_ok <- BO[0] | (CR[BI] == BO[1])
if ctr_ok & cond_ok then NIA <- target
if LK then LR <- CIA + 4
"""

handler = "ppc_bcx"
jit_lowering = "arm64_ppc_bcx"


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
sub xCTR, xCTR, #1
cbz xCTR, .Lfall
b.cond #target
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

