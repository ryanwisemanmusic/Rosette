// SUB/SBB.inc
// ARM64/NEON translation mirror generated from ISA/x86/SUB/SBB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
SBB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: integer_subtract_borrow.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SUB/SBB.inc"
x86_handler = "x86_sbb"
neon_lowering = "arm64_neon_sbb"
lowering_kind = "neon_scalar_integer"


name = "SBB"
category = "integer_subtract_borrow"
feature = "BASE"
element_type = "i32"

encodings = [
  { opcode = "FA 00 00 60", form = "SBC Vd.8B, Vn.8B, Vm.8B", op_en = "A", feature = "NEON", mode = "V/V", handler = "arm64_sbc_vd8b_vn8b_vm8b" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "Vd (w)", operand2 = "Vn (r)", operand3 = "Vm (r)", operand4 = "N/A" }
]

semantic_neon = """
DEST = SRC1 - SRC2 - CF;
"""

simd_fp_exceptions = []
other_exceptions = []

handler = "x86_sbb"
jit_lowering = "arm64_neon_sbb"


neon_register_model = """
x86 general-purpose registers are mapped onto ARM64 v registers for NEON SBC lowering.
"""

neon_flag_model = """
Arithmetic flags (OF, SF, ZF, AF, PF, CF) are preserved through Rosette integer flag side-effect handlers.
"""

neon_assembly = """
sbc vD.8b, vN.8b, vM.8b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "NEON SBC (subtract with carry) is the closest NEON lowering for x86 SBB (subtract with borrow).",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
