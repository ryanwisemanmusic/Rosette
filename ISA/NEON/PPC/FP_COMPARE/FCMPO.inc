// FP_COMPARE/FCMPO.inc
// ARM64/NEON translation mirror generated from ISA/ppc/FP_COMPARE/FCMPO.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "FP_COMPARE/FCMPO.inc"
ppc_handler = "ppc_fcmpo"
neon_lowering = "arm64_ppc_fcmpo"
lowering_kind = "neon_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "CR[CRFD]", operand_2 = "FPR[FA]", operand_3 = "FPR[FB]", operand_4 = "N/A" },
]

name = "fcmpo"
mnemonic = "fcmpo"
category = "floating_point_compare"
operation = "CR[crfD] = ordered compare(frA, frB)"

form = "X"
primary_opcode = 63
opcode_pattern = "0xfc000040"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0xfc000040", form = "fcmpo [CRFD], [FA], [FB]", op_en = "X" }
]

reads = ["FPR[FA]", "FPR[FB]"]
writes = ["CR[CRFD]"]
flags_written = ["CR[crfD]", "FPSCR.FPCC", "FPSCR.VXSNAN"]
special_registers = ["FPSCR"]

semantic = """
CR[crfD] <- {a<b, a>b, a=b, unordered}
FPSCR.FPCC updated; signals VXSNAN/VXVC as ordered comparison requires
"""

handler = "ppc_fcmpo"
jit_lowering = "arm64_ppc_fcmpo"


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
fcmpe dA, dB
bl rosette_ppc_pack_fp_cr
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

