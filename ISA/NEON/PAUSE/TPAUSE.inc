// PAUSE/TPAUSE.inc
// ARM64/NEON mirror generated from ISA/x86/PAUSE/TPAUSE.inc.
// Source contract: TPAUSE — system.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PAUSE/TPAUSE.inc"
x86_handler = "x86_tpause"
neon_lowering = "arm64_tpause"
lowering_kind = "arm64_documented_contract"

name = "TPAUSE"
aliases = []
category = "system"
feature = "waitpkg"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "66 0F AE /6", form = "TPAUSE r32, <edx>, <eax>", op_en = "A", feature = "waitpkg", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = []
}

flags_affected = ['CF', 'AF', 'PF', 'SF', 'ZF', 'OF']

simd_fp_exceptions = []

semantic_general = """
Timed pause — enter optimized state until TSC reaches EDX:EAX.
"""

handler = "x86_tpause"
jit_lowering = "arm64_tpause"
fallback = "zig_tpause"

neon_register_model = """
TPAUSE is a system-level instruction.
"""

neon_flag_model = """
TPAUSE affects: CF, AF, PF, SF, ZF, OF.
"""

neon_assembly = """
// NEON lowering: TPAUSE stub (system)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
