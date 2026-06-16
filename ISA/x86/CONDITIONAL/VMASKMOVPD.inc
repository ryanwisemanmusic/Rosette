// CONDITIONAL/VMASKMOVPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/VMASKMOVPD.inc.
// Source contract: VMASKMOVPD — Conditionally load/store packed double-precision using mask.

semantic = """
VMASKMOVPD: preserve the operation and form-specific semantic blocks.
Category: avx.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/VMASKMOVPD.inc"
x86_handler = "x86_vmaskmovpd"
neon_lowering = "arm64_vmaskmovpd"
lowering_kind = "arm64_conditional_move"

name = "VMASKMOVPD"
aliases = []
category = "avx"
feature = "avx"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F38.W0 2D /r", form = "VMASKMOVPD xmm1, xmm2, m128", op_en = "RVM", feature = "avx", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 2D /r", form = "VMASKMOVPD ymm1, ymm2, m256", op_en = "RVM", feature = "avx", vector_length = 256, encoding = "vex" },
  { opcode = "VEX.128.66.0F38.W0 2F /r", form = "VMASKMOVPD m128, xmm1, xmm2", op_en = "MVR", feature = "avx", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 2F /r", form = "VMASKMOVPD m256, ymm1, ymm2", op_en = "MVR", feature = "avx", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  MVR = ["ModRM:r/m (w)", "ModRM:reg (r)", "VEX.vvvv (r)"]
}

lanes = { xmm = 2, ymm = 4 }
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
Conditionally load packed double-precision from memory using mask in xmm2/ymm2.
Zeroing of masked-off elements is implementation-specific.
"""

handler = "x86_vmaskmovpd"
jit_lowering = "arm64_vmaskmovpd"
fallback = "zig_vmaskmovpd"

neon_register_model = """
x86 XMM/YMM mapped to ARM64 Q/V registers. VMASKMOVPD uses predicate-driven load/store.
"""

neon_flag_model = """
No x86 flags modified by VMASKMOVPD.
"""

neon_assembly = """
// NEON lowering: ld1/st1 with predicate register for masked lanes.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
