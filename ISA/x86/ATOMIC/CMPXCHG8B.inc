// ATOMIC/CMPXCHG8B.inc
// Source contract: CMPXCHG8B — atomic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ATOMIC/CMPXCHG8B.inc"
x86_handler = "x86_cmpxchg8b"
neon_lowering = "arm64_cmpxchg8b"
lowering_kind = "arm64_documented_contract"

name = "CMPXCHG8B"
aliases = []
category = "atomic"
feature = "x86"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "NP 0F C7 /1", form = "CMPXCHG8B m64", op_en = "M", feature = "x86", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['zf']
simd_fp_exceptions = []

semantic_general = """
Compare and Exchange 8 Bytes.
"""

handler = "x86_cmpxchg8b"
jit_lowering = "arm64_cmpxchg8b"
fallback = "zig_cmpxchg8b"

neon_register_model = """
CMPXCHG8B is a atomic instruction.
"""

neon_flag_model = """
CMPXCHG8B does not modify flags.
"""

neon_assembly = """
// NEON lowering: CMPXCHG8B stub (atomic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

