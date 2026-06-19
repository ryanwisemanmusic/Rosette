// TRIG/FSINCOS.inc
// ARM64/NEON mirror generated from ISA/x86/TRIG/FSINCOS.inc.
// Source contract: FSINCOS — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TRIG/FSINCOS.inc"
x86_handler = "x86_fsincos"
neon_lowering = "arm64_fsincos"
lowering_kind = "arm64_documented_contract"

name = "FSINCOS"
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
Sine and Cosine.
"""

handler = "x86_fsincos"
jit_lowering = "arm64_fsincos"
fallback = "zig_fsincos"

neon_register_model = """
FSINCOS is a x87_fpu instruction.
"""

neon_flag_model = """
FSINCOS does not modify flags.
"""

neon_assembly = """
// NEON lowering: FSINCOS stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

