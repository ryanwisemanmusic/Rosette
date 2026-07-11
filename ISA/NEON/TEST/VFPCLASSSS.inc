// TEST/VFPCLASSSS.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/VFPCLASSSS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSSS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: fp_classify.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/VFPCLASSSS.inc"
x86_handler = "x86_vfpclassss"
neon_lowering = "arm64_neon_fclass_ss"
lowering_kind = "neon_scalar"


name = "VFPCLASSSS"
category = "fp_classify"
feature = "arm64_neon"
element_type = "f32"

encodings = [
  { opcode = "7E 30 C0 30", form = "FCMEQ Sd, Sn, Sm", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_fcmeq_sd_sn_sm" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Sd (w)", operand2 = "Sn (r)", operand3 = "Sm (r)", operand4 = "N/A" }
]

semantic_neon = """
IF FCMEQ(Sn, Sm) produces all-ones mask THEN
  classification bit 0 = 1;
ELSE
  classification bit 0 = 0;
DEST mask register bit 0 updated;
"""

simd_fp_exceptions = ["invalid"]
other_exceptions = []

handler = "x86_vfpclassss"
jit_lowering = "arm64_neon_fclass_ss"


neon_register_model = """
x86 scalar single-precision value is mapped onto ARM64 S register; classification result written to mask register k1 bit 0.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fcmeq sD, sN, sM
bl rosette_map_fcmeq_to_classify_scalar
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "No direct ARM64 fpclass equivalent; scalar FCMEQ provides approximate NaN/Inf/zero detection for single precision.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
