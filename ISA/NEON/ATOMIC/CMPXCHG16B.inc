// ATOMIC/CMPXCHG16B.inc
// ARM64/NEON mirror generated from ISA/x86/ATOMIC/CMPXCHG16B.inc.
// Source contract: CMPXCHG16B — atomic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ATOMIC/CMPXCHG16B.inc"
x86_handler = "x86_cmpxchg16b"
neon_lowering = "arm64_cmpxchg16b"
lowering_kind = "arm64_documented_contract"

name = "CMPXCHG16B"
aliases = []
category = "atomic"
feature = "x86"
element_type = "i128"
element_size = 128

encodings = [
  { opcode = "REX.W 0F C7 /1", form = "CMPXCHG16B m128", op_en = "M", feature = "x86", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Compare and Exchange 16 Bytes.
"""

handler = "x86_cmpxchg16b"
jit_lowering = "arm64_cmpxchg16b"
fallback = "zig_cmpxchg16b"

neon_register_model = """
CMPXCHG16B is a atomic instruction.
"""

neon_flag_model = """
CMPXCHG16B does not modify flags.
"""

neon_assembly = """
// NEON lowering: CMPXCHG16B stub (atomic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

