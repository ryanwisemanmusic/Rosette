// ABORT/XABORT.inc
// ARM64/NEON translation mirror generated from ISA/x86/ABORT/XABORT.inc.
// Source contract: XABORT — Force RTM Abort.

semantic = """
XABORT: preserve the operation and form-specific semantic blocks.
Category: transactional_memory.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ABORT/XABORT.inc"
x86_handler = "x86_xabort"
neon_lowering = "arm64_xabort"
lowering_kind = "arm64_rtm"

name = "XABORT"
aliases = []
category = "transactional_memory"
feature = "rtm"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "C6 F8 ib", form = "XABORT imm8", op_en = "A", feature = "rtm", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["imm8 (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if RTM not enabled",
  "#UD if LOCK prefix"
]

semantic_general = """
Force RTM abort.
"""

handler = "x86_xabort"
jit_lowering = "arm64_xabort"
fallback = "zig_xabort"

neon_register_model = """
x86 GPR mapped to ARM64 xN. XABORT takes a GPR-encoded imm8.
"""

neon_flag_model = """
No x86 flags modified by XABORT.
"""

neon_assembly = """
// NEON lowering: RTM abort via imm8 argument.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
