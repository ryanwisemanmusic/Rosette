// RESET/HRESET.inc
// Source contract: HRESET — system.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESET/HRESET.inc"
x86_handler = "x86_hreset"
neon_lowering = "arm64_hreset"
lowering_kind = "arm64_documented_contract"

name = "HRESET"
aliases = []
category = "system"
feature = "hreset"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F3 0F 3A F0 C0 /ib", form = "HRESET imm8, <EAX>", op_en = "A", feature = "hreset", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = []
}

simd_fp_exceptions = []

semantic_general = """
Processor history reset — selectively reset hardware history components.
"""

handler = "x86_hreset"
jit_lowering = "arm64_hreset"
fallback = "zig_hreset"

neon_register_model = """
HRESET is a system-level instruction.
"""

neon_flag_model = """
HRESET does not modify flags.
"""

neon_assembly = """
// NEON lowering: HRESET stub (system)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
