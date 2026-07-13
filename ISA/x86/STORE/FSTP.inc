// STORE/FSTP.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FSTP.inc"
x86_handler = "x86_fstp"
neon_lowering = "arm64_fstp"
lowering_kind = "arm64_documented_contract"

name = "FSTP"
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "D9 /3", form = "FSTP m32fp", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DD /3", form = "FSTP m64fp", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DB /7", form = "FSTP m80fp", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DD D8+i", form = "FSTP ST(i)", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
FSTP: Store floating-point value and pop. Copies ST(0) to destination (memory or FPU register ST(i)), then pops the x87 register stack.
"""

handler = "x86_fstp"
jit_lowering = "arm64_fstp"
fallback = "zig_fstp"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
