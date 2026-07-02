// PXOR/PXOR.inc
// PXOR — Logical Exclusive OR (MMX/SSE2 64/128-bit).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PXOR/PXOR.inc"
x86_handler = "x86_pxor"
neon_lowering = "arm64_pxor"
lowering_kind = "arm64_documented_contract"

name = "PXOR"
aliases = []
category = "bitwise_logical"
feature = "MMX"

encodings = [
  { opcode = "NP 0F EF /r", form = "PXOR mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F EF /r", form = "PXOR xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (r, w)", "ModRM:r/m (r)", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["Non-EVEX: See Table 2-21, Type 4 Class Exception Conditions"]

semantic_general = """
Bitwise XOR of source and destination operands. 64-bit MMX or 128-bit SSE2 forms.
"""

handler = "x86_pxor"
jit_lowering = "arm64_pxor"
fallback = "zig_pxor"

neon_register_model = "PXOR is an x86 packed integer logical XOR. NEON lowering via bitwise EOR."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: PXOR -> EOR (bitwise XOR)"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
