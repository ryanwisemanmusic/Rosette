// SYSTEM/SUBFICX.inc
// ARM64/NEON translation mirror generated from ISA/ppc/SYSTEM/SUBFICX.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "SYSTEM/SUBFICX.inc"
ppc_handler = "ppc_subficx"
neon_lowering = "arm64_ppc_subficx"
lowering_kind = "system_dispatch"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "D", operand_1 = "GPR[RD]", operand_2 = "GPR[RA]", operand_3 = "SIMM", operand_4 = "N/A" },
]

name = "subficx"
mnemonic = "subfic"
category = "system_supervisor"
operation = "subficx: supervisor / machine-state operation"

form = "D"
primary_opcode = 8
opcode_pattern = "0x20000000"
opcode_mask = "0xfc000000"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x20000000", form = "subfic [RD], [RA], [SIMM]", op_en = "D" }
]

reads = ["GPR[RA]", "SIMM"]
writes = ["GPR[RD]"]
flags_written = ["none"]
special_registers = ["none"]

semantic = """
subficx manipulates supervisor state (MSR, segment registers, or the TLB). Rosette models it against the Xbox 360 kernel view of machine state rather than real hardware.
"""

handler = "ppc_subficx"
jit_lowering = "arm64_ppc_subficx"


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
bl rosette_ppc_subficx
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

