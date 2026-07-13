// STORE/STOS.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STOS.inc"
x86_handler = "x86_stos"
neon_lowering = "arm64_stos"
lowering_kind = "neon_documented_contract"

name = "STOS"
category = "string_store"
feature = "8086"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "ARM64 str_post_idx", form = "STOS", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_stos" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "memory (w)", operand2 = "N/A", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
STOS: Store string from AL/AX/EAX/RAX to memory at ES:(E)DI/RDI.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_stos"
jit_lowering = "arm64_stos"

neon_register_model = "x86 GP registers mapped to ARM64 X registers."
neon_flag_model = "DF flag affects address increment/decrement."
neon_assembly = "// ARM64: STR with post-index"
neon_notes = ["ARM64/NEON lowering mirror for x86 STOS."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
