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
  { opcode = "1C ib", form = "SBB AL, imm8", op_en = "I", mode64 = "valid", compat = "valid", handler = "x86_sbb_al_imm8" },
  { opcode = "1D iw", form = "SBB AX, imm16", op_en = "I", mode64 = "valid", compat = "valid", handler = "x86_sbb_ax_imm16" },
  { opcode = "1D id", form = "SBB EAX, imm32", op_en = "I", mode64 = "valid", compat = "valid", handler = "x86_sbb_eax_imm32" },
  { opcode = "REX.W + 1D id", form = "SBB RAX, imm32", op_en = "I", mode64 = "valid", compat = "n.e.", sign_ext = "imm32_to_64", handler = "x86_sbb_rax_imm32" },
  { opcode = "80 /3 ib", form = "SBB r/m8, imm8", op_en = "MI", mode64 = "valid", compat = "valid", handler = "x86_sbb_rm8_imm8" },
  { opcode = "REX + 80 /3 ib", form = "SBB r/m8, imm8", op_en = "MI", mode64 = "valid", compat = "n.e.", handler = "x86_sbb_rm8_imm8_rex", notes = ["REX byte registers cannot encode AH/BH/CH/DH"] },
  { opcode = "81 /3 iw", form = "SBB r/m16, imm16", op_en = "MI", mode64 = "valid", compat = "valid", handler = "x86_sbb_rm16_imm16" },
  { opcode = "81 /3 id", form = "SBB r/m32, imm32", op_en = "MI", mode64 = "valid", compat = "valid", handler = "x86_sbb_rm32_imm32" },
  { opcode = "REX.W + 81 /3 id", form = "SBB r/m64, imm32", op_en = "MI", mode64 = "valid", compat = "n.e.", sign_ext = "imm32_to_64", handler = "x86_sbb_rm64_imm32" },
  { opcode = "83 /3 ib", form = "SBB r/m16, imm8", op_en = "MI", mode64 = "valid", compat = "valid", sign_ext = "imm8_to_16", handler = "x86_sbb_rm16_imm8" },
  { opcode = "83 /3 ib", form = "SBB r/m32, imm8", op_en = "MI", mode64 = "valid", compat = "valid", sign_ext = "imm8_to_32", handler = "x86_sbb_rm32_imm8" },
  { opcode = "REX.W + 83 /3 ib", form = "SBB r/m64, imm8", op_en = "MI", mode64 = "valid", compat = "n.e.", sign_ext = "imm8_to_64", handler = "x86_sbb_rm64_imm8" },
  { opcode = "18 /r", form = "SBB r/m8, r8", op_en = "MR", mode64 = "valid", compat = "valid", handler = "x86_sbb_rm8_r8" },
  { opcode = "REX + 18 /r", form = "SBB r/m8, r8", op_en = "MR", mode64 = "valid", compat = "n.e.", handler = "x86_sbb_rm8_r8_rex", notes = ["REX byte registers cannot encode AH/BH/CH/DH"] },
  { opcode = "19 /r", form = "SBB r/m16, r16", op_en = "MR", mode64 = "valid", compat = "valid", handler = "x86_sbb_rm16_r16" },
  { opcode = "19 /r", form = "SBB r/m32, r32", op_en = "MR", mode64 = "valid", compat = "valid", handler = "x86_sbb_rm32_r32" },
  { opcode = "REX.W + 19 /r", form = "SBB r/m64, r64", op_en = "MR", mode64 = "valid", compat = "n.e.", handler = "x86_sbb_rm64_r64" },
  { opcode = "1A /r", form = "SBB r8, r/m8", op_en = "RM", mode64 = "valid", compat = "valid", handler = "x86_sbb_r8_rm8" },
  { opcode = "REX + 1A /r", form = "SBB r8, r/m8", op_en = "RM", mode64 = "valid", compat = "n.e.", handler = "x86_sbb_r8_rm8_rex", notes = ["REX byte registers cannot encode AH/BH/CH/DH"] },
  { opcode = "1B /r", form = "SBB r16, r/m16", op_en = "RM", mode64 = "valid", compat = "valid", handler = "x86_sbb_r16_rm16" },
  { opcode = "1B /r", form = "SBB r32, r/m32", op_en = "RM", mode64 = "valid", compat = "valid", handler = "x86_sbb_r32_rm32" },
  { opcode = "REX.W + 1B /r", form = "SBB r64, r/m64", op_en = "RM", mode64 = "valid", compat = "n.e.", handler = "x86_sbb_r64_rm64" }
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
