// ATOMIC/CMPXCHG.inc
// ARM64/NEON mirror generated from ISA/x86/ATOMIC/CMPXCHG.inc.
// Source contract: CMPXCHG — atomic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ATOMIC/CMPXCHG.inc"
x86_handler = "x86_cmpxchg"
neon_lowering = "arm64_cmpxchg"
lowering_kind = "arm64_documented_contract"

name = "CMPXCHG"
aliases = []
category = "atomic"
feature = "x86"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "0F B0 /r", form = "CMPXCHG r/m8, r8", op_en = "MR", feature = "NEON", mode = "V/V", handler = "arm64_cmpxchg" }
  { opcode = "0F B1 /r", form = "CMPXCHG r/m16, r16", op_en = "MR", feature = "NEON", mode = "V/V", handler = "arm64_cmpxchg" }
  { opcode = "0F B1 /r", form = "CMPXCHG r/m32, r32", op_en = "MR", feature = "NEON", mode = "V/V", handler = "arm64_cmpxchg" }
  { opcode = "REX.W 0F B1 /r", form = "CMPXCHG r/m64, r64", op_en = "MR", feature = "NEON", mode = "V/V", handler = "arm64_cmpxchg" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Compare and Exchange.
"""

handler = "x86_cmpxchg"
jit_lowering = "arm64_cmpxchg"
fallback = "zig_cmpxchg"

neon_register_model = """
CMPXCHG is a atomic instruction.
"""

neon_flag_model = """
CMPXCHG does not modify flags.
"""

neon_assembly = """
// NEON lowering: CMPXCHG stub (atomic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

