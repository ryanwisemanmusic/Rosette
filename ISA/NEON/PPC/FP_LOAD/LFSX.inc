// FP_LOAD/LFSX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/FP_LOAD/LFSX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "FP_LOAD/LFSX.inc"
ppc_handler = "ppc_lfsx"
neon_lowering = "arm64_ppc_lfsx"
lowering_kind = "neon_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "FPR[FD]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

name = "lfsx"
mnemonic = "lfsx"
category = "floating_point_load"
operation = "frD = MEM32[EA] as a single-precision value converted to double"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c00042e"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c00042e", form = "lfsx [FD], [RA0], [RB]", op_en = "X" }
]

reads = ["GPR[RA]", "GPR[RB]", "MEM"]
writes = ["FPR[FD]"]
flags_written = ["none"]
special_registers = ["FPSCR"]

semantic = """
EA <- (rA|0) + displacement
frD <- DOUBLE(MEM(EA, 4))
"""

handler = "ppc_lfsx"
jit_lowering = "arm64_ppc_lfsx"


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
ldr wT, [xEA]
rev wT, wT
fmov sD, wT
fcvt dD, sD
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

