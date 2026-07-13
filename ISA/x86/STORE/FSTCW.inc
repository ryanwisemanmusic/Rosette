// STORE/FSTCW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FSTCW.inc"
x86_handler = "x86_fstcw"
neon_lowering = "arm64_fstcw"
lowering_kind = "arm64_documented_contract"

name = "FSTCW"
aliases = ["FNSTCW"]
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "9B D9 /7", form = "FSTCW m2byte", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "D9 /7", form = "FNSTCW m2byte", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
FSTCW: Store FPU control word to memory. FSTCW (with FWAIT prefix) waits for pending exceptions before storing; FNSTCW stores immediately without waiting.
"""

handler = "x86_fstcw"
jit_lowering = "arm64_fstcw"
fallback = "zig_fstcw"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
