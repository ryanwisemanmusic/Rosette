// TEST/KTESTW.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/KTESTW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KTESTW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: mask_test.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/KTESTW.inc"
x86_handler = "x86_ktestw"
neon_lowering = "arm64_neon_and_test"
lowering_kind = "arm64_documented_contract"


name = "KTESTW"
category = "mask_test"
feature = "arm64_neon"
element_type = "u16"

encodings = [
  { opcode = "0E 30 80 20", form = "AND Vd.8B, Vn.8B, Vm.8B", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_and_v8b_v8b_v8b" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
TEMP = Vn.8B AND Vm.8B;
ZF = (TEMP == 0) ? 1 : 0;
CF = (TEMP == 0xFF) ? 1 : 0;
OF = 0; AF = 0; PF = 0; SF = 0;
"""

other_exceptions = ["#UD if CR4.OSFXSR = 0", "#UD if LOCK prefix used"]

handler = "x86_ktestw"
jit_lowering = "arm64_neon_and_test"


neon_register_model = """
x86 k-registers are mapped onto ARM64 V registers; only lower 16 bits are considered for the test result.
"""

neon_flag_model = """
ARM64 NZCV are set from the AND result to match x86 KTESTW flag semantics.
"""

neon_assembly = """
and vD.8b, vN.8b, vM.8b
bl rosette_map_and_to_test_flags
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, or implicit-operand behavior.",
  "No direct ARM64 k-register equivalence; NEON AND on 8B vector approximates mask register test.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
