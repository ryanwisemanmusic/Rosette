// STORE/STTILECFG.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "STORE/STTILECFG.inc"
x86_handler = "x86_sttilecfg"
neon_lowering = "arm64_sttilecfg"
lowering_kind = "arm64_documented_contract"

name = "STTILECFG"
category = "amx_store"
feature = "AMX-TILE"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "VEX.128.66.0F38.W0 49 !(11):000:bbb", form = "STTILECFG m512", op_en = "A", feature = "AMX-TILE", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
STTILECFG: Store tile configuration to 64-byte memory location. Stores 64 bytes of zeros if tiles not configured.
"""

handler = "x86_sttilecfg"
jit_lowering = "arm64_sttilecfg"
fallback = "zig_sttilecfg"

neon_register_model = "AMX tile registers not directly mappable to ARM64; uses software emulation."
neon_flag_model = "No flags affected."
neon_assembly = "// ARM64: store via software tile emulation"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
