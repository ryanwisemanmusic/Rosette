// SUB/PSUBUSB.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/PSUBUSB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBUSB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_subtract.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/PSUBUSB.inc"
x86_handler = "x86_psubusb"
neon_lowering = "arm64_neon_subus_b"
lowering_kind = "neon_vector"


name = "PSUBUSB"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "u8"
legacy_width = 64
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64
mxcsr_used = false

encodings = [
  { opcode = "0E 30 80 20", form = "UQSUB Vd.16B, Vn.16B, Vm.16B", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_uqsub_vd16b_vn16b_vm16b" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
for lane in 0..16:
    DEST.u8[lane] = unsigned_saturate(SRC1.u8[lane] - SRC2.u8[lane], 8);
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_psubusb"
jit_lowering = "arm64_neon_subus_b"


neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
Integer saturation flags are preserved through Rosette SIMD integer side-effect handlers.
"""

neon_assembly = """
uqsub vD.16b, vN.16b, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON UQSUB Vd.16B matches x86 PSUBUSB behavior (unsigned saturating 8-bit subtraction).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
