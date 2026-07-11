// TEST/VFPCLASSPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/TEST/VFPCLASSPS.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: fp_classify.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TEST/VFPCLASSPS.inc"
x86_handler = "x86_vfpclassps"
neon_lowering = "arm64_neon_fclass_ps"
lowering_kind = "neon_vector"


name = "VFPCLASSPS"
category = "fp_classify"
feature = "arm64_neon"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16

encodings = [
  { opcode = "7E 30 C0 30", form = "FCMEQ Vd.4S, Vn.4S, Vm.4S", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_fcmeq_v4s_v4s_v4s" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
FOR each f32 lane:
  IF FCMEQ(SRC1.lane, SRC2.lane) produces all-ones mask THEN
    classification bit = 1;
  ELSE
    classification bit = 0;
DEST mask register updated per lane classification;
"""

simd_fp_exceptions = ["invalid"]
other_exceptions = []

handler = "x86_vfpclassps"
jit_lowering = "arm64_neon_fclass_ps"


neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 V registers; classification results are written to mask register k1.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fcmeq vD.4s, vN.4s, vM.4s
bl rosette_map_fcmeq_to_classify
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "No direct ARM64 fpclass equivalent; FCMEQ with specific operands provides approximate NaN/Inf/zero detection for single precision.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
