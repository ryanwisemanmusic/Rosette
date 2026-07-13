// STORE/STR.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STR.inc"
x86_handler = "x86_str"
neon_lowering = "arm64_str"
lowering_kind = "arm64_documented_contract"

name = "STR"
category = "system_store"
feature = "8086"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "0F 00 /1", form = "STR r/m16", op_en = "M", feature = "8086", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
STR: Stores segment selector from task register (TR) to destination.
"""

handler = "x86_str"
jit_lowering = "arm64_str"
fallback = "zig_str"

neon_register_model = "x86 system registers mapped to ARM64."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: MRS to register/memory"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
