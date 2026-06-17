// RELEASE/TILERELEASE.inc
// ARM64/NEON mirror generated from ISA/x86/RELEASE/TILERELEASE.inc.
// Source contract: TILERELEASE — amx.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RELEASE/TILERELEASE.inc"
x86_handler = "x86_tilerelease"
neon_lowering = "arm64_tilerelease"
lowering_kind = "arm64_documented_contract"

name = "TILERELEASE"
aliases = []
category = "amx"
feature = "amx_tile"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "VEX.128.NP.0F38.W0 49 C0", form = "TILERELEASE ", op_en = "A", feature = "amx_tile", vector_length = 128, encoding = "vex" }
]

operand_encoding = {
  A = []
}

simd_fp_exceptions = []

semantic_general = """
Initialize TILECFG and TILEDATA to INIT state.
"""

handler = "x86_tilerelease"
jit_lowering = "arm64_tilerelease"
fallback = "zig_tilerelease"

neon_register_model = """
TILERELEASE is an AMX tile instruction.
"""

neon_flag_model = """
TILERELEASE does not modify flags.
"""

neon_assembly = """
// NEON lowering: TILERELEASE stub (amx)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
