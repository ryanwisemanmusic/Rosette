// CMP/CMPI.inc
// ARM64/NEON translation mirror generated from ISA/ppc/CMP/CMPI.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "CMP/CMPI.inc"
ppc_handler = "ppc_cmpi"
neon_lowering = "arm64_ppc_cmpi"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "CR[CRFD]", operand_2 = "L", operand_3 = "GPR[RA]", operand_4 = "SIMM" },
]

name = "cmpi"
mnemonic = "cmpi"
category = "integer_compare"
operation = "CR[crfD] = signed compare(rA, SIMM)"

form = "D"
primary_opcode = 11
opcode_pattern = "0x2c000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x2c000000", form = "cmpi [CRFD], [L], [RA], [SIMM]", op_en = "D" }
]

reads = ["L", "GPR[RA]", "SIMM"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]"]
special_registers = ["none"]

semantic = """
a <- if L then (rA) else EXTS((rA)[32:63])
CR[crfD] <- {a<SIMM, a>SIMM, a=SIMM, XER.SO}
"""

handler = "ppc_cmpi"
jit_lowering = "arm64_ppc_cmpi"


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
cmp xA, #SIMM
bl rosette_ppc_pack_cr_signed
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

