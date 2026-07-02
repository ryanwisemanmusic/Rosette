// Mirror: ZERO/TILEZERO.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "ZERO/TILEZERO.inc"
x86_handler = "x86_tilezero"
neon_lowering = "arm64_tilezero"
lowering_kind = "arm64_documented_contract"
name = "TILEZERO"
aliases = []
category = "tile_management"
feature = "AMX-TILE"
encodings = [{ opcode = "VEX.128.F2.0F38.W0 49 11:rrr:000", form = "TILEZERO tmm1", op_en = "A", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
