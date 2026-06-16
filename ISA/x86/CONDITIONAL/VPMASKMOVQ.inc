// CONDITIONAL/VPMASKMOVQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/VPMASKMOVQ.inc.
// Source contract: VPMASKMOVQ — Conditionally load/store packed quadwords using mask.

semantic = """
VPMASKMOVQ: preserve the operation and form-specific semantic blocks.
Category: avx2.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/VPMASKMOVQ.inc"
x86_handler = "x86_vpmaskmovq"
neon_lowering = "arm64_vpmaskmovq"
lowering_kind = "arm64_conditional_move"

name = "VPMASKMOVQ"
aliases = []
category = "avx2"
feature = "avx2"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F38.W1 8C /r", form = "VPMASKMOVQ xmm1, xmm2, m128", op_en = "RVM", feature = "avx2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W1 8C /r", form = "VPMASKMOVQ ymm1, ymm2, m256", op_en = "RVM", feature = "avx2", vector_length = 256, encoding = "vex" },
  { opcode = "VEX.128.66.0F38.W1 8E /r", form = "VPMASKMOVQ m128, xmm1, xmm2", op_en = "MVR", feature = "avx2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W1 8E /r", form = "VPMASKMOVQ m256, ymm1, ymm2", op_en = "MVR", feature = "avx2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  MVR = ["ModRM:r/m (w)", "ModRM:reg (r)", "VEX.vvvv (r)"]
}

lanes = { xmm = 2, ymm = 4 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if VEX.W=0",
  "#UD if VEX.vvvv specifies reserved register",
  "#UD if LOCK prefix"
]

semantic_general = """
Conditionally load packed quadwords from memory using mask in xmm2/ymm2.
Zeroing of masked-off elements is implementation-specific.
"""

handler = "x86_vpmaskmovq"
jit_lowering = "arm64_vpmaskmovq"
fallback = "zig_vpmaskmovq"

neon_register_model = """
x86 XMM/YMM mapped to ARM64 Q/V registers. VPMASKMOVQ uses predicate-driven load/store.
"""

neon_flag_model = """
No x86 flags modified by VPMASKMOVQ.
"""

neon_assembly = """
// NEON lowering: ld1/st1 with predicate register for masked lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
