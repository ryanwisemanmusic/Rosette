// STORE/FISTP.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FISTP.inc"
x86_handler = "x86_fistp"
neon_lowering = "arm64_fistp"
lowering_kind = "arm64_documented_contract"

name = "FISTP"
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "DF /3", form = "FISTP m16int", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DB /3", form = "FISTP m32int", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DF /7", form = "FISTP m64int", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
FISTP: Store integer and pop. Converts ST(0) to signed integer and stores to memory, then pops the x87 register stack.
"""

handler = "x86_fistp"
jit_lowering = "arm64_fistp"
fallback = "zig_fistp"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
