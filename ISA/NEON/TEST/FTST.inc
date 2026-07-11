// TEST/FTST.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/FTST.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
FTST: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: x87_fpu_test.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/FTST.inc"
x86_handler = "x86_ftst"
neon_lowering = "arm64_neon_fcmp_sd"
lowering_kind = "neon_scalar"


name = "FTST"
category = "x87_fpu_test"
feature = "arm64_neon"
element_type = "f80"

encodings = [
  { opcode = "1E 63 80 30", form = "FCMP Dd, 0.0", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_fcmp_dd_zero" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Dd (r)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_neon = """
FCMP Dd, 0.0;
NZCV flags set per comparison result;
x87 C3, C2, C0 flags mapped from ARM64 NZCV;
"""

other_exceptions = ["#IS if FPU stack underflow (C1 = 1, exception pending)", "#D x87 FPU stack underflow"]

handler = "x86_ftst"
jit_lowering = "arm64_neon_fcmp_sd"


neon_register_model = """
x87 ST(0) is mapped to ARM64 Dd register; FPU status word flags C3/C2/C0 are synthesized from ARM64 NZCV.
"""

neon_flag_model = """
ARM64 FCMP sets NZCV natively; x87 C3/C2/C0 are derived from NZCV: C3 = Z, C2 = (denormal or zero), C0 = N.
"""

neon_assembly = """
fcmp dD, #0.0
bl rosette_map_fcmp_to_x87_flags
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x87 register, flag, exception, or implicit-operand behavior.",
  "FTST compares ST(0) against +0.0; ARM64 FCMP with #0.0 provides equivalent comparison with NZCV output.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
