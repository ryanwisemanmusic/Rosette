// REVERSE/FDIVR.inc
// ARM64/NEON mirror generated from ISA/x86/REVERSE/FDIVR.inc.
// Source contract: FDIVR — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FDIVR.inc"
x86_handler = "x86_fdivr"
neon_lowering = "arm64_fdivr"
lowering_kind = "arm64_documented_contract"

name = "FDIVR"
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
Reverse Divide.
"""

handler = "x86_fdivr"
jit_lowering = "arm64_fdivr"
fallback = "zig_fdivr"

neon_register_model = """
FDIVR is a x87_fpu instruction.
"""

neon_flag_model = """
FDIVR does not modify flags.
"""

neon_assembly = """
// NEON lowering: FDIVR stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

