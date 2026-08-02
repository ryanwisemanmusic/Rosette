// ADC.inc

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]

name = "ADC"
category = "integer_arithmetic_with_carry"
operation = "dest = dest + src + CF"

encodings = [
  { opcode = "14 ib", form = "ADC AL, imm8", op_en = "I" },
  { opcode = "15 iw", form = "ADC AX, imm16", op_en = "I" },
  { opcode = "15 id", form = "ADC EAX, imm32", op_en = "I" },
  { opcode = "80 /2 ib", form = "ADC r/m8, imm8", op_en = "MI" },
  { opcode = "81 /2 iw", form = "ADC r/m16, imm16", op_en = "MI" },
  { opcode = "81 /2 id", form = "ADC r/m32, imm32", op_en = "MI" },
  { opcode = "83 /2 ib", form = "ADC r/m16|r/m32|r/m64, imm8", op_en = "MI", imm = "sign_extend" },
  { opcode = "10 /r", form = "ADC r/m8, r8", op_en = "MR" },
  { opcode = "11 /r", form = "ADC r/m16|r/m32, r16|r32", op_en = "MR" },
  { opcode = "12 /r", form = "ADC r8, r/m8", op_en = "RM" },
  { opcode = "13 /r", form = "ADC r16|r32, r/m16|r/m32", op_en = "RM" }
]

reads = ["DEST", "SRC", "CF"]
writes = ["DEST"]
flags_written = ["OF", "SF", "ZF", "AF", "CF", "PF"]

lock_allowed = "only_if_dest_is_memory"

semantic = """
carry = CF ? 1 : 0;
result = DEST + SRC + carry;
DEST = truncate(result, operand_size);
update_adc_flags(DEST_old, SRC, carry, result, operand_size);
"""

handler = "x86_adc"
jit_lowering = "arm64_adc_with_x86_flags"
