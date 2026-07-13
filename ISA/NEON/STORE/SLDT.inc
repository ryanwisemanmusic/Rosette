// STORE/SLDT.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/SLDT.inc"
x86_handler = "x86_sldt"
neon_lowering = "arm64_sldt"
lowering_kind = "neon_documented_contract"

name = "SLDT"
category = "system_store"
feature = "8086"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "ARM64 mrs_to_mem", form = "SLDT", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_sldt" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "memory (w)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
SLDT: Stores LDTR selector to destination.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_sldt"
jit_lowering = "arm64_sldt"

neon_register_model = "x86 system registers mapped to ARM64 system registers."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: MRS to memory"
neon_notes = ["ARM64/NEON lowering mirror for x86 SLDT."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
