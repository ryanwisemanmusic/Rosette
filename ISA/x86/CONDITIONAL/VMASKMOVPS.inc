// CONDITIONAL/VMASKMOVPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/VMASKMOVPS.inc.
// Source contract: VMASKMOVPS — Conditionally load/store packed single-precision using mask.

semantic = """
VMASKMOVPS: preserve the operation and form-specific semantic blocks.
Category: avx.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/VMASKMOVPS.inc"
x86_handler = "x86_vmaskmovps"
neon_lowering = "arm64_vmaskmovps"
lowering_kind = "arm64_conditional_move"

name = "VMASKMOVPS"
aliases = []
category = "avx"
feature = "avx"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 2C /r", form = "VMASKMOVPS xmm1, xmm2, m128", op_en = "RVM", feature = "avx", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 2C /r", form = "VMASKMOVPS ymm1, ymm2, m256", op_en = "RVM", feature = "avx", vector_length = 256, encoding = "vex" },
  { opcode = "VEX.128.66.0F38.W0 2E /r", form = "VMASKMOVPS m128, xmm1, xmm2", op_en = "MVR", feature = "avx", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 2E /r", form = "VMASKMOVPS m256, ymm1, ymm2", op_en = "MVR", feature = "avx", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  MVR = ["ModRM:r/m (w)", "ModRM:reg (r)", "VEX.vvvv (r)"]
}

lanes = { xmm = 4, ymm = 8 }
flags_written = []
simd_fp_exceptions = [
  "#SS if non-masked memory reference to non-canonical SS address",
  "#GP if non-masked memory reference to non-canonical address",
  "#PF (fault handling)",
  "#AC if alignment checking enabled and unaligned memory"
]
other_exceptions = [
  "#UD if VEX.W=1",
  "#UD if VEX.vvvv specifies reserved register",
  "#UD if LOCK prefix"
]

semantic_general = """
Conditionally load packed single-precision from memory using mask in xmm2/ymm2.
Zeroing of masked-off elements is implementation-specific.
"""

handler = "x86_vmaskmovps"
jit_lowering = "arm64_vmaskmovps"
fallback = "zig_vmaskmovps"

neon_register_model = """
x86 XMM/YMM mapped to ARM64 Q/V registers. VMASKMOVPS uses predicate-driven load/store.
"""

neon_flag_model = """
No x86 flags modified by VMASKMOVPS.
"""

neon_assembly = """
// NEON lowering: ld1/st1 with predicate register for masked lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
