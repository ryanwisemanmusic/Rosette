// BEGIN/XBEGIN.inc
// ARM64/NEON mirror generated from ISA/x86/BEGIN/XBEGIN.inc.

semantic = """
XBEGIN: preserve the operation and form-specific semantic blocks.
Category: transactional_memory.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BEGIN/XBEGIN.inc"
x86_handler = "x86_xbegin"
neon_lowering = "arm64_xbegin"
lowering_kind = "arm64_rtm"

name = "XBEGIN"
aliases = []
category = "transactional_memory"
feature = "rtm"
element_type = "u16_u32"
element_size = 16

encodings = [
  { opcode = "C7 F8", form = "XBEGIN rel16", op_en = "A", feature = "rtm", vector_length = 0, encoding = "legacy" },
  { opcode = "C7 F8", form = "XBEGIN rel32", op_en = "A", feature = "rtm", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["Offset (w)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#GP if fallback address outside CS/non-canonical",
  "#UD if RTM not enabled",
  "#UD if LOCK prefix"
]

semantic_general = """
TEMP := DEST;
Specify start of RTM region with fallback address.
"""

handler = "x86_xbegin"
jit_lowering = "arm64_xbegin"
fallback = "zig_xbegin"

neon_register_model = """
x86 GPR mapped to ARM64 xN. XBEGIN takes a single relative offset operand.
"""

neon_flag_model = """
No x86 flags modified by XBEGIN.
"""

neon_assembly = """
// NEON lowering: RTM begin stub (not supported on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
