// ANDNOT/KANDNW.inc
// ARM64/NEON mirror generated from ISA/x86/ANDNOT/KANDNW.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ANDNOT/KANDNW.inc"
x86_handler = "x86_kandnw"
neon_lowering = "arm64_kandnw"
lowering_kind = "arm64_documented_contract"

name = "KANDNW"
aliases = []
category = "mask_bitwise"
feature = "AVX512F"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "VEX.L1.0F.W0 42 /r", form = "KANDNW k1, k2, k3", op_en = "RVR", feature = "AVX512F", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RVR = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise AND NOT of 16-bit mask registers k2 and k3, result in k1.
"""

handler = "x86_kandnw"
jit_lowering = "arm64_kandnw"
fallback = "zig_kandnw"

neon_register_model = """
KANDNW is a mask_bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by KANDNW.
"""

neon_assembly = """
// NEON lowering: mask register AND NOT stub
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
