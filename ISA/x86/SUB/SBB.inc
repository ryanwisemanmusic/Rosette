// SBB.inc
// Integer subtract with borrow.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
SBB: subtract with borrow — DEST = DEST - SRC - CF.
Category: integer_subtract_borrow.
"""

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
  { op_en = "I", operand1 = "AL/AX/EAX/RAX", operand2 = "imm8/16/32", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "MI", operand1 = "ModRM:r/m (r, w)", operand2 = "imm8/16/32", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "MR", operand1 = "ModRM:r/m (r, w)", operand2 = "ModRM:reg (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RM", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

flags = {
  affected = ["OF", "SF", "ZF", "AF", "PF", "CF"],
  rule = "All arithmetic status flags are set according to the subtraction result with borrow. OF reports signed overflow; CF reports unsigned borrow."
}

notes = [
  "Immediate operands are sign-extended to the destination width when required by the encoding.",
  "Two memory operands cannot be used in one SBB instruction.",
  "Default operation size in 64-bit mode is 32 bits unless REX.W promotes the operation to 64 bits.",
  "LOCK is valid only when the destination operand is memory."
]

exceptions = {
  protected = ["#GP(0) for non-writable destination segment or segment-limit/null-segment memory access", "#SS(0) for stack segment limit", "#PF(fault-code)", "#AC(0)", "#UD if LOCK prefix is used and destination is not memory"],
  real = ["#GP for segment-limit memory access", "#SS for stack segment limit", "#UD if LOCK prefix is used and destination is not memory"],
  v8086 = ["#GP(0) for segment-limit memory access", "#SS(0) for stack segment limit", "#PF(fault-code)", "#AC(0)", "#UD if LOCK prefix is used and destination is not memory"],
  compatibility = ["same as protected mode"],
  mode64 = ["#SS(0) for non-canonical SS memory address", "#GP(0) for non-canonical memory address", "#PF(fault-code)", "#AC(0)", "#UD if LOCK prefix is used and destination is not memory"]
}

handler = "x86_sbb"
jit_lowering = "arm64_neon_sbb"
