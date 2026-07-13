// STORE/TILESTORED.inc
// ARM64/NEON translation mirror.
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/TILESTORED.inc"
x86_handler = "x86_tilestored"
neon_lowering = "arm64_tilestored"
lowering_kind = "neon_documented_contract"

name = "TILESTORED"
category = "amx_store"
feature = "AMX-TILE"
element_type = "integer"
legacy_width = 0

encodings = [
  { opcode = "ARM64 sw_tile_store", form = "TILESTORED", op_en = "DOC", feature = "NEON", mode = "V/V", handler = "arm64_tilestored" }
]

operand_encodings = [
  { op_en = "DOC", tuple = "N/A", operand1 = "memory (w)", operand2 = "tmm1 (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_general = """
TILESTORED: Store tile from tmm1 to memory.
"""

flags_written = []
simd_fp_exceptions = []

handler = "x86_tilestored"
jit_lowering = "arm64_tilestored"

neon_register_model = "AMX tile registers not directly mappable to ARM64; uses software emulation."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: store via software tile emulation"
neon_notes = ["ARM64/NEON lowering mirror for x86 TILESTORED."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
