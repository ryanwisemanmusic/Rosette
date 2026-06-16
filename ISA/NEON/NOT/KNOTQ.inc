// NOT/KNOTQ.inc
// ARM64/NEON mirror generated from ISA/x86/NOT/KNOTQ.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "NOT/KNOTQ.inc"
x86_handler = "x86_knotq"
neon_lowering = "arm64_knotq"
lowering_kind = "arm64_documented_contract"

name = "KNOTQ"
aliases = []
category = "mask_bitwise"
feature = "AVX512BW"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "VEX.L0.0F.W1 44 /r", form = "KNOTQ k1, k2", op_en = "RR", feature = "AVX512BW", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RR = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise NOT of 64-bit mask register k2, result in k1.
"""

handler = "x86_knotq"
jit_lowering = "arm64_knotq"
fallback = "zig_knotq"

neon_register_model = """
KNOTQ is a mask_bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by KNOTQ.
"""

neon_assembly = """
// NEON lowering: mask register NOT stub
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
