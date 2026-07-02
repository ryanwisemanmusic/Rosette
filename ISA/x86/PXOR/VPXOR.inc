// PXOR/VPXOR.inc
// VPXOR — Logical Exclusive OR (VEX 128/256-bit).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PXOR/VPXOR.inc"
x86_handler = "x86_vpxor"
neon_lowering = "arm64_vpxor"
lowering_kind = "arm64_documented_contract"

name = "VPXOR"
aliases = []
category = "bitwise_logical"
feature = "AVX"

encodings = [
  { opcode = "VEX.128.66.0F.WIG EF /r", form = "VPXOR xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "VEX" },
  { opcode = "VEX.256.66.0F.WIG EF /r", form = "VPXOR ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "VEX" }
]

operand_encoding = {
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["Non-EVEX: See Table 2-21, Type 4 Class Exception Conditions"]

semantic_general = """
Bitwise XOR of packed integer operands. 128-bit (AVX) and 256-bit (AVX2) VEX forms.
"""

handler = "x86_vpxor"
jit_lowering = "arm64_vpxor"
fallback = "zig_vpxor"

neon_register_model = "VPXOR is an x86 packed integer logical XOR. NEON lowering via bitwise EOR."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPXOR -> EOR (bitwise XOR)"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
