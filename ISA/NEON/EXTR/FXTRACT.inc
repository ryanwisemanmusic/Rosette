// EXTR/FXTRACT.inc
// ARM64/NEON mirror generated from ISA/x86/EXTR/FXTRACT.inc.
// Source contract: FXTRACT — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXTR/FXTRACT.inc"
x86_handler = "x86_fxtract"
neon_lowering = "arm64_fxtract"
lowering_kind = "arm64_documented_contract"

name = "FXTRACT"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "D9 F4", form = "FXTRACT ", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Separate ST(0) into exponent and significand.
"""

handler = "x86_fxtract"
jit_lowering = "arm64_fxtract"
fallback = "zig_fxtract"

neon_register_model = """
FXTRACT is an x87 FPU instruction.
"""

neon_flag_model = """
FXTRACT affects: C1, C0, C2, C3.
"""

neon_assembly = """
// NEON lowering: FXTRACT stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
