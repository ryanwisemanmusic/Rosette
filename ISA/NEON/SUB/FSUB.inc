// SUB/FSUB.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/FSUB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
FSUB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: x87_fpu_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/FSUB.inc"
x86_handler = "x86_fsub"
neon_lowering = "arm64_neon_fsub_scalar"
lowering_kind = "neon_scalar_float"


name = "FSUB"
category = "x87_fpu_subtract"
feature = "x87"
element_type = "f80"

encodings = [
  { opcode = "1E 63 80 30", form = "FSUB Sd, Sn, Sm", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_fsub_sd_sn_sm" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_fsub"
jit_lowering = "arm64_neon_fsub_scalar"


neon_register_model = """
x87 FPU stack registers are mapped onto ARM64 v registers; precision and rounding are preserved by the lowering.
"""

neon_flag_model = """
x87 FPU status flags are preserved through Rosette x87 floating-point side-effect handlers.
"""

neon_assembly = """
fsub sD, sN, sM
bl rosette_apply_x87_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
