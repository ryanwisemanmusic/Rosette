// SET/STAC.inc
// Source contract: STAC — flag_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/STAC.inc"
x86_handler = "x86_stac"
neon_lowering = "arm64_stac"
lowering_kind = "arm64_documented_contract"

name = "STAC"
aliases = []
category = "flag_control"
feature = "SMAP"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 01 CB", form = "STAC", op_en = "ZO", feature = "SMAP", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["AC"]
simd_fp_exceptions = []

semantic_general = """
Sets the AC flag in EFLAGS, enabling alignment checking of user-mode data accesses.
"""

handler = "x86_stac"
jit_lowering = "arm64_stac"
fallback = "zig_stac"

neon_register_model = """
x86 GPR mapped to ARM64 xN. STAC is a flag_control instruction.
"""

neon_flag_model = """
No x86 flags are modified by STAC.
"""

neon_assembly = """
// ARM64: MSR DAIF or MRS xTMP, nzcv; ORR
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
