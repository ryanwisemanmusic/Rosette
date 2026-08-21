// VMX128/VCMPEQUW128.inc
// ARM64/NEON translation mirror generated from ISA/ppc/VMX128/VCMPEQUW128.inc.
// This file preserves the full PowerPC instruction contract, then appends the ARM64/NEON lowering contract.

source_isa = "ppc"
target_isa = "arm64_neon"
ppc_table = "VMX128/VCMPEQUW128.inc"
ppc_handler = "ppc_vcmpequw128"
neon_lowering = "arm64_ppc_vcmpequw128_helper"
lowering_kind = "fallback"


// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "VX128_R", operand_1 = "VR[VD]", operand_2 = "VR[VA]", operand_3 = "VR[VB]", operand_4 = "N/A" },
]

name = "vcmpequw128"
mnemonic = "vcmpequw128"
category = "vector_vmx128"
operation = "vcmpequw128: Xbox 360 VMX128 vector operation on the 128-entry vector register file"

form = "VX128_R"
primary_opcode = 6
opcode_pattern = "0x18000200"
opcode_mask = "0xfc0007f3"
instruction_length = 4
byte_order = "big_endian"

encodings = [
  { opcode = "0x18000200", form = "vcmpequw128[Rc] [VD], [VA], [VB]", op_en = "VX128_R" }
]

reads = ["VR[VA]", "VR[VB]"]
writes = ["VR[VD]"]
flags_written = ["CR6 (when Rc=1)"]
special_registers = ["VSCR"]

semantic = """
vcmpequw128 decodes a VMX128 (VX128_R) encoding whose register fields are split across the instruction word; the operation is the VMX128 form of the corresponding AltiVec instruction.
"""

handler = "ppc_vcmpequw128"
jit_lowering = "arm64_ppc_vcmpequw128_helper"


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
bl rosette_ppc_vcmpequw128
"""

neon_notes = [
  "The PowerPC encoding, operands, semantic text, and register/condition contract above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the PowerPC register, CR/XER/FPSCR/VSCR, trap, reservation, or big-endian memory behavior.",
  "Runtime ABI validation checks both the PPC table shape and this NEON lowering shape."
]

abi_contract = ["ppc_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

