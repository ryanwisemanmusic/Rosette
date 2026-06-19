// EXTR/EXTRACTPS.inc
// Source contract: EXTRACTPS — sse.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXTR/EXTRACTPS.inc"
x86_handler = "x86_extractps"
neon_lowering = "arm64_extractps"
lowering_kind = "arm64_documented_contract"

name = "EXTRACTPS"
aliases = []
category = "sse"
feature = "sse4_1"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "66 0F 3A 17 /r ib", form = "EXTRACTPS reg/m32, xmm1, imm8", op_en = "A", feature = "sse4_1", vector_length = 128, encoding = "legacy" }
  { opcode = "VEX.128.66.0F3A.WIG 17 /r ib", form = "EXTRACTPS reg/m32, xmm1, imm8", op_en = "A", feature = "sse4_1", vector_length = 128, encoding = "vex" }
  { opcode = "EVEX.128.66.0F3A.WIG 17 /r ib", form = "EXTRACTPS reg/m32, xmm1, imm8", op_en = "B", feature = "sse4_1", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = []
  B = []
}

simd_fp_exceptions = []

semantic_general = """
Extract single precision float from XMM at offset specified by imm8.
"""

handler = "x86_extractps"
jit_lowering = "arm64_extractps"
fallback = "zig_extractps"

neon_register_model = """
EXTRACTPS is an sse instruction.
"""

neon_flag_model = """
EXTRACTPS does not modify flags.
"""

neon_assembly = """
// NEON lowering: EXTRACTPS stub (sse)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
