// ANDNOT/PANDN.inc
// ARM64/NEON mirror generated from ISA/x86/ANDNOT/PANDN.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ANDNOT/PANDN.inc"
x86_handler = "x86_pandn"
neon_lowering = "arm64_pandn"
lowering_kind = "arm64_documented_contract"

name = "PANDN"
aliases = []
category = "bitwise"
feature = "MMX"
element_type = "u64_u128"
element_size = 64

encodings = [
  { opcode = "NP 0F DF /r", form = "PANDN mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F DF /r", form = "PANDN xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (r, w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise AND NOT of source operands (NOT first AND second).
"""

handler = "x86_pandn"
jit_lowering = "arm64_pandn"
fallback = "zig_pandn"

neon_register_model = """
PANDN is a bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by PANDN.
"""

neon_assembly = """
// NEON lowering: BIC instruction on ARM64
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
