// SUB/VSUBPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/VSUBPH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSUBPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/VSUBPH.inc"
x86_handler = "x86_vsubph"
neon_lowering = "arm64_neon_fsub_ph"
lowering_kind = "neon_vector"


name = "VSUBPH"
category = "simd_float_subtract"
feature = "AVX512-FP16"
element_type = "f16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = true

encodings = [
  { opcode = "0E 30 80 20", form = "FSUB Vd.8H, Vn.8H, Vm.8H", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_fsub_vd8h_vn8h_vm8h" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for each active f16 lane:
    DEST.f16[lane] = SRC1.f16[lane] - SRC2.f16[lane];
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = []

handler = "x86_vsubph"
jit_lowering = "arm64_neon_fsub_ph"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fsub vD.8h, vN.8h, vM.8h
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON FSUB Vd.8H performs FP16 packed subtraction matching x86 VSUBPH.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
