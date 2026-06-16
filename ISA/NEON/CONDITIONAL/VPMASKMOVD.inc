// NEON/CONDITIONAL/VPMASKMOVD.inc
// ARM64/NEON mirror generated from ISA/x86/CONDITIONAL/VPMASKMOVD.inc.

semantic = """
VPMASKMOVD: preserve the operation and form-specific semantic blocks.
Category: avx2.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/VPMASKMOVD.inc"
x86_handler = "x86_vpmaskmovd"
neon_lowering = "arm64_vpmaskmovd"
lowering_kind = "arm64_simd_mask_load_store"

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
  RVM = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  MVR = ["ModRM:r/m (w)", "VEX.vvvv (r)", "ModRM:reg (r)"]
}

lanes = { xmm = 128, ymm = 256 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if VEX.W = 1",
  "No AC# reported for any mask bit combinations"
]

semantic_general = """
Conditional integer SIMD packed loads and stores using mask.
"""

handler = "x86_vpmaskmovd"
jit_lowering = "arm64_vpmaskmovd"
fallback = "zig_vpmaskmovd"

neon_register_model = """
x86 XMM/YMM mapped to ARM64 Vn registers. Masked integer SIMD load/store using predicate registers.
"""

neon_flag_model = """
No x86 flags modified by VPMASKMOVD.
"""

neon_assembly = """
// NEON lowering: masked integer SIMD load/store
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
