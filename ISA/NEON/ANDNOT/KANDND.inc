// ANDNOT/KANDND.inc
// ARM64/NEON mirror generated from ISA/x86/ANDNOT/KANDND.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ANDNOT/KANDND.inc"
x86_handler = "x86_kandnd"
neon_lowering = "arm64_kandnd"
lowering_kind = "arm64_documented_contract"

name = "KANDND"
aliases = []
category = "mask_bitwise"
feature = "AVX512BW"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "VEX.L1.66.0F.W1 42 /r", form = "KANDND k1, k2, k3", op_en = "RVR", feature = "AVX512BW", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise AND NOT of 32-bit mask registers k2 and k3, result in k1.
"""

handler = "x86_kandnd"
jit_lowering = "arm64_kandnd"
fallback = "zig_kandnd"

neon_register_model = """
KANDND is a mask_bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by KANDND.
"""

neon_assembly = """
// NEON lowering: mask register AND NOT stub
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
