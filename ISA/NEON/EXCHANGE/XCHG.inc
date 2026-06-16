// EXCHANGE/XCHG.inc
// ARM64/NEON mirror generated from ISA/x86/EXCHANGE/XCHG.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXCHANGE/XCHG.inc"
x86_handler = "x86_xchg"
neon_lowering = "arm64_xchg"
lowering_kind = "arm64_documented_contract"

name = "XCHG"
aliases = []
category = "data_transfer"
feature = "x86_gpr"
element_type = "u8_u16_u32_u64"
element_size = 8

encodings = [
  { opcode = "90+rw", form = "XCHG AX, r16", op_en = "O", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "90+rw", form = "XCHG r16, AX", op_en = "O", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "90+rd", form = "XCHG EAX, r32", op_en = "O", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 90+rd", form = "XCHG RAX, r64", op_en = "O", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "90+rd", form = "XCHG r32, EAX", op_en = "O", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 90+rd", form = "XCHG r64, RAX", op_en = "O", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "86 /r", form = "XCHG r/m8, r8", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + 86 /r", form = "XCHG r/m8*, r8*", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "86 /r", form = "XCHG r8, r/m8", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + 86 /r", form = "XCHG r8*, r/m8*", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "87 /r", form = "XCHG r/m16, r16", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "87 /r", form = "XCHG r16, r/m16", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "87 /r", form = "XCHG r/m32, r32", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 87 /r", form = "XCHG r/m64, r64", op_en = "MR", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "87 /r", form = "XCHG r32, r/m32", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 87 /r", form = "XCHG r64, r/m64", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  O = ["AX/EAX/RAX (r, w)", "opcode+rd (r, w)"]
  MR = ["ModRM:r/m (r, w)", "ModRM:reg (r)"]
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Exchange the contents of the destination and source operands.
"""

handler = "x86_xchg"
jit_lowering = "arm64_xchg"
fallback = "zig_xchg"

neon_register_model = """
XCHG is a data_transfer instruction. ARM64 register swap via MOV.
"""

neon_flag_model = """
No x86 flags modified by XCHG.
"""

neon_assembly = """
// NEON lowering: register swap via MOV sequence
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
