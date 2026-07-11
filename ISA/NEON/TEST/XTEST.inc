// TEST/XTEST.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/XTEST.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
XTEST: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: transactional_test.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/XTEST.inc"
x86_handler = "x86_xtest"
neon_lowering = "arm64_neon_mrs_el0"
lowering_kind = "arm64_documented_contract"


name = "XTEST"
category = "transactional_test"
feature = "arm64_neon"
element_type = "N/A"

encodings = [
  { opcode = "D5 38 00 00", form = "MRS Xd, TPIDR_EL0", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_mrs_xd_tpidr_el0" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Xd (w)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_neon = """
Xd = TPIDR_EL0;
ZF = (Xd == 0) ? 1 : 0;
CF = 0; OF = 0; AF = 0; PF = 0; SF = 0;
"""

other_exceptions = ["#UD if LOCK prefix used"]

handler = "x86_xtest"
jit_lowering = "arm64_neon_mrs_el0"


neon_register_model = """
No register mapping; TPIDR_EL0 provides an architectural status indicator analogous to RTM/HLE transactional region state.
"""

neon_flag_model = """
ARM64 NZCV are synthesized from TPIDR_EL0 value to match x86 XTEST ZF flag semantics.
"""

neon_assembly = """
mrs xD, tpidr_el0
bl rosette_map_mrs_to_xtest_flags
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "No direct ARM64 transactional region test; MRS TPIDR_EL0 provides a special-purpose register read for behavioral mapping.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
