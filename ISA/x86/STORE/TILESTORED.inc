// STORE/TILESTORED.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/TILESTORED.inc"
x86_handler = "x86_tilestored"
neon_lowering = "arm64_tilestored"
lowering_kind = "arm64_documented_contract"

name = "TILESTORED"
category = "amx_store"
feature = "AMX-TILE"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "VEX.128.F3.0F38.W0 4B !(11):rrr:100", form = "TILESTORED sibmem, tmm1", op_en = "A", feature = "AMX-TILE", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
TILESTORED: Store a tile from tmm1 to memory with SIB addressing. Uses index register as stride.
"""

handler = "x86_tilestored"
jit_lowering = "arm64_tilestored"
fallback = "zig_tilestored"

neon_register_model = "AMX tile registers not directly mappable to ARM64; uses software emulation."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: store via software tile emulation"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
