// NOT/KNOTB.inc
// Source contract: KNOTB — mask_bitwise.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "NOT/KNOTB.inc"
x86_handler = "x86_knotb"
neon_lowering = "arm64_knotb"
lowering_kind = "arm64_documented_contract"

name = "KNOTB"
aliases = []
category = "mask_bitwise"
feature = "AVX512DQ"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "VEX.L0.66.0F.W0 44 /r", form = "KNOTB k1, k2", op_en = "RR", feature = "AVX512DQ", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RR = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise NOT of 8-bit mask register k2, result in k1.
"""

handler = "x86_knotb"
jit_lowering = "arm64_knotb"
fallback = "zig_knotb"

neon_register_model = """
KNOTB is a mask_bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by KNOTB.
"""

neon_assembly = """
// NEON lowering: mask register NOT stub
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
