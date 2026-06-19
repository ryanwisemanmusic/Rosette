// TRIG/FSIN.inc
// ARM64/NEON mirror generated from ISA/x86/TRIG/FSIN.inc.
// Source contract: FSIN — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TRIG/FSIN.inc"
x86_handler = "x86_fsin"
neon_lowering = "arm64_fsin"
lowering_kind = "arm64_documented_contract"

name = "FSIN"
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
Sine.
"""

handler = "x86_fsin"
jit_lowering = "arm64_fsin"
fallback = "zig_fsin"

neon_register_model = """
FSIN is a x87_fpu instruction.
"""

neon_flag_model = """
FSIN does not modify flags.
"""

neon_assembly = """
// NEON lowering: FSIN stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

