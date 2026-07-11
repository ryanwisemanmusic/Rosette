// SUB/PSUBQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBQ.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBQ.inc"
x86_handler = "x86_psubq"
neon_lowering = "arm64_neon_sub_q"
lowering_kind = "neon_vector"


name = "PSUBQ"
category = "simd_integer_subtract"
feature = "SSE2"
element_type = "i64"
legacy_width = 64
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 80", form = "SUB Vd.2D, Vn.2D, Vm.2D", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_sub_vd2d_vn2d_vm2d" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
DEST.i64[0] = SRC1.i64[0] - SRC2.i64[0];
DEST.i64[1] = SRC1.i64[1] - SRC2.i64[1];
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubq"
jit_lowering = "arm64_neon_sub_q"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer wrap behavior is preserved by the NEON lowering (no saturation).
"""

neon_assembly = """
sub vD.2d, vN.2d, vM.2d
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SUB Vd.2D matches x86 PSUBQ behavior (wrapping 64-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
