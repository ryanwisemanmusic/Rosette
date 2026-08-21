// SHIFT/SRADIX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/SHIFT/SRADIX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "SHIFT/SRADIX.inc"
ppc_handler = "ppc_sradix"
neon_lowering = "arm64_ppc_sradix"
lowering_kind = "arm64_scalar"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "XS", operand_1 = "GPR[RA]", operand_2 = "GPR[RS]", operand_3 = "SH", operand_4 = "N/A" },
]

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
asr xA, xS, #SH
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

