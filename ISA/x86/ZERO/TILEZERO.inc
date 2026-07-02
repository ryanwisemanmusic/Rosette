// ZERO/TILEZERO.inc
// TILEZERO — Zero Tile (AMX-TILE).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ZERO/TILEZERO.inc"
x86_handler = "x86_tilezero"
neon_lowering = "arm64_tilezero"
lowering_kind = "arm64_documented_contract"

name = "TILEZERO"
aliases = []
category = "tile_management"
feature = "AMX-TILE"

encodings = [
  { opcode = "VEX.128.F2.0F38.W0 49 11:rrr:000", form = "TILEZERO tmm1", op_en = "A", feature = "AMX-TILE", vector_length = 0, encoding = "VEX" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "N/A", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["#UD (if inside TSX transaction)", "AMX-E5"]

semantic_general = """
Zeroes the destination tile register tmm1. Uses palette_table to determine tile dimensions.
Aborts Intel TSX transactions if executed inside one.
"""

handler = "x86_tilezero"
jit_lowering = "arm64_tilezero"
fallback = "zig_tilezero"

neon_register_model = "TILEZERO is an x86 AMX tile operation. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: TILEZERO stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
