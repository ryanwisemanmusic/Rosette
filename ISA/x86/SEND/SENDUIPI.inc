// SEND/SENDUIPI.inc
// Source contract: SENDUIPI — interrupt.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SEND/SENDUIPI.inc"
x86_handler = "x86_senduipi"
neon_lowering = "arm64_senduipi"
lowering_kind = "arm64_documented_contract"

name = "SENDUIPI"
aliases = []
category = "interrupt"
feature = "uintr"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F3 0F C7 /6", form = "SENDUIPI reg", op_en = "A", feature = "uintr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = []
}

simd_fp_exceptions = []

semantic_general = """
Send user interprocessor interrupt (IPI).
"""

handler = "x86_senduipi"
jit_lowering = "arm64_senduipi"
fallback = "zig_senduipi"

neon_register_model = """
SENDUIPI is a system-level instruction.
"""

neon_flag_model = """
SENDUIPI does not modify flags.
"""

neon_assembly = """
// NEON lowering: SENDUIPI stub (interrupt)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
