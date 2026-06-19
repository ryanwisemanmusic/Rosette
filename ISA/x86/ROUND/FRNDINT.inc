// ROUND/FRNDINT.inc
// Source contract: FRNDINT — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ROUND/FRNDINT.inc"
x86_handler = "x86_frndint"
neon_lowering = "arm64_frndint"
lowering_kind = "arm64_documented_contract"

name = "FRNDINT"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "D9 FC", form = "FRNDINT ", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Round ST(0) to integer value based on current rounding mode.
"""

handler = "x86_frndint"
jit_lowering = "arm64_frndint"
fallback = "zig_frndint"

neon_register_model = """
FRNDINT is an x87 FPU instruction.
"""

neon_flag_model = """
FRNDINT affects: C1, C0, C2, C3.
"""

neon_assembly = """
// NEON lowering: FRNDINT stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
