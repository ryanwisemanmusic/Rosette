// STORE/STR.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STR.inc"
x86_handler = "x86_str"
neon_lowering = "arm64_str"
lowering_kind = "neon_documented_contract"

name = "STR"
category = "system_store"
feature = "8086"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "ARM64 mrs_to_mem", form = "STR", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_str" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "memory (w)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
STR: Stores TR segment selector to destination.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_str"
jit_lowering = "arm64_str"

neon_register_model = "x86 system registers mapped to ARM64."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: MRS to register/memory"
neon_notes = ["ARM64/NEON lowering mirror for x86 STR."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
