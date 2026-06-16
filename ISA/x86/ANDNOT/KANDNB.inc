// ANDNOT/KANDNB.inc
// Source contract: KANDNB — mask_bitwise.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ANDNOT/KANDNB.inc"
x86_handler = "x86_kandnb"
neon_lowering = "arm64_kandnb"
lowering_kind = "arm64_documented_contract"

name = "KANDNB"
aliases = []
category = "mask_bitwise"
feature = "AVX512DQ"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "VEX.L1.66.0F.W0 42 /r", form = "KANDNB k1, k2, k3", op_en = "RVR", feature = "AVX512DQ", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise AND NOT of 8-bit mask registers k2 and k3, result in k1.
"""

handler = "x86_kandnb"
jit_lowering = "arm64_kandnb"
fallback = "zig_kandnb"

neon_register_model = """
KANDNB is a mask_bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by KANDNB.
"""

neon_assembly = """
// NEON lowering: mask register AND NOT stub
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
