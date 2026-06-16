// CONDITIONAL/VPMASKMOVD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/VPMASKMOVD.inc.
// Source contract: VPMASKMOVD — Conditionally load/store packed doublewords using mask.

semantic = """
VPMASKMOVD: preserve the operation and form-specific semantic blocks.
Category: avx2.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/VPMASKMOVD.inc"
x86_handler = "x86_vpmaskmovd"
neon_lowering = "arm64_vpmaskmovd"
lowering_kind = "arm64_conditional_move"

name = "VPMASKMOVD"
aliases = []
category = "avx2"
feature = "avx2"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 8C /r", form = "VPMASKMOVD xmm1, xmm2, m128", op_en = "RVM", feature = "avx2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 8C /r", form = "VPMASKMOVD ymm1, ymm2, m256", op_en = "RVM", feature = "avx2", vector_length = 256, encoding = "vex" },
  { opcode = "VEX.128.66.0F38.W0 8E /r", form = "VPMASKMOVD m128, xmm1, xmm2", op_en = "MVR", feature = "avx2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 8E /r", form = "VPMASKMOVD m256, ymm1, ymm2", op_en = "MVR", feature = "avx2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  MVR = ["ModRM:r/m (w)", "ModRM:reg (r)", "VEX.vvvv (r)"]
}

lanes = { xmm = 4, ymm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if VEX.W=1",
  "#UD if VEX.vvvv specifies reserved register",
  "#UD if LOCK prefix"
]

semantic_general = """
Conditionally load packed doublewords from memory using mask in xmm2/ymm2.
Zeroing of masked-off elements is implementation-specific.
"""

handler = "x86_vpmaskmovd"
jit_lowering = "arm64_vpmaskmovd"
fallback = "zig_vpmaskmovd"

neon_register_model = """
x86 XMM/YMM mapped to ARM64 Q/V registers. VPMASKMOVD uses predicate-driven load/store.
"""

neon_flag_model = """
No x86 flags modified by VPMASKMOVD.
"""

neon_assembly = """
// NEON lowering: ld1/st1 with predicate register for masked lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
