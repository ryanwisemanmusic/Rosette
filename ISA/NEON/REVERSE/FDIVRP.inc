// REVERSE/FDIVRP.inc
// ARM64/NEON mirror generated from ISA/x86/REVERSE/FDIVRP.inc.
// Source contract: FDIVRP — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FDIVRP.inc"
x86_handler = "x86_fdivrp"
neon_lowering = "arm64_fdivrp"
lowering_kind = "arm64_documented_contract"

name = "FDIVRP"
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
Reverse Divide and Pop.
"""

handler = "x86_fdivrp"
jit_lowering = "arm64_fdivrp"
fallback = "zig_fdivrp"

neon_register_model = """
FDIVRP is a x87_fpu instruction.
"""

neon_flag_model = """
FDIVRP does not modify flags.
"""

neon_assembly = """
// NEON lowering: FDIVRP stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

