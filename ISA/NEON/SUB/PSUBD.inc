// SUB/PSUBD.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBD.inc"
x86_handler = "x86_psubd"
neon_lowering = "arm64_neon_sub_d"
lowering_kind = "neon_vector"


name = "PSUBD"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "i32"
legacy_width = 64
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 60", form = "SUB Vd.4S, Vn.4S, Vm.4S", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_sub_vd4s_vn4s_vm4s" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..4:
    DEST.i32[lane] = SRC1.i32[lane] - SRC2.i32[lane];
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubd"
jit_lowering = "arm64_neon_sub_d"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer wrap behavior is preserved by the NEON lowering (no saturation).
"""

neon_assembly = """
sub vD.4s, vN.4s, vM.4s
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SUB Vd.4S matches x86 PSUBD behavior (wrapping 32-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
