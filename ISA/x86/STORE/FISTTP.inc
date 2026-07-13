// STORE/FISTTP.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FISTTP.inc"
x86_handler = "x86_fisttp"
neon_lowering = "arm64_fisttp"
lowering_kind = "arm64_documented_contract"

name = "FISTTP"
category = "x87_fpu_store"
feature = "SSE3"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "DF /1", form = "FISTTP m16int", op_en = "M", feature = "SSE3", vector_length = 0, encoding = "legacy" },
  { opcode = "DB /1", form = "FISTTP m32int", op_en = "M", feature = "SSE3", vector_length = 0, encoding = "legacy" },
  { opcode = "DD /1", form = "FISTTP m64int", op_en = "M", feature = "SSE3", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
FISTTP: Store integer with truncation and pop. Converts ST(0) to signed integer using truncation (chop) mode and stores to memory, then pops the x87 register stack.
"""

handler = "x86_fisttp"
jit_lowering = "arm64_fisttp"
fallback = "zig_fisttp"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
