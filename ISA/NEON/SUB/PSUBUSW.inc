// SUB/PSUBUSW.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBUSW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBUSW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBUSW.inc"
x86_handler = "x86_psubusw"
neon_lowering = "arm64_neon_subus_w"
lowering_kind = "neon_vector"


name = "PSUBUSW"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "u16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 40", form = "UQSUB Vd.8H, Vn.8H, Vm.8H", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_uqsub_vd8h_vn8h_vm8h" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..8:
    DEST.u16[lane] = unsigned_saturate(SRC1.u16[lane] - SRC2.u16[lane], 16);
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubusw"
jit_lowering = "arm64_neon_subus_w"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer saturation flags are preserved through Rosette SIMD integer side-effect handlers.
"""

neon_assembly = """
uqsub vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON UQSUB Vd.8H matches x86 PSUBUSW behavior (unsigned saturating 16-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
