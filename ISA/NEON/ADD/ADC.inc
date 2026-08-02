// ADD/ADC.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/ADC.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/ADC.inc"
x86_handler = "x86_adc"
neon_lowering = "arm64_adc_with_x86_flags"
lowering_kind = "arm64_scalar"


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

neon_register_model = """
x86 general-purpose operands are mapped through the Rosette register file into ARM64 temporaries with explicit writeback.
"""

neon_flag_model = """
ARM64 NZCV is repacked into x86 OF/SF/ZF/AF/CF/PF according to the source table flag contract.
"""

neon_assembly = """
msr nzcv, x86_carry_to_nzcv(CF)
adcs xD, xN, xM
mrs xFLAGS, nzcv
bl rosette_pack_x86_adc_flags
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
