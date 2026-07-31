// PUSH.inc
// Auto-generated from: PUSH Instructions.md
// Instruction: PUSH — Push Word, Doubleword, or Quadword Onto the Stack
// Source table covers PUSH r/m16, r/m32, r/m64, r16, r32, r64, imm8, imm16, imm32, CS, SS, DS, ES, FS, GS.

// Canonical table metadata for registry-wide .inc validation.
name = "PUSH"
encodings = [
  { opcode = "see preserved_source_contract", form = "PUSH documented source contract", op_en = "DOC", mode64 = "see_source_contract", compat = "see_source_contract", handler = "x86_push" },
]
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PUSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
"""

flags_written = []

jit_lowering = "arm64_documented_contract_from_x86_push"

#ifndef X86_PUSH_INC
#define X86_PUSH_INC

// Table schema:
// X86_INST(opcode, mnemonic, operands, op_en, valid_64, valid_compat_legacy, description, operand_encoding, operation, flags, exceptions)

X86_INST(
    "FF /6",
    "PUSH",
    "r/m16",
    "M",
    "Valid",
    "Valid",
    "Push r/m16.",
    "Operand 1: ModRM:r/m (r)
    "SRC := r/m16
    "None",
    "#GP/#SS for segment limit or non-canonical address
)

X86_INST(
    "FF /6",
    "PUSH",
    "r/m32",
    "M",
    "N.E.",
    "Valid",
    "Push r/m32.",
    "Operand 1: ModRM:r/m (r)
    "SRC := r/m32
    "None",
    "#GP/#SS for segment limit
)

X86_INST(
    "FF /6",
    "PUSH",
    "r/m64",
    "M",
    "Valid",
    "N.E.",
    "Push r/m64.",
    "Operand 1: ModRM:r/m (r)
    "SRC := r/m64
    "None",
    "64-bit: #GP for non-canonical memory address
)

X86_INST(
    "50+rw",
    "PUSH",
    "r16",
    "O",
    "Valid",
    "Valid",
    "Push r16.",
    "Operand 1: opcode + rd (r); Operand 2-4: N/A",
    "SRC := r16; stack pointer decremented by 2; word SRC stored at top of stack.",
    "None",
    "#SS if stack address outside stack segment or non-canonical; #PF; #AC; #UD on LOCK prefix."
)

X86_INST(
    "50+rd",
    "PUSH",
    "r32",
    "O",
    "N.E.",
    "Valid",
    "Push r32.",
    "Operand 1: opcode + rd (r); Operand 2-4: N/A",
    "SRC := r32; stack pointer decremented by 4; dword SRC stored at top of stack. PUSH ESP pushes the original ESP value before decrement.",
    "None",
    "#SS if stack address outside stack segment; #PF; #AC; #UD on LOCK prefix."
)

X86_INST(
    "50+rd",
    "PUSH",
    "r64",
    "O",
    "Valid",
    "N.E.",
    "Push r64.",
    "Operand 1: opcode + rd (r); Operand 2-4: N/A",
    "SRC := r64; RSP := RSP - 8; Memory[SS:RSP] := SRC. PUSH RSP pushes the original RSP value before decrement.",
    "None",
    "64-bit: #SS for non-canonical stack address; #PF; #AC; #UD on LOCK prefix."
)

X86_INST(
    "6A ib",
    "PUSH",
    "imm8",
    "I",
    "Valid",
    "Valid",
    "Push imm8.",
    "Operand 1: imm8; Operand 2-4: N/A",
    "SRC := SignExtend(imm8, OperandSize); decrement stack pointer by operand size; store SRC at top of stack.",
    "None",
    "#SS if stack address outside stack segment or non-canonical; #PF; #AC; #UD on LOCK prefix."
)

X86_INST(
    "68 iw",
    "PUSH",
    "imm16",
    "I",
    "Valid",
    "Valid",
    "Push imm16.",
    "Operand 1: imm16; Operand 2-4: N/A",
    "SRC := imm16, sign-extended when source size is smaller than operand size; decrement stack pointer by operand size; store SRC at top of stack.",
    "None",
    "#SS if stack address outside stack segment or non-canonical; #PF; #AC; #UD on LOCK prefix."
)

X86_INST(
    "68 id",
    "PUSH",
    "imm32",
    "I",
    "Valid",
    "Valid",
    "Push imm32.",
    "Operand 1: imm32; Operand 2-4: N/A",
    "SRC := imm32, sign-extended to 64 bits when operand size is 64; decrement stack pointer by operand size; store SRC at top of stack.",
    "None",
    "#SS if stack address outside stack segment or non-canonical; #PF; #AC; #UD on LOCK prefix."
)

X86_INST("0E", "PUSH", "CS", "ZO", "Invalid", "Valid", "Push CS.", "Operands: N/A", "Push segment selector CS; in 64-bit mode this form raises #UD.", "None", "#UD in 64-bit mode or on LOCK prefix; legacy stack exceptions as applicable.")
X86_INST("16", "PUSH", "SS", "ZO", "Invalid", "Valid", "Push SS.", "Operands: N/A", "Push segment selector SS; in 64-bit mode this form raises #UD.", "None", "#UD in 64-bit mode or on LOCK prefix; legacy stack exceptions as applicable.")
X86_INST("1E", "PUSH", "DS", "ZO", "Invalid", "Valid", "Push DS.", "Operands: N/A", "Push segment selector DS; in 64-bit mode this form raises #UD.", "None", "#UD in 64-bit mode or on LOCK prefix; legacy stack exceptions as applicable.")
X86_INST("06", "PUSH", "ES", "ZO", "Invalid", "Valid", "Push ES.", "Operands: N/A", "Push segment selector ES; in 64-bit mode this form raises #UD.", "None", "#UD in 64-bit mode or on LOCK prefix; legacy stack exceptions as applicable.")
X86_INST("0F A0", "PUSH", "FS", "ZO", "Valid", "Valid", "Push FS.", "Operands: N/A", "Push segment selector FS. If operand size is 64, zero-extend 16-bit selector to 64 bits.", "None", "#SS/#PF/#AC stack exceptions as applicable; #UD on LOCK prefix.")
X86_INST("0F A8", "PUSH", "GS", "ZO", "Valid", "Valid", "Push GS.", "Operands: N/A", "Push segment selector GS. If operand size is 64, zero-extend 16-bit selector to 64 bits.", "None", "#SS/#PF/#AC stack exceptions as applicable; #UD on LOCK prefix.")

#endif // X86_PUSH_INC
