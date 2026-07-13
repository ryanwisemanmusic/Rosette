// STORE/FBSTP.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FBSTP.inc"
x86_handler = "x86_fbstp"
neon_lowering = "arm64_fbstp"
lowering_kind = "arm64_documented_contract"

name = "FBSTP"
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "DF /6", form = "FBSTP m80bcd", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
FBSTP: Store BCD integer and pop stack. Converts ST(0) to 18-digit packed BCD and stores to memory, then pops the x87 register stack.
"""

handler = "x86_fbstp"
jit_lowering = "arm64_fbstp"
fallback = "zig_fbstp"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
