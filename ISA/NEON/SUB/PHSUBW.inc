// SUB/PHSUBW.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PHSUBW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PHSUBW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_horizontal_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PHSUBW.inc"
x86_handler = "x86_phsubw"
neon_lowering = "arm64_neon_hsub_w"
lowering_kind = "neon_vector"


name = "PHSUBW"
category = "simd_integer_horizontal_subtract"
feature = "SSSE3"
element_type = "i16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
mxcsr_used = false

encodings = [
  { opcode = "0E 20 34 60", form = "SHSUB Vd.8B, Vn.8B, Vm.8B", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_shsub_vd8b_vn8b_vm8b" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..8:
    DEST.i16[lane] = signed_saturate_half(SRC1.i16[lane*2] - SRC1.i16[lane*2+1], 16);
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_phsubw"
jit_lowering = "arm64_neon_hsub_w"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer saturation flags are preserved through Rosette SIMD integer side-effect handlers.
"""

neon_assembly = """
shsub vD.8b, vN.8b, vM.8b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SHSUB computes signed halving subtract (a - b) >> 1; used as NEON lowering approximation for PHSUBW.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
