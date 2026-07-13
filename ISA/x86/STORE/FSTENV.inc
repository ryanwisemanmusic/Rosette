// STORE/FSTENV.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FSTENV.inc"
x86_handler = "x86_fstenv"
neon_lowering = "arm64_fstenv"
lowering_kind = "arm64_documented_contract"

name = "FSTENV"
aliases = ["FNSTENV"]
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "9B D9 /6", form = "FSTENV m14/28byte", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "D9 /6", form = "FNSTENV m14/28byte", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
FSTENV: Store FPU environment (control, status, tag, last instruction pointer, last data pointer) to memory. FSTENV (with FWAIT prefix) waits before storing; FNSTENV stores immediately.
"""

handler = "x86_fstenv"
jit_lowering = "arm64_fstenv"
fallback = "zig_fstenv"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
