// NOP/FNOP.inc
// ARM64/NEON mirror generated from ISA/x86/NOP/FNOP.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "NOP/FNOP.inc"
x86_handler = "x86_fnop"
neon_lowering = "arm64_fnop"
lowering_kind = "arm64_documented_contract"

name = "FNOP"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "D9 D0", form = "FNOP", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Performs no FPU operation.
"""

handler = "x86_fnop"
jit_lowering = "arm64_fnop"
fallback = "zig_fnop"

neon_register_model = """
FNOP is a x87_fpu no-op. No registers modified.
"""

neon_flag_model = """
No x86 flags modified by FNOP.
"""

neon_assembly = """
// NEON lowering: no-op (FNOP is x87-specific)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
