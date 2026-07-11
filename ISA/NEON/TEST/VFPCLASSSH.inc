// TEST/VFPCLASSSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/VFPCLASSSH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: fp_classify.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/VFPCLASSSH.inc"
x86_handler = "x86_vfpclasssh"
neon_lowering = "arm64_neon_fclass_sh"
lowering_kind = "neon_scalar"


name = "VFPCLASSSH"
category = "fp_classify"
feature = "arm64_neon"
element_type = "f16"

encodings = [
  { opcode = "0E 30 80 20", form = "FCMEQ Hd, Hn, Hm", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_fcmeq_hd_hn_hm" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Hd (w)", operand2 = "Hn (r)", operand3 = "Hm (r)", operand4 = "N/A" }
]

semantic_neon = """
IF FCMEQ(Hn, Hm) produces all-ones mask THEN
  classification bit 0 = 1;
ELSE
  classification bit 0 = 0;
DEST mask register bit 0 updated;
"""

simd_fp_exceptions = ["invalid"]
other_exceptions = []

handler = "x86_vfpclasssh"
jit_lowering = "arm64_neon_fclass_sh"


neon_register_model = """
x86 scalar half-precision value is mapped onto ARM64 H register; classification result written to mask register k1 bit 0.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fcmeq hD, hN, hM
bl rosette_map_fcmeq_to_classify_scalar
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "No direct ARM64 fpclass equivalent; scalar FCMEQ provides approximate NaN/Inf/zero detection for half precision.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
