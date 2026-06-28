// INTERRUPT/SIDT.inc
// ARM64/NEON mirror generated from ISA/x86/INTERRUPT/SIDT.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INTERRUPT/SIDT.inc"
x86_handler = "x86_sidt"
neon_lowering = "arm64_sidt"
lowering_kind = "arm64_documented_contract"

// INTERRUPT/SIDT.inc
// Source contract: SIDT — Store Interrupt Descriptor Table Register.

name = "SIDT"
aliases = []
category = "system"
feature = "system"
element_type = "system"
element_size = 0

encodings = [
  { opcode = "0F 01 /1", form = "SIDT m", op_en = "M", feature = "system", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

reads = ["IDTR"]
writes = ["DST"]
flags_read = []
flags_written = []
implicit_operands = ["IDTR"]

semantic_general = """
Stores the content of the interrupt descriptor table register (IDTR) to the destination memory operand.
"""

handler = "x86_sidt"
jit_lowering = "arm64_sidt"
fallback = "zig_sidt"

neon_register_model = """
SIDT is a system register store instruction.
"""

neon_flag_model = """
SIDT does not modify flags.
"""

neon_assembly = """
// NEON lowering: SIDT stub (system register store)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
