// ROTATE/RLWINMX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/ROTATE/RLWINMX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "ROTATE/RLWINMX.inc"
ppc_handler = "ppc_rlwinmx"
neon_lowering = "arm64_ppc_rlwinmx"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "M", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "MB" },
]

name = "rlwinmx"
mnemonic = "rlwinm"
category = "integer_rotate"
operation = "rA = ROTL32(rS, SH) & MASK(MB, ME)"

form = "M"
primary_opcode = 21
opcode_pattern = "0x54000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x54000000", form = "rlwinm[Rc] [RA], [RS], [SH], [MB], [ME]", op_en = "M" }
]

reads = ["GPR[RS]", "SH", "MB", "ME"]
writes = ["GPR[RA]"]
flags_written = ["CR0 (when Rc=1)"]
special_registers = ["none"]

semantic = """
n <- SH
r <- ROTL32((rS)[32:63], n)
m <- MASK(MB+32, ME+32)
rA <- r & m
"""

handler = "ppc_rlwinmx"
jit_lowering = "arm64_ppc_rlwinmx"


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
ror wT, wS, #(32-SH)
and xA, xT, #MASK
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

