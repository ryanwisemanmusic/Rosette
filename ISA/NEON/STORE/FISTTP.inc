// STORE/FISTTP.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/FISTTP.inc"
x86_handler = "x86_fisttp"
neon_lowering = "arm64_fisttp"
lowering_kind = "neon_documented_contract"

name = "FISTTP"
category = "x87_fpu_store"
feature = "SSE3"
element_type = "float"
legacy_width = 0

encodings = [
  { opcode = "ARM64 FPU store", form = "FISTTP", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_fisttp" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "memory (w)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
FISTTP: Store x87 FPU value to memory.
"""

flags_written = []
simd_fp_exceptions = ["invalid", "precision"]

handler = "x86_fisttp"
jit_lowering = "arm64_fisttp"

neon_register_model = "x87 FPU stack mapped to ARM64 V registers."
neon_flag_model = "Flag behavior emulated."
neon_assembly = "// ARM64: STR to memory"
neon_notes = ["ARM64/NEON lowering mirror for x86 FISTTP."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
