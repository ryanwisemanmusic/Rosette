// ENQUEUE/ENQCMD.inc
// Source contract: ENQCMD — enqueue.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ENQUEUE/ENQCMD.inc"
x86_handler = "x86_enqcmd"
neon_lowering = "arm64_enqcmd"
lowering_kind = "arm64_documented_contract"

name = "ENQCMD"
aliases = []
category = "enqueue"
feature = "enqcmd"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F2 0F 38 F8 /r", form = "ENQCMD r32/r64, m512", op_en = "A", feature = "enqcmd", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = []
}

flags_affected = ['ZF']

simd_fp_exceptions = []

semantic_general = """
Atomically enqueue 64-byte user command to device enqueue register.
"""

handler = "x86_enqcmd"
jit_lowering = "arm64_enqcmd"
fallback = "zig_enqcmd"

neon_register_model = """
ENQCMD is a enqueue instruction.
"""

neon_flag_model = """
ENQCMD affects: ZF.
"""

neon_assembly = """
// NEON lowering: ENQCMD stub (enqueue)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
