// WAIT/WAIT.inc
// ARM64/NEON mirror generated from ISA/x86/WAIT/WAIT.inc.
// Source contract: WAIT — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WAIT/WAIT.inc"
x86_handler = "x86_wait"
neon_lowering = "arm64_wait"
lowering_kind = "arm64_documented_contract"

name = "WAIT"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "none"
element_size = 0

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Wait for FPU.
"""

handler = "x86_wait"
jit_lowering = "arm64_wait"
fallback = "zig_wait"

neon_register_model = """
WAIT is a x87_fpu instruction.
"""

neon_flag_model = """
WAIT does not modify flags.
"""

neon_assembly = """
// NEON lowering: WAIT stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

