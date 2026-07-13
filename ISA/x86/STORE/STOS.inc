// STORE/STOS.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STOS.inc"
x86_handler = "x86_stos"
neon_lowering = "arm64_stos"
lowering_kind = "arm64_documented_contract"

name = "STOS"
aliases = ["STOSB", "STOSW", "STOSD", "STOSQ"]
category = "string_store"
feature = "8086"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "AA", form = "STOS m8", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "AB", form = "STOS m16", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "AB", form = "STOS m32", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + AB", form = "STOS m64", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "AA", form = "STOSB", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "AB", form = "STOSW", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "AB", form = "STOSD", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + AB", form = "STOSQ", op_en = "ZO", feature = "8086", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
STOS/STOSB/STOSW/STOSD/STOSQ: Store byte/word/dword/qword from AL/AX/EAX/RAX to memory at ES:(E)DI/RDI. Updates (E)DI/RDI based on DF flag.
"""

handler = "x86_stos"
jit_lowering = "arm64_stos"
fallback = "zig_stos"

neon_register_model = "x86 GP registers mapped to ARM64 X registers."
neon_flag_model = "DF flag affects address increment/decrement."
neon_assembly = "// ARM64: STR with post-index"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
