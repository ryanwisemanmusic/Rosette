// VMX_PERMUTE/VSLDOI.inc
// ARM64/NEON translation mirror generated from ISA/ppc/VMX_PERMUTE/VSLDOI.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "VMX_PERMUTE/VSLDOI.inc"
ppc_handler = "ppc_vsldoi"
neon_lowering = "arm64_ppc_vsldoi"
lowering_kind = "neon_vector"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VA", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "SHB" },
]

name = "vsldoi"
mnemonic = "vsldoi"
category = "vector_permute"
operation = "vD = ((vA || vB) << (SHB * 8))[0:127]"

form = "VA"
primary_opcode = 4
opcode_pattern = "0x1000002c"
opcode_mask = "0xfc00003f"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x1000002c", form = "vsldoi [VD], [VA], [VB], [SHB]", op_en = "VA" }
]

reads = ["VR[VA]", "VR[VB]", "SHB"]
writes = ["VR[VD]"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
vD = ((vA || vB) << (SHB * 8))[0:127]
"""

handler = "ppc_vsldoi"
jit_lowering = "arm64_ppc_vsldoi"


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
ext vD.16b, vA.16b, vB.16b, #SHB
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

