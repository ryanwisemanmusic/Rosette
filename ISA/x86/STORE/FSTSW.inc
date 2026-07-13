// STORE/FSTSW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FSTSW.inc"
x86_handler = "x86_fstsw"
neon_lowering = "arm64_fstsw"
lowering_kind = "arm64_documented_contract"

name = "FSTSW"
aliases = ["FNSTSW"]
category = "x87_fpu_store"
feature = "x87"
element_type = "float"
element_size = 0

encodings = [
  { opcode = "9B DD /7", form = "FSTSW m2byte", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "9B DF E0", form = "FSTSW AX", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DD /7", form = "FNSTSW m2byte", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
  { opcode = "DF E0", form = "FNSTSW AX", op_en = "M", feature = "x87", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
FSTSW: Store FPU status word to memory or AX register. FSTSW (with FWAIT prefix) waits for pending exceptions before storing; FNSTSW stores immediately.
"""

handler = "x86_fstsw"
jit_lowering = "arm64_fstsw"
fallback = "zig_fstsw"

neon_register_model = "x87 FPU register stack mapped to ARM64 SIMD/FP registers."
neon_flag_model = "C1 flag impacted per x87 semantics."
neon_assembly = "// ARM64: FPU store lowering"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
