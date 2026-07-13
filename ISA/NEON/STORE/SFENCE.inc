// STORE/SFENCE.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/SFENCE.inc"
x86_handler = "x86_sfence"
neon_lowering = "arm64_sfence"
lowering_kind = "neon_documented_contract"

name = "SFENCE"
category = "fence"
feature = "SSE"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "ARM64 dmb_st", form = "SFENCE", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_sfence" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "N/A", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
SFENCE: Serializes store operations.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_sfence"
jit_lowering = "arm64_sfence"

neon_register_model = "x86 memory model mapped to ARM64."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: DMB ST"
neon_notes = ["ARM64/NEON lowering mirror for x86 SFENCE."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
