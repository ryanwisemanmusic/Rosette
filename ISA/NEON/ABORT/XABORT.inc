// ABORT/XABORT.inc
// ARM64/NEON mirror generated from ISA/x86/ABORT/XABORT.inc.

semantic = """
XABORT: transaction abort. Triggers an RTM abort.
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
  A = ["imm8"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if RTM not supported"
]

semantic_general = """
IF RTM_NOT_SUPPORTED
    THEN #UD;
ELSE
    Perform RTM abort with immediate argument;
FI;
"""

handler = "x86_xabort"
jit_lowering = "arm64_xabort"
fallback = "zig_xabort"

neon_register_model = """
XABORT is a no-op on ARM64 (no RTM). No registers are modified.
"""

neon_flag_model = """
No x86 flags are modified (XABORT does not write flags).
"""

neon_assembly = """
// NEON lowering: RTM abort stub (not supported on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "RTM is an x86-specific feature; ARM64 NEON lowering is a no-op stub."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
