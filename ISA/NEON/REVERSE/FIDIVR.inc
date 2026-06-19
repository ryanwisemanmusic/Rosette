// REVERSE/FIDIVR.inc
// ARM64/NEON mirror generated from ISA/x86/REVERSE/FIDIVR.inc.
// Source contract: FIDIVR — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FIDIVR.inc"
x86_handler = "x86_fidivr"
neon_lowering = "arm64_fidivr"
lowering_kind = "arm64_documented_contract"

name = "FIDIVR"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Reverse Divide with Integer.
"""

handler = "x86_fidivr"
jit_lowering = "arm64_fidivr"
fallback = "zig_fidivr"

neon_register_model = """
FIDIVR is a x87_fpu instruction.
"""

neon_flag_model = """
FIDIVR does not modify flags.
"""

neon_assembly = """
// NEON lowering: FIDIVR stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

