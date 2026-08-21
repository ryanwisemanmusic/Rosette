// VMX128/STVRX128.inc
// ARM64/NEON translation mirror generated from ISA/ppc/VMX128/STVRX128.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "VMX128/STVRX128.inc"
ppc_handler = "ppc_stvrx128"
neon_lowering = "arm64_ppc_stvrx128_helper"
lowering_kind = "fallback"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_1", operand_1 = "VR[VS]", operand_2 = "GPR[RA] or 0", operand_3 = "GPR[RB]", operand_4 = "N/A" },
]

name = "stvrx128"
mnemonic = "stvrx128"
category = "vector_vmx128"
operation = "stvrx128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_1"
primary_opcode = 4
opcode_pattern = "0x10000543"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x10000543", form = "stvrx128 [VS], [RA0], [RB]", op_en = "VX128_1" }
]

reads = ["VR[VS]", "GPR[RA]", "GPR[RB]"]
writes = ["none"]
flags_written = ["none"]
special_registers = ["VSCR"]

semantic = """
stvrx128 decodes a VMX128 (VX128_1) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_stvrx128"
jit_lowering = "arm64_ppc_stvrx128_helper"


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
bl rosette_ppc_stvrx128
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

