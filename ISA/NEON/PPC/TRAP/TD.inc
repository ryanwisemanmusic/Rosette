// TRAP/TD.inc
// ARM64/NEON translation mirror generated from ISA/ppc/TRAP/TD.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "TRAP/TD.inc"
ppc_handler = "ppc_td"
neon_lowering = "arm64_ppc_td"
lowering_kind = "system_dispatch"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "X", operand_1 = "TO", operand_2 = "GPR[RA]", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

name = "td"
mnemonic = "td"
category = "control_trap"
operation = "trap if the 64-bit compare of rA and rB matches TO"

form = "X"
primary_opcode = 31
opcode_pattern = "0x7c000088"
opcode_mask = "0xfc0007fe"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x7c000088", form = "td [TO], [RA], [RB]", op_en = "X" }
]

reads = ["TO", "GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
if any TO condition holds for ((rA), (rB)) then raise trap
"""

handler = "ppc_td"
jit_lowering = "arm64_ppc_td"


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
cmp xA, xB
b.cond .Lno_trap
bl rosette_ppc_trap
.Lno_trap:
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

