// STORE/FIST.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FIST.inc"
x86_handler = "x86_fist"
neon_lowering = "arm64_fist"
lowering_kind = "arm64_documented_contract"

name = "FIST"
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "DF /2", form = "FIST m16int", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DB /2", form = "FIST m32int", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
FIST: Store integer. Converts ST(0) to signed integer and stores to memory using current rounding mode.
"""

handler = "x86_fist"
jit_lowering = "arm64_fist"
fallback = "zig_fist"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
