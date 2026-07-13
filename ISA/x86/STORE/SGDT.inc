// STORE/SGDT.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/SGDT.inc"
x86_handler = "x86_sgdt"
neon_lowering = "arm64_sgdt"
lowering_kind = "arm64_documented_contract"

name = "SGDT"
category = "system_store"
feature = "8086"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "0F 01 /0", form = "SGDT m", op_en = "M", feature = "8086", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
SGDT: Stores the content of the global descriptor table register (GDTR) to destination memory.
"""

handler = "x86_sgdt"
jit_lowering = "arm64_sgdt"
fallback = "zig_sgdt"

neon_register_model = "x86 system registers mapped to ARM64 system registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: MRS to memory"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
